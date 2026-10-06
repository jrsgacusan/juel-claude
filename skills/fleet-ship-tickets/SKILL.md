---
name: fleet-ship-tickets
description: Use to ship several work items around the clock on the Sphere fleet. Runs locally - selects items from the project's work source (Linear, Jira, GitHub, spec files), drafts one brief per item for your approval, then hands the batch to one fleet driver chat that runs each item through /juel:ship-ticket --unattended in its own fleet worktree, then through a second-model review of the draft, mark-ready and babysitting until the PR is approved, green and verified on its exact head, with a ledger, capacity gates and quiet hours. "status" reads the driver's ledger, shows the PRs ready for your merge and flushes held actions. Never merges. Triggers "ship my tickets on the fleet", "run these overnight", "/juel:fleet-ship-tickets".
metadata:
  requires:
    mcp:
      - id: fleet
        hard: true
        why: every phase talks to the fleet MCP (chat_create, chat_read, chat_status, chat_message, chat_resume, chats_list)
        check: none
      - id: linear
        hard: false
        why: phase 2 lists and fetches items, and status mode flushes held status writes, when Linear resolves as the project's work source
        check: none
        fallback: the project's other configured source is used; items can also be pasted as refs or spec paths
    context:
      - id: git-repo
        hard: true
        why: briefs carry the branch and base branch resolved from this repo's conventions
        check: "git rev-parse --show-toplevel"
      - id: interactive-user
        hard: true
        why: brief approval and open-loop flushing need explicit yes answers via AskUserQuestion
      - id: work-source-list-capable
        hard: false
        why: phase 2 lists the user's open items
        check: none
        fallback: ask for refs or spec paths directly, one per line
    skills:
      - id: juel:ship-ticket
        hard: true
        why: it is the command every fleet worker runs, with --unattended --brief
---

# Fleet Ship Tickets

Hand a batch of approved work items to the Sphere fleet so they keep moving while you are away. This
skill is the **local intake**: it picks the items, gets your approval on one brief per item, and
creates one fleet **driver chat** that coordinates everything else on the fleet VM. The driver
dispatches one worker per item (`/juel:ship-ticket --unattended --brief …`) into its own fleet
worktree, keeps `ledger.md` and `open-loops.md`, and respects its capacity gates and quiet hours.
Each item then goes through the same steps as the 24/7 setup this follows: the worker opens a
**draft** PR, a second model reviews the whole draft (NOT SAFE sends it back to the worker, up to
three rounds), the worker marks it ready once and babysits it through review, and the driver
verifies it is approved and green on the exact head. **You merge it.** You are pulled in earlier only
when a rule says so: an escalation becomes an open loop with a written question.

`/juel:fleet-ship-tickets status` reads the driver's ledger, lists the PRs waiting for your merge
and flushes held actions with you.

**Announce:** "Using juel:fleet-ship-tickets to hand these items to a fleet driver."

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
| Sphere fleet MCP | mcp | HARD | **none — render as `?`** | STOP → add the fleet HTTP MCP to this project's `.mcp.json`, restart the session |
| Linear MCP | mcp | SOFT | **none — render as `?`** | the project's other configured source is used; items can also be pasted as refs or spec paths |
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP |
| AskUserQuestion | context | HARD | always available interactively | STOP → brief approval is mandatory |
| work source with `list` | context | SOFT | **none — render as `?`** | ask for refs or spec paths directly, one per line |
| juel:ship-ticket | skill | HARD | ships with this plugin | STOP |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Preflight — resolve the fleet MCP prefix and the fleet project id
2. Resolve the work source and select items
3. Fetch each item in full and normalize it
4. Draft one brief per item and get each approved (MANDATORY — never skipped)
5. Resolve capacity, models and quiet hours
6. Create the fleet driver chat with the driver rules and the approved briefs
7. Report the driver chat and what was handed over

In `status` mode the phases are instead:

1. Preflight — resolve the fleet MCP prefix and find the driver chat
2. Read the driver's state, ledger and open loops
3. Offer to resume a stopped driver
4. Flush open loops the local session can perform, each with a yes
5. Report

## Arguments

| Argument | Default | Description |
|---|---|---|
| `[refs…]` | select interactively | Work item refs or spec paths to hand over; skips the selection list |
| `status [driver-chat-id]` | newest driver chat named `juel ship …` | Status mode instead of intake |

Usage: `/juel:fleet-ship-tickets`, `/juel:fleet-ship-tickets SAVI-1162 SAVI-1170`, `/juel:fleet-ship-tickets status`

## Configuration

Read from `<repo>/.claude/workflow.json` (`.claude/workflow.local.json` deep-merged over it):

```jsonc
"fleet": {
  "projectId": "<uuid>",                                  // asked once, offered to persist
  "maxParallel": 3,                                       // build pool, default 3
  "maxInReview": 5,                                       // review + babysitting pool, default 5
  "reviewer": { "provider": "codex", "model": "default", "effort": "high" },   // the second model; claude with another model if codex is not offered
  "driver": { "model": "default", "effort": "high" },     // default model; never a top-tier one unless the user asks
  "worker": { "model": "default", "effort": "high" },
  "quietHours": { "tz": "Asia/Manila", "start": "22:00", "end": "07:00" }   // absent = off
}
```

The work source resolves the way every juel skill resolves it: an explicit argument →
`workflow.local.json` / `workflow.json` `tracker` → a `## Work Source` block in CLAUDE.md or
AGENTS.md (`- type:` / `- project:`) → the legacy `## Linear Worktrees Config` block → auto-detect →
ask once and offer to persist.

## Workflow

### Step 1: Preflight

**Resolve the fleet MCP prefix.** The server's tools appear under whatever name the project's
`.mcp.json` gave it, usually `mcp__fleet__`. Use the prefix that exposes a **domain tool**
(`agents_list`), not only `authenticate`/`complete_authentication`. Every fleet call below is
written `<FLEET>tool_name`. No prefix exposes `agents_list` → STOP: "The fleet MCP is not connected
in this session. Add it to this project's .mcp.json (https://fleet.spheretechnology.com/api/mcp with
your personal access token), restart the session, then re-run."

**Resolve `fleet.projectId`.** Config first. Otherwise: there is no `projects_list` tool, so call
`<FLEET>chats_list(scope: "global")` and collect the distinct non-null `projectId` values, then ask
the user which fleet project is this repo (or to paste the id). Confirm the pick with
`<FLEET>worktrees_list(projectId)`, then offer to persist it to `.claude/workflow.json`. Never guess
a project: a worker in the wrong project ships the wrong repo.

`agents_list` also tells you which models the VM offers; keep it for Step 5.

### Step 2: Select items

Resolve the work source (Configuration above). With refs or spec paths as arguments, use those.
Otherwise call the source's `list` for open `todo` items assigned to the user, using that provider's
row:

| Provider | `list` | `fetch` |
|---|---|---|
| `linear` | resolve `LINEAR_PREFIX` (`mcp__linear__` or `mcp__claude_ai_Linear__`, whichever exposes a domain tool), then `<LINEAR_PREFIX>list_issues(assignee: "me", project: <id>, state: "Todo")` | `<LINEAR_PREFIX>get_issue(id: <ref>)` |
| `jira` | the connected Jira/Atlassian MCP's JQL search: `assignee = currentUser() AND project = <key> AND statusCategory = "To Do"` | the MCP's get-issue tool |
| `github` | `gh issue list --assignee @me --state open --json number,title,url,labels` (skip `status:in-progress` / `status:in-review`) | `gh issue view <n> --json number,title,body,url,labels` |
| `file` | `*.md` in the spec directory whose status is `todo` or absent | read the file |

No `list` (or `inline`): ask for refs or spec paths, one per line. Present the items and let the user
pick with AskUserQuestion (multiSelect). **Do not invoke `juel:daily-worktrees`**: it creates local
worktrees, and these items get fleet worktrees instead.

### Step 3: Fetch and normalize

Fetch every selected item in full **here, locally**: the fleet VM may not have this project's
tracker connector, so the brief must carry the whole item. Normalize each to: `ref` (null when the
source has none), `slug` (kebab-case from the title, ≤ 6 words), `title`, `url` (omit when absent),
`source`, `labels`, description, acceptance criteria. The item's name everywhere after this is its
ref, or its slug when the ref is null — never `null`, never empty.

**Names are unique within the batch.** Two items with no ref and the same slug would share a ledger
row, a branch and a brief. Before Step 4, give every repeat of a slug a suffix (`-2`, `-3`, … in
selection order) and use that final name for the branch, the brief, the ledger row and every report
line.

### Step 4: Draft and approve briefs (MANDATORY)

Resolve the repo's conventions once: remote (one → it, else `origin`, else ask), base branch
(`config.baseBranch` → `git config --get claude.baseBranch` → `git symbolic-ref --short
refs/remotes/<remote>/HEAD` → first existing of main/master/develop/dev/trunk → ask once), and branch
naming (sample `git for-each-ref --sort=-committerdate --count=60 refs/remotes/<remote>`, take the
modal pattern; default `{type}/{ref-lower}-{slug}`, and `{type}/{slug}` when the ref is null; type
is `fix` for bug/fix/error, `refactor`, `chore`, else `feat`).

For each item, read enough of the codebase to propose an approach, then draft its brief:

```markdown
---
juel_brief: 1
item:
  ref: <ref or null>
  slug: <slug>
  title: <title>
  url: <url>            # omit when absent
  source: <source>
  labels: [<labels>]
branch: <branch>
baseBranch: <base>
approved: <iso time, set on approval>
---
## Work item
<description, verbatim>
## Acceptance criteria
- [ ] <one per criterion; when the item has none, ask the user for concrete checks — never invent them>
## Approach
<2-6 sentences: the chosen approach, the components touched>
## Scope
In: <what this item changes>
Out: <what it deliberately does not touch>
```

Show each brief and ask with AskUserQuestion: **Approve / Edit / Drop**. Edit → apply and re-show.
Drop → remove the item from the batch. An approved brief is the worker's contract: the worker
escalates instead of widening it. Zero approved briefs → stop: "Nothing approved, nothing handed
over."

### Step 5: Capacity, models and quiet hours

- `maxParallel` (build pool): config, default 3. `maxInReview` (second-model review and
  babysitting pool): config, default 5. Babysitting mostly waits on reviewers, which is why it has
  its own pool instead of blocking new builds.
- Reviewer: `config.fleet.reviewer`, default provider `codex` with its `default` model at `high`
  effort. If `agents_list` does not offer `codex`, use provider `claude` with a model other than the
  worker's, and say so in the report.
- Driver and worker model/effort: config, default `default` / `high`. Never pick a top-tier model
  unless the user asked for one. A configured model `agents_list` does not offer → ask once.
- Quiet hours: `config.fleet.quietHours`. Absent → ask once: "Set a quiet window (no reviewer pings,
  status changes or messages while you're away)?" with options to set one or leave it off, and offer
  to persist the answer. Render it as `HH:MM-HH:MM@<tz>` or `off`.

### Step 6: Create the driver chat

Read `references/fleet-driver.md`, resolved relative to this skill file's own location
(`../../references/fleet-driver.md`), and build the driver prompt from, in order: that file
verbatim; a `## Batch` section with `projectId`, `maxParallel`, `maxInReview`, quiet hours, worker
`provider: claude` / model / effort, and reviewer provider / model / effort; then every approved brief as its own fenced block, in approval
order.

```
<FLEET>chat_create(
  scope: "project", projectId: <projectId>, mode: "driver", provider: "claude",
  model: <driver model>, effort: <driver effort>, name: "juel ship <YYYY-MM-DD HH:MM>",
  requestId: <fresh uuid>, prompt: <driver prompt>)
```

Generate the `requestId` once (`uuidgen`) and reuse it if the call has to be retried, so a retry
never creates a second driver.

### Step 7: Report

One block: driver chat id and name, the items handed over (item, branch), `maxParallel`,
`maxInReview`, quiet hours, worker / driver / reviewer models. State plainly that **this session is not monitoring the fleet**, that the driver keeps
working while the laptop sleeps, and that `/juel:fleet-ship-tickets status` reads progress and
flushes held actions.

## Status mode

1. **Find the driver.** The argument's chat id, else `<FLEET>chats_list(scope: "project",
   projectId)` → the newest chat whose name starts with `juel ship`.
2. **Read it.** `<FLEET>chat_status(chatId)` for its state, then `<FLEET>chat_message(chatId,
   message: "Print ledger.md and open-loops.md verbatim, then end your turn.")` and read the reply
   with `<FLEET>chat_read`. Show both files.
3. **Stopped or failed driver.** If `chat_status` shows the driver failed or stopped while the ledger
   still has rows in `queued`, `dispatched`, `acked`, `running`, `pr-draft`, `reviewing`, `fixing` or
   `babysitting`, offer
   `<FLEET>chat_resume(chatId)`. The ledger on disk makes a resume safe.
4. **Flush open loops.** For each unticked loop this session can perform, ask the user (one
   AskUserQuestion per loop, Yes / Skip) before doing it:
   - a status write → the source's `update_status` from Step 2's provider, locally;
   - "merge PR #<n> — approved, green, head <sha>" → show the PR URL and check it with
     `gh pr view <n> --json state,headRefOid`. Never merge it: the user merges in GitHub. When the
     state is `MERGED`, tell the driver `MERGED item=<item>` so it marks the row `done`. When the
     head moved since the loop was written, say so: the PR changed after it was verified;
   - "open a draft PR from <compare-url>" (a worker had no `gh`) → show it; the user opens it;
   - anything else (a decision, an escalation) → show it; the user decides, and you relay the answer
     with `<FLEET>chat_message` only when they ask you to.
   Then tell the driver which loops were closed so it ticks them.
5. **Report** counts per state, loops closed, loops still open.

## Hard rules

- **Never merge a PR**, from this skill or by asking the driver to. The flow ends at "ready for
  your merge"; the merge is always the user's click in GitHub.
- Brief approval is never skipped, batched into one yes, or inferred from an earlier batch.
- Never hand over an item whose brief was not approved in this run.

## Common mistakes

- **Hardcoding `mcp__fleet__`.** Resolve the prefix by a domain tool; the server name is whatever the
  project's `.mcp.json` calls it.
- **Guessing the fleet project.** Ask and confirm; a wrong `projectId` ships the wrong repo.
- **Letting the worker fetch the ticket.** The brief carries the whole item, because the VM may not
  have the tracker connector.
- **Using `null` as an item name.** Items without a ref are named by their slug.
- **Invoking `juel:daily-worktrees` for selection.** It creates local worktrees nobody uses.
- **Polling the driver from this session.** Intake ends at Step 7; progress is read on demand with
  `status`.

## Edge cases

| Situation | Handling |
|---|---|
| Fleet MCP only shows `authenticate` | STOP with Step 1's message; nothing is created |
| No `projectId` in config and no project chats exist | Ask the user to paste the id from the fleet web app |
| An item already has a fleet worktree for its branch (`worktrees_list`) | Report it and drop the item from the batch; never create a second one |
| The driver chat create call errors | Retry once with the same `requestId`; still failing → report and stop, nothing was handed over |
| Every brief dropped | Stop with "Nothing approved, nothing handed over." |
| `status` finds no driver chat | Say so and stop |
