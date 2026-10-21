# The tick: what STAR does each time it wakes

Read this at the start of every tick you have not run before in this session, and whenever a step below is
in doubt. A tick is short and does the same seven things in the same order, so a compacted STAR resumes from
the files.

## Rules that hold for the whole tick

- **Never call AskUserQuestion** once a worker exists. Orca types its nudge into this terminal, and a nudge
  that lands on an open picker answers it with the first option (#29). STAR asks nothing in a tick: the
  only questions are `person` items in the queue, and the owner's answers arrive in the file or as an
  ordinary message.
- **Persist before acting.** Every ledger write goes through `ledger.sh`. `stage-start.sh` writes the row
  before `task-create` (state, stage, round), the task id right after it and the dispatch id right after
  `worker-start`. Write the row right after each message's transition, then append the message to
  `processed.log`, and only then acknowledge the delivery. A message already in `processed.log` is skipped.
  Every row write a message causes also sets `last=<message id>`; a message whose id is already the row's
  `last=` is applied: do not match it again, count nothing, do only what comes after the row
  (`worker-release`, `processed.log`, the ack). That is what makes a replay safe.
- **Match by dispatch, not by name.** A message belongs to the row whose `dispatch` cell equals the message's
  dispatch id (the third field of its `msg` line); the `item=` in its first line must then be that row's
  item. A message changes no row, and is only named in the status line, when its dispatch is in no row (or
  has none), when its row is `done` or `dropped`, or when the row has moved on to a newer dispatch. Three
  things change nothing and are not named: a message already applied, the `worker_done` of a dispatch STAR
  stopped itself, and a `worker_done` from a dispatch `processed.log` lists as `released`. Write those to
  `processed.log`, acknowledge, nothing else.
- **One message, one order of effects:** queue items first (`loops.sh add` returns the open item's id when it
  is already there), then `NOTE` and `SENT` appends (each line carries the time the message was sent, so a
  replay writes the identical line: skip one the file has), then the row with its `last=`, then for a settled
  `worker_done` `worker-release` and the close check, then `<dispatch> released <iso>` in `processed.log`,
  then the message's own line, then the ack. A stop anywhere in that order replays into the same end state.
- STAR reads at most 12 lines of a report. It never opens a review, evidence, log or diff file and never
  reads a worker's screen: scripts do that and give one line back.

## 0. Still STAR?

Re-read `terminal` in `star.json`. When it is not this session's `$ORCA_TERMINAL_HANDLE`, this session is no
longer STAR: delete its own heartbeat job (find it with `CronList` by its prompt: the id in `star.json`
belongs to the other session), do nothing else (no slot, no ledger write, no ack), say "STAR now runs in
<handle>" and end the turn. This check is what makes one STAR per home hold however two sessions raced.

## 1. Inbox

Read `HOME_DIR/inbox/*.md` in file-name order (the names start with a UTC time). The formats are in
`references/dashboard.md`. For each file:

- `control: away`, `control: back` or `control: stop` is that command (`references/dashboard.md`,
  `references/recovery.md`): run it and delete the file in the same step.
- A file for another repository (its `repo:` is not `project.repo`) is not ingested; leave it and say so in
  the status line once.
- Refs and text. No `project.orcaRepo` yet: look the repo up in `orca repo list --json`; not found → the
  status line says "register this repo with Orca: orca repo add" and the files wait. Otherwise run
  `sh S/star-home.sh import <ref>` on every spec-path ref (it holds a `/` or ends in `.md`) and use the path
  it prints, so a row's `ref` never names a folder that can vanish (#125); a non-zero exit adds no row and
  the status line names it. Then one `inbox` row per ref with its item name (`ledger.sh name`), skipping a
  ref that already has an open row. A `text:` block is a free-text brief: write each distinct piece of work
  as a spec item, `HOME_DIR/items/<project>/<kebab name>.md` (`status: todo`, `title:`, then the words,
  verbatim), and add it as an `inbox` row. Split only where the text plainly lists separate pieces; when in
  doubt it is one item and its brief worker can report `SPLIT`. Every row from one file gets
  `counters.batch=B-<the file's name without .md>`. Write the ledger, then delete the file.
- A `slack:` block is a message the dashboard's watcher routed here, not a work item. STAR never writes reply
  text. Run `sh S/slack-handled.sh --home HOME_DIR <id>`: `handled sent|drafted <name>` → delete the file,
  nothing else; `queue <draft path>` → the draft exists but its item does not: add the `slack-reply` item
  (`references/state.md`), its Suggest line the draft's second line, or `no draft: <why>` when the draft
  holds only its first line; `new` → no draft file: write its first line `to: slack <channelId> <threadTs>` to
  `HOME_DIR/drafts/<date>-<project>-slack-<id>.md` and queue the no-reply item. Anything else: leave the file
  and say so. Delete the file only after `loops.sh add` printed the item's id.
- A `chat:` line is the owner talking to STAR from the dashboard. See `references/dashboard.md`.

## 2. Answers

`sh S/loops.sh answers` prints one line per answered item. Act, then `loops.sh close <id>` (exit 4: already
closed). A command word counts only when it is the whole answer: lower-case it, strip punctuation at its two
ends only (`can't now` keeps its apostrophe), drop a trailing ` (recommended)`, and compare. Anything longer
is a decision in words. An answer with no letter or digit is not an answer: add the item again with "(answer
in words)" at the end of its title. Before acting, re-read the row the answer names: a row that is `done` or
`dropped` takes no answer (close the item). A row in a worker stage whose probe says `settled` has a report
not yet applied: leave the answer for the next tick.

| Kind | Answer | Action |
|---|---|---|
| `person` | `done`, `yes`, `ok`, `approve`, or words that supply what was asked | append `- <date> person-only step (<kind>): <title> → <answer>` to the row's brief `## Decisions` (and to each brief named on an `also:` line), write a note (`notes.sh add --kind fact --source owner`) so the question never comes back, close the item. When the row is `needs-you` and none of its `person` items is open, it goes to the waiting state of its `stage` |
| `person` | `can't now` or `no` | append the same line ending `→ can't now (<N-id>)` unless the brief has it, and leave the item open with the answer on it. The row stays `needs-you`. STAR never asks it again, and skips this item's answer on later ticks |
| `person` | words that decline the step ("I don't want to install it") | it is feedback on the brief: append `- <date> person-only step declined: <title> → <answer>` under `## Feedback`, close the item, close the row's other open `person` items, row `inbox`: the brief stage plans without the step (`--feedback`) |
| `set-aside` | `try again` | the row goes to the waiting state of its `stage` with `tries` and `rescoped` cleared, `restarts` set to 0 |
| `set-aside` | `drop` | stop any worker (stop, release, close check), row `dropped` |
| `set-aside` | anything else | the answer is a decision: append it to the brief's `## Decisions` with the date, then as `try again` |
| `slack-reply` | `send` | a draft with nothing after its first line has no reply: close the item and add it again with ` (no reply to send: answer rewrite: <how> or skip)` on its title. Otherwise load the Slack MCP's send tool with `ToolSearch`; none loaded → keep the item open and say "connect Slack in Claude Code to send <draft name>" in the status line. When `sent.log` already has `<iso>\tSTAR\tslack\tslack reply <draft name>` the reply was posted: just close the item. Else post everything after the draft's first line as the owner, in its channel, as a thread reply to the `ts` on the first line, then append that `sent.log` line, then close. A post that fails writes nothing and keeps the item open with the reason in the status line |
| `slack-reply` | `rewrite: <how>` | STAR never writes reply text: the drafter does. When `grep -lx 'loop: <id>' HOME_DIR/slack/redraft/*.md` finds a request, do nothing. Otherwise close the item and add it again unanswered with the same lines and ` (redrafting)` on its title, then `sh S/slack-redraft.sh --home HOME_DIR --draft <draft path> --loop <the NEW item's id> --how "<how>"`. Exit 65 (the draft was removed) → keep the new item and say so |
| `slack-reply` | `redrafted` | close it and add it again with the same `draft:` and `message:`, its title without ` (redrafting)` or ` (redraft failed: …)`, Suggest the draft's new second line (`sed -n 2p <draft path>`) and `Options: send (recommended) / rewrite: <how> / skip` |
| `slack-reply` | `redraft failed: <why>` | close it and add it again with ` (redraft failed: <why>)` on its title in place of ` (redrafting)` |
| `slack-reply` | `skip`; anything else | close; anything else is added again with "(answer send, rewrite: <how> or skip)" on its title |
| `draft` | `send` | a draft whose first line is `to: pr <url>` is posted with `gh pr comment <url> --body-file <the rest>`, after appending `<iso>\tSTAR\t<item>\tposted draft N-<id>` to `sent.log` (when that line is already there, only close). Any other draft is the owner's to send: say so |
| `draft` | `done`, `skip`, `drop`, anything else | close it. Nothing changes on any row |

A worker that is still running when its row's answer arrives never gets a second worker: a `drop` stops it
first; any other answer for a running row is appended to the brief's `## Decisions` and sent with
`orca orchestration send --to dispatch:<id> --subject "decision" --body "<answer>" --json`, and the row stays.
A `briefing` row's answer goes to the brief's feedback side file (`references/dashboard.md`).

## 3. Messages

Only while work is active (the end of this file). The wait runs in the background, so a chat message, a nudge
or the owner's words reach STAR within seconds.

**A wait that finished.** When this tick was woken by a wait's completion notification, or one arrived since
the last tick, read that wait's output (the background command's own lines, never a log): `delivery <id> <n>`,
then each message as `msg <id> <type> <dispatch> <sent> [deadline=<iso>]` with at most 12 body lines indented
by two spaces (`cut <n>` after them), or `none`. Heartbeats and processed messages never appear. Apply each by
`references/stages.md` ("Report lines and STAR's response"), in the order of effects above. A wait that
printed no line or exited non-zero has nothing to apply.

**The next wait, never a second one.** Run `sh S/messages.sh --home HOME_DIR --waiting`: it prints `waiting
<pid> <since>` while a wait is outstanding, else `none`. Only on `none` start `sh S/messages.sh --wait
--timeout-ms 540000` with the Bash tool's `run_in_background: true`. Once every message of a delivery is in the
ledger and `processed.log`, the next wait is `sh S/messages.sh --ack <delivery> --wait --timeout-ms 540000`
(or `--ack <delivery>` alone when STAR is about to go idle). On `waiting …` start nothing: the outstanding
wait brings the messages. Never two waits at once, never a foreground wait, never a poll or a Monitor on it:
its completion notification wakes STAR. `waiter-exists <pids>` means orphaned waits hold the run's waiter
(#38): `kill` each pid and start the wait again; `waiter-exists -` twice in a row is `unknown <why>` and files
an improvement issue. `unknown <why>` is a tick, named in the status line.

## 4. Fill slots

First the PR check. For every row that has a PR and is `queued`, `building`, `babysit-queued`, `set-aside`
or `needs-you`: `sh S/pr-verify.sh <pr url> --head <head, or 0000000 when none is recorded>`. Only two answers
matter. `MERGED <sha>`: the owner merged early. Stop the row's worker if it has one (record, stop, release,
close check), then handle it as the verdict `MERGED` (`references/stages.md`). `FAIL closed`: stop and
release the worker, row `set-aside` with "PR was closed without a merge". Every other answer is ignored here.
So no slot ever goes to an item whose PR is already merged or closed.

A `needs-you` row with no open `person` item (an item closed by hand, or lost) goes back to the waiting
state of its `stage`. While `gateDown` is set start no build and no babysit; brief and post stages still
start. While `hostedDown` is set start no babysit. A `queued` row whose brief has a `hold:` line is skipped;
the owner's order waits by itself, and a chat message "lift the hold on <item>" deletes the line.

Then, for each free slot, the row next in line (pools: `references/state.md`): `sh S/stage-start.sh
[--home HOME_DIR] <stage> <item>`, run with `run_in_background: true`. Act on its line as
`references/stages.md` ("Starting a stage") says. A `queued` row starts only when every item its brief's
`blockedBy` names is `done` or `dropped` (#37) and its `notBefore` has passed (#87); `stage-start.sh build`
checks both and prints `wait until <iso>` before then. A row waiting on a blocker is named in the status line.

## 5. Housekeeping

- **Probe** every worker row (`references/stages.md`, "Watching a running worker") and act on the line.
- **`verifying` rows** past their `retry=` time: the merge gate. **`building` rows** past the `retry=` time in
  `verify` (a `DONE` that `done-check.sh` could not check yet): `done-check.sh` again with the row's PR and
  head, acted on as the `DONE` row says.
- **`gateDown`** set and its `checked` 30 minutes old: `sh S/codex-gate.sh check`. **`hostedDown`** set for 30
  minutes: set it to null; "Fill slots" starts the parked babysits.
- **A tracker status** that differs from `counters.tracker`: write it (`references/stages.md`).
- **Notifications**, below. **Improvement issues**, below.
- **Finished worktrees.** Each `done` or `dropped` row that still has a worktree gets `sh S/worktree-clean.sh
  <item>`. It removes the worktree only when nothing in it would be lost (clean, and its work on the remote or
  merged), after copying every evidence folder to `HOME_DIR/evidence/<item>/` (it prints `kept-evidence <path>`
  first: name it). `removed <path>` → name it. `kept <path>: <why>` → name it in the status line; STAR does not
  retry by itself and nobody is asked. `reviews-gzipped …` needs nothing. `set-aside` rows keep their worktrees.
- **Away.** `sh S/handoff.sh --home HOME_DIR summary --if-due`. It prints `not-due` or `unchanged`, or wrote a
  summary. Nothing more to do in any case.
- **A queue `missing` line** from `loops.sh list`: say so in the status line and add again any ask a row still
  needs (a `needs-you` row with no open item, a set-aside row with no item).

## 6. Write

`loops.sh resume --state running --run <id> --pools "brief <n>/<max> · build <n>/<max> · babysit <n>/<max>"
--next "<one line>"` and `loops.sh waiting "<one line per PR in review>"`. Nothing is committed: the folder
is plain files. Print one status line: counts per state, every open queue item (id and title), `screen:
<holder>, renewed <time>` while `sh S/../ship-ticket/screen-lock.sh status` does not print `free`, `gate down
since <since>` while `gateDown` is set, each restart (`restarted <item>`), each `closed` or `kept` terminal
line and each issue filed ("filed issue #19").

## Active or idle

Work is active while any row is in `inbox`, `briefing`, `building`, `babysit-queued`, `babysitting` or
`posting`, in `verifying` while its `verify` holds no `retry=` in the future, in `queued` or `post-queued`
while it may start, or while `gateDown` or `hostedDown` is set. While work is active, every tick ends with a
message wait outstanding in the background and STAR ends its turn. The wait's 9-minute timeout is the clock:
its notification wakes STAR for the next tick, and a wait that ends with `none` is a tick too, so
Housekeeping runs at least every 9 minutes. Any other wake (an Orca nudge, `inbox` from a hand-over or the
dashboard, a chat message, the heartbeat, the owner typing) runs one tick and starts no second wait. When
every row is waiting on the owner or finished, write `state: idle`, start no wait, and end the turn; a hand-over
nudge, the owner or the heartbeat wakes it. A `queued` row waiting for its `notBefore` is not active work, and
nothing ticks once the session is closed: when STAR writes `state: idle` while queued rows wait only on blockers, a date or the
host gate, the status line ends with `; <n> items wait (<item> on <blockers>, <item> until <date>): keep this
session open or they wait until /juel:star runs again`.

## Notifications

`star.json` keeps `"notified"`, the ids of open queue items the owner has been told about. At the end of a
tick, when `loops.sh list` shows open items not in it, print them, send one push notification naming them
(Claude Code's `PushNotification` tool, loaded with `ToolSearch` when deferred; printing is enough when it
does not exist) and add their ids. Ids no longer open are dropped. While the owner is away only `person` items
notify; the rest wait for the first tick after they are back. A merge is announced as it happens: STAR prints
it and sends one notification, "merged <item>: PR #<n>".

## Improvement issues

STAR files an issue against itself, in the plugin's own repository, whenever a STAR script fails outside its
documented exits or prints a line this skill has no rule for; Orca, `gh` or a worker behaves differently than
the skill says; STAR had to improvise (no rule fits, two conflict, or it did by hand what a script should); a
rule change would have saved a stop; or a worker reported `STAR-ISSUE: <one line>`.

1. `sh S/star-issue.sh find "<a few words>"` lists open issues that may be the same finding. When one is,
   `sh S/star-issue.sh comment <n> --fingerprint <fp> --body-file <f>` adds the evidence; otherwise `sh
   S/star-issue.sh file --fingerprint <fp> --title "star: <what is wrong>" --label bug|enhancement
   --body-file <f>`. `<fp>` is a short kebab-case name; one STAR never posts the same fingerprint twice.
2. The body, written to `HOME_DIR/drafts/<date>-issue-<fp>.md`: **What happened**, **Expected**, **Repro**,
   **Versions** (juel from `plugin.json`, `orca --version`, the agent CLIs'), **Suggested fix**. The repository
   is public: describe STAR's behaviour only, with `<project>`, `ITEM-1`, `<repo>` and `<app>` in place of
   every name, and never ticket text, code, diffs, secrets or people. `star-issue.sh` refuses (exit 65) a
   title or body that still names the project, an item, a ref, the repository or a home path.
3. `failed <why>` (no `gh`, no access): queue the body as a `draft` item "STAR issue: <title>".

Filing never delays a tick's real work: it runs in Housekeeping, after the slots are filled, and name each
issue in the status line.

## The host gate

`stage-start.sh` checks the machine before every start against `star.json`'s `hostGate`: `minFreeGB`,
`maxAgents`, `maxSwapGB` and `minDiskGB`. Memory is free plus inactive from `vm_stat` (the `available` column
of `free -g` on Linux); agents are the running `claude` and `codex` processes of every project; swap is the
`used` figure of `sysctl -n vm.swapusage`; disk is the free space on the volume that holds STAR's folder. The
first limit that fails prints `hold <what> <value>`. Heavy test and build gates inside workers take turns
through `juel:ship-ticket`'s `gate-lock.sh`, one lock per user for the whole machine, so workers in different
projects wait for each other too. STAR never raises its slots unasked: heavy runs side by side can take the
machine down. `caffeinate` is macOS only.
