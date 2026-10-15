---
name: star
description: Use to run STAR, a local coordinator that ships a project's work to merged PRs on its own. Type "/juel:star <brief>" in the project, where the brief is free text, work-item refs, or both - the session becomes the coordinator, or hands the brief to the one running; its state lives in the project, git-ignored, under docs/superpowers/context/star (queue, ledger, briefs, grants, notes). Brief workers explore each item and STAR decides product calls from cited sources; the owner reads one batch summary, does the steps only a person can, and says go. One Orca worker per item plans, has codex run the plan on the newest luna, verifies, and loops its draft PR through a headless codex review gate until it passes; a babysit worker takes it through the hosted review or a person's approval; STAR merges under the owner's go when every gate holds on the exact head. STAR never reads big output and recovers by itself after compaction. Triggers "start STAR", "add this to STAR", "what does STAR need from me", "/juel:star".
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: brief workers fetch items from Linear when it is a project's work source
        check: none
        fallback: the project's other configured source is used; items can also be given as spec paths
      - id: mobbin
        hard: false
        why: brief workers look up how real apps solve a user-facing change before they decide it
        check: none
        fallback: a web search, named in the decision record's Source
      - id: context7
        hard: false
        why: brief workers check a library, framework, SDK, API or CLI at the project's version before they decide it
        check: none
        fallback: a web search, named in the decision record's Source
    cli:
      - id: orca
        hard: true
        why: every stage is an Orca orchestration task with a supervised worker
        check: "resolve_bin orca against PATH, then the app-bundle candidate"
      - id: gh
        hard: true
        why: workers open and babysit PRs; pr-verify.sh, done-check.sh and release-record.sh read them; merge.sh merges under the owner's go; star-issue.sh files STAR's own improvement issues
        check: "gh auth status"
      - id: git
        hard: true
        why: star-home.sh finds the project's main checkout with it, and workers branch and push
        check: "command -v git"
      - id: python3
        hard: true
        why: star-home.sh, loops.sh, ledger.sh, messages.sh, stage-start.sh, star-issue.sh, worktree-clean.sh, pr-verify.sh, worker-probe.sh, release-record.sh, handoff.sh, done-check.sh, merge.sh, codex-gate.sh, step-check.sh and the session hook run on it
        check: "command -v python3"
      - id: claude
        hard: true
        why: brief, build, babysit and post workers run the configured worker agent, claude by default
        check: "command -v claude"
      - id: claude-mods
        hard: false
        why: juel's mod draws STAR's band above the coordinator's prompt and refuses a direct merge and reading review, evidence or log files into the coordinator
        check: "claude --version is 2.1.287 or later"
        fallback: no band; the coordinator's rules hold as prose, from the SessionStart hook
      - id: codex
        hard: true
        why: the executor runs every plan on the newest luna, and codex-gate.sh reviews every draft PR with codex review
        check: "command -v codex"
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
        why: the first run asks for quiet hours, before any worker starts; every later question is asked in plain chat
    skills:
      - id: juel:ship-ticket
        hard: true
        why: the build stage runs it with --unattended --brief
      - id: juel:babysit-pr
        hard: true
        why: the babysit stage runs it with --unattended --mark-ready
      - id: juel:receive-review-and-execute
        hard: true
        why: babysit-pr remediates every review round through it with --unattended
---

# STAR

STAR is one long-running coordinator session for shipping one project's work. You start it by
typing `/juel:star` in the project with a brief: free text, work-item refs, or both. That session
plans, hands out work, checks results, keeps the queue and merges. It never writes code and never
reads big output. Real work goes to Orca workers: a fresh agent per stage, in the item's own
worktree, that reports in at most 12 lines and is released. Everything that matters lives in files
inside the project, in a git-ignored folder, never only in chat, so a compacted or restarted STAR
reads them and carries on. `skills/star/how-it-works.html` draws the flow (published at
https://claude.ai/artifact/V2Qx9Cm469k1vuJvcjS2fC). **STAR merges only through `merge.sh`, under the
owner's go, when every gate holds on the exact head.**

## Goal

STAR exists to build and ship a project's work independently and autonomously, at the quality
bar of a fresh Claude review, a second-model codex gate, the regression gates, the hosted review or
a person's approval, and an exact-head merge gate before its own merge. It asks only what a person
must supply, all at once, before the work starts (the batch summary), then runs without the owner.
Product calls are STAR's: decided from sourced options and logged as decision records the owner can
overrule. When the rules leave a choice, take the one that keeps work moving without the owner:
decide from sources, retry, recover by itself, re-scope, file its own improvement issue. Stop for
the owner only for what a person must do: say go, supply a secret or an account, act at the screen
before go, approve a risky call, approve a PR on a project with no hosted reviewer, or answer an
escalation.

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
| Mobbin MCP | mcp | SOFT | this session's tools (load them with `ToolSearch` when they are deferred): `available`; `needs-sign-in` when its only tools are `authenticate` and `complete_authentication`; else `absent`. Render that state, and write it to `star.json` as `mcps` | a web search, named in the decision record's Source |
| Context7 MCP | mcp | SOFT | this session's tools (load them with `ToolSearch` when they are deferred): `available`; `needs-sign-in` when its only tools are `authenticate` and `complete_authentication`; else `absent`. Render that state, and write it to `star.json` as `mcps` | a web search, named in the decision record's Source |
| orca | cli | HARD | `resolve_bin orca` against PATH, then the app-bundle candidate | STOP → https://www.onorca.dev |
| gh | cli | HARD | `gh auth status` | STOP → `gh auth login` |
| git | cli | HARD | `command -v git` | STOP |
| python3 | cli | HARD | `command -v python3` | STOP → install Python 3 |
| claude | cli | HARD | `command -v claude` (or the configured `worker.agent`) | STOP → install the worker agent CLI |
| Claude Code mods | cli | SOFT | `claude --version` is 2.1.287 or later | no band; the coordinator's rules hold as prose, from the SessionStart hook |
| codex | cli | HARD | `command -v codex` | STOP → install the Codex CLI (`npm i -g @openai/codex`): the executor and the gate need it |
| reachable Orca runtime | context | HARD | `orca status` reports `runtimeReachable: true` and `graphState: ready` | STOP → run `orca open`, then re-run |
| running in an Orca terminal | context | HARD | `[ -n "$ORCA_TERMINAL_HANDLE" ]` | STOP → start Claude Code from an Orca terminal and re-run there |
| inside a git repository | context | HARD | `git rev-parse --show-toplevel` | STOP → run `/juel:star` from inside the project's repository |
| AskUserQuestion | context | HARD | always available interactively | STOP → the first run asks one setup question, before any worker exists |
| juel:ship-ticket, juel:babysit-pr, juel:receive-review-and-execute | skill | HARD | ship with this plugin | STOP |

Claude Code's first-run trust dialogs are not a preflight item: `stage-start.sh` clears them in a
throwaway terminal before every Claude worker starts, and only when it cannot does the queue ask
the user to trust the path once (`hold trust <path>`).

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Preflight — binaries, the Orca runtime and terminal, the project's repository
2. Create the project's STAR folder with `star-home.sh init`, or load the existing one and bring it up to date with `star-home.sh migrate`
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
| `/juel:star add a CSV export to the reports page, and SPH-12` | Free text and refs together: the text becomes a spec item and the ref an item, in one batch. Starts STAR, or hands both to the one running, like the row above |
| `/juel:star` | Start STAR for this project, or resume it: the two are the same command |
| `/juel:star status` | Print the Needs-you block and counts per state. Read-only |
| `/juel:star away` (or tell STAR "I'm leaving") | Ask once more what the batch summary left open, then write the handoff file and switch to away mode (below). Away holds no work |
| `/juel:star back` (or tell STAR "I'm back") | Print the latest summary and the queue; leave away mode |
| `/juel:star stop` | Finish the tick and stop. Running workers are left to finish; their reports wait in the Orca run |
| `/juel:star draft-brief <ref> --project <name> --out <path> [--rescope <file>]` | Worker mode, below: a brief worker's command, never the user's |
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

Everything after `/juel:star` is read as words. A first word of `draft-brief` or `post-report` is
that command: they take arguments.
`status`, `away`, `back` and `stop` are commands only when they are the whole text, as `take over`
is, so `/juel:star stop the digest from sending twice` is a free-text brief, not a stop, and
`/juel:star status badge on the dashboard` prints no status. When the whole text is `take over`, it
is the user's "take over" ("Start, resume, stop"): this session becomes the coordinator even though
another terminal is listed. Otherwise every word that is a work-item ref (`SPH-11`, `#412`) or a path
to a spec file is a ref: `SPH-11 and SPH-12`, `SPH-11, SPH-12` and `add SPH-11 SPH-12` are the same
request. The rest of the words are the free-text brief, unless they are only filler
(`and`, `add`, `please`), which is dropped, or only say something about the refs
("the second one is urgent"), which goes into the inbox file's `note:` line. A free-text brief goes
into the inbox file's `text:` block, word for word; the Inbox step turns it into spec items.

### Coordinator, or hand-over

1. `HOME_DIR=$(sh S/star-home.sh path)`. Exit 1 (not inside a project's repository) → say so in one
   line and stop. `path` creates nothing.
2. When `HOME_DIR/star.json` exists, read its `terminal`. It names a terminal that is not this
   session's `$ORCA_TERMINAL_HANDLE` and that `orca terminal list --limit 500 --json` still lists
   (and the user did not say "take over") → **hand-over**: STAR is running there, and this session hands the refs to it.
   Write them, and any free text, as an inbox file (below), nudge it with
   `orca terminal send --terminal <handle> --text "inbox" --enter`, say
   "STAR for <project> runs in <handle>; I handed it <refs, or the text's first words>", and end.
   With no refs and no free text, say where it runs and print `status`. Hand-over needs no Orca terminal.
   The list cannot be read → write the inbox file, say that it could not be checked whether STAR is
   running, and end: never become a second coordinator on a guess.
3. Otherwise **this session becomes the coordinator**: run the Preflight table (a STOP there leaves
   the project untouched: nothing was created yet), then `sh S/star-home.sh init`, write any refs and
   free text as an inbox file (free text in its `text:` block), then the start sequence ("Start,
   resume, stop"). The first tick ingests them.

An inbox file is `HOME_DIR/inbox/<UTC YYYYMMDDTHHMMSSZ>-<4 random hex>.md` (never overwrite an existing inbox file;
pick another suffix):

```
repo: <project.repo from HOME_DIR/star.json>
refs:
- <ref or absolute spec path>
text: |
  <the free-text brief, word for word, every line indented two spaces; omit when there is none>
note: <anything the user said about the refs, one line; omit when nothing>
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
`git -C <project.repo> remote` prints, else `origin`.
It also looks for a hosted reviewer: when `greptile-apps[bot]` commented on one of the
repository's last 20 merged PRs, it sets `hostedReviewer` to
`{"login": "greptile-apps[bot]", "minScore": 4, "maxPasses": 2, "refreshOutsideCap": true}` and says so in one line; the owner
can change it. The lookup is `gh pr list --state merged --limit 20 --json number --jq '.[].number'`,
then for each `<n>`:
`gh api "repos/{owner}/{repo}/pulls/<n>/reviews" --jq '.[].user.login'` and
`gh api "repos/{owner}/{repo}/issues/<n>/comments" --jq '.[].user.login'`,
stopping at the first line that is exactly `greptile-apps[bot]` (REST logins carry the `[bot]`
suffix). The work source and base branch are not
kept here: each item's brief carries them. Then, before any worker starts, it asks once, with
AskUserQuestion, for a quiet window ("no reviewer pings, ready-marking or status changes while
you're away?"), writes it to `star.json`, and tells the user where the queue is:
`HOME_DIR/open-loops.md`.

These files are plain local files. They are not a repository of their own: nothing is committed
or pushed, and the standing instructions a session needs after a compaction come from the
plugin's session hook ("Recovery").

```
star.json               settings (below) plus "project", run id, STAR's terminal handle, caffeinate pid, heartbeat id, "notified", "away"
star.json.v1.bak        the copy star-home.sh migrate kept of a v1 star.json (ledger.md.v1.bak the same)
open-loops.md           Resume block, then Needs you, then Waiting on others   (written only through loops.sh)
open-loops-archive.md   closed items
open-loops.md.seq       the highest queue id ever used (so an id is never handed out twice)
handoff.md              the summaries written while the user is away (handoff.sh)
sent.log                <iso>\t<project>\t<item>\t<what was sent>: every message a worker or STAR posted
ledger.md               one row per item
processed.log           <message id> <dispatch> <iso time>
inbox/                  one file per hand-over; deleted once ingested
items/<project>/<name>.md            a spec item from a free-text brief, a split, or a re-scope's follow-up
briefs/<project>/<item>.md
grants/<UTC>-<4 hex>.md              the owner's go for a batch: their words, the time, the items
reviews/<project>/<item>-r<k>.md     the codex gate's review (first line the verdict), beside <item>-r<k>.raw.md and <item>-r<k>.log
reviews/<project>/<item>-r<k>-fix.md the disposition of each finding a round left unfixed, or that a re-scope moved or kept
reviews/<project>/<item>-r<k>-carried.md  the owner's decision to ship round k's head with its findings deferred (review-proof.sh carry writes it)
reviews/<project>/<item>-hosted-p<n>.md  a hosted reviewer's findings that sent an item to a re-scope
reviews/<project>/<item>-hosted.log      one line per hosted-reviewer request a babysit worker made: `<iso> pass <n> head=<sha>` or `<iso> refresh head=<sha>`; when it is missing, babysit rebuilds it from the PR's reviews and the reviewer's summary comments (`pr-state.sh --hosted-passes`) before it counts a pass
reviews/<project>/<item>-r<k>-error-<n>.log  the transcript of a gate attempt that ended in ERROR; the round keeps its number
reviews/<project>/<item>-r<k>.run   while a gate round runs: its pids, agent, model and start (codex-gate.sh writes it, step-check.sh reads it)
specs/<project>/<item>-gate-r<k>.md  the gate's prompt (codex-gate.sh writes it)
progress/<item>.log                  one line per milestone, appended by the item's workers
reports/<project>/<item>.md   a report item's report (deliverable: report)
issues.log              <iso>\t<fingerprint>\t<url>: every improvement issue STAR filed (star-issue.sh)
ids.json                ids reserved from sequences that branches share (ids.sh; workers write it, under a lock)
gates/<project>/<item>.json
releases/<YYYY-MM-DD>-<project>-<item>.md
evidence/<item>/                     the item's evidence folder, copied from its worktree before worktree-clean.sh removes it
drafts/<YYYY-MM-DD>-<project>-<item>-<kind>.md
memory/<project>.md
```

`<project>` is the name in `star.json`. A folder holds one project; the name stays in the paths,
the queue and the ledger so every file says what it belongs to.

Settings in `star.json`:

```jsonc
{
  "schema": 2,                                           // star-home.sh migrate brings a v1 folder here
  "maxParallel": 3,                                      // build pool
  "maxInReview": 3,                                      // babysit pool
  "maxBriefs": 4,                                        // brief pool
  "stages": {                                            // the best model for each stage's kind of work
    "brief":   { "agent": "claude", "model": "opus", "effort": "high" },
    "build":   { "agent": "claude", "model": "opus", "effort": "xhigh" },
    "babysit": { "agent": "claude", "model": "opus", "effort": "xhigh" },
    "post":    { "agent": "claude", "model": "opus", "effort": "xhigh" }
  },
  "worker":   { "agent": "claude", "model": "opus", "effort": "xhigh" },   // a stage with no entry, and the fallback
  "executor": { "model": "latest-luna", "effort": "xhigh", "fallback": "latest-sol" },   // runs every written plan
  "gate":     { "model": "latest-sol", "effort": "xhigh", "fallback": { "agent": "claude", "model": "opus", "effort": "xhigh" }, "maxRounds": 3 },   // the review gate: Sol, then Claude
  "hostedReviewer": null,                                // or { "login": "greptile-apps[bot]", "minScore": 4, "maxPasses": 2, "refreshOutsideCap": true }
  "hostGate": { "minFreeGB": 3, "maxAgents": 40, "maxSwapGB": 11, "minDiskGB": 25 },
  "progressDeadlineMin": 30,                             // no progress for this long: a check-in
  "mcps":     { "mobbin": "available", "context7": "needs-sign-in" },   // null in a new folder; every start writes it from the Preflight: available, needs-sign-in or absent
  "gateDown": null,                                      // while the review gate is down: { "since", "why", "checked" }
  "quietHours": { "tz": "Asia/Manila", "start": "22:00", "end": "07:00" },  // null = off
  "tokenCmd": null                                       // or a command that prints a GitHub token, such as a keychain lookup
}
```

Each stage runs on `stages.<stage>`; a stage with no entry there (or a home with no `stages`
block) runs on `worker`. The executor and the gate are not stages: every worker reads `executor`,
`gate`, `hostedReviewer` and `mcps` from this file through its brief's `star.home`. `latest-<family>` is the
newest model of that family `codex debug models` lists, resolved at each run by `juel:ship-ticket`'s
`executor-model.sh`. The defaults are the owner's choice for each kind of work:

| Role | Default | Why this one |
|---|---|---|
| STAR itself | Fable 5.1 (the model the STAR session is started on; not a setting here) | the strongest rule-following of the Claude models, with top-level reasoning |
| brief | Opus 5.5, high | a brief reads the item and enough code to propose an approach and take its product calls: `high` lands briefs sooner |
| build, babysit, post | Opus 5.5, xhigh | plans, verifies and answers reviewers, and acts on an Orca dispatch. Fable 5.1 scores higher on rule-following but, started as an Orca worker, it treated the dispatch as pasted text and did nothing until told to go ahead (tried 2026-10-07): do not put it on a worker stage without trying that again |
| executor | the newest luna (`gpt-6-luna` on 2026-10-09), xhigh | the owner's choice: a fast, affordable model types the plan Opus wrote. At capacity it falls back to the newest sol, then to the worker's own session |
| gate | the newest sol (`gpt-6.1-sol` on 2026-10-12), xhigh, through `codex review`; its fallback is Opus 5.5, xhigh, through `claude -p` | the owner's choice on 2026-10-12: only Sol reviews. Luna writes the code and Sol gates it, so the build's own fresh Claude review is the independent one. The fallback runs only when Sol is still at capacity after its retries, or the Codex account is out of usage: then the gate is a second Claude review, not a second model |
| hosted review | the project's own (Greptile), 4/5 or better | the owner's convention for a hosted reviewer's 0 to 5 confidence score |

`maxAgents` is 40, not the usual 20: this Mac ran 29 `claude` and `codex` processes on 2026-10-09.
These are the most capable models and they use more of the Claude and Codex usage limits than a
mid-tier setup; `max` effort costs about three times `xhigh` for a gain the benchmark cannot show
reliably, so it is not the default.

A model of `default` means: pass neither `--model` nor `--effort`. Model ids come from the CLIs,
never from memory.

`tokenCmd` (null when absent) is for a repository the default `gh` account cannot see (#91, #92).
Set it to a command that prints a token for it, such as `security find-generic-password -s <item> -w`:
the plugin's session hook then adds `export GH_TOKEN="$(<tokenCmd>)"` to every session that starts
in this project, STAR's and every worker's, so `gh`, and every script that runs it, has the token.
The hook writes the command, never the token, and leaves a session that already has `GH_TOKEN`
alone. The command must be quick and must not ask anything.

`hostedReviewer.refreshOutsideCap` (true when absent) says whether a status refresh after the
last pass stays outside `maxPasses`. A project whose own rule counts every run the hosted reviewer
starts sets it to false: babysit then never asks for a run past `maxPasses`, and a head that needs
one comes to the owner as `reason=hosted-cap` (#93). Babysit also merges the base in before it asks
for the last pass, so that pass reviews a current head.

### The queue: `open-loops.md`

STAR writes this file only through `loops.sh`, which re-reads it every time and never loses text the
user typed. The user answers on an item's `Answer:` line (continuing on the lines right under it),
or by telling STAR, who records it with `loops.sh set-answer <id> "<text>"` and then acts on it
in the same turn (the Answers step below, run at once for that item), so the worker that owns the
work gets the answer without waiting for the next tick.

| When | Command |
|---|---|
| a batch's briefs are drafted (no row of the batch is `inbox` or `briefing` any more) | `loops.sh add --kind go-batch --project <p> --item <batch> --title "go for batch <batch>: <n> items" --body "<item names, one per line>\nOptions: go / go except <items> / drop <item> / or say what to change"` |
| a brief lists a person-only step | `loops.sh add --kind person --project <p> --item <i> --title "<the step>" --body "brief: <brief path>\nstep: <n>\nkind: <secret, account, screen, confirm-id or risky>\nOptions: done / can't now"` (a `risky` step: `Options: approve / no`; a `(value)` step: the kind line `kind: <kind> (value)` and `Options: <the value> / can't now`) |
| a `verifying` row's brief has no grant (`grep -cE '^grant: [^ #]' <brief>` prints 0: a brief whose grant line was lost, since every go writes one) | `loops.sh add --kind go-merge --project <p> --item <i> --title "merge PR #<n> under a go?" --body "<pr url>\nOptions: go / not merging"` |
| a report item's report is written | `loops.sh add --kind accept-report --project <p> --item <i> --title "accept report for <i>" --body "<report path>\nOptions: accept / drop / or say what to redo"` |
| a worker escalated, or a row failed | `loops.sh add --kind escalation --project <p> --item <i> --title "<reason>" --body "<needs= text, or what failed>\nOptions: answer with your decision to run the stage again / drop"` |
| a worker asked something the brief does not answer | `loops.sh add --kind question --project <p> --item <i> --title "<the question, one line>" --body "msg: <id>\ndeadline: <iso>"` (the `msg: <id>` line is the Orca message id the reply needs after a restart; the deadline is the `deadline=` that `messages.sh` printed for the message: the time the message was sent plus 30 minutes, or plus the minutes the worker asked for with `deadline=<minutes>`, at most 240, so a replay writes the same item) |
| a build was lost to a restart | `loops.sh add --kind restart-or-drop --project <p> --item <i> --title "build was interrupted" --body "worktree: <path> (it must be clean before a restart: commit or discard what the interrupted run left)\nOptions: restart / drop"` |
| a draft is ready | `loops.sh add --kind draft --project <p> --item <i> --title "<what the draft is>" --body "<draft path>\nOptions: send / drop"` |
| a worker held an outward action, or a merge waits for something only a person gives | `loops.sh add --kind held --project <p> --item <i> --title "<action, or what the merge waits for>" --body "Options: done"` |

`<batch>` is `B-<the inbox file's name without .md>` for the items one inbox file brought in (the
name is unique), or `B-<UTC YYYYMMDDTHHMMSSZ>-<4 hex>` for a start or a migrate; every row of the
batch carries it as `counters.batch`.

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
| `sh S/ledger.sh set <item> <col>=<value> … counters.<key>=<n>\|+1\|-` | changes only the named cells, in that order; `counters=keep:hold,last,start,tracker,batch,rescoped,parent` drops every other counter |
| `sh S/ledger.sh get <item> [<col>\|counters.<key>]` | one cell (`-` when absent), or the whole row as `col=value` lines |
| `sh S/ledger.sh list [--state <s>,…]`, `counts` | one row per line (item, state, stage, round, worktree, dispatch, pr, updated), or `<state> <n>` |

`| item | ref | project | worktree | state | stage | round | task | dispatch | restarts | pr | head | cursor | verify | counters | updated |`

`updated` holds one UTC time, `YYYY-MM-DDTHH:MM:SSZ`, and nothing else (the handoff summary reads
it). `verify` holds `retry=<iso>` or `-`. Every count STAR needs across ticks lives in `counters`
as space-separated `key=n` pairs, `-` when there are none:

| Key | Counts | Cleared when |
|---|---|---|
| `silent=<n>` | probes in a row that said `settled` with no report processed | a report is processed |
| `unknown=<n>` | probes in a row that said `unknown` | any other probe result |
| `hold=<n>` | ticks in a row this row could not start because the host gate held it | it starts |
| `moved=<n>` | merge-gate checks that found the head moved | a merge-gate `PASS`, or the user answers its escalation |
| `pending=<n>` | merge-gate checks in a row that said `PENDING` | any other verdict |
| `nudge=<n>` | instructions and check-ins sent to this row's worker with no progress since ("Checking in") | a report from it is processed, `step-check.sh` prints `ok`, a restart, or a new worker starts |
| `asked=<iso>` | not a count: when STAR last sent this row's worker an instruction or a check-in | as `nudge=` |
| `step=<token>` | not a count: the step that instruction was about (a progress step token, such as `gate-r3`) | as `nudge=` |
| `busy=<n>` | check-ins Orca refused with `agent_prompt_blocked` in this row's current silent stretch | the probe prints anything but `quiet`, a report from it is processed, or a new worker starts |
| `shape=1` | a `worker_done` whose first line was none of its stage's report words (the Messages table) | a report from it is processed, or a new worker starts |
| `reask=1` | the open question's deadline was extended once (Housekeeping) | the question is answered or closed |
| `last=<message id>` | not a count: the id of the last message applied to this row | never; the next message overwrites it |
| `tracker=<status>` | not a count: the last status STAR wrote to the work item, `!<status>` when that write failed | never; the next write overwrites it |
| `synced=<sha7>` | not a count: the base head this row was last sent back to babysitting to sync with | never; the next sync overwrites it |
| `start=<n>`, `live=<n>` | written by `stage-start.sh`: the attempt number, and an attempt still being started | `live=` when that start ends; never `start=` |
| `kept=1` | the worktree of a finished row was kept (`worktree-clean.sh`): STAR does not try again by itself | its held item is answered `done` |
| `capacity=<n>` | retry nudges sent to a worker stalled on a model at capacity (`stalled:`) in one silent stretch | the probe prints anything else, a report from it is processed, or a new worker starts |
| `prompted=<n>` | Claude Code safety prompts STAR answered on this row's worker screen (`prompt bounded`, #114) | a new worker starts |
| `mismatch=<n>` | `DONE` reports `done-check.sh` could not check | the row reaches `babysit-queued` |
| `mergefail=<n>` | merge-gate `FAIL`s sent back to babysitting | the row is `done`, or the user answers its escalation |
| `rescoped=1` | the item was narrowed once by a re-scope | never: a second re-scope request escalates |
| `rescope=<file>` | not a count: the review file whose findings the next brief stage narrows the item by (`--rescope`) | the re-scoping `BRIEF` arrives |
| `batch=<id>` | not a count: the batch the item came in with | never |
| `parent=<item>` | not a count: on a follow-up item, the item it was split off from by a re-scope | never |

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
| `inbox` | — | ingested; waiting for a brief slot (with `rescope=`: waiting to be narrowed) |
| `briefing` | brief | a brief worker is reading the item and the code |
| `brief-ready` | — | brief drafted; waiting for its batch's go and its person-only steps |
| `queued` | — | go given; waiting for a build slot, the host gate, its blockers and its `notBefore` time |
| `building` | build | build worker running: plan, executor, checks, draft PR, the codex gate loop |
| `babysit-queued` | — | its `DONE` checked out, or the merge gate sent it back; waiting for a babysit slot |
| `babysitting` | babysit | babysit worker running: ready, the hosted review or an approval, gated fixes |
| `verifying` | — | `READY` received; STAR runs the merge gate each tick until it holds, then merges |
| `reported` | — | report written (`deliverable: report`); waiting for the user's accept |
| `post-queued` | — | accepted; waiting for a build slot to post it |
| `posting` | build | a post worker is posting the report to the work item |
| `done` | — | merged and its release record written, or its report posted |
| `escalated` | — | stopped on an escalation; in the queue |
| `failed` | — | a worker settled without its report or could not start; in the queue |
| `dropped` | — | the user dropped it, or it was split into new items |

Brief pool (at most `maxBriefs`; 4 when `star.json` has no such key): `inbox` rows, the oldest
`updated` first. Briefs never take a build slot: they only read, and run no gate. Build pool (at
most `maxParallel`): `post-queued` rows (only outside quiet hours: posting is outward), then
`queued` rows whose brief is stamped (`grep -cE '^approved: [0-9]' <brief>` prints 1) and whose
`blockedBy` items are all `done` or `dropped` (#37), and whose `notBefore` time, when the brief has one, has passed (#87); within each, the oldest `updated` first. A `queued` row still waiting on a blocker
is named in the status line: `<item> waiting on <items>`, and one waiting for its date: `<item> waits until <date>`. Babysit pool (at most `maxInReview`):
`babysit-queued` rows, the oldest first. A row counts against a pool exactly while its state is one
the table marks `brief`, `build` or `babysit`.

Each stage has a waiting state, used whenever a stage is to run (again): brief → `inbox`, build →
`queued`, babysit → `babysit-queued`, post → `post-queued`. Nothing starts a worker except "Fill
slots", so a restarted stage waits for its pool like any other.

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

1. Migrate: `sh S/star-home.sh migrate`. `current` → nothing. `migrated gate` (it comes first, before
   `current` or `migrated rows=<n>`) → say in one line "gate moved to Sol with a Claude fallback".
   `migrated rows=<n>` → say it in one line. For each `stop <dispatch>` line (a v1 review, fix or screen worker whose row moved on):
   append `<dispatch> stopped <iso>` to `processed.log`, then
   `orca orchestration worker-stop --dispatch <id> --json` and `worker-release`. All before the
   reconcile, so no v1 report lands on a row that moved. A non-zero exit stops the start: print
   its message, stop and release each `stop <dispatch>` line it printed as above,
   release the claim (`"terminal": null` in `star.json`), tell the owner the folder may be half moved
   and that running `/juel:star` again retries the migrate, and end here: no reconcile and no tick.
   Then give every open row (not `done` or `dropped`) with no `counters.batch` the batch
   `B-<this start's UTC time, YYYYMMDDTHHMMSSZ>-<4 hex>`. For that batch's `brief-ready` rows,
   queue each one's person-only steps (its brief's `## Person-only steps`, and for a row moved
   from a v1 screen state the checks its decision record names, as `screen` steps), and print the
   batch's summary and queue its `go-batch` item once no row of the batch is `inbox` or `briefing`
   ("The batch summary and go"). When it printed `migrated rows=<n>`
   and `star.json`'s `hostedReviewer` is null, run the hosted-reviewer lookup of "STAR's home" once.
2. `orca orchestration run-use --id <run from star.json> --json`; when that run no longer exists,
   `orca orchestration run-create --objective "STAR" --json`. Record the run id and
   `$ORCA_TERMINAL_HANDLE` in `star.json`, and the Preflight's Mobbin and context7 states as
   `"mcps": {"mobbin": "<state>", "context7": "<state>"}`. Every start writes it again, so a sign-in
   made between runs shows at the next start. Workers read it: it tells them which research MCPs
   STAR's session found.
3. `caffeinate`: when `star.json` has a pid and `ps -p <pid> -o comm=` prints `caffeinate`, kill it.
   Start a new one (`caffeinate -dimsu >/dev/null 2>&1 &`) and record its pid. It deliberately
   outlives a closed session, so the workers' Mac stays awake.
4. Heartbeat: load the scheduler (`ToolSearch("select:CronCreate,CronDelete")`), delete the job id in
   `star.json` if any, and create a recurring job `7,37 * * * *` with the prompt
   `STAR heartbeat: if you are not already in a tick, run one.` Record its id and, as `heartbeatAt`,
   the time. Jobs fire only while the session is idle and die with the session, which is why every
   start registers a fresh one. A recurring job also expires by itself after 7 days: any tick that
   finds `heartbeatAt` 6 or more days old deletes the job and registers a new one, the same way.
   No scheduler tool → skip it and say so: an idle STAR then wakes only on a hand-over nudge or the user, so
   away summaries and answers typed into the queue file wait for one of those.
5. **Reconcile** every row in a worker stage, except a `building` row whose `verify` holds `retry=` (below), with `sh S/worker-probe.sh <dispatch> --item <item> --home HOME_DIR --worktree <worktree> --deadline <progressDeadlineMin>` (no `--worktree` for a `briefing` or `posting` row):
   `ok`, `quiet …` or `stale …` (with or without ` holds-screen <m>`) → keep it. `stalled: …` → housekeeping's capacity rule. `settled <state> [<reason>]` → its report is in the run's inbox; housekeeping's settlement rule
   catches it if it is not (`agent_prompt_stalled` included). `gone` → Orca has no such worker (an Orca restart):
   a `briefing`, `posting` or `babysitting` row restarts once on its own (`restarts` column: set it to 1 and
   put the row in its stage's waiting state; `restarts` goes back to 0 whenever the row moves on to a new stage; babysit resumes with `--since <cursor>`), because
   those stages can pick up safely (a post worker first looks for the comment it may already have
   posted); a row whose `restarts` is already 1 → `failed`, queue
   `--kind escalation` "<stage> worker lost twice". For a lost `building` row,
   queue `--kind restart-or-drop` and set the row to `failed` (restarting a half-finished build
   blindly would build on a dirty worktree, and a dead row must not keep holding a build slot or
   keep STAR ticking all night). `stuck: <what>` → as in housekeeping. `unknown <why>` (which includes empty or unreadable Orca
   output) says nothing about the worker: keep the row and let housekeeping probe it again; it
   never justifies a restart. A `verifying` row has no worker: never restart it, and run the
   merge gate for it only when its `verify` is `-` or its `retry=` time has passed (a resume
   inside the two-minute wait must not count as the second `PENDING`). A `building` row
   whose `verify` holds `retry=` has already reported and its worker is released (its `DONE` waits
   for `done-check.sh`): skip the probe for it, which would read as a lost worker, and once its
   `retry=` time has passed run `done-check.sh` for it with its PR and head, as Housekeeping does,
   and act on its line as the `DONE` row of the Messages table says. A row in a worker stage with no task never started
   (STAR stopped between writing the row and `task-create`), and a row with a task but no
   dispatch never got its worker: put either back in its stage's waiting state, no restart
   counted, and leave its `counters` as they are. Its `live=` tells the next `stage-start.sh`
   that this is the same start, so it sends the same `--retry-request` ids and Orca hands back
   the task or dispatch it already made instead of a second one.
6. `loops.sh resume --state running --run <id> --pools "brief <n>/<max> · build <n>/<max> · babysit <n>/<max>" --next "<one line>"`, then tick.

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

Never call AskUserQuestion inside a tick, or anywhere once a worker exists: Orca types its nudge
into this terminal, and a nudge that lands on an open picker answers it with the first option
(#29). Questions for the user go into the queue and are notified; the answer arrives in the file
or as an ordinary message. The batch summary ("The batch summary and go") asks them in plain chat while the user
is there.

**Persist before acting.** Every ledger write goes through `ledger.sh`. `stage-start.sh` writes
the row before `task-create` (state, stage, round), the task id right after `task-create` and the
dispatch id right after `worker-start`.
Write the whole ledger right after each message's transition, then append the message to
`processed.log`, and only then acknowledge the delivery (step 3). A message already in
`processed.log` is skipped (its worker was released before that line was written). Every row write that a message causes also puts `last=<message id>`
in that row's `counters`, in the same write. A message whose id is already the row's `last=` is
already applied to it: do not match it against the table again, do not run the merge gate
again and do not count anything; do only what comes after the row (`worker-release`,
`processed.log`, the ack). This is what makes a replay safe when STAR stopped between the row and `processed.log`.

**Match by dispatch, not by name.** A message belongs to the row whose `dispatch` cell equals the
message's dispatch id (the third field of its `msg` line from `messages.sh`); the `item=` in its first line must then be that row's
item. Item names can repeat, so a name alone never selects a row. A message changes no
row, and is queued as `--kind held` with its first line, when its dispatch is in no row (or it
carries no dispatch id: `--project - --item <the dispatch id, or unmatched>`), when its
row is `done` or `dropped`, or when the row has moved on to a newer dispatch (a superseded attempt:
a report from a worker that a restart replaced). Two exceptions change nothing and queue
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

**A stopped worker is gone** (#76). `worker-stop` fences the dispatch, but Orca can keep its
terminal open, and the agent in it with it. After every `worker-stop` and `worker-release` STAR
makes (a drop, an early merge, a closed PR, a restart, the capacity rule, a stuck worker, a merge
the owner orders), check the dispatch's terminal:

```sh
orca orchestration worker-list --json | python3 -c 'import json, sys
try:
    ws = [w for w in json.load(sys.stdin)["result"]["workers"] if w.get("dispatchId") == sys.argv[1]]
except (ValueError, KeyError, TypeError):
    print("- unknown -"); sys.exit()
w = ws[0] if ws else {}; print(" ".join([w.get("agentTerminalHandle") or "-", w.get("terminalState") or "none", (w.get("resource") or {}).get("retainedReason") or "-"]))' <dispatch>
```

It prints `<terminal> <state> <reason>`. A state of `released` or `none` is gone: nothing more.
A state of `unknown` (the line `- unknown -`) means Orca did not answer: check again on the next tick,
and close nothing now. A reason of `user_takeover` or `identity_unproven` means a person may be at
that terminal, or Orca cannot tell whose it is: never close it; queue `--kind held` "<item>: terminal
<terminal> (<reason>) outlived its stopped worker; close it or finish there, then answer done". Any
other state: `orca terminal close --terminal <terminal> --json`, and say `closed <terminal> for <item>`
in the status line. `stage-start.sh` checks the row's previous dispatch again before its stage
starts ("Fill slots"), so two sessions never work in one worktree.

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
   ticks pass. Otherwise add one `inbox` row per ref with its item name (the naming rule above) and the raw
   reference in `ref`, skipping a ref that already has an open row. A `text:` block is a
   free-text brief: write each distinct piece of work it names as a spec item,
   `HOME_DIR/items/<project>/<kebab name>.md` (frontmatter `status: todo` and `title: <a short
   title>`, then the words that describe that piece, verbatim), and add it as an `inbox` row whose
   `ref` is that path. Split only where the text plainly lists separate pieces of work (a list, "and
   also"); when in doubt, it is one item, and its brief worker can report `SPLIT`. Every row from one
   file gets `counters.batch=B-<the file's name without .md>`. Write the ledger, then delete the
   file.
2. **Answers.** `sh S/loops.sh answers` prints one line per answered item. Act, then
   `loops.sh close <id>` (exit 4 means it is already closed: carry on). A command word counts only when it is
   the whole answer: lower-case it, strip punctuation at its two ends only (an apostrophe or a
   hyphen inside it stays: `can't now`, `ITEM-2`), and compare all of it with `go`, `yes`, `ok`,
   `approve`, `no`, `drop`, `drop it`, `drop it please`, `restart`, `send`, `done`, `can't now`,
   `accept`, `retry` or `not merging`. For a `go-batch` item, `go except <items>` and `drop <item>` match
   as prefixes, and the names after them compare case-insensitively with the batch's ledger names.
   So `Drop.` and `restart!` count, while `go, but rename the flag` and `Drop the retry wrapper
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
   and `sh S/worker-probe.sh <dispatch>` says `ok`, `quiet …`, `stale …` or `stalled: …`: a worker in any of those is still running) is handled first: `drop` stops the worker before
   the row changes (`orca orchestration worker-stop --dispatch <id> --json`, then `worker-release` and the gone check);
   any other answer is appended to the brief's `## Decisions` and sent to that worker with
   `orca orchestration send --to dispatch:<id> --subject "decision" --body "<answer>" --json`, and
   the row stays as it is. A `briefing` row's answer goes to the brief's feedback side file
   instead, and is not sent ("Feedback while a brief drafts", in "The batch summary and go", #112).
   An answer never starts a second worker for a row that has one.
   A `question` is always answered with `reply` (its worker is blocked waiting for exactly that),
   and `held` and `draft` answers never reach a worker.

   | Kind | Answer | Action |
   |---|---|---|
   | `go-batch` | exactly `go`, `yes` or `ok` (any case) | the go is for every row of the batch that is `brief-ready`, except a row whose brief still says `NEEDS CRITERIA` (`grep -c 'NEEDS CRITERIA' <brief>` prints 1 or more) or that has an open `person` item: those stay. Write the grant once, for the rows that start: `HOME_DIR/grants/<UTC YYYYMMDDTHHMMSSZ>-<4 hex>.md`, a frontmatter block with `date: <iso>` and `items: [<names>]`, then the user's answer exactly as typed. In each started row's brief, in one write: stamp `approved: <iso>` and `grant: <grant path>`, and remove each ` (proposed)` suffix, so builders and the gate read plain criteria. Those rows → `queued`. When rows stayed, add the `go-batch` item again for them, titled "go for <items> once <what each waits for>". A brief with `NEEDS CRITERIA` asks for criteria in that title: an answer in words is feedback (criteria stated in the user's own words STAR writes itself, as below; otherwise the brief worker writes them from it). A go is only ever this explicit answer from the user, never a default, a timeout or a blanket answer |
   | `go-batch` | `go except <items>` | the same, for every row of the batch but the named ones; those stay `brief-ready` with a `go-batch` item of their own |
   | `go-batch` | `drop <item>` | that row → `dropped`; add the `go-batch` item again for the rest |
   | `go-batch` | anything else, including "go, but …" | it is feedback for the item it names (it names none and the batch has more than one item: ask which, one question), never a conditional go: append it to that brief under `## Feedback` with the date (so it survives a restart of STAR), except a `branch` or `baseBranch` change on a brief with `existingPr` (below). When it only edits the brief's own text (add, remove or reword an acceptance criterion it states in its own words; change `deliverable`, `branch` or `baseBranch`; add or remove a Scope `In:` or `Out:` line), STAR makes the edit itself, ends that Feedback entry with "(applied by STAR)", keeps the row `brief-ready` and adds the `go-batch` item again, showing the changed lines marked `(changed)`. That mark is only in the question STAR asks in chat, never in the brief file; a changed `branch` or `baseBranch` gets its own line there, since the summary does not otherwise show them. On a brief with `existingPr`, `branch` and `baseBranch` are not small edits: they must equal the PR's `headRefName` and `baseRefName`, so a change to either is answered in chat: the branches come from the PR, so the user changes the base on GitHub, and a different head branch needs a different PR. Nothing is recorded (no `## Feedback` entry), and STAR adds the `go-batch` item again, with that explanation in its title. A later reply saying the PR was changed is feedback, and the brief worker re-reads the PR (row → `inbox`, as below). A criterion STAR writes from the user's words (added, or reworded) carries no ` (proposed)` suffix, and STAR removes the `- [ ] NEEDS CRITERIA` line in the same write when the brief has one; every other proposed criterion keeps its suffix until the go. When STAR's edit leaves the brief with no acceptance criterion, it makes sure the brief has `- [ ] NEEDS CRITERIA` in the same write. Anything that needs the code or the work item read again (another approach, "also handle X", a question about the code, a criterion described rather than stated): row → `inbox`; the brief stage then runs with `--feedback` |
   | `person`, a `(value)` step (the kind line of its body ends in `(value)`) | exactly `done` | no value came with it: close the answered item and add it again with the title "<the step> (answer with the value)" and the same body. The step stays open, so the row stays out of the go |
   | `person`, a `(value)` step | anything but `done`, `can't now` or `no` | the answer is the value (#86): append `- <date> person-only step #<n> (<kind>, value): <step> → value: <answer>` to the brief's `## Decisions` (the step is the title without a trailing " (answer with the value)", and the answer exactly as `loops.sh answers` printed it). The step is done. The row does not change, except a `brief-ready` row whose brief has a grant line (`grep -cE '^grant: [^ #]' <brief>` prints 1) and no other open `person` item: it → `queued` (a re-scope that waited for its person-only steps, #101) |
   | `person` | `done` or `approve` | append `- <date> person-only step #<n> (<kind>): <step> → <answer>` to the brief's `## Decisions` (`n` and `kind` from the item's body, the step from its title); the row does not change, with the same exception as the row above. A `(value)` step never takes this row: `done` alone is asked again, and any other answer but `can't now` or `no` is its value (the two rows above) |
   | `person` | `can't now` or `no` | the same record, then close the answered item and add the same `person` item again (`loops.sh add` returns an item that is still in the queue, answered or not, and adds nothing): the open item keeps the row from starting on a go, and the next batch summary asks it again. A `risky` step answered `no`: append "risky call refused: <step>" under `## Feedback`, row → `inbox`, and do not add the item again: the brief stage plans without it |
   | `person` | anything else | record it under `## Decisions` as feedback on that step (the same line, ending `→ feedback: <answer>`), then close the answered item and add the same `person` item again: the step is asked again, and the row stays out of the go |
   | `go-merge` | exactly `go`, `yes` or `ok` | write a grant for that item as for `go-batch`, and stamp `grant:` in its brief; the row stays `verifying`, and the next merge-gate check may merge it |
   | `go-merge` | drop / not merging | row → `dropped`; its PR stays open for the user |
   | `go-merge` | anything else | nothing changes: add the same `go-merge` item again |
   | `accept-report` | exactly `accept`, `yes` or `ok` (any case) | row → `post-queued` |
   | `accept-report` | drop | row → `dropped` |
   | `accept-report` | anything else | it is a decision: append it to the brief under `## Decisions` with the date; row → `queued`, so the build stage runs again with it |
   | `escalation` | drop | row → `dropped` |
   | `escalation` | an answer that ships the PR's head with the codex gate's open findings deferred ("ship it", "merge it, defer the findings"), on a row with a PR whose newest review is NOT-SAFE | first the proof, which STAR writes and never reads (#82). `<k>` is the newest round: `ls HOME_DIR/reviews/<project>/ | sed -n 's/^<item>-r\([0-9]*\)\.md$/\1/p' | sort -n | tail -1`. The head is the PR's: `gh pr view <pr url> --json headRefOid --jq .headRefOid`. Then `sh S/../babysit-pr/review-proof.sh carry --reviews HOME_DIR/reviews/<project> --item <item> --round <k> --head <that head> --decision <the answered item's id> --note "<the answer>"`. `wrote <path>` → append "- <date> the owner shipped <head7> with the findings of <item>-r<k>.md deferred (<id>): <the answer>" to the brief's `## Decisions`, `head=<that head>`, row → `babysit-queued`: `stage-start.sh` gives babysit that file as `--reviewed`, and babysit posts the carried PASS with it. `ERROR <why>` → queue `--kind held` "could not record the owner's carried PASS for <item>: <why>" and leave the row as it is |
   | `escalation` | anything else | the answer is the decision. Brief stage: append it to the brief file under `## Feedback` (creating the file with only that section when the worker stopped before writing a brief), row → `inbox`; the brief stage then runs with `--feedback`. `reason=no-safe-verdict` (babysit could not prove the head passed the gate) or `reason=mismatch` (a `DONE` that did not check out twice): append it under `## Decisions`, row → `queued`: the build resumes the gate loop on the existing PR. A row with no PR whose worker lacked `gh`: an answer that is a PR URL records it, row → `queued` (the build resumes on it). Any other stage: append the answer to the brief under `## Decisions` with the date (workers read that section first and treat it as binding; where two decisions disagree the later one wins), then put the row in the waiting state of the stage in its `stage` column (babysit resumes with `--since <cursor>`) |
   | `question` | any | `orca orchestration reply --id <the item's msg id> --body "<answer>" --json` |
   | every `escalation` and `restart-or-drop` answer that runs a stage again | also clears every counter except `hold=`, `last=`, `start=`, `tracker=`, `batch=`, `rescoped=` and `parent=` from the row (`sh S/ledger.sh set <item> counters=keep:hold,last,start,tracker,batch,rescoped,parent`), and `restarts` goes back to 0: the user's "try again" starts with fresh budgets, while the attempt number (so a new start never reuses an old request id), the last status written, the batch and the re-scope lineage stay |
   | `restart-or-drop` | restart | `git -C <worktree> status --porcelain` must print nothing. Clean → `queued` (the build resumes on the branch as it is). Not clean → change nothing and add the item again with the title "build was interrupted: clean <worktree> first, then answer restart" |
   | `restart-or-drop` | drop | row → `dropped` |
   | `restart-or-drop` | anything else | add the item again with the title "build was interrupted: answer restart or drop" |
   | `draft` | send | a draft whose first line is `to: pr <url>` is posted with `gh pr comment <url> --body-file <the rest>`; any other draft is the user's to send, say so. Before posting, append `<iso>\tSTAR\t<item>\tposted draft N-<id>` to `sent.log`; when that line is already there the draft was posted and only the close was lost: just close the item. Posting is an outward action: inside quiet hours, leave the item open (do not close it) and say "posts at the first tick outside the quiet window"; the Answers step sees it again every tick and posts it then |
   | `held` "could not move <item> to <status>…" | done | `counters.tracker=<status>` (the user moved it), then close it |
   | `held` "<item>'s worktree … was kept…" | done | clear `counters.kept=`, so the next tick runs `worktree-clean.sh` for it again, then close it |
   | `held` "the review gate is down…" | `retry` | `sh S/codex-gate.sh check` now. `up <agent:model>` → as Housekeeping's `up`. `down <why>` → write `checked=<now>` and `why=<why>` in `gateDown`, close the item and add it again with the new `<why>` |
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
   too, named in the status line.
   `waiter-exists <pids>` means an earlier wait still holds this run's waiter (#38). The pids are
   orphaned waits only (`messages.sh` lists only waits whose parent is pid 1, never another live
   session's): end each (`kill <pid>`), then wait again. `waiter-exists -` (none found): wait
   again once; a second `waiter-exists -` in a row is handled as `unknown <why>` and files an
   improvement issue.
   STAR reads only the report's lines (at most 12 lines): it
   never opens a review, evidence or log file, and never reads a worker's screen; the scripts do
   that and give one line back. A `cut` report: act on the first 12 lines and queue `--kind held`
   "<item>: report was cut at 12 lines".

   The first row that fits wins, top to bottom. A line that lacks a field its row names (`DONE`
   without `pr=`, `RESCOPE` without `review=`) fits only the last row. A brief stage's `BRIEF`,
   `SPLIT` or `ESCALATION` settles the brief's feedback side file first (#112, "Feedback while a
   brief drafts", in "The batch summary and go").

   | First line of the report | Action |
   |---|---|
   | `BRIEF item=… path=… … rescoped=1 followup=<path>` (a re-scope's brief) | in every case: `counters.rescoped=1`, clear `counters.rescope`, add the follow-up spec as a new `inbox` row (its `ref` is the path, `counters.batch` the parent's, `counters.parent=<item>`), and queue one `--kind person` per line of the brief's `## Person-only steps`, as the next row does. A brief with no grant line (`grep -cE '^grant: [^ #]' <brief>` prints 0): row → `brief-ready`, finished as the next row does. A brief that keeps its grant (it prints 1): row → `queued` when none of those steps is open, else `brief-ready`, with "<item>: re-scope waits for <n> person-only steps" in the status line; the grant still covers it |
   | `BRIEF item=… path=… [asks=<n>] [followup=<path>]` | row → `brief-ready`; queue one `--kind person` per line of the brief's `## Person-only steps` section (`sed -n '/^## Person-only steps/,/^## /p' <brief>`, at most 20 lines, nothing else of the brief). When the line carries `followup=<path>`, also add that path as a new `inbox` row (its `ref` is the path, `counters.batch` the parent's, `counters.parent=<item>`), as the re-scope row does. A row with `counters.parent=` (a follow-up) and no person-only step, whose parent's brief has a grant (`grep -cE '^grant: [^ #]' <the parent's brief>` prints 1): stamp `approved: <iso>` and its parent's `grant:` in its brief, and `rescopedFrom: <parent>` when the parent was re-scoped (its `counters.rescoped=1`); row → `queued`, and say "covered by <parent>'s go" in the status line. A follow-up whose parent has no grant yet stays `brief-ready` and goes with its batch's go. When no row of its batch is `inbox` or `briefing` any more, print the batch summary and queue the `go-batch` item ("The batch summary and go") |
   | `SPLIT item=… into=<path>,<path>` | one `inbox` row per path (`ref` the path, the same `counters.batch`); the row → `dropped`, and the status line says "split into <names>" |
   | `DONE item=… pr=<url> head=<sha> review=<path>` | first `sh S/done-check.sh <item> --pr <url> --head <sha>`. `OK` → record the PR and head, free the build slot, row → `babysit-queued`, clear `mismatch=`. When the brief carries another author's PR (#94: `sed -n 's/^Decision: carried as a new PR: \([^ ]*\) .*/\1/p' <brief>` prints its URL) and its `## Decisions` has no record of closing it (`grep -cF 'close <that url>: carried on' <brief>` prints 0), also `loops.sh add --kind person --project <p> --item <item> --title "close <that url>: carried on <pr url>" --body "brief: <brief path>\nstep: -\nkind: account\nOptions: done / can't now"`: the owner closes the original now that its new PR is open, and the `person` rows record the answer. `MISMATCH <what>` → record the PR and head; with no `mismatch=` yet: write `mismatch=1`, append to the brief's `## Decisions` "- <date> the report did not check out: <what>; resume the gate loop on the existing PR", row → `queued`. With `mismatch=1` already: → `escalated`, queue `--kind escalation` "the report did not check out twice: <what>" (`reason=mismatch`). `PENDING <why>`, no line, or a non-zero exit → process and ack the message as for any report, record the PR and head, and keep the row `building` with `verify` = `retry=<now + 2 min>`: it has reported, so neither the reconcile step nor Housekeeping's probe treats it as a lost worker, and Housekeeping runs `done-check.sh` again once that time has passed. Exit 64 (`done-check.sh` refused its arguments) also files an improvement issue |
   | `RESCOPE item=… reason=<gate or hosted-review> review=<path>` | free the slot. When the row has `counters.rescoped=1` or its brief has `rescopedFrom:` → `escalated`, queue `--kind escalation` "NOT-SAFE again after a re-scope" with the review's path. Otherwise row → `inbox` with `counters.rescope=<the review file's name>`: its next brief stage narrows the item (`--rescope`) |
   | `READY item=… pr=… head=<sha> cursor=<cursor>` | record head and cursor; row → `verifying`; run the merge gate now ("The merge gate"). The cursor is an opaque string from `pr-state.sh` (a time, then `#` and the ids already seen in that second): store it and pass it back as `--since` exactly as it came |
   | `ESCALATION item=… reason=review-unavailable needs=ERROR gate-down …` in a `worker_done` | the review gate is down for every model, Sol and its Claude fallback ("Gate down", in "Stages"). Record `cursor` when given, free the slot, row → its stage's waiting state (`queued` for a build, `babysit-queued` for a babysit, which resumes with `--since <cursor>`), and append "- <date> the review gate is down: <why>; parked until it is back" to the brief's `## Decisions`. When `gateDown` in `star.json` is null or absent: set it to `{"since": "<now>", "why": "<why>", "checked": "<now>"}`, queue `--kind held` "the review gate is down since <since>: <why>. Answer retry to check it now", and notify. When it is set already: nothing more, so one held item stands for every parked row |
   | `ESCALATION item=… phase=… reason=… [cursor=<cursor>] needs=…` in a `worker_done` | record `cursor` when given; row → `escalated`; queue `--kind escalation` (and `--kind draft` with it when the report has a `DRAFT <path>` line); notify; free the slot. `reason=ci-missing` (babysit found no CI run on the PR's head while the PR does not conflict with its base, #102) is the owner's to look at: missing checks are never a pass, so STAR neither answers it nor restarts the stage on its own |
   | `MERGED item=… pr=<url>` (a babysit worker saw the PR merged) | handle it as `pr-verify.sh` printing `MERGED`: release record, row → `done` |
   | `REPORTED item=… path=<path>` | row → `reported`; queue `--kind accept-report` with the path; free the build slot. STAR never opens the report |
   | `POSTED item=… url=<url>` | row → `done`; free the build slot (its `SENT` line goes to `sent.log` as for any report) |
   | an `escalation` message while the worker still runs | queue it and notify, but keep the row and its slot until its `worker_done` arrives |
   | a `question` message | **STAR answers first** ("Looking after the workers"): when the answer is STAR's to give → `reply` at once and record it; an in-scope product call is always STAR's, decided from the sourced options the worker brings. When it is the user's: a row that already has an open `question` item → close that item and `reply` to its `msg:` id "Superseded by your newer question." first. Then, inside quiet hours or while the user is away → reply "No answer from the user: escalate this." at once (nobody will read it in time); otherwise queue `--kind question` with the deadline `messages.sh` printed, notify, keep looping; the worker stays blocked and keeps its slot |
   | `CONFLICT:`, `AMBIGUOUS:`, `BRIEF-VIOLATION:` or `STOPPED:` (a `receive-review-and-execute` run that reported by itself) | as an `ESCALATION` whose reason is that word and whose `needs=` is the rest of the line |
   | a `worker_done` whose first line starts with none of its stage's report words (brief: `BRIEF`, `SPLIT`, `ESCALATION`; build: `DONE`, `RESCOPE`, `REPORTED`, `ESCALATION`; babysit: `READY`, `MERGED`, `RESCOPE`, `ESCALATION`, `CONFLICT:`, `AMBIGUOUS:`, `BRIEF-VIOLATION:`, `STOPPED:`; post: `POSTED`, `ESCALATION`), and the row has no `shape=` | a prose body in place of the report (#56). Write `counters.shape=1` with `last=`, keep the row in its state and its slot, and do not run `worker-release` for it; then `orca orchestration send --to dispatch:<dispatch> --subject "report" --body "STAR: your worker_done body must be the report lines your skill names, first line one of <that stage's words>. Send it again." --json`. The message does not count as a processed report: the settlement rule in Housekeeping still applies to that worker |
   | the same, and the row has `shape=1` | row → `failed`; queue `--kind escalation` "<stage> worker sent no report line twice: <the first line>" with `reason=report-shape`; free the slot |
   | anything else, or no report line | row → `failed`; queue `--kind escalation` quoting the first line; free the slot. Never re-run without the user's answer |

   `PHASE`, `PR` and `GATES` lines need no action: the gate manifest is
   already at the brief's `star.gates` path, which the babysit stage is given.

   Also, for any report: each `HELD item=… action=…` line → `--kind held`; a `NOTE: <text>` line →
   append `- <date> <item>: <text>` to `HOME_DIR/memory/<project>.md`; a `NOTE: accepted residual <criterion>: <follow-up path>` line
   also adds that path as an `inbox` row (its `ref` the path, `counters.batch` the item's,
   `counters.parent=<item>`; `ledger.sh name` prints `open <item>` when STAR already added it, and
   then nothing is added), or, when no file is at that path, queues `--kind held` "<item>'s
   accepted residual names <path>, which does not exist"; a `SENT …` line → append
   `<iso>\t<project>\t<item>\t<the text after SENT>` to `HOME_DIR/sent.log`; a `STAR-ISSUE: <text>`
   line → "Improvement issues". STAR logs its own sends
   there too (a draft it posted with `gh pr comment`). After each settled
   `worker_done`: `orca orchestration worker-release --dispatch <id>` (in the order of effects
   above: before `processed.log`).
4. **Fill slots** by the pool rules above. Before filling, the PR check: for every row that has
   a PR and is `queued`, `building`, `babysit-queued`, `escalated` or `failed`,
   `sh S/pr-verify.sh <pr url> --head <head, or 0000000 when none is recorded>`. Only
   two answers matter here. `MERGED <sha>`: the user merged early; stop the row's worker if it has
   one (`worker-stop`, then `worker-release` and the gone check), close the row's open `escalation` item if any, then
   handle it as `MERGED` below. `FAIL closed`: stop and release the worker, row → `escalated`,
   queue `--kind escalation` "PR was closed without a merge" (a row already `escalated` or
   `failed` only gets the queue item). Every other answer is ignored in these states. So no slot
   is ever given to an item whose PR is already merged or closed.
   While `gateDown` is set, start no build and no babysit: those rows wait for the gate ("Gate
   down"); brief and post stages need no gate and still start.
   Then, for each free slot, the row next in line: `sh S/stage-start.sh <stage> <item>`. Run it with the Bash
   tool's `run_in_background: true` and wait for its completion notification,
   like `gate-lock.sh` in a worker: creating a worktree with a setup hook, clearing the dialogs
   and starting the worker can take longer than the tool's 600 s foreground cap. It runs the host gate (memory, agents, swap and disk),
   sets up a build's worktree, clears Claude Code's first-run trust dialogs, writes the prompt and
   starts the worker, writing the row as it goes; a worktree named in another open row is refused
   (`failed in-use`). Its last line is one of these. Before it, up to three lines of their own may come
   (`stopped previous gate …`, `ended previous session …`, `kept previous session …`): say each in
   the status line as `<item>: <the line>`, one line each, then act on the last line:

   | Line | Then |
   |---|---|
   | `started task=… dispatch=…` | nothing more. A ` fallback <model>: <why>` suffix → `--kind held` "<stage> for <item> ran on <model>: <why>" |
   | `hold <what> <value>` (`memory`, `agents`, `swap` or `disk`) | the host gate held it: start nothing else this tick; `counters.hold=+1` on that row; at `hold=3`, `--kind held` "the host gate held every start for 3 ticks: <what> <value>" (for memory: "memory below 3 GB: nothing can start") and notify. The next start that succeeds clears `hold=` and closes that item |
   | `hold trust <path>` | `--kind held` "trust <path> for Claude Code once: run `claude` there and accept, then answer done"; the row keeps waiting and the next tick tries again |
   | `stopped previous gate pgid=<n>` (a line of its own, before the last line) | the item's earlier session still held the gate lock under the label `<project>/<item>`, and `stage-start.sh` sent TERM to that gate (#76): say `<item>: stopped previous gate pgid=<n>` in the status line, then act on the next line |
   | `ended previous session <terminal>` (a line of its own, before the last line) | the previous dispatch's own terminal was still open, or Orca reports that dispatch `released` with no retained reason (#95), and `stage-start.sh` closed it (#76; a released dispatch whose close fails is ended all the same): say `<item>: ended previous session <terminal>` in the status line, then act on the next line |
   | `kept previous session <terminal> (<state>)` (a line of its own, before the last line) | a terminal Orca cannot place as the dispatch's (`user_takeover` or `identity_unproven`) had been quiet for 10 minutes or more, so it was left open and the start goes on (#76): say `<item>: kept previous session <terminal> (<state>)` in the status line, then act on the next line. A dispatch Orca reports `released` with no retained reason is ended, not kept (#95); one a person kept (`retainedReason` set, for example `user_takeover`) follows this row as before |
   | `hold session <terminal> (<state>)` | a session may still be working on this item (#76): a terminal Orca cannot place as the previous dispatch's (a person took it over, or Orca cannot prove whose it is, including a `released` one a person kept (`retainedReason` set); a session Orca reports `released` with no retained reason is ended, #95), or another `claude` or `codex` terminal in the item's worktree, printed output in the last 10 minutes. Start nothing for this row and keep it in its waiting state; queue `--kind held` "<item>: terminal <terminal> (<state>) may still be working on it; close it or finish there, then answer done", and give the slot to the next row in line. The next tick tries again |
   | `wait until <iso>` | the brief's `notBefore` is still ahead (#87): start nothing for this row, keep it `queued`, say `<item> waits until <date>` in the status line, and give the slot to the next row in line |
   | `failed <step>: <why>` | row → `failed`, `--kind escalation` "<stage> could not start: <step>: <why>" |
   | no line, or a non-zero exit | the script was cut off: put the row back in its stage's waiting state with its `counters` as they are (its `live=` makes the next start a replay of this one), and file an improvement issue ("Improvement issues") |

   A `queued` row starts only when its brief is stamped (`grep -cE '^approved: [0-9]' <brief>`
   prints 1), every item its brief's `blockedBy` line names
   (`sed -n 's/^blockedBy: //p' <brief>`, one line) is `done` or `dropped` (#37), and its
   `notBefore` time (`sed -n 's/^notBefore: //p' <brief>`), when it has one, has passed (#87):
   `stage-start.sh build` checks that itself and prints `wait until <iso>` before then. A `post-queued`
   row starts only outside quiet hours: posting is outward.
5. **Housekeeping.**
   - Questions past their deadline: when the user is not away, it is not quiet hours and the row
     has no `reask=`, remind once: a push notification "still waiting on you: <question>", the
     question first in the status line, the item added again with its `deadline:` moved on by its
     original length (then close the old item), and `counters.reask=1`. Otherwise reply "No answer
     from the user: escalate this.", close the item and clear `reask=`.
   - Each row in a worker stage that has not reported this tick (a `building` row whose `verify`
     holds `retry=` has reported: its `DONE` waits for `done-check.sh`, below):
     `sh S/worker-probe.sh <dispatch> --item <item> --home HOME_DIR --worktree <worktree> --deadline <progressDeadlineMin>`
     (no `--worktree` for a `briefing` or `posting` row).
     A ` holds-screen <m>` ending → name it in the status line (`screen: <item> <m> min`).
     `ok`, `stale <minutes> <terminal>` or `quiet <minutes> <terminal>` (with or without that
     ending): the worker runs and shows no screen to act on, so read its step with
     `sh S/step-check.sh --item <item> --home HOME_DIR --state <state> --deadline <progressDeadlineMin>`,
     adding `--worktree <worktree>` (not for a `briefing` or `posting` row), `--pr <pr>` when the
     row has one, `--asked <counters.asked>` when that is set and `--hosted <hostedReviewer.login>`
     when `star.json` has a hosted reviewer, and act on its one line ("Checking in", in "Looking
     after the workers"). `stalled: model at capacity` → the capacity rule:
     below `capacity=3`, send

     ```sh
     orca terminal send --terminal <terminal> --text "STAR: the model was at capacity. Retry now." --enter --json
     ```

     and `counters.capacity=+1`; at `capacity=3`, `worker-stop`, `worker-release` and the gone check, and treat it as
     a lost worker (the reconcile rule: a `briefing`, `posting` or `babysitting` row restarts once;
     a `building` row gets `--kind restart-or-drop`) (#41).
     `prompt bounded <terminal> <path>` (#114): the worker sits on Claude Code's safety prompt for an
     `rm` or `rmdir` of a variable path, and `worker-probe.sh` found every operand inside the item's
     worktree or a Claude Code session scratchpad. Below `prompted=3`, send
     `orca terminal send --terminal <terminal> --text "1" --json` (no `--enter`: the digit picks the
     option, and an Enter could answer what comes next), append
     `- <date> STAR answered a permission prompt for the <stage> worker: Yes (<path>)` to the brief's
     `## Decisions` (a row with no brief yet: the status line only), name it in the status line, and
     `counters.prompted=+1`. At `prompted=3`, a fourth `prompt bounded` takes the `stuck:` path below.
     `stuck: <what>` → `orca orchestration worker-stop`, then `worker-release` and the gone check, row → `failed`, queue
     `--kind escalation` "<stage> worker stuck: <what>" (a prompt the probe would not answer reads
     `stuck: confirmation dialog: <its line>`, so the escalation names it). `settled failed agent_prompt_stalled` (the
     worker never took its prompt) → `failed`, release, queue `--kind escalation` "<stage> worker
     never received its prompt: most likely Claude Code's trust dialog for <worktree>. Trust it once
     (run `claude` there and accept), then answer restart". Any other `settled …` with no processed
     report: `silent=1` in `counters` the first time; the second time in a row → `failed`, release,
     queue it. `gone` → the reconcile rule for a lost worker. `unknown <why>` → `unknown=<n>` in
     `counters`; three ticks in a row → `failed`, queue it with `<why>` (the worker is not stopped:
     nothing is known about it). Never answer a worker's prompt for it, except `prompt bounded` (above, #114).
   - `sh S/loops.sh list` printing a `missing` line (an id that was handed out and is now in
     neither the queue nor the archive: removed by hand, or lost when an editor saved an older
     copy of the file): say so in the status line, and add again any ask a row still needs (an
     open `escalated` or `failed` row with no open item, a `brief-ready` row with no `go-batch`
     item, a `verifying` row whose brief has no grant (`grep -cE '^grant: [^ #]' <brief>` prints 0)
     and no `go-merge` item).
   - `gateDown` set, and its `checked` 30 minutes or more ago: `sh S/codex-gate.sh check`.
     `up <agent:model>` → set `gateDown` to null, close the held item "the review gate is down…",
     and say "the review gate is back (<agent:model>)" in the status line: "Fill slots" starts the
     parked rows. `down <why>`, no line or any other exit → write `checked=<now>` in `gateDown`
     (and `why=<why>` when it printed one).
   - `verifying` rows (past the `retry=` time in `verify` when one is set): the merge gate (below). `building` rows past the `retry=` time in `verify` (a `DONE` that `done-check.sh` could not check yet): `done-check.sh` again with the row's PR and head, and its line acted on as the `DONE` row of the Messages table says.
   - Notifications (below).
   - The tracker status ("The tracker status").
   - Improvement issues met this tick ("Improvement issues").
   - Finished worktrees: each `done` or `dropped` row that still has a worktree and no `kept=` gets
     `sh S/worktree-clean.sh <item>`. It removes the worktree only when nothing in it would be lost
     (clean, and its work on the remote or merged), never with work in it that exists nowhere else.
     Before it removes one, it copies every evidence folder it finds there (`evidence/` under the
     docs root STAR's home implies, `docs/superpowers` and `docs/.superpowers`) to
     `HOME_DIR/evidence/<item>/` and prints `kept-evidence <path>` first: name it in the status line
     too. A copy that fails keeps the worktree (`kept <path>: evidence copy failed: <why>`, below).
     `removed <path>` → name it in the status line. `kept <path>: <why>` → `--kind held` "<item>'s
     worktree <path> was kept: <why>", and `counters.kept=1`. `none` → nothing. `failed` and
     `escalated` rows keep their worktrees until the user answers.
   - Away: `sh S/handoff.sh --home HOME_DIR due` printing `due` → `sh S/handoff.sh --home HOME_DIR summary`.
6. **Write.** `loops.sh resume …` with the current pools and the next step;
   `loops.sh waiting "<one line per PR in review, per blocked question>"`. Nothing is committed:
   the folder is plain files. Print one status line: counts per state, then every open queue item, `screen: <holder>, renewed <time>`
   while `sh S/../ship-ticket/screen-lock.sh status` does not print `free`, `gate down since <since>`
   while `gateDown` is set, each `note` line from
   this tick's `step-check.sh` (`<item>: <diagnosis>`), each restart (`restarted <item> at <step>`),
   and each issue filed this tick ("filed issue #19").

**Active or idle.** While any row is in `inbox`, `briefing`, `building`, `babysit-queued`,
`babysitting` or `posting`, in `verifying` while its `verify` holds no `retry=` in the future, or in
`queued` or `post-queued` while it may start, or while `gateDown` is set, stay in the turn and tick
again (step 3's bounded wait is the clock). When every row is waiting on the user or finished, write
`state: idle` and STAR ends its turn. It is woken by a hand-over nudge, by the user, or by the
heartbeat, and each wake runs one tick. A `queued` row waiting for its `notBefore` date cannot
start, so it does not keep STAR in the turn: the heartbeat's next wake tries it again. While a question is open in chat, STAR does not
stay in the turn: each wake runs one tick, then STAR prints the open question again and ends the
turn ("The batch summary and go").

## Stages

Every stage is its own Orca task and a fresh worker.

| Stage | Worktree | Agent | Prompt |
|---|---|---|---|
| brief | the project's main checkout (`path:<repo path>`), read-only | `stages.brief` | `/juel:star draft-brief <ref> --project <name> --item <name> --out HOME_DIR/briefs/<project>/<item>.md [--feedback] [--rescope HOME_DIR/reviews/<project>/<file>]` (the row's raw `ref`, then its item name; `--rescope` when the row's `counters.rescope` names a review file) |
| build | a new Orca worktree in that project, set up as below | `stages.build` | `/juel:ship-ticket --unattended --brief <brief> [--quiet-hours <window>]`: the plan, the executor, the fresh Claude review, the live checks, the draft PR and the codex gate loop, in one worker |
| babysit | the item's worktree | `stages.babysit` | `/juel:babysit-pr <n> --unattended --mark-ready --reviewed <the item's newest review> --item <item> --brief <brief> --gates-file HOME_DIR/gates/<project>/<item>.json [--since <cursor>] [--quiet-hours <window>]` (`--reviewed` is the newest round's `<item>-r<k>-carried.md` when the owner shipped that round, else the newest `<item>-r<k>.md`, the gate's SAFE review of the head: the worker's proof that the head passed the gate. The build marks the PR ready after its final SAFE round; `--mark-ready` marks it when quiet hours held the build's) |
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
   delete Orca's; otherwise, for a brief with `existingPr`, fetch it from `project.remote` and
   check it out tracking the remote branch (the open PR's head), then delete Orca's; otherwise
   rename Orca's branch to it. Git is authoritative; Orca's view of the branch can lag for a
   moment.
4. **Environment files** from the main checkout, only files git ignores (`git check-ignore`):
   `.env*`, `*.local`, `.envrc`, `.npmrc`, `.tool-versions` and ignored files under `.claude/`.
   Ignored files never show in `git status`, so `ship-ticket`'s clean-tree check still passes,
   and a worker's `git add -A` can never commit them; an untracked file that is not ignored is
   someone's work in progress and stays where it is. The worktree must then be clean.
5. **A worktree inside the repository** (`<repo>/.worktrees/…`) gets one line in
   `.git/info/exclude` for its top folder, so the main checkout's `git status` stays clean.

**Starting a stage** is `stage-start.sh` ("Fill slots"). It runs the host gate first ("The host
gate"). Agent, model and effort come from `stages.<stage>` (else `worker`). A failed
`worker-start` is retried once: with `--retry-of` and the same placement, one effort level lower
when the effort was refused, or, when the launch refuses the model (the agent is not installed, no
access, no credits), it falls back to `worker` once and says so in a `fallback` suffix.
`task-create` and `worker-start` carry `--retry-request` ids, so a replay never makes a second task.
Every spec is one line: Orca echoes the spec inside its JSON, and a line break there once made the
output unreadable and left an orphan task. A worker that starts and then sits on a usage-limit
screen is the probe's `stuck: usage limit`.

`--quiet-hours <window>` is `star.json`'s `quietHours` rendered as `HH:MM-HH:MM@tz` (for example
`22:00-07:00@Asia/Manila`), omitted when it is null. Being away
does not change it: away holds no work, and only quiet hours hold what goes out. A window is never judged by hand:
`sh S/../ship-ticket/quiet-hours.sh "<window>"` prints `inside` or `outside`;
anything but exit 0 with exactly `inside` or `outside` (exit 64 for a window it cannot read, a
missing script, no `python3`, an empty line) is treated as inside: hold what would go out, notify only escalations,
and queue `--kind held` "fix quietHours in star.json: <what the script said>". A window that
cannot be judged never lets something out.

**The codex gate.** Not a stage and not a worker: the build worker runs it on its own draft PR
(`juel:ship-ticket`'s gate loop), and the babysit worker runs it again after every push it makes.
`sh S/codex-gate.sh --brief <brief> --item <item> --round <k> --base <remote>/<baseBranch>` runs
one headless `codex review` of the branch against its base, read-only and with no MCP server, on
`star.json`'s `gate` model (the newest sol at xhigh, resolved like the executor's
`latest-<family>`). Each round pins the base to one commit and records it in the review's `Gate:`
line. A round whose base moved past the branch and changed a file the branch changes refuses
before any review runs, with
`ERROR base-moved <ref> at <B7> changes <path>, a file this branch changes: merge it in, then run round <k>`
(#113): the worker merges the base in, runs the sweep and runs the same round again.
That is not an `ERROR` retry: it counts toward no escalation and casts no `gate.maxRounds` vote.
A base that moved without touching the branch's files is not acted on. A capacity error is retried
after 60 and 180 seconds. After that, or at once
when the Codex account is out of usage, the same prompt runs through `gate.fallback`: a headless
`claude -p` review on Opus at xhigh, with read-only tools and no MCP server. The review's `Gate:`
line and the PASS comment then name it (`claude:opus xhigh`). A fallback run with a denied tool
call (it may not have read the diff) is retried once inside the round, told which call was denied
(#100). When the fallback fails too, or a second denial follows, the gate prints
`ERROR gate-down <why>`, never a verdict. The fallback searches with Grep and Glob, never
`git grep`, whose `-O` runs a program; its retry line says so too (#117). Its prompt,
`S/template/gate-prompt.md`, kept as
`HOME_DIR/specs/<project>/<item>-gate-r<k>.md`, carries the brief's criteria and `## Decisions`, the
project's notes, the previous round's review and `-fix.md` from round 2, and the review rules from
the base branch, so a PR cannot change its own rules. Only a `[P0]` or `[P1]` finding makes the round
NOT SAFE. It writes three files in `HOME_DIR/reviews/<project>/`: `<item>-r<k>.md`, whose first line
is the verdict, `VERDICT item=<item> round=<k> SAFE findings=<n> head=<sha>` or
`VERDICT item=<item> round=<k> NOT-SAFE findings=<n> head=<sha>`, then the numbered findings, then
Notes; `<item>-r<k>.raw.md`, Codex's own text; and `<item>-r<k>.log`, its transcript. An attempt
that ends in `ERROR` writes none of these: its transcript goes to `<item>-r<k>-error-<n>.log`, and
the next attempt keeps round `k`, so `gate.maxRounds` counts verdicts only. After a SAFE
round the worker posts the receipt with `codex-gate.sh post-pass`, once per head (a direct verdict's
receipt is posted even when a carried receipt already names the head, #104), in two lines:
`Codex gate: PASS (head <full sha>, round <k>, <model> <effort>)`, then `VERDICT: PASS`. Two receipts
carry an earlier verdict, and `post-pass` writes both, so none is ever written by hand. A merge of
the base that `carry-check.sh` proves added no change of its own (#110: the base side changed
none of the files the branch changes, so a merge with a conflict never carries) carries the last
SAFE to the merge head, with
`, carried from <gated head>: <reason>` before the first line's closing parenthesis (#75). A head
the owner shipped with a round's findings deferred carries `, carried by owner decision <id>:
findings deferred` there, and `VERDICT: PASS (owner decision <id>)` (#82; the Answers row for a ship
decision writes its proof). A build still NOT SAFE after `gate.maxRounds` (3) rounds
reports `RESCOPE`. A babysit run counts its NOT-SAFE rounds since the newest SAFE round or its last
push, whichever is later, and reports `RESCOPE` at the `gate.maxRounds`-th (#108). A SAFE round
that could not be pushed, because the PR needed a base merge first, starts a fresh count. STAR
opens none of these files: `done-check.sh` and `pr-verify.sh --merge-gate`
read them and print one line. `done-check.sh` accepts a SAFE round on an earlier head only when
`carry-check.sh` carries it to the PR's head, by the rule above (#110). Luna writes the code and
Sol gates it, so the independent review is
the build's fresh Claude review, before the gate. While the fallback runs, the gate is a second
Claude review, not a second model.

**Gate down.** `codex-gate.sh` prints `ERROR gate-down <why>` when Sol failed and its Claude
fallback failed too. Each build and babysit would then escalate on its own, so STAR holds them
instead: the Messages table parks each row that reports it, `gateDown` in `star.json` keeps
`since`, `why` and `checked`, "Fill slots" starts no build and no babysit while it is set (brief
and post stages need no gate and still start), and Housekeeping runs `sh S/codex-gate.sh check`
every 30 minutes. `check` sends a one-line prompt through the same chain and prints
`up <agent:model>` or `down <why>`. The owner can answer `retry` on the held item to check at once.

## Brief worker mode: `draft-brief`

`/juel:star draft-brief <ref> --project <name> --item <name> --out <path> [--feedback] [--rescope <file>]`
runs in the project's main checkout as an Orca worker. It never edits the repo: it writes only the
brief at `--out`, spec items under `<HOME_DIR>/items/<project>/` when it splits an item or moves
part of it to a follow-up, and in re-scope mode the `-fix.md` of the review it narrowed by. It is
unattended: nobody is at its terminal, so it never asks there.
With `--rescope <file>` it runs in re-scope mode ("Re-scope mode" below).
Where a step below says ask, it sends `orca orchestration ask --question "<question>" --json` and
waits for the reply; a reply of "No answer … escalate this." ends the run with
`ESCALATION item=<name> phase=0 reason=unanswered-question needs=<the question>`.

1. Read `<HOME_DIR>/memory/<project>.md` (HOME_DIR is two levels
   above `--out`'s directory), and `mcps` in `<HOME_DIR>/star.json`: the research MCPs STAR's
   session found (`available`, `needs-sign-in` or `absent`). Then, before step 2, when a file already exists at `--out`, read its
   `## Feedback` section: the user's dated answers to earlier runs of this stage. `--feedback` is
   a bare flag that says there is something new there; the text itself is never put in the prompt,
   where a quote or a line break could change it. An answer there settles the question it answers (which tracker holds the ref, what a
   term means): use it in the steps below and never ask or escalate the same thing again.
   Read `<--out>.feedback.md` too when it exists (#112): one line per entry, feedback STAR took
   while no brief was written yet. Its lines count as `## Feedback` entries. Never edit or delete it.
2. Resolve the project's work source: an explicit source in the ref → `.claude/workflow.local.json`
   / `.claude/workflow.json` `tracker` → a `## Work Source` block in CLAUDE.md or AGENTS.md → the
   legacy `## Linear Worktrees Config` block → the ref's shape when unambiguous (`#412` is GitHub; an
   existing path is a `file` item) → the single connected tracker. Still ambiguous →
   `ESCALATION item=<name> phase=0 reason=needs-human-input needs=which tracker holds <ref>`
   (`<name>` is `--item`, like every report line; the ref goes in `needs=`).
3. Fetch the item in full:

| Provider | `list` | `fetch` |
|---|---|---|
| `linear` | resolve `LINEAR_PREFIX` (the first of `mcp__linear__`, `mcp__plugin_linear_linear__` or `mcp__claude_ai_Linear__` (then any other loaded prefix ending in `linear__`) that exposes both `get_issue` and `list_issues`), then `<LINEAR_PREFIX>list_issues(assignee: "me", project: <id>, state: "Todo")` | `<LINEAR_PREFIX>get_issue(id: <ref>)` |
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
6. Read enough of the code to choose an approach and to take the item's open decisions (grounded,
   as below), then write the brief to `--out`. Right before writing, read `<--out>.feedback.md`
   again when it exists, and copy each of its lines the brief does not already hold, verbatim, under
   the brief's `## Feedback` (#112): STAR may have added one while you read the code. Answer every
   one of them, as below. When a brief already exists at `--out`, read it
   first: revise it to answer every entry under its `## Feedback` section (the user's dated answers
   to earlier drafts, kept there by STAR), keep the `## Feedback` section as it is, and keep every
   entry under `## Decisions` (records and dated lines), adding new records after them with the
   next free `D<n>`.

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
   existingPr: <url>       # only for an item that brings an open PR to mergeable: see below
   deliverable: pr          # or report: see below
   blockedBy: [<item>, <item>]
   notBefore: <YYYY-MM-DD or ISO datetime>   # only when the item must not be built before then
   approved:               # stamped by STAR on the owner's go
   grant:                  # stamped by STAR with the go: the grant file's path
   star:
     home: <HOME_DIR>
     project: <project>
     notes: [<HOME_DIR>/memory/<project>.md]
     reviews: <HOME_DIR>/reviews/<project>
     gates: <HOME_DIR>/gates/<project>/<item>.json
     reports: <HOME_DIR>/reports/<project>
   ---
   ## Work item
   <description, word for word, with every Markdown heading in it demoted one level>
   ## Acceptance criteria
   - [ ] <one per criterion>
   ## Approach
   <2-6 sentences: the chosen approach, the components touched>
   ## Scope
   In: <what this item changes>
   Out: <what it deliberately does not touch>
   ## Checks
   - <what is checked> | auto: <playwright, hidden-window, computer-use, api or cli>[ | helper: <path>]
   ## Person-only steps
   1. [<kind>] <what to do>
   ## Decisions
   ### D1 <title> (<date>, decided by the brief worker)
   Context: <the question the item leaves open>
   Decision: <the choice>
   Consequences: <what it changes or rules out>
   Source: <a URL, a Mobbin screen or flow URL, a context7 library id and topic, or file:line>
   ```

   Acceptance criteria, by case. (1) The item's own and (2) any the user states in a `## Feedback`
   entry go in together, with no suffix. (3) When neither gives any, derive them from the item's
   text (its description, what it links to, and what the code does now), each line ending in
   ` (proposed)`; on every re-draft, keep the earlier draft's proposed criteria with
   their ` (proposed)` suffix, except those a `## Feedback` entry replaces or removes, next to any
   from cases 1 and 2. (4) Only when there is nothing to derive them from, write the single line
   `- [ ] NEEDS CRITERIA`. Never invent criteria the item's text does not support.

   `## Checks` holds one line per acceptance check, each marked with how the build runs it:
   `auto: playwright` (a web page, headless), `auto: hidden-window` (an Electron window: a hidden
   dev build driven over CDP with no screen lock, as `juel:verify`'s Electron row says; add
   `| helper: <path>` when the project has its own launch helper), `auto: computer-use` (a native
   window, through `orca computer`, under the screen lock; also keystrokes into other apps, OS
   prompts, capture and packaged builds), `auto: api` or `auto: cli` (call it and read the
   answer). A check that needs a person
   first (sign in with 2FA, grant a macOS permission once, approve a keychain prompt) adds
   `| person: <what>`, and the same step goes under `## Person-only steps`: the owner does it before
   go, and the build runs the rest of the check itself. A check no tool can run is not left for
   later: find an automated check that proves the same criterion (a decision record says why it is
   enough), or list it as a `risky` person-only step, "ship without a live check of <criterion>?".
   Write `none` when the item has nothing to check live.

   `## Person-only steps` lists what only a person can do, so it is all done before go and nothing
   stops the build later: one numbered line each, `<n>. [<kind>] <what to do>`. Kinds: `secret` (a
   key or an env var, and where it goes), `account` (a login or a paid service), `screen`
   (something a person must do at the Mac: sign in to an app, grant a permission, approve a
   keychain or Gatekeeper prompt once), `confirm-id` (an external id that could not be checked
   live, below) and `risky` (a call the owner must approve: deleting data, a migration that cannot
   be undone, spending money, anything outward beyond the PR). A step whose answer the build needs
   as a value (a host name, an id, a path) adds `(value)` after its kind,
   `<n>. [account] (value) <what to provide>`: the owner's answer is recorded as that value under
   `## Decisions` (`→ value: <answer>`), where the build reads it (#86). Never on a `secret` step:
   the queue and the brief are plain files, so a secret goes where its step says, never into an
   answer. A product call is never a person-only step: take it as a decision record. Nothing the brief, its `## Decisions` or the
   memory notes already answer goes here. Write `none` under the heading when there is nothing.

   **Decisions are taken, not asked.** Every question the item leaves open that a builder would
   otherwise ask (a product call, a library, a name, a format, how an edge case behaves) is decided
   here and written under `## Decisions` as a decision record:
   `### D<n> <title> (<date>, decided by the brief worker)`, then `Context:`, `Decision:`,
   `Consequences:` and `Source:` lines. The owner reads them in the batch summary and can overrule
   any of them in the reply; workers read them as binding. Ground each one in a source, in this
   order of fit: for a user-facing change, the Mobbin MCP (`search_screens`, `search_flows`,
   `search_sections`) for how real apps solve it, and the `frontend-design` skill for the visual and
   interaction choices; for a library, framework, SDK, API or CLI, context7 at the version the
   project uses; when neither fits, a web search, official docs first; for a project convention,
   the repository, cited as `file:line`. Mobbin searches spend paid credits: use them for
   user-facing changes only. Look for the tools `mcps` names `available` (with `ToolSearch` when
   they are deferred) before you decide they are missing, and use an MCP only when this session lists its
   tools. When it does not, or `mcps` says `needs-sign-in` or `absent`, search the web instead and
   say so in `Source:`. A decision no source can settle, and that only the owner
   can make (money, a policy, a legal question), is a `risky` person-only step instead.
   A brief names a file-name, path or id form only by quoting the rule the repository enforces it
   with (a checker, lint or pretest script, `file:line`); when it finds none, it names no form and
   the build follows the repository (#107).

   **External ids are checked live** (#42). Every service slug, project id, DSN, hostname or
   account name the brief carries is checked where a CLI or API can reach it (`gh api`, the
   service's own CLI, a DNS lookup) and marked `(verified <date> via <how>)`, or
   `(unverified: <why>)`. An unverified id becomes a `confirm-id` person-only step: "confirm <id>
   is the right <what>".

   **A hosted review comes after ready** (#40). When the item, a memory note or a `## Feedback`
   entry asks for the hosted reviewer's review before the PR is marked ready, take a decision
   record that the order is ready first, then the review: Greptile skips draft PRs by default and
   starts its review when the PR is marked ready (cite its docs in `Source:`).

   **The copied item's headings** (#36). The description goes under `## Work item` word for word,
   except that every Markdown heading in it is demoted one level (`## Scope` becomes `### Scope`),
   so the item's own sections never collide with the brief's. STAR and the workers read only the
   brief's own top-level sections.

   **Blocked by** (#37). `blockedBy` lists the items this one needs merged first, `[]` when none:
   from the item's own links (a Linear "blocked by" relation, a GitHub "depends on #n" or "blocked
   by #n") and from items of the same batch whose changes this one builds on (the open rows of
   `<HOME_DIR>/ledger.md`). Use each item's ledger name. A blocker STAR does not track goes under
   `## Approach` instead, with what the build does until it lands. Never a cycle: when two items
   would block each other, keep the link the code needs and take a decision record.

   **Not before** (#87). When the item's text, a memory note or a `## Feedback` entry says it may
   only be built after a date or time ("after Wednesday", "not before the 15th"), set `notBefore`
   to it: `YYYY-MM-DD` for a day, which starts at 00:00 in `star.json`'s `quietHours.tz` (the
   machine's local zone when quiet hours are off), or an ISO datetime with an offset or `Z`. Take a
   decision record that quotes the words it came from. Leave the key out otherwise.

   `deliverable` is `report` when every acceptance criterion asks only for evidence, a
   disposition or a write-up (exercise flows and record what passed, map an impact, assess a PR,
   post a status) and nothing in the item asks for a change to code or docs in the repository;
   otherwise `pr`. A `## Feedback` entry that names one ("deliverable: pr") wins.

   `existingPr` is set only when the item's outcome is to bring an open PR to mergeable (the item
   links an open PR and asks to finish, update or merge it, rather than to build something new):
   `gh pr view <url> --json url,headRefName,baseRefName,isCrossRepository,state,author`, and
   only when `state` is `OPEN`; otherwise leave `existingPr` out and take a decision record that
   the item is built as a new PR. Then `branch` is its `headRefName` and `baseBranch` its
   `baseRefName`, and step 5's naming rule does not apply. A PR whose `isCrossRepository` is
   true comes from a fork, which cannot be pushed to: leave `existingPr` out and take a decision
   record that `<url> comes from a fork`, so the build opens a new PR from a copy of its branch.
   A PR whose `author.login` is not the `gh` user (`gh api user --jq .login`) is handled like a fork
   (#94): every gate binds its receipt to the PR's author, while STAR acts as the `gh` user. Leave
   `existingPr` out, name `branch` by step 5's rule (never the original's `headRefName`), take
   `baseBranch` from its `baseRefName`, and take a decision record that
   `<url>` is `<login>`'s PR, carried as a new PR, with the `Decision:` line exactly
   `Decision: carried as a new PR: <url> (<login>'s PR)`. The build opens a new PR from the
   original's head, so the commits keep their author, and
   the PR body links `<url>` and credits `@<login>`. The brief adds no person-only step for the
   original: STAR asks the owner to close it once the new PR is open (the `DONE` row in Messages).
7. Report, as the `worker_done` body: `BRIEF item=<name> path=<--out> asks=<n> [followup=<path>]`
   (`<n>` is the number of lines under `## Person-only steps`, 0 for `none`). Add `followup=` when
   a `## Feedback` entry made part of the item impossible as written and you moved that part to a
   follow-up spec item, `<HOME_DIR>/items/<project>/<name>-followup.md` (`-followup-2` when that
   file exists; frontmatter `status: todo` and `title:`, then what is left to do and the feedback
   that moved it), with a decision record that says what moved and why. Then `NEEDS-CRITERIA` (case 4 of
   step 6) when that applies, or `PROPOSED-CRITERIA` when any criterion ends in ` (proposed)`,
   then at most one `NOTE: <one line>`, and at most one `STAR-ISSUE: <one line>` when STAR's own
   contract or tools got in the way (no project or ticket names). An item that holds more than one
   piece of work that could ship on its own is split instead: write each piece as a spec item,
   `<HOME_DIR>/items/<project>/<name>-<k>.md` (frontmatter `status: todo` and `title:`, then the
   words of the item that describe that piece), write no brief, and report
   `SPLIT item=<name> into=<path>,<path>`.
   The `worker_done` body is these report lines and nothing else: it overrides any request for a
   prose summary, Orca's worker preamble included. STAR reads the first line as the report.

**Re-scope mode** (`--rescope <file>`). The build or babysit worker could not get the item past a
reviewer (the codex gate after its rounds, or the hosted reviewer after its passes), and `<file>`
holds the findings still open. Read the brief with its `## Decisions`, then `<file>`, then what the
branch changed so far (`git fetch <remote>`, then
`git diff --stat <remote>/<baseBranch>...<remote>/<branch>`). Narrow the brief to what the branch
can ship safely: move each part the findings show cannot be done safely in this item to Scope
`Out:`, drop or reword the criteria that belonged to it, and take a decision record that says what
moved and why, with the findings file as its source. Keep `approved:`, `grant:`, `branch`,
`baseBranch` and `existingPr` as they are: the narrowed item builds on the same branch and PR,
under the same go. `## Person-only steps` follows step 6's rules, and leaves out a step its
`## Decisions` already records as answered: STAR asks the rest before the build runs again, under
the grant or not (#101). Write what moved as a follow-up spec item,
`<HOME_DIR>/items/<project>/<name>-followup.md` (frontmatter `status: todo` and `title:`, then what
is left to do and the findings that sent it there). When `<file>` is a codex gate review
(`<item>-r<k>.md`) and no `<item>-r<k>-fix.md` lies beside it, write that file: one line per
finding of the review, in its order, `Disposition: moved to <follow-up path> (decision D<n>)` or
`Disposition: kept, <why> (decision D<n>)`, citing the decision record that moved or kept it. The
next gate round reads it as the dispositions of those findings, so it does not raise settled
findings again. A hosted review file gets none: the gate never saw its findings. Report
`BRIEF item=<name> path=<--out> asks=<n> rescoped=1 followup=<path>` (`<n>` as in step 7). When
narrowing cannot leave anything safe to ship, report
`ESCALATION item=<name> phase=0 reason=rescope-impossible needs=<why>`.

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
| `linear` | the Linear MCP's comment tool, `<LINEAR_PREFIX>save_comment` or `<LINEAR_PREFIX>create_comment`, whichever that prefix has, with `(issueId: <id>, body: <the report file's text>)` |
| `github` | `gh issue comment <n> --body-file <path>` |
| `jira` | the connected Jira/Atlassian MCP's add-comment tool |
| `file` | nothing to post: add `report: <path>` to the spec file's frontmatter |

Report, as the `worker_done` body: `POSTED item=<name> url=<comment url, or the spec path>`, then
`SENT report posted to <ref>`. A post that fails: `ESCALATION item=<name> phase=0
reason=post-failed needs=<what the tracker said>`. The `worker_done` body is these lines and
nothing else: it overrides any request for a prose summary, Orca's worker preamble included.

## The merge gate

Each tick, every `verifying` row (past the `retry=` time in its `verify` when one is set) runs the
merge gate on the head its `READY` reported: `sh S/pr-verify.sh <pr url> --head <head> --merge-gate`,
adding `--hosted <hostedReviewer.login>` when `star.json`'s `hostedReviewer` is set.
It prints one line. `PASS` needs all of: the PR is open, not a draft, and its head is the head given;
a comment by the PR's author that starts `Codex gate: PASS (head <that head>`; every check that
reported is green, and GitHub's merge state is not blocked, behind or dirty; a reply from the PR's
author on every unresolved review thread someone else opened (the fix, or a `Disposition:` with the
reason); and, without a hosted reviewer, an approving review on this head by someone other than
the PR's author, with nobody's latest review asking for changes. With a hosted reviewer the gate
reads none of its review: the babysit worker judged it clean on this exact head, from guidelines,
before it reported `READY` (`juel:babysit-pr`), and the head check holds the gate to that head.

**One merge per base at a time** (#75, #93). `merge.sh` runs in the background, so two `PASS` rows
on one base would race, and GitHub would refuse the second as behind. Take the `verifying` rows
base by base (each brief's `baseBranch`): while a `merge.sh` for a base is still running, no other
row on that base starts one, and it waits for that line. Among the rows on one base whose gate
prints `PASS` in a tick, merge first a row with no hosted pass left
(`grep -c ' pass ' HOME_DIR/reviews/<project>/<item>-hosted.log` prints `hostedReviewer.maxPasses`
or more: it cannot take another review run, so it must not be the one left behind), then the oldest
`updated`. When `merge.sh` prints `MERGED`, run the merge gate at once, in the same tick, for every other `verifying` row on that base: a
`PENDING merge state: behind the base branch` or `FAIL conflicts` there goes to the sync rule now
("Sync after the base moved"), so its babysit run merges the new base in before any later pass.

| Verdict | Then |
|---|---|
| `PASS …` | First close the row's open `held` item "PR #<n> waits for an approval from someone other than you" when it has one. The brief has a grant (`grep -cE '^grant: [^ #]' <brief>` prints 1): `sh S/merge.sh <pr url> --head <head> --grant <grant path> --home HOME_DIR --item <item> [--quiet-hours <window>]` (the window as `stage-start.sh` renders it; none when `quietHours` is null), run in the background like `stage-start.sh`; its line is the next table. No grant (a brief whose grant line was lost, since every go writes one): queue `--kind go-merge` and leave the row |
| no line, or an exit that is not 0 | as `PENDING script gave no verdict` |
| `PENDING <what>` | `PENDING approval: …`: queue `--kind held` "PR #<n> waits for an approval from someone other than you" (GitHub never lets a PR's author approve their own PR), notify, and put `retry=<now + 10 min>` in `verify`: the gate runs again after that; it is not a `pending=`. `PENDING merge state: behind the base branch`: the sync rule below. `PENDING hosted-status <check> missing on <sha>`: the hosted reviewer has no status on this head, most often after a base sync that came after its last pass. When the brief's `## Decisions` has no line "the merge gate said: no <check> status on <sha7>" yet: append "- <date> the merge gate said: no <check> status on <sha7>; refresh the hosted status on <sha7>", row → `babysit-queued` (babysit resumes with `--since <cursor>`; its Phase 1 asks the hosted reviewer for a status refresh, which is not a pass, unless `refreshOutsideCap` is false: then babysit escalates `reason=hosted-cap`, which the owner answers); it is not a `pending=`. When that line is there already, the refresh did not help: the Otherwise branch. Otherwise: `counters` has no `pending=1`: write it, put `retry=<now + 2 min>` in `verify`, and check again in a later tick. It has: → `escalated`, queue `--kind escalation` "<what> still pending" |
| `MOVED <head>` | `counters` has no `moved=1`: write it (its own budget, separate from `restarts` and from `pending=`, and never overwritten by them), row → `babysit-queued`. It has: → `escalated`, queue `--kind escalation` "head keeps moving" |
| `MERGED <sha>` | the PR is merged (by STAR's own earlier call, or by someone else): `sh S/release-record.sh --home HOME_DIR --project <p> --item <i> --pr <url>`; row → `done`; print the record's path |
| `FAIL <what>` | `FAIL closed`: as the PR check's `FAIL closed` ("Fill slots"): row → `escalated`, queue `--kind escalation` "PR was closed without a merge". `FAIL conflicts`: the sync rule below. `FAIL no codex PASS for <sha7>`: append "- <date> the merge gate said: no codex PASS for <sha7>; resume the gate loop on the existing PR" to the brief's `## Decisions`, row → `queued` (the build resumes the gate loop, as for `reason=no-safe-verdict`); it spends no `mergefail=`. Otherwise: `counters` has no `mergefail=1`: write it, append "- <date> the merge gate said: <what>. Fix it on the PR." to the brief's `## Decisions`, row → `babysit-queued` (babysit resumes with `--since <cursor>`). It has: → `escalated`, queue `--kind escalation` "the merge gate failed twice: <what>" |

`merge.sh` prints one line:

| Line | Then |
|---|---|
| `MERGED <sha>` | as the verdict `MERGED`, then print it and push one notification, "merged <item>: PR #<n>". Then run the merge gate for the other `verifying` rows on that base in this same tick ("One merge per base at a time") |
| `HELD quiet hours` | put `retry=<now + 10 min>` in `verify`: the gate runs again after that, and merges at the first run outside quiet hours |
| `FAIL head moved` | as the verdict `MOVED` |
| `FAIL live worker <dispatch>` | the row is in a worker stage, so its worker may still push to the PR (#80): fence it ("A merge on a PR a worker is still working on", below), then run the gate again |
| `FAIL ledger: <why>` | `merge.sh` found no ledger row for the item it was given: nothing on the PR is wrong, so no `mergefail=` and no babysit round: queue `--kind held` "merge.sh could not merge PR #<n>: <the line>" and put `retry=<now + 10 min>` in `verify`; the gate and `merge.sh` run again after that |
| `FAIL grant: …`, `FAIL merge methods: …` or `FAIL comment: …` | nothing on the PR is wrong, so no `mergefail=` and no babysit round: queue `--kind held` "merge.sh could not merge PR #<n>: <the line>" and put `retry=<now + 10 min>` in `verify`; the gate and `merge.sh` run again after that |
| `FAIL merge: …` | as the Otherwise branch of a merge-gate `FAIL <what>` (the `mergefail=` budget) |
| exit 64 | `merge.sh` refused its arguments (a head that is not 40 hex characters, a URL that is not a PR, or missing arguments): queue `--kind held` "merge.sh refused its arguments for PR #<n>" and file an improvement issue; the row stays as it is |
| no line, or another exit that is not 0 | the merge may or may not have happened: change nothing; the next tick's gate prints `MERGED` when it did |

Any verdict other than `PENDING` clears `pending=`; `PASS` clears `moved=` too. STAR merges only
here: through `merge.sh`, on the exact head the gate passed, under the item's grant, never inside
quiet hours. `merge.sh` posts the owner's go on the PR first (`Merging head <sha> under your go of
<date>: "<their words>"`) and merges with `--match-head-commit`, so a head that moved after the gate
is GitHub's refusal, never a merge. STAR never marks a PR ready: the build does after its final SAFE round, or babysit when quiet hours held the build's.

**A merge on a PR a worker is still working on** (#80). When the owner orders a merge ("merge it
now", "ship it at this head") on a row in `building` or `babysitting`, its worker may push at any
moment, so a merge, and any reply STAR or a worker posts for it, races that push. Fence it first:

1. Stop the worker: append `<dispatch> stopped <iso>` to `processed.log`, then `worker-stop`,
   `worker-release` and the gone check ("A stopped worker is gone").
2. Read the head again: `sh S/pr-verify.sh <pr url> --head <the row's head> --merge-gate`.
   `MOVED <new head>` means the worker pushed before it stopped: `head=<new head>`. Any other line:
   the head is the row's.
3. Append "- <date> the owner ordered a merge at <head7>: <their words>. Reply on each review
   thread the order settles (a `Disposition:` that quotes it), push nothing the order does not ask
   for, and report READY." to the brief's `## Decisions`, and the row → `babysit-queued` (babysit
   resumes with `--since <cursor>`). That fresh babysit run is then the only writer on the PR: it
   replies, reports `READY` on the head, and the merge gate merges it as it does any row.

The order never skips a gate: the merge gate still checks that exact head as for every
`verifying` row.

**`gh` that cannot see the repository.** `PENDING gh cannot see <repo>: export GH_TOKEN for this
repository` is not retried blind and does not count as a `pending=`: queue `--kind held`
"gh cannot see <repo>: set tokenCmd in star.json to a command that prints a token for it, restart STAR's session, then answer done" once,
and leave the row as it is. A token exported in a shell never reaches Orca's workers; `tokenCmd`
reaches every session that starts after it is set (#91). The next check runs after that item is
answered. A worker's escalation that says so goes through the `ESCALATION` row of the report table
as usual, and the stage that runs again on its answer starts with the token.

**Sync after the base moved.** `FAIL conflicts` or `PENDING merge state: behind the base branch`
for a `verifying` row means the base branch moved since babysit last merged it in,
most often because STAR merged a sibling PR. Read the base's head:
`git -C <project.repo> ls-remote <project.remote> refs/heads/<the brief's baseBranch>`, its first
7 characters. When the row's `counters.synced` is not that sha: write `counters.synced=<sha7>` and `counters.pending=-`, and the row → `babysit-queued`
(babysit resumes with `--since <cursor>`; its Phase 4 merges the base in and resolves mechanical
conflicts itself). When it is: syncing did not help: → `escalated`, queue `--kind escalation`
"<what> again after syncing with <base> at <sha7>". `ls-remote` failing: the Otherwise branch of the cell that sent it here.

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

## The host gate

`stage-start.sh` checks the machine before every start, against `star.json`'s `hostGate`:
`minFreeGB`, `maxAgents`, `maxSwapGB` and `minDiskGB`. Memory is free + inactive from `vm_stat` (on
Linux the `available` column of `free -g`); agents are the running `claude` and `codex` processes,
every project's; swap is the `used` figure of `sysctl -n vm.swapusage` (on Linux, `free -g`); disk
is the free space on the volume that holds STAR's folder. The first limit that fails prints
`hold <what> <value>` and starts nothing ("Fill slots" says what follows: `hold=` counts the ticks,
and at `hold=3` the queue gets one held item until a start succeeds). Heavy test and build gates
inside workers take turns through `juel:ship-ticket`'s `gate-lock.sh`, which uses one lock per user
for the whole machine (`/tmp/juel.gate.<uid>.lock`), so workers in different projects wait for each
other too, and no worker needs to be told where STAR's home is.
Waiters are served in strict arrival order with one slot (the default), one gate at a time (#97);
with more slots (the slots file says up to 4), the first waiters in the queue race for a freed slot.
STAR never raises the slots unasked: heavy runs side by side can take the machine down.
The owner may ask for `sh S/../ship-ticket/gate-lock.sh --slots 2` once free memory allows it.
`caffeinate` is a macOS tool; on Linux skip it.

## Looking after the workers

STAR is the most capable session in the run and the only one that sees every item. A worker that
is unsure asks STAR; a worker that makes no progress hears from STAR. Workers are told both in their
own skills.

**STAR answers first.** A worker's question (`orca orchestration ask`) is STAR's to answer when
the answer is in the brief, its `## Decisions` or `## Feedback`, the memory notes or the ledger;
when it is an engineering call inside the brief's Scope: which of two approaches, what to name
something, whether to retry, how to get past a tool that fails, what this project's convention
is; and when it is a product call inside the brief's Scope. Answer in a few lines, say what to do
next, and where it helps say what to read and what to decide by: STAR still opens no code, review
or log file itself, and does no research in its own session.

**Product calls are STAR's.** A product call inside the brief's Scope is decided by STAR whether
the user is there or not, from the sourced options the worker brings: pick the one that best fits
the brief's intent and its decision records, reply, and append a decision record to the brief's
`## Decisions`: `### D<n> <title> (<date>, decided by STAR)`, with the worker's source in `Source:`
and the message id in `Context:`. A question that brings no sourced options gets the reply
"Bring sourced options: <what to look up>, each with its source." and no decision.

**An accepted residual.** A build worker whose live check for one criterion still fails after its
loop, with a residual the item cannot close (`juel:ship-ticket` Phase 6), asks whether the
criterion may be accepted with that residual. It is STAR's to accept when the worker's evidence
shows the criterion's intent met and the residual can be an item of its own; when the residual is
most of the criterion, or touches a risky call, the question is the user's: ask it in chat, and
on the user's yes take the same steps, with `decided by the owner` in the record. To accept: write the
follow-up spec item `<HOME_DIR>/items/<project>/<item>-residual-<k>.md` (frontmatter
`status: todo` and `title:`, then the residual and the criterion it comes from), add it as an
`inbox` row (its `ref` the path, `counters.batch` the item's, `counters.parent=<item>`), append
`### D<n> Accept a residual on <criterion> (<date>, decided by STAR)` to the brief's `## Decisions`
with that path in `Consequences:`, and reply with the path. The worker's `DONE` then carries
`NOTE: accepted residual <criterion>: <follow-up path>`.

A question is the user's, and goes to the queue, when it would change or stretch the Scope or an
acceptance criterion; needs a secret, an account or a paid service; is about anything that goes out
to other people beyond the PR itself; or would delete or overwrite work. Inside quiet hours or while
the user is away, such a question is answered "No answer from the user: escalate this." at once (the
Messages table).

**One open question per row.** A worker that asks again while its earlier question is still in
the queue has moved on: close the old item and reply to its message "Superseded by your newer
question." before queueing the new one, so the worker is never blocked on a stale ask. A worker
may end its question with `deadline=<minutes>` (at most 240); asks that need the user's hands at
the Mac use 60. At the deadline STAR reminds once (Housekeeping) before it gives up.

Every answer STAR gives is on record: append `- <date> STAR answered (<message id>): <question> → <answer>` to
the brief's `## Decisions` (later workers read it as binding, and the user can overrule it there
or in chat), and name it in the next status line. So is every rule STAR sends a worker unasked (a
gate policy, how to write progress lines, any instruction it must keep following): append
`- <date> STAR to the <stage> worker (<subject>): <body>` to the brief's `## Decisions` before the
`send` (#99). A one-time nudge (`act`, the check-in, the report-shape re-send) is not a rule.

**Checking in.** Each tick, Housekeeping runs `step-check.sh` for every worker the probe found
running (`ok`, `quiet …` or `stale …`). It reads the worker's activity (progress lines, commits
and changed files in its worktree), the step its last progress line names (the line's second
field: `phase<N>`, `executor`, `live-check`, `regression-gate`, `gate-r<k>`, `post-pass`,
`wait-hosted`, `wait-ci`, `sync`, `report`, or the step a build writes once it has marked the PR
ready), that step's own evidence (a gate round's run file,
whether its pids are alive, the age of its log, a verdict already on disk) and, for a row with a
PR, the PR itself through `pr-state.sh` (draft or ready, its merge state, its checks, the hosted
reviewer's status on the head). It reads none of that into STAR's context and prints one line:

| Line | Then |
|---|---|
| `ok <step>` | the step is moving, even when the progress log is old (a gate round whose log still grows): clear `asked=`, `step=` and `nudge=` |
| `note <step> <diagnosis>` | name it in the status line (`<item>: <diagnosis>`), for example "checks green, no hosted run on abc1234". `note <step> instructed <m> min ago` means STAR's last instruction is less than 15 minutes old: send nothing, and name it the same way |
| `act <step> <diagnosis> -- <instruction>` | split the line on its first ` -- `: the diagnosis is before it, the instruction after it. Send the instruction: `orca terminal send --terminal <terminal> --text "<instruction>" --enter --json` when this tick's probe printed a terminal (`quiet` or `stale`), else `orca orchestration send --to dispatch:<dispatch> --subject "STAR" --body "<instruction>" --json`. Then `counters.asked=<now>`, `counters.step=<step>` and `counters.nudge=+1`. An `act` for a step other than `counters.step` starts over at `nudge=1`. `step-check.sh` spaces these out: within 15 minutes of an instruction it prints `note … instructed <m> min ago` instead |
| `restart <step> <diagnosis>` | the restart rule below, at once: the evidence is plain (the gate's process is gone while the worker still waits, or a verdict or a green status sat unread after an instruction) |
| `unknown <why>` | STAR cannot read a step (`no-progress-source`: the worker has written no progress line yet). A probe that printed `quiet <minutes> <terminal>` gets the plain check-in below; anything else, nothing |

Pass `--asked <counters.asked>` whenever it is set: `step-check.sh` itself ignores one older than
the worker's newest activity.

The plain check-in is for a worker with no step to read whose terminal has printed nothing for
15 minutes. Unless the row has an open `question` item (then it is waiting for an answer, which is
expected), send it one message and set `asked=` and `nudge=` as for `act`:

```sh
orca terminal send --terminal <terminal> --text "STAR checking in on <item>: say in one line where you are. Waiting on a background command: keep waiting. Blocked or unsure: ask me with orca orchestration ask. Finished: send your worker_done report now." --enter --json
```

**The restart rule.** It runs on a `restart` line; on `nudge=2` with `asked` 15 minutes or more ago
and this tick's line `act` again for the step in `counters.step` (the second instruction was
ignored); and, for a worker with no step to read, on `nudge=2` with `asked` 15 minutes or more ago
and the probe still `quiet`. "Once per stage" is the ledger's `restarts` column, the same one the
reconcile step uses for a lost worker: a stage gets one automatic restart in all.

1. The row's `restarts` is already 1 (its stage was restarted once, by this rule or by the
   reconcile step): queue `--kind held` "<stage> worker for <item>
   stalled again at <step> after a restart: <diagnosis>", notify, and send it nothing more while
   that item is open. The worker is not stopped.
2. A `building` row whose worktree has uncommitted changes (`git -C <worktree> status --porcelain`
   prints anything) is not restarted: queue `--kind held` "<item>'s build is stuck at <step>
   with uncommitted work in <worktree>", notify, and send it nothing more while that item is open.
3. Otherwise restart it. Append `<dispatch> stopped <iso>` to `processed.log`, then
   `orca orchestration worker-stop --dispatch <id> --json`, `worker-release` and the gone check ("A stopped worker is gone"). Then
   `sh S/ledger.sh set <item> state=<its stage's waiting state> restarts=1 counters.nudge=- counters.asked=- counters.step=-`
   (`inbox`, `queued`, `babysit-queued` or `post-queued`; the round stays as it is, and babysit
   resumes with `--since <cursor>`). Append "- <date> STAR restarted the <stage> worker at
   <step>: <diagnosis>. Resume on the existing branch and PR." to the brief's `## Decisions` when
   the brief exists, and say "restarted <item> at <step>" in the status line. "Fill slots" starts
   it again.

**A refused check-in.** `orca terminal send` answering with the error code `agent_prompt_blocked`
means the worker's agent is mid-turn: busy, not idle, often inside a long command such as a wait
for the gate lock. It is not a nudge: add one to `busy=` in `counters` and leave `nudge=` alone.
An instruction sent with `orca terminal send` is a check-in for this rule, so a refused one sets
none of `asked=`, `step=` and `nudge=`: nothing reached the worker, and only `busy=` moves.
While `busy=<n>` is set, send the next check-in only when this tick's probe prints `quiet <m>` or
`stale <m>` with `m` at least the probe's own threshold × (n + 1) (15 for `quiet`,
`progressDeadlineMin` for `stale`), so one silent stretch gets one try per window. When `busy=` is
set and the probe's minutes reach 120, queue `--kind held`
"<stage> worker for <item> silent and busy for 2 h: look at terminal <terminal>", notify, and send it
no more check-ins; the worker is not stopped. Any probe result other than `quiet` or `stale` clears `busy=`: the worker moved, so that
silent stretch is over.

The probe never says `quiet` or `stale` while a question with numbered options is on the worker's
screen (that is `stuck: confirmation dialog`, or `prompt bounded` for the one prompt STAR answers),
because the check-in ends with Enter and Enter would answer the prompt. It reads the rendered
screen (`orca terminal read --screen`), not Orca's transcript, which shows no prompt (#114). Send a
check-in or an instruction only on this tick's probe and `step-check.sh`
lines, never from memory of an earlier one.

A blocking screen is a different thing (`stuck:`): that worker is stopped and the row goes to the
user, and STAR never answers a worker's screen for it, with one exception (#114): `prompt bounded`,
Claude Code's safety prompt for an `rm` or `rmdir` whose every operand `worker-probe.sh` found
inside the item's worktree or a session scratchpad, gets the digit `1` (Housekeeping). A model at
capacity is a third thing
(`stalled:`): STAR nudges it to retry, three times at most, then restarts it (the capacity rule in
Housekeeping).

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

A merge is announced as it happens: STAR prints it and sends one push notification,
"merged <item>: PR #<n>".

Workers get the quiet window (`--quiet-hours`) and decide at each outward action: they keep
building, gating and pushing, while marking ready, replying to reviewers, re-requesting review,
`@greptileai` comments and status writes wait for the window to end or come back as `HELD` lines.
STAR's own merge waits the same way: `merge.sh` prints `HELD quiet hours`.

## Report items

A brief with `deliverable: report` (a QA run, an impact map, a PR assessment, a status) ships a
report, not a PR. Its build stage is the same `ship-ticket` command: `ship-ticket` reads the
field, skips the code phases, runs every check, writes the report to
`HOME_DIR/reports/<project>/<item>.md` and reports `REPORTED item=… path=…`, with no commit, push
or PR. Then:

1. `REPORTED` → `reported`, and the queue asks "accept report for <item>" with the report's path.
   STAR never opens the report; the user reads it.
2. `accept` → `post-queued`. Posting is outward, so it waits for the first tick outside quiet
   hours. A post worker posts the report as one comment on the work item and
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
| `babysit-queued`, `babysitting`, `verifying` | In Review |
| `done` | Done |
| `inbox`, `briefing`, `brief-ready`, `escalated`, `failed`, `dropped` | not written |

At the end of every tick outside quiet hours, compare each row's status with its
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

## The batch summary and go

A batch is the items one request brought in: a start with refs or text, refs said in chat, or one
inbox file (`counters.batch`). The owner is asked once per batch, while they are there, and the
batch then runs without them.

1. When no row of the batch is `inbox` or `briefing` any more, print the summary in one chat
   message, for the rows of the batch that are `brief-ready`, `escalated` or `failed`. STAR reads
   only these lines of each brief, with `sed -n`, never the whole file: the frontmatter's
   `item.title`, `blockedBy`, `notBefore` and `deliverable`, and the lines under `## Acceptance criteria`,
   `## Approach` and `## Person-only steps`, with the `### D<n>` headings under `## Decisions`.

   ```
   Batch B-20261009T081200Z-a3f9 · 3 items

   ITEM-1 · Export reports as CSV
     Criteria (4): one line each
     Approach: one line
     Decisions STAR took (2): D1 CSV over XLSX · D2 a 10,000-row cap
     Blocked by: none
   ITEM-2 · ...
     Not before: 2026-10-15
     Person-only: sign in to <app> as <account> (2FA)
   ITEM-3 · stopped: <the escalation or failure, one line>

   Reply go, go except <items>, drop <item>, or tell me what to change.
   ```

   A `Not before:` line appears only for a brief that has `notBefore`.
   The `go-batch` item carries the same choice. The decision records are where the owner
   overrules STAR: an answer that names one is feedback for that brief.
2. Between ticks, never inside one: ask each open `person` item of the batch in plain chat,
   one person-only step per message, then end the turn; the go is the last question. Never with
   AskUserQuestion: workers are running, and an Orca nudge that lands on an open picker answers it
   with its first option.

   ```
   Q2 of 3 · ITEM-2 · screen
   Sign in to <app> as <account> on this Mac (2FA).
   1. done
   2. can't now
   ```

   A `risky` step's options are `1. approve` and `2. no`. A `(value)` step's only numbered option is
   `1. can't now`, followed by "Or tell me the value." A worker's `question` that reaches the
   owner lists the options the worker brought, STAR's pick first, labelled `(Recommended)`. An
   `escalation`'s option is `1. drop`, followed by "Or tell me your decision." A queue option that
   asks for words is never numbered: it becomes that closing "Or tell me" line.

   The reply: a bare number, or the text of one option, is that option; any other words are the
   answer in words.
   On a question with numbered options, a bare number that names no option is not an answer:
   print the question again. Record the answer with
   `loops.sh set-answer <id> "<the option's text, or the words>"` and run the Answers step for it at
   once, so STAR stays the only writer of briefs and rows, then ask the next question. A message
   that is Orca's nudge (it starts with "You have" and names orchestration messages), exactly
   `inbox`, a message that starts with `STAR heartbeat:`, or one whose whole text is one of STAR's
   own control phrases (`stop`, `away` or "I'm leaving", `back` or "I'm back", `take over`)
   is never an answer: handle the nudge, `inbox` and the heartbeat as usual, and run a control
   phrase as the command it is, then print the open question again as
   `Still open: Q2 · ITEM-2 · <question>` with its options. While a question is open, each wake
   (the reply, a nudge, the heartbeat) runs one tick, then STAR prints the open question (or the
   next one) and ends the turn.
3. A go given before every step is answered starts the items whose steps are done; the others stay
   `brief-ready` and come back in the next summary, with what each waits for.

**Feedback while a brief drafts** (#112). Feedback the owner gives on a row that is still
`briefing`, in chat or as an answer for it, never goes into the brief, which its worker may be
writing, and is never sent to the worker. STAR appends it to the brief's feedback side file,
`<the brief path>.feedback.md` (`HOME_DIR/briefs/<project>/<item>.md.feedback.md`), one line per
entry: `- <YYYY-MM-DD HH:MM> <the words, line breaks folded to spaces>`. STAR is its only writer.
The brief worker copies it under the brief's `## Feedback` right before it writes (draft-brief
steps 1 and 6). When the row's report arrives, STAR settles the side file before the report's row
in Messages:

- `BRIEF`: append under the brief's `## Feedback` each side-file line the brief lacks
  (`grep -cxF '<line>' <brief>` prints 0), then delete the side file. When any line was missing,
  the brief was written without it: after the `BRIEF` row's own action, handle those lines as a
  `go-batch` "anything else" answer for that row, which they already are under `## Feedback` (a
  small edit STAR makes itself, or row → `inbox` and the brief stage runs again with `--feedback`).
- `ESCALATION`: put the lines under the brief file's `## Feedback`, creating the file with only that
  section when the worker wrote no brief, then delete the side file. The brief stage that runs
  again reads them there.
- `SPLIT`: put the lines under `## Feedback` in each new row's brief file, creating each with only
  that section, then delete the side file.

A row that leaves `briefing` any other way (lost, `failed`) keeps the side file: its next brief run
reads it.

Refs handed over from another session: STAR's own session prints the summary, and the handing
session says "answer STAR's batch summary in <terminal>".

A step the owner could not do (`can't now`) holds only its own item. Nothing else waits for the
owner: STAR takes the product calls, and the build checks what it can by itself.

## Handoff

The handoff is how the user leaves and comes back without losing anything. `handoff.md` only lists:
the queue stays the one place to answer, so an answer can never exist in two files.

**Away holds no work.** Every stage keeps starting while the user is away, babysitting included,
and STAR keeps merging under the owner's go. Quiet hours, not away, hold what goes out: marking
ready, replies, reviewer pings, status writes and merges, in workers and in STAR's own merge.

**Away** (`/juel:star away`, "I'm leaving", or a `control: away` inbox file). Away while already
away changes nothing: `handoff.sh start` keeps the file and its summaries and says so.

1. Finish the current tick. When a batch summary still has open questions, ask them once more
   ("The batch summary and go"); a person-only step left unanswered holds only its own item, which
   stays `brief-ready`.
2. `sh S/handoff.sh --home HOME_DIR start` writes `handoff.md` and marks `away` in `star.json`. Its
   three parts come straight from the files: **A. Needs you now** (queue items that block work: a
   batch's go, person-only steps, merge questions, worker questions, escalations, restarts),
   **B. Waits for you** (drafts, held actions, an approval a PR waits for), **C. What runs while
   you're away** (each open item and where it will stop).
3. Print part A: what is still open, and that those items stop where they need the answer.
   Answers that arrive later are handled like any other.

**While away:**

- A worker's question that is not STAR's to answer ("Looking after the workers") is answered "No
  answer from the user: escalate this." at once.
- Only `escalation` items notify, as inside quiet hours.
- About every 4 hours (housekeeping's `handoff.sh due`), `handoff.sh summary` adds a dated summary
  to the top of `handoff.md`: items per state, PRs waiting to merge, what merged, what stopped,
  everything in `sent.log` since the last summary, free memory and running workers, and the full
  Needs-you list again. The heartbeat keeps this going while STAR is idle. It needs STAR's session
  to be open: with the session closed, workers continue but no summary is written.

**Back** (`/juel:star back`, "I'm back", or a `control: back` inbox file):

1. `sh S/handoff.sh --home HOME_DIR end` clears `away` and prints the latest summary. Print it, then
   the open queue (`loops.sh list`). When it prints `not away`, say so and print only the queue.
2. Send the notifications that were held, then run a tick.
3. As the user answers, in the file or in chat, record each answer and act on it in the same turn.

## Recovery

- **Compaction:** the plugin's session hook tells the session that owns STAR for this project
  (the terminal named in `star.json`) that it is the coordinator and to run `/juel:star` if it is
  not in a tick. Other sessions in the same repository hear nothing. Nothing is needed from the
  user.
- **A closed session:** workers keep running and their reports wait in the Orca run. The user
  runs `/juel:star` in the project again, from any Orca terminal: the old terminal is no longer
  listed, so the new session takes over.
- **An Orca restart:** every worker is gone. The reconcile step restarts brief, babysit and post
  stages once and queues lost builds for the user.
- **A stop in the middle of a tick:** nothing is lost and nothing runs twice. A message not yet in
  `processed.log` is replayed into the same end state (the order of effects above); a row written
  before its `task-create` goes back to its waiting state; an inbox file read twice adds no row.
- **A v1 STAR folder:** the start's first step, `star-home.sh migrate`, brings it to schema 2. It
  keeps `star.json.v1.bak` and `ledger.md.v1.bak`, moves each row out of a removed state with a
  decision record in its brief, and prints the workers of the removed stages, which STAR stops and
  releases before it reconciles.

## Hard rules

- **Merge only through `merge.sh`**, on the exact head `pr-verify.sh --merge-gate` passed, under
  the item's grant, outside quiet hours. No worker merges.
- Never read review, evidence, log or diff content into this session. One line per fact, from a
  script or a report.
- On Claude Code 2.1.287 and later, juel's mod refuses a direct `gh pr merge` in the coordinator and in STAR's workers, and refuses reading review, evidence, report or log files into the coordinator; on any other agent or build these rules hold as written.
- An item is never built before the owner's go for its batch, or, for a re-scope's follow-up, its
  parent's grant. A go is never inferred.
- Product calls are STAR's, decided from sourced options and kept as decision records the owner
  can overrule.
- A `failed` or `escalated` row is never re-run without the user's answer, except the single
  automatic restart of a stage: a brief, babysit or post worker that was lost or stalled at
  capacity, or any worker `step-check.sh` found stuck ("Checking in"; a build only with a clean
  worktree).
- Workers are started only through `orca orchestration worker-start`, and only by "Fill slots".
- One STAR per home, one worker per row, one row per worktree.
- The work item's status is written only by STAR, from the row's state ("The tracker status").
- Never put a project's details in an improvement issue: placeholders only, and `star-issue.sh`
  refuses the rest.
- AskUserQuestion only for the first-run setup question, before any worker exists. Every other
  question is asked in plain chat, one question per message.
- A worktree is removed only by `worktree-clean.sh`, never with work in it that exists nowhere
  else, and only after its evidence is copied into `HOME_DIR/evidence/<item>/`.
- `open-loops.md` is written only through `loops.sh`, and `ledger.md` only through `ledger.sh`.

## Common mistakes

| Mistake | Fix |
|---|---|
| Opening a review file "to summarize it" | `done-check.sh` and the merge gate read it and print one line |
| A worker moving the tracker status | Workers never write it; STAR follows the row's state |
| Pasting ticket text or a project name into an improvement issue | Placeholders only; `star-issue.sh` refuses project details |
| Opening a report "to check it" before asking for the accept | The queue item carries the path; the user reads it |
| Editing `open-loops.md` with Edit or sed | `loops.sh` only: it keeps what the user typed |
| Merging with `gh pr merge` by hand | `merge.sh` only: it quotes the go, waits out quiet hours and passes `--match-head-commit` |
| Asking the owner a product call | Decide it from the worker's sourced options and record it as a decision record |
| Starting a build before its batch's go | Only a `go-batch` answer, or a parent's grant, stamps `approved:` |
| Starting a worker by hand | `stage-start.sh`: it sets up the branch, the env files and the trust dialogs before any agent starts |
| Ticking forever with nothing to do | When every row waits on the user or is finished, go idle and end the turn |
| Batching ledger writes to the end of a tick | Write after every message, before `processed.log` and the ack |
| Answering a worker's TUI prompt | `worker-probe.sh` says stuck → stop it, fail the row, queue it. The one exception is `prompt bounded` (#114): the digit `1`, never Enter |
| Restarting a worker because a probe came back empty or `unknown` | Only `gone` means lost. `unknown` three ticks in a row goes to the user |
| Sending a stuck worker the same "where are you" again and again | `step-check.sh` names the step and the instruction; two ignored instructions restart the stage once |
| Picking a row for a message by its `item=` name | By dispatch id; the name only confirms it |
| Writing a note or a count into `updated` | `updated` is a time. Counts go in `counters` |
| Working out the quiet window in your head | `quiet-hours.sh` says `inside` or `outside` |
| Working out the STAR folder's path yourself | `star-home.sh path` prints it; `init` creates it |
| Writing a ledger row by hand, or building a `set` line by splitting a string | `ledger.sh`, one quoted argument per field |
| Parsing `orca orchestration check` yourself | `messages.sh`: it drops heartbeats, replays and processed messages |
| Putting a line break in a task spec | `stage-start.sh` writes long prompts to a file and sends one line |
| Starting a brief in a build slot | Briefs have their own pool, `maxBriefs`; build slots are for building |
| Asking the user with AskUserQuestion while workers run | Plain chat, one question per message: an Orca nudge answers an open picker with its first option |

## Edge cases

| Situation | Handling |
|---|---|
| Refs given while STAR is stopped | The invoking session becomes the coordinator and ingests them |
| The same ref given twice | One row. The second time changes nothing |
| The user merges or closes a PR before STAR merged it | The PR check before "Fill slots" sees it in every state that has a PR, stopped rows included: merged → release record and `done`; closed → `escalated` |
| The user says "drop" while the item's worker is running | The worker is stopped and released first, then the row → `dropped` |
| The owner gives feedback while an item's brief is drafting | STAR writes it to the brief's feedback side file, never to the brief; the worker copies it in right before writing, and the `BRIEF` row adds any line it missed (#112) |
| The owner orders a merge while the item's worker is still fixing the PR | The worker is stopped and its terminal checked first, the head is read again, and a fresh babysit run replies and reports `READY`; `merge.sh` refuses a row in a worker stage (`FAIL live worker`) |
| A stopped worker's terminal is still open when its stage starts again | `stage-start.sh` stops a gate the item's earlier session left holding the lock, and closes the terminal when Orca shows the stopped dispatch owns it. A terminal Orca cannot place holds the row while it still prints, and is left open once it has been quiet for 10 minutes |
| A second `/juel:star` in another terminal of the same project | It hands its refs to the running STAR and ends; it never becomes a second coordinator |
| `loops.sh` exits 3 (conflict markers in `open-loops.md`) | Stop writing the queue, tell the user to resolve the file, keep workers running |
| The project is not registered with Orca | `--kind held` "register this repo with Orca: orca repo add"; inbox files stay until it is |
| `codex` missing | STAR does not start: the executor and the gate need it (Preflight) |
| A stage's model is refused at launch (no access, no credits) | The stage falls back to `worker` once and the queue says which model ran |
| `/juel:star` typed in a linked worktree or a subfolder | The same folder as the main checkout: one STAR per project |
| `/juel:star` typed outside a git repository | One line: STAR needs a project repository. Nothing is created |
| A ticket that only asks for a QA run or a write-up | `deliverable: report`: a report the user accepts, posted by a post worker; no PR |
| The tracker cannot be reached from STAR's session | One held item per status move; the user answers done once they moved it |
| A finding that is already an open issue | `star-issue.sh comment` adds the new evidence to it |
| A finished item's worktree still holds uncommitted or unpushed work | It stays; the queue says why, and `done` there makes STAR try again |
| The STAR folder was deleted | That project's state is gone; the next `/juel:star` starts fresh. Stop STAR first: workers still running would report to nobody |
| Two projects each run a STAR | Each has its own queue and its own 4 + 3 + 3 slots; the gate lock (strict arrival order with one slot, the default; with more slots the first waiters race for a freed slot) and the host gate are shared by the machine |
| A worker asks again while its first question is still open | The old item is closed and its message answered "Superseded by your newer question." |
| The user leaves with person-only steps unanswered | Those items stay `brief-ready`; the rest of the batch builds and merges |
| A person-only step needs a value from the owner (a host name, an id) | `(value)` on the step: the answer is recorded under `## Decisions` as `→ value: <answer>`, and the step is done |
| An item that may only be built after a date | `notBefore` in its brief: the row stays `queued`, and the status line says `<item> waits until <date>` until then |
| A check turns out to need a person in the middle of a build | The build escalates `needs-human-input`: the brief missed a person-only step |
| An Orca nudge whose batch holds only heartbeats | `messages.sh` acknowledges it; nothing happens |
| The codex gate errors twice | The build escalates `review-unavailable`, quoting the gate's `ERROR` line |
| The base moves under a gate loop and changes the branch's own files | The round prints `ERROR base-moved`: the worker merges the base in, runs the sweep and runs the same round again; it is not an error, and STAR does nothing (#113) |
| The review gate is down on every model (`ERROR gate-down`) | STAR parks each build and babysit that reports it, starts no new ones, asks the owner once, and checks the gate every 30 minutes until it is back |
| A worktree Orca created inside the repository | `.git/info/exclude` gets a line for its top folder |
| A new worktree Claude Code has never trusted | `stage-start.sh` clears the dialogs; only when it cannot does the queue ask |
| STAR stopped between `task-create` and recording the task | The next start replays the same request ids and gets the same task back |
| A check-in Orca refuses with `agent_prompt_blocked` | The worker is busy, not idle: `busy=` counts it, not `nudge=`, and the next try waits a full quiet window |
| A gate round that prints nothing for 20 minutes | `step-check.sh` says `act`: STAR tells the worker to stop it and run the round again; ignored twice, the stage restarts once |
| A worker still polling for a review that already passed on its head | `step-check.sh` reads the PR: an instruction to judge it and report `READY`, then a restart if that is ignored |
| Two items that each add a decision to the same register | Each worker reserves its ids through `ids.sh`, so siblings never take the same number |
| An Orca nudge, the heartbeat or one of STAR's control phrases arrives while a question is open in chat | It is handled as what it is (a control phrase runs as its command), never as the answer; the question is printed again |
| A build still NOT-SAFE after 3 rounds | `RESCOPE`: the brief is narrowed once and the rest becomes a follow-up item under the same go; a second re-scope escalates |
| A project with no hosted reviewer | The merge gate waits for an approval from someone other than the PR's author; the queue says so once |
| A v1 STAR folder | The first start migrates it and stops the workers of the removed review, fix and screen stages |
