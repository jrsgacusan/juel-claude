# Work-source interface — authoring source of truth

This file is **not** read at runtime, for the same reason as `references/preflight.md` and
`references/strict-protocol.md`: no `SKILL.md` links to it, and progressive disclosure (a sibling
file loaded only if the model chooses to) cannot deliver an "always resolve work items this way"
guarantee. It exists so Phase C's skills (`start`, `daily-worktrees`, `ship-ticket`,
`create-linear-ticket`, and later `compact-context`/`cmux-review-pr`) share one canonical
work-item shape, one normalized status vocabulary, one provider capability table, and — critically
— **one set of Linear tool names**, instead of each skill re-deriving (and disagreeing on) its own.

**Read this file's Linear section before writing or editing any Linear call site.** It replaces the
bare, non-resolving `linear__*` prefix used throughout the current skill set (defect 1) and the
`save_issue`/`update_issue` disagreement between `ship-ticket` and `daily-worktrees` (defect 2).

---

## 1. The work-item interface

Skills consume a work item, never a tracker. Field list derived from what `skills/start/SKILL.md`,
`skills/ship-ticket/SKILL.md` and `skills/daily-worktrees/SKILL.md` actually read or write today
(not invented): `start` reads ticket id/description/requirements/AC/dependencies/API-endpoints from
a fetched Linear issue; `ship-ticket` reads the ticket title for the PR title and writes a status
update; `daily-worktrees` lists issues by assignee+project+state, reads id/title, and writes status.

```jsonc
{
  "ref": "SAVI-1162",        // NULLABLE — display/naming token, not a lookup key
  "id": "SAVI-1162",         // provider-native fetch id
  "title": "…",              // the ONLY truly required field
  "slug": "…", "type": "feat",
  "description": "…",
  "requirements": [], "acceptance_criteria": [],   // derived from description
  "status": "todo",          // normalized: todo | in_progress | in_review | done
  "url": "…", "labels": [], "branch_hint": "…", "parent": null,
  "source": "linear"
}
```

| Field | Required? | Consumed by |
|---|---|---|
| `title` | **Yes — the only required field** | all three: PR title (`ship-ticket` phase 8), ticket list rows (`daily-worktrees` phase 5), requirements summary (`start` phase 3) |
| `ref` | **No — NULLABLE** | branch/worktree/spec/plan/PR-title/commit-scope naming (`daily-worktrees` phase 3, `ship-ticket` phases 2/3/8). When null, the segment drops out entirely — never a placeholder string like `"none"` |
| `id` | No | the provider-native lookup key passed back into `fetch`/`update_status` calls (`start` phase 2, `daily-worktrees` phase 7) |
| `slug` | No | branch/worktree name generation (`daily-worktrees` phase 3) |
| `type` | No | branch prefix inference — `feat`/`fix`/`refactor`/`chore` (`daily-worktrees` phase 3) |
| `description` | No | requirements/AC parsing source (`start` phase 3) |
| `requirements` | No | derived from `description`; presented in `start` phase 3's summary |
| `acceptance_criteria` | No | derived from `description` (`## Acceptance Criteria`, `## Done When`, `## Outcome` headings, else `- [ ]` checkboxes); the highest-value derived field — six call sites across `ship-ticket` phases 2 and 7, `start` phase 3, PR body QA instructions |
| `status` | No | normalized read/write target for `update_status` (`daily-worktrees` phases 6–7, `ship-ticket` phase 8) |
| `url` | No | PR-body Linear link section (`ship-ticket` phase 8) |
| `labels` | No | not read by these three skills today; carried for `create-linear-ticket` authoring parity |
| `branch_hint` | No | seeds branch naming when `slug`/`type` are absent |
| `parent` | No | gates the "branch from the parent tip" guidance (spec §7.11); only Linear/Jira expose it |
| `source` | No | which provider produced the item — drives capability-flag branching (§3 below), never branched on by name elsewhere |

## 2. Normalized status enum

```
todo | in_progress | in_review | done
```

Every provider recipe below maps its native status vocabulary onto exactly these four values.
Skills branch only on this enum, never on a provider's native status string.

## 3. Provider capability table

Skills branch on **capability flags, never on a provider name**.

| Provider | fetch | list | update_status | create | url |
|---|:-:|:-:|:-:|:-:|:-:|
| `linear` | Yes | Yes | Yes | Yes | Yes |
| `jira` | Yes | Yes | Needs `statusMap` | Yes | Yes |
| `github` | Yes | Yes | Emulated (label-based) | Yes | Yes |
| `file` | Yes | Dir only | Yes | Yes | No |
| `inline` | Partial | No | No | No | No |

## 4. Per-provider recipes

### 4.1 `linear`

**Tool-name status: every name below is UNVERIFIED against a live tool listing.** This session's
tool set contains zero `mcp__linear__*` or `mcp__claude_ai_Linear__*` tools — MCP connectors bind
at session start, and the `linear` plugin dependency (installed in Task 5) was added after this
session started, so Step 1 of this task's brief ("enumerate tools from a live session") is
mechanically impossible here. **The verified corroboration below is the strongest evidence
available without a restart; it is not a substitute for one.** See the report's explicit
restart-confirmation item.

**Prefix — the connector shape, corroborated locally.**

`~/.claude-personal/plugins/cache/claude-plugins-official/linear/unknown/.mcp.json` (installed in
Task 5) registers the server under the key `linear`, pointed at Linear's own hosted endpoint:

```json
{ "linear": { "type": "http", "url": "https://mcp.linear.app/mcp" } }
```

An MCP server registered under key `linear` is exposed to the model as `mcp__linear__<tool>` —
this is how the Claude Code / plugin tool-naming convention composes server key + tool name, and is
the direct fix for defect 1 (the bare `linear__*` prefix used throughout the current skill set does
not resolve to any real tool).

`~/.claude.json`'s `claudeAiMcpEverConnected` array separately records `"claude.ai Linear"` — this
user has, at some point, also connected Linear via the claude.ai connector (a different binding path
than the plugin). A claude.ai-connector-sourced server is exposed under the composed key
`claude_ai_Linear`, i.e. `mcp__claude_ai_Linear__<tool>`. **Both shapes are corroborated as
genuinely reachable for this user** (one via the installed plugin's `.mcp.json`, one via connector
history), which is why the detection rule below accepts either rather than assuming one.

Grepping `~/.claude.json` for any recorded `mcp__*linear*` tool-call name returned nothing — the
`linear@claude-plugins-official` plugin's own usage counter is `0`, consistent with it never having
been exercised in a prior session. There is no local record of the *tool names themselves*, only of
the *server bindings* — hence Step 2 below relies on external research, not local logs.

**Detection rule (dual-prefix, required regardless of findings):**

```
LINEAR_PREFIX = the first of "mcp__linear__" or "mcp__claude_ai_Linear__" for which any
                tool with that prefix appears in the current session's tool set.
                If neither is present, Linear capability is absent — degrade per §5.
```

Every recipe call below is written as `<LINEAR_PREFIX>get_issue` etc. — substitute whichever
prefix resolved.

**Tool names — externally researched, name-by-name confidence:**

| Operation | Candidate name | Status | Evidence |
|---|---|---|---|
| fetch one issue | `fetch_issue` | UNVERIFIED — two independent primary reports | Real-session bug reports against the actual `mcp.linear.app` endpoint name `fetch_issue` as a working read call: [Cursor Community Forum bug report](https://forum.cursor.com/t/linear-mcp-save-issue-fails-empty-payload-title-is-required-or-invalid-json-when-using-parentid-ticket-style-strings/155803) ("read-only Linear tools like fetch_issue work") |
| fetch one issue (alt. candidate) | `get_issue` | UNVERIFIED — aggregator-catalog only, contradicted by primary evidence | [Fiberplane blog analysis](https://blog.fiberplane.com/blog/mcp-server-analysis-linear/), mcpservers.org agent-skills catalog. These aggregator catalogs may describe a normalized/generic naming scheme rather than Linear's actual hosted server, or may describe one of the many *community* Linear MCP servers (e.g. `jerhadf/linear-mcp-server`, `tacticlaunch/mcp-linear`) rather than Linear's own `mcp.linear.app`. Do not adopt without live confirmation |
| create **or** update an issue | `save_issue` | UNVERIFIED — two independent primary reports, best-evidenced write verb | [Cursor Community Forum bug report](https://forum.cursor.com/t/linear-mcp-save-issue-fails-empty-payload-title-is-required-or-invalid-json-when-using-parentid-ticket-style-strings/155803) and [anthropics/claude-code issue #51674](https://github.com/anthropics/claude-code/issues/51674) both show real users' sessions calling `save_issue` against the live Linear MCP server and hitting real (transport/argument) errors — i.e. the name appears in **production tool-call logs**, not in a marketing/aggregator description. Both reports describe it handling issue creation; whether it also performs status-only updates (Linear's own web UI conventionally uses "save" as the single verb for both new and edited issues, which would make an upsert-style single write tool plausible) is **not confirmed** |
| status write (alt. candidate) | `update_issue` | UNVERIFIED — aggregator-catalog only, no primary-log evidence found | [Fiberplane blog analysis](https://blog.fiberplane.com/blog/mcp-server-analysis-linear/), mcpservers.org, Speakeasy's MCP Gateway catalog. Zero real-session logs found using this name against `mcp.linear.app` (searched specifically) |
| create a comment | `save_comment` | UNVERIFIED — one primary report | [anthropics/claude-code issue #51674](https://github.com/anthropics/claude-code/issues/51674) lists `save_comment` alongside `save_issue` as tool calls made in a real session |
| list issues | `list_issues` | UNVERIFIED — primary report + aggregator agreement | Named directly in [anthropics/claude-code issue #51674](https://github.com/anthropics/claude-code/issues/51674)'s session log, and consistently in every aggregator catalog found. The one name with corroboration from both evidence classes |
| list teams | `list_teams` | UNVERIFIED — primary report + aggregator agreement | Named as a working read call in [the Cursor forum report](https://forum.cursor.com/t/linear-mcp-save-issue-fails-empty-payload-title-is-required-or-invalid-json-when-using-parentid-ticket-style-strings/155803), and in aggregator catalogs |
| list issue statuses | `list_issue_statuses` | UNVERIFIED — aggregator-catalog only | No primary-log sighting found; used by `create-linear-ticket`'s existing Step 3 today (pre-existing, unaudited by this task) |
| list projects | `list_projects` | UNVERIFIED — aggregator-catalog only | Same caveat as above; used by `create-linear-ticket`'s existing Step 2 |

**Resolution of the `save_issue` vs `update_issue` disagreement (defect 2):** `ship-ticket:138`'s
`mcp__linear__save_issue` is **better-evidenced** than `daily-worktrees:110`'s bare
`linear__update_issue` — `save_issue` appears in two independent real production tool-call logs
against the actual `mcp.linear.app` server, while no such log was found for `update_issue` (only
third-party aggregator descriptions, which may not describe this exact server). **Neither is
VERIFIED.** Both skills should converge on `<LINEAR_PREFIX>save_issue` pending live confirmation —
this is a directional call based on the stronger of two unconfirmed candidates, not a fact.

**Recipe:**

```
fetch(ref)        → <LINEAR_PREFIX>fetch_issue(id: ref)
list(filters)     → <LINEAR_PREFIX>list_issues(assignee: "me", project: <id>, state: "Todo")
update_status(id, status) → map normalized status to Linear's native state name, then
                     <LINEAR_PREFIX>save_issue(id: id, state: <native-state-name>)
create(fields)    → <LINEAR_PREFIX>save_issue(title: …, teamId: …, description: …, …)
url(item)         → item.url as returned by fetch/list — Linear issues always carry one
```

Status mapping (normalized → Linear native, team-configurable — resolve via `list_issue_statuses`
rather than hardcoding): `todo` → team's default entry status, `in_progress` → "In Progress",
`in_review` → "In Review", `done` → team's completed state.

### 4.2 `jira`

Not implemented in v1.0 (deferred — see spec §14). Capability table above reflects intended shape:
`fetch`/`list`/`create`/`url` map onto Jira's REST API directly; `update_status` needs an explicit
`statusMap` (config) since Jira workflow states are project-specific and have no fixed vocabulary.

### 4.3 `github`

Not implemented in v1.0. `update_status` is **emulated** via labels (e.g. `status:in-progress`)
since GitHub Issues has only an open/closed axis, no native todo/in-progress/in-review distinction
— a convention the user must maintain by hand (spec §7.11). `fetch`/`list`/`create`/`url` map onto
`gh issue view` / `gh issue list` / `gh issue create` / the issue's HTML URL.

### 4.4 `file`

A local spec file (`docs/.superpowers/specs/<date>-<slug>.md` or user-pointed path).
`fetch` reads the file; `list` only works for a directory of such files (not a single file); `create`
writes a new one; `update_status` rewrites a status marker inside the file (e.g. frontmatter or a
`Status:` line); `url` is unsupported — files have no canonical link.

### 4.5 `inline`

Conversational prose pasted by the user, with no persistent backing store. `fetch` is partial (the
prose itself, not re-fetchable by id); `list`/`create`/`update_status`/`url` are all unsupported.
Per spec §7.8, `inline` **auto-promotes to `file`** on first use in a worktree — requirements get
written to `${docsRoot}/specs/<date>-<slug>.md`, which restores `update_status` and survives
`/compact`.

## 5. The degradation contract

None of the following ever fail a phase:

- **Missing `update_status`** — print exactly one line and continue:
  `Status: skipped — provider '<name>' has no status field configured`
  (or the provider-specific reason, e.g. "Linear MCP unavailable"). Never retry, never block the
  remaining phases on it.
- **Missing `url`** — omit the PR-body link section entirely rather than printing a dead
  placeholder (no `Linear: [none]` or `Linear: N/A` line — the section itself does not appear).
- **Missing `list`** — prompt the user for refs directly (paste ticket IDs / point at a spec
  directory) rather than failing the phase that needed the list.

## 6. Authoring templates (extracted from `create-linear-ticket`, provider-neutral)

Extracted verbatim from `skills/create-linear-ticket/SKILL.md` Steps 4–6 so the description
templates, AC rules, code-sample policy, and mandatory preview step are available to any future
provider-neutral authoring flow (spec §7.11: a thin `create-work-item` dispatcher for other
providers is deferred past v1.0, but its authoring half should not have to be re-derived from
scratch when that dispatcher is built). **`create-linear-ticket` itself is not modified by this
task** — a later task points it at this file instead of carrying this content inline.

### 6.1 Code samples policy — diagnostic only, never descriptive

| Include | Don't include |
|---------|---------------|
| Stack traces / error output | Current implementation ("here's UserService") |
| Minimal reproduction (the trigger) | Large blocks of existing code |
| API contract examples (expected I/O shapes) | Implementation suggestions |
| Before/after behavioral deltas | AI-scanned codebase dumps |

**Size limits:** 1-3 lines inline in Context, 4-10 lines in a code block, 11+ lines **never** —
reference the component instead.

### 6.2 Description templates — adapt based on ticket type

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

For **trivial tickets** (fix typo, rename variable): a one-line description is fine. Skip the
template.

### 6.3 Acceptance-criteria rules

Each item must be verifiable — no vague language like "works correctly." State the observable
outcome.

### 6.4 Mandatory preview step (never skipped)

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
This step is MANDATORY for any provider-neutral authoring flow, exactly as it is today for
`create-linear-ticket` — never create a work item without showing this preview first.
