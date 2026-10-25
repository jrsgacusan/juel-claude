# Stages: starting a worker, reading its report, and what STAR does about each line

Read this when you start a stage, apply a `worker_done` report, run the merge gate on a `verifying` row,
or decide what a failure costs.

## Contents

- Starting a stage
- The codex gate
- Report lines and STAR's response
- What a failure costs
- Set-aside, re-scope and follow-ups
- Merge-gate verdicts
- Report items
- The tracker status
- Watching a running worker

## Starting a stage

Every stage is its own Orca task and a fresh worker. The prompts are the Stage table in SKILL.md.
`sh S/stage-start.sh [--home HOME_DIR] brief|build|babysit|post <item>` does everything "Fill slots"
needs in one place, so no session hand-rolls it: the host gate, a build's worktree, Claude Code's
first-run trust dialogs, the prompt file, `task-create` and `worker-start`, writing the row as it goes.
Run it with `run_in_background: true` and wait for its completion notification: a worktree with a setup
hook can take longer than the Bash tool's 600 s foreground cap. Parallel starts are safe: `stage-start.sh` holds a lock per repository around the branch step. Agent, model and effort come from
`stages.<stage>` (else `worker`). A failed `worker-start` is retried once, one effort level lower when the
effort was refused, or on `worker` when the model was refused (a `fallback` suffix says so).
`task-create` and `worker-start` carry `--retry-request` ids, so a replay never makes a second task. Every
spec is one line: a line break once left an orphan task.

**Build worktree.** `stage-start.sh build` sets it up before any agent starts, because Orca picks the
new worktree's branch name and `ship-ticket` stops when the checkout is not on the brief's branch.
It reuses a worktree that `git worktree list --porcelain` shows on the brief's branch (unless another
open row names that path: `failed in-use`), else creates one with `orca worktree create --repo
"id:<REPO_ID>" --name "<item>" --base-branch "<remote>/<baseBranch>" --no-parent --setup run --json`,
switches to the brief's branch (fetching the PR head for an `existingPr`, else renaming Orca's branch),
copies only environment files git ignores from the main checkout (`.env*`, `*.local`, `.envrc`,
`.npmrc`, `.tool-versions`, ignored files under `.claude/`; they never show in `git status`, and an
untracked file that is not ignored is someone's work and stays), and adds one `.git/info/exclude` line
for a worktree inside the repository.

Its last line decides what happens next. Before it, up to three lines of their own may come
(`stopped previous gate …`, `ended previous session …`, `kept previous session …`): say each in the
status line as `<item>: <the line>`, then act on the last line.

| Last line | Then |
|---|---|
| `started task=… dispatch=…` | nothing more. A ` fallback <model>: <why>` suffix goes in the status line |
| `hold <what> <value>` (`memory`, `agents`, `swap`, `disk`) | the host gate held it: start nothing else this tick, `counters.hold=+1`. The next start that succeeds clears it. Nobody is asked: the machine frees up by itself |
| `hold trust <path>` | Claude Code's trust dialog for the path could not be cleared. Add a `person` item of kind `screen`: "trust <path> for Claude Code: run `claude` there and accept". The row keeps waiting and the next tick tries again |
| `hold session <terminal> (<state>)` | a session may still be working on this item (a person took the terminal over, or Orca cannot prove whose it is). Start nothing for this row, keep it waiting, give the slot to the next row. The next tick tries again. No question: the session ends or goes quiet |
| `wait until <iso>` | the brief's `notBefore` is ahead: keep the row `queued`, say `<item> waits until <date>`, give the slot to the next row |
| `failed <step>: <why>` | an infra failure: `<step>` is one of `brief`, `worktree`, `branch`, `env`, `in-use`, `task-create`, `worker-start`. Spend a try (below); the row goes back to its waiting state |
| no line, or a non-zero exit | the script was cut off: put the row back in its waiting state with its counters as they are, and file an improvement issue |

**A stopped worker is gone** (#76, #175). `worker-stop` fences the dispatch, but Orca can keep its terminal
and the agent in it. After every `worker-stop` and `worker-release` STAR makes, run
`sh S/stage-start.sh --home HOME_DIR close <dispatch>`. It prints exactly one line and exits 0:
`closed <terminal>` (the dispatch settled and the terminal was provably its own, whatever its
`retainedReason`), `kept <terminal> (<state>)` (anything else: a person's terminal, or a dispatch not yet
settled) or `none`. Say a `closed` or `kept` line in the status line. A `kept` terminal stays open and
nobody is asked. `stage-start.sh` applies the same rule to a row's previous dispatch before it starts the
stage, so two sessions never work in one worktree.

## The codex gate

Not a stage and not a worker: the build runs it on its own draft PR, and babysit runs it again after every
push. `sh S/codex-gate.sh --brief <brief> --item <item> --round <k> --base <remote>/<baseBranch>` runs one
headless `codex review` of the branch against its base on `star.json`'s `gate` model (the newest sol at
xhigh), read-only and with no MCP server. Facts STAR relies on:

- It writes `reviews/<project>/<item>-r<k>.md` (first line `VERDICT item=<item> round=<k> SAFE|NOT-SAFE
  findings=<n> head=<sha>`), `.raw.md` and `.log`. Only a `[P0]` or `[P1]` finding makes a round NOT SAFE.
  An attempt that ends in `ERROR` writes none of them, so rounds count verdicts only.
- A capacity error is retried after 60 and 180 seconds, then, or at once when the Codex account is out of
  usage, the same prompt runs through `gate.fallback` (a headless `claude -p` review on Opus, read-only).
  The review's `Gate:` line names it. Luna writes the code and Sol gates it; while the fallback runs, the
  gate is a second Claude review, not a second model.
- A round whose base moved past the branch and changed a file the branch changes refuses with `ERROR
  base-moved …`: the worker merges the base in and runs the same round again. That is neither a try nor a
  failure.
- After a SAFE round the worker posts the receipt with `codex-gate.sh post-pass` once per head: `Codex
  gate: PASS (head <full sha>, round <k>, <model> <effort>)` then `VERDICT: PASS`. `carry-check.sh` proves
  when a base merge added no change of its own, and then the receipt names `carried from <gated head>`.
  `done-check.sh` and `pr-verify.sh --merge-gate` read these files and print one line; STAR opens none.
- A build still NOT SAFE after `tries.perStep` rounds reports `RESCOPE … reason=gate`. A babysit run counts
  its NOT-SAFE rounds since the newest SAFE round or its last push, and reports the same at the
  `tries.perStep`-th.

**Gate down.** `ERROR gate-down <why>` printed by `codex-gate.sh` itself (or its `check` printing `down`) means Sol and its
Claude fallback both failed. A worker reports it as `ESCALATION … reason=out-of-tries step=gate-down`; any other
gate or `post-pass` `ERROR` is `review-tool`, an infra step. STAR spends no try: it puts the row in its stage's
waiting state (babysit resumes with `--since <cursor>`), sets `gateDown` to `{"since", "why", "checked"}` when
it is null, and starts no build or babysit while it is set (brief and post stages need no gate and still
start). Housekeeping runs `sh S/codex-gate.sh check` every 30 minutes: `up <agent:model>` clears `gateDown`
and the parked rows start again; `down <why>` writes `checked=<now>`. Nobody is asked.

## Report lines and STAR's response

STAR reads only the report's lines (at most 12). A `cut` report: act on the first 12 lines. Match the first
line against the stage's words; a line that lacks a field its row names fits only the last row. Apply
each message in the order of effects (tick.md). After any report: `NOTE: <text>` becomes a note through
`notes.sh` (`NOTE: always <text>` with `--always`); `NOTE: accepted residual <criterion>: <follow-up path>`
also adds the follow-up (below); `SENT …` goes to `sent.log`; `STAR-ISSUE: <text>` becomes an improvement
issue (tick.md); `HELD item=… action=…` becomes a `draft` item titled `by hand: <action>` (body `action:
<action>`, options `done / skip`), and nothing waits on it; `REUSED` and `CORRECTED` lines go to
`library.sh`; `PHASE`, `PR` and `GATES` need nothing.

**Brief**

| First line | Action |
|---|---|
| `BRIEF item=… path=… asks=<n> [followup=<path>] [rescoped=1]` | write each `MCP <name>=<state>` line that follows it to `star.json` as `mcps.<name>` and name it in the status line (the worker's tools showed a state other than the one STAR had; the next worker reads the new value from `star.json`, #192); queue one `person` item per line of the brief's `## Person-only steps` (`sed -n '/^## Person-only steps/,/^## /p' <brief>`, at most 20 lines), but look first, because the owner is never asked the same thing twice: STAR's notes (`sh S/recall.sh --kind note <the step's words>`), the project's `CLAUDE.md` and `AGENTS.md`, and the queue and its archive. A step one of them already answers, or one answered `done` in the last 7 days, goes into `## Decisions` instead (naming where the answer lives, never a secret's value), and no item is added. The row goes to `queued`, or `needs-you` (its `stage` set to build) while any of those items is open. `followup=<path>` adds the follow-up row (below). `rescoped=1`: clear `counters.rescope` (the count went up when the row was sent to be re-scoped). When the brief's `baseBranch` is one of `ownerBranches`, its point is a merge into that branch, which is the owner's: the row goes `set-aside` with "<branch> → <baseBranch> is yours", nothing is built |
| `SPLIT item=… into=<path>,<path>` | one `inbox` row per path (`ref` the path, the same `batch`, `parent=<item>`); when the parent's `ref` is a tracker item every part also carries `counters.trackerRef=<parent ref>` (#172); the parent row goes to `dropped`; say "split into <names>" |
| `ESCALATION …` | below |

**Build**

| First line | Action |
|---|---|
| `DONE item=… pr=<url> head=<sha> review=<path>` | `sh S/done-check.sh <item> --pr <url> --head <sha>`. `OK` → record PR and head, free the slot, row `babysit-queued`. For a brief that carries another author's PR (`Decision: carried as a new PR: <url>` in its `## Decisions`), also add a `draft` item "by hand: close <that url>, carried on <pr url>" (the original is the teammate's: STAR never touches it). `MISMATCH <what>` → record PR and head, append "- <date> the report did not check out: <what>; resume the gate loop on the existing PR" to `## Decisions`, spend a try, row `queued`. `PENDING <why>`, no line or a non-zero exit → process and acknowledge the message, record PR and head, keep the row `building` with `verify=retry=<now + 2 min>`: it has reported, so the probe does not read it as a lost worker, and Housekeeping runs `done-check.sh` again after that time. Exit 64 also files an improvement issue |
| `RESCOPE item=… reason=<gate\|hosted-review\|ci\|brief> review=<path> [tooling=all]` | free the slot. See "Set-aside, re-scope and follow-ups". `tooling=all` on a row with a PR, `rescoped=0` and no `rescopedFrom:` in its brief is a hand-over to a follow-up instead: those findings are safety findings by the gate's tooling rule |
| `REPORTED item=… path=<path>` | row `post-queued`, free the slot. STAR never opens the report |
| `ESCALATION …` | below |

**Babysit**

| First line | Action |
|---|---|
| `READY item=… pr=… head=<sha> cursor=<cursor>` | record head and cursor (an opaque string: pass it back as `--since` exactly as it came), update `reached`, row `verifying`, run the merge gate now |
| `MERGED item=… pr=<url>` | as `pr-verify.sh` printing `MERGED`: release record, row `done` |
| `RESCOPE …` | as for a build |
| `ESCALATION …` | below |

**Post**: `POSTED item=… url=<url>` → row `done`, free the slot. `ESCALATION …` below.

**`ESCALATION`** has two forms and nothing else. It carries no cursor: a restarted babysit resumes from the cursor of the row's last `READY` (the ledger `cursor` column).

- `ESCALATION item=<item> phase=<n> reason=needs-person needs=<secret|account|screen|approval|access>: <what>`.
  Add a `person` item (title the thing, body `kind: <needs>` and what it is for), set the row `needs-you`
  with its `stage` as it was, free the slot, stop and release the worker. When the
  item is done the row goes to that stage's waiting state. STAR first checks its notes and the project's
  `CLAUDE.md` and `AGENTS.md`: when the answer is there, it records the decision and puts the row straight
  back in its waiting state. When the same need comes back for the same item, the note did not work: add the `person`
  item, naming the note (`M-…`) so the owner can correct it. At most one note retry per need per item. A need that is not one of the five kinds is not a person's: decide it
  (SKILL.md, "When STAR asks you") and reply to the worker or run the stage again.
- `ESCALATION item=<item> phase=<n> reason=out-of-tries step=<step>[ review=<path>]`. Free the slot and apply "What a failure costs" to `<step>`.

A babysit worker settles `CONFLICT:`, `AMBIGUOUS:`, `BRIEF-VIOLATION:` and `STOPPED:` itself; they never
reach STAR. A `question` message (`orca orchestration ask`) is STAR's to answer, always (tick.md,
"Looking after workers" in SKILL.md). An escalation message while the worker still runs: keep the row and its
slot until the `worker_done`.

**A report of the wrong shape.** A `worker_done` whose first line is none of its stage's words (brief:
`BRIEF`, `SPLIT`, `ESCALATION`; build: `DONE`, `RESCOPE`, `REPORTED`, `HELD`, `ESCALATION`; babysit: `READY`,
`MERGED`, `RESCOPE`, `HELD`, `ESCALATION`; post: `POSTED`, `ESCALATION`) is a prose body in place of the
report (#56). It costs one try at step `worker`, and the stage runs again. The same holds for a worker that
settled with no report at all.

## What a failure costs

One counter per row, `counters.tries`. Every failure below adds one; mixed failures share it. The step
decides what happens next:

| Class | Steps | STAR's response |
|---|---|---|
| quality | `verify`, `regression`, `gate`, `ci`, `hosted-review`, `conflict` | re-scope while `tries.rescopes` is left, else `set-aside` |
| infra | `executor`, `stack`, `screen`, `worker`, `gh`, `pr-draft`, `hosted-wait`, `ci-wait`, `review-tool` | spend one try, then run the stage again; after `tries.perStep` → `set-aside` |
| outside | `gate-lock`, `gate-down` | no try spent: set `gateDown` and recheck every 30 minutes |

- A worker reports `out-of-tries` after its own loop used `tries.perStep` attempts, so a quality step goes
  straight to re-scope or `set-aside`: shrinking the item is what is left.
- When the cause text matters the worker writes it to `reviews/<project>/<item>-tool.log` and names it in `review=`; STAR never reads that file. `review-tool`, `gate-lock` and `gate-down` need only the step.
- An infra step spends one try per report. A stage that could not start (`stage-start.sh failed …`), a
  lost or stalled worker, a report of the wrong shape, an executor that is down, a regression gate that stalled
  or timed out, a failed dependency install: all infra.
- `hosted-wait` with the reviewer silent: set `hostedDown` to `{"since", "why"}` when it is null and park the
  row in `babysit-queued`; Housekeeping clears `hostedDown` after 30 minutes and the parked babysits start
  again. Each report spends a try, so a reviewer down past the tries sets the row aside with the note
  "<reviewer> unavailable since <time>". STAR never merges past a configured reviewer, and never asks.
- The merge gate's own repeating `FAIL`, `MOVED` or `PENDING` spend a try each (below) and set the row aside
  at `tries.perStep`; shrinking the item fixes nothing there.
- Not a try: a base sync because a sibling merged or the base moved, and each recheck of a wait on something
  outside STAR (the hosted reviewer, CI that has not reported, the host gate, the codex gate being down). A wait
  that outlasts its window does spend one: a babysit run that ends `out-of-tries step=hosted-wait` or
  `step=ci-wait`, and a merge-gate `PENDING` older than 60 minutes. So a reviewer or CI that never comes ends
  `set-aside` after `tries.perStep` windows, and is never merged past.
- `tries` resets only when the row first reaches a state further along than `reached`, on a re-scope, and
  on the owner's `try again`.

## Set-aside, re-scope and follow-ups

**Set aside.** When everything is spent: stop and release the worker if one runs (and `stage-start.sh close`
it), set the row `set-aside` (keep its `stage`), add a `set-aside` item `<item> set aside: <one-line
reason>` with `step: <step>` and `review: <path>` when there is one, and carry on with everything else.
Leave its PR open: it is STAR's own, and the owner may want it. The reason is one line: "executor failed 3
times", "NOT-SAFE again after a re-scope", "<base> → <owner branch> is yours". `try again` puts the row in
the waiting state of the stage it stopped in, with `tries` and `rescoped` cleared. `drop` stops any worker,
row `dropped`.

**Re-scope.** The row goes to `inbox` with `counters.rescope=<review file name>`, `rescoped=+1`, `tries=0`.
Its next brief stage runs with `--rescope`, narrows the item to the part that passes, and reports `BRIEF …
rescoped=1 followup=<path>`. The narrowed item builds on the same branch and PR. Only quality failures
re-scope.

**Follow-ups.** A follow-up comes from a re-scope, a merge despite a check that is not the PR's fault, an
accepted residual, or an owner's overrule after a merge. It is the owner's own ask ("merge it and create a
follow up ticket"), so under `--unattended` filing it, writing the tracker status and posting a report
to the ticket STAR was handed need no confirmation (work-source.md §5 stays as it is by hand).

**A proven red check** is filed by STAR alone, after `MERGED`, once per check name per base branch: skip it when an
open ledger row or tracker item already covers `<check name> fails on <base branch>`. Workers write the proof line
and never file for it.

1. A ticket in the project's tracker through `references/work-source.md` (`create`): the same team and
   project as the parent item (the same repo for GitHub Issues), assigned to the account STAR acts as
   (`ghLogin`), the tracker's default status and no labels; the body links the parent item and the PR and
   gives the reason in one line. An item with no tracker (free text) gets a spec file instead:
   `HOME_DIR/items/<project>/<kebab name>.md` with `status: todo`, `title:` and the words.
2. A new `inbox` row for it (`ref` the ticket or the path, the parent's `batch`), with `counters.parent=<item>`
   and `counters.depth=<parent depth + 1>`.
3. When that depth would exceed `tries.followUpDepth`, the row is added and set straight to `set-aside` with
   the reason "follow-up depth <n> is past tries.followUpDepth", so the follow-up is filed and visible but
   not built: `try again` queues it.

An **accepted residual** is a build worker's question whether a criterion may ship with a residual it cannot
close (`juel:ship-ticket` Phase 6). It is STAR's call: accept when the evidence shows the criterion's intent
met and the residual can be an item of its own. Write the follow-up as above, append `### D<n> Accept a
residual on <criterion> (<date>, decided by STAR)` to `## Decisions` with the follow-up in `Consequences:`, and
reply with it. A residual that is most of the criterion is a re-scope instead.

**Handing a PR to a follow-up** (#159, #161). When findings left on a PR live only in a review file and their
fixes belong on that PR, the PR goes on under one follow-up row, never under a row whose `ref` is the review
file. `sh S/ledger.sh add rescopedFrom=<item> review=<the review path>` writes the item file (with
`existingPr:` when the parent has a PR), adds the row with `parent` and the batch, and moves the parent's
worktree to it. When the item file has `existingPr:`, the parent goes `dropped` ("<item>: continued by <name>
on <pr>" in the status line, and the same line in the parent's `## Decisions`). The follow-up's brief has
`rescopedFrom:`, so a cap on it sets it aside: one hand-over per PR. When it merges, its parent goes `done`
with it.

## Merge-gate verdicts

Each tick, every `verifying` row (past the `retry=` time in its `verify`) runs
`sh S/pr-verify.sh <pr url> --head <head> --merge-gate --brief <brief> --home HOME_DIR`, adding
`--hosted <hostedReviewer.login>` when `star.json`'s `hostedReviewer` is set and not paused. It prints one line.

| Verdict | Then |
|---|---|
| `PASS …` | `sh S/merge.sh <pr url> --head <head> --home HOME_DIR --item <item> [--hosted <login>]`, in the background like `stage-start.sh`, with `--hosted` exactly when it went to the gate. A note ending ` (proven not the PR's: <check> <cause>[, …])` means a red check that is not the PR's fault: remember it, and after `MERGED` file the follow-up below |
| no line, or an exit that is not 0 | as `PENDING script gave no verdict` |
| `PENDING approval: …` | add a `person` item of kind `approval` titled "approve PR #<n>" (GitHub never lets a PR's author approve their own PR); skip it while one is open for this head; `verify=retry=<now + 10 min>`. No try |
| `PENDING merge state: behind the base branch` | the sync rule below. No try |
| `PENDING hosted-status <check> missing on <sha>` | the hosted reviewer has no status on this head. When `## Decisions` has no line "the merge gate said: no <check> status on <sha7>", append it, row `babysit-queued` (it asks for a status refresh; with `refreshOutsideCap` false it reports `out-of-tries step=hosted-review`). When the line is there, spend a try and do the same |
| any other `PENDING <what>` | append "- <iso> the merge gate said: pending <what> at <sha7>" to `## Decisions` unless that line exists for this head; `verify=retry=<now + 2 min>`. When the line is more than 60 minutes old, spend a try at step `ci-wait` and send the row to `babysit-queued` |
| `PENDING gh cannot see <repo>…` | add a `person` item of kind `access`: "gh cannot see <repo>: set tokenCmd in star.json to a command that prints a token for it". No try; the next check runs after the item is done |
| `MOVED <head>` | spend a try, row `babysit-queued` |
| `MERGED <sha>` | the PR is merged (by STAR's call or someone else's): `sh S/release-record.sh --home HOME_DIR --project <p> --item <i> --pr <url>`, row `done`, print the record's path. When the row's `parent` row is `dropped` and its `pr` is this PR, set that row `done` too |
| `FAIL closed` | stop and release any worker, row `set-aside` with "PR was closed without a merge" |
| `FAIL conflicts` | the sync rule below |
| `FAIL no codex PASS for <sha7>` | append "- <date> the merge gate said: no codex PASS for <sha7>; resume the gate loop on the existing PR" to `## Decisions`, spend a try, row `queued` |
| any other `FAIL <what>` | append "- <date> the merge gate said: <what>. Fix it on the PR." to `## Decisions`, spend a try, row `babysit-queued` |

`merge.sh` prints one line:

| Line | Then |
|---|---|
| `MERGED <sha>` | as the verdict `MERGED`; print it and push one notification, "merged <item>: PR #<n>". Run the gate at once, in this tick, for every other `verifying` row on that base |
| `FAIL head moved` | as the verdict `MOVED` |
| `FAIL live worker <dispatch>` | the row is in a worker stage, so its worker may still push (#80): append `<dispatch> stopped <iso>` to `processed.log`, `worker-stop`, `worker-release`, the close check, then row `babysit-queued` and run the gate again from a fresh READY |
| `FAIL settings: <why>` | add a `person` item of kind `access`: "star.json cannot be read: <why>". No comment was posted and nothing merged; the row stays `verifying` with `verify=retry=<now + 10 min>` |
| `FAIL owner branch <base>` | the PR targets a branch only the owner merges into: row `set-aside`, "<base> is an owner branch" |
| `FAIL merge methods: <method> not allowed` | add a `person` item of kind `access`: "allow <method> merges on <repo>, or change mergeMethod". The row stays `verifying` with `verify=retry=<now + 10 min>`; the gate and `merge.sh` run again after that |
| `PENDING check <name> not reported` | a required check has not reported on the head; nothing is wrong. `verify=retry=<now + 2 min>`. No try |
| `FAIL ledger: <why>` | STAR's own bug, nothing on the PR is wrong: file an improvement issue and `verify=retry=<now + 10 min>` |
| `FAIL comment: …` or `FAIL merge: …` | spend a try, `verify=retry=<now + 10 min>`; at `tries.perStep` the row is set aside |
| exit 64 | `merge.sh` refused its arguments: file an improvement issue, change nothing |
| no line, or another non-zero exit | the merge may or may not have happened: change nothing; the next gate prints `MERGED` when it did |

Any verdict other than `PENDING` ends a pending wait. **One merge per base at a time** (#75, #93): `merge.sh`
runs in the background, so two `PASS` rows on one base would race and GitHub would refuse the second as
behind. While a `merge.sh` for a base runs, no other row on that base starts one. Among the rows on one base
that pass in a tick, merge first a row with no hosted pass left (`grep -cE '^[^ ]+ pass [0-9]+ head='
HOME_DIR/reviews/<project>/<item>-hosted.log` prints `hostedReviewer.maxPasses` or more: it cannot take another
review run, so it must not be the one left behind), then the oldest `updated`.

**Sync after the base moved.** `FAIL conflicts` or `PENDING merge state: behind the base branch` means the base
moved since babysit last merged it in, most often because STAR merged a sibling PR. Read the base's head:
`git -C <project.repo> ls-remote <project.remote> refs/heads/<the brief's baseBranch>`, first 7 characters.
When `## Decisions` has no line "synced with <base> at <sha7>", append it and send the row to
`babysit-queued` (it resumes with `--since <cursor>`; its Phase 4 merges the base in and resolves the
conflicts itself, spec section 7). This spends no try. When the line is there, syncing did not help: spend a
try and do the same; at `tries.perStep` the row is set aside. `pr-verify.sh` reports behind only when the base requires branches to be up to date (`review-rule.sh` prints `strict`, or the rule cannot be read).

## Report items

A brief with `deliverable: report` (a QA run, an impact map, a PR assessment, a status) ships a report, not a
PR. The build is the same `ship-ticket` command; it writes `HOME_DIR/reports/<project>/<item>.md` and
reports `REPORTED`. The row goes to `post-queued`, with no accept step: a post worker posts the report as one
comment on the ticket STAR was handed (`references/post-worker.md`) and reports `POSTED`; the row goes `done`
and the tracker status becomes Done. No release record is written. `sort-memory-notes` is the one report with
no ticket: its row goes `done` with no post, and STAR tells the owner in the dashboard chat where the proposal
is and that `sh S/notes.sh --shelf memory --project <project> apply <path>` applies it. STAR never applies it unread; the owner saying "apply it", in chat or the terminal, is the owner having
read it.

## The tracker status

STAR is the one writer of a work item's status; no worker under STAR writes it.

| Row state | Status |
|---|---|
| `queued` | Todo |
| `building`, `post-queued`, `posting` | In Progress |
| `babysit-queued`, `babysitting`, `verifying` | In Review |
| `done` | Done |
| `inbox`, `briefing`, `needs-you`, `set-aside`, `dropped` | not written |

At the end of every tick compare each row's status with its `counters.tracker=` and write only where they
differ, through the source in the item's brief (`item.source`, `item.ref`):

| Source | Write |
|---|---|
| `linear` | `<LINEAR_PREFIX>save_issue(id: <ref>, state: <the team's state of that name>)` |
| `github` | `gh label create status:in-progress --force` and `status:in-review` once, then `gh issue edit <n>` adding the status's label and removing the other. Done: nothing for a merged PR (its `Closes` does it), `gh issue close <n>` for a report item |
| `jira` | the transition named by `config.tracker.statusMap`, through the connected Jira or Atlassian MCP |
| `mcp:<type>` | `<TRACKER_PREFIX>update_work_item`, setting the status to the name `config.tracker.statusMap` gives, else the status itself |
| `file` | the spec file's marker: `todo`, `in_progress`, `in_review`, `done`; never a path under `HOME_DIR/reviews/` |

Each write sets `counters.tracker=<status>` and appends `<iso>\tSTAR\t<item>\tstatus <status>` to `sent.log`.
A write that fails sets `counters.tracker=!<status>` and is tried again only when the row's status changes;
the status line names it. Nobody is asked.

**A split keeps the tracker link** (#172). The parts of a split tracker item carry `counters.trackerRef=<parent
ref>`. The parent's status is written from its parts, through the project's tracker: In Progress while any
part builds, In Review while any part is in review, Done once every part is `done` or `dropped`. The parent's
own row is `dropped`, and `counters.tracker` on the first part that carries the ref records what was written.

## Watching a running worker

Each tick, Housekeeping probes every row in a worker stage that has not reported this tick (a `building` row
whose `verify` holds `retry=` has reported: skip it), and so does the start's reconcile:
`sh S/worker-probe.sh <dispatch> --item <item> --home HOME_DIR --worktree <worktree> --deadline <progressDeadlineMin>`
(no `--worktree` for a `briefing` or `posting` row). It reads the worker's screen and progress and prints one
line, so none of that enters STAR's context. STAR never answers a worker's screen for it, with one exception
(`prompt bounded`). A ` holds-screen <m>` ending goes in the status line (`screen: <item> <m> min`).

STAR remembers what it sent a worker in `sent.log`, not in counters: one line per nudge,
`<iso>\tSTAR\t<item>\tcheck-in`, `retry-nudge` or `answered a permission prompt (<path>)`.

| Probe line | Then |
|---|---|
| `ok` | nothing |
| `quiet <m> <terminal>` or `stale <m> <terminal>` | the worker runs but shows no progress. With no `check-in` line for this item in the last 15 minutes, send one: `orca terminal send --terminal <terminal> --text "STAR checking in on <item>: say in one line where you are. Waiting on a background command: keep waiting. Blocked or unsure: ask me with orca orchestration ask. Finished: send your worker_done report now." --enter --json`, and log it. Orca answering `agent_prompt_blocked` means the worker is mid-turn, not idle: it was no nudge, log nothing. A `check-in` 15 minutes or more old and the probe still `quiet` or `stale`: a lost worker, below |
| `prompt bounded <terminal> <path>` | Claude Code's safety prompt for an `rm` or `rmdir` whose every operand is inside the item's worktree or a session scratchpad. Send `orca terminal send --terminal <terminal> --text "1" --json` (no `--enter`: the digit picks the option, and an Enter could answer what comes next), log it, and append "- <date> STAR answered a permission prompt for the <stage> worker: Yes (<path>)" to `## Decisions`. After three of these for the item, treat the next as `stuck` |
| `stalled: model at capacity` or `stalled: api error` | send `orca terminal send --terminal <terminal> --text "STAR: the model was at capacity. Retry now." --enter --json` (for an API error: "STAR: your last model call failed with an API error. Continue where you stopped; a background command you started may still be running, so check it before you start it again."), log a `retry-nudge`. After three, a lost worker |
| `stuck: login` | the worker sits on Claude Code's login screen, most often after an account switch logged every session out. Check `claude auth status >/dev/null 2>&1` from the project folder. It fails: keep the worker, add one `person` item of kind `screen` "the Claude login is lost: run /login in any Claude Code session of this profile" (one for every row; when it is open add nothing), close it on the first tick the check passes. It passes: a lost worker, but spend no try. When every probe this tick says `stuck: login`, the status line says so and the item's title ends ` (machine-wide login loss)` |
| `stuck: usage limit` | a lost worker at step `worker` |
| `stuck: <what>` (any other) | stop the worker, release it, close the check, and spend a try at step `screen`; the row goes to its waiting state |
| `settled <state> [<reason>]` | its report is in the run's inbox and the Messages step applies it. If this tick's Messages step processed no report for that dispatch, a lost worker. `agent_prompt_stalled` (the worker never took its prompt, most often a trust dialog) is a try at step `screen` |
| `gone` | Orca has no such worker (an Orca restart): a lost worker |
| `unknown <why>` | says nothing about the worker, including empty or unreadable Orca output: keep the row and probe again next tick; it never justifies a restart |
| `gate-gone r<k>` | gate round `k`'s process died while no verdict file exists and the worker still waits. Spend a try at step `worker` and send `orca orchestration send --to dispatch:<dispatch> --subject "STAR" --body "The gate process for round <k> died with no verdict. Run round <k> again." --json` |

**A lost worker.** Append `<dispatch> stopped <iso>` to `processed.log`, then `orca orchestration worker-stop
--dispatch <id> --json`, `worker-release`, and `sh S/stage-start.sh --home HOME_DIR close <dispatch>`. Spend a
try at step `worker`, set `restarts` to its old value plus one, and put the row in its stage's waiting state
(babysit resumes with `--since <cursor>`); a stage that has used `tries.perStep` is set aside with "worker lost
<n> times". A lost build restarts on its worktree and branch as they are; STAR never cleans or discards what a
dead run left, and the new run sees it. Append "- <date> STAR restarted the <stage> worker at <step>:
<diagnosis>. Resume on the existing branch and PR." to `## Decisions` when the brief exists, and say
"restarted <item>" in the status line. A `verifying` row has no worker: never restart it.

A stopped worker is put on record first (the `stopped` line above), so a message from that dispatch is written
to `processed.log` and changes nothing else, also after a restart.
