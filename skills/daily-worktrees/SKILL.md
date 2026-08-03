---
name: daily-worktrees
description: Use when starting your workday and need to see Linear tickets assigned to you, or when setting up worktrees for multiple tickets in parallel
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: phase 2 fetches open Todo tickets assigned to the user
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

# Daily Linear Worktrees

## Overview

Fetch Linear tickets for the current project and create git worktrees for parallel development.

**Announce:** "Using this skill to fetch your tickets and set up worktrees."

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v1 -->

**1. Preflight, then checklist, before anything else.** Before any other output and before any tool call, emit the Preflight block (below), then this skill's `## Phases` checklist rendered as:

```
<skill-name> — N phases
[ ] 1. <phase name>
[ ] 2. <phase name>
```

If the preflight verdict is STOP, print the preflight block and **stop** — do not print the checklist and do not begin work. Otherwise no work begins until the checklist is on screen. This is not optional on re-invocation, on resume, or when the user says "just do it".

**2. Phases run in order.** No skipping, reordering, or merging. A phase that does not apply is still announced: mark it `[-] N. <name> — SKIPPED: <one-line reason>` and continue at N+1. Never drop a phase silently. Never begin phase N+1 before phase N is marked done or skipped.

**3. Report after every phase.** Re-emit the checklist (`[x]` done, `[-]` skipped, `[ ]` pending) plus one line of evidence for the phase just finished — path written, command run, count found. Never claim progress in prose alone.

**4. Everything runs in the FOREGROUND.** This overrides every other instruction in this file and in any skill invoked from it.
- `pr-review-toolkit:review-pr`, `simplify`, and `codex exec` are all foreground-only. Invoke subagents with `run_in_background: false` **explicitly** — the harness backgrounds subagents by default, so omitting the flag is a violation, not a neutral choice.
- Never `&`. Never `run_in_background: true`. Never "dispatch and continue".
- **Never redirect a command's output to a log file.** No `> out.log`, no `| tee`, no writing output somewhere to read back later. The user must be able to watch the run as it happens.
- Do not request `review-pr`'s parallel / `all parallel` mode.
- Read the complete output and state the outcome — finding count, exit status, files changed — before marking the phase done. A summary may follow the raw output; it may never replace it.
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

[ ] 1. Detect the project
[ ] 2. Fetch open work items from the resolved source
[ ] 3. Generate branch and worktree names
[ ] 4. Check for existing branches and worktrees
[ ] 5. Present for confirmation and let the user select
[ ] 6. Handle existing work — reuse or start fresh
[ ] 7. Create worktrees, copy untracked files, set status to in_progress
[ ] 8. Report and offer planning (SKIPPED if declined)
[ ] 9. Final report

## Prerequisites

- Linear plugin installed & authenticated
- Inside a git repository
- Git worktrees supported (git 2.5+)

## Workflow

### Step 1: Detect Project

```bash
project_name=$(basename "$(git rev-parse --show-toplevel)")
```

Search Linear projects for a match. If no confident match, list available projects and ask user to select.

### Step 2: Fetch Tickets

Query Linear using `linear__list_issues`:
- `assignee`: "me"
- `project`: matched project name/ID
- `state`: "Todo"

**IMPORTANT:** Only fetch tickets in "Todo" status. Do NOT fetch "In Progress" tickets - those are already being worked on.

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

For each selected ticket with existing branch/worktree, ask:
- "Reuse existing" - keep current work, update Linear status to "In Progress"
- "Start fresh" - delete old branch, create new

**Auto-update Linear:** If ticket has existing branch/worktree and user reuses it, update ticket status:
```
linear__update_issue(id: ticket_id, state: "In Progress")
```

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
   # (e.g. "*.pem"). Secrets are never in the default set below; a repo that wants private
   # keys copied must say so explicitly via config.worktreeCopy.
   EXTRA_PATTERNS=""
   # for p in $config_worktreeCopy; do EXTRA_PATTERNS="$EXTRA_PATTERNS -o -name '$p'"; done

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
5. **Update Linear status to "In Progress":**
   ```
   linear__update_issue(id: ticket_id, state: "In Progress")
   ```

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

> This is a planning subagent, not a code review, simplify, or the plan executor. Protocol rule 4 does not apply to it.

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

Check CLAUDE.md for overrides:
```markdown
## Linear Worktrees Config
- linear-project: PROJECT_NAME
- default-status: Todo
```

## Edge Cases

| Situation | Action |
|-----------|--------|
| No Todo tickets found | Report "No Todo tickets" - do NOT fall back to In Progress |
| Worktree already exists | Show as "already exists", skip creating, inform user of path |
| Branch exists (no worktree) | Offer to create worktree from existing branch or start fresh |
| Project not found | List Linear projects, ask to select |
| Only 1 new ticket | Use Yes/No confirmation (AskUserQuestion requires 2+ options) |
| Branch name conflict | Append `-v2` suffix or ask |
| Worktree creation fails | Report error, continue with others |
| 0 tickets selected | "No tickets selected. Done." |
| Type inference wrong | Let user adjust before creating |
| Worktree created/reused | Update Linear ticket to "In Progress" |
| No untracked env files found | Continue without copying - user handles setup |
| `CLAUDE.md` (or any other candidate) is tracked | `copy_untracked` skips it — the worktree's own checked-out version is used, never clobbered by the main checkout's copy |
| No `config.worktreeCopy` patterns configured | `EXTRA_PATTERNS` stays empty; only the default `.env`-family patterns are copied — no `*.pem` unless opted in |
| No `.claude` dir / `CLAUDE.md` | Continue without copying |
| No install command resolves for this repo | Not an error — skip Step 7.4 entirely (no venv or dependency copy either); user installs deps themselves |
| `$WORKTREE_ROOT` not gitignored, and is inside `$MAIN_ROOT` | Add its top-level component to `$MAIN_ROOT/.gitignore` before creating worktrees |
| `$WORKTREE_ROOT` resolves outside `$MAIN_ROOT` (configured) | Skip the gitignore step entirely — nothing under the repo to ignore |

## Quick Reference

```
Project detection → Linear fetch → Branch names → Check existing → Select → Create worktrees → Update Linear → Offer planning → Report
```

**Naming:**
- Worktree dir: `$WORKTREE_ROOT/<ticket-id>` — default `$MAIN_ROOT/.worktrees/<ticket-id>` (see Step 7)
- Branch: detected modal pattern, or `<type>/<ticket-id>-<slug>` when there's no history (see Step 3)

**Types:** feat, fix, refactor, chore
