---
name: daily-worktrees
description: Use when starting your workday and need to see Linear tickets assigned to you, or when setting up worktrees for multiple tickets in parallel
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

**Branch format:** `<type>/<ticket-id-lowercase>-<slug>`
**Worktree directory:** `.worktrees/<ticket-id-lowercase>`

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

For each selected ticket:

1. Verify `.worktrees` directory exists and is gitignored
2. Create worktree:
   ```bash
   git worktree add .worktrees/<ticket-id> -b <full-branch-name>
   ```
3. **Copy environment and project files** from main repo to worktree:
   ```bash
   # Auto-detect and copy common env file patterns
   for f in .env .env.* *.local .envrc; do
     [ -f "$f" ] && cp "$f" ".worktrees/<ticket-id>/"
   done
   # Copy .pem files if they exist
   for f in *.pem; do
     [ -f "$f" ] && cp "$f" ".worktrees/<ticket-id>/"
   done
   # Copy venv if it exists
   [ -d "venv" ] && cp -a venv ".worktrees/<ticket-id>/venv"
   # Copy .claude contents (settings, agents, skills, commands) if present.
   # Use contents-copy (`.claude/.` → `target/.claude/`) so re-running or a
   # pre-existing target dir does NOT nest into `.claude/.claude`.
   if [ -d ".claude" ]; then
     mkdir -p ".worktrees/<ticket-id>/.claude"
     cp -a .claude/. ".worktrees/<ticket-id>/.claude/"
   fi
   [ -f "CLAUDE.md" ] && cp CLAUDE.md ".worktrees/<ticket-id>/CLAUDE.md"
   [ -f "CLAUDE.local.md" ] && cp CLAUDE.local.md ".worktrees/<ticket-id>/CLAUDE.local.md"
   ```
4. **Update Linear status to "In Progress":**
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

**Get the absolute worktree path:**
```bash
realpath .worktrees/[ticket-id]
```

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
| No env files found | Continue without copying - user handles setup |
| No .pem files found | Continue without copying |
| No venv directory found | Continue without copying |
| No .claude dir / CLAUDE.md | Continue without copying |
| `.worktrees` not gitignored | Add `.worktrees/` to `.gitignore` before creating worktrees |

## Quick Reference

```
Project detection → Linear fetch → Branch names → Check existing → Select → Create worktrees → Update Linear → Offer planning → Report
```

**Naming:**
- Worktree dir: `.worktrees/<ticket-id>` (simple)
- Branch: `<type>/<ticket-id>-<slug>` (descriptive)

**Types:** feat, fix, refactor, chore
