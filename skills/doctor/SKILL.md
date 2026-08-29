---
name: doctor
description: Machine audit for the juel plugin — checks every skill's dependencies against requirements.json and reports present/missing/unverifiable per skill, ending in a runnable/degraded/blocked verdict. The only place in this plugin that runs `claude mcp list`. Triggers "doctor", "audit the plugin", "/juel:doctor".
metadata:
  requires:
    cli:
      - id: coreutils
        hard: true
        why: phase 1 batches command -v, grep, find and ls to gather every machine fact this audit reports
        check: "command -v grep"
      - id: claude
        hard: false
        why: phase 1 runs `claude mcp list` - the only invocation of it anywhere in this plugin
        check: "command -v claude"
        fallback: under Codex the Claude CLI is absent or describes a different agent; skip that call and render every MCP dependency as `?`
    context:
      - id: git-repo
        hard: false
        why: phase 1 records repo context (toplevel, clean tree, remote) for the context-kind dependency rows
        check: "git rev-parse --show-toplevel"
        fallback: context-kind rows render `n/a` outside a repository
---

# juel:doctor — machine audit

## Overview

This audit answers a different question than every skill's own `## Preflight` section does.
Preflight asks "can THIS skill run in THIS session?"; doctor asks "what does THIS MACHINE have
installed?" It changes nothing and is safe to run any time.

**Why `claude mcp list` lives here and nowhere else.** Every skill's preflight is forbidden from
running it - see `references/preflight.md`. It takes ~4.6s, it reports a *freshly-started
process's* connection state rather than *this session's*, it has no `--json`, and its registered
server names don't map cleanly onto the tool prefixes skills actually call. Preflight therefore
always renders MCP dependencies as `?` - declared, unverified, never blocking - and moves on.
This skill is the deliberate exception: the user invoking it is explicitly asking about their
**machine**, not their session, so the cost and the fresh-process semantics are exactly what is
being asked for.

**Announce:** "Using juel:doctor to audit this machine."

**The most important thing this skill outputs is the caveat below - print it first, every run,
unabbreviated:**

> **Connectors bind at session start.** `claude mcp list` describes a freshly-started process,
> not this session. If you enable a connector and this command reports it as connected, the
> *current* session still cannot use it — restart before re-running the skill that needs it.

This is the failure mode that otherwise looks like a broken skill: a user enables a connector,
doctor reports it connected, they immediately re-run the skill that needs it in the *same*
session, and it still fails - not because anything is broken, but because that session's tool
set was fixed at startup.

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v7 -->

**0. Harness check, before every other rule.** If you do not have the `TaskCreate` tool, you are not running in Claude Code. Read `references/harness-codex.md`, resolved relative to this skill file's own location (`../../references/harness-codex.md`), and apply its construct map, corrected facts, dependency substitutions and degradation contract to every rule below and to every phase body in this skill. This single read is the one action permitted before rule 1's preflight, and only in that case. If you do have `TaskCreate`, ignore that file entirely and continue to rule 1.

**1. Preflight, then task list, before anything else.** Before any other output and before any tool call, emit the Preflight block (below). If the preflight verdict is STOP, print the preflight block and **stop** — do not create tasks and do not begin work. Otherwise, before any other work, create one task per phase in this skill's `## Phases` list via `TaskCreate` — `subject` is the phase name, `activeForm` is its present-continuous form. This task list, rendered persistently by the harness, IS the checklist; nothing else satisfies this rule. This is not optional on re-invocation, on resume, or when the user says "just do it".
- **If `TaskCreate`/`TaskUpdate` genuinely fail** — one attempted call returns an error, never merely assumed unavailable in advance — fall back to an explicit numbered phase log, printed after every phase transition with the same one-line evidence rule 3 already requires. State the degradation once, in one line, before continuing. Never silently swap to prose without saying so.

**2. Phases run in order.** No skipping, reordering, or merging. A phase that does not apply is still announced, not dropped: mark its task `completed` via `TaskUpdate`, with the one-line evidence required by rule 3 stating the skip reason (e.g. "SKIPPED: <reason>") — the task list has no separate "skipped" status, so a skipped phase becomes `completed` too. Never begin phase N+1 before phase N's task is marked `completed`.

**3. Report after every phase.** Mark the phase's task `in_progress` via `TaskUpdate` when starting it, then `completed` via `TaskUpdate` when it finishes or is skipped — each transition accompanied by exactly one line of evidence (path written, command run, count found). Do not re-print the checklist as text; the task list is the persistent record and replaces that. Never claim progress in prose alone.

**4. `review-pr`'s agents run in PARALLEL and FOREGROUND; `code-simplifier` runs FOREGROUND; `codex exec` runs BACKGROUND, WATCHED, and WAITED-ON.** This overrides every other instruction in this file and in any skill invoked from it. Foreground/background is about whether the tool call blocks; watched is about whether output still streams somewhere the user can see it — these are different axes, and `codex exec` needs the second without the first. `review-pr`'s agents additionally need PARALLEL: dispatched together, not one at a time.
- `pr-review-toolkit:review-pr`'s agents MUST be dispatched in parallel: pass `all parallel`, or dispatch the agents together in ONE message. Its sequential default — one agent at a time — is the exact slowness this rule exists to prevent; requesting it, or omitting `all parallel`, is a violation.
- `pr-review-toolkit:review-pr` and `code-simplifier` are foreground-only. Invoke both with `run_in_background: false` **explicitly** — the harness backgrounds subagents by default, so omitting the flag is a violation, not a neutral choice. Dispatching review-pr's agents in parallel does not relax this: each agent in that one message still carries its own explicit `run_in_background: false`. Never `&`. Never `run_in_background: true` for these two. Never "dispatch and continue".
- `codex exec` runs through the **Bash tool**, whose `timeout` parameter is capped at 600000ms (10 minutes). A real `codex exec` applying a plan routinely runs longer than that, so a foreground dispatch gets silently DETACHED by the harness at the cap regardless of this rule — nothing then watches it, nothing reads its output, and the skill would wrongly proceed as if the phase had ended. `review-pr` and `code-simplifier` run through the **Skill/Agent tool**, which carries no such cap — that is the entire reason only `codex exec` changes. Do not "fix" this back to foreground; the cap is a harness fact, not a preference.
- **Always dispatch `codex exec` with `run_in_background: true`** — not optional, not "if it looks long," always. Omitting the flag, or passing `false`, is a violation.
- **Never redirect a command's output to a log file.** No `> out.log`, no `| tee`, no writing output somewhere to read back later. This applies to all three, and is now MORE load-bearing for `codex exec`: backgrounded with no ceiling, the shell is the only place the user watches it work.
- For `review-pr` and `code-simplifier`: read the complete output and state the outcome — finding count, exit status, files changed — before marking the phase done. A summary may follow the raw output; it may never replace it.
- For `codex exec`: wait for it to exit before marking the phase done — backgrounding must never become fire-and-forget. Then state the outcome — exit status, files changed — not a transcript; the user already watched it stream in the shell, so its full output is never printed back into the conversation.
- **Never attach a `Monitor` or a polling loop to `codex exec`.** No `Monitor` armed on its output, no repeated reads of the `.output` file, no `tail -f`. Dispatch it backgrounded and wait for the completion notification — the user already watches it stream in their own shell, which is exactly why output must never be redirected; a watcher on top adds nothing, and a filter with no pattern for `Reading additional input from stdin...` will misread a stalled executor as healthy.
- Passing any of this into another session (a CMUX prompt, a nested `claude`) carries these rules with it — say so explicitly in that prompt string.

**5. Confirmation gates stack; they do not replace this.** Where this skill pauses between phases, the checklist report comes first, then the "Proceed to phase N+1?" question. A user's "yes" advances exactly one phase — it never authorizes skipping ahead or batching the remainder.

**6. `Idling` is a status, not a verdict — never read it as "returned nothing."** When a dispatched `pr-review-toolkit:review-pr` agent or `code-simplifier` shows `Idling` (or any non-streaming status) in the harness's agent view while its call is still in flight, that status alone never means the agent produced no output — `Idling` covers both "still working" and "finished, with a result already available but not yet consumed by this session" indistinguishably. Multi-agent dispatch is exactly where this bites: `pr-review-toolkit:review-pr`'s specialist agents run "all parallel" (rule 4), so several can sit at `Idling` simultaneously while one has already returned and the others haven't.
- **Before concluding a dispatch returned nothing, or re-dispatching it, check `ListAgents` for the agent by name.** If it's listed with a result available, read that result directly — do not wait further and do not re-dispatch a duplicate call.
- **Never re-dispatch `pr-review-toolkit:review-pr` or `code-simplifier` "to unstick it"** without first confirming via `ListAgents` that the original dispatch genuinely produced nothing — re-dispatching a call whose result already exists wastes a full review cycle and risks duplicate, conflicting findings.
- **Never go quiet past a check-in point with no status update.** If a dispatch has been running long enough that you would normally report progress, either report genuine progress or check `ListAgents` first — silently waiting while a subagent is actually done is the exact failure this rule exists to prevent.

This skill has no `codex exec`, `pr-review-toolkit:review-pr`, or `code-simplifier` dispatch sites
of its own — rule 4 and rule 6's agent-dispatch clauses carry no live obligation here, kept
verbatim only because the block is copied byte-for-byte across every skill (see
`references/strict-protocol.md`).

## Preflight

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| coreutils | cli | HARD | `command -v grep` | STOP → this audit is entirely shell-based |
| Claude Code CLI | cli | SOFT | `command -v claude` | under Codex the Claude CLI is absent or describes a different agent; skip that call and render every MCP dependency as `?` |
| git repository | context | SOFT | `git rev-parse --show-toplevel` | context-kind rows render `n/a` outside a repository |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Gather machine facts
2. Resolve LINEAR_STATE
3. Classify every dependency id
4. Decide a per-skill verdict
5. Render the report

## Resolving `PLUGIN_ROOT`

Every path below is written against `${PLUGIN_ROOT}`. Resolve it once, first:

```bash
# In Claude Code, CLAUDE_PLUGIN_ROOT is set. In Codex it is EMPTY for skill bodies -
# verified, not assumed: a probe skill echoing it returned `CPR=[] PR=[] PD=[]`.
# When it is empty, substitute the literal absolute path of this plugin's root, which is
# this SKILL.md's own location with /skills/doctor removed. Both harnesses tell you that
# path: Claude Code via the variable, Codex via the skill catalog's `(file: ...)` locator.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<substitute this SKILL.md's plugin root>"
echo "PLUGIN_ROOT=${PLUGIN_ROOT}"
```

## Phase 1 — Gather machine facts (one batched Bash call)

Run everything below in a single batched call. `claude mcp list` is the slow part (~4.6s) —
that cost is accepted here, once, deliberately.

```bash
# --- requirements.json: the generated rollup, source of truth for hard/soft per skill ---
cat "${PLUGIN_ROOT}/.claude-plugin/requirements.json"

# --- authoritative counts: phase 5 QUOTES these, it never re-tallies by hand ---
# A live run of this audit reported "27 dependency ids" and "15 skills" when the true
# figures were 34 and 14, and its own subtotals (18+5+8=31) did not even sum to the total
# it printed. Hand-counting across a long classification pass is not reliable; derive it.
if command -v node >/dev/null 2>&1; then
  node -e 'const r=require(process.argv[1]);const ids=new Set();for(const s of Object.values(r.skills)){(s.hard||[]).forEach(i=>ids.add(i));(s.soft||[]).forEach(i=>ids.add(i));}console.log("SKILL_COUNT="+Object.keys(r.skills).length);console.log("DEP_ID_COUNT="+ids.size);' "${PLUGIN_ROOT}/.claude-plugin/requirements.json"
else
  echo "SKILL_COUNT=$(ls -1d "${PLUGIN_ROOT}"/skills/*/ 2>/dev/null | wc -l | tr -d ' ')"
  echo "DEP_ID_COUNT=unavailable"
fi

# --- plugin identity + the version-gated cache fact (Task 23) ---
cat "${PLUGIN_ROOT}/.claude-plugin/plugin.json"
echo "PLUGIN_ROOT=${PLUGIN_ROOT}"
# The cache path shape is <config-dir>/plugins/cache/<marketplace>/<plugin>/<version>/ —
# PLUGIN_ROOT IS the <version> directory, so its parent is where sibling VERSION
# directories live (not its grandparent, which is one level too high and only lists plugin
# NAMES under that marketplace — a wrong-level bug that fails silently, since `ls` still
# succeeds there). Derive from PLUGIN_ROOT itself rather than hardcoding names, and
# only trust it if the directory actually exists on this machine.
cache_plugin_dir="$(dirname "${PLUGIN_ROOT}")"     # .../<marketplace>/<plugin> — version siblings live HERE
if [ -d "${cache_plugin_dir}" ]; then
  echo "CACHE_SIBLINGS:"; ls -1 "${cache_plugin_dir}" 2>/dev/null
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
for s in daily-worktrees review-and-execute ship-ticket start; do
  test -f "${PLUGIN_ROOT}/skills/${s}/SKILL.md" && echo "JUEL_${s}=present" || echo "JUEL_${s}=absent"
done
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
for p in superpowers pr-review-toolkit code-simplifier; do
  found=$(find "${cfg}/plugins/cache/claude-plugins-official" -maxdepth 1 -type d -iname "$p" 2>/dev/null | head -1)
  [ -n "$found" ] && echo "PLUGIN_${p}=present:${found}" || echo "PLUGIN_${p}=absent"
done
find "${cfg}/plugins/cache/claude-plugins-official/superpowers" -maxdepth 3 -type d -iname "brainstorming" 2>/dev/null | head -1

# --- the only `claude mcp list` invocation in this whole plugin ---
time claude mcp list
```

### Under Codex (rule 0 applies)

Do **not** run `claude mcp list` here. It is the Claude Code CLI: it describes a Claude session,
not this one, and on a machine with both agents it will confidently report a tool set this session
does not have. Run this instead:

```bash
# Codex's own view of registered MCP servers. Plugin-bundled servers appear here WITHOUT any
# entry in config.toml - verified: a plugin declaring mcpServers registered and enabled its
# server while `grep` found nothing in config.toml. Absence from config.toml is not absence.
codex mcp list

# the shared agents skill root the Codex path depends on (scripts/link-agent-skills.mjs)
for s in brainstorming writing-plans receiving-code-review; do
  if [ -L "$HOME/.agents/skills/$s" ] && [ -f "$HOME/.agents/skills/$s/SKILL.md" ]; then
    echo "AGENTSKILL_$s=ok"
  elif [ -L "$HOME/.agents/skills/$s" ]; then
    echo "AGENTSKILL_$s=broken -> $(readlink "$HOME/.agents/skills/$s")"
  else
    echo "AGENTSKILL_$s=absent"
  fi
done

# the vendored Codex skill four juel skills dispatch as $claude-plan-executor
if [ -L "$HOME/.codex/skills/claude-plan-executor" ] && [ -f "$HOME/.codex/skills/claude-plan-executor/SKILL.md" ]; then
  echo "CODEXSKILL_claude-plan-executor=ok"
elif [ -e "$HOME/.codex/skills/claude-plan-executor" ]; then
  echo "CODEXSKILL_claude-plan-executor=unmanaged (not the vendored symlink)"
else
  echo "CODEXSKILL_claude-plan-executor=absent"
fi

# Codex's installed plugin cache - the analogue of Claude's version-gated cache
ls -1 "$HOME"/.codex/plugins/cache/*/juel 2>/dev/null || echo "juel not installed in Codex"
```

Report `broken` or `absent` for any of the three as a **HARD** failure with the remedy
`node scripts/link-agent-skills.mjs`. `juel:start`, `juel:review-pr`, `juel:review-and-execute`,
`juel:receive-review-and-execute` and `juel:ship-ticket` all hard-depend on them, and the failure
is silent until a skill actually reaches for one.

The link targets are version-pinned into the superpowers plugin cache, so they go stale on every
superpowers update. A `broken` result usually means "superpowers updated", not "something is
wrong" - the remedy is the same either way.

Report `absent` for `CODEXSKILL_claude-plan-executor` as a **HARD** failure for
`juel:execute`, `juel:review-and-execute`, `juel:receive-review-and-execute` and
`juel:ship-ticket`, with the remedy `node scripts/link-agent-skills.mjs`. Report `unmanaged` as
DEGRADED, not a failure: a personal copy still works, it just is not the version this plugin
ships, so its contract may differ.

**Also report whether a sandboxed Codex executor can commit here.** `.git` is a protected path
under `workspace-write`, so a commit only succeeds if the escalation is approved, and who approves
is config, not repo. Read it directly:

```bash
grep -E '^approvals_reviewer' "${CODEX_HOME:-$HOME/.codex}/config.toml" \
  || echo 'approvals_reviewer = "user"   # unset, so the default applies'
```

- `user` (the default) → an interactive session prompts and commits succeed, but a
  **non-interactive `codex exec` has nobody to ask and every commit phase fails**. Report this as a
  DEGRADED condition for `juel:execute` and `juel:review-and-execute`, with the remedy: pass
  `--approve-for-me` for that run, or run the executor author-only and commit outside the sandbox.
- `auto_review` or `guardian_subagent` → escalations are auto-approved and commits work in both
  modes. Report as present.

Do **not** try to infer this from `codex debug prompt-input`. The permission profile is
byte-identical whether commits succeed or fail, so it is not a signal.

Treat every line as informational text to parse, not as something to trust blindly — a command
that doesn't exist on this machine (`cmux`, `codex`, `gh`) will simply fail its `command -v`
check and print `absent`; that's a valid, expected result, not an error to report.

## Phase 2 — Resolve `LINEAR_STATE`

Per `references/work-source.md` §4.1, Linear has **three** states, not two — `working`,
`auth_needed`, and `absent` — and the middle one is the dangerous one: the server is listed, so a
naive presence check reports success while every real call fails. Do not collapse these.

`claude mcp list` names each server explicitly; map its output onto the three states like this
(a line has the shape `<name>: <endpoint> - <glyph> <status text>`):

Check rows in order — the first one that matches wins:

| Observed in `claude mcp list` output | `LINEAR_STATE` |
|---|---|
| A line starting `claude.ai Linear:` with status `Connected` | `working` (via the claude.ai connector) |
| A line starting `claude.ai Linear:` with any status other than `Connected` | unverifiable — report the raw status text verbatim. `claude.ai`-hosted connectors on this machine (Gmail, Google Calendar) demonstrably have their own auth-needed state, so a `claude.ai Linear:` line is not guaranteed to be binary either; don't force it into `working`/`auth_needed`/`absent` on a guess — the same discipline row 6 already applies to the plugin connector |
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

## Phase 3 — Classify every dependency id

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
| `juel:daily-worktrees`, `juel:review-and-execute`, `juel:ship-ticket`, `juel:start` | skill | `${PLUGIN_ROOT}/skills/<name>/SKILL.md` exists | it doesn't (a corrupted or partial install) | |
| `pr-review-toolkit`, `superpowers`, `code-simplifier` | skill | a matching directory exists under `<config-dir>/plugins/cache/claude-plugins-official/` | it doesn't | |
| `claude-plan-executor` | skill | `~/.codex/skills/claude-plan-executor/SKILL.md` resolves | it does not | when running under Claude Code — the Claude path still dispatches `codex exec`, so it is required there too; report it in both harnesses |
| `superpowers:brainstorming` | skill | the `superpowers` plugin cache dir exists **and** contains a `skills/brainstorming/SKILL.md` | the plugin dir is missing, or it's present without that skill | |
| `run`, `verify` | skill | — | — | yes, always — harness built-ins this plugin cannot install or query. Report plainly: "cannot determine; assume present unless a skill actually fails to invoke it" |

## Phase 4 — Per-skill verdict

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

## Phase 5 — Render the report

**Counts come from phase 1, verbatim.** Print `SKILL_COUNT` and `DEP_ID_COUNT` as gathered, never
a number you arrived at by counting rows yourself. Before printing, check that your
present + missing + unverifiable subtotals sum exactly to `DEP_ID_COUNT`. If they do not, print
the discrepancy as a line of its own — `COUNT MISMATCH: <p>+<m>+<u>=<sum>, expected <DEP_ID_COUNT>`
— rather than silently adjusting a number to make the total look right. If `DEP_ID_COUNT` came
back `unavailable`, say so instead of substituting a hand count.

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
