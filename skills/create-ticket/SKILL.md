---
name: create-ticket
description: Use when the user asks to create a ticket, issue or work item, file a bug, track a task, or when discovering issues/TODOs in code that need one. The tracker comes from the project (.claude/workflow.json `tracker`, a `## Work Source` block in CLAUDE.md/AGENTS.md, or auto-detect) - Linear, Jira, GitHub Issues or a spec file. Scopes the request through superpowers:brainstorming first, so the requirements and acceptance criteria are unambiguous and grounded in the actual codebase before the ticket is drafted, and always previews before creating.
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: creates the item via Linear's save_issue when Linear resolves as the project's work source
        check: none
        fallback: the project's other configured source is used; if Linear is the configured source and its MCP is not connected, Step 0 stops with the connect instructions
    skills:
      - id: superpowers:brainstorming
        hard: true
        why: phase 1 scopes the request into unambiguous requirements and acceptance criteria before anything is drafted
    context:
      - id: work-source-create-capable
        hard: true
        why: Step 0 resolves the project's work source and requires its create capability
      - id: interactive-user
        hard: true
        why: Step 0's one-time source question, phase 3 scope selection and phase 7 preview use AskUserQuestion
      - id: git-repo
        hard: false
        why: phase 5 scans the codebase for bug/refactor tickets
        check: "git rev-parse --show-toplevel"
        fallback: phase 5 codebase scan is SKIPPED
---

# Create Ticket

## Overview

Creates a work item in whatever tracker the project uses, from conversational input or code
context. Scopes the request into unambiguous requirements before drafting anything, and always
previews before submitting. The skill never decides the tracker: the project does.

**Announce at start:** "I'm using juel:create-ticket to draft and create the ticket."

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

## Preflight

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| Linear MCP | mcp | SOFT | **none — render as `?`** | the project's other configured source is used; if Linear is the configured source and its MCP is not connected, Step 0 stops with the connect instructions |
| superpowers:brainstorming | skill | HARD | ships as a plugin dependency | STOP → `/plugin install superpowers@claude-plugins-official` |
| work source with `create` | context | HARD | Step 0 resolution | STOP → configure `tracker` in `.claude/workflow.json` or a `## Work Source` block in CLAUDE.md/AGENTS.md |
| AskUserQuestion | context | HARD | always available interactively | STOP → scope selection and preview are mandatory |
| git repo | context | SOFT | `git rev-parse --show-toplevel` | phase 5 codebase scan is SKIPPED |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

0. Resolve the work source (MANDATORY — never skipped)
1. Scope the request (MANDATORY — never skipped): unambiguous requirements and acceptance criteria
2. Gather input — parent, blockers, assignee, deadline, cycle, links
3. Scope selection — project, repo or directory (MANDATORY where the source has a project concept)
4. Fetch source metadata — labels, statuses, issue types
5. Codebase scan (conditional)
6. Draft the ticket — title, description, defaults, labels
7. Preview (MANDATORY — never skipped): Yes / Edit / Cancel
8. Create and report the ticket identifier and URL

Phase 5 is the canonical rule-2 case: it is never silently dropped. Not in a git repo, or the ticket type doesn't warrant it (feature request, design task, research spike — see Step 5 below), it is still announced: mark its task `completed` via `TaskUpdate` with the one-line evidence stating the skip reason. For a feature request that evidence reads:
`SKIPPED: feature request, code context would prescribe implementation`

**Steps marked MANDATORY must never be skipped.**

## Workflow

### Step 0: Resolve the Work Source (MANDATORY)

The project decides where the ticket goes. Resolve the provider once, stop at the first hit:

1. An explicit source in the user's request ("file this as a GitHub issue").
2. `.claude/workflow.local.json`, then `.claude/workflow.json`: `tracker.type` (and `tracker.project`).
3. A `## Work Source` block in the repo's CLAUDE.md or AGENTS.md (`- type:` / `- project:`), then
   the legacy `## Linear Worktrees Config` block (`linear-project:` implies `linear`).
4. Auto-detect: a connected Linear MCP (a domain tool under `mcp__linear__` or
   `mcp__claude_ai_Linear__`), a connected Jira/Atlassian MCP, or a GitHub remote with `gh`
   authenticated. Exactly one candidate → use it. More than one → step 5.
5. Ask once with AskUserQuestion, then offer to persist the answer as `tracker` in
   `.claude/workflow.json`. Never write config without a yes.

The resolved source must be able to `create`:

| Source | `create` | Notes |
|---|---|---|
| `linear` | Yes | resolve `LINEAR_PREFIX` now: `mcp__linear__` or `mcp__claude_ai_Linear__`, whichever exposes a domain tool (anything but `authenticate`/`complete_authentication`); every Linear call below is written `<LINEAR_PREFIX>tool_name`. Neither does → STOP: "Linear MCP is not connected. Enable the connector, restart this session (connectors bind at startup), then re-run." |
| `jira` | Yes | needs a connected Jira/Atlassian MCP |
| `github` | Yes | needs `gh auth status` to pass and a GitHub remote |
| `file` | Yes | writes into `<docsRoot>/specs/`, where docsRoot is `config.docsRoot` if set, else `docs/.superpowers/` when it exists and is non-empty, else `docs/superpowers/` (the same directory `juel:daily-worktrees` lists) |
| `inline` | No | `inline` cannot create: STOP with "This project's work source is inline text, which has nowhere to store a ticket. Configure `tracker` in .claude/workflow.json or a `## Work Source` block, then re-run." |

State the result in one line before Step 1, e.g. `Work source: github (from CLAUDE.md Work Source block)`.

### Step 1: Scope the Request (MANDATORY)

A work item is only as good as its acceptance criteria, and a request as typed is almost never
specific enough to write them from. This phase turns the request into a requirement set the
implementer cannot misread. It runs for **every** ticket — a one-line TODO capture that is already
complete passes through in a single exchange, but it is never skipped on the judgment that the
request "looks clear enough".

Invoke `Skill("superpowers:brainstorming")` with a scoping contract. Pass all four clauses — the
first three bound what it produces, and the fourth is what stops it building the thing you are
only trying to file:

```
Scope this request into a work item's requirements. Contract:
- Classify this as BOUNDED. We are scoping one work item, not designing a subsystem.
- The deliverable is a confirmed Context / Requirements / Acceptance Criteria set for a
  ticket. Not a design, not an implementation approach, not a file-by-file plan.
- Read the codebase to ground every requirement in what is actually there: confirm the
  components involved exist, the described behavior is real, and each acceptance criterion
  is checkable. Those findings shape the criteria; they do NOT go into the ticket body.
- Your terminal state is handing that requirement set back to juel:create-ticket.
  Do NOT implement, do NOT write a spec file, do NOT invoke writing-plans. The human
  approval you are seeking is the user confirming this scope is right for a ticket.

The request: <verbatim user request>
```

**Why the fourth clause is load-bearing.** `superpowers:brainstorming`'s documented terminal state
for a bounded task is "implement via the normal development workflow". Without an explicit
contract it would correctly read approval of the scope as approval to start building. The contract
is what makes an off-label invocation safe; never abbreviate it to "brainstorm this first".

**What comes back, and what to do with it:**

| Brainstorming produced | Use it for |
|---|---|
| Context — why the work is needed | Step 6's Context section |
| Requirements — what must be true when done | Step 6's Requirements section |
| Acceptance criteria — how each is checked | Step 6's Acceptance Criteria section |
| Codebase findings — what exists, what it is called | Grounding the above. **Not** ticket content |
| An implementation approach, if it volunteered one | Discard it. The implementer decides that |

The last two rows are the point: the reading makes the criteria concrete and testable, and then
stays out of the ticket. Step 5's code-samples policy ("diagnostic only, never descriptive") still
governs everything that reaches the ticket body.

**If brainstorming starts implementing anyway** — editing files, writing a spec, invoking
`writing-plans` — stop it, and re-invoke with the contract restated. Do not file a ticket for work
that has already been half-done in the working tree without telling the user that happened.

**This is deliberately the second time this work gets thought about.** `juel:start` phase 4 runs
`superpowers:brainstorming` again when someone picks the ticket up, in a worktree with the ticket
in hand. That run decides *how*; this one decides *what*. Removing either one is a mistake, not a
simplification.

### Step 2: Gather Input

Extract from input if mentioned, keeping only the fields the resolved source supports:

- **Parent issue:** "sub-task of ENG-123". Linear: resolve via `<LINEAR_PREFIX>get_issue`, set `parentId`. Jira: parent key. GitHub and file: add a "Parent: <ref or link>" line to Context.
- **Blocking relationships:** "blocked by ENG-456" / "blocks ENG-789". Linear: `blockedBy` / `blocks`. Others: a "Blocked by" / "Blocks" line in Context.
- **Assignee:** Linear: resolve via `<LINEAR_PREFIX>list_users`. Jira: the MCP's user lookup. GitHub: a login for `--assignee`. File: an `assignee:` frontmatter field.
- **Deadline:** "by next Friday", "before the release" → compute a due date (Linear, Jira, file frontmatter; GitHub has none, so add it to Context).
- **Cycle:** "for this sprint". Linear only: fetch the current cycle via `<LINEAR_PREFIX>list_cycles`.
- **URLs:** Linear: attach as `links`. Others: a Links section in the description.

### Step 3: Scope Selection

| Source | What to select |
|---|---|
| `linear` | MANDATORY. Ask the user to type a project name or keyword (offer the project the source resolved with as the default: `tracker.project`, the Work Source block's `project`, or the legacy `linear-project`), then call `<LINEAR_PREFIX>list_projects(query="<input>")` and present matches with AskUserQuestion |
| `jira` | MANDATORY. Project (offer the resolved project first: `tracker.project` or the Work Source block's `project`), then issue type (Bug / Task / Story as the project defines them) |
| `github` | No selection: the repo is the scope. Say so in one line, e.g. `Scope: github.com/owner/repo` |
| `file` | No selection: the resolved spec directory. Say so in one line |

**Session memory:** if the user already selected a project in this conversation, offer "Same project ([ProjectName])?" instead of asking again. Only re-prompt the full selection if the user requests a different project.

### Step 4: Fetch Source Metadata (parallel)

| Source | Fetch |
|---|---|
| `linear` | resolve the team (`<LINEAR_PREFIX>list_teams` if needed), then in parallel `<LINEAR_PREFIX>list_issue_labels` and `<LINEAR_PREFIX>list_issue_statuses` for that team (identify the default entry status) |
| `jira` | labels in use in the project, and the issue type's fields |
| `github` | `gh label list --json name --limit 200` |
| `file` | nothing |

**Error handling:** if any non-critical call fails (labels, cycles, statuses), continue with that field unset and note it in the preview. Only abort if scope selection or the create call itself fails.

### Step 5: Codebase Scan (conditional)

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
dispatcher can reuse it — kept inline here too, since this skill
must stay fully self-contained: `references/*.md` files are authoring sources of truth, never read
at runtime, so nothing that must actually run can live only there):

| Include | Don't include |
|---------|---------------|
| Stack traces / error output | Current implementation ("here's UserService") |
| Minimal reproduction (the trigger) | Large blocks of existing code |
| API contract examples (expected I/O shapes) | Implementation suggestions |
| Before/after behavioral deltas | AI-scanned codebase dumps |

**Size limits:** 1-3 lines inline in Context, 4-10 lines in a code block, 11+ lines **never** — reference the component instead.

### Step 6: Draft Ticket

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

**Defaults (auto-set unless the user specifies otherwise; only for fields the source has):**

| Field | Value |
|-------|-------|
| Priority | No priority — only set higher if user indicates urgency (Linear, Jira) |
| Status | The source's default entry status: Linear's team default from `<LINEAR_PREFIX>list_issue_statuses`, Jira's workflow start, GitHub's `status:todo` label only if the repo already uses `status:*` labels, file `Status: todo` |
| Cycle | Unset — Linear only, and only if user says "this sprint" or "current cycle" |
| Due date | Unset — only set if user mentions a deadline |

Suggest 1-3 labels by keyword overlap between ticket content and label names. Never invent labels that don't exist.

### Step 7: Preview (MANDATORY)

Canonical shared copy: `references/work-source.md` §6.4; this step is never skipped. The header
names the source, and a field the source does not support is **left out**, never shown as "unset":

```
<Source> Work Item Preview          (e.g. "GitHub Issue Preview", "Linear Ticket Preview")
---------------------
Title:    [title]
Scope:    [project / repo / spec directory]
Type:     [Jira issue type — Jira only]
Team:     [team name — Linear only]
Priority: [No priority — Linear, Jira]
Status:   [default entry status]
Cycle:    [unset or cycle name — Linear only]
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

### Step 8: Create & Report

| Source | Create |
|---|---|
| `linear` | `<LINEAR_PREFIX>save_issue` with all fields, including `parentId`, `blocks`, `blockedBy`, `links` from Step 2. `save_issue` is the sole create-or-update verb; `create_issue` does not exist |
| `jira` | the connected Jira/Atlassian MCP's create-issue tool, with project, issue type, summary, description, labels, parent |
| `github` | write the body to a temp file, then `gh issue create --title "<title>" --body-file <tmp> [--label …] [--assignee …]`; never a HEREDOC |
| `file` | write `<spec-dir>/<YYYY-MM-DD>-<slug>.md` with frontmatter (`title`, `status: todo`, `labels`, `assignee`, `due`) and the description as the body; never overwrite, bump to `-v2`, `-v3` on a collision |

Report the identifier and its URL (`file` reports the absolute path instead, since files have no URL).

## Edge Cases

| Situation | Action |
|-----------|--------|
| Input too vague | Ask targeted follow-up before drafting |
| No work source resolves and the user declines to pick one | Stop: nothing is created |
| Resolved source is `inline` | Stop with Step 0's message |
| Linear configured but its MCP shows only `authenticate` | Stop with Step 0's connect message |
| User mentions parent issue | Linear: `get_issue` + `parentId`; Jira: parent key; others: Context line |
| User mentions "blocked by" / "blocks" | Linear fields, otherwise Context lines |
| User mentions URL | Linear `links`, otherwise a Links section |
| Video/timestamp mentioned | Add "Video timestamp: MM:SS" to Context |
| User wants edits after preview | Apply changes, re-preview |
| API call fails (non-critical) | Continue with field unset, note in preview |
| 50+ projects in workspace | Use `<LINEAR_PREFIX>list_projects(query=...)` (Linear) or a filtered search (Jira), never dump the full list |

## Common Mistakes

| Mistake | Correct |
|---------|---------|
| Hardcoding Linear | Step 0 resolves the project's source; Linear is one row of each table |
| Asking which tracker every time | Resolve from config / CLAUDE.md / auto-detect first; ask once only when that fails, and offer to persist |
| Skipping scoping because the request "looks clear" | Phase 1 runs for every ticket. A complete request passes through in one exchange; it is never skipped on judgment |
| Abbreviating the scoping contract to "brainstorm this first" | Pass all four clauses. Without the terminal-state clause, brainstorming reads scope approval as approval to start building |
| Putting brainstorming's codebase findings in the ticket | They ground the acceptance criteria and stay out of the body. Step 5's diagnostic-only policy still governs |
| Skipping scope selection on Linear or Jira | ALWAYS ask the user to pick a project there |
| Showing fields the source doesn't have | Leave them out of the preview entirely |
| Dumping full project list | Use a query to filter server-side |
| Using wrong template structure | Context/Requirements/AC for features+bugs; adapt for spikes/chores |
| Setting due date without user asking | Only set when user mentions a deadline |
| Hardcoding "Todo" status | Use the source's configured default entry status |
| Not fetching labels | Fetch labels and suggest 1-3 relevant ones |
| Dumping code blocks as context | Code must be diagnostic (stack trace, repro, error), never descriptive (current impl) |
| Vague acceptance criteria | Specific, testable ("Returns 200 for valid payload") |
| Skipping preview | ALWAYS show preview before creating |
