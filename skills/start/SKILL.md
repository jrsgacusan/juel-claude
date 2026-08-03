---
name: start
description: Use when beginning work on a ticket inside a worktree - detects ticket ID from directory, fetches Linear ticket, analyzes requirements, then brainstorms implementation
---

# Start Ticket Work

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
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP → run from inside a repo |
| Linear MCP (`mcp__linear__get_issue`) | mcp | HARD | **none — render as `?`** | proceed; the fetch in phase 2 fails loudly |
| superpowers:brainstorming | skill | HARD | ships as a plugin dependency | STOP → `/plugin install superpowers@claude-plugins-official` |

## Phases

[ ] 1. Detect the work-item reference (worktree, then branch)
[ ] 2. Fetch the work item from the resolved source
[ ] 3. Analyze requirements and present the summary
[ ] 4. Brainstorm via superpowers:brainstorming

## Overview

Automates the "start working on a ticket" workflow: detect ticket from worktree, fetch from Linear, analyze requirements, brainstorm.

## Workflow

### Step 1: Detect Ticket ID

Extract the ticket ID from the current working directory:

```bash
basename "$(pwd)"
```

Expected format: `savi-XXX` (from `.worktrees/savi-XXX`).

If the directory doesn't match a ticket pattern, ask the user for the ticket ID.

### Step 2: Fetch Linear Ticket

Convert directory name to Linear identifier (e.g., `savi-855` -> `SAVI-855`).

Fetch full ticket details:
```
linear__get_issue(id: "SAVI-XXX")
```

### Step 3: Analyze Requirements

Read the ticket description and extract:
- **Type**: Feature, Enhancement, Bug fix, etc.
- **Context**: Why this work is needed
- **Requirements**: What needs to be built (bullet points)
- **Acceptance Criteria**: Definition of done
- **Dependencies**: Other tickets this depends on
- **API endpoints**: Any backend APIs to integrate with

Present a concise summary to the user.

### Step 4: Brainstorm

Invoke `superpowers:brainstorming` to explore implementation approach before writing code.

## Edge Cases

| Situation | Action |
|-----------|--------|
| Not in a worktree directory | Ask user for ticket ID |
| Linear ticket not found | Report error, ask user to verify |
| Ticket has no description | Warn user, proceed with title only |
