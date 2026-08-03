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
| `labels` | No | read by `daily-worktrees` phase 3's branch-type inference table (`skills/daily-worktrees/SKILL.md:119`: "Title/labels contain 'bug', 'fix', 'error'" → `fix`); also carried for `create-linear-ticket` authoring parity |
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

**Tool names VERIFIED** — ground truth supplied by the user from a live session, 2026-08-03,
superseding this task's original external-research round entirely (that round is preserved below
only as one recorded lesson; every name it produced has been checked against the live listing).

**Two Linear MCP connections exist for this user, in different states:**

- `plugin:linear` (the plugin dependency installed in Task 5, registered under key `linear` at
  `https://mcp.linear.app/mcp` per `~/.claude-personal/plugins/cache/claude-plugins-official/linear/unknown/.mcp.json`)
  — **installed but NOT authenticated.** It exposes only `authenticate` and
  `complete_authentication`; none of its domain tools (issues, projects, comments, etc.) are
  present until the user completes that OAuth flow. **This is a distinct third state from
  "absent"** — a check that only tests "does any `mcp__linear__*` tool exist" will false-positive
  on this connector pre-authentication, because `authenticate`/`complete_authentication` themselves
  match that prefix.
- `claude.ai Linear` (the claude.ai connector, previously corroborated only indirectly via
  `~/.claude.json`'s `claudeAiMcpEverConnected` array — now confirmed directly) — **authenticated,
  full tool set.** This is the currently *active* source for every verified name below, exposed
  under the composed prefix `mcp__claude_ai_Linear__<tool>`.

**The dual-prefix detection rule is load-bearing, not defensive — unchanged from the original
design, now confirmed necessary rather than merely precautionary.** The active prefix for this user
today is `mcp__claude_ai_Linear__*`, not `mcp__linear__*` — the opposite of what a naive reading of
"the plugin dependency is installed, so use its prefix" would assume. A skill must not hardcode
either prefix, and must not treat presence of the `mcp__linear__` namespace alone as proof the
plugin connector is usable.

**Detection rule (dual-prefix, revised to account for the present-but-unauthenticated state):**

```
LINEAR_PREFIX = the first of "mcp__linear__" or "mcp__claude_ai_Linear__" for which a DOMAIN
                tool — i.e. anything other than authenticate / complete_authentication — with
                that prefix appears in the current session's tool set.
                If "mcp__linear__" is present but exposes only authenticate/
                complete_authentication, treat it as present-but-unauthenticated, NOT as
                satisfying the Linear dependency — fall through to "mcp__claude_ai_Linear__".
                If neither prefix has a domain tool, Linear capability is absent.

LINEAR_STATE = one of three values, carried alongside LINEAR_PREFIX and kept distinguishable
               all the way to the degrade message a skill actually prints — never collapsed
               into a single "unavailable" bucket:
                 "working"     — LINEAR_PREFIX resolved to a domain tool. Proceed normally.
                 "auth_needed" — "mcp__linear__" exposes only authenticate/
                                 complete_authentication, AND "mcp__claude_ai_Linear__" has
                                 no domain tool either. Degrade per §5's auth-needed message,
                                 NOT the generic absent message.
                 "absent"      — neither prefix appears at all. Degrade per §5's generic
                                 absent message.
```

A downstream preflight table renders these three differently: `working` → proceed / `✓`,
`auth_needed` → its own line (never folded into `✗` or the generic `!`), `absent` → `✗`/`!` per
`references/preflight.md`'s existing symbol vocabulary.

Every recipe call below is written as `<LINEAR_PREFIX>get_issue` etc. — substitute whichever
prefix resolved.

**Tool names — VERIFIED (live tool listing supplied by the user, 2026-08-03):**

| Operation | Name | Status | Source |
|---|---|---|---|
| fetch one issue | `get_issue` | VERIFIED | live tool listing, 2026-08-03 |
| get issue status | `get_issue_status` | VERIFIED | live tool listing, 2026-08-03 |
| get project | `get_project` | VERIFIED | live tool listing, 2026-08-03 |
| get team | `get_team` | VERIFIED | live tool listing, 2026-08-03 — needed for `create-linear-ticket` team resolution |
| get user | `get_user` | VERIFIED | live tool listing, 2026-08-03 |
| list issues | `list_issues` | VERIFIED | live tool listing, 2026-08-03 |
| list projects | `list_projects` | VERIFIED | live tool listing, 2026-08-03 |
| list teams | `list_teams` | VERIFIED | live tool listing, 2026-08-03 |
| list users | `list_users` | VERIFIED | live tool listing, 2026-08-03 — needed for `create-linear-ticket` assignee resolution |
| list comments | `list_comments` | VERIFIED | live tool listing, 2026-08-03 |
| list cycles | `list_cycles` | VERIFIED | live tool listing, 2026-08-03 — needed for `create-linear-ticket` cycle field |
| list issue statuses | `list_issue_statuses` | VERIFIED | live tool listing, 2026-08-03 |
| list issue labels | `list_issue_labels` | VERIFIED | live tool listing, 2026-08-03 — needed for `create-linear-ticket` labels field |
| create **or** update an issue | `save_issue` | VERIFIED | live tool listing, 2026-08-03 — `save_*` is confirmed upsert: creates when no matching issue is targeted, updates when one is |
| create **or** update a comment | `save_comment` | VERIFIED | live tool listing, 2026-08-03 — **never call automatically; see the mandatory confirmation rule in §5** |
| delete a comment | `delete_comment` | VERIFIED | live tool listing, 2026-08-03 |

`update_issue` **does not exist.** The defect-2 disagreement is fully resolved, not directional.

**A recorded lesson for anyone revisiting this file — `fetch_issue` was wrong.** The original
research round weighted two real production error-log sightings (a Cursor Community Forum bug
report and a GitHub issue, both showing users hitting real errors against Linear's MCP server) over
third-party aggregator catalogs, and concluded the fetch-one-issue tool was named `fetch_issue`.
**The live listing confirms it is `get_issue`** — the aggregator catalogs that round downgraded
("may describe a different server") were right on this specific name. The lesson: a forum poster's
own prose shorthand for "the read call that fetched my issue" can look exactly like a literal
tool-call name without being one — evidence embedded in human prose is not automatically more
reliable than a catalog's structured listing. Weight a machine-rendered tool-call trace over a
prose description of one, and weight a live listing over both. This file no longer carries the name
`fetch_issue` anywhere.

**Resolution of the `save_issue` vs `update_issue` disagreement (defect 2) — CONFIRMED, not
directional.** `ship-ticket:138`'s `mcp__linear__save_issue` was the correct verb all along (modulo
the prefix defect, which the dual-prefix rule above fixes); `daily-worktrees:110`'s `update_issue`
does not exist as a tool on Linear's MCP server. Both skills converge on `<LINEAR_PREFIX>save_issue`.
`save_issue` is confirmed to perform both create and update.

**Recipe:**

```
fetch(ref)        → <LINEAR_PREFIX>get_issue(id: ref)
list(filters)     → <LINEAR_PREFIX>list_issues(assignee: "me", project: <id>, state: "Todo")
update_status(id, status) → map normalized status to Linear's native state name, then
                     <LINEAR_PREFIX>save_issue(id: id, state: <native-state-name>)
create(fields)    → <LINEAR_PREFIX>save_issue(title: …, teamId: …, description: …, …)
url(item)         → item.url as returned by fetch/list — Linear issues always carry one
comment(id, body) → <LINEAR_PREFIX>save_comment(issueId: id, body: body) — subject to the
                     mandatory per-instance confirmation rule in §5; never automatic
```

Status mapping (normalized → Linear native, team-configurable — resolve via `list_issue_statuses`
rather than hardcoding): `todo` → team's default entry status, `in_progress` → "In Progress",
`in_review` → "In Review", `done` → team's completed state.

**Remaining caveat — an auth-state check, not a naming gap.** `plugin:linear` requires the user to
complete `authenticate` → `complete_authentication` before any domain tool appears. A session or
machine that relies on the plugin connector rather than the claude.ai connector will see only
`authenticate`/`complete_authentication` under `mcp__linear__*` until the user authorizes it. The
tool *names* in the table above are no longer in question; whether a *given session* can reach them
through the plugin connector specifically still depends on that session's own auth state, and must
be checked (or degraded around, per the detection rule above) independently every time.

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
  (or the provider-specific reason — for `linear` specifically, use the `LINEAR_STATE`-keyed
  message below, never the generic phrase unqualified). Never retry, never block the remaining
  phases on it.
- **Missing `url`** — omit the PR-body link section entirely rather than printing a dead
  placeholder (no `Linear: [none]` or `Linear: N/A` line — the section itself does not appear).
- **Missing `list`** — prompt the user for refs directly (paste ticket IDs / point at a spec
  directory) rather than failing the phase that needed the list.

**Linear degrade messages, keyed by `LINEAR_STATE` (§4.1) — the two non-`working` states print
different lines, wired here so a reader of this section alone reaches the right one without also
reading the §4.1 prose:**

| `LINEAR_STATE` | One-line message actually printed |
|---|---|
| `auth_needed` | `Status: skipped — Linear plugin is installed but not authorized. Run the plugin's authenticate tool, then restart the session so its tools bind.` |
| `absent` | `Status: skipped — Linear MCP unavailable.` |
| `working` | (no degrade message — the call proceeds) |

The `auth_needed` message is never replaced by the generic `absent` line, and vice versa — a user
whose only problem is an unauthorized plugin must never be told Linear is missing, because the fix
(`authenticate`, then restart) is a completely different action from installing or reconnecting a
missing provider. Any skill or preflight table that surfaces a Linear degrade message must read
`LINEAR_STATE` and select the matching row above, not print a single hardcoded string for both
cases.

**Standing user constraint — comment posting requires explicit per-instance confirmation.** No
Linear comment may be posted without the user's explicit go-ahead for that specific instance. Any
call to `<LINEAR_PREFIX>save_comment` (§4.1) must be preceded by an explicit confirmation prompt
naming the issue and the comment text — it must never be automatic, never inferred from an earlier
blanket "yes," and never fired as a side effect of another operation (e.g. a status update, a PR
open, or a worktree setup must never silently also drop a comment). This is a hard rule, not a
capability-flag default; it applies even when the provider's `create`/`update_status` flags are
otherwise satisfied.

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
