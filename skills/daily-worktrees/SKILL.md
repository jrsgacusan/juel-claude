---
name: daily-worktrees
description: Use when starting your workday and need to see work items assigned to you (Linear, Jira, GitHub Issues, or a spec directory), or when setting up worktrees for multiple items in parallel
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: phase 2 fetches open todo work items assigned to the user, when Linear resolves as the provider
        check: none
        fallback: falls back to the next available provider
    cli:
      - id: git
        hard: true
        why: worktree creation in phase 7 requires git >= 2.5
        check: "git --version"
      - id: resolved-install-command
        hard: false
        why: phase 7 runs the resolved install command inside each new worktree instead of copying venv
        check: "see resolution layer"
        fallback: skip this step; install deps yourself
    context:
      - id: git-repo
        hard: true
        why: worktrees are created under the main checkout's .worktrees (see the three-root discipline in Step 7), never nested inside another worktree
        check: "git rev-parse --show-toplevel"
      - id: interactive-user
        hard: true
        why: phase 5 lets the user select which tickets to set up via AskUserQuestion
      - id: work-source-list-capable
        hard: true
        why: phase 2 needs a work source that can list items, or the user pastes refs / points at a spec directory
---

# Daily Worktrees

## Overview

Fetch open work items from the resolved work source and create git worktrees for parallel development.

**Announce:** "Using this skill to fetch your open work items and set up worktrees."

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v4 -->

**1. Preflight, then task list, before anything else.** Before any other output and before any tool call, emit the Preflight block (below). If the preflight verdict is STOP, print the preflight block and **stop** — do not create tasks and do not begin work. Otherwise, before any other work, create one task per phase in this skill's `## Phases` list via `TaskCreate` — `subject` is the phase name, `activeForm` is its present-continuous form. This task list, rendered persistently by the harness, IS the checklist; nothing else satisfies this rule. This is not optional on re-invocation, on resume, or when the user says "just do it".

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

## Preflight

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| git ≥ 2.5 | cli | HARD | `git --version` | STOP → worktree support required |
| resolved install command | cli | SOFT | see resolution layer | skip this step; install deps yourself |
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP |
| AskUserQuestion | context | HARD | always available interactively | STOP → selection is interactive |
| work source with `list` | context | HARD | provider capability | STOP → paste refs, or point at a spec directory |
| Linear MCP | mcp | SOFT | **none — render as `?`** | falls back to the next available provider |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Detect the project
2. Fetch open work items from the resolved source
3. Generate branch and worktree names
4. Check for existing branches and worktrees
5. Present for confirmation and let the user select
6. Handle existing work — reuse or start fresh
7. Create worktrees, copy untracked files, set status to in_progress
8. Report and offer planning (SKIPPED if declined)
9. Final report

## Prerequisites

- A work source resolved with `list` capability (a Linear/Jira project, a GitHub repo, or a spec
  directory) — see "Configuration" below; a provider without `list` falls back to the edge case in
  Step 2
- Inside a git repository
- Git worktrees supported (git 2.5+)

## Workflow

### Step 1: Resolve the Provider and Project/Repo Scope

Resolve the work-source provider first (`config.tracker.type`, or capability auto-detect — see
`references/resolution.md` §2's absent-config table, `tracker.type` row).

**Project/scope resolution is provider-specific — there is no single "project" concept that
applies to every provider:**

- **`linear` / `jira`:** prefer `config.tracker.project` if it is set. Otherwise:
  ```bash
  project_name=$(basename "$(git rev-parse --show-toplevel)")
  ```
  Search the provider's projects for a match against `project_name`. If no confident match, list
  available projects and ask the user to select.
- **`github`:** **no project step at all** — the repo IS the scope. Skip straight to Step 2; there
  is nothing to detect or ask about here.
- **`file`:** use the configured directory (`config.docsRoot`'s `specs/` subdirectory, or a
  user-pointed spec directory) — no project lookup, just a directory listing in Step 2.
- **`inline`:** cannot list (§3 of `references/work-source.md`'s capability table) — see the "no
  `list`" edge case in Step 2 instead of running this step at all.

### Step 2: Fetch Open Work Items

Call the resolved work source's `list`:

```
list({ assignee: "me", project: <resolved project/repo/dir from Step 1>, status: "todo" })
```

For `linear` specifically: resolve `LINEAR_PREFIX` first — accept either `mcp__linear__` or
`mcp__claude_ai_Linear__`, whichever exposes a domain tool (never a hardcoded prefix; same
detection rule `juel:start`'s Step 2 uses), then call:

```
<LINEAR_PREFIX>list_issues(assignee: "me", project: <id>, state: "Todo")
```

The verb is **`list_issues`** — not `list_tickets`, not `search_issues`.

**IMPORTANT:** Only fetch work items in `todo` status. Do NOT fetch `in_progress` items — those
are already being worked on. This rule is correct and provider-neutral: it holds regardless of
which provider resolved.

**Provider capability note.** This skill needs `list` + assignee filter + status write
simultaneously. Linear has all three. Jira needs a `statusMap` because transition names are
per-workflow. **GitHub Issues has no todo/in-progress axis at all — only open/closed** — so
status is emulated via labels or a Projects v2 field, which is a convention the user maintains by
hand and other tools will not respect. `inline` cannot list and is unsupported here.

**If the resolved provider has no `list` capability** (or none resolved at all), do not fail the
phase — ask instead: "paste the refs you want to work on, or point me at a spec directory."

### Step 3: Generate Branch Names

For each ticket, infer the type:

| Signal | Type |
|--------|------|
| Title/labels contain "bug", "fix", "error" | `fix` |
| Title contains "refactor", "cleanup" | `refactor` |
| Title contains "chore", "deps", "update dependencies" | `chore` |
| Default | `feat` |

**Resolve the repo's own conventions once, before naming branches, then reuse them:**

**Remote (`$REMOTE`):** exactly one → use it; contains `origin` → use `origin`; else ask once and
cache.

**Base branch (`$BASE_BRANCH`)** — the branch every new ticket worktree forks from. Resolve once,
same precedence as `cmux-review-pr`/`ship-ticket`: `config.baseBranch` → `git config --get
claude.baseBranch` → `git symbolic-ref --short refs/remotes/$REMOTE/HEAD` (if missing, `git remote
set-head "$REMOTE" --auto` and retry once) → first existing of `main`/`master`/`develop`/`dev`/
`trunk` → ask once and offer to persist. **This is what Step 7 forks every new branch from — never
bare `HEAD`.** Run from inside another ticket's worktree, `HEAD` is that ticket's own branch, not
the base branch; forking from it silently carries that ticket's unmerged commits into the new one.

**Branch naming:** sample `git for-each-ref --sort=-committerdate --count=60 refs/remotes/<remote>`,
strip the remote prefix and default branch, classify each into `type-slash` /
`type-slash-noticket` / `ticket-first` / `user-slash` / `flat`, take the mode. Default
`{type}/{ref-lower}-{slug}` when there is no history.

**Commit style:** sample `git log --no-merges -n 60 --format=%s`. ≥60% conventional →
`conventional`; of those, ≥50% with a ticket-shaped scope → `conventional-ticket`; else
`freeform` — mirror the tone of the last 20 subjects, do not impose a format. (Consumed later, by
whichever skill drives commits/PRs for the ticket in this worktree — not created here.)

**Trailers:** `git log -n 100 --format=%B | grep -ci '^Co-Authored-By:'` — zero means omit.
Default when ambiguous is omit.

None of the above ever blocks worktree creation: an inconclusive detection asks once (and offers
to persist the answer to `.claude/workflow.json`) or falls through to its documented default —
never guessed silently, never a convention the repo doesn't exhibit.

**Branch format:** the detected modal pattern, or `{type}/{ref-lower}-{slug}` when there is no
remote branch history to sample — e.g. `<type>/<ticket-id-lowercase>-<slug>`
**Worktree directory:** `$WORKTREE_ROOT/<ticket-id-lowercase>` (see "Roots" in Step 7 for how
`$WORKTREE_ROOT` is resolved — an absolute path, never the cwd-relative `.worktrees/<ticket-id>`)

Example:
- Branch: `feat/asw-123-add-user-authentication`
- Worktree: `.worktrees/asw-123`

### Step 4: Check Existing Branches/Worktrees

**Before presenting tickets, check if work already exists:**

For each ticket, run:
```bash
git branch --list "*<ticket-id>*"
git worktree list | grep "<ticket-id>"
```

Mark each ticket as:
- **"new"** - No branch or worktree exists
- **"existing branch"** - Branch exists but no worktree
- **"existing worktree"** - Worktree already set up

**If a worktree already exists for a ticket, inform the user and skip creating a duplicate.** They can `cd` into the existing worktree to resume work.

### Step 5: Present for Confirmation

Present tickets with their status clearly marked:

```
Found N Todo tickets for [project]:

ASW-123: Add user authentication
  → feat/asw-123-add-user-authentication (new)

ASW-124: Fix login redirect bug
  → fix/asw-124-fix-login-redirect-bug (existing branch)

ASW-125: Update API docs
  → .worktrees/asw-125 already exists - skip

Does this look correct? [Type adjustments needed?]
```

**For tickets with existing worktrees:** Show them as "already exists - skip" and don't include in selection.

**For 2+ new tickets:** Use AskUserQuestion with multiSelect to let user pick which to set up.

**For 1 new ticket:** Use AskUserQuestion with Yes/No options (tool requires 2+ options).

**Always confirm inferred types** - user can adjust feat→fix, etc. before creation.

### Step 6: Handle Existing

For each selected item with existing branch/worktree, ask:
- "Reuse existing" - keep current work, update the work item's status to `in_progress`
- "Start fresh" - delete old branch, create new

**Auto-update status:** If the item has an existing branch/worktree and the user reuses it, write
`in_progress` through the resolved work source's `update_status`. For `linear` specifically:
resolve `LINEAR_PREFIX` (accept either `mcp__linear__` or `mcp__claude_ai_Linear__`, whichever
exposes a domain tool — never hardcode either), then call:
```
<LINEAR_PREFIX>save_issue(id: item_id, state: "In Progress")
```
`save_issue` is the sole create-or-update verb — `update_issue` does not exist as a tool. If the
provider has no `update_status` capability, print `Status: skipped — provider '<name>' has no
status field configured` and continue; never block worktree reuse on it.

### Step 7: Create Worktrees

**Roots — resolve ONCE before the per-ticket loop, then reuse for every ticket. Never derive the
worktree location from `--show-toplevel` alone:** invoked from inside an existing ticket's
worktree, `--show-toplevel` returns THAT worktree's root, so a naive `<toplevel>/.worktrees` would
nest the new worktree inside the old one.

```bash
CWD_ROOT=$(git rev-parse --show-toplevel)                        # current checkout — for reading project files
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)   # main repo's .git, normalized —
                                                                   # --git-common-dir can print a
                                                                   # RELATIVE path (bare ".git" when
                                                                   # run from the main repo's own
                                                                   # root) — never trust it raw
MAIN_ROOT=$(dirname "$GIT_COMMON")                                # main checkout
```

**`WORKTREE_ROOT`** — `config.worktreeRoot` if set (absolute, `~`-prefixed, or relative to
`$MAIN_ROOT`), else `$MAIN_ROOT/.worktrees`. Worktrees are created under `$WORKTREE_ROOT`, **never**
under `$CWD_ROOT` — the whole point of this resolution is that running this skill from inside
ticket A's worktree must not nest ticket B's worktree inside ticket A's.

**`$REMOTE`** and **`$BASE_BRANCH`** — resolved in Step 3; reused here, not re-derived.

For each selected ticket:

1. Ensure `$WORKTREE_ROOT` exists (`mkdir -p`). If `$WORKTREE_ROOT` is inside `$MAIN_ROOT`, ensure
   its top-level component is gitignored in `$MAIN_ROOT/.gitignore` (add it if absent) — skip this
   entirely when `$WORKTREE_ROOT` resolves outside `$MAIN_ROOT` (an externally configured root has
   nothing under the repo to gitignore, so adding an entry there is pointless).
2. Fetch the base branch fresh, then create the worktree from an EXPLICIT start-point — never bare
   `HEAD`. A plain `git worktree add <path> -b <branch>` with no start-point forks from whatever
   `HEAD` happens to be, which, run from inside another ticket's worktree, is that ticket's own
   branch, not `$BASE_BRANCH`:
   ```bash
   git -C "$MAIN_ROOT" fetch "$REMOTE" "$BASE_BRANCH"
   git -C "$MAIN_ROOT" worktree add "$WORKTREE_ROOT/<ticket-id>" -b <full-branch-name> "$REMOTE/$BASE_BRANCH"
   ```
   Use the absolute `$WORKTREE_ROOT/<ticket-id>` path — never the cwd-relative `.worktrees/<ticket-id>`,
   which resolves against whatever directory the Bash tool's cwd happens to be at that point.
3. **Copy untracked project files only.** Tracked files — including `CLAUDE.md`, which is normally
   tracked — already arrive via the checkout; copying them again would clobber the branch's own
   version of that file. `find` is used instead of a bare glob (`for f in .env .env.* *.local`)
   because a bare glob **aborts the whole script under zsh** when nothing matches (zsh's default,
   non-`nullglob` behavior); `find` never fails on no-match, so this same code runs unmodified under
   `sh`, `bash` and `zsh`:
   ```bash
   # Guard REQUIRED under zsh: without it, an unquoted $EXTRA_PATTERNS is passed to `find`
   # as ONE literal argument instead of being word-split, `find` fails outright, and — because
   # the failure is upstream of the `| while read` pipe — the ENTIRE copy silently produces
   # ZERO files, including the always-on .env/.npmrc defaults. Harmless no-op under bash/sh.
   [ -n "$ZSH_VERSION" ] && setopt SH_WORD_SPLIT

   # EXTRA_PATTERNS is built from config.worktreeCopy — EXTRA, opt-in-only glob patterns
   # (e.g. *.pem). Secrets are never in the default set below; a repo that wants private
   # keys copied must say so explicitly via config.worktreeCopy. No embedded quotes around
   # each pattern: this value is only ever word-split (SH_WORD_SPLIT/bash), never re-parsed
   # by a shell, so a literal quote character would pass straight through to `find` as text.
   EXTRA_PATTERNS=""
   # for p in $config_worktreeCopy; do EXTRA_PATTERNS="$EXTRA_PATTERNS -o -name $p"; done

   # copy_untracked SRC DST — portable, untracked-only, no glob-abort.
   copy_untracked() {
     find "$1" -maxdepth 1 \( \
           -name '.env' -o -name '.env.*' -o -name '*.local' \
        -o -name '.envrc' -o -name '.npmrc' -o -name '.tool-versions' \
        $EXTRA_PATTERNS \) -type f -print | while IFS= read -r f; do
       git -C "$1" ls-files --error-unmatch "${f#"$1"/}" >/dev/null 2>&1 && continue
       cp -p "$f" "$2/"
     done
   }

   copy_untracked "$MAIN_ROOT" "$WORKTREE_ROOT/<ticket-id>"
   ```
   `*.pem` is deliberately NOT in the default pattern set — copying private keys into every
   worktree by default is a bad default. Add it per-repo via `config.worktreeCopy` if actually
   needed.

   Also copy `.claude/` contents (settings, agents, skills, commands) if present — untracked or not,
   this is config plumbing meant to follow every worktree, not project source:
   ```bash
   if [ -d "$MAIN_ROOT/.claude" ]; then
     mkdir -p "$WORKTREE_ROOT/<ticket-id>/.claude"
     cp -a "$MAIN_ROOT/.claude/." "$WORKTREE_ROOT/<ticket-id>/.claude/"
   fi
   ```
4. **Install dependencies — do NOT copy `venv`.** A copied `venv` breaks `python3 -m venv`: paths
   inside a venv are absolute, baked in at creation time, so a `cp -a`'d venv silently points at the
   wrong interpreter/site-packages in every worktree it lands in. This also directly contradicted
   `cmux-review-pr`, which already refuses to copy or symlink `venv/` for the same reason. Run the
   resolved install command instead — same tiered detection (task runner → language manifest → CI
   suggestion, each key verified before acceptance) already wired up in `cmux-review-pr` /
   `cmux-ship-tickets` / `ship-ticket`; see `ship-ticket/SKILL.md`'s "Toolchain commands" section for
   the full per-manifest table. Resolve `INSTALL_CMD` once against `$MAIN_ROOT` (reuse for every
   ticket in this run, do not re-detect per ticket):
   ```bash
   [ -n "$INSTALL_CMD" ] && ( cd "$WORKTREE_ROOT/<ticket-id>" && eval "$INSTALL_CMD" )
   ```
   If nothing resolves and verifies, that is not an error — skip this step with a one-line note and
   let the user install dependencies themselves.
5. **Update the work item's status to `in_progress`** through the resolved work source (same call
   and degrade rule as Step 6's "Auto-update status" above — reuse the `LINEAR_PREFIX` resolved
   once for this run, never re-derive it):
   ```
   <LINEAR_PREFIX>save_issue(id: item_id, state: "In Progress")
   ```
   A missing `update_status` capability is not an error — print the one-line skip note and
   continue; the worktree is already created.

### Step 8: Report & Offer Planning

```
Created N worktrees:

1. .worktrees/asw-123 → branch: feat/asw-123-add-user-authentication
2. .worktrees/asw-124 → branch: fix/asw-124-fix-login-redirect-bug
```

**Ask:** "Create implementation plans for these tickets?"

If yes, for each worktree spawn a **planning subagent**:

```
Task(
  subagent_type: "general-purpose",
  prompt: "WORKTREE PATH: [absolute path, e.g., /Users/me/project/.worktrees/asw-123]
           TICKET ID: [TICKET-ID]

           Plan implementation for this ticket.",
  run_in_background: true
)
```

> This is a planning subagent, not a code review, code-simplifier, or the plan executor. Protocol rule 4 does not apply to it.

**Worktree path:** already absolute from Step 7 (`$WORKTREE_ROOT/<ticket-id>`) — pass it straight
into the subagent prompt, no `realpath` needed.

The agent has access to the same MCP tools as this session to fetch full ticket details, Write access to create plans, and Skill access to use superpowers workflows. Each ticket gets dedicated planning in a fresh context.

### Step 9: Final Report

```
Ready to work!

Worktrees:
- .worktrees/asw-123 (planning in progress...)
- .worktrees/asw-124 (planning in progress...)

cd [path] to begin, or wait for plans to complete.
```

## Configuration

Config resolves via the shared precedence chain (`references/resolution.md` §1), read from
`<repo-root>/.claude/workflow.json` (`.claude/workflow.local.json` deep-merged over it, local
wins):

```jsonc
{
  "tracker": {
    "type": "linear",       // linear | jira | github | file | inline | none
    "project": "PROJECT_NAME_OR_ID"
  }
}
```

`tracker.project` is consumed by Step 1 (preferred over basename guessing); `tracker.type` selects
the provider this whole skill resolves against.

**Deprecated fallback.** When neither `workflow.json` nor `workflow.local.json` exists, the legacy
CLAUDE.md block below is still read (precedence step 4 — see `references/resolution.md` §2's
"Backwards compatibility" note):

```markdown
## Linear Worktrees Config
- linear-project: PROJECT_NAME
- default-status: Todo
```

New repos should use `.claude/workflow.json`; this block is read only for repos that already have
it and haven't migrated.

## Edge Cases

| Situation | Action |
|-----------|--------|
| No Todo work items found | Report "No Todo work items found" - do NOT fall back to In Progress |
| Worktree already exists | Show as "already exists", skip creating, inform user of path |
| Branch exists (no worktree) | Offer to create worktree from existing branch or start fresh |
| Project not found (`linear`/`jira`) | List the provider's projects, ask to select — not applicable to `github` (no project step) or `file` (directory-based) |
| Only 1 new item | Use Yes/No confirmation (AskUserQuestion requires 2+ options) |
| Branch name conflict | Append `-v2` suffix or ask |
| Worktree creation fails | Report error, continue with others |
| 0 items selected | "No items selected. Done." |
| Type inference wrong | Let user adjust before creating |
| Worktree created/reused | Update the work item's status to `in_progress` through the resolved work source (skipped with a one-line note if the provider has no `update_status`) |
| No untracked env files found | Continue without copying - user handles setup |
| `CLAUDE.md` (or any other candidate) is tracked | `copy_untracked` skips it — the worktree's own checked-out version is used, never clobbered by the main checkout's copy |
| No `config.worktreeCopy` patterns configured | `EXTRA_PATTERNS` stays empty; only the default `.env`-family patterns are copied — no `*.pem` unless opted in |
| No `.claude` dir / `CLAUDE.md` | Continue without copying |
| No install command resolves for this repo | Not an error — skip Step 7.4 entirely (no venv or dependency copy either); user installs deps themselves |
| `$WORKTREE_ROOT` not gitignored, and is inside `$MAIN_ROOT` | Add its top-level component to `$MAIN_ROOT/.gitignore` before creating worktrees |
| `$WORKTREE_ROOT` resolves outside `$MAIN_ROOT` (configured) | Skip the gitignore step entirely — nothing under the repo to ignore |

## Quick Reference

```
Resolve provider/scope → Fetch work items → Branch names → Check existing → Select → Create worktrees → Update status → Offer planning → Report
```

**Naming:**
- Worktree dir: `$WORKTREE_ROOT/<ticket-id>` — default `$MAIN_ROOT/.worktrees/<ticket-id>` (see Step 7)
- Branch: detected modal pattern, or `<type>/<ticket-id>-<slug>` when there's no history (see Step 3)

**Types:** feat, fix, refactor, chore
