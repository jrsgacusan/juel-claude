#!/bin/sh
# Guards on skills/star/SKILL.md: the permanent local coordinator.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/star/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
# has <name> <text>: the text is in $SKILL once line breaks and repeated spaces are folded
has() { tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qF -- "$2" && pass "$1" || fail "$1"; }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }
[ -d "$ROOT/skills/ship-tickets" ] && fail "ship-tickets removed" || pass "ship-tickets removed"
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
grep -q '^name: star$' "$SKILL" && pass "name" || fail "name"
grep -q 'juel:protocol v9' "$SKILL" && pass "protocol block" || fail "protocol block"
for id in orca-terminal git-repo; do grep -q "id: $id" "$SKILL" && pass "requires $id" || fail "requires $id"; done
for m in '`/juel:star SPH-11 and SPH-12`' '`/juel:star status`' '`/juel:star stop`' 'draft-brief <ref> --project <name> --out <path>'; do
  grep -qF -- "$m" "$SKILL" && pass "mode $m" || fail "mode $m"
done
for s in inbox briefing brief-ready queued building babysit-queued babysitting verifying reported post-queued posting done escalated failed dropped; do
  grep -q "\`$s\`" "$SKILL" && pass "state $s" || fail "state $s"
done
for c in 'loops.sh' 'pr-verify.sh' 'worker-probe.sh' 'release-record.sh'; do
  grep -q "$c" "$SKILL" && pass "uses $c" || fail "uses $c"
done
for k in go-batch person go-merge accept-report escalation question restart-or-drop draft held; do
  grep -q -- "--kind $k" "$SKILL" && pass "queue kind $k" || fail "queue kind $k"
done
grep -q 'briefs/<project>/<item>.md' "$SKILL" && grep -q 'reviews/<project>/<item>-r<k>.md' "$SKILL" && pass "paths keyed by project" || fail "paths keyed by project"
grep -q 'star-home.sh init' "$SKILL" && pass "the folder is created by star-home.sh" || fail "star-home.sh init"
grep -q 'orca terminal send --terminal' "$SKILL" && pass "add nudges STAR" || fail "add nudge"
grep -q 'Refs given while STAR is stopped' "$SKILL" && pass "refs given while STAR is down start it" || fail "refs when STAR is down"
grep -q 'at most 12 lines' "$SKILL" && grep -q 'never opens a review' "$SKILL" && pass "STAR reads one line, never the files" || fail "small-context rule"
grep -q 'NOTE:' "$SKILL" && grep -q 'memory/<project>.md' "$SKILL" && pass "notes appended to project memory" || fail "memory notes"
grep -q 'state: idle' "$SKILL" && grep -q 'ends its turn' "$SKILL" && pass "idle ends the turn" || fail "idle rule"
grep -q 'restart-or-drop' "$SKILL" && grep -q 'restarts once' "$SKILL" && pass "restart recovery" || fail "restart recovery"
! grep -q 'git -C HOME_DIR' "$SKILL" && ! grep -q 'git init' "$SKILL" && pass "STAR's files are not a git repo: no commit step" || fail "commit step still there"
grep -q 'silence means missed' "$SKILL" && pass "open items repeated" || fail "repeat rule"
grep -q -- '--timeout-ms 540000' "$SKILL" && pass "bounded waits" || fail "bounded waits"
grep -q '"maxParallel": 3' "$SKILL" && grep -q '"maxInReview": 3' "$SKILL" && pass "pool defaults" || fail "pool defaults"
grep -q 'free + inactive' "$SKILL" && pass "memory check" || fail "memory check"
grep -q 'processed.log' "$SKILL" && grep -q 'Write the whole ledger right after each message' "$SKILL" && pass "persist before act" || fail "persist before act"
grep -q 'Never call AskUserQuestion' "$SKILL" && pass "never blocks on a question" || fail "non-blocking"
grep -qF '**Merge only through `merge.sh`**' "$SKILL" && pass "STAR merges only through merge.sh" || fail "merge rule"
grep -q '`star`' "$ROOT/README.md" && pass "README row" || fail "README row"
grep -qE '(^|[^-])ship-tickets' "$ROOT/README.md" "$ROOT/skills/ship-ticket/SKILL.md" "$ROOT/skills/babysit-pr/SKILL.md" "$ROOT/skills/receive-review-and-execute/SKILL.md" && fail "no ship-tickets references left" || pass "no ship-tickets references left"

# Team test pass fixes
grep -q 'Every transition into `escalated` or `failed` queues' "$SKILL" && pass "F1 no stranded rows" || fail "F1 stranded rows"
grep -q 'git check-ignore' "$SKILL" && grep -q 'only files git ignores' "$SKILL" && pass "F6 copy keeps the tree clean" || fail "F6 copy step"
grep -q -- 'messages.sh --ack <delivery> --wait' "$SKILL" && pass "F4 deliveries acknowledged" || fail "F4 ack"
grep -q 'issue-<n>' "$SKILL" && grep -q -- '--item <name>' "$SKILL" && grep -q '| item | ref | project |' "$SKILL" && pass "F5 one item name everywhere" || fail "F5 item naming"
grep -q '## Decisions' "$SKILL" && grep -q -- '--feedback' "$SKILL" && pass "F7 answers reach the restarted stage" || fail "F7 decisions"
grep -q 'cursor=<cursor>' "$SKILL" && grep -q 'MERGED item=' "$SKILL" && pass "F7/F8 escalation cursor and worker-seen merges" || fail "F7/F8 cursor, MERGED"
grep -q '`gone`' "$SKILL" && grep -q 'three ticks in a row' "$SKILL" && pass "F2 gone and unknown handled" || fail "F2 probe results"
grep -q 'A `verifying` row has no worker' "$SKILL" && pass "F8 verifying rows are re-checked, not restarted" || fail "F8 verifying reconcile"
grep -q 'orca orchestration ask' "$SKILL" && pass "F16 workers ask through Orca" || fail "F16 worker asks"
grep -q 'msg: <id>' "$SKILL" && pass "F15 question keeps its message id" || fail "F15 msg id"
grep -q 'never overwrite an existing inbox file' "$SKILL" && grep -q 'git worktree list --porcelain' "$SKILL" && pass "F11 unique inbox files, real main checkout" || fail "F11 inbox"
grep -q 'exactly `go`' "$SKILL" && pass "F18 a go is exact" || fail "F18 exact go"
grep -q 'HH:MM-HH:MM@tz' "$SKILL" && pass "F19 quiet-hours rendering" || fail "F19 quiet hours format"
grep -q 'moved=' "$SKILL" && grep -q 'mergefail=' "$SKILL" && pass "F18 moved and mergefail counters" || fail "F18 counters"
# Handoff: away, night summaries, back
grep -qF '`/juel:star away`' "$SKILL" && grep -qF '`/juel:star back`' "$SKILL" && pass "away and back commands" || fail "away/back commands"
for c in start due summary end; do grep -q "handoff.sh --home HOME_DIR $c" "$SKILL" && pass "uses handoff.sh $c" || fail "uses handoff.sh $c"; done
! grep -q -- '--quiet-hours always' "$SKILL" && grep -q 'Away holds no work' "$SKILL" && pass "away holds no work; quiet hours hold what goes out" || fail "away rule"
grep -q 'sent.log' "$SKILL" && grep -q 'SENT ' "$SKILL" && pass "messages sent are logged" || fail "sent log"
grep -q 'in the same turn' "$SKILL" && pass "chat answers are relayed in the same turn" || fail "same-turn relay"
grep -q 'control: away' "$SKILL" && pass "away works from any session" || fail "away from anywhere"
grep -q 'one place to answer' "$SKILL" && pass "handoff never collects answers" || fail "single answer place"
# Stress test pass fixes
T="$ROOT/skills/star/template"
grep -q '| verify | counters | updated |' "$SKILL" && grep -q '| verify | counters | updated |' "$T/ledger.md" && pass "S12 counters have a ledger cell" || fail "S12 counters column"
left=""; for c in 'unknown=' 'silent=' 'hold=' 'moved=' 'pending=' 'capacity=' 'mismatch=' 'mergefail=' 'rescoped=1' 'rescope=<file>' 'batch=<id>' 'parent=<item>'; do grep -qF -- "$c" "$SKILL" || left="$left [$c]"; done
[ -z "$left" ] && pass "S12 every counter is named" || fail "S12 counters not named:$left"
grep -q '## Feedback' "$SKILL" && pass "S12 brief feedback is kept in the brief" || fail "S12 feedback storage"
grep -q 'One STAR per home' "$SKILL" && grep -q 'orca terminal list --limit 500 --json' "$SKILL" && pass "S2 one STAR per home" || fail "S2 second STAR not refused"
grep -q 'Match by dispatch' "$SKILL" && grep -q 'superseded' "$SKILL" && pass "S2 messages matched by dispatch id" || fail "S2 message matching"
grep -q 'the same item: no new row' "$SKILL" && pass "S10 a repeated ref is not a second item" || fail "S10 repeated ref"
grep -q 'named in another open row' "$SKILL" && pass "S10 a worktree is never shared by two rows" || fail "S10 shared worktree"
grep -q 'queue items first' "$SKILL" && pass "S2 one order of effects per message" || fail "S2 effect order"
grep -q 'worker-stop' "$SKILL" && grep -q 'never starts a second worker' "$SKILL" && pass "S18 answers never double a running worker" || fail "S18 answer on a running worker"
grep -q 'add the same `go-merge` item again' "$SKILL" && pass "S18 a merge question is not lost to a chat answer" || fail "S18 go-merge reminder"
grep -q 'PR was closed' "$SKILL" && grep -q '`babysit-queued`, `escalated` or `failed`' "$SKILL" && pass "S18 merged or closed PRs are noticed in every state, stopped rows included" || fail "S18 PR lifecycle"
grep -q 'must be clean' "$SKILL" && pass "S18 a restarted build needs a clean worktree" || fail "S18 dirty restart"
grep -q 'quiet-hours.sh' "$SKILL" && pass "S6 quiet hours are decided by the script" || fail "S6 quiet-hours.sh"
grep -q -- '--reviewed' "$SKILL" && grep -q 'VERDICT item=<item> round=<k> SAFE findings=<n> head=<sha>' "$SKILL" && pass "S5 babysit gets the SAFE review as proof" || fail "S5 SAFE proof"
grep -q '"notified"' "$SKILL" && ! grep -q 'notifiedThrough' "$T/star.json" && ! grep -q 'notifiedThrough' "$SKILL" && pass "S14 notifications tracked per item" || fail "S14 notified list"
grep -q 'memory below 3 GB' "$SKILL" && pass "S14 a long memory hold reaches the user" || fail "S14 memory hold"
grep -q 'plus 30 minutes' "$SKILL" && pass "S14 a question's deadline is set when it is asked" || fail "S14 question deadline"
grep -q 'another repository' "$SKILL" && pass "S17 an inbox file for another repo is not ingested" || fail "S17 project identity"
grep -q 'ESCALATION item=<name> phase=0 reason=needs-human-input' "$SKILL" && ! grep -q 'item=<ref> phase=0' "$SKILL" && pass "S11 brief escalations carry the item name" || fail "S11 brief escalation name"
grep -q 'first 12 lines' "$SKILL" && grep -q 'BRIEF-VIOLATION:' "$SKILL" && grep -q 'need no action' "$SKILL" && pass "S11 every report line has a rule" || fail "S11 report grammar"
grep -q 'A-Za-z0-9._-' "$SKILL" && pass "S1 item names are safe as paths" || fail "S1 item name rule"
grep -q 'no task' "$SKILL" && grep -q 'lost twice' "$SKILL" && pass "S18 rows that never started and second losses are defined" || fail "S18 reconcile gaps"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["notified"]==[]' "$T/star.json" && pass "template star.json has the notified list" || fail "template notified"
# Review of the stress fixes
grep -q 'A `question` is always answered with `reply`' "$SKILL" && grep -q 'An `escalation` answer for a row whose worker is still running' "$SKILL" && pass "R1 a waiting worker gets its reply, not a side message" || fail "R1 question vs running-worker rule"
grep -q 'creating the file with only that section' "$SKILL" && grep -q 'before step 2' "$SKILL" && pass "R2 a brief-stage answer reaches the step that asked" || fail "R2 brief escalation answer"
grep -q 'no-safe-verdict' "$SKILL" && grep -q 'resumes the gate loop' "$SKILL" && pass "R3 a head with no SAFE review goes back to the gate" || fail "R3 no-safe-verdict route"
# Second stress pass
grep -q 'last=<message id>' "$SKILL" && grep -q 'already applied' "$SKILL" && pass "T3 a replayed message is recognised by the row itself" || fail "T3 replay by message id"
grep -q 'cannot be read, STOP' "$SKILL" && grep -q 'read it back' "$SKILL" && grep -q 'take over' "$SKILL" && pass "T2 one STAR per home fails closed, with a way to take over" || fail "T2 coordinator lock"
grep -q 'a ref whose earlier row is `done` or `dropped`' "$SKILL" && pass "T4 a re-added ref gets its own name" || fail "T4 re-added ref"
grep -q -- '--project - --item' "$SKILL" && pass "T7 a message with no row has a place in the queue" || fail "T7 unmatched message"
grep -q 'strip punctuation' "$SKILL" && grep -q 'no letter or digit' "$SKILL" && pass "T16 answers are read without their punctuation" || fail "T16 answer punctuation"
grep -q 'clears every counter except `hold=`, `last=`, `start=`, `tracker=`, `batch=`, `rescoped=` and `parent=`' "$SKILL" && pass "T16 a retry answer clears the old counts" || fail "T16 counters on answer"
grep -q 'worker-stop' "$SKILL" && grep -q 'then `worker-release`' "$SKILL" && grep -q 'a dispatch STAR stopped itself' "$SKILL" && pass "T18 a stopped worker is released and its last report ignored" || fail "T18 stop then release"
grep -q 'Before filling' "$SKILL" && pass "T18 the PR check runs before slots are filled" || fail "T18 PR check order"
grep -q 'the time the message was sent plus 30 minutes' "$SKILL" && pass "T21 a replayed question is the same item" || fail "T21 question deadline"
grep -q 'posts at the first tick outside' "$SKILL" && pass "T12 STAR posts nothing in quiet hours" || fail "T12 draft in quiet hours"
! grep -q -- '--feedback "<' "$SKILL" && grep -q -- '\[--feedback\]' "$SKILL" && pass "T12 feedback travels in the brief file, not in the prompt" || fail "T12 feedback in the prompt"
grep -q '/tmp/juel.gate.<uid>.lock' "$SKILL" && ! grep -q 'HOME_DIR/gate.lock' "$SKILL" && pass "T1 the gate lock is one file per user" || fail "T1 gate lock path"
# The coordinator looks after its workers
grep -q '## Looking after the workers' "$SKILL" && grep -q 'STAR answers first' "$SKILL" && pass "STAR answers a worker's question itself when it can" || fail "STAR answers first"
grep -q 'quiet <minutes> <terminal>' "$SKILL" && grep -q 'nudge=' "$SKILL" && grep -q 'orca terminal send --terminal <terminal>' "$SKILL" && pass "STAR checks in on a quiet worker" || fail "check-in on a quiet worker"
grep -q 'STAR answered' "$SKILL" && pass "what STAR decided for a worker is on record" || fail "STAR's answers recorded"
grep -q 'Answer on' "$T/open-loops.md" && pass "the queue file says how to answer" || fail "template answer hint"
# Final pass
g() { grep -qF -- "$2" "$SKILL" && pass "$1" || fail "$1"; }
g "V1 away, back and stop are not a start" '`status`, `dashboard`, `away`, `back`, `stop`, `draft-brief` and `post-report` are not a start'
g "V3 every tick checks it still owns the home" "is not this session's handle"
g "V4 the heartbeat is renewed before it expires" 'heartbeatAt'
g "V5 a lost build leaves its pool" 'and set the row to `failed`'
g "V6 a stop or away request is written down at once" 'control: stop'
g "V7 a command word counts only when it is the whole answer" 'the whole answer'
g "V8 the reply goes out before the row is marked" 'the `reply`, then the row'
g "V9 a worker is released before the message is marked done" '`worker-release`, then `processed.log`'
g "V10 a resume does not spend the pending retry" 'its `retry=` time has passed'
g "V11 an answer waits for the report that raised it" 'leave its answers for the next tick'
g "V12 a draft is posted once" 'posted draft N-'
g "V13 a worker STAR stopped is on record" 'stopped <iso>'
g "V14 a re-added item gets its own branch" 'the same suffix'
g "V15 a quiet or stale worker is still a running worker" '`ok`, `quiet …` or `stale …`'
g "V16 a second answer cannot revive a dropped row" 're-read the row'
g "V17 the automatic restart is per stage" '`restarts` goes back to 0'
g "V18 a brief without criteria is not built on a bare approve" 'still says `NEEDS CRITERIA`'
g "V20 a check that prints nothing is pending" 'no line, or an exit that is not 0'
g "V21 an unreadable quiet window holds, for STAR too" 'anything but exit 0 with exactly `inside` or `outside`'
g "V23 the feedback cursor is passed back as it is" 'opaque'
g "V26 a lost queue item is noticed" '`missing`'
g "V29 inbox files are read in order" 'in file-name order'
g "V30 back runs a tick" 'then run a tick'
# Best model per stage
g "M1 each stage has its own model setting" '"stages"'
g "M1 a stage reads its own entry" 'stages.<stage>'
g "M2 the coordinator runs on Fable 5.1" 'Fable 5.1'
g "M3 a stage whose model cannot start falls back" 'falls back to `worker`'
g "M4 every plan runs on the newest luna" '"latest-luna"'
g "M4b the executor is resolved from Codex's catalog" 'executor-model.sh'
python3 - "$T/star.json" <<'PY2' && pass "M5 template: schema 2" || fail "M5 template schema 2"
import json, sys
d = json.load(open(sys.argv[1])); s = d["stages"]
assert d["schema"] == 2, d.get("schema")
assert set(s) == {"brief", "build", "babysit", "post"}, sorted(s)
assert s["brief"] == {"agent": "claude", "model": "opus", "effort": "high"}, s["brief"]
for k in ("build", "babysit", "post"):
    assert s[k] == {"agent": "claude", "model": "opus", "effort": "xhigh"}, (k, s[k])
assert d["worker"] == {"agent": "claude", "model": "opus", "effort": "xhigh"} and "reviewer" not in d
assert d["executor"] == {"model": "latest-luna", "effort": "xhigh", "fallback": "latest-sol"}, d["executor"]
assert d["gate"] == {"model": "latest-sol", "effort": "xhigh", "fallback": {"agent": "claude", "model": "opus", "effort": "xhigh"}, "maxRounds": 3}, d["gate"]
assert d["hostedReviewer"] is None, d["hostedReviewer"]
assert d["hostGate"] == {"minFreeGB": 3, "maxAgents": 40, "maxSwapGB": 11, "minDiskGB": 25}, d["hostGate"]
assert d["progressDeadlineMin"] == 30 and d["maxBriefs"] == 4 and d["maxParallel"] == 3 and d["maxInReview"] == 3
assert [k for k in d if k not in ("tokenCmd", "ownerApproval", "hostedDown", "ghLogin")] == ["schema", "maxParallel", "maxInReview", "maxBriefs", "stages", "worker", "executor", "gate", "hostedReviewer", "hostGate", "progressDeadlineMin", "mcps", "gateDown", "quietHours", "run", "terminal", "caffeinatePid", "heartbeat", "notified", "away", "project"], list(d)
assert d.get("tokenCmd") is None and d.get("ownerApproval") is None and d.get("hostedDown") is None and d.get("ghLogin") is None, d
assert d["notified"] == [], d["notified"]
for k in ("mcps", "gateDown", "quietHours", "run", "terminal", "caffeinatePid", "heartbeat", "away", "project"):
    assert d[k] is None, (k, d[k])
PY2
# STAR lives in the project
! grep -q 'juel-star' "$SKILL" && ! grep -q 'JUEL_STAR_HOME' "$SKILL" && pass "P1 no separate home to set up" || fail "P1 old home instructions left"
g "P2 the folder is inside the project" 'context/star'
g "P3 refs can be given in plain words" 'SPH-11 and SPH-12'
g "P4 the invoking session becomes the coordinator" 'this session becomes the coordinator'
g "P5 refs are handed to a STAR that is already running" 'hands the refs to it'
g "P6 stop releases the claim" '"terminal": null'
! grep -q 'HOME_DIR/CLAUDE.md' "$SKILL" && grep -q 'come from the' "$SKILL" && grep -q 'session hook' "$SKILL" && pass "P7 the standing rules come from the session hook" || fail "P7 standing rules"
! grep -q 'projects\.md' "$SKILL" && ! grep -q 'global\.md' "$SKILL" && pass "P8 one project per folder: no registry, no global notes" || fail "P8 registry or global notes left"
g "P9 a ref for another repo is refused" 'another repository'
# Final review
g "F1 finding out whether to hand over comes before the preflight" 'the one exception to rule 1'
g "F2 take over is a command, not filler" 'whole text is `take over`'
g "F3 an inbox file for another repo is kept, not deleted" 'leave the file where it is'
g "F4 the worktree is created from the recorded repo id" '`<REPO_ID>` is `project.orcaRepo`'
g "F5 a late registration is recorded" 'write it to `star.json` as `project.orcaRepo`'
# Issues #7 to #18: the scripts, the goal, the pool
g "G1 the goal is stated" '## Goal'
g "I13 the ledger is written through ledger.sh" 'sh S/ledger.sh set <item>'
g "I13 the item name comes from ledger.sh" 'sh S/ledger.sh name <ref>'
g "I13 messages are read through messages.sh" 'sh S/messages.sh --wait --timeout-ms 540000'
g "I13 stages start through stage-start.sh" 'sh S/stage-start.sh <stage> <item>'
g "I8 a heartbeat-only nudge is a no-op" 'holds only heartbeats is a no-op'
g "I11 every spec is one line" 'Every spec is one line'
g "I11 a replay reuses its request ids" 'same `--retry-request` ids'
g "I7 a stalled prompt names the trust dialog" 'agent_prompt_stalled'
g "I7 dialogs that cannot be cleared reach the user" 'hold trust <path>'
g "I9 a worktree inside the repo is excluded" '.git/info/exclude'
g "I18 briefs have a pool of their own" '`maxBriefs`'
[ ! -e "$T/reviewer-prompt.md" ] && pass "the v1 reviewer prompt is gone" || fail "reviewer-prompt.md still there"
! grep -q 'payload.dispatchId' "$SKILL" && ! grep -q "orca orchestration task-create --spec" "$SKILL" && pass "no hand-rolled message reading or task creation left" || fail "hand-rolled steps left"
# Questions and the intake
g "Q1 a worker sets its own deadline" 'deadline=<minutes>'
g "Q2 a new ask supersedes the open one" 'Superseded by your newer question.'
g "Q3 one reminder before No answer" 'still waiting on you'
g "Q3 the reminder is counted" '`reask=1`'
g "B3 the intake asks between ticks only" 'Between ticks, never inside one'
g "B7 the brief report counts its asks" 'asks=<n>'
# Report items, the tracker status, improvement issues
g "R1 report items" 'deliverable: report'
g "R2 the report is accepted in the queue" '--kind accept-report'
g "R3 a post worker posts it" '/juel:star post-report <ref> --item <name> --report <path>'
g "R4 report states" '`post-queued`'
g "R5 the report lines" 'REPORTED item='
g "R5 the post line" 'POSTED item='
g "T1 STAR owns the tracker status" '## The tracker status'
g "T2 the status follows the row" 'counters.tracker='
g "T3 status writes are logged" 'status <status>'
g "N1 STAR files its own issues" '## Improvement issues'
g "N2 through star-issue.sh" 'sh S/star-issue.sh file --fingerprint'
g "N3 workers can report friction" 'STAR-ISSUE:'
g "N4 project details never go out" '`<project>`, `ITEM-1`, `<repo>` and `<app>`'
# Final review fixes
g "FR1 a retry keeps the attempt number, status, batch and lineage" '`counters=keep:hold,last,start,tracker,batch,rescoped,parent`'
g "FR2 lost brief, babysit and post workers restart once" 'a `briefing`, `posting` or `babysitting` row restarts once'
g "FR2 a restarted post worker does not post twice" 'already starts with the report'
g "FR6 stage-start runs in the background" 'like `gate-lock.sh` in a worker'
g "FR6 a start that printed nothing is replayed" '| no line, or a non-zero exit |'
# Finished worktrees (#19)
g "W1 finished worktrees are removed" 'sh S/worktree-clean.sh <item>'
g "W2 a kept worktree waits for the user" '`kept=1`'
g "W3 never with work in it" 'never with work in it'
# Issue #22
# Issue #25
g "K1 a refused check-in is not a nudge" 'agent_prompt_blocked'
g "K2 busy has its own count" '`busy=<n>`'
g "K3 a long busy stretch goes to the user" 'silent and busy for 2 h'
# Issue #27
g "Z5 a repository gh cannot see goes to the user, who sets tokenCmd" 'set tokenCmd in star.json to a command that prints a token for it'
# Issue #28
g "U4 a moved base is synced once per head" 'counters.synced=<sha7>'
g "U5 the sync is named in the counters table" '`synced=<sha7>`'
# Issue #26
g "I2 STAR's home keeps the id ledger" 'ids.json'
# Issue #33
g "E4 the brief names an existing PR" 'existingPr'
g "E5 a fork's PR is asked about" 'comes from a fork'
# Issue #20
g "C1 proposed criteria are reported" 'PROPOSED-CRITERIA'
g "C3 the marker is removed on approval" 'remove each ` (proposed)` suffix'
g "C4 a re-draft keeps proposed criteria marked" 'on every re-draft, keep the earlier draft'
# Issue #29
g "Q1 plain chat, one question per message" 'one question per message'
g "Q2 the recommended option is labelled" '(Recommended)'
g "Q3 a nudge is never an answer" 'is never an answer'
g "Q4 the picker only before any worker" 'AskUserQuestion only for the first-run setup question, before any worker exists'
grep -qF 'AskUserQuestion only in the intake' "$SKILL" && fail "Q5 the old hard rule is gone" || pass "Q5 the old hard rule is gone"
# Faster briefs
g "F1 the pool default is documented" '"maxBriefs": 4'
g "F3 STAR edits a brief itself" '(applied by STAR)'
g "F4 changed lines are marked" '(changed)'
grep -qF 'briefs may take every build slot' "$SKILL" && fail "F5 briefs no longer take build slots" || pass "F5 briefs no longer take build slots"
g "F6 STAR's own edit keeps the criteria markers right" 'carries no ` (proposed)` suffix, and STAR removes the `- [ ] NEEDS CRITERIA` line'
g "Q6 the heartbeat and STAR's own commands are never an answer" 'a message that starts with `STAR heartbeat:`, or one'
# Faster briefs: review fixes
grep -qF 'STAR writes itself, as below; otherwise the brief worker writes them from it' "$SKILL" && ! grep -qF 'is feedback, and the brief worker writes the criteria from it' "$SKILL" && pass "B9 a NEEDS CRITERIA answer in the user's words is STAR's to write" || fail "B9 a NEEDS CRITERIA answer in the user's words is STAR's to write"
g "B11 an edit that leaves no criterion writes NEEDS CRITERIA" 'leaves the brief with no acceptance criterion'
g "B12 the changed mark is only in chat" 'only in the question STAR asks in chat, never in the brief file'
g "B13 an existing PR fixes branch and baseBranch" 'On a brief with `existingPr`, `branch` and `baseBranch` are not small edits'
# Final fix wave (Z4 and Z5 are issue #27's)
g "Z1 the base sync clears pending=" 'write `counters.synced=<sha7>` and `counters.pending=-`'
g "Z2 a bare number is refused only where options are numbered" 'On a question with numbered options, a bare number that names no option is not an answer'
grep -qF 'so a change to either is answered in chat' "$SKILL" && grep -qF 'A later reply saying the PR was changed is feedback, and the brief worker re-reads the PR' "$SKILL" && ! grep -qF 'a change to either is feedback for the brief worker' "$SKILL" && pass "Z6 an existing PR's branches are changed on GitHub, not by a re-draft" || fail "Z6 an existing PR's branches are changed on GitHub, not by a re-draft"
grep -qF 'it makes sure the brief has `- [ ] NEEDS CRITERIA`' "$SKILL" && ! grep -qF 'it writes `- [ ] NEEDS CRITERIA`' "$SKILL" && pass "Z7 an edit that leaves no criterion never adds a second marker" || fail "Z7 an edit that leaves no criterion never adds a second marker"
grep -qF '`PROPOSED-CRITERIA` when any criterion ends in ` (proposed)`' "$SKILL" && ! grep -qF '`PROPOSED-CRITERIA` (case 3)' "$SKILL" && pass "Z8 PROPOSED-CRITERIA whenever a criterion is proposed" || fail "Z8 PROPOSED-CRITERIA whenever a criterion is proposed"
grep -qF -- '--json url,headRefName,baseRefName,isCrossRepository,state,author' "$SKILL" && grep -qF 'only when `state` is `OPEN`' "$SKILL" && pass "Z9 existingPr only for an open PR" || fail "Z9 existingPr only for an open PR"
grep -qF '`ls-remote` failing: the Otherwise branch of the cell that sent it here.' "$SKILL" && ! grep -qF "the table's own rule for that verdict" "$SKILL" && pass "Z13 an ls-remote failure goes to the Otherwise branch of its own cell" || fail "Z13 an ls-remote failure goes to the Otherwise branch of its own cell"
grep -qF 'Nothing is recorded (no `## Feedback` entry), and STAR adds the `go-batch` item again, with that explanation in its title' "$SKILL" && grep -qF 'except a `branch` or `baseBranch` change on a brief with `existingPr` (below)' "$SKILL" && ! grep -qF 'Nothing is recorded, and the approve question is printed again' "$SKILL" && pass "Z14 an existingPr branch answer re-asks the approve question" || fail "Z14 an existingPr branch answer re-asks the approve question"
# STAR closed loop: intake and home
g "FT1 a brief can be free text" 'free-text brief'
g "FT2 free text becomes spec items" 'items/<project>/<name>.md'
g "FT3 the inbox file carries free text" 'text: |'
g "FT4 grants are kept" 'grants/<UTC>-<4 hex>.md'
g "FT5 workers write progress" 'progress/<item>.log'
g "H1 the first start looks for a hosted reviewer" 'greptile-apps[bot]'
g "LD1 the flow page is named" 'how-it-works.html'
g "SC1 schema 2" '"schema": 2'
g "SC2 the gate settings" '"gate":'
g "SC3 the host gate settings" '"hostGate":'
g "SC4 the progress deadline" '"progressDeadlineMin": 30'
g "SC5 migrate on start" 'star-home.sh migrate'
g "SC6 the gate's command" 'codex review'
g "S1b free text is handed over" 'no refs and no free text'
# Fix round 1: the hosted-reviewer lookup, command words, hand-over of free text, filler
g "H2 the lookup lists the PR numbers through --jq" "gh pr list --state merged --limit 20 --json number --jq '.[].number'"
g "H3 it reads each PR's review logins from the REST API" "gh api \"repos/{owner}/{repo}/pulls/<n>/reviews\" --jq '.[].user.login'"
g "H4 and each PR's comment logins" "gh api \"repos/{owner}/{repo}/issues/<n>/comments\" --jq '.[].user.login'"
g "H5 it stops at the exact REST login" 'stopping at the first line that is exactly `greptile-apps[bot]`'
grep -qF 'gh pr view <n> --json comments,reviews' "$SKILL" && fail "H6 the GraphQL lookup is gone" || pass "H6 the GraphQL lookup is gone"
g "CW1 status, dashboard, away, back and stop are commands only as the whole text" '`status`, `dashboard`, `away`, `back` and `stop` are commands only when they are the whole text'
g "CW2 a free-text brief may start with a command word" '`/juel:star stop the digest from sending twice` is a free-text brief'
g "CW3 draft-brief and post-report match as the first word" 'A first word of `draft-brief` or `post-report` is'
g "CW4 filler is dropped, a remark about the refs goes to the note" '(`and`, `add`, `please`), which is dropped, or only say something about the refs'
g "HO1 a hand-over carries free text too" 'Write them, and any free text, as an inbox file'
g "HO2 the hand-over line names the refs or the text" "I handed it <refs, or the text's first words>"
g "MG1 the start migrates a v1 folder first" 'sh S/star-home.sh migrate'
g "MG2 the workers of removed stages are stopped" 'stop <dispatch>'
g "BT1 every row knows its batch" 'counters.batch'
g "BL1 a blocked item waits for its blockers (#37)" 'blockedBy'
g "TK1 a DONE is checked before babysitting" 'sh S/done-check.sh <item> --pr <url> --head <sha>'
g "TK2 a report that does not check out resumes once" 'the report did not check out'
g "TK3 a re-scope" 'RESCOPE item='
g "TK4 one re-scope per item" 'NOT-SAFE again after a re-scope'
g "TK5 a split" 'SPLIT item='
g "TK6 a stale waiter is ended (#38)" 'waiter-exists'
g "TK7 go except" 'go except <items>'
g "TK8 capacity stalls are nudged, then restarted (#41)" 'stalled: model at capacity'
g "TK9 the screen holder is named (#39)" 'holds-screen'
g "TK10 a follow-up rides its parent's go" "covered by <parent>'s go"
g "TK11 the probe gets the progress options" '--deadline <progressDeadlineMin>'
g "TK12 a grant is written on go" 'grants/<UTC YYYYMMDDTHHMMSSZ>-<4 hex>.md'
# STAR closed loop: stages, the codex gate, the brief
left=""; for gone in '| review | the item' '| fix | the item' '| screen | the item' '--executor session' 'stages.review' 'reviewer-prompt.md' '`## Before you go` lists everything'; do
  grep -qF -- "$gone" "$SKILL" && left="$left [$gone]"
done
[ -z "$left" ] && pass "the v1 stages and the reviewer prompt are gone" || fail "still there:$left"
g "ST1 the build stage runs one worker through the gate" '`/juel:ship-ticket --unattended --brief <brief> [--quiet-hours <window>]`'
g "ST2 the brief stage can re-scope" '[--rescope HOME_DIR/reviews/<project>/<file>]'
g "ST3 the gate is a script, not a stage" 'sh S/codex-gate.sh --brief <brief> --item <item> --round <k> --base <remote>/<baseBranch>'
g "ST4 the gate's files" "\`<item>-r<k>.raw.md\`, Codex's own text"
g "ST5 the PASS comment" 'Codex gate: PASS (head <full sha>, round <k>, <model> <effort>)'
g "DB1 the copied item's headings are demoted (#36)" 'demoted one level'
g "DB2 a brief names its blockers (#37)" 'blockedBy: ['
g "DB3 decision records" '### D<n> <title> (<date>, decided by'
g "DB4 every check says how it runs" 'auto: playwright'
g "DB5 a check that needs a person first" '| person: <what>'
g "DB6 person-only steps" '## Person-only steps'
g "DB7 external ids are checked live (#42)" '(verified <date> via <how>)'
g "DB8 an unverified id is confirmed before go" '`confirm-id`'
g "DB9 a hosted review comes after ready (#40)" 'skips draft PRs'
g "DB10 grounding: Mobbin for user-facing changes" 'search_screens'
g "DB11 grounding: context7 for libraries" 'context7'
g "DB12 the re-scope report" 'BRIEF item=<name> path=<--out> asks=<n> rescoped=1 followup=<path>'
g "DB13 the split report" 'SPLIT item=<name> into=<path>,<path>'
g "DB14 criteria are derived when the item has none" 'derive them from the item'
# STAR closed loop: the merge gate, the batch summary, the rules
left=""; for gone in '`pr-draft`' '`reviewing`' '`fix-queued`' '`fixing`' '`screen-queued`' '`screening`' '`ready`' '--kind approve-brief' '--kind prep' '--kind merge-pr' 'Exact-head verification' 'exact-head check' 'Before you go' 'decided while you were away' 'default taken' 'you said rest' 'Never merge'; do
  grep -qF -- "$gone" "$SKILL" && left="$left [$gone]"
done
[ -z "$left" ] && pass "nothing of the v1 flow is left" || fail "v1 flow still named:$left"
g "MG3 the merge gate" 'sh S/pr-verify.sh <pr url> --head <head> --merge-gate'
g "MG4 a hosted reviewer stands in for the approval" 'adding `--hosted <hostedReviewer.login>` when'
g "MG5 STAR merges through merge.sh" 'sh S/merge.sh <pr url> --head <head> --grant <grant path>'
g "MG6 a merge-gate failure goes back to babysitting once" 'mergefail=1'
g "MG7 without a hosted reviewer, someone else approves" 'waits for an approval from someone other than you'
g "MG8 a merge in quiet hours waits" 'HELD quiet hours'
g "MG9 merges are announced" 'merged <item>: PR #<n>'
g "BS1 the batch summary" '## The batch summary and go'
g "BS2 one message for the whole batch" 'Reply go, go except <items>, drop <item>, or tell me what to change.'
g "BS3 person-only steps one per message" 'one person-only step per message'
g "HG1 the host gate" '## The host gate'
g "HG2 every limit is named" '`minFreeGB`, `maxAgents`, `maxSwapGB` and `minDiskGB`'
g "LW1 product calls are STAR's, from sourced options" 'Bring sourced options'
g "LW2 a stale worker gets a check-in" 'stale <minutes> <terminal>'
g "HR2 the go is never inferred" 'A go is never inferred'
g "EC1 a re-scope edge case" 'NOT-SAFE after 3 rounds'
g "RC1 a v1 folder is migrated on start" 'A v1 STAR folder'
python3 - "$ROOT/.claude-plugin/requirements.json" <<'PY3' && pass "PF1 STAR needs codex, and briefs and builds use Mobbin and context7" || fail "PF1 requirements"
import json, sys
d = json.load(open(sys.argv[1]))
star, ship = d["skills"]["star"], d["skills"]["ship-ticket"]
assert "codex" in star["hard"], star
for s in (star, ship):
    assert "mobbin" in s["soft"] and "context7" in s["soft"], s
assert d["definitions"]["mobbin"]["kind"] == "mcp", d["definitions"].get("mobbin")
PY3
g "PF2 the codex row stops STAR" '| codex | cli | HARD |'
grep -q 'merges it under your go' "$ROOT/README.md" && ! grep -q 'You merge; nothing in the flow does' "$ROOT/README.md" && ! grep -q 'no skill here depends on it' "$ROOT/README.md" && pass "RD1 the README describes the closed loop" || fail "RD1 README"
# Final fix pass, group S: the Answers, Messages, merge gate, merge.sh and start rules.
# gin looks a phrase up in one part of the skill only, so a rule cannot pass on another rule's words.
gin() { printf '%s\n' "$2" | grep -qF -- "$3" && pass "$1" || fail "$1"; }
start1=$(sed -n '/^1\. Migrate:/,/^2\. `orca orchestration run-use/p' "$SKILL")
reconcile=$(sed -n '/^5\. \*\*Reconcile\*\*/,/^6\. `loops\.sh resume/p' "$SKILL")
gatefail=$(grep -F '| `FAIL <what>` |' "$SKILL")
[ -n "$start1" ] && [ -n "$reconcile" ] && [ -n "$gatefail" ] && pass "FS0 the parts of the skill that the FS lines look in are found" || fail "FS0 the parts of the skill that the FS lines look in are found"
# FS1: a person step answered can't now is asked again
g "FS1 a go leaves a row that has an open person item" 'or that has an open `person` item: those stay'
grep -qF 'a `person` item still open, answered' "$SKILL" && fail "FS1 the go row no longer reads an answered item as open" || pass "FS1 the go row no longer reads an answered item as open"
g "FS1 can't now closes the answered item, then asks the step again" 'then close the answered item and add the same `person` item again'
g "FS1 add returns an item that is still in the queue" 'returns an item that is still in the queue, answered or not, and adds nothing'
g "FS1 a refused risky step is not asked again" 'and do not add the item again: the brief stage plans without it'
g "FS1 an answer in words is feedback on the step" '   | `person` | anything else | record it under `## Decisions` as feedback on that step'
answers=$(sed -n '/^   | Kind | Answer | Action |/,/^3\. \*\*Messages\*\*/p' "$SKILL")
[ -n "$answers" ] && ! printf '%s\n' "$answers" | grep -q '^|' && pass "FS1 every row of the Answers table keeps the table's indent" || fail "FS1 every row of the Answers table keeps the table's indent"
# FS2: the reconcile step does not probe a building row whose DONE is pending
gin "FS2 reconcile names the building row whose DONE is pending" "$reconcile" 'whose `verify` holds `retry=` has already reported'
gin "FS2 reconcile does not probe it" "$reconcile" 'skip the probe for it'
gin "FS2 reconcile runs done-check.sh for it" "$reconcile" 'run `done-check.sh` for it'
# FS3: a re-scope BRIEF on a brief with no grant line
g "FS3 a re-scope brief always adds its follow-up and keeps the lineage" 'in every case: `counters.rescoped=1`, clear `counters.rescope`, add the follow-up spec as a new `inbox` row'
g "FS3 with no grant line the row goes to brief-ready for the batch go" 'A brief with no grant line (`grep -cE '"'"'^grant: [^ #]'"'"' <brief>` prints 0): row → `brief-ready`'
grep -qF 'else treat it as the next row' "$SKILL" && fail "FS3 a re-scope brief no longer falls through to the next row" || pass "FS3 a re-scope brief no longer falls through to the next row"
# FS4: the merge gate's FAIL no codex PASS goes back to the gate loop
gin "FS4 a missing codex PASS resumes the gate loop on the existing PR" "$gatefail" 'no codex PASS for <sha7>; resume the gate loop on the existing PR'
gin "FS4 it goes to queued like no-safe-verdict and spends no mergefail" "$gatefail" 'row → `queued` (the build resumes the gate loop, as for `reason=no-safe-verdict`); it spends no `mergefail=`'
# FS5: the start gives its batch to every open row, not only the brief-ready ones
gin "FS5 the start gives its batch to every open row" "$start1" 'give every open row (not `done` or `dropped`) with no `counters.batch`'
grep -qF 'give each `brief-ready` row with no' "$SKILL" && fail "FS5 the batch is no longer given to brief-ready rows only" || pass "FS5 the batch is no longer given to brief-ready rows only"
gin "FS5 the summary waits until no row of the batch is still being briefed" "$start1" 'once no row of the batch is `inbox` or `briefing`'
# FS6: merge.sh failures that are not the PR's
g "FS6 grant, merge-method and comment failures are held at once" '| `FAIL grant: …`, `FAIL merge methods: …` or `FAIL comment: …` | nothing on the PR is wrong, so no `mergefail=` and no babysit round: queue `--kind held`'
g "FS6 the merge failure itself keeps the mergefail budget" '| `FAIL merge: …` | as the Otherwise branch of a merge-gate `FAIL <what>` (the `mergefail=` budget)'
g "FS6 exit 64 names what merge.sh refuses" 'a head that is not 40 hex characters, a URL that is not a PR, or missing arguments'
grep -qF 'or no grant file' "$SKILL" && fail "FS6 exit 64 is no longer blamed on a missing grant file" || pass "FS6 exit 64 is no longer blamed on a missing grant file"
# FS7: a migrate that exits non-zero stops the start
gin "FS7 a failing migrate stops the start" "$start1" 'A non-zero exit stops the start'
gin "FS7 the stop lines it printed are still stopped and released" "$start1" 'stop and release each `stop <dispatch>` line it printed'
gin "FS7 the claim is released as stop does" "$start1" 'release the claim'
gin "FS7 the owner is told that running /juel:star again retries" "$start1" 'running `/juel:star` again retries the migrate'
gin "FS7 no reconcile and no tick follow" "$start1" 'no reconcile and no tick'
# Issues 55 to 74, lane D2
# The gate reviews on Sol (owner, 2026-10-12), with a Claude fallback (#64); an ERROR attempt keeps its round (#66)
grep -qi 'astra' "$SKILL" && fail "SOL1 STAR's text names no astra" || pass "SOL1 STAR's text names no astra"
g "SOL2 the settings block's gate is Sol with a Claude fallback" '"gate":     { "model": "latest-sol", "effort": "xhigh", "fallback": { "agent": "claude", "model": "opus", "effort": "xhigh" }, "maxRounds": 3 }'
g "SOL3 the settings block shows mcps" '"mcps":     { "mobbin": "available", "context7": "needs-sign-in" }'
g "SOL4 the settings block shows gateDown" '"gateDown": null'
g "SOL5 the models table's gate row" '| gate | the newest sol'
g "SOL6 luna writes and Sol gates" 'Luna writes the code and Sol gates it'
g "SOL7 the fallback is a second Claude review" 'a second Claude review, not a second model'
g "SOL8 the gate's last resort" 'ERROR gate-down <why>'
g "SOL9 an ERROR attempt keeps its round" '<item>-r<k>-error-<n>.log'
# Issue #55: workers learn which research MCPs exist
g "MCP1 the preflight tells needs-sign-in from available" '`needs-sign-in` when its only tools are `authenticate` and `complete_authentication`'
g "MCP2 every start writes mcps" '"mcps": {"mobbin": "<state>", "context7": "<state>"}'
g "MCP3 every worker reads mcps" '`gate`, `hostedReviewer` and `mcps` from this file'
g "MCP4 a brief worker reads mcps" '`mcps` in `<HOME_DIR>/star.json`'
g "MCP5 a brief worker uses an MCP only when its own session has it" 'use an MCP only when this session lists its'
# Issue #56: the worker_done body is the report lines
g "SHP1 report lines override the preamble" "Orca's worker preamble included"
g "SHP2 a body with no report line is asked for once more" 'your worker_done body must be the report lines your skill names'
g "SHP3 a second miss fails the row" 'reason=report-shape'
g "SHP4 the shape counter" '| `shape=1` |'
g "SHP5 a prose body never stops the settlement rule" 'does not count as a processed report'
# Issue #67: a re-scope leaves the dispositions the next gate round reads
g "FIX1 a moved finding names its follow-up" 'Disposition: moved to <follow-up path> (decision D<n>)'
g "FIX2 a kept finding says why" 'Disposition: kept, <why> (decision D<n>)'
g "FIX3 only a gate review gets one" 'A hosted review file gets none'
g "FIX4 the brief worker writes it into STAR's folder" 'in re-scope mode the `-fix.md` of the review it narrowed by'
# Issues #68 and #61: follow-up items get their own rows in every mode
g "FUP1 a BRIEF may name a follow-up in every mode" 'BRIEF item=<name> path=<--out> asks=<n> [followup=<path>]'
g "FUP2 the BRIEF row adds the follow-up row" 'When the line carries `followup=<path>`'
g "FUP3 a follow-up whose parent has no grant waits for its batch's go" "whose parent's brief has a grant"
g "FUP4 STAR may accept a residual" '**An accepted residual.**'
g "FUP5 the DONE note adds the follow-up" 'a `NOTE: accepted residual <criterion>: <follow-up path>` line'
g "FUP6 a missing follow-up file is held" 'which does not exist'
# Issue #70: STAR reads each worker's step and restarts a stuck stage; the PR pass of #69
g "STP1 housekeeping reads each running worker's step" 'sh S/step-check.sh --item <item> --home HOME_DIR --state <state> --deadline <progressDeadlineMin>'
g "STP2 an act line sends its instruction" '| `act <step> <diagnosis> -- <instruction>` |'
g "STP3 the second ignored instruction restarts the stage" '`nudge=2` with `asked` 15 minutes or more ago'
g "STP4 one automatic restart per stage" 'stalled again at <step> after a restart'
g "STP5 a build with uncommitted work is held, not restarted" 'with uncommitted work in <worktree>'
g "STP6 the asked and step counters" '| `asked=<iso>` |'
g "STP7 notes go in the status line" "this tick's \`step-check.sh\` (\`<item>: <diagnosis>\`)"
grep -qF 'through 3 check-ins' "$SKILL" && fail "STP8 held after 3 check-ins is gone" || pass "STP8 held after 3 check-ins is gone"
g "STP9 the run file" '<item>-r<k>.run'
g "STP10 an act on a new step starts the count over" 'starts over at `nudge=1`'
g "STP11 an instruction still fresh is a note, not a second send" '`note <step> instructed <m> min ago`'
g "STP12 the act line splits on its first separator" 'split the line on its first ` -- `'
# Issue #69: the build marks the PR ready
g "STP13 the build marks the PR ready" 'the build does after its final SAFE round'
# Issue #64: the review gate is down
g "GD1 a gate-down escalation parks the row" '| `ESCALATION item=… reason=review-unavailable needs=ERROR gate-down …` in a `worker_done` |'
g "GD2 no build or babysit starts while the gate is down" 'While `gateDown` is set, start no build and no babysit'
g "GD3 the gate is checked every 30 minutes" '`gateDown` set, and its `checked` 30 minutes or more ago: `sh S/codex-gate.sh check`'
g "GD4 retry checks the gate now" '| `held` "the review gate is down…" | `retry` |'
g "GD5 retry is a command word" '`accept`, `retry`, `skip` or `not merging`'
g "GD6 STAR stays active while the gate is down" 'or while `gateDown` is set'
g "GD7 the status line says so" '`gate down since <since>`'
g "GD8 the Gate down rule" '**Gate down.**'
g "GD9 one held item, however many rows report it" 'When it is set already: nothing more'
# Issue #59: a missing hosted status is refreshed by babysit, not counted
g "HS1 the merge gate names a missing hosted status" '`PENDING hosted-status <check> missing on <sha>`'
g "HS2 babysit refreshes it" 'refresh the hosted status on <sha7>'
g "HS3 a second miss on the same head is a pending" 'the refresh did not help'
g "HS4 the merge gate is told who the hosted reviewer is" 'adding `--hosted <hostedReviewer.login>` when'
# Issue #73: evidence outlives the worktree
g "EV1 the evidence folder in STAR's home" 'evidence/<item>/'
g "EV2 the copy is named in the status line" '`kept-evidence <path>`'
g "EV3 a worktree goes only after its evidence is copied" 'only after its evidence is copied'
# Issue #74
g "EL13 a hidden-window check follows juel:verify's Electron row" "as \`juel:verify\`'s Electron row says"
g "EL14 a Checks line may name the project's launch helper" '[ | helper: <path>]'
grep -q 'window that paints' "$SKILL" && fail "EL15 no 'window that paints' description left" || pass "EL15 no 'window that paints' description left"
# Final-review fixes: the start says what a gate migration means; a refused send sets no counter
g "FW1 migrated gate is said in one line" 'say in one line "gate moved to Sol with a Claude fallback"'
g "FW2 a refused check-in sets no asked, step or nudge" 'none of `asked=`, `step=` and `nudge=`: nothing reached the worker'
# README, v2.1.0
grep -qF 'gate on the newest Sol' "$ROOT/README.md" && pass "RD2 the README names Sol for the gate" || fail "RD2 the README names Sol for the gate"
grep -qi 'astra' "$ROOT/README.md" && fail "RD3 the README names no astra" || pass "RD3 the README names no astra"
grep -qF 'restarts it once before asking you' "$ROOT/README.md" && pass "RD4 the README says STAR restarts a stuck worker" || fail "RD4 the README says STAR restarts a stuck worker"
grep -qF "keeps each merged item's evidence" "$ROOT/README.md" && pass "RD5 the README says evidence outlives the worktree" || fail "RD5 the README says evidence outlives the worktree"
grep -qF 'an Electron window over CDP' "$ROOT/README.md" && pass "RD6 the README's verify row names Electron" || fail "RD6 the README's verify row names Electron"
# lane g: STAR's contract for issues #75 to #93
g "G1a the receipt carries a VERDICT line (#84)" 'Codex gate: PASS (head <full sha>, round <k>, <model> <effort>)`, then `VERDICT: PASS`'
g "G1b a clean base merge carries the last SAFE (#75)" 'the base that `carry-check.sh` proves added no change of its own'
g "G1c no receipt is written by hand (#84)" 'so none is ever written by hand'
g "G1d an owner's ship decision is written as a carried proof (#82)" 'sh S/../babysit-pr/review-proof.sh carry --reviews HOME_DIR/reviews/<project> --item <item> --round <k>'
g "G1e babysit gets the carried proof as --reviewed (#82)" '`<item>-r<k>-carried.md` when the owner shipped that round'
g "G1f STAR's home lists the carried proof" 'reviews/<project>/<item>-r<k>-carried.md'
g "G2a refreshOutsideCap is a hosted-reviewer setting (#93)" '"maxPasses": 2, "refreshOutsideCap": true }'
g "G2b the lookup writes it too (#93)" '"maxPasses": 2, "refreshOutsideCap": true}` and says so in one line'
g "G2c a project that counts every run escalates hosted-cap (#93)" 'comes to the owner as `reason=hosted-cap`'
g "G2d one merge per base at a time (#75)" '**One merge per base at a time** (#75, #93)'
g "G2e a row with no hosted pass left merges first (#93)" 'merge first a row with no hosted pass left'
g "G2f siblings sync in the same tick (#75)" 'run the merge gate at once, in the same tick, for every other `verifying` row on that base'
g "G2g STAR's home lists the hosted pass record" 'reviews/<project>/<item>-hosted.log'
g "G3a a stopped worker is gone (#76)" '**A stopped worker is gone** (#76)'
g "G3b the gone check reads Orca's worker list" 'orca orchestration worker-list --json | python3 -c'
g "G3c a terminal a person may be at is never closed (#76)" 'never close it; queue `--kind held`'
g "G3d an owned terminal is closed" 'orca terminal close --terminal <terminal> --json'
g "G3e the restart rule runs the gone check" '`worker-release` and the gone check ("A stopped worker is gone")'
g "G3f stage-start ended an earlier session" '| `ended previous session <terminal>`'
g "G3g stage-start holds a row a live session may still work on" '| `hold session <terminal> (<state>)` |'
g "G3l stage-start stopped a gate the earlier session left (#76)" '| `stopped previous gate pgid=<n>`'
g "G3m stage-start kept a quiet terminal it cannot place (#76)" '| `kept previous session <terminal> (<state>)`'
g "G3n the extra lines come before any final line" 'Its last line is one of these. Before it, up to three lines of their own may come'
g "G3o merge.sh may find no ledger row" '| `FAIL ledger: <why>` |'
g "G3h merge.sh is told the home and the item (#80)" '--grant <grant path> --home HOME_DIR --item <item>'
g "G3i merge.sh refuses a row with a live worker (#80)" '| `FAIL live worker <dispatch>` |'
g "G3j the fence before an ordered merge (#80)" '**A merge on a PR a worker is still working on** (#80)'
g "G3k the edge case of an ordered merge" 'The owner orders a merge while the item'"'"'s worker is still fixing the PR'
g "G4a a person-only step can carry a value (#86)" '`<n>. [account] (value) <what to provide>`'
g "G4b never a value on a secret step (#86)" 'Never on a `secret` step'
g "G4c the queue item says it takes a value (#86)" 'a `(value)` step: the kind line `kind: <kind> (value)`'
g "G4d the answer is recorded as the value (#86)" '(<kind>, value): <step> → value: <answer>'
g "G4e done alone is asked again for the value (#86)" '(answer with the value)'
g "G4f the chat question asks for the value (#86)" 'Or tell me the value.'
g "G4g the edge case" 'A person-only step needs a value from the owner'
g "G5a the brief template has notBefore (#87)" 'notBefore: <YYYY-MM-DD or ISO datetime>'
g "G5b the brief worker sets it from the item's words (#87)" '**Not before** (#87)'
g "G5c a row waiting for its date is named in the status line (#87)" 'one waiting for its date: `<item> waits until <date>`'
g "G5d Fill slots reads stage-start's wait until (#87)" '   | `wait until <iso>` |'
g "G5e a queued row starts only after its notBefore (#87)" '`notBefore` time (`sed -n '"'"'s/^notBefore: //p'"'"' <brief>`), when it has one, has passed (#87)'
g "G5f the batch summary shows it (#87)" '`item.title`, `blockedBy`, `notBefore` and `deliverable`'
g "G5g the edge case" 'An item that may only be built after a date'
g "G6a the settings block names tokenCmd (#91)" '"tokenCmd": null'
g "G6b the session hook exports it in every session (#91)" 'export GH_TOKEN="$(<tokenCmd>)"'
g "G6c the hook never writes the token (#91)" 'The hook writes the command, never the token'
g "G6d a shell export never reaches a worker (#92)" 'A token exported in a shell never reaches Orca'"'"'s workers'
# review fixes: the gate holder label names the project (#76), and the gone check survives an Orca that does not answer (#76)
g "RF1 the gate stage-start stops is held under the project's label (#76)" 'under the label `<project>/<item>`'
g "RF2 the gone check says what unknown means (#76)" 'A state of `unknown` (the line `- unknown -`) means Orca did not answer: check again on the next tick'
# RF3 runs the gone-check command as SKILL.md prints it, against a stub orca
RFTMP=$(mktemp -d); mkdir -p "$RFTMP/bin"
awk '/^\*\*A stopped worker is gone\*\*/ { on = 1 } on && /^```sh$/ { grab = 1; next } on && grab && /^```$/ { exit } grab { print }' "$SKILL" | sed 's/<dispatch>/d1/' > "$RFTMP/gone-check.sh"
printf '#!/bin/sh\ncat "$STUB_REPLY"\n' > "$RFTMP/bin/orca"
chmod +x "$RFTMP/bin/orca"
gone_check() { STUB_REPLY="$RFTMP/reply" PATH="$RFTMP/bin:$PATH" sh "$RFTMP/gone-check.sh" 2>"$RFTMP/err"; }
[ -s "$RFTMP/gone-check.sh" ] && grep -q 'worker-list' "$RFTMP/gone-check.sh" && pass "RF3a the gone-check command is extracted from SKILL.md" || fail "RF3a gone-check extraction"
printf '{"ok":true,"result":{"workers":[{"dispatchId":"d1","agentTerminalHandle":"term_9","terminalState":"running","resource":{"retainedReason":"user_takeover"}}]}}' > "$RFTMP/reply"
out=$(gone_check); [ "$out" = "term_9 running user_takeover" ] && pass "RF3b a listed worker prints its terminal, state and reason" || fail "RF3b listed worker ($out)"
printf '{"ok":true,"result":{"workers":[]}}' > "$RFTMP/reply"
out=$(gone_check); [ "$out" = "- none -" ] && pass "RF3c a worker the list does not hold prints none" || fail "RF3c unlisted worker ($out)"
printf 'orca: command not found' > "$RFTMP/reply"
out=$(gone_check); [ "$out" = "- unknown -" ] && [ ! -s "$RFTMP/err" ] && pass "RF3d no JSON prints unknown, never a traceback" || fail "RF3d no JSON ($out; $(cat "$RFTMP/err"))"
: > "$RFTMP/reply"
out=$(gone_check); [ "$out" = "- unknown -" ] && [ ! -s "$RFTMP/err" ] && pass "RF3e an empty answer prints unknown" || fail "RF3e empty answer ($out; $(cat "$RFTMP/err"))"
printf '{"ok":false,"error":{"message":"orca is not running"}}' > "$RFTMP/reply"
out=$(gone_check); [ "$out" = "- unknown -" ] && [ ! -s "$RFTMP/err" ] && pass "RF3f an error answer prints unknown" || fail "RF3f error answer ($out; $(cat "$RFTMP/err"))"
rm -rf "$RFTMP"
# lane h: STAR's contract for issues #94 to #108
g "LH1a another author's PR is checked against the gh user (#94)" 'A PR whose `author.login` is not the `gh` user (`gh api user --jq .login`) is handled like a fork'
g "LH1b it is carried as a new PR (#94)" '`<url>` is `<login>`'"'"'s PR, carried as a new PR'
g "LH1c the new PR never shares the original's branch (#94)" 'name `branch` by step 5'"'"'s rule (never the original'"'"'s `headRefName`)'
g "LH1d the new PR credits the original's author (#94)" 'the PR body links `<url>` and credits `@<login>`'
g "LH1e the decision record has a line STAR can read (#94)" '`Decision: carried as a new PR: <url> (<login>'"'"'s PR)`'
g "LH1f the brief adds no person-only step for the close (#94)" 'The brief adds no person-only step for the'
g "LH1g STAR asks the owner to close the original once the new PR exists (#94)" '--title "close <that url>: carried on <pr url>"'
g "LH1h STAR reads the original's URL from the brief (#94)" 'sed -n '"'"'s/^Decision: carried as a new PR: \([^ ]*\) .*/\1/p'"'"' <brief>` prints its URL'
g "LH1i the close is asked once (#94)" '(`grep -cF '"'"'close <that url>: carried on'"'"' <brief>` prints 0)'
g "LH2a a re-scope queues its person-only steps (#101)" 'and queue one `--kind person` per line of the brief'"'"'s `## Person-only steps`, as the next row does'
g "LH2b a granted re-scope waits while a step is open (#101)" 'row → `queued` when none of those steps is open, else `brief-ready`'
g "LH2c the status line says what it waits for (#101)" '"<item>: re-scope waits for <n> person-only steps" in the status line; the grant still covers it'
g "LH2d the last answered value step queues it (#101)" 'and no other open `person` item: it → `queued` (a re-scope that waited for its person-only steps, #101)'
g "LH2e the last answered done step queues it too (#101)" 'the row does not change, with the same exception as the row above'
g "LH2f re-scope mode keeps step 6's person-only rules (#101)" '`## Person-only steps` follows step 6'"'"'s rules, and leaves out a step its'
grep -qF 'The brief keeps its `approved:` and `grant:`' "$SKILL" && fail "LH2g a granted re-scope no longer goes straight to queued (#101)" || pass "LH2g a granted re-scope no longer goes straight to queued (#101)"
g "LH3a a brief names a form only by quoting the repo's rule (#107)" 'A brief names a file-name, path or id form only by quoting the rule the repository enforces it'
g "LH3b with no rule it names no form (#107)" 'when it finds none, it names no form and'
g "LH3c a standing rule STAR sends is on record (#99)" 'So is every rule STAR sends a worker unasked'
g "LH3d it goes into the brief before the send (#99)" '`- <date> STAR to the <stage> worker (<subject>): <body>` to the brief'"'"'s `## Decisions` before the'
g "LH3e a one-time nudge is not a rule (#99)" 'A one-time nudge (`act`, the check-in, the report-shape re-send) is not a rule.'
g "LH4a a released dispatch is ended (#95)" 'or Orca reports that dispatch `released` with no retained reason (#95), and `stage-start.sh` closed it'
g "LH4b a failed close still ends it (#95)" 'a released dispatch whose close fails is ended all the same'
g "LH4c a released dispatch with no retained reason is ended, not kept (#95)" 'A dispatch Orca reports `released` with no retained reason is ended, not kept (#95)'
g "LH4d a released dispatch with no retained reason is not held (#95)" 'a session Orca reports `released` with no retained reason is ended, #95)'
g "LH4e gate waiters are served in arrival order (#97)" 'Waiters are served in strict arrival order'
g "LH4f STAR never raises the gate slots unasked (#97)" 'STAR never raises the slots unasked: heavy runs side by side can take the machine down.'
g "LH4g the owner may ask for a second slot (#97)" 'The owner may ask for `sh S/../ship-ticket/gate-lock.sh --slots 2` once free memory allows it.'
g "LH4h the shared gate lock's order, in the edge cases (#97)" 'the gate lock (strict arrival order with one slot, the default;'
g "LH5a a missing CI run is the owner's to look at (#102)" '`reason=ci-missing` (babysit found no CI run on the PR'"'"'s head while the PR does not conflict with its base, #102) is the owner'"'"'s to look at'
g "LH5b missing checks are never a pass (#102)" 'missing checks are never a pass, so STAR neither answers it nor restarts the stage on its own'
g "LH6a a missing hosted log is rebuilt by babysit (#96, #116)" 'when it is missing, babysit rebuilds it from the PR'"'"'s reviews and the reviewer'"'"'s summary comments (`pr-state.sh --hosted-passes`)'
g "LH6b babysit counts NOT-SAFE rounds since the newest SAFE round or push (#108)" 'A babysit run counts its NOT-SAFE rounds since the newest SAFE round or its last'
g "LH6c an unpushed SAFE round starts a fresh count (#108)" 'that could not be pushed, because the PR needed a base merge first, starts a fresh count'
g "LH7a a denied fallback run is retried once inside the round (#100)" 'is retried once inside the round, told which call was denied'
g "LH7b a second denial is gate-down (#100)" 'When the fallback fails too, or a second denial follows, the gate prints'
grep -qF 'call it made was denied so it may not have read the diff' "$SKILL" && fail "LH7c one denial is no longer gate-down (#100)" || pass "LH7c one denial is no longer gate-down (#100)"
g "LH7d a direct receipt is posted over a carried one (#104)" 'receipt is posted even when a carried receipt already names the head, #104'
# fix: strict arrival order holds with one gate slot only (#97)
g "F97a STAR: strict arrival order is for one slot, the default" 'Waiters are served in strict arrival order with one slot (the default), one gate at a time (#97);'
g "F97b STAR: with more slots the first waiters race for a freed slot" 'with more slots (the slots file says up to 4), the first waiters in the queue race for a freed slot.'
g "F97c STAR: the edge-case row says the same" 'the gate lock (strict arrival order with one slot, the default; with more slots the first waiters race for a freed slot)'
grep -qF 'Waiters are served in arrival order' "$SKILL" && fail "F97d STAR: arrival order is no longer unqualified" || pass "F97d STAR: arrival order is no longer unqualified"
# fix: a released session a person kept is still kept or held (#95)
g "F95a the kept row: a released one a person kept follows the row" 'one a person kept (`retainedReason` set, for example `user_takeover`) follows this row as before'
g "F95b the hold row: a released one a person kept is held" 'including a `released` one a person kept (`retainedReason` set);'
grep -qF 'is never kept' "$SKILL" && fail "F95c a released dispatch is no longer never kept" || pass "F95c a released dispatch is no longer never kept"
grep -qF 'never a dispatch Orca reports `released`' "$SKILL" && fail "F95d a released dispatch is no longer never held" || pass "F95d a released dispatch is no longer never held"
# lane h: STAR's contract for issues #110 to #118 and the mod
g "LH110a a merge carries only when the base changed none of the branch's files (#110)" 'none of the files the branch changes, so a merge with a conflict never carries) carries the last'
grep -qF 'git merged it cleanly, or every' "$SKILL" && fail "LH110b a mechanical conflict no longer carries (#110)" || pass "LH110b a mechanical conflict no longer carries (#110)"
g "LH110c done-check accepts a carry by the same rule (#110)" '`carry-check.sh` carries it to the PR'"'"'s head, by the rule above (#110).'
g "LH113a a round pins its base (#113)" 'Each round pins the base to one commit and records it in the review'"'"'s `Gate:`'
g "LH113b a moved base that touches the branch refuses the round (#113)" '`ERROR base-moved <ref> at <B7> changes <path>, a file this branch changes: merge it in, then run round <k>`'
g "LH113c the worker merges the base and runs the round again (#113)" '(#113): the worker merges the base in, runs the sweep and runs the same round again.'
g "LH113d the refusal is not an ERROR retry (#113)" 'That is not an `ERROR` retry: it counts toward no escalation and casts no `gate.maxRounds` vote.'
g "LH113e a disjoint base move is not acted on (#113)" 'A base that moved without touching the branch'"'"'s files is not acted on.'
g "LH113f the edge case (#113)" '| The base moves under a gate loop and changes the branch'"'"'s own files |'
g "LH117a the fallback searches with Grep and Glob (#117)" '`ERROR gate-down <why>`, never a verdict. The fallback searches with Grep and Glob, never'
g "LH117b never git grep, whose -O runs a program (#117)" '`git grep`, whose `-O` runs a program; its retry line says so too (#117).'
g "LH112a feedback on a briefing row goes to a side file (#112)" '`<the brief path>.feedback.md` (`HOME_DIR/briefs/<project>/<item>.md.feedback.md`), one line per'
g "LH112b one dated line per entry, and STAR is the only writer (#112)" 'entry: `- <YYYY-MM-DD HH:MM> <the words, line breaks folded to spaces>`. STAR is its only writer.'
g "LH112c a BRIEF adds every line the brief lacks (#112)" '(`grep -cxF '"'"'<line>'"'"' <brief>` prints 0), then delete the side file. When any line was missing,'
g "LH112d a missing line is handled as go-batch feedback (#112)" '`go-batch` "anything else" answer for that row, which they already are under `## Feedback`'
g "LH112e an ESCALATION moves the lines into the brief file (#112)" '- `ESCALATION`: put the lines under the brief file'"'"'s `## Feedback`, creating the file with only that'
g "LH112f a SPLIT copies them to each new row's brief (#112)" '- `SPLIT`: put the lines under `## Feedback` in each new row'"'"'s brief file, creating each with only'
g "LH112g a row lost or failed keeps its side file (#112)" 'A row that leaves `briefing` any other way (lost, `failed`) keeps the side file: its next brief run'
g "LH112h Messages settles the side file first (#112)" '`SPLIT` or `ESCALATION` settles the brief'"'"'s feedback side file first (#112,'
g "LH112i a briefing row's answer is not sent to its worker (#112)" 'the row stays as it is. A `briefing` row'"'"'s answer goes to the brief'"'"'s feedback side file'
g "LH112j draft-brief reads the side file at step 1 (#112)" 'Read `<--out>.feedback.md` too when it exists (#112): one line per entry, feedback STAR took'
g "LH112k draft-brief copies it right before writing (#112)" 'as below), then write the brief to `--out`. Right before writing, read `<--out>.feedback.md`'
g "LH112l only the lines the brief lacks are copied (#112)" 'again when it exists, and copy each of its lines the brief does not already hold, verbatim, under'
g "LH112m the edge case (#112)" '| The owner gives feedback while an item'"'"'s brief is drafting |'
g "LH114a a bounded prompt is the probe's own result (#114)" '`prompt bounded <terminal> <path>` (#114): the worker sits on Claude Code'"'"'s safety prompt for an'
g "LH114b STAR sends the digit 1 with no Enter (#114)" '`orca terminal send --terminal <terminal> --text "1" --json` (no `--enter`: the digit picks the'
g "LH114c the answer is on record (#114)" '`- <date> STAR answered a permission prompt for the <stage> worker: Yes (<path>)` to the brief'"'"'s'
g "LH114d three answers at most per row (#114)" '`counters.prompted=+1`. At `prompted=3`, a fourth `prompt bounded` takes the `stuck:` path below.'
g "LH114e the escalation names the prompt (#114)" '`stuck: confirmation dialog: <its line>`, so the escalation names it)'
g "LH114f never answer, except prompt bounded (#114)" 'Never answer a worker'"'"'s prompt for it, except `prompt bounded` (above, #114).'
g "LH114g the probe reads the rendered screen (#114)" 'screen (`orca terminal read --screen`), not Orca'"'"'s transcript, which shows no prompt (#114).'
g "LH114h the one exception to never answering a screen (#114)" 'user, and STAR never answers a worker'"'"'s screen for it, with one exception (#114): `prompt bounded`,'
g "LH114i the common mistake names the exception (#114)" 'The one exception is `prompt bounded` (#114): the digit `1`, never Enter |'
g "LH114j the prompted counter (#114)" '| `prompted=<n>` | Claude Code safety prompts STAR answered on this row'"'"'s worker screen (`prompt bounded`, #114) | a new worker starts |'
grep -qF 'user, and STAR never answers a worker'"'"'s screen for it. A model at capacity' "$SKILL" && fail "LH114k the old unqualified rule is gone (#114)" || pass "LH114k the old unqualified rule is gone (#114)"
grep -q 'id: claude-mods' "$SKILL" && pass "LHmod-a STAR requires claude-mods" || fail "LHmod-a STAR requires claude-mods"
g "LHmod-b the requirement is soft, with the version check" 'check: "claude --version is 2.1.287 or later"'
g "LHmod-c the fallback is the prose rules" 'fallback: no band; the coordinator'"'"'s rules hold as prose, from the SessionStart hook'
g "LHmod-d the Preflight row" '| Claude Code mods | cli | SOFT | `claude --version` is 2.1.287 or later | no band; the coordinator'"'"'s rules hold as prose, from the SessionStart hook |'
g "LHmod-e the hard rule names the mod" '- On Claude Code 2.1.287 and later, juel'"'"'s mod refuses a direct `gh pr merge` in the coordinator and in STAR'"'"'s workers, and refuses reading review, evidence, report or log files into the coordinator; on any other agent or build these rules hold as written.'
# fix-2: prompt bounded in Reconcile and the escalation-answer rule (#114)
g "FIX2a Reconcile keeps a prompt bounded worker, Housekeeping answers it (#114)" '`prompt bounded …` → keep it; Housekeeping answers it.'
g "FIX2b an escalation answer counts a prompt bounded worker as still running (#114)" 'says `ok`, `quiet …`, `stale …`, `prompt bounded …` or `stalled: …`: a worker in any of those is still running'
# the STAR dashboard (star-dashboard-server)
g "DASH1 the dashboard command row" '| `/juel:star dashboard` |'
g "DASH2 dashboard is a command word only as the whole text" '`status`, `dashboard`, `away`, `back` and `stop` are commands only when they are the whole text'
g "DASH3 the dashboard section runs dashboard.sh" '`sh S/dashboard.sh`'
g "DASH4 the dashboard needs no STAR running" 'It needs no STAR running, does not become the coordinator and writes nothing in the STAR folder.'
g "DASH5 init lists the folder in the registry" '`~/.juel/star-homes.json`'
g "DASH6 every start registers the home" 'Then `sh S/star-home.sh register`'
g "DASH7 a pick is marked recommended" 'it marks that option in the `Options:` line with a ` (recommended)` suffix'
g "DASH8 a pick says why on a Suggest line" '`Suggest: <one line, why>`'
g "DASH9 never a pick on a secret step" 'A `secret` step never gets either'
g "DASH10 the Answers step drops the suffix" 'drops a trailing ` (recommended)` from an answer before it compares command words'
g "DASH11 a slack: inbox file is not a work item" 'A file with a `slack:` block is a Slack message the dashboard'"'"'s watcher routed to this project'
g "DASH12 the Slack draft path" '`HOME_DIR/drafts/<YYYY-MM-DD>-<project>-slack-<id>.md`'
g "DASH13 the draft first line" '`to: slack <channelId> <threadTs>`'
g "DASH14 the slack-reply queue item" '--kind slack-reply --project <p> --item slack'
g "DASH15 the slack-reply options" 'Options: send (recommended) / rewrite: <how> / skip'
g "DASH16 send posts through the Slack connector" '| `slack-reply` | send |'
g "DASH17 quiet hours do not hold a send" 'Quiet hours do not hold it: the owner pressed send.'
g "DASH18 no Slack connector holds the send" 'connect Slack in Claude Code to send <draft name>'
g "DASH19 rewrite redrafts" '| `slack-reply` | `rewrite: <how>` |'
g "DASH20 skip closes it" '| `slack-reply` | skip | close it |'
g "DASH21 the home lists the Slack drafts" 'drafts/<YYYY-MM-DD>-<project>-slack-<id>.md'
g "DASH22 dashboard skips the preflight like status" '`status`, `dashboard`, `away`, `back`, `stop`, `draft-brief` and `post-report` are not a start'
g "DASH23 the slack block's thread field" 'threadTs: <ts, or ->'
g "DASH24 the slack block's channel id" 'channelId: <id>'
g "DASH25 the slack block's permalink" 'permalink: <url>'
g "DASH26 a draft for a top-level message names its own ts" '(the block'"'"'s `ts` when `threadTs` is `-`)'
g "DASH27 the reply's rules" 'at most two sentences, no greeting'
g "DASH28 a reply STAR cannot answer says the owner will check" 'reply says the owner will check'
g "DASH29 a slack: file adds no row" 'not a work item: it adds no row'
g "DASH30 the sent.log line for a Slack reply" '`<iso>\tSTAR\tslack\tslack reply <draft name>`'
g "DASH31 the reply goes in the message's thread" '(`thread_ts`)'
g "DASH32 no Slack tool writes nothing to sent.log" 'and write nothing to `sent.log`'
g "DASH33 a reply is marked sent only once it posted" 'once the post succeeds, append that line to `sent.log`'
g "DASH34 anything else asks again" '(answer send, rewrite: <how> or skip)'
g "DASH35 a failed post writes nothing to sent.log" 'A post that fails: write nothing to `sent.log`'
g "DASH36 a slack: file is checked against what STAR already raised" '`sh S/slack-handled.sh --home HOME_DIR <id>`'
g "DASH37 handled: STAR already raised the message" '`handled sent <draft name>` or `handled drafted <draft name>`: STAR already raised this message'
g "DASH38 handled: the file is deleted and nothing is raised" 'Delete the file and do nothing else: no draft, no queue item, no notification.'
g "DASH39 queue: the item is added for the draft already written" '`queue <draft path>`: the draft was written but its item never was'
g "DASH40 queue: the draft is not rewritten" 'Do not rewrite the draft.'
g "DASH41 new: the reply is drafted as before" '`new`: write the reply as a draft,'
g "DASH42 a check that could not run keeps the file" 'Anything else (a non-zero exit, or output that is not exactly one of those lines)'
g "DASH43 the held item names the file" 'slack-handled.sh could not check inbox file <name>'
g "DASH44 the file is deleted only once its item is queued" 'delete the file only once `loops.sh add` has printed the item'"'"'s id'
g "DASH45 queue: the item names the printed draft path" '`<draft path>` on its `draft:` line'

# #121: a draft brief's branch never collides with another item's or a remote branch
g "LH121a draft-brief checks the branch for a collision (#121)" 'old PR. Then check the branch for a collision (#121): compare the branch you would name against'
g "LH121b against the brief of every other ledger row (#121)" 'the `branch:` line of the brief of every other row in `<HOME_DIR>/ledger.md` (each row has its'
g "LH121c the remote and the local branches (#121)" '(`git ls-remote --heads <remote>`) and against the local branches of the main checkout'
g "LH121d next title words, then the item's own words (#121)" 'one at a time, then with distinguishing words of the item itself (a word of its ref or description'
g "LH121e the chosen slug is recorded, and checked again before writing (#121)" 'Record the chosen slug in the brief front matter as `item.slug`. Check again right before writing'
g "LH121g the item's own branch and its existingPr head are no collision (#121)" 'The branch the brief at `--out` already names, and the head branch of an `existingPr`, belong to'
g "LH121h a numeric suffix when the words run out (#121)" 'that no other item title has), then with `-2`, `-3` and so on, until the branch is unique, so a'
g "LH121f the slug rule points at the collision rule (#121)" '6 words, unless the collision rule of step 5 extends it), `title`, `url`, `path` (a `file`'
# #122: STAR's merge order counts hosted passes per distinct head
g "LH122a the merge order counts distinct heads (#122)" '`updated`. The count is of distinct heads with a `pass` line (#122). `grep -c` counts `pass` lines,'
g "LH122b the count relies on one pass line per head (#122)" 'and each one is a distinct head because `juel:babysit-pr` gives a head at most one `pass` line (a'
g "LH122c the hosted log keeps one pass line per head (#122)" '`<iso> pass <n> head=<sha>` (at most one per head) or `<iso> refresh head=<sha>` (a status refresh, or a second run on a head that already has a `pass` line, #122)'
g "LH122d babysit rewrites an older log's second pass line for one head (#122)" 'later hosted run on that head is logged `refresh`) and, in its Phase 1, rewrites a second `pass`'
grep -qF 'and is counted as written.' "$SKILL" && fail "LH122e no log is counted with two pass lines for one head (#122)" || pass "LH122e no log is counted with two pass lines for one head (#122)"
# #123: an API error at the prompt gets the capacity rule's nudges
g "LH123a the capacity rule covers stalled: api error (#123)" '`stalled: model at capacity` or `stalled: api error` (#123) → the'
g "LH123b the API error nudge, with Enter (#123)" 'orca terminal send --terminal <terminal> --text "STAR: your last model call failed with an API error. Continue where you stopped; a background command you started may still be running, so check it before you start it again." --enter --json'
g "LH123c both share the capacity counter (#123)" 'Either way `counters.capacity=+1` (both lines share the counter); at `capacity=3`, `worker-stop`, `worker-release` and the gone check, and treat it as'
g "LH123d the counter row names the API error (#123)" '| `capacity=<n>` | retry nudges sent to a worker stalled on a model at capacity or an API error (`stalled:`, #123) in one silent stretch |'
g "LH123e looking after the workers names it (#123)" 'capacity, or a worker left at an empty prompt under an `API Error:` line (#123), is a third thing'
g "LH123f the matching nudge, never both (#123)" 'capacity rule: below `capacity=3`, send the nudge that matches the line: for `stalled: model at capacity`'
g "LH123g a stalled worker becomes a lost worker (#123)" '(`stalled:`): STAR nudges it to retry, three times at most, then treats it as a lost worker (the capacity rule in'
g "LH123h the automatic restart covers an API error (#123)" '  capacity or on an API error (`stalled:`), or any worker `step-check.sh` found stuck ("Checking in"; a build only with a clean'

R126="Outside babysit's Phase 4 sync before \`READY\` and STAR's \"Sync after the base moved\", a worker merges the base in only when the PR is CONFLICTING or a gate round refuses with \`ERROR base-moved\`, never otherwise."
S124="PASS self-approved under the owner's grant"
S129="the hosted reviewer is not reviewing since <since>: <why>. Answer retry once it can review again"
has "#124 star.json documents ownerApproval" '"ownerApproval": null'
has "#124 the merge gate reads STAR's folder" '`sh S/pr-verify.sh <pr url> --head <head> --merge-gate --home HOME_DIR`'
has "#124 --hosted takes only the hosted reviewer's login" '`--hosted` takes only `hostedReviewer.login`'
has "#124 the self-approved pass is named" "$S124"
has "#125 the Inbox imports every spec-path ref" 'run `sh S/star-home.sh import <ref>` on every spec-path ref'
has "#125 the same source makes one row" 'The same source handed over twice prints the same copy, so it still makes one row.'
has "#126 the one base-merge rule" "$R126"
has "#126 a base-merge rule STAR sends quotes it whole" 'A rule about merging the base quotes this rule whole:'
has "#129 STAR handles hosted-unavailable" '`ESCALATION item=… reason=hosted-unavailable …` in a `worker_done`'
has "#129 one held item for every PR" "$S129"
has "#129 no babysit starts while the hosted reviewer is down" 'While `hostedDown` is set, start no babysit'
has "#129 star.json documents hostedDown" '"hostedDown": null'
has "#137 STAR records its gh login" '`gh api user --jq .login`'
has "#137 star.json documents ghLogin" '"ghLogin": null'
has "#137 the hook falls back to ghLogin" '`export GH_TOKEN="$(gh auth token --user <ghLogin>)"`'

# review fixes for #124-#137
S137="Record STAR's own \`gh\` login as \`ghLogin\`"
S129R='| `held` "the hosted reviewer is not reviewing…" | `retry` | set `hostedDown` to null in `star.json` and close the item'
S129C='(`grep -cE '\''^[^ ]+ pass [0-9]+ head='\'' HOME_DIR/reviews/<project>/<item>-hosted.log` prints `hostedReviewer.maxPasses`'
S125='and the reference in `ref` (for a spec path, the path `import` printed)'
S137S="STAR's own scripts do the same when \`GH_TOKEN\` is unset: \`merge.sh\`, \`pr-verify.sh\`, \`done-check.sh\` and \`codex-gate.sh post-pass\` run gh with the token \`gh-token.sh\` prints"
has "#137 STAR records its own gh login as ghLogin" "$S137"
has "#137 STAR's scripts act as the configured account" "$S137S"
has "#129 retry clears hostedDown and closes the item" "$S129R"
has "#129 the merge order counts only pass lines" "$S129C"
has "#125 the row's ref is the imported path" "$S125"
grep -qF 'the raw reference in `ref`' "$SKILL" && fail "#125 no raw reference left in the Inbox step" || pass "#125 no raw reference left in the Inbox step"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
