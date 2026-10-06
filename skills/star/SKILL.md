---
name: star
description: Use to run STAR, a permanent local coordinator that ships work items to merged-ready PRs across all your projects. STAR lives in its own git repo (~/juel-star) - a queue with Answer slots, a ledger, briefs, release records and shared memory notes. Hand it work from any session with "/juel:star add <refs>"; a worker drafts a brief per item for your approval, then Orca workers build, a second model reviews the draft PR, fixes land, and the PR is babysat until it is approved, green and verified on its exact head. STAR never reads big output, recovers by itself after compaction, and never merges. Triggers "start STAR", "add this to STAR", "what does STAR need from me", "/juel:star".
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: brief workers fetch items from Linear when it is a project's work source
        check: none
        fallback: the project's other configured source is used; items can also be given as spec paths
    cli:
      - id: orca
        hard: true
        why: every stage is an Orca orchestration task with a supervised worker
        check: "resolve_bin orca against PATH, then the app-bundle candidate"
      - id: gh
        hard: true
        why: workers open and babysit PRs; pr-verify.sh and release-record.sh read them
        check: "gh auth status"
      - id: git
        hard: true
        why: the docs repo is a git repo committed after every tick
        check: "command -v git"
      - id: python3
        hard: true
        why: loops.sh, pr-verify.sh, worker-probe.sh, release-record.sh and the session hook run on it
        check: "command -v python3"
      - id: claude
        hard: true
        why: brief, build, fix and babysit workers run the configured worker agent, claude by default
        check: "command -v claude"
      - id: codex
        hard: false
        why: the second-model reviewer runs as a codex worker
        check: "command -v codex"
        fallback: the reviewer runs as a claude worker on a model other than the builders'
    context:
      - id: orca-runtime
        hard: true
        why: the run, tasks and workers live in the Orca runtime
        check: "orca status reports runtimeReachable: true and graphState: ready"
      - id: orca-terminal
        hard: true
        why: run-create binds the orchestration run to the calling terminal, which must be an Orca terminal
        check: "ORCA_TERMINAL_HANDLE is set"
      - id: star-home
        hard: true
        why: STAR's standing instructions, hook and files are tied to its docs repo being the session's cwd
        check: "cwd is $JUEL_STAR_HOME or ~/juel-star"
      - id: interactive-user
        hard: true
        why: the first run asks for quiet hours; the loop itself never asks through AskUserQuestion
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

# STAR

STAR is one long-running coordinator session for shipping work across all your projects. It plans,
hands out work, checks results and keeps the queue; it never writes code and never reads big
output. Real work goes to Orca workers: a fresh agent per stage, in the item's own worktree, that
reports in at most 12 lines and is released. Everything that matters lives in files in STAR's own
git repo, never only in chat, so a compacted or restarted STAR reads them and carries on. It follows
the artifact "My 24/7 Agent Setup". **You merge; nothing here does.**

**Announce:** "Using juel:star." (in `add`, `status` and `draft-brief` modes: say which mode.)

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

`add`, `status` and `draft-brief` are not STAR itself: they skip this table (each states its own
needs below) and the task list. Everything else is the start mode.

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| Linear MCP | mcp | SOFT | **none — render as `?`** | the project's other configured source is used; items can also be given as spec paths |
| orca | cli | HARD | `resolve_bin orca` against PATH, then the app-bundle candidate | STOP → https://www.onorca.dev |
| gh | cli | HARD | `gh auth status` | STOP → `gh auth login` |
| git | cli | HARD | `command -v git` | STOP |
| python3 | cli | HARD | `command -v python3` | STOP → install Python 3 |
| claude | cli | HARD | `command -v claude` (or the configured `worker.agent`) | STOP → install the worker agent CLI |
| codex | cli | SOFT | `command -v codex` | the reviewer runs as a claude worker on a model other than the builders' |
| reachable Orca runtime | context | HARD | `orca status` reports `runtimeReachable: true` and `graphState: ready` | STOP → run `orca open`, then re-run |
| running in an Orca terminal | context | HARD | `[ -n "$ORCA_TERMINAL_HANDLE" ]` | STOP → start Claude Code from an Orca terminal and re-run there |
| running in STAR's home | context | HARD | cwd is `$JUEL_STAR_HOME`, else `~/juel-star` | STOP → `mkdir -p ~/juel-star`, open an Orca terminal there, start Claude Code and run `/juel:star` |
| AskUserQuestion | context | HARD | always available interactively | STOP → the first run asks one setup question |
| juel:ship-ticket, juel:babysit-pr, juel:receive-review-and-execute | skill | HARD | ship with this plugin | STOP |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Preflight — binaries, the Orca runtime and terminal, STAR's home
2. Create the docs repo from the template, or load the existing one
3. Bind the Orca run, start caffeinate, register the heartbeat
4. Reconcile every row in a worker stage
5. Tick until idle or stopped
6. On stop: write the Resume block, stop caffeinate and the heartbeat, report

Phase 5 repeats. Keep its task `in_progress` across ticks and put the tick's one-line summary in its
evidence; it completes when STAR goes idle or is stopped.

## Commands

| Command | Run from | Effect |
|---|---|---|
| `/juel:star` | an Orca terminal whose cwd is STAR's home | Start STAR, or resume it: the two are the same command |
| `/juel:star add <refs…>` | any Claude session inside a project repo | Put items in STAR's inbox and nudge it |
| `/juel:star status` | anywhere | Print the Needs-you block and counts per state. Read-only |
| `/juel:star away` | anywhere, or tell STAR "I'm leaving" | Write the handoff file and switch to away mode (below) |
| `/juel:star back` | anywhere, or tell STAR "I'm back" | Print the latest summary and the queue; leave away mode |
| `/juel:star stop` | STAR's session | Finish the tick and stop. Running workers are left to finish; their reports wait in the Orca run |
| `/juel:star draft-brief <ref> --project <name> --out <path>` | a brief worker, never the user | Worker mode, below |

STAR's home is `$JUEL_STAR_HOME` when set, else `~/juel-star`. Below, `HOME_DIR` is its absolute
path and `S` is this skill's directory (`${CLAUDE_PLUGIN_ROOT}/skills/star` when that is set, else
the directory of this file). Scripts are run as `sh S/<name>.sh`.

### `add`

Needs: a git repo, and STAR's home to exist. No Orca terminal needed.

1. Repo path = the main checkout: the first `worktree ` line of `git worktree list --porcelain`
   (right from a linked worktree, a subdirectory or a submodule). Project name = its basename.
2. Write `HOME_DIR/inbox/<UTC YYYYMMDDTHHMMSSZ>-<project>-<4 random hex>.md`
   (never overwrite an existing inbox file; pick another suffix):

   ```
   project: <name>
   repo: <absolute repo path>
   refs:
   - <ref or absolute spec path>
   note: <anything the user said about these items, one line; omit when nothing>
   ```
3. Nudge STAR: read `terminal` from `HOME_DIR/star.json` and run
   `orca terminal send --terminal <handle> --text "inbox" --enter`. When `terminal` is null, the
   command fails, or STAR's Resume block says `state: stopped`, say: "STAR is not running; the item
   waits in the inbox and is picked up when you start it."
4. When `HOME_DIR` does not exist, write nothing and say how to create it (the star-home row above).

A message to STAR that says only `inbox` means "run a tick now".

### `status`

`sh S/loops.sh --file HOME_DIR/open-loops.md list`, then counts per state from `ledger.md`. Print
both. Nothing else.

### `away` and `back`

In STAR's own session these run directly (see "Handoff"). From any other session they need only
STAR's home: write `HOME_DIR/inbox/<UTC timestamp>-control-<4 random hex>.md` containing the single
line `control: away` (or `control: back`), then nudge STAR exactly as `add` does. STAR not running →
say so; the control file waits in the inbox.

## STAR's home

Created on the first `/juel:star` in an empty home: copy `S/template/` into it (rename `gitignore`
to `.gitignore`), `mkdir -p inbox briefs reviews gates releases drafts`, `git init`, commit
`star: init`. Ask once, with AskUserQuestion, for a quiet window ("no reviewer pings, ready-marking
or status changes while you're away?") and write it to `star.json`. Then tell the user where the
queue is: `HOME_DIR/open-loops.md`.

```
CLAUDE.md               standing instructions; Claude Code re-reads it after every compaction
star.json               settings (below) plus run id, STAR's terminal handle, caffeinate pid, heartbeat id, notifiedThrough
open-loops.md           Resume block, then Needs you, then Waiting on others   (written only through loops.sh)
open-loops-archive.md   closed items
handoff.md              the "before you go" lists and the summaries written while the user is away (handoff.sh)
sent.log                <iso>\t<project>\t<item>\t<what was sent>: every message a worker or STAR posted
ledger.md               one row per item, all projects
processed.log           <message id> <dispatch> <iso time>
projects.md             | name | repo path | orca repo id | work source | base branch | remote |
inbox/                  one file per add; deleted once ingested (not committed)
briefs/<project>/<item>.md
reviews/<project>/<item>-r<k>.md   and   <item>-r<k>-fix.md
gates/<project>/<item>.json
releases/<YYYY-MM-DD>-<project>-<item>.md
drafts/<YYYY-MM-DD>-<project>-<item>-<kind>.md
memory/global.md, memory/<project>.md
```

Every path keyed by an item is also keyed by its project, so the same item name in two projects
never collides. A second repo with the same basename is named `<parent dir>-<basename>`.

Settings in `star.json`:

```jsonc
{
  "maxParallel": 3,                                      // build pool
  "maxInReview": 3,                                      // review pool
  "worker":   { "agent": "claude", "model": "opus",    "effort": "high" },
  "reviewer": { "agent": "codex",  "model": "default", "effort": null },
  "quietHours": { "tz": "Asia/Manila", "start": "22:00", "end": "07:00" }   // null = off
}
```

A model of `default` means: pass neither `--model` nor `--effort`. Model ids come from the CLIs,
never from memory. Never pick a top-tier model (frontier, toughest, most capable) unless the user
asked for one; `opus` is the mid tier.

### The queue: `open-loops.md`

STAR writes this file only through `loops.sh`, which re-reads it every time and never loses text the
user typed. The user answers on an item's `Answer:` line (continuing on the lines right under it),
or by telling STAR, who records it with `loops.sh set-answer <id> "<text>"` and then acts on it
in the same turn (the Answers step below, run at once for that item), so the worker that owns the
work gets the answer without waiting for the next tick.

| When | Command |
|---|---|
| a brief is drafted | `loops.sh add --kind approve-brief --project <p> --item <i> --title "approve brief" --body "<brief path>\nOptions: approve / drop / or say what to change"` |
| a PR passed the exact-head check | `loops.sh add --kind merge-pr --project <p> --item <i> --title "merge PR #<n> — approved, green, head <sha7>" --body "<pr url>"` |
| a worker escalated, or a row failed | `loops.sh add --kind escalation --project <p> --item <i> --title "<reason>" --body "<needs= text, or what failed>\nOptions: answer with your decision to run the stage again / drop"` |
| a worker asked something the brief does not answer | `loops.sh add --kind question --project <p> --item <i> --title "<the question, one line>" --body "msg: <id>\ndeadline: <iso, 30 min after it is notified>"` (the `msg: <id>` line is the Orca message id the reply needs after a restart) |
| a build or fix was lost to a restart | `loops.sh add --kind restart-or-drop --project <p> --item <i> --title "<stage> was interrupted" --body "Options: restart / drop"` |
| a draft is ready | `loops.sh add --kind draft --project <p> --item <i> --title "<what the draft is>" --body "<draft path>\nOptions: send / drop"` |
| a worker held an outward action | `loops.sh add --kind held --project <p> --item <i> --title "<action>" --body "Options: done"` |

Open items are repeated in every status line STAR prints, by id and title, until they are answered:
silence means missed, not no.

Every transition into `escalated` or `failed` queues a `--kind escalation` item in the same step,
so no row is ever stranded: its answer either runs the stage again with the user's decision or
drops the row. A `held` item is only a reminder of an outward action; closing it changes no row.

### The ledger

`| item | ref | project | worktree | state | stage | round | task | dispatch | restarts | pr | head | cursor | verify | updated |`

**An item has one name everywhere**, set once at ingest and used for its row, its brief, review
and gate paths, its worktree and every report line: a tracker ref as written (`SAVI-1162`); a
GitHub ref `#<n>` becomes `issue-<n>`; a spec path becomes the kebab-case of its file name without
the extension. A name already used in that project gets `-2`, `-3`. The raw reference stays in the
`ref` column and is what the brief worker fetches.

| State | Pool | Meaning |
|---|---|---|
| `inbox` | — | ingested; waiting for a build slot to draft its brief |
| `briefing` | build | a brief worker is reading the item and the code |
| `brief-ready` | — | brief drafted; waiting for the user's approval |
| `queued` | — | approved; waiting for a build slot |
| `building` | build | build worker running |
| `pr-draft` | — | draft PR open; waiting for a review slot |
| `reviewing` | review | second-model reviewer running, or `findings waiting` for a build slot |
| `fixing` | build | fix worker running |
| `babysit-queued` | — | waiting for a review slot to start babysitting (after SAFE, or again after the head moved) |
| `babysitting` | review | babysit worker running |
| `verifying` | review | `READY` received; exact-head check pending |
| `ready` | — | approved, green, verified; waiting for the user's merge |
| `done` | — | merged; release record written |
| `escalated` | — | stopped on an escalation; in the queue |
| `failed` | — | a worker settled without its report or could not start; in the queue |
| `dropped` | — | the user dropped it |

Build pool (at most `maxParallel`): waiting fixes first, then `inbox` rows (briefs are short and
unblock the user), then `queued` rows, oldest first. Review pool (at most `maxInReview`):
`babysit-queued` rows first, then the oldest `pr-draft`.

## Start, resume, stop

`/juel:star` in a home that already has rows is a resume; there is no separate command.

1. `orca orchestration run-use --id <run from star.json> --json`; when that run no longer exists,
   `orca orchestration run-create --objective "STAR" --json`. Record the run id and
   `$ORCA_TERMINAL_HANDLE` in `star.json`.
2. `caffeinate`: when `star.json` has a pid and `ps -p <pid> -o comm=` prints `caffeinate`, kill it.
   Start a new one (`caffeinate -dimsu >/dev/null 2>&1 &`) and record its pid. It deliberately
   outlives a closed session, so the workers' Mac stays awake.
3. Heartbeat: load the scheduler (`ToolSearch("select:CronCreate,CronDelete")`), delete the job id in
   `star.json` if any, and create a recurring job `7,37 * * * *` with the prompt
   `STAR heartbeat: if you are not already in a tick, run one.` Record its id. Jobs fire only while
   the session is idle and die with the session, which is why every start registers a fresh one.
   No scheduler tool → skip it and say so: an idle STAR then wakes only on `add` or the user.
4. **Reconcile** every row in a worker stage with `sh S/worker-probe.sh <dispatch>`:
   `ok` → keep it. `settled <state>` → its report is in the run's inbox; the settlement rule below
   catches it if it is not. `gone` → Orca has no such worker (an Orca restart): a `briefing`,
   `reviewing` or `babysitting` row restarts once on its own (`restarts` column; babysit with
   `--since <cursor>`), because those stages can pick up safely; a lost `building` or `fixing` row
   goes to the queue (`--kind restart-or-drop`), because restarting a half-finished build blindly
   would build on a dirty worktree. `unknown <why>` says nothing about the worker: keep the row and
   let housekeeping probe it again. A `verifying` row has no worker: run the exact-head check for
   it, never restart it. A row with a task but no dispatch:
   `orca orchestration dispatch-show --task <id> --json` and record what exists before starting
   anything.
5. `loops.sh resume --state running --run <id> --pools "build <n>/<max> · review <n>/<max>" --next "<one line>"`, then tick.

**Stop** (`/juel:star stop`, or the user says stop): finish the current tick, kill the recorded
caffeinate, delete the heartbeat, `loops.sh resume --state stopped --next "run /juel:star to resume"`,
commit, and print the queue. Workers still running are left alone.

## The tick

Never call AskUserQuestion inside a tick: it would block every other item until answered. Questions
for the user go into the queue and are notified; the answer arrives in the file or as an ordinary
message.

**Persist before acting.** Write the row before every `task-create` (state, stage, round), record
the task id right after `task-create` and the dispatch id right after `worker-start`.
Write the whole ledger right after each message's transition, then append the message to
`processed.log`, and only then acknowledge the delivery (step 3). A message already in
`processed.log` is skipped. A message that matches no row is never dropped: `--kind held` with its
first line.

1. **Inbox.** A file whose only line is `control: away` or `control: back` is that command: run it
   (see "Handoff") and delete the file. For each other `HOME_DIR/inbox/*.md`: learn the project into `projects.md` on first sight
   (orca repo id from `orca repo list --json` by repo path; not registered → `--kind held` "register
   <repo> with Orca: orca repo add" and leave the file), add one `inbox` row per ref with its item
   name (the naming rule above) and the raw reference in `ref`, delete the file.
2. **Answers.** `sh S/loops.sh answers` prints one line per answered item. Act, then
   `loops.sh close <id>`:

   | Kind | Answer | Action |
   |---|---|---|
   | `approve-brief` | exactly `approve`, `yes` or `ok` (any case) | stamp `approved: <iso>` in the brief's frontmatter; row → `queued` |
   | `approve-brief` | drop | row → `dropped` |
   | `approve-brief` | anything else, including "approve, but …" | it is feedback, never a conditional approval: row → `inbox` and the brief stage runs again with `--feedback "<answer>"` |
   | `merge-pr` | drop / not merging | row → `dropped`. Any other answer changes nothing: a merge is detected from GitHub, never taken from an answer |
   | `escalation` | drop | row → `dropped` |
   | `escalation` | anything else | the answer is the decision. Brief stage: run it again with `--feedback "<answer>"`. A row with no PR whose worker lacked `gh`: an answer that is a PR URL records it, row → `pr-draft`. Any other stage: append the answer to the brief under `## Decisions` with the date (workers read that section first and treat it as binding), then run the stage in the `stage` column again (babysit with `--since <cursor>`) |
   | `question` | any | `orca orchestration reply --id <the item's msg id> --body "<answer>" --json` |
   | `restart-or-drop` | restart / drop | requeue the stage, or row → `dropped` |
   | `draft` | send | a draft whose first line is `to: pr <url>` is posted with `gh pr comment <url> --body-file <the rest>`; any other draft is the user's to send, say so |
   | `draft`, `held` | anything else | close it |
3. **Messages**, only while some row is in a worker stage or waiting for a slot:
   `orca orchestration check --wait --types worker_done,escalation,question`
   `--timeout-ms 540000 --json`, stdout only. The JSON carries a `deliveryId`; Orca replays that
   same batch until it is acknowledged. So once every message in it is in the ledger and in
   `processed.log`, the next wait is
   `orca orchestration check --ack <delivery_id> --wait --types worker_done,escalation,question --timeout-ms 540000 --json`
   (or `check --ack <delivery_id> --json` alone when STAR is about to go idle). A timeout is a tick. STAR reads only the report's
   lines (at most 12 lines); it never opens a review, evidence or log file, and never reads a
   worker's screen: the scripts do that and give one line back.

   | First line of the report | Action |
   |---|---|
   | `BRIEF item=… path=…` | row → `brief-ready`; queue `--kind approve-brief` (title "approve brief — add acceptance criteria first" when the report has a `NEEDS-CRITERIA` line) |
   | `DONE item=… pr=<url>` | record the PR; row → `pr-draft`; free the build slot. A compare URL (no `/pull/`) → `escalated`, queue `--kind escalation` "no gh on this machine: open a draft PR from <url>, then answer with the PR's URL" (and skip the worker's own `HELD … open a draft PR` line) |
   | `VERDICT item=… round=<k> SAFE findings=<n>` | row → `babysit-queued`; free the review slot |
   | `VERDICT … NOT-SAFE findings=<n>`, round 1 or 2 | row stays `reviewing` with `findings waiting` until a build slot frees, then → `fixing` and the fix stage starts |
   | `VERDICT … NOT-SAFE`, round 3 | row → `escalated`; queue `--kind escalation` "review still NOT SAFE after 3 rounds" with the review's path |
   | a reviewer report with no `VERDICT` line | run the same round once more; a second miss → `escalated`, queue `--kind escalation` "reviewer gave no verdict twice" |
   | `FIXED item=… head=<sha>` | record head; row → `pr-draft`; free the build slot. The next review is `round + 1` (the first review is round 1; `round` is written when a review starts) |
   | `READY item=… pr=… head=<sha> cursor=<iso>` | record head and cursor; row → `verifying`; run the exact-head check now |
   | `ESCALATION item=… phase=… reason=… [cursor=<iso>] needs=…` in a `worker_done` | record `cursor` when given; row → `escalated`; queue `--kind escalation` (and `--kind draft` with it when the report has a `DRAFT <path>` line); notify; free the slot |
   | `MERGED item=… pr=<url>` (a babysit worker saw the user merge early) | handle it as `pr-verify.sh` printing `MERGED`: release record, row → `done` |
   | an `escalation` message while the worker still runs | queue it and notify, but keep the row and its slot until its `worker_done` arrives |
   | a `question` message | brief decides it → `reply`. Inside quiet hours → reply "No answer during quiet hours: escalate this." Otherwise queue `--kind question`, notify, keep looping; the worker stays blocked and keeps its slot |
   | anything else, or no report line | row → `failed`; queue `--kind escalation` quoting the first line; free the slot. Never re-run without the user's answer |

   Also, for any report: each `HELD item=… action=…` line → `--kind held`; a `NOTE: <text>` line →
   append `- <date> <item>: <text>` to `HOME_DIR/memory/<project>.md`; a `SENT …` line → append
   `<iso>\t<project>\t<item>\t<the text after SENT>` to `HOME_DIR/sent.log`. STAR logs its own sends
   there too (a draft it posted with `gh pr comment`). After each settled
   `worker_done`: `orca orchestration worker-release --dispatch <id>`.
4. **Fill slots** by the pool rules above, memory check first (below).
5. **Housekeeping.**
   - Questions past their deadline: reply "No answer from the user: escalate this." and close the item.
   - Each row in a worker stage that has not reported this tick: `sh S/worker-probe.sh <dispatch>`.
     `stuck: <what>` → `orca orchestration worker-stop`, release, row → `failed`, queue
     `--kind escalation` "<stage> worker stuck: <what>". `settled …` with no processed report, twice
     in a row → `failed`, release, queue it. `gone` → the reconcile rule for a lost worker.
     `unknown <why>` → note it in `updated`; three ticks in a row → `failed`, queue it with `<why>`.
     Never answer a worker's prompt for it.
   - `verifying` rows past `retry-not-before`, and every `ready` row: the exact-head check (below).
   - Notifications (below).
   - Away: `sh S/handoff.sh --home HOME_DIR due` printing `due` → `sh S/handoff.sh --home HOME_DIR summary`.
6. **Write and commit** (one `git commit` per tick that changed files). `loops.sh resume …` with the current pools and the next step;
   `loops.sh waiting "<one line per PR in review, per blocked question>"`; then, when anything
   changed: `git -C HOME_DIR add -A && git -C HOME_DIR commit -q -m "star: <n> transitions, <m> loops"`,
   and `git push` when a remote named `origin` exists. A failed push is noted in the Resume block's
   `next:` line and retried next tick; it is never fatal. Print one status line: counts per state,
   then every open queue item.

**Active or idle.** While any row is in `inbox`, `briefing`, `queued`, `building`, `pr-draft`,
`reviewing`, `fixing`, `babysit-queued`, `babysitting` or `verifying`, stay in the turn and tick
again (step 3's bounded wait is the clock). When every row is waiting on the user or finished, write
`state: idle` and STAR ends its turn. It is woken by an `add` nudge, by the user, or by the
heartbeat, and each wake runs one tick.

## Stages

Every stage is its own Orca task and a fresh worker.

| Stage | Worktree | Agent | Prompt |
|---|---|---|---|
| brief | the project's main checkout (`path:<repo path>`), read-only | worker | `/juel:star draft-brief <ref> --project <name> --item <name> --out HOME_DIR/briefs/<project>/<item>.md [--feedback "<text>"]` (the row's raw `ref`, then its item name) |
| build | a new Orca worktree in that project, set up as below | worker | `/juel:ship-ticket --unattended --brief HOME_DIR/briefs/<project>/<item>.md [--quiet-hours <window>]` |
| review | the item's worktree | reviewer | the reviewer prompt below |
| fix | the item's worktree | worker | `/juel:ship-ticket --unattended --brief <brief> --fix-review HOME_DIR/reviews/<project>/<item>-r<k>.md [--quiet-hours <window>]` |
| babysit | the item's worktree | worker | `/juel:babysit-pr <n> --unattended --mark-ready --item <item> --brief <brief> --gates-file HOME_DIR/gates/<project>/<item>.json [--since <cursor>] [--quiet-hours <window>]` |

**Build worktree.** Orca picks the new worktree's branch name (`<user>/<name>` when the repo has a
git username, else `<name>`) and cannot be told otherwise, and `ship-ticket` escalates when the
checkout is not on the brief's branch. So set the worktree up first, without an agent, and only
then start the worker:

1. **Reuse first.** If `git worktree list --porcelain` shows a worktree on `refs/heads/<brief
   branch>`, use its path and skip to step 4.
2. **Create.** `orca worktree create --repo "id:<REPO_ID>" --name "<item>" --base-branch
   "<remote>/<baseBranch>" --no-parent --setup run --json`; keep `result.worktree.path` as
   `<worktree>`.
3. **Put it on the brief's branch.** If `git show-ref --verify --quiet refs/heads/<brief branch>`
   succeeds (a branch left by an earlier attempt), `git -C <worktree> switch <brief branch>`, then
   delete Orca's branch; otherwise `git -C <worktree> branch -m <brief branch>`. A non-zero exit →
   `failed` with an open loop; never start a worker on the wrong branch. Git is authoritative;
   Orca's view of the branch can lag for a moment.
4. **Copy environment files** from the main checkout: only files git ignores. Ignored files
   never show in `git status`, so `ship-ticket`'s clean-tree check still passes, and a worker's
   `git add -A` can never commit them. An untracked file that is not ignored is someone's work in
   progress, not environment, and stays where it is. Run it under `sh`, so a pattern that matches
   nothing cannot abort it (zsh does):

   ```sh
   sh -c 'cd "<main checkout>" && { find . -maxdepth 1 -type f \( -name ".env" -o -name ".env.*" \
     -o -name "*.local" -o -name ".*.local" -o -name ".envrc" -o -name ".npmrc" -o -name ".tool-versions" \) ;
     git ls-files --others --ignored --exclude-standard .claude ; } \
     | while IFS= read -r f; do git check-ignore -q "$f" || continue
         mkdir -p "<worktree>/$(dirname "$f")" && cp -p "$f" "<worktree>/$f"; done'
   ```

   Then confirm `git -C <worktree> status --porcelain` is empty; if it is not, remove what was
   copied and queue the row as `failed`.

A failed branch step or a second failed `worker-start` → `failed`, `--kind escalation` naming the
step.

**Starting a stage:**

```sh
orca orchestration task-create --spec "<prompt from the table>" --json
orca orchestration worker-start --task <task_id> --worktree path:<worktree> \
  --agent <agent> [--model <model> --effort <effort>] --json
```

`worker-start` exits 0 only for `ready`. Any other result: retry once with `--retry-of <dispatch_id>`
and the same placement; a second failure → `failed`, queued. A rejected effort retries once with the
next lower listed level. `--quiet-hours <window>` is `star.json`'s `quietHours` rendered as
`HH:MM-HH:MM@tz` (for example `22:00-07:00@Asia/Manila`); omit the flag when it is null.

**Reviewer prompt** (fill in `<…>`):

```
You are reviewing a draft pull request you did not write, as a second, independent reviewer.
Do not edit, commit, push or comment anywhere in the repo or on GitHub. Read only.
Brief (the approved contract): <brief path>
Notes for this project: <HOME_DIR>/memory/global.md and <HOME_DIR>/memory/<project>.md
Previous round (rounds 2 and 3 only): <review path of round k-1> and its -fix.md beside it. Judge
each rejection on its merits; a prior rejection is evidence, not a verdict.
Run: git fetch <remote> <baseBranch> && git diff <remote>/<baseBranch>...HEAD
Review the whole diff against the brief: correctness, every acceptance criterion, scope (In/Out),
a regression test for every bug fix, security, data loss, error handling.
NOT-SAFE only for a defect that breaks behaviour, loses data, opens a security hole, misses an
acceptance criterion or leaves scope. Anything smaller goes under "Notes" and does not block.
Write the full review (numbered findings: severity, file:line, the failure scenario, the fix; then
Notes) to <HOME_DIR>/reviews/<project>/<item>-r<k>.md. That file is the only thing you write.
Your worker_done body is exactly one line:
VERDICT item=<item> round=<k> SAFE findings=<n>
or
VERDICT item=<item> round=<k> NOT-SAFE findings=<n>
```

The reviewer agent is `reviewer` from `star.json` (default `codex`); without the codex CLI it is
`claude` on a model other than the worker's, and STAR says so.

## Brief worker mode: `draft-brief`

`/juel:star draft-brief <ref> --project <name> --item <name> --out <path> [--feedback "<text>"]`
runs in the project's main checkout as an Orca worker. It never edits the repo; the brief at `--out`
is the only file it writes. It is unattended: nobody is at its terminal, so it never asks there.
Where a step below says ask, it sends `orca orchestration ask --question "<question>" --json` and
waits for the reply; a reply of "No answer … escalate this." ends the run with
`ESCALATION item=<name> phase=0 reason=unanswered-question needs=<the question>`.

1. Read `<HOME_DIR>/memory/global.md` and `<HOME_DIR>/memory/<project>.md` (HOME_DIR is two levels
   above `--out`'s directory).
2. Resolve the project's work source: an explicit source in the ref → `.claude/workflow.local.json`
   / `.claude/workflow.json` `tracker` → a `## Work Source` block in CLAUDE.md or AGENTS.md → the
   legacy `## Linear Worktrees Config` block → the ref's shape when unambiguous (`#412` is GitHub; an
   existing path is a `file` item) → the single connected tracker. Still ambiguous → `ESCALATION
   item=<ref> phase=0 reason=needs-human-input needs=which tracker holds <ref>`.
3. Fetch the item in full:

| Provider | `list` | `fetch` |
|---|---|---|
| `linear` | resolve `LINEAR_PREFIX` (`mcp__linear__` or `mcp__claude_ai_Linear__`, whichever exposes a domain tool), then `<LINEAR_PREFIX>list_issues(assignee: "me", project: <id>, state: "Todo")` | `<LINEAR_PREFIX>get_issue(id: <ref>)` |
| `jira` | the connected Jira/Atlassian MCP's JQL search: `assignee = currentUser() AND project = <key> AND statusCategory = "To Do"` | the MCP's get-issue tool |
| `github` | `gh issue list --assignee @me --state open --limit 200 --json number,title,url,labels` (skip `status:in-progress` / `status:in-review`) | `gh issue view <n> --json number,title,body,url,labels` |
| `file` | `*.md` in the spec directory whose status is explicitly `todo` | read the file |

4. Normalize: `ref` (null when the source has none), `slug` (kebab-case from the title, at most 6
   words), `title`, `url`, `path` (a `file` item's absolute spec path), `source`, `labels`,
   description, acceptance criteria. The item's name is `--item`, exactly as given: STAR already
   uses it for the row and the paths, and every later report line must carry it.
5. Resolve the repo's conventions: remote (one → it, else `origin`, else ask), base branch
(`config.baseBranch` → `git config --get claude.baseBranch` → `git symbolic-ref --short
refs/remotes/<remote>/HEAD` → first existing of main/master/develop/dev/trunk → ask once), and branch
naming (sample `git for-each-ref --sort=-committerdate --count=60 refs/remotes/<remote>`, take the
modal pattern; default `{type}/{ref-lower}-{slug}`, `{type}/{slug}` when the ref is null, and a
GitHub ref `#412` renders as `issue-412`; type is `fix` for bug/fix/error, `refactor`, `chore`, else
`feat`).
6. Read enough of the code to propose an approach, then write the brief to `--out`. With
   `--feedback`, read the existing brief at `--out` first and revise it to answer the feedback.

   ```markdown
   ---
   juel_brief: 1
   item:
     name: <the --item value>
     ref: <ref or null>
     slug: <slug>
     title: <title>
     url: <url>            # omit when absent
     path: <absolute spec path — file sources only>
     source: <source>
     labels: [<labels>]
   branch: <branch>
   baseBranch: <base>
   approved:               # stamped by STAR when the user approves
   star:
     home: <HOME_DIR>
     project: <project>
     notes: [<HOME_DIR>/memory/global.md, <HOME_DIR>/memory/<project>.md]
     reviews: <HOME_DIR>/reviews/<project>
     gates: <HOME_DIR>/gates/<project>/<item>.json
   ---
   ## Work item
   <description, verbatim>
   ## Acceptance criteria
   - [ ] <one per criterion from the item>
   ## Approach
   <2-6 sentences: the chosen approach, the components touched>
   ## Scope
   In: <what this item changes>
   Out: <what it deliberately does not touch>
   ```

   Acceptance criteria come from the item. When it has none, write the single line
   `- [ ] NEEDS CRITERIA` and never invent any.
7. Report, as the `worker_done` body: `BRIEF item=<name> path=<--out>`, then `NEEDS-CRITERIA` when
   that applies, then at most one `NOTE: <one line>`.

## Exact-head verification

`sh S/pr-verify.sh <pr url> --head <head from the ledger>` prints one line:

| Verdict | Row in `verifying` | Row in `ready` |
|---|---|---|
| `PASS` | → `ready`; free the review slot; queue `--kind merge-pr`; notify | nothing |
| `PENDING <what>` | first time: record `retry-not-before <now + 2 min>` in `verify` and check again in a later tick; second time: → `escalated`, queue `--kind escalation` "<what> still pending" | nothing |
| `MOVED <head>` | first time for this item → `babysit-queued`, and note `moved 1` in `verify` (its own budget, separate from `restarts`); a second time → `escalated`, queue `--kind escalation` "head keeps moving" | the same, and close its `merge-pr` item |
| `MERGED <sha>` | as for `ready` | close its `merge-pr` item, then `sh S/release-record.sh --home HOME_DIR --project <p> --item <i> --pr <url>`; row → `done`; print the record's path |
| `FAIL <what>` | → `escalated`; queue `--kind escalation` "<what>" | → `escalated`; close its `merge-pr` item; queue `--kind escalation` "<what>" |

STAR never merges, and never marks a PR ready: babysit does that once, and the merge is the user's.

## Drafts

STAR writes for the user only what shipping needs, and sends none of it by itself:

- A babysit worker that escalates `ambiguous-review` first writes
  `HOME_DIR/drafts/<date>-<project>-<item>-reply.md` (each ambiguous comment, then two or three
  candidate decisions) and adds `DRAFT <path>` to its report. STAR queues it as `--kind draft` with
  the escalation; the user's answer on the escalation is the decision the next babysit run applies.
- "Draft a status note": STAR writes `HOME_DIR/drafts/<date>-status.md` from the ledger and the
  queue (its own small files) and queues it as `--kind draft`. The user sends it.

## Memory notes

`memory/global.md` and `memory/<project>.md` are read by every worker before it starts (the brief
lists them). Workers add to them only through a `NOTE:` line in their report, which STAR appends to
`memory/<project>.md`. The user edits or deletes notes freely. When a project file passes 80 lines,
queue `--kind held` "trim memory/<project>.md" instead of trimming it yourself.

## Pools and the memory check

Before every `worker-start`:

```sh
pg=$(vm_stat | sed -n 's/.*page size of \([0-9]*\) bytes.*/\1/p')
fr=$(vm_stat | sed -n 's/^Pages free: *\([0-9]*\)\./\1/p')
in=$(vm_stat | sed -n 's/^Pages inactive: *\([0-9]*\)\./\1/p')
echo $(( (fr + in) * pg / 1073741824 ))   # GB free + inactive
```

Under 3 GB free + inactive → do not start; note `HOLD: memory` in the row's `updated` cell and try
again at the next tick. Heavy test and build gates inside workers take turns through
`juel:ship-ticket`'s `gate-lock.sh`, which uses one lock under STAR's home (`HOME_DIR/gate.lock`),
so workers in different projects wait for each other too. `vm_stat` and `caffeinate` are macOS
tools; on Linux read the `available` column of `free -g` and skip `caffeinate`.

## Notifications and quiet hours

`star.json` keeps `notifiedThrough`, the highest queue id the user has been notified about. At the
end of a tick outside quiet hours, when `loops.sh list` shows open items above it: print them, send
one push notification naming them (Claude Code's `PushNotification` tool, loaded with `ToolSearch`
when deferred; printing is enough when it does not exist), and advance `notifiedThrough`. Inside
quiet hours only `escalation` items notify; everything else waits for the first tick after the
window, so a restart never loses a notification. A question's 30-minute deadline starts when it is
notified.

Workers get the quiet window (`--quiet-hours`) and decide at each outward action: they keep
building, reviewing, fixing and pushing, while marking ready, replying to reviewers, re-requesting
review and status writes wait for the window to end or come back as `HELD` lines.

## Handoff

The handoff is how the user leaves and comes back without losing anything. `handoff.md` only lists:
the queue stays the one place to answer, so an answer can never exist in two files.

**Away** (`/juel:star away`, "I'm leaving", or a `control: away` inbox file):

1. Finish the current tick, so the queue and ledger are current.
2. `sh S/handoff.sh --home HOME_DIR start` writes `handoff.md` and marks `away` in `star.json`. Its
   three parts come straight from the files: **A. Needs you now** (queue items that block work:
   briefs to approve, questions, escalations, restarts), **B. Waits for you** (merges, drafts, held
   actions), **C. What runs while you're away** (each open item and where it will stop).
3. Print part A and ask the user to answer those before they go. Do not wait for them: answers
   that arrive are handled like any other.

**While away:**

- Build, second-model review and fix stages keep running, started with `--quiet-hours always`, so
  their status writes come back as `HELD`.
- No babysit stage is started: a row that reaches `babysit-queued` waits there, so no new PR is
  marked ready and no human reviewer is pinged until the user is back. Babysit workers that were
  already running are left alone and keep their own quiet window.
- Only `escalation` items notify, as inside quiet hours.
- About every 4 hours (housekeeping's `handoff.sh due`), `handoff.sh summary` adds a dated summary
  to the top of `handoff.md`: items per state, PRs ready for the merge, what merged, what stopped,
  everything in `sent.log` since the last summary, free memory and running workers, and the full
  Needs-you list again. The heartbeat keeps this going while STAR is idle. It needs STAR's session
  to be open: with the session closed, workers continue but no summary is written.

**Back** (`/juel:star back`, "I'm back", or a `control: back` inbox file):

1. `sh S/handoff.sh --home HOME_DIR end` clears `away` and prints the latest summary. Print it, then
   the open queue (`loops.sh list`).
2. Send the notifications that were held, and let the next tick start babysitting for the rows
   waiting in `babysit-queued`.
3. As the user answers, in the file or in chat, record each answer and act on it in the same turn.

## Recovery

- **Compaction:** Claude Code re-reads `HOME_DIR/CLAUDE.md`, and the plugin's session hook repeats
  the instruction: run `/juel:star` if you are not in a tick. Nothing is needed from the user.
- **A closed session:** workers keep running and their reports wait in the Orca run. The user
  reopens a terminal in STAR's home (`claude --continue`, or a new session) and runs `/juel:star`.
- **An Orca restart:** every worker is gone. The reconcile step restarts review, babysit and brief
  stages once and queues lost builds and fixes for the user.

## Hard rules

- **Never merge a PR**, and never start a worker that would.
- Never read review, evidence, log or diff content into this session. One line per fact, from a
  script or a report.
- A brief is never built before the user approves it in the queue. Approval is never inferred.
- A `failed` or `escalated` row is never re-run without the user's answer, except the single
  automatic restart of a review, babysit or brief stage lost to a restart.
- Workers are started only through `orca orchestration worker-start`.
- `open-loops.md` is written only through `loops.sh`.

## Common mistakes

| Mistake | Fix |
|---|---|
| Opening a review file "to summarize it" | The queue item carries the path; the user reads it. STAR reads the verdict line |
| Editing `open-loops.md` with Edit or sed | `loops.sh` only: it keeps what the user typed |
| Treating a `merge-pr` answer as a merge | Only `pr-verify.sh` printing `MERGED` moves the row |
| Starting the build worker before the branch is right | Reuse, create, switch or rename, copy, then start |
| Ticking forever with nothing to do | When every row waits on the user or is finished, go idle and end the turn |
| Batching ledger writes to the end of a tick | Write after every message, before `processed.log` and the ack |
| Answering a worker's TUI prompt | `worker-probe.sh` says stuck → stop it, fail the row, queue it |

## Edge cases

| Situation | Handling |
|---|---|
| `add` while STAR is stopped | The inbox file is written; the item waits in the inbox |
| The same item name in two projects | Rows, briefs, reviews and records are all keyed by project |
| `loops.sh` exits 3 (conflict markers in `open-loops.md`) | Stop writing the queue, tell the user to resolve the file, keep workers running |
| A project not registered with Orca | `--kind held` "register <repo> with Orca"; its inbox file stays until it is |
| `codex` missing | The reviewer runs on claude with a different model; say so |
| The home has uncommitted edits by the user | `git add -A` in the tick's commit includes them; never discard them |
