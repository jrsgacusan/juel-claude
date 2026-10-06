---
name: star
description: Use to run STAR, a local coordinator that ships a project's work items to merged-ready PRs. Type "/juel:star <refs>" in the project - the session becomes the coordinator, or hands the refs to the one already running, and its state lives inside the project, git-ignored, under docs/superpowers/context/star - a queue with Answer slots, a ledger, briefs, release records and memory notes. A worker drafts a brief per item for your approval, then Orca workers build, a second model reviews the draft PR, fixes land, and the PR is babysat until it is approved, green and verified on its exact head. STAR never reads big output, recovers by itself after compaction, and never merges. Triggers "start STAR", "add this to STAR", "what does STAR need from me", "/juel:star".
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
        why: star-home.sh finds the project's main checkout with it, and workers branch and push
        check: "command -v git"
      - id: python3
        hard: true
        why: star-home.sh, loops.sh, pr-verify.sh, worker-probe.sh, release-record.sh, handoff.sh and the session hook run on it
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
      - id: git-repo
        hard: true
        why: STAR's state lives inside the project it is invoked in
        check: "git rev-parse --show-toplevel"
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

STAR is one long-running coordinator session for shipping one project's work. You start it by
typing `/juel:star` in the project; that session plans, hands out work, checks results and keeps
the queue. It never writes code and never reads big output. Real work goes to Orca workers: a
fresh agent per stage, in the item's own worktree, that reports in at most 12 lines and is
released. Everything that matters lives in files inside the project, in a git-ignored folder,
never only in chat, so a compacted or restarted STAR reads them and carries on. It follows the
artifact "My 24/7 Agent Setup". **You merge; nothing here does.**

**Announce:** "Using juel:star." (in hand-over, `status` and `draft-brief` modes: say which mode.)

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

`status`, `away`, `back`, `stop` and `draft-brief` are not a start: they skip this table (each
states its own needs below) and the task list, and announce their own mode. So does a
`/juel:star <refs>` that finds STAR already running for this project in another terminal: it
hands the refs over and ends. Everything else is the start mode. `stop` typed in STAR's own
session is the Stop rule below, nothing more: it does not run the start sequence first.

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
| inside a git repository | context | HARD | `git rev-parse --show-toplevel` | STOP → run `/juel:star` from inside the project's repository |
| AskUserQuestion | context | HARD | always available interactively | STOP → the first run asks one setup question |
| juel:ship-ticket, juel:babysit-pr, juel:receive-review-and-execute | skill | HARD | ship with this plugin | STOP |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Preflight — binaries, the Orca runtime and terminal, the project's repository
2. Create the project's STAR folder with `star-home.sh init`, or load the existing one
3. Bind the Orca run, start caffeinate, register the heartbeat
4. Reconcile every row in a worker stage
5. Tick until idle or stopped
6. On stop: write the Resume block, stop caffeinate and the heartbeat, report

Phase 5 repeats. Keep its task `in_progress` across ticks and put the tick's one-line summary in its
evidence; it completes when STAR goes idle or is stopped.

## Commands

Typed in the project (its main checkout, a linked worktree or any subfolder):

| Command | Effect |
|---|---|
| `/juel:star SPH-11 and SPH-12` | STAR is not running for this project: this session becomes the coordinator, adds both refs and starts. STAR is running in another live terminal: this session hands the refs to it and stays free |
| `/juel:star` | Start STAR for this project, or resume it: the two are the same command |
| `/juel:star status` | Print the Needs-you block and counts per state. Read-only |
| `/juel:star away` (or tell STAR "I'm leaving") | Write the handoff file and switch to away mode (below) |
| `/juel:star back` (or tell STAR "I'm back") | Print the latest summary and the queue; leave away mode |
| `/juel:star stop` | Finish the tick and stop. Running workers are left to finish; their reports wait in the Orca run |
| `/juel:star draft-brief <ref> --project <name> --out <path>` | Worker mode, below: a brief worker's command, never the user's |

`S` is this skill's directory (`${CLAUDE_PLUGIN_ROOT}/skills/star` when that is set, else the
directory of this file); scripts are run as `sh S/<name>.sh`. `HOME_DIR` is the project's STAR
folder, and it is never worked out by hand: `sh S/star-home.sh path` prints it and
`sh S/star-home.sh init` creates it. It is `<main checkout>/docs/superpowers/context/star` (under
the project's own docs folder when it has configured another), so every worktree of a project
shares one folder and a project has exactly one STAR.

The session that becomes the coordinator should be an Orca terminal running Claude Code on
Fable 5.1 (`claude --model fable`); the stage table under "STAR's home" says why. The skill does
not check the session's model.

### Reading the command

Everything after `/juel:star` is read as words. A first word of `status`, `away`, `back`, `stop`
or `draft-brief` is that command. Otherwise every word that is a work-item ref (`SPH-11`, `#412`)
or a path to a spec file is a ref, and the rest is ignored: `SPH-11 and SPH-12`, `SPH-11, SPH-12`
and `add SPH-11 SPH-12` are the same request. Words that say something about the items ("the
second one is urgent") go into the inbox file's `note:` line.

### Coordinator, or hand-over

1. `HOME_DIR=$(sh S/star-home.sh path)`. Exit 1 (not inside a project's repository) → say so in one
   line and stop. `path` creates nothing.
2. When `HOME_DIR/star.json` exists, read its `terminal`. It names a terminal that is not this
   session's `$ORCA_TERMINAL_HANDLE` and that `orca terminal list --limit 500 --json` still lists
   (and the user did not say "take over") → **hand-over**: STAR is running there, and this session hands the refs to it. Write them as an
   inbox file (below), nudge it with `orca terminal send --terminal <handle> --text "inbox" --enter`,
   say "STAR for <project> runs in <handle>; I handed it <refs>", and end. With no refs, say where
   it runs and print `status`. Hand-over needs no Orca terminal. The list cannot be read → write
   the inbox file, say that it could not be checked whether STAR is running, and end: never become
   a second coordinator on a guess.
3. Otherwise **this session becomes the coordinator**: run the Preflight table (a STOP there leaves
   the project untouched: nothing was created yet), then `sh S/star-home.sh init`, write any refs as
   an inbox file, then the start sequence ("Start, resume, stop"). The first tick ingests them.

An inbox file is `HOME_DIR/inbox/<UTC YYYYMMDDTHHMMSSZ>-<4 random hex>.md` (never overwrite an existing inbox file;
pick another suffix):

```
repo: <absolute path of the main checkout>
refs:
- <ref or absolute spec path>
note: <anything the user said about these items, one line; omit when nothing>
```

A message to STAR that says only `inbox` means "run a tick now".

### `status`

`HOME_DIR=$(sh S/star-home.sh path)`. No `star.json` there → "STAR has not been started in this
project." Otherwise `sh S/loops.sh --file HOME_DIR/open-loops.md list`, then counts per state from
`ledger.md`. Print both. Nothing else.

### `away`, `back` and `stop` from another session

In STAR's own session these run directly (see "Handoff" and "Stop"). From any other session of
the project: write `HOME_DIR/inbox/<UTC timestamp>-control-<4 random hex>.md` containing the single
line `control: away` (or `control: back`, `control: stop`), then nudge STAR as in hand-over. STAR
not running → say so; the control file waits in the inbox.

## STAR's home

`sh S/star-home.sh init` creates it the first time `/juel:star` runs in a project: the queue, the
ledger and `star.json` from `S/template/`, the folders below, and one line in the repository's
`.git/info/exclude` so git ignores it (never `.gitignore`: nothing shows as a change, and a
read-only repository is fine). It records the project in `star.json` as
`"project": {"name": <the main checkout's folder name>, "repo": <its path>}`. On the first start
(`run` in `star.json` is still null, which is true exactly once) STAR adds what it learns about
the project to that block, as `orcaRepo` (the id from `orca repo list --json`, by repo path),
`source` (the work source), `base` (the base branch) and `remote`. Then it asks once, with
AskUserQuestion, for a quiet window ("no reviewer pings, ready-marking or status changes while
you're away?"), writes it to `star.json`, and tells the user where the queue is:
`HOME_DIR/open-loops.md`.

These files are plain local files. They are not a repository of their own: nothing is committed
or pushed, and the standing instructions a session needs after a compaction come from the
plugin's session hook ("Recovery").

```
star.json               settings (below) plus "project", run id, STAR's terminal handle, caffeinate pid, heartbeat id, "notified", "away"
open-loops.md           Resume block, then Needs you, then Waiting on others   (written only through loops.sh)
open-loops-archive.md   closed items
open-loops.md.seq       the highest queue id ever used (so an id is never handed out twice)
handoff.md              the "before you go" lists and the summaries written while the user is away (handoff.sh)
sent.log                <iso>\t<project>\t<item>\t<what was sent>: every message a worker or STAR posted
ledger.md               one row per item
processed.log           <message id> <dispatch> <iso time>
inbox/                  one file per hand-over; deleted once ingested
briefs/<project>/<item>.md
reviews/<project>/<item>-r<k>.md   and   <item>-r<k>-fix.md
gates/<project>/<item>.json
releases/<YYYY-MM-DD>-<project>-<item>.md
drafts/<YYYY-MM-DD>-<project>-<item>-<kind>.md
memory/<project>.md
```

`<project>` is the name in `star.json`. A folder holds one project; the name stays in the paths,
the queue and the ledger so every file says what it belongs to.

Settings in `star.json`:

```jsonc
{
  "maxParallel": 3,                                      // build pool
  "maxInReview": 3,                                      // review pool
  "stages": {                                            // the best model for each stage's kind of work
    "brief":   { "agent": "claude", "model": "opus",        "effort": "xhigh" },
    "build":   { "agent": "claude", "model": "opus",        "effort": "xhigh", "executor": "session" },
    "fix":     { "agent": "claude", "model": "opus",        "effort": "xhigh", "executor": "session" },
    "review":  { "agent": "codex",  "model": "gpt-6-astra", "effort": "xhigh" },
    "babysit": { "agent": "claude", "model": "opus",        "effort": "xhigh", "executor": "session" }
  },
  "worker":   { "agent": "claude", "model": "opus",        "effort": "xhigh" },   // a stage with no entry, and the fallback
  "reviewer": { "agent": "codex",  "model": "gpt-6-astra", "effort": "xhigh" },   // the same, for review
  "quietHours": { "tz": "Asia/Manila", "start": "22:00", "end": "07:00" }   // null = off
}
```

Each stage runs on `stages.<stage>`; a stage with no entry there (or a home with no `stages`
block) runs on `worker`, and review on `reviewer`. The defaults are the owner's choice of the best
model for each kind of work, by benchmark, among the models the two installed agents can run:

| Stage | Default | Why this one |
|---|---|---|
| STAR itself | Fable 5.1 (the model the STAR session is started on; not a setting here) | the strongest rule-following of the Claude models, with top-level reasoning |
| brief, build, fix, babysit | Opus 5.5, xhigh | the best agentic coding and plain coding available, and it acts on an Orca dispatch. Fable 5.1 scores higher on rule-following but, started as an Orca worker, it treated the dispatch as pasted text and did nothing until told to go ahead (tried 2026-10-07): do not put it on a worker stage without trying that again |
| review | GPT-6-Astra, xhigh | the highest reasoning score, and a different model family from the builder |

`executor` says who runs a written plan inside a stage: `session` (the worker's own model, the
default here, because the Claude models lead agentic coding) or `codex` (dispatch `codex exec`).
The reviewer must stay a different model family from the builder: a review by the builder's own
family is a weaker second opinion. Effort is `xhigh` on every stage. These are the most capable models and
they use more of the Claude and Codex usage limits than a mid-tier setup; `max` effort costs
about three times `xhigh` for a gain the benchmark cannot show reliably, so it is not the
default.

A model of `default` means: pass neither `--model` nor `--effort`. Model ids come from the CLIs,
never from memory.

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
| a worker asked something the brief does not answer | `loops.sh add --kind question --project <p> --item <i> --title "<the question, one line>" --body "msg: <id>\ndeadline: <iso>"` (the `msg: <id>` line is the Orca message id the reply needs after a restart; the deadline is the time the message was sent plus 30 minutes, taken from the message itself, so a replay writes the same item) |
| a build or fix was lost to a restart | `loops.sh add --kind restart-or-drop --project <p> --item <i> --title "<stage> was interrupted" --body "worktree: <path> (it must be clean before a restart: commit or discard what the interrupted run left)\nOptions: restart / drop"` |
| a draft is ready | `loops.sh add --kind draft --project <p> --item <i> --title "<what the draft is>" --body "<draft path>\nOptions: send / drop"` |
| a worker held an outward action | `loops.sh add --kind held --project <p> --item <i> --title "<action>" --body "Options: done"` |

Open items are repeated in every status line STAR prints, by id and title, until they are answered:
silence means missed, not no.

`loops.sh add` is safe to repeat: asked for an item that is already open with the same kind,
project, item and title, it prints that item's id and adds nothing. It refuses (exit 64) a project
or item with a line break or ` · ` in it, and it writes body lines that look like headings or
`Answer:` lines as quotes, so text from a ticket or a worker can never forge an answer.

Every transition into `escalated` or `failed` queues a `--kind escalation` item in the same step,
so no row is ever stranded: its answer either runs the stage again with the user's decision or
drops the row. A `held` item is only a reminder of an outward action; closing it changes no row.

### The ledger

`| item | ref | project | worktree | state | stage | round | task | dispatch | restarts | pr | head | cursor | verify | counters | updated |`

`updated` holds one UTC time, `YYYY-MM-DDTHH:MM:SSZ`, and nothing else (the handoff summary reads
it). `verify` holds `retry=<iso>` or `-`. Every count STAR needs across ticks lives in `counters`
as space-separated `key=n` pairs, `-` when there are none:

| Key | Counts | Cleared when |
|---|---|---|
| `miss=1` | a reviewer report with no `VERDICT` line, this round | a verdict arrives |
| `silent=<n>` | probes in a row that said `settled` with no report processed | a report is processed |
| `unknown=<n>` | probes in a row that said `unknown` | any other probe result |
| `hold=<n>` | ticks in a row this row could not start for lack of memory | it starts |
| `moved=<n>` | exact-head checks that found the head moved | the row reaches `ready`, or the user answers its escalation |
| `pending=<n>` | exact-head checks in a row that said `PENDING` | any other verdict |
| `nudge=<n>` | check-ins sent to this row's worker with no report since | a report from it is processed, or a new worker starts |
| `last=<message id>` | not a count: the id of the last message applied to this row | never; the next message overwrites it |

A cell never contains `|` or a line break: replace them with `/` and a space.

**An item has one name everywhere**, set once at ingest and used for its row, its brief, review
and gate paths, its worktree and every report line: a tracker ref as written (`SAVI-1162`); a
GitHub ref `#<n>` becomes `issue-<n>`; a spec path becomes the kebab-case of its file name without
the extension. A name is also a file name and a worktree name, so it keeps only `A-Za-z0-9._-`:
every other character becomes `-`, a leading `.` or `-` is dropped, and it is cut at 60 characters.
The raw reference stays in the `ref` column and is what the brief worker fetches.

A ref that already has a row in that project which is not `done` or `dropped` is the same item: no new row
(a ref handed over twice, or an inbox file read twice after a restart, changes nothing; say so in the status
line). A name is used once per project, ever: a different ref that maps to a taken name, and
a ref whose earlier row is `done` or `dropped` and is added again, get `-2`, `-3`. The new row
then has its own brief, reviews and queue items, and an answer can never land on the old row.

| State | Pool | Meaning |
|---|---|---|
| `inbox` | — | ingested; waiting for a build slot to draft its brief |
| `briefing` | build | a brief worker is reading the item and the code |
| `brief-ready` | — | brief drafted; waiting for the user's approval |
| `queued` | — | approved; waiting for a build slot |
| `building` | build | build worker running |
| `pr-draft` | — | draft PR open; waiting for a review slot |
| `reviewing` | review | second-model reviewer running |
| `fix-queued` | — | the review said NOT-SAFE; waiting for a build slot to fix |
| `fixing` | build | fix worker running |
| `babysit-queued` | — | waiting for a review slot to start babysitting (after SAFE, or again after the head moved) |
| `babysitting` | review | babysit worker running |
| `verifying` | review | `READY` received; exact-head check pending |
| `ready` | — | approved, green, verified; waiting for the user's merge |
| `done` | — | merged; release record written |
| `escalated` | — | stopped on an escalation; in the queue |
| `failed` | — | a worker settled without its report or could not start; in the queue |
| `dropped` | — | the user dropped it |

Build pool (at most `maxParallel`): `fix-queued` rows first, then `inbox` rows (briefs are short
and unblock the user), then `queued` rows; within each, the oldest `updated` first. Review pool (at
most `maxInReview`): `babysit-queued` rows first, then the oldest `pr-draft`. A row counts against
a pool exactly while its state is one the table marks `build` or `review`.

Each stage has a waiting state, used whenever a stage is to run (again): brief → `inbox`, build →
`queued`, review → `pr-draft`, fix → `fix-queued`, babysit → `babysit-queued`. Nothing starts a
worker except "Fill slots", so a restarted stage waits for its pool like any other.

## Start, resume, stop

`/juel:star` in a project whose folder already has rows is a resume; there is no separate command.

**One STAR per home**, and a home is one project's folder. "Coordinator, or hand-over" above
already decided that this session is to be the coordinator: `star.json` named no terminal, or
this one, or one that `orca terminal list --limit 500 --json` no longer lists (a closed session).
A handle that is still listed belongs to a running STAR, and this session handed its refs over
and ended. When the list cannot be read, STOP: no answer is not proof that the other session is
gone. If that session is dead but its terminal is still open, the user says "take over" here.
Two coordinators would fill the same slot twice and overwrite each other's ledger.

Then claim the home: write this session's handle to `star.json` at once and read it back after
the next command. Another handle there means a second STAR started in the same moment: STOP.
"take over" from the user, in this session, is the one way past a listed handle: it skips the
check and claims the home.

**The claim is checked again at the start of every tick**, which is what makes the rule hold
however two sessions raced, and what stops a session that was taken over: re-read `terminal` in
`star.json`; when it is not this session's handle, this session is no longer STAR. Delete this
session's own heartbeat job (find it with `CronList` by its prompt: the id in `star.json` now
belongs to the other session), do nothing else (no slot, no ledger write, no ack), say "STAR now
runs in <handle>", and end the turn.

1. `orca orchestration run-use --id <run from star.json> --json`; when that run no longer exists,
   `orca orchestration run-create --objective "STAR" --json`. Record the run id and
   `$ORCA_TERMINAL_HANDLE` in `star.json`.
2. `caffeinate`: when `star.json` has a pid and `ps -p <pid> -o comm=` prints `caffeinate`, kill it.
   Start a new one (`caffeinate -dimsu >/dev/null 2>&1 &`) and record its pid. It deliberately
   outlives a closed session, so the workers' Mac stays awake.
3. Heartbeat: load the scheduler (`ToolSearch("select:CronCreate,CronDelete")`), delete the job id in
   `star.json` if any, and create a recurring job `7,37 * * * *` with the prompt
   `STAR heartbeat: if you are not already in a tick, run one.` Record its id and, as `heartbeatAt`,
   the time. Jobs fire only while the session is idle and die with the session, which is why every
   start registers a fresh one. A recurring job also expires by itself after 7 days: any tick that
   finds `heartbeatAt` 6 or more days old deletes the job and registers a new one, the same way.
   No scheduler tool → skip it and say so: an idle STAR then wakes only on a hand-over nudge or the user, so
   away summaries and answers typed into the queue file wait for one of those.
4. **Reconcile** every row in a worker stage with `sh S/worker-probe.sh <dispatch>`:
   `ok` or `quiet …` → keep it. `settled <state>` → its report is in the run's inbox; the settlement rule below
   catches it if it is not. `gone` → Orca has no such worker (an Orca restart): a `briefing`,
   `reviewing` or `babysitting` row restarts once on its own (`restarts` column: set it to 1 and
   put the row in its stage's waiting state; `restarts` goes back to 0 whenever the row moves on to a new stage; babysit resumes with `--since <cursor>`), because
   those stages can pick up safely; a row whose `restarts` is already 1 → `failed`, queue
   `--kind escalation` "<stage> worker lost twice". For a lost `building` or `fixing` row,
   queue `--kind restart-or-drop` and set the row to `failed` (restarting a half-finished build
   blindly would build on a dirty worktree, and a dead row must not keep holding a build slot or
   keep STAR ticking all night). `stuck: <what>` → as in housekeeping. `unknown <why>` (which includes empty or unreadable Orca
   output) says nothing about the worker: keep the row and let housekeeping probe it again; it
   never justifies a restart. A `verifying` row has no worker: never restart it, and run the
   exact-head check for it only when its `verify` is `-` or its `retry=` time has passed (a resume
   inside the two-minute wait must not count as the second `PENDING`). A row in a worker stage with no task never started (STAR stopped between
   writing the row and `task-create`): put it back in its stage's waiting state, no restart counted.
   A row with a task but no dispatch: `orca orchestration dispatch-show --task <id> --json`; record
   the dispatch it shows and probe it, or, when it shows none, treat the row as one with no task.
5. `loops.sh resume --state running --run <id> --pools "build <n>/<max> · review <n>/<max>" --next "<one line>"`, then tick.

A stop or an "I'm leaving" said in chat is written down at once, before the tick goes on: a file
`HOME_DIR/inbox/<UTC timestamp>-control-<4 random hex>.md` with the line `control: stop` (or
`control: away`). A compaction in the middle of a tick then cannot lose it: the next tick's Inbox
step finds it. A control file is acted on once: whoever carries the command out, this turn at the
end of the tick or the Inbox step later, deletes the file in the same step. And a start (before
its first tick) deletes every `control: stop` file it finds: a stop older than this start has
already happened, and must not stop STAR again.

**Stop** (`/juel:star stop`, the user says stop, or a `control: stop` file): finish the current tick, kill the recorded
caffeinate (only when `ps -p <pid> -o comm=` still prints `caffeinate`), delete the heartbeat, `loops.sh resume --state stopped --next "run /juel:star to resume"`, set
`"terminal": null` in `star.json` (the claim is released, so the session hook goes quiet and the
next `/juel:star` in this project becomes the coordinator), and print the queue. Workers still running are left alone.

## The tick

Never call AskUserQuestion inside a tick: it would block every other item until answered. Questions
for the user go into the queue and are notified; the answer arrives in the file or as an ordinary
message.

**Persist before acting.** Write the row before every `task-create` (state, stage, round), record
the task id right after `task-create` and the dispatch id right after `worker-start`.
Write the whole ledger right after each message's transition, then append the message to
`processed.log`, and only then acknowledge the delivery (step 3). A message already in
`processed.log` is skipped (its worker was released before that line was written). Every row write that a message causes also puts `last=<message id>`
in that row's `counters`, in the same write. A message whose id is already the row's `last=` is
already applied to it: do not match it against the table again, do not run the exact-head check
again and do not count anything; do only what comes after the row (`worker-release`,
`processed.log`, the ack). This is what makes a replay safe when STAR stopped between the row and `processed.log`.

**Match by dispatch, not by name.** A message belongs to the row whose `dispatch` cell equals the
message's dispatch id (`payload.dispatchId`); the `item=` in its first line must then be that row's
item. Item names can repeat, so a name alone never selects a row. A message changes no
row, and is queued as `--kind held` with its first line, when its dispatch is in no row (or it
carries no dispatch id: `--project - --item <the dispatch id, or unmatched>`), when its
row is `done` or `dropped`, or when the row has moved on to a newer dispatch (a superseded attempt:
a round-1 verdict arriving after round 2 started). Two exceptions change nothing and queue
nothing: a message already applied (its id is the row's `last=`), and the `worker_done` of
a dispatch STAR stopped itself (a drop, an early merge, a closed PR): write it to `processed.log`
and move on.

**One message, one order of effects:** queue items first (`loops.sh add` returns the open item's
id when it is already there, so a replayed message adds nothing), then the `NOTE` and `SENT`
appends (each line carries the time the message was sent, not the time of the append, so a
replay writes the identical line: skip a line the file already has), then the row with its
`last=`, then, for a settled `worker_done`, `worker-release`, then `processed.log`, then the ack
(releasing a worker that is already released is harmless, so it always comes before the line
that ends the message). A question STAR answers itself follows the same order: the `## Decisions`
line (skip it when the brief already has that line), the `reply`, then the row with
`last=<message id>`, then `processed.log` (a second reply to the same message is harmless; a
missing one leaves the worker blocked).

**A worker STAR stops itself is put on record first:** before `worker-stop` (a drop, an early
merge, a closed PR, a stuck screen), append `<dispatch> stopped <iso>` to `processed.log`. A
message from a dispatch listed as stopped is written to `processed.log` and changes nothing else,
also after a restart, when STAR no longer remembers stopping it. `release-record.sh` is safe to repeat: it
prints the existing record for a PR that already has one. A stop anywhere in that order replays the
message into the same end state.

0. **Still STAR?** The claim check from "One STAR per home": `terminal` in `star.json` is this
   session's handle, or this session ends the turn without acting.
1. **Inbox.** Read `HOME_DIR/inbox/*.md` in file-name order (the names start with a UTC time, so
   that is the order they were written in). A file whose only line is `control: away`,
   `control: back` or `control: stop` is that command: run it (see "Handoff" and "Stop") and delete
   the file. For each other file: its `repo:` must be this project's (`project.repo` in
   `star.json`); a file for another repository is not ingested: queue `--kind held` "inbox file for
   <repo>: STAR here ships <project> only" and delete it. The project is not registered with Orca
   (no repo id in `star.json`, and `orca repo list --json` has no entry for the repo path) →
   `--kind held` "register this repo with Orca: orca repo add" and leave the file: the queue keeps
   one such item, however many ticks pass. Otherwise add one `inbox` row per ref with its item
   name (the naming rule above) and the raw reference in `ref`, skipping a ref that already has an
   open row, write the ledger, then delete the file.
2. **Answers.** `sh S/loops.sh answers` prints one line per answered item. Act, then
   `loops.sh close <id>` (exit 4 means it is already closed: carry on). A command word counts only when it is
   the whole answer: lower-case it, strip punctuation, and compare all of it with `approve`, `yes`,
   `ok`, `drop`, `drop it`, `drop it please`, `restart`, `send`, `done` or `not merging`. So
   `Drop.` and `restart!` count, while `approve, but rename the flag` and `Drop the retry wrapper
   and call the queue directly` do not: anything longer than the bare word is feedback or a
   decision, and goes to the "anything else" row of its kind. An answer with no letter or digit in
   it (`?`, `…`) is not an answer: add the item again with "(answer in words)" at the end of its
   title.

   Before acting on each answer, re-read the row it names. A row that is `done` or `dropped` takes
   no answer: close the item and do nothing (so a second answered item for the same row can never
   bring a dropped item back). A row in a worker stage whose probe says `settled` has a report
   that has not been applied yet: leave its answers for the next tick, after Messages has
   applied it.

   **An `escalation` answer for a row whose worker is still running** (its state is a worker stage
   and `sh S/worker-probe.sh <dispatch>` says `ok` or `quiet …`: a quiet worker is still a running worker) is handled first: `drop` stops the worker before
   the row changes (`orca orchestration worker-stop --dispatch <id> --json`, then `worker-release`);
   any other answer is appended to the brief's `## Decisions` and sent to that worker with
   `orca orchestration send --to dispatch:<id> --subject "decision" --body "<answer>" --json`, and
   the row stays as it is. An answer never starts a second worker for a row that has one.
   A `question` is always answered with `reply` (its worker is blocked waiting for exactly that),
   and `held` and `draft` answers never reach a worker.

   | Kind | Answer | Action |
   |---|---|---|
   | `approve-brief` | exactly `approve`, `yes` or `ok` (any case) | stamp `approved: <iso>` in the brief's frontmatter; row → `queued`. Not while the brief still says `NEEDS CRITERIA` (`grep -c 'NEEDS CRITERIA' <brief>` prints 1 or more): then nothing is stamped; add the item again titled "approve brief — it has no acceptance criteria yet: answer with the criteria" (an answer in words is feedback, and the brief worker writes the criteria from it) |
   | `approve-brief` | drop | row → `dropped` |
   | `approve-brief` | anything else, including "approve, but …" | it is feedback, never a conditional approval: append it to the brief file under `## Feedback` with the date (so it survives a restart of STAR), row → `inbox`; the brief stage then runs with `--feedback` |
   | `merge-pr` | drop / not merging | row → `dropped` |
   | `merge-pr` | anything else | nothing changes: a merge is detected from GitHub, never taken from an answer. After closing the item, add the same `merge-pr` item again, so the reminder stays in the queue |
   | `escalation` | drop | row → `dropped` |
   | `escalation` | anything else | the answer is the decision. Brief stage: append it to the brief file under `## Feedback` (creating the file with only that section when the worker stopped before writing a brief), row → `inbox`; the brief stage then runs with `--feedback`. `reason=no-safe-verdict` (the PR's head has no SAFE review): row → `pr-draft` for a new review round of the current head. A row with no PR whose worker lacked `gh`: an answer that is a PR URL records it, row → `pr-draft`. Any other stage: append the answer to the brief under `## Decisions` with the date (workers read that section first and treat it as binding; where two decisions disagree the later one wins), then put the row in the waiting state of the stage in its `stage` column (babysit resumes with `--since <cursor>`). A fix stage goes back to `fix-queued` only while `git -C <worktree> rev-parse HEAD` is still the row's `head` (the commit the review was written for); when the worktree has moved on (the interrupted run committed, or the user did), row → `pr-draft` instead, so the new commits get a review of their own. `reason=stale-review` from a fix worker means the same: row → `pr-draft`. After "review still NOT SAFE": row → `fix-queued` for one more fix and review round |
   | `question` | any | `orca orchestration reply --id <the item's msg id> --body "<answer>" --json` |
   | every `escalation` and `restart-or-drop` answer that runs a stage again | also clears every counter except `hold=` and `last=` from the row, and `restarts` goes back to 0: the user's "try again" starts with fresh budgets |
   | `restart-or-drop` | restart | `git -C <worktree> status --porcelain` must print nothing. Clean → the waiting state of its stage (`queued`; for a fix, `fix-queued` or `pr-draft` by the head rule in the `escalation` row). Not clean → change nothing and add the item again with the title "<stage> was interrupted: clean <worktree> first, then answer restart" |
   | `restart-or-drop` | drop | row → `dropped` |
   | `restart-or-drop` | anything else | add the item again with the title "<stage> was interrupted: answer restart or drop" |
   | `draft` | send | a draft whose first line is `to: pr <url>` is posted with `gh pr comment <url> --body-file <the rest>`; any other draft is the user's to send, say so. Before posting, append `<iso>\tSTAR\t<item>\tposted draft N-<id>` to `sent.log`; when that line is already there the draft was posted and only the close was lost: just close the item. Posting is an outward action: inside quiet hours or while the user is away, leave the item open (do not close it) and say "posts at the first tick outside the quiet window"; the Answers step sees it again every tick and posts it then |
   | `draft`, `held` | anything else | close it |
3. **Messages**, only while some row is in a worker stage or waiting for a slot:
   `orca orchestration check --wait --types worker_done,escalation,question`
   `--timeout-ms 540000 --json`, stdout only. The JSON carries a `deliveryId`; Orca replays that
   same batch until it is acknowledged. So once every message in it is in the ledger and in
   `processed.log`, the next wait is
   `orca orchestration check --ack <delivery_id> --wait --types worker_done,escalation,question --timeout-ms 540000 --json`
   (or `check --ack <delivery_id> --json` alone when STAR is about to go idle). A timeout is a tick. STAR reads only the report's
   lines (at most 12 lines); it never opens a review, evidence or log file, and never reads a
   worker's screen: the scripts do that and give one line back. A report longer than that: act on
   the first 12 lines and queue `--kind held` "<item>: report was cut at 12 lines".

   The first row that fits wins, top to bottom. A line that lacks a field its row names (`DONE`
   without `pr=`, `VERDICT` without `round=`) fits only the last row.

   | First line of the report | Action |
   |---|---|
   | `BRIEF item=… path=…` | row → `brief-ready`; queue `--kind approve-brief` (title "approve brief — add acceptance criteria first" when the report has a `NEEDS-CRITERIA` line) |
   | `DONE item=… pr=<url>` | record the PR; row → `pr-draft`; free the build slot. A compare URL (no `/pull/`) → `escalated`, queue `--kind escalation` "no gh on this machine: open a draft PR from <url>, then answer with the PR's URL" (and skip the worker's own `HELD … open a draft PR` line) |
   | `VERDICT item=… round=<k> SAFE findings=<n> head=<sha>` | record head; row → `babysit-queued`; free the review slot. `SAFE` wins whatever `findings=` says: they are notes. A `head=` that is not 7 to 40 hex characters is not a verdict babysit can use: treat the report as one with no `VERDICT` line (next row but two) |
   | `VERDICT … NOT-SAFE findings=<n>`, round 1 or 2 | row → `fix-queued`; free the review slot |
   | `VERDICT … NOT-SAFE`, round 3 or later | row → `escalated`; queue `--kind escalation` "review still NOT SAFE after <k> rounds" with the review's path |
   | a report from a reviewer (the row is `reviewing`) with no `VERDICT` line, including an empty one | `counters` has no `miss=1`: write it, row → `pr-draft`, and the same round runs once more. It has: → `escalated`, queue `--kind escalation` "reviewer gave no verdict twice" |
   | `FIXED item=… head=<sha>` | record head; row → `pr-draft`; free the build slot. The next review is `round + 1` (the first review is round 1; `round` is written when a review starts) |
   | `READY item=… pr=… head=<sha> cursor=<cursor>` | record head and cursor; row → `verifying`; run the exact-head check now. The cursor is an opaque string from `pr-state.sh` (a time, then `#` and the ids already seen in that second): store it and pass it back as `--since` exactly as it came |
   | `ESCALATION item=… phase=… reason=… [cursor=<cursor>] needs=…` in a `worker_done` | record `cursor` when given; row → `escalated`; queue `--kind escalation` (and `--kind draft` with it when the report has a `DRAFT <path>` line); notify; free the slot |
   | `MERGED item=… pr=<url>` (a babysit worker saw the user merge early) | handle it as `pr-verify.sh` printing `MERGED`: release record, row → `done` |
   | an `escalation` message while the worker still runs | queue it and notify, but keep the row and its slot until its `worker_done` arrives |
   | a `question` message | **STAR answers first** ("Looking after the workers"): when the answer is STAR's to give → `reply` at once and record it. When it is the user's: inside quiet hours, or while the user is away → reply "No answer from the user: escalate this." at once (nobody will read it in time); otherwise queue `--kind question`, notify, keep looping; the worker stays blocked and keeps its slot |
   | `CONFLICT:`, `AMBIGUOUS:`, `BRIEF-VIOLATION:` or `STOPPED:` (a `receive-review-and-execute` run that reported by itself) | as an `ESCALATION` whose reason is that word and whose `needs=` is the rest of the line |
   | anything else, or no report line | row → `failed`; queue `--kind escalation` quoting the first line; free the slot. Never re-run without the user's answer |

   `PHASE`, `PR`, `GATES` and `fixed=… rejected=…` lines need no action: the gate manifest is
   already at the brief's `star.gates` path, which the babysit stage is given.

   Also, for any report: each `HELD item=… action=…` line → `--kind held`; a `NOTE: <text>` line →
   append `- <date> <item>: <text>` to `HOME_DIR/memory/<project>.md`; a `SENT …` line → append
   `<iso>\t<project>\t<item>\t<the text after SENT>` to `HOME_DIR/sent.log`. STAR logs its own sends
   there too (a draft it posted with `gh pr comment`). After each settled
   `worker_done`: `orca orchestration worker-release --dispatch <id>` (in the order of effects
   above: before `processed.log`).
4. **Fill slots** by the pool rules above. Before filling, the PR check: for every row that has
   a PR and is `pr-draft`, `reviewing`, `fix-queued`, `fixing`, `babysit-queued`, `escalated` or `failed`,
   `sh S/pr-verify.sh <pr url> --head <head, or 0000000 when none is recorded>`. Only
   two answers matter here. `MERGED <sha>`: the user merged early; stop the row's worker if it has
   one (`worker-stop`, then `worker-release`), close the row's open `escalation` item if any, then
   handle it as `MERGED` below. `FAIL closed`: stop and release the worker, row → `escalated`,
   queue `--kind escalation` "PR was closed without a merge" (a row already `escalated` or
   `failed` only gets the queue item). Every other answer is ignored in these states. So no slot
   is ever given to an item whose PR is already merged or closed.
   Then, for each free slot, in this order: the memory check
   (below; too little memory starts nothing this tick), the row (state, stage, round), `task-create`
   (record the task), `worker-start` (record the dispatch). A fix or build never starts in a
   worktree named in another open row: → `failed`, queue `--kind escalation` "<worktree> is already
   in use by <other item>".
5. **Housekeeping.**
   - Questions past their deadline: reply "No answer from the user: escalate this." and close the item.
   - Each row in a worker stage that has not reported this tick: `sh S/worker-probe.sh <dispatch>`.
     `quiet <minutes> <terminal>` → check in on it ("Looking after the workers").
     `stuck: <what>` → `orca orchestration worker-stop`, then `worker-release`, row → `failed`, queue
     `--kind escalation` "<stage> worker stuck: <what>". `settled …` with no processed report:
     `silent=1` in `counters` the first time; the second time in a row → `failed`, release, queue
     it. `gone` → the reconcile rule for a lost worker. `unknown <why>` → `unknown=<n>` in
     `counters`; three ticks in a row → `failed`, queue it with `<why>` (the worker is not stopped:
     nothing is known about it). Never answer a worker's prompt for it.
   - `sh S/loops.sh list` printing a `missing` line (an id that was handed out and is now in
     neither the queue nor the archive: removed by hand, or lost when an editor saved an older
     copy of the file): say so in the status line, and add again any ask a row still needs (an
     open `escalated`, `failed`, `brief-ready` or `ready` row with no open item).
   - `verifying` rows past the `retry=` time in `verify`, and every `ready` row: the exact-head check (below).
   - Notifications (below).
   - Away: `sh S/handoff.sh --home HOME_DIR due` printing `due` → `sh S/handoff.sh --home HOME_DIR summary`.
6. **Write.** `loops.sh resume …` with the current pools and the next step;
   `loops.sh waiting "<one line per PR in review, per blocked question>"`. Nothing is committed:
   the folder is plain files. Print one status line: counts per state, then every open queue item.

**Active or idle.** While any row is in `inbox`, `briefing`, `queued`, `building`, `pr-draft`,
`reviewing`, `fix-queued`, `fixing`, `babysit-queued`, `babysitting` or `verifying`, stay in the turn and tick
again (step 3's bounded wait is the clock). When every row is waiting on the user or finished, write
`state: idle` and STAR ends its turn. It is woken by a hand-over nudge, by the user, or by the
heartbeat, and each wake runs one tick.

## Stages

Every stage is its own Orca task and a fresh worker.

| Stage | Worktree | Agent | Prompt |
|---|---|---|---|
| brief | the project's main checkout (`path:<repo path>`), read-only | `stages.brief` | `/juel:star draft-brief <ref> --project <name> --item <name> --out HOME_DIR/briefs/<project>/<item>.md [--feedback]` (the row's raw `ref`, then its item name) |
| build | a new Orca worktree in that project, set up as below | `stages.build` | `/juel:ship-ticket --unattended --brief HOME_DIR/briefs/<project>/<item>.md [--executor session] [--quiet-hours <window>]` |
| review | the item's worktree | `stages.review` | the reviewer prompt below |
| fix | the item's worktree | `stages.fix` | `/juel:ship-ticket --unattended --brief <brief> --fix-review HOME_DIR/reviews/<project>/<item>-r<k>.md [--executor session] [--quiet-hours <window>]` |
| babysit | the item's worktree | `stages.babysit` | `/juel:babysit-pr <n> --unattended --mark-ready --reviewed HOME_DIR/reviews/<project>/<item>-r<k>.md --item <item> --brief <brief> --gates-file HOME_DIR/gates/<project>/<item>.json [--executor session] [--since <cursor>] [--quiet-hours <window>]` (`--reviewed` is the review file of the round that said SAFE: the worker's proof before it marks the PR ready) |

**Build worktree.** Orca picks the new worktree's branch name (`<user>/<name>` when the repo has a
git username, else `<name>`) and cannot be told otherwise, and `ship-ticket` escalates when the
checkout is not on the brief's branch. So set the worktree up first, without an agent, and only
then start the worker:

1. **Reuse first.** If `git worktree list --porcelain` shows a worktree on `refs/heads/<brief
   branch>`, use its path and skip to step 4. Not when that path is named in another open row:
   two items would then build in one worktree. That is `failed`, with `--kind escalation` "branch
   <brief branch> is already being built as <other item>".
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

`<agent>`, `<model>` and `<effort>` come from `stages.<stage>` (else `worker`, or `reviewer` for
review). `--executor session` is added to the prompt when that entry says `"executor": "session"`.

`worker-start` exits 0 only for `ready`. Any other result: retry once with `--retry-of <dispatch_id>`
and the same placement; a second failure → `failed`, queued. A rejected effort retries once with the
next lower listed level. A stage whose model cannot start at all (the agent is not installed, or
the launch refuses the model: no access, no credits) falls back to `worker` (review: `reviewer`)
once, and the queue gets one `--kind held` "<stage> for <item> ran on <fallback model>: <what the
launch said>"; when the fallback is the very setting that failed, it is the ordinary failure above.
A worker that starts and then sits on a usage-limit screen is the probe's `stuck: usage limit`. `--quiet-hours <window>` is `star.json`'s `quietHours` rendered as
`HH:MM-HH:MM@tz` (for example `22:00-07:00@Asia/Manila`); omit the flag when it is null. A window
is never judged by hand: `sh S/../ship-ticket/quiet-hours.sh "<window>"` prints `inside` or
`outside`;
anything but exit 0 with exactly `inside` or `outside` (exit 64 for a window it cannot read, a
missing script, no `python3`, an empty line) is treated as inside: hold what would go
out, notify only escalations, and queue `--kind held` "fix quietHours in star.json: <what the
script said>". A window that cannot be judged never lets something out.

**Reviewer prompt** (fill in `<…>`):

```
You are reviewing a draft pull request you did not write, as a second, independent reviewer.
Do not edit, commit, push or comment anywhere in the repo or on GitHub. Read only.
Brief (the approved contract): <brief path>
Notes for this project: <HOME_DIR>/memory/<project>.md
Previous round (rounds 2 and 3 only): <review path of round k-1> and its -fix.md beside it. Judge
each rejection on its merits; a prior rejection is evidence, not a verdict.
Run: git fetch <remote> <baseBranch> && git diff <remote>/<baseBranch>...HEAD
Review the whole diff against the brief: correctness, every acceptance criterion, scope (In/Out),
a regression test for every bug fix, security, data loss, error handling.
NOT-SAFE only for a defect that breaks behaviour, loses data, opens a security hole, misses an
acceptance criterion or leaves scope. Anything smaller goes under "Notes" and does not block.
Write the full review to <HOME_DIR>/reviews/<project>/<item>-r<k>.md. Its first line is the verdict
line below; then the numbered findings (severity, file:line, the failure scenario, the fix); then
Notes. That file is the only thing you write. <sha> is `git rev-parse HEAD`, the commit you reviewed.
Your worker_done body is exactly that one line:
VERDICT item=<item> round=<k> SAFE findings=<n> head=<sha>
or
VERDICT item=<item> round=<k> NOT-SAFE findings=<n> head=<sha>
```

The reviewer is `stages.review` from `star.json` (default: `codex` on GPT-6-Astra); without the
codex CLI it is `claude` on a model other than the builder's, and STAR says so.

## Brief worker mode: `draft-brief`

`/juel:star draft-brief <ref> --project <name> --item <name> --out <path> [--feedback]`
runs in the project's main checkout as an Orca worker. It never edits the repo; the brief at `--out`
is the only file it writes. It is unattended: nobody is at its terminal, so it never asks there.
Where a step below says ask, it sends `orca orchestration ask --question "<question>" --json` and
waits for the reply; a reply of "No answer … escalate this." ends the run with
`ESCALATION item=<name> phase=0 reason=unanswered-question needs=<the question>`.

1. Read `<HOME_DIR>/memory/<project>.md` (HOME_DIR is two levels
   above `--out`'s directory). Then, before step 2, when a file already exists at `--out`, read its
   `## Feedback` section: the user's dated answers to earlier runs of this stage. `--feedback` is
   a bare flag that says there is something new there; the text itself is never put in the prompt,
   where a quote or a line break could change it. An answer there settles the question it answers (which tracker holds the ref, what a
   term means): use it in the steps below and never ask or escalate the same thing again.
2. Resolve the project's work source: an explicit source in the ref → `.claude/workflow.local.json`
   / `.claude/workflow.json` `tracker` → a `## Work Source` block in CLAUDE.md or AGENTS.md → the
   legacy `## Linear Worktrees Config` block → the ref's shape when unambiguous (`#412` is GitHub; an
   existing path is a `file` item) → the single connected tracker. Still ambiguous →
   `ESCALATION item=<name> phase=0 reason=needs-human-input needs=which tracker holds <ref>`
   (`<name>` is `--item`, like every report line; the ref goes in `needs=`).
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
`feat`). When `--item` ends in a number the ref does not have (`SAVI-1162-2`: the same ref added
again after its first item was dropped or finished), the branch gets the same suffix
(`feat/savi-1162-add-auth-2`), so the new item never builds in the old item's worktree or on its
old PR.
6. Read enough of the code to propose an approach, then write the brief to `--out`. When a brief
   already exists at `--out`, read it first: revise it to answer every entry under
   its `## Feedback` section (the user's dated answers to earlier drafts, kept there by STAR), and
   keep the `## Feedback` and `## Decisions` sections as they are at the end of the new brief.

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
     notes: [<HOME_DIR>/memory/<project>.md]
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

   Acceptance criteria come from the item, or from a `## Feedback` entry in which the user states
   them. When neither has any, write the single line `- [ ] NEEDS CRITERIA` and never invent any.
7. Report, as the `worker_done` body: `BRIEF item=<name> path=<--out>`, then `NEEDS-CRITERIA` when
   that applies, then at most one `NOTE: <one line>`.

## Exact-head verification

`sh S/pr-verify.sh <pr url> --head <head from the ledger>` prints one line. How it judges: without
a review rule on the repo, an approval counts only when it was given on the current head commit;
with a rule, GitHub's own decision stands. Green means every check that reported is green and
GitHub's merge state is not blocked or behind, so a required check that has not started is
`PENDING`, not a pass. A repo with no reviewers at all never passes: someone has to approve.

| Verdict | Row in `verifying` | Row in `ready` |
|---|---|---|
| `PASS` | → `ready`; free the review slot; queue `--kind merge-pr`; notify. `PASS approval is on an earlier commit` is the same, with the queue title "merge PR #<n> — approved on an earlier commit, green, head <sha7>": the repo's rule is satisfied, but nobody approved the newest commits, and the person who merges should know | nothing |
| no line, or an exit that is not 0 | as `PENDING script gave no verdict` | nothing |
| `PENDING <what>` | `counters` has no `pending=1`: write it, put `retry=<now + 2 min>` in `verify`, and check again in a later tick. It has: → `escalated`, queue `--kind escalation` "<what> still pending" | nothing |
| `MOVED <head>` | `counters` has no `moved=1`: write it (its own budget, separate from `restarts` and from `pending=`, and never overwritten by them), row → `babysit-queued`. It has: → `escalated`, queue `--kind escalation` "head keeps moving" | the same, and close its `merge-pr` item |
| `MERGED <sha>` | as for `ready` (there is no `merge-pr` item to close yet) | close its `merge-pr` item, then `sh S/release-record.sh --home HOME_DIR --project <p> --item <i> --pr <url>`; row → `done`; print the record's path |
| `FAIL <what>` | → `escalated`; queue `--kind escalation` "<what>" | → `escalated`; close its `merge-pr` item; queue `--kind escalation` "<what>" |

Any verdict other than `PENDING` clears `pending=`; `PASS` clears `moved=` too. "Close its
`merge-pr` item" means `loops.sh close` on the open item of that kind for the row; none open (exit
4, or nothing to find) is fine. STAR never merges, and never marks a PR ready: babysit does that
once, and the merge is the user's.

## Drafts

STAR writes for the user only what shipping needs, and sends none of it by itself:

- A babysit worker that escalates `ambiguous-review` first writes
  `HOME_DIR/drafts/<date>-<project>-<item>-reply.md` (each ambiguous comment, then two or three
  candidate decisions) and adds `DRAFT <path>` to its report. STAR queues it as `--kind draft` with
  the escalation; the user's answer on the escalation is the decision the next babysit run applies.
- "Draft a status note": STAR writes `HOME_DIR/drafts/<date>-status.md` from the ledger and the
  queue (its own small files) and queues it as `--kind draft`. The user sends it.

## Memory notes

`memory/<project>.md` is read by every worker before it starts (the brief lists it). Workers add
to it only through a `NOTE:` line in their report, which STAR appends to it. The user edits or deletes notes freely. When a project file passes 80 lines,
queue `--kind held` "trim memory/<project>.md" instead of trimming it yourself.

## Pools and the memory check

Before every `worker-start`:

```sh
pg=$(vm_stat | sed -n 's/.*page size of \([0-9]*\) bytes.*/\1/p')
fr=$(vm_stat | sed -n 's/^Pages free: *\([0-9]*\)\./\1/p')
in=$(vm_stat | sed -n 's/^Pages inactive: *\([0-9]*\)\./\1/p')
echo $(( (fr + in) * pg / 1073741824 ))   # GB free + inactive
```

Under 3 GB free + inactive → start nothing this tick, write nothing but `hold=<n>` (one higher
each tick) in the `counters` of the row that was next in line, and try again at the next tick.
At `hold=3`, queue `--kind held` "memory below 3 GB: nothing can start" for that row and notify;
the queue keeps the one item until a start succeeds, which clears `hold=` and closes it. Heavy test and build gates inside workers take turns through
`juel:ship-ticket`'s `gate-lock.sh`, which uses one lock per user for the whole machine
(`/tmp/juel.gate.<uid>.lock`), so workers in different projects wait for each other too, and no
worker needs to be told where STAR's home is. `vm_stat` and `caffeinate` are macOS
tools; on Linux read the `available` column of `free -g` and skip `caffeinate`.

## Looking after the workers

STAR is the most capable session in the run and the only one that sees every item. A worker that
is unsure asks STAR; a worker that goes quiet hears from STAR. Workers are told both in their own
skills.

**STAR answers first.** A worker's question (`orca orchestration ask`) is STAR's to answer when
the answer is in the brief, its `## Decisions` or `## Feedback`, the memory notes or the ledger,
or when it is an engineering call inside the brief's Scope: which of two approaches, what to name
something, whether to retry, how to get past a tool that fails, what this project's convention
is. Answer in a few lines, say what to do next, and where it helps say what to read and what to
decide by: STAR still opens no code, review or log file itself.

A question is the user's, and goes to the queue, when it would change or stretch the Scope or an
acceptance criterion; needs a secret, an account or a paid service; is about anything that goes
out to other people (a reply, a status, marking ready); would delete or overwrite work; settles
product behaviour the brief leaves open; or when STAR is not confident. When in doubt whose it
is, it is the user's.

Every answer STAR gives is on record: append `- <date> STAR answered (<message id>): <question> → <answer>` to
the brief's `## Decisions` (later workers read it as binding, and the user can overrule it there
or in chat), and name it in the next status line.

**Checking in.** `worker-probe.sh` printing `quiet <minutes> <terminal>` means the worker runs but
its terminal has printed nothing for 15 minutes: it may have ended its turn without reporting, or
be waiting on a long command. Unless the row has an open `question` item (then it is waiting for
an answer, which is expected), send it one message and add one to `nudge=` in `counters`:

```sh
orca terminal send --terminal <terminal> --text "STAR checking in on <item>: say in one line where you are. Waiting on a background command: keep waiting. Blocked or unsure: ask me with orca orchestration ask. Finished: send your worker_done report now." --enter --json
```

The probe never says `quiet` while a question with numbered options is on the worker's screen
(that is `stuck: confirmation dialog`), because the check-in ends with Enter and Enter would
answer the prompt. Send a check-in only on a `quiet` result from this tick's probe, never from
memory of an earlier one.

At `nudge=3` with still no report, queue `--kind held` "<stage> worker for <item> has been quiet
through 3 check-ins: look at terminal <terminal>", notify, and send no more check-ins to it. The
worker is not stopped: it may be inside an hour-long gate. A blocking screen is a different thing
(`stuck:`): that worker is stopped and the row goes to the user, and STAR never answers a
worker's screen for it.

## Notifications and quiet hours

`star.json` keeps `"notified"`, the ids of the open queue items the user has been told about. At the
end of a tick outside quiet hours, when `loops.sh list` shows open items that are not in it: print
them, send one push notification naming them (Claude Code's `PushNotification` tool, loaded with
`ToolSearch` when deferred; printing is enough when it does not exist), and add their ids. Inside
quiet hours, and while the user is away, only `escalation` items are notified and added; every
other item stays out of the list, so it is notified at the first tick after the window however
many escalations went out in between, and a restart never loses a notification. Ids that are no
longer open are dropped from the list. A question's deadline is 30 minutes from when it was sent;
one that arrives inside quiet hours or while the user is away is answered "No answer" at once (the
Messages table).

Workers get the quiet window (`--quiet-hours`) and decide at each outward action: they keep
building, reviewing, fixing and pushing, while marking ready, replying to reviewers, re-requesting
review and status writes wait for the window to end or come back as `HELD` lines.

## Handoff

The handoff is how the user leaves and comes back without losing anything. `handoff.md` only lists:
the queue stays the one place to answer, so an answer can never exist in two files.

**Away** (`/juel:star away`, "I'm leaving", or a `control: away` inbox file). Away while already
away changes nothing: `handoff.sh start` keeps the file and its summaries and says so.

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
  marked ready and no human reviewer is pinged until the user is back. Such a row does not keep
  STAR active: when nothing else is running or waiting for a slot, STAR goes idle and the
  heartbeat wakes it. Babysit workers that were already running are left alone and keep their own
  quiet window.
- A worker's question is answered "No answer from the user: escalate this." at once.
- Only `escalation` items notify, as inside quiet hours.
- About every 4 hours (housekeeping's `handoff.sh due`), `handoff.sh summary` adds a dated summary
  to the top of `handoff.md`: items per state, PRs ready for the merge, what merged, what stopped,
  everything in `sent.log` since the last summary, free memory and running workers, and the full
  Needs-you list again. The heartbeat keeps this going while STAR is idle. It needs STAR's session
  to be open: with the session closed, workers continue but no summary is written.

**Back** (`/juel:star back`, "I'm back", or a `control: back` inbox file):

1. `sh S/handoff.sh --home HOME_DIR end` clears `away` and prints the latest summary. Print it, then
   the open queue (`loops.sh list`). When it prints `not away`, say so and print only the queue.
2. Send the notifications that were held, then run a tick, so the rows waiting in
   `babysit-queued` start babysitting now and not at the next heartbeat.
3. As the user answers, in the file or in chat, record each answer and act on it in the same turn.

## Recovery

- **Compaction:** the plugin's session hook tells the session that owns STAR for this project
  (the terminal named in `star.json`) that it is the coordinator and to run `/juel:star` if it is
  not in a tick. Other sessions in the same repository hear nothing. Nothing is needed from the
  user.
- **A closed session:** workers keep running and their reports wait in the Orca run. The user
  runs `/juel:star` in the project again, from any Orca terminal: the old terminal is no longer
  listed, so the new session takes over.
- **An Orca restart:** every worker is gone. The reconcile step restarts review, babysit and brief
  stages once and queues lost builds and fixes for the user.
- **A stop in the middle of a tick:** nothing is lost and nothing runs twice. A message not yet in
  `processed.log` is replayed into the same end state (the order of effects above); a row written
  before its `task-create` goes back to its waiting state; an inbox file read twice adds no row.

## Hard rules

- **Never merge a PR**, and never start a worker that would.
- Never read review, evidence, log or diff content into this session. One line per fact, from a
  script or a report.
- A brief is never built before the user approves it in the queue. Approval is never inferred.
- A `failed` or `escalated` row is never re-run without the user's answer, except the single
  automatic restart of a review, babysit or brief stage lost to a restart.
- Workers are started only through `orca orchestration worker-start`, and only by "Fill slots".
- One STAR per home, one worker per row, one row per worktree.
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
| Restarting a worker because a probe came back empty or `unknown` | Only `gone` means lost. `unknown` three ticks in a row goes to the user |
| Picking a row for a message by its `item=` name | By dispatch id; the name only confirms it |
| Writing a note or a count into `updated` | `updated` is a time. Counts go in `counters` |
| Working out the quiet window in your head | `quiet-hours.sh` says `inside` or `outside` |
| Working out the STAR folder's path yourself | `star-home.sh path` prints it; `init` creates it |

## Edge cases

| Situation | Handling |
|---|---|
| Refs given while STAR is stopped | The invoking session becomes the coordinator and ingests them |
| The same ref given twice | One row. The second time changes nothing |
| The user merges or closes a PR before STAR reached `ready` | The PR check before "Fill slots" sees it in every state that has a PR, stopped rows included: merged → release record and `done`; closed → `escalated` |
| The user says "drop" while the item's worker is running | The worker is stopped and released first, then the row → `dropped` |
| A second `/juel:star` in another terminal of the same project | It hands its refs to the running STAR and ends; it never becomes a second coordinator |
| `loops.sh` exits 3 (conflict markers in `open-loops.md`) | Stop writing the queue, tell the user to resolve the file, keep workers running |
| The project is not registered with Orca | `--kind held` "register this repo with Orca: orca repo add"; inbox files stay until it is |
| `codex` missing | The reviewer runs on claude with a different model; say so |
| A stage's model is refused at launch (no access, no credits) | The stage falls back to `worker` once and the queue says which model ran |
| `/juel:star` typed in a linked worktree or a subfolder | The same folder as the main checkout: one STAR per project |
| `/juel:star` typed outside a git repository | One line: STAR needs a project repository. Nothing is created |
| The STAR folder was deleted | That project's state is gone; the next `/juel:star` starts fresh. Stop STAR first: workers still running would report to nobody |
| Two projects each run a STAR | Each has its own queue and its own 3 + 3 slots; the gate lock and the memory check are shared by the machine |
