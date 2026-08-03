---
description: Machine audit for the juel plugin — checks every skill's dependencies against requirements.json and reports present/missing/unverifiable per skill, ending in a runnable/degraded/blocked verdict. The only place in this plugin that runs `claude mcp list`.
allowed-tools: ["Bash", "Read"]
---

# /juel:doctor — machine audit

This is a **command**, not a skill: no preflight block of its own, no phase checklist, no
`<!-- juel:protocol v1 -->`. It answers a different question than every skill's own `## Preflight`
section does.

**Why this exists.** Every skill's preflight is forbidden from running `claude mcp list` —
see `references/preflight.md`. It takes ~4.6s, it reports a *freshly-started process's*
connection state rather than *this session's*, it has no `--json`, and its registered server
names don't map cleanly onto the tool prefixes skills actually call. Preflight therefore always
renders MCP dependencies as `?` — declared, unverified, never blocking — and moves on.

`/juel:doctor` is the deliberate exception. The user invoking it is explicitly asking about their
**machine**, not about the current session, so the 4.6s cost and the fresh-process semantics are
exactly what's being asked for. Nowhere else in this plugin may `claude mcp list` run.

**The most important thing this command outputs is the caveat below — print it first, every
run, unabbreviated:**

> **Connectors bind at session start.** `claude mcp list` describes a freshly-started process,
> not this session. If you enable a connector and this command reports it as connected, the
> *current* session still cannot use it — restart before re-running the skill that needs it.

This is the failure mode that otherwise looks like a broken skill: a user enables a connector,
`/juel:doctor` reports it connected, they immediately re-run the skill that needs it in the
*same* session, and it still fails — not because anything is broken, but because that session's
tool set was fixed at startup.

## Step 1 — Gather machine facts (one batched Bash call)

Run everything below in a single batched call. `claude mcp list` is the slow part (~4.6s) —
that cost is accepted here, once, deliberately.

```bash
# --- requirements.json: the generated rollup, source of truth for hard/soft per skill ---
cat "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/requirements.json"

# --- plugin identity + the version-gated cache fact (Task 23) ---
cat "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
echo "CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}"
# The cache path shape is <config-dir>/plugins/cache/<marketplace>/<plugin>/<version>/ —
# derive marketplace/plugin/version from CLAUDE_PLUGIN_ROOT itself rather than hardcoding
# names, and only trust it if the derived pieces actually look like that layout.
cache_plugin_dir="$(dirname "${CLAUDE_PLUGIN_ROOT}")"     # .../<marketplace>/<plugin>
cache_root="$(dirname "${cache_plugin_dir}")"              # .../<marketplace>
if [ -d "${cache_root}" ]; then
  echo "CACHE_SIBLINGS:"; ls -1 "${cache_root}" 2>/dev/null
fi

# --- cli binaries referenced by requirements.json's cli-kind definitions ---
for b in claude cmux codex gh git; do
  command -v "$b" >/dev/null 2>&1 && echo "CLI_${b}=present:$(command -v "$b")" || echo "CLI_${b}=absent"
done
git --version 2>/dev/null || echo "GIT_VERSION=unknown"
for c in grep sleep tail head cat; do command -v "$c" >/dev/null 2>&1 || echo "COREUTIL_MISSING=$c"; done
gh auth status >/dev/null 2>&1 && echo "GH_AUTH=yes" || echo "GH_AUTH=no-or-absent"

# --- context, relative to the cwd this command was invoked from ---
git rev-parse --show-toplevel 2>/dev/null && echo "GIT_REPO=yes" || echo "GIT_REPO=no"
git status --porcelain 2>/dev/null | head -1 | grep -q . && echo "CLEAN_TREE=no" || echo "CLEAN_TREE=yes-or-na"
git remote get-url origin 2>/dev/null || echo "REMOTE=none"
test -w . && echo "WRITABLE_CWD=yes" || echo "WRITABLE_CWD=no"
[ "$PWD" = "$(git rev-parse --show-toplevel 2>/dev/null)" ] && echo "WORKTREE_ROOT_CWD=yes" || echo "WORKTREE_ROOT_CWD=no-or-na"
command -v gh >/dev/null 2>&1 && gh pr view --json number >/dev/null 2>&1 && echo "OPEN_PR=yes" || echo "OPEN_PR=no-or-na"
command -v cmux >/dev/null 2>&1 && { cmux list-workspaces 2>/dev/null | head -1 | grep -q . && echo "CMUX_SESSION=yes" || echo "CMUX_SESSION=no"; } || echo "CMUX_SESSION=na-no-cmux"

# --- perm: hook config ---
settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
[ -f "$settings" ] && grep -q 'cmux wait-for' "$settings" 2>/dev/null && echo "CMUX_HOOKS=yes" || echo "CMUX_HOOKS=no"

# --- skill-kind deps: juel:* ship in this very bundle; the rest are marketplace plugin deps ---
for s in daily-worktrees regression review-and-execute ship-ticket start; do
  test -f "${CLAUDE_PLUGIN_ROOT}/skills/${s}/SKILL.md" && echo "JUEL_${s}=present" || echo "JUEL_${s}=absent"
done
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
for p in superpowers pr-review-toolkit; do
  found=$(find "${cfg}/plugins/cache/claude-plugins-official" -maxdepth 1 -type d -iname "$p" 2>/dev/null | head -1)
  [ -n "$found" ] && echo "PLUGIN_${p}=present:${found}" || echo "PLUGIN_${p}=absent"
done
find "${cfg}/plugins/cache/claude-plugins-official/superpowers" -maxdepth 3 -type d -iname "brainstorming" 2>/dev/null | head -1

# --- the only `claude mcp list` invocation in this whole plugin ---
time claude mcp list
```

Treat every line as informational text to parse, not as something to trust blindly — a command
that doesn't exist on this machine (`cmux`, `codex`, `gh`) will simply fail its `command -v`
check and print `absent`; that's a valid, expected result, not an error to report.

## Step 2 — Resolve `LINEAR_STATE`

Per `references/work-source.md` §4.1, Linear has **three** states, not two — `working`,
`auth_needed`, and `absent` — and the middle one is the dangerous one: the server is listed, so a
naive presence check reports success while every real call fails. Do not collapse these.

`claude mcp list` names each server explicitly; map its output onto the three states like this
(a line has the shape `<name>: <endpoint> - <glyph> <status text>`):

| Observed in `claude mcp list` output | `LINEAR_STATE` |
|---|---|
| A line starting `claude.ai Linear:` with status `Connected` | `working` (via the claude.ai connector) |
| No `claude.ai Linear:` line, but a `plugin:linear:linear:` (or `plugin:linear:`) line with status `Connected` | `working` (via the plugin connector) |
| No `claude.ai Linear:` line, and `plugin:linear:linear:` shows `Needs authentication` | `auth_needed` — **the plugin dependency is installed, not authorized.** This is never reported as "Linear is missing" |
| Neither line appears at all | `absent` |
| `plugin:linear:linear:` shows some other status (a connection error, not an auth prompt) | unverifiable — report the raw status text verbatim rather than forcing it into one of the three buckets |

This machine's live `claude mcp list` observed today: `plugin:linear:linear` present with
`Needs authentication`, and no `claude.ai Linear` line — i.e. `auth_needed`, via the plugin
connector, not the claude.ai connector. **Do not assume which connector is live; always resolve
`LINEAR_STATE` from this run's actual output**, because which connector is authenticated (if
either) can change between runs as the user enables or disables things.

Print the exact message keyed by `LINEAR_STATE` (from work-source.md §5 — never substitute a
generic line for `auth_needed`, and never claim `working` from a `claude mcp list` "Connected"
without repeating the session-binding caveat next to it):

| `LINEAR_STATE` | Message |
|---|---|
| `working` | present — but repeat: this describes the fresh process this command just started, not necessarily your current session |
| `auth_needed` | `Linear plugin is installed but not authorized. Run the plugin's authenticate tool, then restart the session so its tools bind.` |
| `absent` | `Linear MCP unavailable.` |

Resolve `playwright` the same way against its own `plugin:playwright:playwright:` line, but it
only has two meaningful states here (present / not) — report `Connected` as present, no line at
all as missing, and anything else as unverifiable with the raw status text (Playwright has no
OAuth step, so an unexpected status is worth surfacing honestly rather than guessing what it
means).

## Step 3 — Classify every dependency id

For each `id` referenced by any skill in `requirements.json`, classify it `present` / `missing` /
`unverifiable` using the table below. **If `requirements.json` ever contains an id not in this
table** (this file can drift from a newer rollup) — classify it `unverifiable`, reason
"unrecognized dependency id, doctor has no check defined for it yet." Never guess.

| id | kind | Present when | Missing when | Always unverifiable? |
|---|---|---|---|---|
| `claude` | cli | `command -v claude`, or one of the declared `paths` is executable | neither resolves | |
| `cmux` | cli | `command -v cmux`, or a declared `paths` entry | neither resolves | |
| `codex` | cli | `command -v codex` | absent | |
| `coreutils` | cli | none of `grep`/`sleep`/`tail`/`head`/`cat` missing | any missing (rare) | |
| `gh` | cli | `command -v gh` | absent | note `GH_AUTH` alongside — some skills additionally need `gh auth status` to succeed; report that as a bonus fact, not a separate id |
| `git` | cli | `command -v git`; note the version string | absent | |
| `resolved-install-command` | cli | — | — | yes — resolved per-repo at run time from the repo's own install layer; doctor has no fixed target to check |
| `app-url` | context | — | — | yes — depends on which app/port the invoking task is running; doctor doesn't know the target |
| `clean-tree` | context | in a repo, `git status --porcelain` empty | in a repo, dirty | only when not in a git repo (report `not applicable — no git repo at cwd`) |
| `cmux-session` | context | `cmux` present and `cmux list-workspaces` non-empty | `cmux` present but zero workspaces | when `cmux` itself is absent (report `not applicable — no cmux binary`) |
| `git-repo` | context | `git rev-parse --show-toplevel` succeeds at cwd | it fails | |
| `github-remote` | context | a remote URL resolves and contains `github.com` | it resolves to something else, or no remote | when there's no git repo at all |
| `interactive-user` | context | always — `/juel:doctor` itself only runs inside an interactive session | — | |
| `open-pr` | context | `gh` present, in a repo, `gh pr view --json number` succeeds | `gh` present but it fails | when `gh` itself is absent |
| `plan-file` | context | — | — | yes — depends on which ticket/plan is in scope; doctor doesn't know the target |
| `verification-criteria` | context | — | — | yes — same reason as `plan-file` |
| `work-source-list-capable` | context | tied to `LINEAR_STATE`: `working` → present | `LINEAR_STATE` is `auth_needed` or `absent` → missing (soft-degradable: paste refs, or point at a spec directory) | |
| `worktree-root-cwd` | context | cwd equals `git rev-parse --show-toplevel` | it's a subdirectory of the repo | when there's no git repo at all |
| `writable-cwd` | context | `test -w .` | it fails | |
| `cmux-notification-hooks` | perm | `settings.json` contains a `cmux wait-for` hook | it doesn't | |
| `permission-mode-auto` | perm | — | — | yes — depends on the flag this *session* was launched with; no reliable check from inside a running command |
| `linear` | mcp | `LINEAR_STATE == working` | `LINEAR_STATE` is `auth_needed` or `absent` (see Step 2 — these render with different messages, never the same one) | |
| `playwright` | mcp | `plugin:playwright:playwright` shows `Connected` | no such line | when the line exists but shows an unexpected status — report the raw text |
| `juel:daily-worktrees`, `juel:regression`, `juel:review-and-execute`, `juel:ship-ticket`, `juel:start` | skill | `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md` exists | it doesn't (a corrupted or partial install) | |
| `pr-review-toolkit`, `superpowers` | skill | a matching directory exists under `<config-dir>/plugins/cache/claude-plugins-official/` | it doesn't | |
| `superpowers:brainstorming` | skill | the `superpowers` plugin cache dir exists **and** contains a `skills/brainstorming/SKILL.md` | the plugin dir is missing, or it's present without that skill | |
| `run` | skill | — | — | yes, always — a harness built-in this plugin cannot install or query. Report plainly: "cannot determine; assume present unless a skill actually fails to invoke it" |
| `simplify` | skill | — | — | yes, always — same reasoning as `run`; both are declared SOFT everywhere they're used precisely because they can't be guaranteed |

## Step 4 — Per-skill verdict

For each skill in `requirements.json`'s `skills` map, join its `hard`/`soft` id lists against the
Step 3 classification and compute:

- **`BLOCKED`** — at least one `hard` id is verified `missing` (this includes `linear` in
  `auth_needed` or `absent` when it's listed `hard`, and `playwright`/other mcp misses).
- **`DEGRADED`** — not blocked, but at least one id (`hard` or `soft`) is `unverifiable`, or at
  least one `soft` id is `missing`.
- **`RUNNABLE`** — every `hard` id is `present`, and every `soft` id is `present` or simply not
  declared.

This mirrors `references/preflight.md`'s own STOP / DEGRADE / PROCEED verdict exactly — `BLOCKED`
↔ `STOP`, `DEGRADED` ↔ `DEGRADE`, `RUNNABLE` ↔ `PROCEED` — because a machine that can't run a
skill's hard requirement is in exactly the state that would make that skill's own preflight stop.

## Step 5 — Render the report

```
juel:doctor — machine audit
`claude mcp list` took ~<N>s against a freshly-started process.

CAVEAT — READ THIS FIRST
<the session-binding caveat, verbatim, from the top of this file>

## Plugin install
juel <installed-version> — running from <CLAUDE_PLUGIN_ROOT>
[only if the cache layout resolved and sibling version dirs exist:]
Cache holds: <version-a>, <version-b>, ...
[only if a sibling dir's version sorts higher than the installed one:]
⚠ A newer version exists in the plugin cache than the one this session loaded. The cache is
  version-gated, not commit-gated — pushing commits without bumping plugin.json's version leaves
  `claude plugin marketplace update` serving the stale one until you uninstall and reinstall.

## MCP servers (from this run's `claude mcp list`)
linear:     <working|auth_needed|absent> — <the Step 2 message>
playwright: <present|missing|unverifiable> — <raw status text if unverifiable>

## Per-skill audit

### <skill> — <RUNNABLE|DEGRADED|BLOCKED>
  ✓ present (<n>): <comma-separated labels, satisfied deps are never itemized beyond this line>
  ✗ missing (hard): <label> — <the specific message: requirements.json's install hint, or the
                                 Linear auth_needed/absent message, never a generic fallback>
  ! missing (soft): <label> — <install hint / fallback>
  ? unverifiable (hard): <label> — <reason, exactly as given in Step 3's table>
  ? unverifiable (soft): <label> — <reason>
→ <one-line consequence — what specifically breaks or degrades, and the fix>

[repeat for every skill in requirements.json, in the order they appear there]
```

Three worked shapes, so the verdict lines are never generic:

- **RUNNABLE**: `### compact-context — RUNNABLE` / `✓ present (2): git, git-repo` / `→ all
  requirements met.`
- **DEGRADED**: `### start — DEGRADED` / `✓ present (2): git-repo, superpowers:brainstorming` /
  `! missing (soft): linear (auth_needed) — Linear plugin is installed but not authorized. Run
  the plugin's authenticate tool, then restart the session so its tools bind.` / `→ proceeds
  without Linear; resolve the work item from a spec file or inline conversation instead.`
- **BLOCKED**: `### cmux-babysit — BLOCKED` / `✗ missing (hard): cmux — https://github.com/manaflow-ai/cmux`
  / `→ nothing to babysit without the cmux binary; install it and re-run.`

## What this command deliberately does not do

- It does not modify anything — no installs, no config writes, no auth flows triggered on the
  user's behalf.
- It does not replace a skill's own preflight — preflight still runs on every invocation of every
  skill, still renders MCP deps as `?`, and still never calls `claude mcp list`. This command is
  an on-demand, opt-in, slower, machine-wide complement to that — not a substitute for it.
- It does not claim certainty it doesn't have. Every row in Step 3 that can't be determined says
  so in plain language instead of being silently rendered as `✓` or folded into a generic `✗`.
