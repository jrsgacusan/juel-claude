---
name: ship-tickets
description: Use to ship several work items unattended on this Mac - selects items from the project's work source (Linear, Jira, GitHub, spec files), gets one brief per item approved, then this session coordinates them through Orca, 3 at a time from a queue - build with /juel:ship-ticket --unattended, a second-model review of the draft PR, fixes, mark-ready and babysitting - until each PR is approved, green and verified on its exact head. Keeps the Mac awake, holds reviewer-facing actions in quiet hours, pulls you in only on escalations. Never merges. Triggers "ship my tickets", "run these unattended", "work through my queue", "/juel:ship-tickets".
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: intake lists and fetches items when Linear resolves as the project's work source
        check: none
        fallback: the project's other configured source is used; items can also be pasted as refs or spec paths
    cli:
      - id: orca
        hard: true
        why: every stage is an Orca orchestration task with a supervised worker
        check: "resolve_bin orca against PATH, then the app-bundle candidate"
      - id: gh
        hard: true
        why: workers open and babysit PRs, and the coordinator verifies the exact head
        check: "gh auth status"
      - id: git
        hard: true
        why: worktree branch renames and the shared state directory under the git common dir
        check: "command -v git"
      - id: codex
        hard: false
        why: the second-model reviewer runs as a codex worker
        check: "command -v codex"
        fallback: the reviewer runs as a claude worker on a model other than the builders'
    context:
      - id: git-repo
        hard: true
        why: worktrees, briefs and the batch state live with this repo
        check: "git rev-parse --show-toplevel"
      - id: orca-runtime
        hard: true
        why: the run, tasks and workers live in the Orca runtime
        check: "orca status reports runtimeReachable: true and graphState: ready"
      - id: orca-repo-registered
        hard: true
        why: worktree create needs this repo's Orca id
        check: "orca repo list contains this repo's path"
      - id: orca-terminal
        hard: true
        why: run-create binds the orchestration run to the calling terminal, which must be an Orca terminal
        check: "ORCA_TERMINAL_HANDLE is set"
      - id: interactive-user
        hard: true
        why: brief approval, relayed worker questions and open-loop decisions use AskUserQuestion
      - id: work-source-list-capable
        hard: false
        why: intake lists the user's open items
        check: none
        fallback: ask for refs or spec paths directly, one per line
    skills:
      - id: juel:ship-ticket
        hard: true
        why: build and fix stages run it with --unattended --brief (and --fix-review)
      - id: juel:babysit-pr
        hard: true
        why: the babysit stage runs it with --unattended --mark-ready
      - id: juel:receive-review-and-execute
        hard: true
        why: babysit-pr remediates every review round through it with --unattended
---

# Ship Tickets

Ship a batch of work items while you are away from the keyboard. You approve one brief per item;
then **this session is the coordinator**. Each item moves through its stages as separate Orca
workers: build, a second-model review of the draft PR, fixes when the review says NOT SAFE, then
mark-ready and babysitting until the PR is approved. The coordinator verifies the exact head and
puts "merge PR #n" in front of you. **You merge.** Workers report straight back to this session, so
escalations and questions reach you while they are fresh. It follows the artifact "My 24/7 Agent
Setup": draft first, review the whole draft, mark ready once, verify the exact head, and keep
everything important in files.

**Announce:** "Using juel:ship-tickets to coordinate these items through Orca."

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
| Linear MCP | mcp | SOFT | **none — render as `?`** | the project's other configured source is used; items can also be pasted as refs or spec paths |
| orca | cli | HARD | `resolve_bin orca` against PATH, then the app-bundle candidate | STOP → https://www.onorca.dev |
| gh | cli | HARD | `gh auth status` | STOP → `gh auth login` |
| git | cli | HARD | `command -v git` | STOP |
| codex | cli | SOFT | `command -v codex` | the reviewer runs as a claude worker on a model other than the builders' |
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP |
| reachable Orca runtime | context | HARD | `orca status` reports `runtimeReachable: true` and `graphState: ready` | STOP → run `orca open`, then re-run |
| repo registered with Orca | context | HARD | `orca repo list` contains this repo's path | offer `orca repo add` once, then continue |
| running in an Orca terminal | context | HARD | `[ -n "$ORCA_TERMINAL_HANDLE" ]` | STOP → start Claude Code from an Orca terminal and re-run there |
| AskUserQuestion | context | HARD | always available interactively | STOP → brief approval is mandatory |
| work source with `list` | context | SOFT | **none — render as `?`** | ask for refs or spec paths directly, one per line |
| juel:ship-ticket, juel:babysit-pr, juel:receive-review-and-execute | skill | HARD | ship with this plugin | STOP |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Preflight — resolve binaries, the Orca runtime, this repo's Orca id and the Orca terminal
2. Resolve the work source and select items
3. Fetch each item in full and normalize it
4. Draft one brief per item and get each approved (MANDATORY — never skipped)
5. Resolve pools, models and quiet hours, and write the batch directory
6. Start the run: caffeinate and `run-create`
7. Coordinate until every item is ready, done, escalated or failed
8. Report the merge list and the open loops

`resume` runs phases 1, 6 (bind with `run-use` instead of `run-create`), 7 and 8. `status` runs
phase 1 and prints the ledger and open loops.

## Arguments

| Argument | Default | Description |
|---|---|---|
| `[refs…]` | select interactively | Work item refs or spec paths for the batch |
| `resume [batch-id]` | newest batch | Rebind to a batch's run and keep coordinating |
| `status [batch-id]` | newest batch | Print the ledger, open loops and merge state |

Usage: `/juel:ship-tickets`, `/juel:ship-tickets SAVI-1162 SAVI-1170`, `/juel:ship-tickets resume`, `/juel:ship-tickets status`

## Configuration

Read from `<repo>/.claude/workflow.json` (`.claude/workflow.local.json` deep-merged over it):

```jsonc
"ship": {
  "maxParallel": 3,                                      // build pool, default 3
  "maxInReview": 3,                                      // review + babysit pool, default 3
  "worker":   { "agent": "claude", "model": "opus",    "effort": "high" },
  "reviewer": { "agent": "codex",  "model": "default", "effort": "high" },
  "quietHours": { "tz": "Asia/Manila", "start": "22:00", "end": "07:00" }   // absent = off
}
```

Model ids come from the CLIs, never from memory: when a configured model is not offered by the
agent's own model listing, ask once. A model of `default` means: pass neither `--model` nor `--effort`, and let the agent use its own default. Never pick a top-tier model (described as
frontier, toughest or most capable) unless the user asked for one; `opus` is the mid tier.

The work source resolves the way every juel skill resolves it: an explicit argument →
`workflow.local.json` / `workflow.json` `tracker` → a `## Work Source` block in CLAUDE.md or
AGENTS.md (`- type:` / `- project:`) → the legacy `## Linear Worktrees Config` block (read whenever
no `tracker.type` resolved) → auto-detect, exactly one candidate → ask once and offer to persist.

## State

Everything the run needs survives in files, so a compacted or restarted coordinator carries on.

`BATCH` is an **absolute** path, computed once in Step 5 and used in every prompt:
`$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/juel/ship/<batch-id>` (`<batch-id>` =
`YYYYMMDD-HHMM`). From the main checkout `git rev-parse --git-common-dir` prints a relative `.git`,
which a worker in another worktree cannot resolve; `pwd -P` fixes that. Shared by every worktree,
never committed:

- `batch.json` — Orca run id, repo id, pools, quiet window, worker and reviewer agents and models,
  caffeinate pid
- `ledger.md` — one row per item:
  `| item | worktree | state | stage | round | task | dispatch | restarts | pr | head | cursor | verify | updated |`
- `processed.log` — one line per message already handled: `<message id> <dispatch> <iso time>`
- `open-loops.md` — `- [ ] <iso time> <item> — <action> — <reason> — notify: pending|sent|print-only`
- `questions.md` — one line per worker question relayed to the user: `<message id> <item> <deadline> open|answered|expired`
- `briefs/<item>.md`, `reviews/<item>-r<k>.md` (each reviewer's whole output),
  `reviews/<item>-r<k>-fix.md` (the fix worker's outcome per finding), `gates/<item>.txt` (the build's
  resolved gates)

`<git-common-dir>/juel/gate.lock` is the heavy-gate lock workers share through `juel:ship-ticket`'s
`gate-lock.sh`.

States:

| State | Pool | Meaning |
|---|---|---|
| `queued` | — | waiting for a build slot |
| `building` | build | build worker running (`ship-ticket --unattended --brief`) |
| `pr-draft` | — | draft PR open; waiting for a review slot |
| `reviewing` | review | second-model reviewer running, or `findings waiting` for a build slot |
| `fixing` | build | fix worker running (`ship-ticket --fix-review`) |
| `babysit-queued` | — | must be babysat again (head moved, or new feedback at verification); waiting for a review slot |
| `babysitting` | review | babysit worker running (`babysit-pr --unattended --mark-ready`) |
| `verifying` | review | `READY` received; exact-head check pending (checks still running or mergeable `UNKNOWN`) |
| `ready` | — | approved, green, verified on the exact head; waiting for your merge |
| `done` | — | you merged it |
| `escalated` | — | stopped on an escalation; open loop written |
| `failed` | — | a worker settled without its report, or could not start; open loop written |

`item` is the ref, or the slug when the ref is null. Never `null`, never empty.

## Intake

### Step 1: Preflight

Resolve `orca` (PATH, then `/Applications/Orca.app/Contents/Resources/bin/orca`), confirm
`orca status` (text form: `runtimeReachable: true`, `graphState: ready`), and match this repo's
main checkout path (`dirname` of the normalized `git rev-parse --git-common-dir`) against
`orca repo list --json` to get `REPO_ID`. Then check `ORCA_TERMINAL_HANDLE`: Orca sets it in every
terminal it manages. Empty → STOP — "Start Claude Code from an Orca terminal and run
`/juel:ship-tickets` there, so workers can report back to it."

Resolve the configured agents now, before anything is created: `command -v <agent>` for the worker
agent and the reviewer agent (`claude`, `codex`). A missing worker agent → STOP. A missing reviewer
agent → fall back to `claude` on a model other than the worker's (itself checked), and say so.

### Step 2: Select items

With refs or spec paths as arguments, use those. Otherwise call the source's `list` for open `todo`
items assigned to the user:

| Provider | `list` | `fetch` |
|---|---|---|
| `linear` | resolve `LINEAR_PREFIX` (`mcp__linear__` or `mcp__claude_ai_Linear__`, whichever exposes a domain tool), then `<LINEAR_PREFIX>list_issues(assignee: "me", project: <id>, state: "Todo")` | `<LINEAR_PREFIX>get_issue(id: <ref>)` |
| `jira` | the connected Jira/Atlassian MCP's JQL search: `assignee = currentUser() AND project = <key> AND statusCategory = "To Do"` | the MCP's get-issue tool |
| `github` | `gh issue list --assignee @me --state open --limit 200 --json number,title,url,labels` (skip `status:in-progress` / `status:in-review`) | `gh issue view <n> --json number,title,body,url,labels` |
| `file` | `*.md` in the spec directory whose status is explicitly `todo` | read the file |

No `list` (or `inline`): ask for refs or spec paths, one per line. Present the items and let the user
pick with AskUserQuestion (multiSelect). Do not invoke `juel:daily-worktrees`: this skill creates
its own Orca worktrees.

### Step 3: Fetch and normalize

Fetch every selected item in full. Normalize each to: `ref` (null when the source has none), `slug`
(kebab-case from the title, at most 6 words), `title`, `url` (omit when absent), `path` (a `file`
source's absolute spec path, so its status can be updated later), `source`, `labels`,
description, acceptance criteria. **Names are unique within the batch:** give every repeat of a slug
a suffix (`-2`, `-3`, … in selection order) and use that final name everywhere.

### Step 4: Draft and approve briefs (MANDATORY)

Resolve the repo's conventions once: remote (one → it, else `origin`, else ask), base branch
(`config.baseBranch` → `git config --get claude.baseBranch` → `git symbolic-ref --short
refs/remotes/<remote>/HEAD` → first existing of main/master/develop/dev/trunk → ask once), and branch
naming (sample `git for-each-ref --sort=-committerdate --count=60 refs/remotes/<remote>`, take the
modal pattern; default `{type}/{ref-lower}-{slug}`, `{type}/{slug}` when the ref is null, and a
GitHub ref `#412` renders as `issue-412`; type is `fix` for bug/fix/error, `refactor`, `chore`, else
`feat`).

For each item, read enough of the codebase to propose an approach, then draft its brief:

```markdown
---
juel_brief: 1
item:
  ref: <ref or null>
  slug: <slug>
  title: <title>
  url: <url>            # omit when absent
  path: <absolute path of the spec file in the main checkout — file sources only>
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
Drop → remove the item. An approved brief is the workers' contract: they escalate instead of
widening it. Zero approved briefs → stop: "Nothing approved, nothing started."

### Step 5: Pools, models, quiet hours, batch directory

Pools and models from Configuration (defaults above). Quiet hours: `ship.quietHours`; absent → ask
once ("Set a quiet window: no reviewer pings, ready-marking or status changes while you're away?"),
offer to persist, render as `HH:MM-HH:MM@<tz>` or `off`. Compute the absolute `BATCH` (see "State"), create it, write `batch.json`, one
`queued` row per item in `ledger.md` (approval order), an empty `open-loops.md`, and each approved
brief to `briefs/<item>.md`.

### Step 6: Start the run

```sh
caffeinate -dimsu >/dev/null 2>&1 &      # keeps the Mac awake (screen off is fine; a closed lid on battery still sleeps)
echo "caffeinate pid: $!"                # record it in batch.json
orca orchestration run-create --objective "juel ship <batch-id>" --json
```

`caffeinate` is started without `-w`, so it outlives a closed coordinator session and keeps the
workers' Mac awake overnight. It is stopped only by Step 8, or replaced by `resume`. Before killing
or replacing a recorded pid, confirm it is still caffeinate (`ps -p <pid> -o comm=` prints
`caffeinate`); a pid that now belongs to something else is left alone.

Record the run id in `batch.json`, then start filling slots (below) and enter the loop.

## Coordinator loop

One pass per wake, until every row is `ready`, `done`, `escalated` or `failed`.
Never call AskUserQuestion inside the loop: it blocks every other item until you answer. Questions for you are
printed and notified, and your answer arrives as an ordinary message between ticks.

**Persist before acting.** Write the row before every `task-create` (state, stage, round), record
the task id right after `task-create` and the dispatch id right after `worker-start`, and append a
message to `processed.log` before acknowledging its delivery. On `resume` or after a compaction,
a message already in `processed.log` is skipped, and a row whose stage has a task but no dispatch is
reconciled with `orca orchestration dispatch-show --task <id> --json` before anything is started
again. This is what stops a restart from starting a second worker on the same item.

1. **Wait.** `orca orchestration check --wait --types worker_done,escalation,question`
   `--timeout-ms 540000 --json`, reading stdout only (keepalives go to stderr; never merge the
   streams). A timeout or `count: 0` is a tick, not a failure.
2. **Process every message in the delivery**, matched to its row by the dispatch it carries. A
   message that matches no ledger row, or a row in a different stage, is never dropped: open loop
   quoting it. Skip messages already in `processed.log`. Then acknowledge with `--ack <delivery_id>`.

   | Message | Action |
   |---|---|
   | `worker_done`, body starts `DONE item=… pr=<url>` | save its `GATES` line to `gates/<item>.txt`; state `pr-draft`; free the build slot. A compare URL instead of a PR (no `/pull/`) → `escalated` (the `HELD` line asks you to open it) |
   | `worker_done`, `FIXED item=… head=<sha>` | save the body to `reviews/<item>-r<k>-fix.md` (the worker wrote it there too); state `pr-draft`, record head; free the build slot |
   | `worker_done` from a reviewer | **Save every reviewer body** to `reviews/<item>-r<k>.md` first, then read its last line |
   | `VERDICT item=… round=<k> SAFE` | state `babysitting` (the review slot carries over); start the babysit stage |
   | `VERDICT … NOT-SAFE`, round 1 or 2 | state `reviewing` with `findings waiting` until a build slot frees, then state `fixing` (the review slot frees) and start the fix stage |
   | `VERDICT … NOT-SAFE`, round 3 | `escalated`: "review still NOT SAFE after 3 rounds — see reviews/<item>-r3.md" |
   | no `VERDICT` line from a reviewer | start the same round once more; a second miss → `escalated` |
   | `worker_done`, `READY item=… pr=<url> head=<sha> cursor=<iso>` | record head and cursor; state `verifying`; run the exact-head check now |
   | `ESCALATION item=… phase=… reason=… needs=…` in a `worker_done` | `escalated`; open loop with `needs=`; notify; free the slot |
   | an `escalation` message (the worker may still be running) | open loop and notify, but keep the row and its slot until that worker's `worker_done` arrives or it is found settled (step 4) |
   | `HELD item=… action=…` lines in any body | one open loop each |
   | `question` (a worker's `orca orchestration ask`) | answer with `orca orchestration reply --id <msg_id> --body <answer>` when the brief decides it. Otherwise add it to `questions.md` with a deadline 30 min out, print it, notify, and keep looping; the worker stays blocked and keeps its slot |
   | any `worker_done` whose body lacks the line its stage owes | `failed`; open loop quoting the body; free the slot. Never re-run automatically |

   After processing each settled `worker_done`: `orca orchestration worker-release --dispatch <id>`.
3. **Fill free slots.** Build pool (`building`, `fixing`) up to `maxParallel`: waiting fixes first,
   then `queued` rows in approval order. Review pool (`reviewing`, `babysitting`, `verifying`) up to
   `maxInReview`: `babysit-queued` rows first, then the oldest `pr-draft` row starts its next review
   round. Every start passes the memory check first.
4. **Housekeeping.**
   - **Your answers.** An answer you gave to an open question since the last tick → `reply` it to
     the worker, mark it `answered`. A question past its deadline → reply "No answer from the user:
     escalate this.", mark it `expired`; the worker escalates `unanswered-question`.
   - **Settlement.** For every row in a worker stage, `orca orchestration worker-show --dispatch <id>
     --json`. A worker that has settled without a processed `worker_done` at the previous tick as
     well → `failed`, open loop, free the slot. (A report can lag its settlement by a tick; two
     ticks cannot.)
   - **Stuck workers.** Read each worker that has not reported since the last tick once with
     `orca orchestration worker-read --dispatch <id> --limit 30 --json`: a worker stuck at a dialog,
     a model or login prompt, or a usage limit never reports on its own — `worker-stop` it, mark
     the row `failed`, open loop with what it shows. Never answer a TUI prompt for a worker.
   - **Verifying rows.** Run the exact-head check again (once; see below).
   - **Ready rows.** `gh pr view <n> --json state,headRefOid` — `MERGED` → `done`. Head moved since
     verification → `babysit-queued` if `restarts` is 0 (then `restarts` = 1); otherwise
     `escalated`. One restart budget per item, shared with the verification step.
   - **Notifications.** Every open loop still `notify: pending` whose quiet window is over is sent
     now and marked `sent` (or `print-only` when no notification tool exists).
5. **Write `ledger.md`** (the whole file) and print one status line: counts per state, slots in use,
   new open loops.

## Stages

Every stage is its own Orca task and a fresh worker, so a crash loses one stage, not the item, and no
idle agent holds memory between stages.

| Stage | Worktree | Agent | Prompt |
|---|---|---|---|
| build | a new one, created as below | worker | `/juel:ship-ticket --unattended --brief <BATCH>/briefs/<item>.md [--quiet-hours <window>]` |
| review | the item's worktree | reviewer | the reviewer prompt below |
| fix | the item's worktree | worker | `/juel:ship-ticket --unattended --brief <BATCH>/briefs/<item>.md --fix-review <BATCH>/reviews/<item>-r<k>.md [--quiet-hours <window>]` |
| babysit | the item's worktree | worker | `/juel:babysit-pr <n> --unattended --mark-ready --item <item> --brief <BATCH>/briefs/<item>.md --gates "<gates from gates/<item>.txt, non-null commands ;-separated>" [--since <cursor>] [--quiet-hours <window>]` |

**Build worktree.** Orca names a new worktree's branch `<user>/<name>` and cannot be told otherwise,
and `ship-ticket` escalates when the checkout is not on the brief's branch. So create the worktree
first, without an agent, then rename the branch and copy the untracked files, and only then start
the worker:

```sh
orca worktree create --repo "id:<REPO_ID>" --name "<item>" --base-branch "<remote>/<baseBranch>" \
  --no-parent --setup run --json          # keep result.worktree.path as <worktree>
git -C "<worktree>" branch -m "<brief branch>"
```

Then copy untracked project files from the main checkout into `<worktree>` (`.env`, `.env.*`,
`*.local`, `.envrc`, `.npmrc`, `.tool-versions`, only when `git ls-files --error-unmatch` says they
are untracked) and the `.claude/` directory, and check each one landed. Git is authoritative for the
branch name; Orca's view of it can lag for a moment. A worktree that already exists for the item's
branch is reused, never duplicated.

**Starting a stage** (after the build worktree exists):

```sh
orca orchestration task-create --spec "<prompt from the table>" --json
orca orchestration worker-start --task <task_id> --worktree path:<worktree> \
  --agent <agent> --model <model> --effort <effort> --json
```

`worker-start` exits 0 only for `ready`. Any other result: retry once with `--retry-of <dispatch_id>`
and the same placement; a second failure → `failed` with the receipt's `stage` in the open loop. A
rejected effort (`does not support effort`) retries once with the next lower listed level.

**Reviewer prompt** (fill in `<…>`):

```
You are reviewing a draft pull request you did not write, as a second, independent reviewer.
Do not edit, commit, push or comment anywhere. Read only.
Brief (the approved contract): <BATCH>/briefs/<item>.md
Previous round (rounds 2 and 3 only): the findings in <BATCH>/reviews/<item>-r<k-1>.md and the fix
worker's outcome per finding in <BATCH>/reviews/<item>-r<k-1>-fix.md. Judge each rejection on its
merits; a prior rejection is evidence, not a verdict.
Run: git fetch <remote> <baseBranch> && git diff <remote>/<baseBranch>...HEAD
Review the whole diff against the brief: correctness, every acceptance criterion, scope (In/Out),
a regression test for every bug fix, security, data loss, error handling.
NOT-SAFE only for a defect that breaks behaviour, loses data, opens a security hole, misses an
acceptance criterion or leaves scope. Anything smaller goes under "Notes" and does not block.
Output a numbered findings list (severity, file:line, the failure scenario, the fix), then Notes,
then exactly one last line:
VERDICT item=<item> round=<k> SAFE
or
VERDICT item=<item> round=<k> NOT-SAFE
Send that whole output as your worker_done body.
```

The reviewer agent is `ship.reviewer` (default `codex`); without the codex CLI it is `claude` with a
model other than the worker's, and the report says so.

## Exact-head verification

On `READY` (state `verifying`), check the PR yourself:

```sh
gh pr view <url> --json isDraft,reviewDecision,reviews,commits,headRefOid,mergeable,statusCheckRollup
```

It passes when: `isDraft` is false; `reviewDecision` is `APPROVED`, or null or an empty string (the
repo requires no review; `gh` reports an empty string) with an `APPROVED` review submitted after the
last commit; `headRefOid` equals the reported head; `mergeable` is `MERGEABLE`; and every check
passed — read `conclusion`, falling back to `state` for commit statuses, and accept `SUCCESS`,
`NEUTRAL` or `SKIPPED` (a `CANCELLED` check is not a pass).

- **Pass** → state `ready`, free the review slot, open loop
  `merge PR #<n> — approved, green, head <sha7>`, notify.
- **Pending checks or `mergeable: UNKNOWN`** → stay `verifying`, keep the review slot, record
  `verify: retry <time>`; housekeeping checks once more at the next tick. Still not passing then →
  `escalated` naming what is pending.
- **Head moved or new feedback** → `babysit-queued` if `restarts` is 0 (then 1), else `escalated`.
- **Anything else** → `escalated` naming the failing check or the missing approval.

## Pools and the memory check

Before every `worker-start`, check memory, following the user's rule for heavy work on this machine:

```sh
pg=$(vm_stat | sed -n 's/.*page size of \([0-9]*\) bytes.*/\1/p')
fr=$(vm_stat | sed -n 's/^Pages free: *\([0-9]*\)\./\1/p')
in=$(vm_stat | sed -n 's/^Pages inactive: *\([0-9]*\)\./\1/p')
echo $(( (fr + in) * pg / 1073741824 ))   # GB free + inactive
```

Under 3 GB free + inactive → do not start; note `HOLD: memory` in the row's `updated` cell and try
again at the next tick. On Linux, read the `available` column of `free -g` instead. Inside workers,
Phase 5's test and lint run, the Phase 6 regression gate and babysit's gates all go through
`gate-lock.sh`, so only one heavy gate runs at a time; each worker also checks memory before it
starts its Phase 6 stack.

## Notifications

On an escalation, a worker question you cannot answer from the brief, and "merge PR #n": print it,
and send a push notification with Claude Code's `PushNotification` tool (load it with `ToolSearch`
when it is deferred; when it does not exist, printing is enough). Inside quiet hours only
escalations notify; the rest are written as `notify: pending` and sent by housekeeping when the
window ends, so a restart never loses them.

## Quiet hours

Workers get the window and decide at each outward action. They keep building, reviewing, fixing and
pushing; marking ready, replying to reviewers, re-requesting review and status writes wait for the
window to end (or come back as `HELD` lines, which become open loops).

## Step 8: Report

Kill the recorded `caffeinate` (after `ps -p <pid> -o comm=` confirms it is caffeinate), then print: the merge list (`ready` rows with PR URLs), every open
loop, and counts per state. State that nothing was merged, and that `/juel:ship-tickets status`
shows the batch later.

## Resume

`/juel:ship-tickets resume [batch-id]` (newest batch by default): read `batch.json`, `ledger.md`,
`processed.log` and `questions.md`; `orca orchestration run-use --id <run id> --json`. Reconcile
every row in a worker stage: a task with no recorded dispatch → `dispatch-show --task <id>` and
record what exists; a dispatch → `worker-show --dispatch <id>`: still running → keep it; settled →
its `worker_done` should be in the run's inbox, and the settlement rule in housekeeping fails it if
it never arrives. Replace `caffeinate`: kill the recorded pid if `ps -p <pid> -o comm=` says it is
still caffeinate, start a new one, record it. Then enter the loop. Use this after a compaction, a
closed session or a Mac that slept.

## Status

`/juel:ship-tickets status [batch-id]`: print `ledger.md` and `open-loops.md`; for `ready` rows,
`gh pr view <n> --json state` and mark merged ones `done`. Read-only otherwise.

## Hard rules

- **Never merge a PR**, and never start a worker that would. The flow ends at "merge PR #n"; the
  merge is always your click.
- Brief approval is never skipped, batched into one yes, or carried over from another batch.
- A `failed` row is never re-run automatically. You decide.
- Workers are started only through `orca orchestration worker-start`, never a provider's own
  subagent tool, so every report comes back through the run.

## Common mistakes

| Mistake | Fix |
|---|---|
| Starting the build worker before renaming the branch | The worker escalates on the branch mismatch. Create, rename, copy, then start |
| Reading `check --wait --json 2>&1` through a parser | Keepalives go to stderr; pipe stdout only |
| Releasing a worker before reading its `worker_done` | Process, then `worker-release` |
| Treating a `check` timeout as a dead worker | It is a tick. Read the worker once; only a prompt or usage-limit screen means stuck |
| Answering a worker's TUI prompt | Stop it and mark it failed; never type into it |
| Starting a fourth build because a slot looks free while memory is low | The memory check runs before every start |
| Counting a `findings waiting` review as free review capacity | It holds its review slot until the fix starts |

## Edge cases

| Situation | Handling |
|---|---|
| Not in an Orca terminal | STOP with the Step 1 message; nothing is created |
| `orca repo list` lacks this repo | Offer `orca repo add` once; declined → STOP |
| A worktree for the item's branch already exists | Reuse it; never create a second one |
| The session closes or compacts mid-batch | `/juel:ship-tickets resume` |
| Every brief dropped | "Nothing approved, nothing started." |
| `codex` missing | Reviewer runs on claude with a different model; say so in the report |
