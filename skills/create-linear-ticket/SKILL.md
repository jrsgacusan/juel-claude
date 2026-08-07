---
name: create-linear-ticket
description: Use when user asks to create a Linear ticket, file a bug, track a task, or when discovering issues/TODOs in code that need a Linear issue. Linear-specific — for other sources, resolve the work item via the work-source reference.
metadata:
  requires:
    mcp:
      - id: linear
        hard: true
        why: creates the ticket directly via Linear's save_issue (the sole create-or-update verb); this skill is Linear-specific by design
        check: none
    context:
      - id: interactive-user
        hard: true
        why: phase 2 project selection is mandatory and uses AskUserQuestion
      - id: git-repo
        hard: false
        why: phase 4 scans the codebase for bug/refactor tickets
        check: "git rev-parse --show-toplevel"
        fallback: phase 4 codebase scan is SKIPPED
---

# Create Linear Ticket

## Overview

Creates Linear tickets from conversational input or code context. Always previews before submitting.

**Announce at start:** "I'm using juel:create-linear-ticket to draft and create the ticket."

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
| Linear MCP | mcp | HARD | **none — render as `?`** | proceed; phase 2 fails loudly. This skill is Linear-specific by design |
| AskUserQuestion | context | HARD | always available interactively | STOP → project selection is mandatory |
| git repo | context | SOFT | `git rev-parse --show-toplevel` | phase 4 codebase scan is SKIPPED |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Gather input — parent, blockers, assignee, deadline, cycle, links
2. Project selection (MANDATORY — never skipped)
3. Fetch team data — labels and statuses
4. Codebase scan (conditional)
5. Draft the ticket — title, description, defaults, labels
6. Preview (MANDATORY — never skipped): Yes / Edit / Cancel
7. Create and report the ticket identifier

Phase 4 is the canonical rule-2 case: it is never silently dropped. Not in a git repo, or the ticket type doesn't warrant it (feature request, design task, research spike — see Step 4 below), it is still announced: mark its task `completed` via `TaskUpdate` with the one-line evidence stating the skip reason. For a feature request that evidence reads:
`SKIPPED: feature request, code context would prescribe implementation`

**Steps marked MANDATORY must never be skipped.**

## Workflow

**Resolve the Linear MCP prefix first — every call below is written `<LINEAR_PREFIX>tool_name`.**
Both `mcp__linear__` (the plugin dependency) and `mcp__claude_ai_Linear__` (the claude.ai connector)
are real; the active one depends on which connector the user authenticated. Use whichever prefix
exposes a *domain* tool — anything other than `authenticate`/`complete_authentication`, since the
plugin connector can be installed but not yet authorized, which is not the same as usable. If
neither prefix exposes a domain tool, **STOP**: "Linear MCP is not connected. Enable the connector,
restart this session (connectors bind at startup), then re-run." Do not retry.

### Step 1: Gather Input

If input is vague, ask a targeted follow-up before proceeding. Never guess.

Extract from input if mentioned:
- **Parent issue:** "sub-task of ENG-123" → resolve via `<LINEAR_PREFIX>get_issue`, set `parentId`
- **Blocking relationships:** "blocked by ENG-456" → set `blockedBy`; "blocks ENG-789" → set `blocks`
- **Assignee:** resolve via `<LINEAR_PREFIX>list_users`
- **Deadline:** "by next Friday", "before the release" → compute due date
- **Cycle:** "for this sprint", "current cycle" → fetch current cycle via `<LINEAR_PREFIX>list_cycles`
- **URLs:** attach as `links`

### Step 2: Project Selection (MANDATORY)

Ask the user to type a project name or keyword. Then call `<LINEAR_PREFIX>list_projects(query="<input>")` to filter and present matches with AskUserQuestion.

**Session memory:** if the user already selected a project in this conversation, offer "Same project ([ProjectName])?" instead of asking again. Only re-prompt the full selection if the user requests a different project.

### Step 3: Fetch Team Data (parallel)

From the selected project, resolve the team (use `<LINEAR_PREFIX>list_teams` if needed). Then fetch in parallel:
- `<LINEAR_PREFIX>list_issue_labels` (for that team)
- `<LINEAR_PREFIX>list_issue_statuses` (for that team — identify the team's default entry status)

**Error handling:** if any non-critical call fails (labels, cycles, statuses), continue with that field unset and note it in the preview. Only abort if `<LINEAR_PREFIX>list_projects` or `<LINEAR_PREFIX>save_issue` fails.

### Step 4: Codebase Scan (conditional)

**Only scan when in a git repo AND the ticket type warrants it:**

| Ticket type | Scan? | Reason |
|-------------|-------|--------|
| Bug report | Yes | File/error context helps reproduction |
| Refactoring / tech debt | Yes | Scope clarity helps implementation |
| Feature request | **No** | Describe the outcome, don't prescribe implementation |
| Design task | **No** | Code context is irrelevant |
| Research spike | **No** | Let the investigator discover the codebase |

**Never drop this phase silently when it doesn't apply — mark its task `completed` via `TaskUpdate` with the one-line evidence stating the skip reason (protocol rule 2), e.g. for a feature request:**
`SKIPPED: feature request, code context would prescribe implementation`

**When scanning, match input to action:**

| Input mentions | Scan action |
|---------------|-------------|
| Component or module | Read relevant files; reference by **component name** |
| Bug or error | Grep error messages, check recent commits |
| TODO/FIXME | Grep for it, include surrounding code |

**Code references:** prefer component/module names over raw file paths. References are for orientation, not prescription.

**Code samples policy — diagnostic only, never descriptive** (canonical shared copy:
`references/work-source.md` §6.1, extracted verbatim so a future provider-neutral authoring
dispatcher can reuse it without re-deriving from scratch — kept inline here too, since this skill
must stay fully self-contained: `references/*.md` files are authoring sources of truth, never read
at runtime, so nothing that must actually run can live only there):

| Include | Don't include |
|---------|---------------|
| Stack traces / error output | Current implementation ("here's UserService") |
| Minimal reproduction (the trigger) | Large blocks of existing code |
| API contract examples (expected I/O shapes) | Implementation suggestions |
| Before/after behavioral deltas | AI-scanned codebase dumps |

**Size limits:** 1-3 lines inline in Context, 4-10 lines in a code block, 11+ lines **never** — reference the component instead.

### Step 5: Draft Ticket

**Title:** concise, imperative (e.g., "Add retry logic to payment webhook handler")

**Description template — adapt based on ticket type** (canonical shared copy: `references/work-source.md`
§6.2 — same reuse/inlining rationale as the code-samples policy above):

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

**AC rules** (canonical shared copy: `references/work-source.md` §6.3): each item must be verifiable — no vague language like "works correctly." State the observable outcome.

**Defaults (auto-set unless user specifies otherwise):**

| Field | Value |
|-------|-------|
| Priority | No priority (0) — only set higher if user indicates urgency |
| Status | Team's default entry status (from `<LINEAR_PREFIX>list_issue_statuses`) |
| Cycle | Unset — only set if user says "this sprint" or "current cycle" |
| Due date | Unset — only set if user mentions a deadline |

Suggest 1-3 labels by keyword overlap between ticket content and label names. Never invent labels that don't exist.

### Step 6: Preview (MANDATORY)

Canonical shared copy: `references/work-source.md` §6.4 — same reuse/inlining rationale as above;
this step is never skipped regardless of which copy a future generic dispatcher reads.

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

Call `<LINEAR_PREFIX>save_issue` with all fields. Include `parentId`, `blocks`, `blockedBy`, `links` if detected in Step 1. Report the ticket identifier. `save_issue` is the sole create-or-update verb — `create_issue` does not exist as a tool.

## Edge Cases

| Situation | Action |
|-----------|--------|
| Input too vague | Ask targeted follow-up before drafting |
| User mentions parent issue | Resolve via `<LINEAR_PREFIX>get_issue`, set `parentId` |
| User mentions "blocked by" / "blocks" | Set `blockedBy` / `blocks` fields |
| User mentions assignee | Resolve via `<LINEAR_PREFIX>list_users` |
| User mentions URL | Attach as `links` |
| Video/timestamp mentioned | Add "Video timestamp: MM:SS" to Context |
| User wants edits after preview | Apply changes, re-preview |
| API call fails (non-critical) | Continue with field unset, note in preview |
| 50+ projects in workspace | Use `<LINEAR_PREFIX>list_projects(query=...)` to filter, never dump full list |

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
