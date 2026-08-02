---
name: create-linear-ticket
description: Use when user asks to create a Linear ticket, file a bug, track a task, or when discovering issues/TODOs in code that need a Linear issue
---

# Create Linear Ticket

## Overview

Creates Linear tickets from conversational input or code context. Always previews before submitting.

**Announce at start:** "I'm using juel:create-linear-ticket to draft and create the ticket."

**Steps marked MANDATORY must never be skipped.**

## Workflow

### Step 1: Gather Input

If input is vague, ask a targeted follow-up before proceeding. Never guess.

Extract from input if mentioned:
- **Parent issue:** "sub-task of ENG-123" → resolve via `get_issue`, set `parentId`
- **Blocking relationships:** "blocked by ENG-456" → set `blockedBy`; "blocks ENG-789" → set `blocks`
- **Assignee:** resolve via `list_users`
- **Deadline:** "by next Friday", "before the release" → compute due date
- **Cycle:** "for this sprint", "current cycle" → fetch current cycle
- **URLs:** attach as `links`

### Step 2: Project Selection (MANDATORY)

Ask the user to type a project name or keyword. Then call `list_projects(query="<input>")` to filter and present matches with AskUserQuestion.

**Session memory:** if the user already selected a project in this conversation, offer "Same project ([ProjectName])?" instead of asking again. Only re-prompt the full selection if the user requests a different project.

### Step 3: Fetch Team Data (parallel)

From the selected project, resolve the team (use `list_teams` if needed). Then fetch in parallel:
- `list_issue_labels` (for that team)
- `list_issue_statuses` (for that team — identify the team's default entry status)

**Error handling:** if any non-critical call fails (labels, cycles, statuses), continue with that field unset and note it in the preview. Only abort if `list_projects` or `create_issue` fails.

### Step 4: Codebase Scan (conditional)

**Only scan when in a git repo AND the ticket type warrants it:**

| Ticket type | Scan? | Reason |
|-------------|-------|--------|
| Bug report | Yes | File/error context helps reproduction |
| Refactoring / tech debt | Yes | Scope clarity helps implementation |
| Feature request | **No** | Describe the outcome, don't prescribe implementation |
| Design task | **No** | Code context is irrelevant |
| Research spike | **No** | Let the investigator discover the codebase |

**When scanning, match input to action:**

| Input mentions | Scan action |
|---------------|-------------|
| Component or module | Read relevant files; reference by **component name** |
| Bug or error | Grep error messages, check recent commits |
| TODO/FIXME | Grep for it, include surrounding code |

**Code references:** prefer component/module names over raw file paths. References are for orientation, not prescription.

**Code samples policy — diagnostic only, never descriptive:**

| Include | Don't include |
|---------|---------------|
| Stack traces / error output | Current implementation ("here's UserService") |
| Minimal reproduction (the trigger) | Large blocks of existing code |
| API contract examples (expected I/O shapes) | Implementation suggestions |
| Before/after behavioral deltas | AI-scanned codebase dumps |

**Size limits:** 1-3 lines inline in Context, 4-10 lines in a code block, 11+ lines **never** — reference the component instead.

### Step 5: Draft Ticket

**Title:** concise, imperative (e.g., "Add retry logic to payment webhook handler")

**Description template — adapt based on ticket type:**

For **features and bugs**, use Context / Requirements / Acceptance Criteria:

```markdown
## Context

[Why is this work needed?]
[If from code: include component names and brief context]
[If video mentioned: include "Video timestamp: MM:SS"]

## Requirements

- [What needs to be built/implemented]
- [Any constraints or dependencies]

## Acceptance Criteria

- [ ] [Specific, testable criterion — e.g., "Returns 200 for valid payload"]
- [ ] [Another specific, testable criterion]
```

For **research spikes and investigations**, replace AC with:
```markdown
## Outcome
- [ ] [What should be delivered — e.g., "Decision document comparing options A and B"]
```

For **chores and tech debt**, replace AC with:
```markdown
## Done When
- [ ] [Completion condition — e.g., "All v1 endpoints removed, no references remain"]
```

For **trivial tickets** (fix typo, rename variable): a one-line description is fine. Skip the template.

**AC rules:** each item must be verifiable — no vague language like "works correctly." State the observable outcome.

**Defaults (auto-set unless user specifies otherwise):**

| Field | Value |
|-------|-------|
| Priority | No priority (0) — only set higher if user indicates urgency |
| Status | Team's default entry status (from `list_issue_statuses`) |
| Cycle | Unset — only set if user says "this sprint" or "current cycle" |
| Due date | Unset — only set if user mentions a deadline |

Suggest 1-3 labels by keyword overlap between ticket content and label names. Never invent labels that don't exist.

### Step 6: Preview (MANDATORY)

```
Linear Ticket Preview
---------------------
Title:    [title]
Project:  [project name]
Team:     [team name]
Priority: No priority
Status:   [team default status]
Cycle:    [unset or cycle name]
Due:      [unset or date]
Labels:   [label1, label2]
Assignee: [name or "unassigned"]
Parent:   [parent issue or "none"]
Blocked:  [blocking relationships or "none"]

-- Description --
[full markdown description]
---------------------
Create this ticket? [Yes / Edit / Cancel]
```

If user says **Edit**: apply their changes and re-preview. If **Cancel**: stop. If **Yes**: proceed.

### Step 7: Create & Report

Call `create_issue` with all fields. Include `parentId`, `blocks`, `blockedBy`, `links` if detected in Step 1. Report the ticket identifier.

## Edge Cases

| Situation | Action |
|-----------|--------|
| Input too vague | Ask targeted follow-up before drafting |
| User mentions parent issue | Resolve via `get_issue`, set `parentId` |
| User mentions "blocked by" / "blocks" | Set `blockedBy` / `blocks` fields |
| User mentions assignee | Resolve via `list_users` |
| User mentions URL | Attach as `links` |
| Video/timestamp mentioned | Add "Video timestamp: MM:SS" to Context |
| User wants edits after preview | Apply changes, re-preview |
| API call fails (non-critical) | Continue with field unset, note in preview |
| 50+ projects in workspace | Use `list_projects(query=...)` to filter, never dump full list |

## Common Mistakes

| Mistake | Correct |
|---------|---------|
| Skipping project selection | ALWAYS ask user to pick a project |
| Dumping full project list | Use `query` param to filter server-side |
| Using wrong template structure | Context/Requirements/AC for features+bugs; adapt for spikes/chores |
| Setting due date without user asking | Only set when user mentions a deadline |
| Auto-assigning current cycle | Only set when user says "this sprint" |
| Hardcoding "Todo" status | Use the team's configured default entry status |
| Setting priority to "Normal" unprompted | Default to No priority (0) unless user indicates urgency |
| Not fetching labels | Fetch labels and suggest 1-3 relevant ones |
| Not scanning codebase for bugs/refactors | Do targeted scan for bugs and tech debt; skip for features/spikes |
| Using raw file paths only | Prefer component/module names; paths are supplementary |
| Dumping code blocks as context | Code must be diagnostic (stack trace, repro, error), never descriptive (current impl) |
| Vague acceptance criteria | Specific, testable ("Returns 200 for valid payload") |
| Skipping preview | ALWAYS show preview before creating |
| Aborting on non-critical API failure | Continue with field unset, note in preview |
