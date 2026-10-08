---
name: star
description: Use to run STAR, a local coordinator that ships a project's work items to merged-ready PRs on its own. Type "/juel:star <refs>" in the project - the session becomes the coordinator, or hands the refs to the one already running, and its state lives inside the project, git-ignored, under docs/superpowers/context/star - a queue with Answer slots, a ledger, briefs, release records and memory notes. A worker drafts a brief per item; before you go STAR walks you through every brief and every question it can foresee, then Orca workers build, a second model reviews the draft PR, fixes land, and the PR is babysat until it is approved, green and verified on its exact head. STAR moves the tracker status, files its own improvement issues, never reads big output, recovers by itself after compaction, and never merges. Triggers "start STAR", "add this to STAR", "what does STAR need from me", "/juel:star".
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
        why: workers open and babysit PRs; pr-verify.sh and release-record.sh read them; star-issue.sh files STAR's own improvement issues
        check: "gh auth status"
      - id: git
        hard: true
        why: star-home.sh finds the project's main checkout with it, and workers branch and push
        check: "command -v git"
      - id: python3
        hard: true
        why: star-home.sh, loops.sh, ledger.sh, messages.sh, stage-start.sh, star-issue.sh, worktree-clean.sh, pr-verify.sh, worker-probe.sh, release-record.sh, handoff.sh and the session hook run on it
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

## Goal

STAR exists to build and ship a project's work independently and autonomously, at the quality
bar of a second-model review, the regression gates and an exact-head check. It asks everything
it can foresee before the user goes ("Before you go"), then runs without them. When the rules
leave a choice, take the one that keeps work moving without the user: answer from the brief,
retry, recover by itself, file its own improvement issue. Stop for the user only for what a
person must do: approve a brief, supply a secret or an account, act at the screen, accept a
report, merge.

**Announce:** "Using juel:star." (in hand-over, `status` and `draft-brief` modes: say which mode.)

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v9 -->

**0. Harness check, before every other rule.** You are running in Codex when you have the `update_plan` tool and no `Skill` tool. Only then read `references/harness-codex.md`, resolved relative to this skill file's own location (`../../references/harness-codex.md`), and apply its construct map, corrected facts, dependency substitutions and degradation contract to every rule below and to every phase body in this skill. This single read is the one action permitted before rule 1's preflight, and only in that case. In every other case, Claude Code without the `TaskCreate` tool included, ignore that file entirely and continue to rule 1.

**1. Preflight, then task list, before anything else.** Before any other output and before any tool call, emit the Preflight block (below). If the preflight verdict is STOP, print the preflight block and **stop** — do not create tasks and do not begin work. Otherwise, before any other work, create one task per phase in this skill's `## Phases` list via `TaskCreate` — `subject` is the phase name, `activeForm` is its present-continuous form. This task list, rendered persistently by the harness, IS the checklist; nothing else satisfies this rule. This is not optional on re-invocation, on resume, or when the user says "just do it".
- **If `TaskCreate`/`TaskUpdate` are not in your tool list, or genuinely fail** — one attempted call returns an error; never assumed unavailable without checking the tool list — use `TodoWrite` when you have it (one todo per phase, the same names, updated at every transition), else an explicit numbered phase log, printed after every phase transition with the same one-line evidence rule 3 already requires. State the degradation once, in one line, before continuing. Never silently swap to prose without saying so.

**2. Phases run in order.** No skipping, reordering, or merging. A phase that does not apply is still announced, not dropped: mark its task `completed` via `TaskUpdate`, with the one-line evidence required by rule 3 stating the skip reason (e.g. "SKIPPED: <reason>") — the task list has no separate "skipped" status, so a skipped phase becomes `completed` too. Never begin phase N+1 before phase N's task is marked `completed`.

**3. Report after every phase.** Mark the phase's task `in_progress` via `TaskUpdate` when starting it, then `completed` via `TaskUpdate` when it finishes or is skipped — each transition accompanied by exactly one line of evidence (path written, command run, count found). Do not re-print the checklist as text; the task list is the persistent record and replaces that. Never claim progress in prose alone.

**4. `review-pr`'s agents run in PARALLEL and FOREGROUND; `code-simplifier` runs FOREGROUND; `codex exec` runs BACKGROUND, WATCHED, and WAITED-ON.** This overrides every other instruction in this file and in any skill invoked from it. Foreground/background is about whether the tool call blocks; watched is about whether output still streams somewhere the user can see it — these are different axes, and `codex exec` needs the second without the first. `review-pr`'s agents additionally need PARALLEL: dispatched together, not one at a time.
- `pr-review-toolkit:review-pr`'s agents MUST be dispatched in parallel: pass `all parallel`, or dispatch the agents together in ONE message. Its sequential default — one agent at a time — is the exact slowness this rule exists to prevent; requesting it, or omitting `all parallel`, is a violation.
- `pr-review-toolkit:review-pr` and `code-simplifier` are foreground-only. When your Agent tool has a `run_in_background` parameter, invoke both with `run_in_background: false` **explicitly** — the harness backgrounds subagents by default, so omitting the flag is a violation, not a neutral choice. Dispatching review-pr's agents in parallel does not relax this: each agent in that one message still carries its own explicit `run_in_background: false`. When your Agent tool has no such parameter, dispatch every one of them together in one message, wait for each one's completion, read each result in full, and check `ListAgents` before treating an idle agent as empty (rule 6); the phase never ends while one is still out. Never `&`. Never `run_in_background: true` for these two. Never "dispatch and continue".
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

`status`, `away`, `back`, `stop`, `draft-brief` and `post-report` are not a start: they skip this table (each
states its own needs below) and the task list, and announce their own mode. So does a
`/juel:star`, with or without refs, that finds STAR already running for this project in another
terminal: it hands over and ends. Finding that out takes steps 1 and 2 of "Coordinator, or
hand-over" below, so those two steps are the one exception to rule 1: they run before the
Preflight block, and they create nothing. Everything else is the start mode. `stop` typed in STAR's own
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

Claude Code's first-run trust dialogs are not a preflight item: `stage-start.sh` clears them in a
throwaway terminal before every Claude worker starts, and only when it cannot does the queue ask
the user to trust the path once (`hold trust <path>`).

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
| `/juel:star away` (or tell STAR "I'm leaving") | Walk through everything still open ("Before you go"), then write the handoff file and switch to away mode (below) |
| `/juel:star back` (or tell STAR "I'm back") | Print the latest summary and the queue; leave away mode |
| `/juel:star stop` | Finish the tick and stop. Running workers are left to finish; their reports wait in the Orca run |
| `/juel:star draft-brief <ref> --project <name> --out <path>` | Worker mode, below: a brief worker's command, never the user's |
| `/juel:star post-report <ref> --item <name> --report <path>` | Worker mode, below: a post worker's command, never the user's |

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

Everything after `/juel:star` is read as words. A first word of `status`, `away`, `back`, `stop`,
`draft-brief` or `post-report` is that command. When the whole text is `take over`, it is the user's "take
over" ("Start, resume, stop"): this session becomes the coordinator even though another terminal
is listed. Otherwise every word that is a work-item ref (`SPH-11`, `#412`) or a path to a spec
file is a ref: `SPH-11 and SPH-12`, `SPH-11, SPH-12` and `add SPH-11 SPH-12` are the same request.
Of the other words, filler (`and`, `add`, `please`) is dropped, and anything that says something
about the items ("the second one is urgent") goes into the inbox file's `note:` line.

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
repo: <project.repo from HOME_DIR/star.json>
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
(`run` in `star.json` is still null, which is true exactly once) STAR looks the repo path up in
`orca repo list --json` and adds the id to that block as `orcaRepo` (the Inbox step does the same
later when the repo was not registered yet), and adds the remote as `remote`: the only one
`git -C <project.repo> remote` prints, else `origin`. The work source and base branch are not
kept here: each item's brief carries them. Then it asks once, with
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
specs/<project>/<item>-review-r<k>.md   the reviewer's instructions (stage-start.sh writes them)
reports/<project>/<item>.md   a report item's report (deliverable: report)
issues.log              <iso>\t<fingerprint>\t<url>: every improvement issue STAR filed (star-issue.sh)
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
    "babysit": { "agent": "claude", "model": "opus",        "effort": "xhigh", "executor": "session" },
    "screen":  { "agent": "claude", "model": "opus",        "effort": "xhigh", "executor": "session" },
    "post":    { "agent": "claude", "model": "opus",        "effort": "xhigh" }
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
| brief, build, fix, screen, babysit, post | Opus 5.5, xhigh | the best agentic coding and plain coding available, and it acts on an Orca dispatch. Fable 5.1 scores higher on rule-following but, started as an Orca worker, it treated the dispatch as pasted text and did nothing until told to go ahead (tried 2026-10-07): do not put it on a worker stage without trying that again |
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
| a brief lists a "Before you go" question | `loops.sh add --kind prep --project <p> --item <i> --title "<the question>" --body "brief: <brief path>\nask: <n>\nkind: <kind>\nOptions: <options>; recommended: <default, or none>"` |
| a PR passed the exact-head check | `loops.sh add --kind merge-pr --project <p> --item <i> --title "merge PR #<n> — approved, green, head <sha7>" --body "<pr url>"` |
| a report item's report is written | `loops.sh add --kind accept-report --project <p> --item <i> --title "accept report for <i>" --body "<report path>\nOptions: accept / drop / or say what to redo"` |
| a worker escalated, or a row failed | `loops.sh add --kind escalation --project <p> --item <i> --title "<reason>" --body "<needs= text, or what failed>\nOptions: answer with your decision to run the stage again / drop"` |
| a worker asked something the brief does not answer | `loops.sh add --kind question --project <p> --item <i> --title "<the question, one line>" --body "msg: <id>\ndeadline: <iso>"` (the `msg: <id>` line is the Orca message id the reply needs after a restart; the deadline is the `deadline=` that `messages.sh` printed for the message: the time the message was sent plus 30 minutes, or plus the minutes the worker asked for with `deadline=<minutes>`, at most 240, so a replay writes the same item) |
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
drops the row. A `held` item is only a reminder; closing it never changes a row's state (two `done` answers set a
counter: a status the user moved by hand, and a kept worktree to try again).

### The ledger

`ledger.md` holds one row per item. It is written only through `ledger.sh`, which re-reads the
file under a lock for every command, cleans every value on the way in (`|` and line breaks
become `/ `, an empty value is `-`) and stamps `updated` itself. Every field is its own quoted
argument: never build a `set` line by splitting a string, which is how a value once became two
rows.

| Command | Does |
|---|---|
| `sh S/ledger.sh name <ref>` | the item name the ref gets, or `open <item>` when the ref already has an open row |
| `sh S/ledger.sh add <item> ref=<raw ref> project=<p>` | a new `inbox` row; exit 65 when the item, or an open row for the ref, already exists |
| `sh S/ledger.sh set <item> <col>=<value> … counters.<key>=<n>\|+1\|-` | changes only the named cells, in that order; `counters=keep:hold,last,start,screen,tracker` drops every other counter |
| `sh S/ledger.sh get <item> [<col>\|counters.<key>]` | one cell (`-` when absent), or the whole row as `col=value` lines |
| `sh S/ledger.sh list [--state <s>,…]`, `counts` | one row per line (item, state, stage, round, worktree, dispatch, pr, updated), or `<state> <n>` |

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
| `reask=1` | the open question's deadline was extended once (Housekeeping) | the question is answered or closed |
| `screen=<n>` | checks that wait for the user at the screen (a `SCREEN` line after `DONE`) | a `VERIFIED` report with `failing=0` |
| `last=<message id>` | not a count: the id of the last message applied to this row | never; the next message overwrites it |
| `tracker=<status>` | not a count: the last status STAR wrote to the work item, `!<status>` when that write failed | never; the next write overwrites it |
| `start=<n>`, `live=<n>` | written by `stage-start.sh`: the attempt number, and an attempt still being started | `live=` when that start ends; never `start=` |
| `kept=1` | the worktree of a finished row was kept (`worktree-clean.sh`): STAR does not try again by itself | its held item is answered `done` |

**An item has one name everywhere**, set once at ingest by `sh S/ledger.sh name <ref>` and used
for its row, its brief, review and gate paths, its worktree and every report line: a tracker ref
as written (`SAVI-1162`); a GitHub ref `#<n>` becomes `issue-<n>`; a spec path becomes the
kebab-case of its file name without the extension. A name is also a file name and a worktree
name, so it keeps only `A-Za-z0-9._-`: every other character becomes `-`, a leading `.` or `-` is
dropped, and it is cut at 60 characters. The raw reference stays in the `ref` column and is what
the brief worker fetches.

A ref that already has a row in that project which is not `done` or `dropped` is the same item: no new row
(`ledger.sh name` prints `open <item>`; a ref handed over twice, or an inbox file read twice after a
restart, changes nothing; say so in the status line). A name is used once per project, ever: a
different ref that maps to a taken name, and a ref whose earlier row is `done` or `dropped` and is
added again, get `-2`, `-3`. The new row then has its own brief, reviews and queue items, and an
answer can never land on the old row.

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
| `screen-queued` | — | SAFE review; some checks wait for the user at the screen; waiting for the user and a build slot |
| `screening` | build | a screen-check worker is running, with the user at the Mac |
| `babysit-queued` | — | waiting for a review slot to start babysitting (after SAFE, or again after the head moved) |
| `babysitting` | review | babysit worker running |
| `verifying` | review | `READY` received; exact-head check pending |
| `ready` | — | approved, green, verified; waiting for the user's merge |
| `reported` | — | report written (`deliverable: report`); waiting for the user's accept |
| `post-queued` | — | accepted; waiting for a build slot to post it |
| `posting` | build | a post worker is posting the report to the work item |
| `done` | — | merged; release record written |
| `escalated` | — | stopped on an escalation; in the queue |
| `failed` | — | a worker settled without its report or could not start; in the queue |
| `dropped` | — | the user dropped it |

Build pool (at most `maxParallel`): `fix-queued` rows first, then `screen-queued` rows (only
while the user is not away and it is not quiet hours), then `post-queued` rows (the same: posting
is outward), then `inbox` rows (briefs are short and unblock the user), then `queued` rows; within
each, the oldest `updated` first. While any `queued` row waits, rows in `briefing` hold at most
`maxParallel - 1` build slots, so an approved build never waits for every other brief to be
drafted. With `maxParallel` 1 there is nothing to reserve: the older of the waiting `inbox` and
`queued` rows goes first. Review pool (at most `maxInReview`): `babysit-queued` rows first, then
the oldest `pr-draft`. A row counts against a pool exactly while its state is one the table marks
`build` or `review`. During the intake ("Before you go") briefs may take every build slot: nothing
is building yet.

Each stage has a waiting state, used whenever a stage is to run (again): brief → `inbox`, build →
`queued`, review → `pr-draft`, fix → `fix-queued`, screen → `screen-queued`, babysit →
`babysit-queued`, post → `post-queued`. Nothing starts a worker except "Fill slots", so a
restarted stage waits for its pool like any other.

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
   `ok` or `quiet …` → keep it. `settled <state> [<reason>]` → its report is in the run's inbox; housekeeping's settlement rule
   catches it if it is not (a reviewer's review file and `agent_prompt_stalled` included). `gone` → Orca has no such worker (an Orca restart):
   a `briefing`, `reviewing`, `screening`, `posting` or `babysitting` row restarts once on its own (`restarts` column: set it to 1 and
   put the row in its stage's waiting state; `restarts` goes back to 0 whenever the row moves on to a new stage; babysit resumes with `--since <cursor>`), because
   those stages can pick up safely (a screen-check worker only runs checks, and a post worker first
   looks for the comment it may already have posted); a row whose `restarts` is already 1 → `failed`, queue
   `--kind escalation` "<stage> worker lost twice". For a lost `building` or `fixing` row,
   queue `--kind restart-or-drop` and set the row to `failed` (restarting a half-finished build
   blindly would build on a dirty worktree, and a dead row must not keep holding a build slot or
   keep STAR ticking all night). `stuck: <what>` → as in housekeeping. `unknown <why>` (which includes empty or unreadable Orca
   output) says nothing about the worker: keep the row and let housekeeping probe it again; it
   never justifies a restart. A `verifying` row has no worker: never restart it, and run the
   exact-head check for it only when its `verify` is `-` or its `retry=` time has passed (a resume
   inside the two-minute wait must not count as the second `PENDING`). A row in a worker stage with no task never started
   (STAR stopped between writing the row and `task-create`), and a row with a task but no
   dispatch never got its worker: put either back in its stage's waiting state, no restart
   counted, and leave its `counters` as they are. Its `live=` tells the next `stage-start.sh`
   that this is the same start, so it sends the same `--retry-request` ids and Orca hands back
   the task or dispatch it already made instead of a second one.
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
message. The intake ("Before you go") asks them between ticks while the user is there.

**Persist before acting.** Every ledger write goes through `ledger.sh`. `stage-start.sh` writes
the row before `task-create` (state, stage, round), the task id right after `task-create` and the
dispatch id right after `worker-start`.
Write the whole ledger right after each message's transition, then append the message to
`processed.log`, and only then acknowledge the delivery (step 3). A message already in
`processed.log` is skipped (its worker was released before that line was written). Every row write that a message causes also puts `last=<message id>`
in that row's `counters`, in the same write. A message whose id is already the row's `last=` is
already applied to it: do not match it against the table again, do not run the exact-head check
again and do not count anything; do only what comes after the row (`worker-release`,
`processed.log`, the ack). This is what makes a replay safe when STAR stopped between the row and `processed.log`.

**Match by dispatch, not by name.** A message belongs to the row whose `dispatch` cell equals the
message's dispatch id (the third field of its `msg` line from `messages.sh`); the `item=` in its first line must then be that row's
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
   `star.json`); a file for another repository is not ingested: leave the file where it is and
   queue `--kind held` "inbox file <name> is for <repo>: STAR here ships <project> only", once per
   file. No `project.orcaRepo` in `star.json` yet: look the repo path up in `orca repo list --json`.
   Found → write it to `star.json` as `project.orcaRepo`. Not found → `--kind held` "register this
   repo with Orca: orca repo add" and leave the file: the queue keeps one such item, however many
   ticks pass. Otherwise add one `inbox` row per ref with its item
   name (the naming rule above) and the raw reference in `ref`, skipping a ref that already has an
   open row, write the ledger, then delete the file.
2. **Answers.** `sh S/loops.sh answers` prints one line per answered item. Act, then
   `loops.sh close <id>` (exit 4 means it is already closed: carry on). A command word counts only when it is
   the whole answer: lower-case it, strip punctuation, and compare all of it with `approve`, `yes`,
   `ok`, `drop`, `drop it`, `drop it please`, `restart`, `send`, `done`, `accept` or `not merging`. So
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
   | `accept-report` | exactly `accept`, `yes` or `ok` (any case) | row → `post-queued` |
   | `accept-report` | drop | row → `dropped` |
   | `accept-report` | anything else | it is a decision: append it to the brief under `## Decisions` with the date; row → `queued`, so the build stage runs again with it |
   | `escalation` | drop | row → `dropped` |
   | `escalation` "<m> screen checks failed" | restart | row → `screen-queued`: the checks run again (the user changed something outside the code) |
   | `escalation` "<m> screen checks failed" | anything else but drop | append the answer and the pending-checks file's path to the brief's `## Decisions` with the date; row → `pr-draft`: a new review round reads the failed checks as missed acceptance criteria, and its NOT-SAFE sends them to a fix. `counters.screen=` stays, so the checks run again after the next SAFE review |
   | `escalation` | anything else | the answer is the decision. Brief stage: append it to the brief file under `## Feedback` (creating the file with only that section when the worker stopped before writing a brief), row → `inbox`; the brief stage then runs with `--feedback`. `reason=no-safe-verdict` (the PR's head has no SAFE review): row → `pr-draft` for a new review round of the current head. A row with no PR whose worker lacked `gh`: an answer that is a PR URL records it, row → `pr-draft`. Any other stage: append the answer to the brief under `## Decisions` with the date (workers read that section first and treat it as binding; where two decisions disagree the later one wins), then put the row in the waiting state of the stage in its `stage` column (babysit resumes with `--since <cursor>`). A fix stage goes back to `fix-queued` only while `git -C <worktree> rev-parse HEAD` is still the row's `head` (the commit the review was written for); when the worktree has moved on (the interrupted run committed, or the user did), row → `pr-draft` instead, so the new commits get a review of their own. `reason=stale-review` from a fix worker means the same: row → `pr-draft`. After "review still NOT SAFE": row → `fix-queued` for one more fix and review round |
   | `prep` | any | append `- <date> before you go #<n> (<kind>): <question> → <answer>` to the brief's `## Decisions` (`n` and `kind` from the item's body, the question from its title); `can't now` on a `screen` item is recorded the same way, so the worker knows that check will block. The row does not change |
   | `question` | any | `orca orchestration reply --id <the item's msg id> --body "<answer>" --json` |
   | every `escalation` and `restart-or-drop` answer that runs a stage again | also clears every counter except `hold=`, `last=`, `start=`, `screen=` and `tracker=` from the row (`sh S/ledger.sh set <item> counters=keep:hold,last,start,screen,tracker`), and `restarts` goes back to 0: the user's "try again" starts with fresh budgets, while the attempt number (so a new start never reuses an old request id), the checks still waiting at the screen and the last status written stay |
   | `restart-or-drop` | restart | `git -C <worktree> status --porcelain` must print nothing. Clean → the waiting state of its stage (`queued`; for a fix, `fix-queued` or `pr-draft` by the head rule in the `escalation` row). Not clean → change nothing and add the item again with the title "<stage> was interrupted: clean <worktree> first, then answer restart" |
   | `restart-or-drop` | drop | row → `dropped` |
   | `restart-or-drop` | anything else | add the item again with the title "<stage> was interrupted: answer restart or drop" |
   | `draft` | send | a draft whose first line is `to: pr <url>` is posted with `gh pr comment <url> --body-file <the rest>`; any other draft is the user's to send, say so. Before posting, append `<iso>\tSTAR\t<item>\tposted draft N-<id>` to `sent.log`; when that line is already there the draft was posted and only the close was lost: just close the item. Posting is an outward action: inside quiet hours or while the user is away, leave the item open (do not close it) and say "posts at the first tick outside the quiet window"; the Answers step sees it again every tick and posts it then |
   | `held` "could not move <item> to <status>…" | done | `counters.tracker=<status>` (the user moved it), then close it |
   | `held` "<item>'s worktree … was kept…" | done | clear `counters.kept=`, so the next tick runs `worktree-clean.sh` for it again, then close it |
   | `draft`, `held` | anything else | close it |
3. **Messages**, only while some row is in a worker stage or waiting for a slot:
   `sh S/messages.sh --wait --timeout-ms 540000`. It prints `delivery <id> <n>`, then each message
   as `msg <id> <type> <dispatch> <sent> [deadline=<iso>]` with at most 12 body lines indented by
   two spaces (`cut <n>` after them when the body was longer), or `none`. Heartbeats, "Rejected
   heartbeat" notices and messages already in `processed.log` never appear: the script drops them
   and acknowledges a batch that held nothing else, so an Orca nudge ("You have N orchestration
   messages") whose batch holds only heartbeats is a no-op. Orca replays a delivery until it is
   acknowledged, so once every message in it is in the ledger and in `processed.log`, the next wait
   is `sh S/messages.sh --ack <delivery> --wait --timeout-ms 540000` (or `sh S/messages.sh --ack
   <delivery>` alone when STAR is about to go idle). `none` is a tick; `unknown <why>` is a tick
   too, named in the status line. STAR reads only the report's lines (at most 12 lines): it
   never opens a review, evidence or log file, and never reads a worker's screen; the scripts do
   that and give one line back. A `cut` report: act on the first 12 lines and queue `--kind held`
   "<item>: report was cut at 12 lines".

   The first row that fits wins, top to bottom. A line that lacks a field its row names (`DONE`
   without `pr=`, `VERDICT` without `round=`) fits only the last row.

   | First line of the report | Action |
   |---|---|
   | `BRIEF item=… path=… [asks=<n>]` | row → `brief-ready`; queue `--kind approve-brief` (title "approve brief — add acceptance criteria first" when the report has a `NEEDS-CRITERIA` line), then one `--kind prep` per line of the brief's `## Before you go` section (`sed -n '/^## Before you go/,/^## /p' <brief>`, at most 20 lines, nothing else of the brief) |
   | `DONE item=… pr=<url>` | record the PR; row → `pr-draft`; free the build slot. A compare URL (no `/pull/`) → `escalated`, queue `--kind escalation` "no gh on this machine: open a draft PR from <url>, then answer with the PR's URL" (and skip the worker's own `HELD … open a draft PR` line) A `SCREEN path=<file> pending=<n>` line in the report → `counters.screen=<n>`. |
   | `VERDICT item=… round=<k> SAFE findings=<n> head=<sha>` | record head; row → `babysit-queued` (`screen-queued` while `counters` has `screen=`); free the review slot. `SAFE` wins whatever `findings=` says: they are notes. `head=` is its leading run of hex characters, at most 40 (a summary glued on after a literal `\n` does not spoil it). A run shorter than 7 is not a verdict babysit can use: treat the report as one with no `VERDICT` line (next row but two) |
   | `VERDICT … NOT-SAFE findings=<n>`, round 1 or 2 | row → `fix-queued`; free the review slot |
   | `VERDICT … NOT-SAFE`, round 3 or later | row → `escalated`; queue `--kind escalation` "review still NOT SAFE after <k> rounds" with the review's path |
   | a report from a reviewer (the row is `reviewing`) with no `VERDICT` line, including an empty one | `counters` has no `miss=1`: write it, row → `pr-draft`, and the same round runs once more. It has: → `escalated`, queue `--kind escalation` "reviewer gave no verdict twice" |
   | `FIXED item=… head=<sha>` | record head; row → `pr-draft`; free the build slot. The next review is `round + 1` (the first review is round 1; `round` is written when a review starts) |
   | `VERIFIED item=… passed=<n> failing=<m> head=<sha>` | record head; `failing=0` → clear `screen=`, row → `babysit-queued`; otherwise → `escalated`, queue `--kind escalation` "<m> screen checks failed" with the pending-checks file's path; free the build slot |
   | `READY item=… pr=… head=<sha> cursor=<cursor>` | record head and cursor; row → `verifying`; run the exact-head check now. The cursor is an opaque string from `pr-state.sh` (a time, then `#` and the ids already seen in that second): store it and pass it back as `--since` exactly as it came |
   | `ESCALATION item=… phase=… reason=… [cursor=<cursor>] needs=…` in a `worker_done` | record `cursor` when given; row → `escalated`; queue `--kind escalation` (and `--kind draft` with it when the report has a `DRAFT <path>` line); notify; free the slot |
   | `MERGED item=… pr=<url>` (a babysit worker saw the user merge early) | handle it as `pr-verify.sh` printing `MERGED`: release record, row → `done` |
   | `REPORTED item=… path=<path>` | row → `reported`; queue `--kind accept-report` with the path; free the build slot. STAR never opens the report |
   | `POSTED item=… url=<url>` | row → `done`; free the build slot (its `SENT` line goes to `sent.log` as for any report) |
   | an `escalation` message while the worker still runs | queue it and notify, but keep the row and its slot until its `worker_done` arrives |
   | a `question` message | **STAR answers first** ("Looking after the workers"): when the answer is STAR's to give → `reply` at once and record it; while the user is away or it is quiet hours, an in-scope product call is STAR's to give too. When it is the user's: a row that already has an open `question` item → close that item and `reply` to its `msg:` id "Superseded by your newer question." first. Then, inside quiet hours or while the user is away → reply "No answer from the user: escalate this." at once (nobody will read it in time); otherwise queue `--kind question` with the deadline `messages.sh` printed, notify, keep looping; the worker stays blocked and keeps its slot |
   | `CONFLICT:`, `AMBIGUOUS:`, `BRIEF-VIOLATION:` or `STOPPED:` (a `receive-review-and-execute` run that reported by itself) | as an `ESCALATION` whose reason is that word and whose `needs=` is the rest of the line |
   | anything else, or no report line | row → `failed`; queue `--kind escalation` quoting the first line; free the slot. Never re-run without the user's answer |

   `PHASE`, `PR`, `GATES` and `fixed=… rejected=…` lines need no action: the gate manifest is
   already at the brief's `star.gates` path, which the babysit stage is given.

   Also, for any report: each `HELD item=… action=…` line → `--kind held`; a `NOTE: <text>` line →
   append `- <date> <item>: <text>` to `HOME_DIR/memory/<project>.md`; a `SENT …` line → append
   `<iso>\t<project>\t<item>\t<the text after SENT>` to `HOME_DIR/sent.log`; a `STAR-ISSUE: <text>`
   line → "Improvement issues". STAR logs its own sends
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
   Then, for each free slot, the row next in line: `sh S/stage-start.sh <stage> <item>` (add
   `--round <k>` only to run review round k once more, the no-verdict rerun). Run it with the Bash
   tool's `run_in_background: true` and wait for its completion notification,
   like `gate-lock.sh` in a worker: creating a worktree with a setup hook, clearing the dialogs
   and starting the worker can take longer than the tool's 600 s foreground cap. It checks memory,
   sets up a build's worktree, clears Claude Code's first-run trust dialogs, writes the prompt and
   starts the worker, writing the row as it goes; a worktree named in another open row is refused
   (`failed in-use`). Its one line:

   | Line | Then |
   |---|---|
   | `started task=… dispatch=…` | nothing more. A ` fallback <model>: <why>` suffix → `--kind held` "<stage> for <item> ran on <model>: <why>" |
   | `hold memory <gb>` | start nothing else this tick; `counters.hold=+1` on that row; at `hold=3`, `--kind held` "memory below 3 GB: nothing can start" and notify. The next start that succeeds clears `hold=` and closes that item |
   | `hold trust <path>` | `--kind held` "trust <path> for Claude Code once: run `claude` there and accept, then answer done"; the row keeps waiting and the next tick tries again |
   | `failed <step>: <why>` | row → `failed`, `--kind escalation` "<stage> could not start: <step>: <why>" |
   | no line, or a non-zero exit | the script was cut off: put the row back in its stage's waiting state with its `counters` as they are (its `live=` makes the next start a replay of this one), and file an improvement issue ("Improvement issues") |

   A `screen-queued` row starts only while the user is not away and it is not quiet hours
   (`quiet-hours.sh`), with a push notification first: "<item> needs you at the screen for <n>
   checks: starting now". A `post-queued` row starts only while the user is not away and it is
   not quiet hours: posting is outward.
5. **Housekeeping.**
   - Questions past their deadline: when the user is not away, it is not quiet hours and the row
     has no `reask=`, remind once: a push notification "still waiting on you: <question>", the
     question first in the status line, the item added again with its `deadline:` moved on by its
     original length (then close the old item), and `counters.reask=1`. Otherwise reply "No answer
     from the user: escalate this.", close the item and clear `reask=`.
   - Each row in a worker stage that has not reported this tick: `sh S/worker-probe.sh <dispatch>`.
     `quiet <minutes> <terminal>` → check in on it ("Looking after the workers").
     `stuck: <what>` → `orca orchestration worker-stop`, then `worker-release`, row → `failed`, queue
     `--kind escalation` "<stage> worker stuck: <what>". `settled failed agent_prompt_stalled` (the worker never took its prompt) → `failed`, release,
     queue `--kind escalation` "<stage> worker never received its prompt: most likely Claude Code's
     trust dialog for <worktree>. Trust it once (run `claude` there and accept), then answer
     restart". Any other `settled …` with no processed report: a `reviewing` row first reads its
     review file's first line, `head -n 1 HOME_DIR/reviews/<project>/<item>-r<round>.md` and
     nothing more; a line that fits a `VERDICT` row of the Messages table is that dispatch's
     report, applied with `counters.last=file:<dispatch>`. Otherwise, and for every other stage:
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
   - The tracker status ("The tracker status").
   - Improvement issues met this tick ("Improvement issues").
   - Finished worktrees: each `done` or `dropped` row that still has a worktree and no `kept=` gets
     `sh S/worktree-clean.sh <item>`. It removes the worktree only when nothing in it would be lost
     (clean, and its work on the remote or merged), never with work in it that exists nowhere else.
     `removed <path>` → name it in the status line. `kept <path>: <why>` → `--kind held` "<item>'s
     worktree <path> was kept: <why>", and `counters.kept=1`. `none` → nothing. `failed` and
     `escalated` rows keep their worktrees until the user answers.
   - Away: `sh S/handoff.sh --home HOME_DIR due` printing `due` → `sh S/handoff.sh --home HOME_DIR summary`.
6. **Write.** `loops.sh resume …` with the current pools and the next step;
   `loops.sh waiting "<one line per PR in review, per blocked question>"`. Nothing is committed:
   the folder is plain files. Print one status line: counts per state, then every open queue item, `screen: <holder>`
   while `sh S/../ship-ticket/screen-lock.sh status` does not print `free`, and each issue filed
   this tick ("filed issue #19").

**Active or idle.** While any row is in `inbox`, `briefing`, `queued`, `building`, `pr-draft`,
`reviewing`, `fix-queued`, `fixing`, `screening`, `babysit-queued`, `babysitting`, `posting` or
`verifying`, or in `screen-queued` or `post-queued` while it may start, stay in the turn and tick
again (step 3's bounded wait is the clock). When every row is waiting on the user or finished, write
`state: idle` and STAR ends its turn. It is woken by a hand-over nudge, by the user, or by the
heartbeat, and each wake runs one tick.

## Stages

Every stage is its own Orca task and a fresh worker.

| Stage | Worktree | Agent | Prompt |
|---|---|---|---|
| brief | the project's main checkout (`path:<repo path>`), read-only | `stages.brief` | `/juel:star draft-brief <ref> --project <name> --item <name> --out HOME_DIR/briefs/<project>/<item>.md [--feedback]` (the row's raw `ref`, then its item name) |
| build | a new Orca worktree in that project, set up as below | `stages.build` | `/juel:ship-ticket --unattended --brief HOME_DIR/briefs/<project>/<item>.md [--executor session] [--quiet-hours <window>]` |
| review | the item's worktree | `stages.review` | the reviewer prompt below, written by `stage-start.sh` to `HOME_DIR/specs/<project>/<item>-review-r<k>.md`; the task spec is one line pointing at it |
| fix | the item's worktree | `stages.fix` | `/juel:ship-ticket --unattended --brief <brief> --fix-review HOME_DIR/reviews/<project>/<item>-r<k>.md [--executor session] [--quiet-hours <window>]` |
| screen | the item's worktree | `stages.screen` | `/juel:ship-ticket --unattended --brief <brief> --screen-checks HOME_DIR/gates/<project>/<item>-screen.md [--executor session] [--quiet-hours <window>]` |
| babysit | the item's worktree | `stages.babysit` | `/juel:babysit-pr <n> --unattended --mark-ready --reviewed HOME_DIR/reviews/<project>/<item>-r<k>.md --item <item> --brief <brief> --gates-file HOME_DIR/gates/<project>/<item>.json [--executor session] [--since <cursor>] [--quiet-hours <window>]` (`--reviewed` is the review file of the round that said SAFE: the worker's proof before it marks the PR ready) |
| post | the project's main checkout (`path:<repo path>`), read-only | `stages.post` | `/juel:star post-report <ref> --item <name> --report HOME_DIR/reports/<project>/<item>.md` |

**Build worktree.** `stage-start.sh build` sets it up before any agent starts, because Orca picks
the new worktree's branch name (`<user>/<name>` when the repo has a git username, else `<name>`)
and cannot be told otherwise, and `ship-ticket` escalates when the checkout is not on the brief's
branch:

1. **Reuse first:** a worktree that `git worktree list --porcelain` shows on the brief's branch,
   unless that path is named in another open row (two items would build in one worktree:
   `failed in-use`).
2. **Create:** `orca worktree create --repo "id:<REPO_ID>" --name "<item>" --base-branch
   "<remote>/<baseBranch>" --no-parent --setup run --json` (`<REPO_ID>` is `project.orcaRepo` and
   `<remote>` is `project.remote` in `star.json`; `<baseBranch>` is the brief's).
3. **The brief's branch:** switch to it when it exists (a branch left by an earlier attempt), then
   delete Orca's; otherwise rename Orca's branch to it. Git is authoritative; Orca's view of the
   branch can lag for a moment.
4. **Environment files** from the main checkout, only files git ignores (`git check-ignore`):
   `.env*`, `*.local`, `.envrc`, `.npmrc`, `.tool-versions` and ignored files under `.claude/`.
   Ignored files never show in `git status`, so `ship-ticket`'s clean-tree check still passes,
   and a worker's `git add -A` can never commit them; an untracked file that is not ignored is
   someone's work in progress and stays where it is. The worktree must then be clean.
5. **A worktree inside the repository** (`<repo>/.worktrees/…`) gets one line in
   `.git/info/exclude` for its top folder, so the main checkout's `git status` stays clean.

**Starting a stage** is `stage-start.sh` ("Fill slots"). Agent, model and effort come from
`stages.<stage>` (else `worker`, or `reviewer` for review); `--executor session` is added to the
prompt when that entry says `"executor": "session"`. A failed `worker-start` is retried once: with
`--retry-of` and the same placement, one effort level lower when the effort was refused, or, when
the launch refuses the model (the agent is not installed, no access, no credits), it falls back to
`worker` (review: `reviewer`) once and says so in a `fallback` suffix. `task-create` and
`worker-start` carry `--retry-request` ids, so a replay never makes a second task.
Every spec is one line: Orca echoes the spec inside its JSON, and a line break there once made the
output unreadable and left an orphan task. A worker that starts and then sits on a usage-limit
screen is the probe's `stuck: usage limit`.

`--quiet-hours <window>` is `star.json`'s `quietHours` rendered as `HH:MM-HH:MM@tz` (for example
`22:00-07:00@Asia/Manila`), omitted when it is null, and `always` while the user is away
(`stage-start.sh` reads `away` from `star.json`). A window is never judged by hand:
`sh S/../ship-ticket/quiet-hours.sh "<window>"` prints `inside` or `outside`;
anything but exit 0 with exactly `inside` or `outside` (exit 64 for a window it cannot read, a
missing script, no `python3`, an empty line) is treated as inside: hold what would go out, notify only escalations,
and queue `--kind held` "fix quietHours in star.json: <what the script said>". A window that
cannot be judged never lets something out.

**Reviewer prompt.** `S/template/reviewer-prompt.md`, filled in by `stage-start.sh review` with
the brief, the project's notes, the previous round's review and `-fix.md` (rounds 2 and up), the
remote and base branch, and the review file to write. The reviewer reads only, writes the full
review to `HOME_DIR/reviews/<project>/<item>-r<k>.md` (first line the verdict, then numbered
findings, then Notes), and its `worker_done` body starts with exactly one line:
`VERDICT item=<item> round=<k> SAFE findings=<n> head=<sha>` or
`VERDICT item=<item> round=<k> NOT-SAFE findings=<n> head=<sha>`.

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
   deliverable: pr          # or report: see step 6
   approved:               # stamped by STAR when the user approves
   star:
     home: <HOME_DIR>
     project: <project>
     notes: [<HOME_DIR>/memory/<project>.md]
     reviews: <HOME_DIR>/reviews/<project>
     gates: <HOME_DIR>/gates/<project>/<item>.json
     reports: <HOME_DIR>/reports/<project>
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
   ## Before you go
   1. [<kind>] <question> | options: <a> / <b> | default: <recommended option, or none>
   ```

   Acceptance criteria come from the item, or from a `## Feedback` entry in which the user states
   them. When neither has any, write the single line `- [ ] NEEDS CRITERIA` and never invent any.

   `## Before you go` lists everything a builder would predictably need from a person, so the
   user can answer it before leaving: one numbered line each, `<n>. [<kind>] <question> |
   options: <a> / <b> | default: <recommended option, or none>`. Kinds: `criteria` (missing or
   vague acceptance criteria), `decision` (a product call the item leaves open), `secret` (a key
   or an env var), `account` (a login or a paid service), `screen` (something a person must do
   at the Mac: sign in to an app, approve a keychain or Gatekeeper prompt). A `decision` always
   has a default; the other kinds never do. Nothing the brief, its `## Decisions` or the memory
   notes already answer goes here. Write `none` under the heading when there is nothing.

   `deliverable` is `report` when every acceptance criterion asks only for evidence, a
   disposition or a write-up (exercise flows and record what passed, map an impact, assess a PR,
   post a status) and nothing in the item asks for a change to code or docs in the repository;
   otherwise `pr`. A `## Feedback` entry that names one ("deliverable: pr") wins.
7. Report, as the `worker_done` body: `BRIEF item=<name> path=<--out> asks=<n>` (`<n>` is the
   number of lines under `## Before you go`, 0 for `none`), then `NEEDS-CRITERIA` when that
   applies, then at most one `NOTE: <one line>`, and at most one `STAR-ISSUE: <one line>` when STAR's
   own contract or tools got in the way (no project or ticket names).

## Post worker mode: `post-report`

`/juel:star post-report <ref> --item <name> --report <path>` runs in the project's main checkout
as an Orca worker, after the user accepted a report item's report. It never edits the repo and
never changes the work item's status (STAR does that). It is unattended, like `draft-brief`.
Resolve the work source exactly as `draft-brief` steps 2 and 3 do, then post the report file as
one comment on the work item. First look at the work item's latest comments: one that
already starts with the report's first line is this report, posted by an earlier post worker
that was lost; then report `POSTED` with its URL and post nothing.

| Provider | Post |
|---|---|
| `linear` | the Linear MCP's comment tool, `<LINEAR_PREFIX>create_comment(issueId: <id>, body: <the report file's text>)` |
| `github` | `gh issue comment <n> --body-file <path>` |
| `jira` | the connected Jira/Atlassian MCP's add-comment tool |
| `file` | nothing to post: add `report: <path>` to the spec file's frontmatter |

Report, as the `worker_done` body: `POSTED item=<name> url=<comment url, or the spec path>`, then
`SENT report posted to <ref>`. A post that fails: `ESCALATION item=<name> phase=0
reason=post-failed needs=<what the tracker said>`.

## Exact-head verification

`sh S/pr-verify.sh <pr url> --head <head from the ledger>` prints one line. How it judges: without
a review rule on the repo, an approval counts only when it was given on the current head commit;
with a rule, GitHub's own decision stands. Green means every check that reported is green and
GitHub's merge state is not blocked or behind, so a required check that has not started is
`PENDING`, not a pass. A repo with no reviewers at all never passes: someone has to approve.

| Verdict | Row in `verifying` | Row in `ready` |
|---|---|---|
| `PASS` | → `ready`; free the review slot; queue `--kind merge-pr`; notify. `PASS approval is on an earlier commit` is the same, with the queue title "merge PR #<n> — approved on an earlier commit, green, head <sha7>": the repo's rule is satisfied, but nobody approved the newest commits, and the person who merges should know When `grep -cE 'decided while you were away|default taken' <brief>` prints k > 0, the title ends "— k decisions made while you were away" and the body adds the brief's path, so the user sees them before merging. | nothing |
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

`stage-start.sh` checks memory before every start: free + inactive from `vm_stat` (on Linux the
`available` column of `free -g`) under 3 GB prints `hold memory <gb>` and starts nothing ("Fill
slots" says what follows: `hold=` counts the ticks, and at `hold=3` the queue gets one "memory
below 3 GB: nothing can start" item until a start succeeds).
Heavy test and build gates inside workers take turns through
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

**While the user is away**, or inside quiet hours, a product call inside the brief's Scope is
STAR's to make too: pick the option that best fits the brief's intent, reply, and record
`- <date> STAR decided while you were away (<message id>): <question> → <answer>` in the brief's
`## Decisions`. Out of scope, a secret, an account, a paid service, anything outward and deleting
work stay the user's, and are answered "No answer from the user: escalate this." at once.

**One open question per row.** A worker that asks again while its earlier question is still in
the queue has moved on: close the old item and reply to its message "Superseded by your newer
question." before queueing the new one, so the worker is never blocked on a stale ask. A worker
may end its question with `deadline=<minutes>` (at most 240); asks that need the user's hands at
the Mac use 60. At the deadline STAR reminds once (Housekeeping) before it gives up.

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
longer open are dropped from the list. A question's deadline is the one `messages.sh` printed (30 minutes from when it was sent unless
the worker asked for more), extended once by the Housekeeping reminder; one that arrives inside
quiet hours or while the user is away is decided by STAR or answered "No answer" at once (the
Messages table).

Workers get the quiet window (`--quiet-hours`) and decide at each outward action: they keep
building, reviewing, fixing and pushing, while marking ready, replying to reviewers, re-requesting
review and status writes wait for the window to end or come back as `HELD` lines.

## Report items

A brief with `deliverable: report` (a QA run, an impact map, a PR assessment, a status) ships a
report, not a PR. Its build stage is the same `ship-ticket` command: `ship-ticket` reads the
field, skips the code phases, runs every check, writes the report to
`HOME_DIR/reports/<project>/<item>.md` and reports `REPORTED item=… path=…`, with no commit, push
or PR. Then:

1. `REPORTED` → `reported`, and the queue asks "accept report for <item>" with the report's path.
   STAR never opens the report; the user reads it.
2. `accept` → `post-queued`. Posting is outward, so it waits for the first tick outside quiet
   hours and outside away. A post worker posts the report as one comment on the work item and
   reports `POSTED`; the row → `done`, and the tracker status moves to Done.
3. Anything else the user answers is a decision: it goes into the brief's `## Decisions`, and the
   build stage runs again.

No release record is written for a report item: the report and its `sent.log` line are the
record. The user can switch a brief to `deliverable: pr` in their feedback whenever they want the
run kept in the repository.

## The tracker status

STAR is the one writer of a work item's status; no worker under STAR writes it. The status
follows the row's state:

| Row state | Status |
|---|---|
| `queued` | Todo |
| `building`, `reported`, `post-queued`, `posting` | In Progress |
| `pr-draft`, `reviewing`, `fix-queued`, `fixing`, `screen-queued`, `screening`, `babysit-queued`, `babysitting`, `verifying`, `ready` | In Review |
| `done` | Done |
| `inbox`, `briefing`, `brief-ready`, `escalated`, `failed`, `dropped` | not written |

At the end of every tick outside quiet hours and outside away, compare each row's status with its
`counters.tracker=` and write only where they differ, through the source in the item's brief
(`item.source`, `item.ref`):

| Source | Write |
|---|---|
| `linear` | `<LINEAR_PREFIX>save_issue(id: <ref>, state: <the team's state of that name>)` (resolve `LINEAR_PREFIX` as in `draft-brief`) |
| `github` | `gh label create status:in-progress --force` and `gh label create status:in-review --force` once, then `gh issue edit <n>` adding the status's label and removing the other. Done: nothing for a merged PR (its `Closes` does it), `gh issue close <n>` for a report item |
| `jira` | the transition named by `config.tracker.statusMap`, through the connected Jira/Atlassian MCP |
| `file` | the spec file's status marker: `todo`, `in_progress`, `in_review`, `done` |

Each write sets `counters.tracker=<status>` and appends `<iso>\tSTAR\t<item>\tstatus <status>` to
`sent.log`; STAR reads only whether the call succeeded. A write that fails: `--kind held` "could
not move <item> to <status>: <reason>" and `counters.tracker=!<status>`. It is tried again only
when the row's status changes; `done` on that item means the user moved it by hand. A source with
no status field, or no connector in this session, is the same held item, once per status.

## Improvement issues

STAR files an issue against itself, in the plugin's own repository, whenever it meets one of
these:

- a STAR script fails outside its documented exits, or prints a line this skill has no rule for;
- Orca, `gh` or a worker behaves differently than this skill says;
- STAR had to improvise: no rule fits, two rules conflict, or it did by hand what a script should;
- a rule change would have saved time or a stop for the user;
- a worker reported `STAR-ISSUE: <one line>`.

1. `sh S/star-issue.sh find "<a few words>"` lists open issues that may be the same finding. When
   one is, `sh S/star-issue.sh comment <n> --fingerprint <fp> --body-file <f>` adds the new
   evidence; otherwise `sh S/star-issue.sh file --fingerprint <fp> --title "star: <what is
   wrong>" --label bug|enhancement --body-file <f>`. `<fp>` is a short kebab-case name for the
   finding; one STAR never posts the same fingerprint twice (`already <url>`).
2. The body, written to `HOME_DIR/drafts/<date>-issue-<fp>.md`: **What happened**, **Expected**,
   **Repro**, **Versions** (juel from the plugin's `plugin.json`, `orca --version`, the agent
   CLIs'), **Suggested fix**. The repository is public: describe STAR's behaviour only, with
   `<project>`, `ITEM-1`, `<repo>` and `<app>` in place of every name, and never ticket text,
   code, diffs, secrets or people's names. `star-issue.sh` refuses (exit 65) a title or body that
   still names the project, an item, a ref, the repository or a home path: rewrite it and run it
   again.
3. `failed <why>` (no `gh`, no access): queue the body as `--kind draft` "STAR issue: <title>".
4. Name each one in the status line ("filed issue #19").

Filing is not held by quiet hours or away: it goes to the plugin's own repository and pings nobody
else. It never delays a tick's real work: it runs in Housekeeping, after the slots are filled.

## Before you go

The goal needs every answer a person can give collected while the user is still there. The
intake runs in STAR's own session when it ingests new refs (a start with refs, refs said in chat,
or an inbox file that adds rows), and again on `away`.

1. Say "drafting <n> briefs; I'll walk you through each as it lands". While the intake runs, the
   Messages wait is `--timeout-ms 60000`, and briefs may take every build slot.
2. Between ticks, never inside one: ask every open item that blocks work (`approve-brief`,
   `prep`, `question`, `escalation`, `restart-or-drop`) with AskUserQuestion, up to 4 questions a
   call, the recommended option first. Record each answer with `loops.sh set-answer <id>
   "<answer>"` and run the Answers step for it at once, so STAR stays the only writer of briefs
   and rows.
3. `screen` items are things to do now: "sign in to <app> as <account>", "approve the keychain
   prompt once". Options: `done` / `can't now`.
4. When nothing is left to ask and no brief is still drafting: "All set: <n> approved, <m>
   decisions recorded. Leaving now?" Yes → Away (Handoff). No → STAR keeps ticking as usual.
5. "later" as any answer ends the walk-through at once and goes to Away with what is known.
   AskUserQuestion holds STAR's loop until it is answered; workers keep running in Orca and their
   reports wait there, so the cost is slots left unfilled while a question is on screen.

Refs handed over from another session: STAR's own session runs the walk-through, the handing
session says "answer STAR's intake in <terminal>", and STAR notifies when the first item is ready.

**What was not answered before the user left** is settled by Away (Handoff, step 1):

- a `decision` takes its recommended default: `loops.sh set-answer <id> "default taken: <default>
  (you left before answering)"`, applied like any answer;
- a `screen` item left open counts as `can't now`;
- a `criteria`, `secret` or `account` item has no safe default: it stays open, the item still
  builds until it needs the answer, then escalates (`needs-human-input`) as before.

**Screen checks after the user left.** A build worker that cannot do a check without a person
(the brief's Decisions say `can't now`, or its ask came back "No answer") records the check as
blocked, finishes everything else and opens the draft PR with those checks listed as pending; its
report adds `SCREEN path=<file> pending=<n>` after `DONE`. Review and fix run as usual, and after
a SAFE review the row goes to `screen-queued`. When the user is back and it is not quiet hours,
the `screen` stage runs only those checks with the user at the Mac; `VERIFIED … failing=0` sends
the row on to babysitting. Nothing is marked ready with a check unverified.

## Handoff

The handoff is how the user leaves and comes back without losing anything. `handoff.md` only lists:
the queue stays the one place to answer, so an answer can never exist in two files.

**Away** (`/juel:star away`, "I'm leaving", or a `control: away` inbox file). Away while already
away changes nothing: `handoff.sh start` keeps the file and its summaries and says so.

1. Finish the current tick, then run the walk-through ("Before you go"): wait for briefs still
   drafting and ask everything open. Then settle what is still unanswered: the default for each
   open `decision` item, `can't now` for each open `screen` item.
2. `sh S/handoff.sh --home HOME_DIR start` writes `handoff.md` and marks `away` in `star.json`. Its
   three parts come straight from the files: **A. Needs you now** (queue items that block work:
   briefs to approve, questions, escalations, restarts), **B. Waits for you** (merges, drafts, held
   actions), **C. What runs while you're away** (each open item and where it will stop).
3. Print part A: what is still open after the walk-through, and that those items stop where they
   need the answer. Answers that arrive later are handled like any other.

**While away:**

- Build, second-model review and fix stages keep running, started with `--quiet-hours always`, so
  their outward actions come back as `HELD`.
- No babysit stage is started: a row that reaches `babysit-queued` waits there, so no new PR is
  marked ready and no human reviewer is pinged until the user is back. Such a row does not keep
  STAR active: when nothing else is running or waiting for a slot, STAR goes idle and the
  heartbeat wakes it. Babysit workers that were already running are left alone and keep their own
  quiet window. No `screen` stage is started either: a row in `screen-queued` waits for the user.
- A worker's question that STAR cannot answer, and that is not an in-scope product call (STAR
  decides those, "Looking after the workers"), is answered "No answer from the user: escalate
  this." at once.
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
- **An Orca restart:** every worker is gone. The reconcile step restarts review, babysit, brief,
  screen and post stages once and queues lost builds and fixes for the user.
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
- The work item's status is written only by STAR, from the row's state ("The tracker status").
- Never put a project's details in an improvement issue: placeholders only, and `star-issue.sh`
  refuses the rest.
- AskUserQuestion only in the intake, between ticks.
- A worktree is removed only by `worktree-clean.sh`, and never with work in it that exists nowhere
  else.
- `open-loops.md` is written only through `loops.sh`, and `ledger.md` only through `ledger.sh`.

## Common mistakes

| Mistake | Fix |
|---|---|
| Opening a review file "to summarize it" | The queue item carries the path; the user reads it. STAR reads the verdict line |
| A worker moving the tracker status | Workers never write it; STAR follows the row's state |
| Pasting ticket text or a project name into an improvement issue | Placeholders only; `star-issue.sh` refuses project details |
| Opening a report "to check it" before asking for the accept | The queue item carries the path; the user reads it |
| Editing `open-loops.md` with Edit or sed | `loops.sh` only: it keeps what the user typed |
| Treating a `merge-pr` answer as a merge | Only `pr-verify.sh` printing `MERGED` moves the row |
| Starting a worker by hand | `stage-start.sh`: it sets up the branch, the env files and the trust dialogs before any agent starts |
| Ticking forever with nothing to do | When every row waits on the user or is finished, go idle and end the turn |
| Batching ledger writes to the end of a tick | Write after every message, before `processed.log` and the ack |
| Answering a worker's TUI prompt | `worker-probe.sh` says stuck → stop it, fail the row, queue it |
| Restarting a worker because a probe came back empty or `unknown` | Only `gone` means lost. `unknown` three ticks in a row goes to the user |
| Picking a row for a message by its `item=` name | By dispatch id; the name only confirms it |
| Writing a note or a count into `updated` | `updated` is a time. Counts go in `counters` |
| Working out the quiet window in your head | `quiet-hours.sh` says `inside` or `outside` |
| Working out the STAR folder's path yourself | `star-home.sh path` prints it; `init` creates it |
| Writing a ledger row by hand, or building a `set` line by splitting a string | `ledger.sh`, one quoted argument per field |
| Parsing `orca orchestration check` yourself | `messages.sh`: it drops heartbeats, replays and processed messages |
| Putting a line break in a task spec | `stage-start.sh` writes long prompts to a file and sends one line |
| Letting briefs take every build slot | While a `queued` row waits, briefs hold at most `maxParallel - 1` |

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
| A ticket that only asks for a QA run or a write-up | `deliverable: report`: a report the user accepts, posted by a post worker; no PR |
| The tracker cannot be reached from STAR's session | One held item per status move; the user answers done once they moved it |
| A finding that is already an open issue | `star-issue.sh comment` adds the new evidence to it |
| A finished item's worktree still holds uncommitted or unpushed work | It stays; the queue says why, and `done` there makes STAR try again |
| The STAR folder was deleted | That project's state is gone; the next `/juel:star` starts fresh. Stop STAR first: workers still running would report to nobody |
| Two projects each run a STAR | Each has its own queue and its own 3 + 3 slots; the gate lock and the memory check are shared by the machine |
| A worker asks again while its first question is still open | The old item is closed and its message answered "Superseded by your newer question." |
| The user leaves with "Before you go" items unanswered | Decisions take their defaults, screen items count as "can't now", the rest stop the item where it needs them |
| A check needs the user at the screen while they are away | The check is blocked, the PR opens with it pending, and the row waits in `screen-queued` after its SAFE review |
| An Orca nudge whose batch holds only heartbeats | `messages.sh` acknowledges it; nothing happens |
| A reviewer settles without a `worker_done` | Its review file's first line is the report |
| A worktree Orca created inside the repository | `.git/info/exclude` gets a line for its top folder |
| A new worktree Claude Code has never trusted | `stage-start.sh` clears the dialogs; only when it cannot does the queue ask |
| STAR stopped between `task-create` and recording the task | The next start replays the same request ids and gets the same task back |
