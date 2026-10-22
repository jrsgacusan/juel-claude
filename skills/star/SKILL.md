---
name: star
description: Use to run STAR, a local coordinator that ships a project's work to merged PRs without asking the owner. Type "/juel:star <brief>" in the project, where the brief is free text, work-item refs, or both - the session becomes the coordinator, or hands the brief to the one running; its state lives in the project, git-ignored, under docs/superpowers/context/star (queue, ledger, briefs, notes). STAR asks only for what a person must supply (a secret, an account, an action at the screen, an approval, access) and decides everything else from cited sources, logging each call for the owner to overrule. One Orca worker per item plans, has codex run the plan on the newest luna, verifies, and loops its draft PR through a headless codex review gate until it passes; a babysit worker takes it through the hosted review or green CI; STAR merges when every gate holds on the exact head. A failing step spends a tries budget, then the item is re-scoped or set aside while everything else keeps moving. STAR never reads big output and recovers by itself after compaction. Triggers "start STAR", "add this to STAR", "what does STAR need from me", "/juel:star".
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
        why: workers open and babysit PRs; pr-verify.sh, done-check.sh and release-record.sh read them; merge.sh merges when the merge gate holds on the exact head; star-issue.sh files STAR's own improvement issues
        check: "gh auth status"
      - id: git
        hard: true
        why: star-home.sh finds the project's main checkout with it, and workers branch and push
        check: "command -v git"
      - id: python3
        hard: true
        why: star-home.sh, loops.sh, ledger.sh, messages.sh, stage-start.sh, star-issue.sh, worktree-clean.sh, pr-verify.sh, worker-probe.sh, release-record.sh, handoff.sh, done-check.sh, merge.sh, codex-gate.sh and the session hook run on it
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
        why: every question is asked in plain chat
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

STAR is one long-running coordinator session that ships one project's work. You start it by typing
`/juel:star` in the project with a brief: free text, work-item refs, or both. That session plans, hands out
work, checks results, keeps the queue and merges. It never writes code and never reads big output. Real work
goes to Orca workers: a fresh agent per stage, in the item's own worktree, that reports in at most 12 lines
and is released. Everything that matters lives in files inside the project, in a git-ignored folder, so a
compacted or restarted STAR reads them and carries on. `skills/star/how-it-works.html` draws the flow
(published at https://claude.ai/artifact/V2Qx9Cm469k1vuJvcjS2fC).

## Goal

Hand STAR a brief or a ticket and get back a merged PR without being asked anything, unless only a person can
supply what is missing. It holds the quality bar of a fresh Claude review, a second-model codex gate, the
regression gates, the hosted review or green CI, and an exact-head merge gate. When the rules leave a choice,
take the one that keeps work moving: decide from sources, retry within the budget, re-scope, set aside, file
its own improvement issue. Stopping the whole run for the owner is never that choice; only the one item that
needs a person waits.

What counts as failure, even when it technically works:

- **A merge that is unsafe:** no codex PASS on the exact head, a head whose own check is red and is the PR's
  fault, or a required check or required approval passed over. STAR never uses an admin bypass.
- **Crossing the owner's four lines** (Hard rules).
- **An old stop coming back as a new question.** If a rule would make STAR ask the owner something it can look
  up, decide or retry, the rule is wrong.
- **Breaking the dashboard.** It reads the ledger, queue, briefs and releases; change those only through the scripts.
- **Handing an exact job to judgment.** A head check, a ledger write and a terminal close are scripts.
- **Endless work:** follow-ups that breed follow-ups, or retries that burn tokens forever. The tries budget ends both.

**Announce:** "Using juel:star." (in hand-over, `status`, `dashboard` and worker modes say which mode.)

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

`status`, `dashboard`, `away`, `back`, `stop`, `draft-brief` and `post-report` are not a start: they skip
this table and the task list, and announce their own mode. So does a `/juel:star` that finds STAR already
running for this project in another terminal: it hands over and ends. Finding that out takes steps 1 and 2 of
"Coordinator, or hand-over" below, which run before the Preflight block and create nothing. Everything else is
the start mode. `stop` typed in STAR's own session is the Stop rule in `references/recovery.md`, nothing more.

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

Claude Code's first-run trust dialogs are not a preflight item: `stage-start.sh` clears them in a throwaway
terminal before every Claude worker starts, and only when it cannot does the queue ask the owner (a `person`
item of kind `screen`).

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
| `/juel:star SPH-11 and SPH-12` | STAR is not running here: this session becomes the coordinator, adds both refs and starts. STAR is running in another live terminal: this session hands the refs over and stays free |
| `/juel:star add a CSV export to the reports page, and SPH-12` | Free text and refs together: the text becomes a spec item and the ref an item, in one batch |
| `/juel:star` | Start STAR for this project, or resume it: the same command |
| `/juel:star status` | Print the Needs-you block and counts per state. Read-only |
| `/juel:star dashboard [--tailnet]` | Open the STAR dashboard (`references/dashboard.md`). Needs no STAR running |
| `/juel:star away` / `back` | The owner leaves or returns (`references/dashboard.md`). Away holds no work |
| `/juel:star stop` | Finish the tick and stop. Running workers are left to finish |
| `/juel:star draft-brief <ref> --project <name> --out <path> [--rescope <file>]` | Worker mode: read `references/brief-worker.md` and follow it. A brief worker's command, never the owner's |
| `/juel:star post-report <ref> --item <name> --report <path>` | Worker mode: read `references/post-worker.md` and follow it |

`S` is this skill's directory (`${CLAUDE_PLUGIN_ROOT}/skills/star` when set, else this file's directory);
scripts run as `sh S/<name>.sh`. `HOME_DIR` is the project's STAR folder, never worked out by hand: `sh
S/star-home.sh path` prints it, `init` creates it, and every worktree of a project shares one.

**Reading the command.** Everything after `/juel:star` is read as words. A first word of `draft-brief` or
`post-report` is that command. `status`, `dashboard`, `away`, `back` and `stop` are commands only when they
are the whole text, so `/juel:star stop the digest from sending twice` is a free-text brief. The whole text
`take over` makes this session the coordinator even though another terminal is listed. Otherwise every word
that is a work-item ref (`SPH-11`, `#412`) or a path to a spec file is a ref, and the rest is the free-text
brief, unless it is only filler (`and`, `add`, `please`) or only says something about the refs ("the second
one is urgent"), which goes in the inbox file's `note:` line. Free text goes word for word in `text:`.

**Coordinator, or hand-over.** (1) `HOME_DIR=$(sh S/star-home.sh path)`; exit 1 means not inside a project's
repository: say so in one line and stop. (2) When `HOME_DIR/star.json` names a `terminal` that is not this
session's `$ORCA_TERMINAL_HANDLE` and `orca terminal list --limit 500 --json` still lists it (and the owner did
not say "take over"), STAR runs there: hand over (`references/dashboard.md`) and end. (3) Otherwise this
session becomes the coordinator: run the Preflight table (a STOP leaves the project untouched), `sh
S/star-home.sh init`, write any refs and text as an inbox file, then the start sequence. The first tick ingests
them. The coordinator session should be an Orca terminal running Claude Code on Fable 5.1 (`claude --model
fable`); the skill does not check.

| Role | Default | Why this one |
|---|---|---|
| STAR itself | Fable 5.1 (the model the STAR session is started on; not a setting here) | the strongest rule-following of the Claude models, with top-level reasoning |
| brief | Opus 5.5, high | a brief reads the item and enough code to propose an approach and take its product calls: `high` lands briefs sooner |
| build, babysit, post | Opus 5.5, xhigh | plans, verifies and answers reviewers, and acts on an Orca dispatch. Fable 5.1 scores higher on rule-following but, started as an Orca worker, it treated the dispatch as pasted text and did nothing until told to go ahead (tried 2026-10-07): do not put it on a worker stage without trying that again |
| executor | the newest luna (`gpt-6-luna` on 2026-10-09), xhigh | a fast, affordable model types the plan Opus wrote. At capacity it falls back to the newest sol, then to the worker's own session |
| gate | the newest sol (`gpt-6.1-sol` on 2026-10-12), xhigh, through `codex review`; fallback Opus 5.5, xhigh, through `claude -p` | only Sol reviews, so the build's own fresh Claude review is the independent one. The fallback runs only when Sol is still at capacity after its retries or the Codex account is out of usage |
| hosted review | the project's own (Greptile), 4/5 or better | the owner's convention for a hosted reviewer's score |

## How a brief becomes a merged PR

Every stage is its own Orca task and a fresh worker, started only by `stage-start.sh` in "Fill slots"
(`references/tick.md`). The stage prompts and what STAR does with each report line are in
`references/stages.md`.

| Stage | Worktree | Agent | Prompt |
|---|---|---|---|
| brief | the project's main checkout, read-only | `stages.brief` | `/juel:star draft-brief <ref> --project <name> --item <name> --out HOME_DIR/briefs/<project>/<item>.md [--feedback] [--rescope HOME_DIR/reviews/<project>/<file>]` |
| build | a new Orca worktree in that project | `stages.build` | `/juel:ship-ticket --unattended --brief <brief>`: plan, executor, fresh Claude review, live checks, draft PR and the codex gate loop, in one worker |
| babysit | the item's worktree | `stages.babysit` | `/juel:babysit-pr <n> --unattended --mark-ready --reviewed <the item's newest review> --item <item> --brief <brief> --gates-file HOME_DIR/gates/<project>/<item>.json [--since <cursor>]` |
| post | the project's main checkout, read-only | `stages.post` | `/juel:star post-report <ref> --item <name> --report HOME_DIR/reports/<project>/<item>.md` |

A row is in exactly one state. A pool caps how many workers run; a waiting state is where a row sits until
"Fill slots" gives it a slot.

| State | Pool | Meaning |
|---|---|---|
| `inbox` | none | ingested; waiting for a brief slot (with `rescope=`: waiting to be narrowed) |
| `briefing` | brief | a brief worker is reading the item and the code |
| `needs-you` | none | waiting for a `person` item to be done; resumes the stage in its `stage` column |
| `queued` | none | brief drafted; waiting for a build slot, the host gate, its blockers and its `notBefore` time |
| `building` | build | build worker running: plan, executor, checks, draft PR, the codex gate loop |
| `babysit-queued` | none | its `DONE` checked out, or sent back; waiting for a babysit slot |
| `babysitting` | babysit | babysit worker running: ready, the hosted review or green CI, gated fixes |
| `verifying` | none | `READY` received; STAR runs the merge gate each tick until it holds, then merges |
| `post-queued` | none | a report is written; waiting for a build slot to post it |
| `posting` | build | a post worker is posting the report to the work item |
| `done` | none | merged and its release record written, or its report posted |
| `set-aside` | none | out of tries; in the queue as a note, nothing waits on it |
| `dropped` | none | the owner dropped it, or it was split into new items |

The path: an `inbox` row gets a brief (`BRIEF`), becomes `queued` (or `needs-you` while a `person` item for it
is open), and starts when a slot, the host gate, its blockers and its date allow. A `DONE` that `done-check.sh`
confirms makes it `babysit-queued`; `READY` makes it `verifying`; the merge gate passing makes `merge.sh` merge
it, and the row is `done`. A `SPLIT` drops the parent and adds one `inbox` row per part. A report item ends in
`post-queued`, `posting`, `done` with no merge. A failure follows the tries budget below. There is no go and no
batch approval: a drafted brief is `queued`, and the owner overrules by feedback (`references/dashboard.md`).
Counters, pools and the ledger commands are in `references/state.md`.

## When STAR asks you

STAR asks the owner only for what a person must supply. Each is asked once, as a `person` item in the queue,
and only the item that needs it waits; every other item keeps moving.

| Kind | Example |
|---|---|
| `secret` | an API key or token the work needs |
| `account` | signing up for or in to a third-party service; anything that costs money |
| `screen` | an action at the owner's screen: a trust dialog STAR could not clear, a lost Claude login, hardware |
| `approval` | the base branch's protection requires an approving review STAR cannot give (GitHub never lets an author approve their own PR) |
| `access` | `gh` cannot see the repository, so `tokenCmd` must be set; or the repository forbids the merge method STAR must use |

Before STAR asks the owner anything, it checks its notes and the project's `CLAUDE.md` and `AGENTS.md`. After an
answer, it writes a note. This is why the same question never comes back: the answer is looked up first, and
the next question finds the note. STAR reads `CLAUDE.md` and `AGENTS.md` but never edits them, since they are
committed and shared with teammates; a rule every agent must follow is one the owner writes there, and STAR
obeys it.

Everything else is STAR's call, logged as a decision record the owner can overrule: scope, acceptance criteria
for an item that has none, a worker's question, a risky call that has a safe option, an accepted residual. The
order of sources:

- **A user-facing change:** Mobbin for how real apps solve it, together with the `frontend-design:frontend-design` skill.
- **A technical question:** Context7 for the library at the project's version, else a web search.
- **The repository itself:** `file:line`.

When an MCP is missing, a web search stands in and the record's `Source:` says so. A decision no source can
settle and only the owner can make (money, a policy, a legal question) is an `account` item.

## Tries, re-scopes and follow-ups

```json
"tries": { "perStep": 3, "rescopes": 1, "followUpDepth": 2 }
```

- **`tries.perStep`:** how many times one step may fail the same way before STAR changes approach. It covers a
  NOT-SAFE gate round, a red-CI fix attempt, a hosted-review round with blocking findings, a lost or stalled
  worker, a stage that could not start, a report in the wrong shape, and a repeating merge-gate
  `PENDING`, `MOVED` or `FAIL`. The row carries one counter, `counters.tries`; mixed failures share it.
- **`tries.rescopes`:** after the tries are spent on a quality failure, STAR shrinks the item once: the part that
  works ships, the rest becomes a follow-up.
- **`tries.followUpDepth`:** how deep a follow-up of a follow-up may chain, counted from the original item.
- **Everything spent:** the row goes to `set-aside` with a one-line reason and a `set-aside` item (`try again`
  or `drop`) in the queue. Nothing waits on it. STAR keeps working on everything else. `try again` gives fresh
  tries.

How the count works, and why: `tries` resets only when the row first reaches a state further along than
`reached` (the stage order `briefing`, `building`, `babysitting`, `verifying`, `done`), so a `verifying` to
`babysit-queued` to `verifying` loop can never run forever. Only quality failures re-scope, because shrinking
the item fixes nothing for an infrastructure failure. A base sync because a sibling merged, and each recheck of a wait
on something outside STAR (the hosted reviewer, CI that has not reported, the host gate, the codex gate being
down), spend nothing: this item did nothing wrong, and those recheck on their own timers. A wait that outlasts
its window (a babysit `step=hosted-wait` or `step=ci-wait`, a merge-gate `PENDING` past 60 minutes) spends one
try, so a reviewer or CI that never comes ends set aside, never merged past. The class of each step and
what STAR does about it is the table in `references/stages.md`. A worker that runs out of its own loop reports
`ESCALATION … reason=out-of-tries step=<step>`, which spends one try on the row. Follow-ups are filed as tickets
or spec files with the defaults in `references/stages.md`; a follow-up past `tries.followUpDepth` is set aside
instead of built.

## The merge gate

Every merge needs all of: a codex PASS on the exact head; every required check green; GitHub's merge state not blocked or dirty, and not behind when the base requires up-to-date
branches; and a reply from the author on every unresolved review thread someone else opened.
The gate is `sh S/pr-verify.sh <pr url> --head <head> --merge-gate --brief <brief> --home HOME_DIR [--hosted
<login>]`, with `--hosted` passed only when `hostedReviewer` is set and not paused (by `hostedReviewer.paused`
or by the project's `CLAUDE.md` or `AGENTS.md`). A project with a hosted reviewer also needs its passes. A project
with none, or a paused one, needs nothing more: green CI plus the codex PASS merges it. No second person's
approval by default: when the base branch's protection requires one, the row waits on a `person` item of kind
`approval` ("approve PR #n"), because only a person can meet a GitHub rule. This holds with a hosted reviewer too.

- **Red CI.** The babysit worker (or the build before its PR is ready) works out why. If the PR caused it, it
  fixes within the tries budget, then re-scopes: STAR never merges a PR whose own change is red. If it is not
  the PR's fault (the base head fails the same check, an infrastructure failure, or one rerun passes), the PR
  merges only when the red check is not a required one, and STAR files a follow-up after the merge. A script checks the proof,
  not trust: the worker records `red-check-proof check=<name> head=<sha> cause=base|infra base=<sha> url=<url>`
  in the brief's `## Decisions`, and `pr-verify.sh --merge-gate --brief` confirms it with `gh`. A proof never
  carries over to another head or check.
- **`mergeMethod`** (`merge`, `squash`, `rebase`, or null for the first the repository allows).
- **`baseBranch`** is the branch every STAR PR targets (null is the repository's default); **`ownerBranches`**
  lists branches only the owner merges into. STAR never opens a PR into one or merges into one. A brief or
  ticket that names an owner branch is re-targeted to `baseBranch`, logged as a decision. An item whose whole
  point is a merge into an owner branch (a `dev` to `main` release) is set aside with "`<base>` → `<owner
  branch>` is yours", and nobody is asked: a merge to the owner's branch can be a release to every user.
- **One merge per base at a time**, since two merges on one base race and GitHub refuses the second.
- **A hosted reviewer that is down** is waited on, never merged past, because it is that project's own bar.
- **`merge.sh <pr url> --head <sha> --home HOME_DIR --item <item> [--hosted <login>]`** is the only merge, with
  `--hosted` exactly when the gate got it. It posts `Merging head
  <sha>: codex PASS, required checks green[, <login> passed].` first and merges with `--match-head-commit`, so a
  head that moved is GitHub's refusal. `FAIL owner branch <base>` → `set-aside`. `FAIL merge methods: <method>
  not allowed` and `FAIL settings: <why>` → a `person` item of kind `access`. `PENDING approval` → a `person` item of kind `approval`.
  Every other verdict and line, and what each costs, is in `references/stages.md`.

## Conflicts

After a sibling PR merges, the babysit worker resolves a conflict itself from both items' briefs and
`## Decisions` and the sibling PR's diff and description, keeping both changes' intent. It records the
resolution as a decision, then reruns the regression gate and the codex gate on the result. A `## Decisions`
entry that already names the conflicting files and a resolution is applied as written. A resolution that fails
its gates spends tries like any other step. STAR does nothing here except send the row back to babysit when
the merge gate says `FAIL conflicts` or behind (`references/stages.md`, "Sync after the base moved").

## Memory

Notes are STAR's memory: one file per note in `HOME_DIR/memory/<project>/`, a `rule` (something every worker
must do or avoid) or a `fact`, readable as an Obsidian vault. STAR writes them only through `sh S/notes.sh
--shelf memory --project <project>` and decisions that apply beyond one item through `library.sh`, because
brief workers write at the same time and `notes.sh` numbers them under a lock; a legacy home also keeps its old
notes file in step. STAR finds them with `recall.sh` and never reads the folder into its context. A worker's
`NOTE:` is a `fact` note. A rule the owner says in chat is a `rule` note at once (`--source owner`, `--always`
when it holds for every item), never a new `star.json` key; replacing one is `notes.sh … replace`. The notes
mode of a home (`legacy` or `split`) is never changed by STAR on its own.

## Tracker status

STAR is the one writer of a work item's status; no worker under STAR writes it. The row's state decides the
status and STAR writes only where it differs from `counters.tracker=`. For Linear the call is
`<LINEAR_PREFIX>save_issue(id: <ref>, state: <the team's state>)` and a report goes to the ticket with
`<LINEAR_PREFIX>save_comment`; `LINEAR_PREFIX` is the first loaded of `mcp__linear__`,
`mcp__plugin_linear_linear__` or `mcp__claude_ai_Linear__`, as `references/work-source.md` resolves it. The
other providers and the parts of a split are in `references/stages.md`. A write that fails is named in the
status line and nobody is asked. Under STAR, filing a follow-up, writing the status and posting a report to the
ticket STAR was handed need no confirmation; by hand, `references/work-source.md` §5 stays as it is.

## Looking after workers

A worker that is unsure asks STAR (`orca orchestration ask`), and STAR answers, always: from the brief, its
decisions, the notes or the ledger; an engineering call inside the brief's Scope; or a product call, decided
from the sourced options the worker brings (`recall.sh --kind decision` first, so a mid-build answer never undoes
the owner's correction). Answer in a few lines, record `- <date> STAR answered (<message id>): <question> →
<answer>` in `## Decisions`, and name it in the next status line. A question that brings no sourced options
gets "Bring sourced options: <what to look up>, each with its source." A question only a person can settle
(the five kinds) becomes a `person` item and the worker is told to report `ESCALATION … reason=needs-person`.
STAR opens no code, review or log file itself.

Each tick `worker-probe.sh` reads every running worker and prints one line (`ok`, `quiet`, `stale`, `stuck:`,
`stalled:`, `settled`, `gone`, `unknown`, `gate-gone r<k>`); `references/stages.md` ("Watching a running
worker") says what each costs and does. After every `worker-stop` and `worker-release`, STAR runs `sh
S/stage-start.sh --home HOME_DIR close <dispatch>`, which closes the dispatch's own settled terminal and keeps a
terminal it cannot prove it created (#175). Nobody is asked about a kept one.

## The start sequence

In order, each detailed in `references/recovery.md`: claim the home; `sh S/star-home.sh init` or `migrate`
(print its `warn` lines as they are); the hosted-reviewer lookup; when `mergeMethod` or `baseBranch` is null,
look for a rule in the project's `CLAUDE.md` and `AGENTS.md` and STAR's rule notes, and set the key and say so
in one line when one is found; print one line when those instructions say the hosted reviewer is paused while
`hostedReviewer.paused` is false (#169); bind the Orca run; caffeinate; the heartbeat; reconcile every
running row; kill a stale message wait; then tick (`references/tick.md`).

## Hard rules

The owner's four lines. STAR never:

- Never touch a teammate's PR or branch.
- Never force-push over work that is not STAR's own.
- Never delete anything STAR did not create.
- Never post as the owner anywhere but STAR's own PRs and tickets and the tickets it was handed; drafts wait for the owner's send.

The reasons: a teammate's work is not STAR's to change; a force-push loses commits nobody can recover; a
deletion of something STAR did not make can destroy work; and a post in the owner's name is the owner speaking.
These are the harm the code cannot undo, so they hold in chat, in a follow-up and under a deadline.

- **Merge only through `merge.sh`**, on the exact head `pr-verify.sh --merge-gate` passed, and never with an
  admin bypass. A merge on any other head, or past a required check, cannot be taken back.
- Never read review, evidence, log or diff content into this session; one line per fact, from a script or a
  report. A big read exhausts the one session every item depends on. On Claude Code 2.1.287 and later juel's
  mod enforces this and refuses a direct `gh pr merge`; elsewhere the rule holds as written.
- Never call AskUserQuestion once a worker exists: Orca's nudge would answer it with the first option. Every
  question is a queue item.
- `open-loops.md` is written only through `loops.sh`, `ledger.md` only through `ledger.sh`, notes only through
  `notes.sh` and `library.sh`: each keeps what two writers would lose.
- Workers start only through `stage-start.sh`, from "Fill slots". One STAR per home, one worker per row, one row
  per worktree.
- One message wait at a time, in the background: `messages.sh --waiting` first, start only on `none`.
- A worktree is removed only by `worktree-clean.sh`, and only after its evidence is copied.
- STAR never writes a script into the home or the project; a step that wants a script is an
  improvement issue (`star-issue.sh`), filed once with placeholders only.

## Where the detail lives

- `references/state.md`: the home layout, `star.json` keys, the queue kinds, the ledger, counters and pools. Read
  when you write any of them.
- `references/tick.md`: the tick step by step, answers, messages, slots, housekeeping, notifications, improvement
  issues and the host gate. Read at every tick you have not run before.
- `references/stages.md`: stage start, the codex gate, every report line and verdict with STAR's response, the
  failure classes, set-aside, re-scope, follow-ups, report items, the tracker status, watching a worker. Read
  when a report or a probe line arrives.
- `references/brief-worker.md`: `draft-brief` mode, SPLIT, re-scope and the decision record with its sources.
  Read when you are a brief worker.
- `references/post-worker.md`: `post-report` mode. Read when you are a post worker.
- `references/dashboard.md`: the dashboard, hand-over, chat, feedback on a brief, the batch digest, status-note drafts, away
  and back. Read when the owner talks to STAR.
- `references/recovery.md`: the start in detail, stop, compaction and restart, edge cases. Read at every start
  and when something looks odd.
