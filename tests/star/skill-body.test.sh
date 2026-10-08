#!/bin/sh
# Guards on skills/star/SKILL.md: the permanent local coordinator.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/star/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }
[ -d "$ROOT/skills/ship-tickets" ] && fail "ship-tickets removed" || pass "ship-tickets removed"
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
grep -q '^name: star$' "$SKILL" && pass "name" || fail "name"
grep -q 'juel:protocol v9' "$SKILL" && pass "protocol block" || fail "protocol block"
for id in orca-terminal git-repo; do grep -q "id: $id" "$SKILL" && pass "requires $id" || fail "requires $id"; done
for m in '`/juel:star SPH-11 and SPH-12`' '`/juel:star status`' '`/juel:star stop`' 'draft-brief <ref> --project <name> --out <path>'; do
  grep -qF -- "$m" "$SKILL" && pass "mode $m" || fail "mode $m"
done
for s in inbox briefing brief-ready queued building pr-draft reviewing fixing babysit-queued babysitting verifying ready done escalated failed dropped; do
  grep -q "\`$s\`" "$SKILL" && pass "state $s" || fail "state $s"
done
for c in 'loops.sh' 'pr-verify.sh' 'worker-probe.sh' 'release-record.sh'; do
  grep -q "$c" "$SKILL" && pass "uses $c" || fail "uses $c"
done
for k in approve-brief merge-pr escalation question restart-or-drop draft held; do
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
grep -qi 'Never merge' "$SKILL" && pass "never merge" || fail "never merge"
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
grep -q 'exactly `approve`' "$SKILL" && pass "F18 approval is exact" || fail "F18 exact approval"
grep -q 'HH:MM-HH:MM@tz' "$SKILL" && pass "F19 quiet-hours rendering" || fail "F19 quiet hours format"
grep -q 'moved' "$SKILL" && grep -q 'round + 1' "$SKILL" && pass "F18 round and moved counters" || fail "F18 counters"
# Handoff: away, night summaries, back
grep -qF '`/juel:star away`' "$SKILL" && grep -qF '`/juel:star back`' "$SKILL" && pass "away and back commands" || fail "away/back commands"
for c in start due summary end; do grep -q "handoff.sh --home HOME_DIR $c" "$SKILL" && pass "uses handoff.sh $c" || fail "uses handoff.sh $c"; done
grep -q -- '--quiet-hours always' "$SKILL" && pass "away holds reviewer-facing actions" || fail "away quiet mode"
grep -q 'sent.log' "$SKILL" && grep -q 'SENT ' "$SKILL" && pass "messages sent are logged" || fail "sent log"
grep -q 'in the same turn' "$SKILL" && pass "chat answers are relayed in the same turn" || fail "same-turn relay"
grep -q 'control: away' "$SKILL" && pass "away works from any session" || fail "away from anywhere"
grep -q 'one place to answer' "$SKILL" && pass "handoff never collects answers" || fail "single answer place"
# Stress test pass fixes
T="$ROOT/skills/star/template"
grep -q '`fix-queued`' "$SKILL" && ! grep -q 'findings waiting' "$SKILL" && pass "S12 a waiting fix is its own state" || fail "S12 fix-queued state"
grep -q '| verify | counters | updated |' "$SKILL" && grep -q '| verify | counters | updated |' "$T/ledger.md" && pass "S12 counters have a ledger cell" || fail "S12 counters column"
grep -q 'miss=1' "$SKILL" && grep -q 'unknown=' "$SKILL" && grep -q 'silent=' "$SKILL" && grep -q 'hold=' "$SKILL" && grep -q 'moved=' "$SKILL" && grep -q 'pending=' "$SKILL" && pass "S12 every counter is named" || fail "S12 counter names"
grep -q '## Feedback' "$SKILL" && pass "S12 brief feedback is kept in the brief" || fail "S12 feedback storage"
grep -q 'One STAR per home' "$SKILL" && grep -q 'orca terminal list --limit 500 --json' "$SKILL" && pass "S2 one STAR per home" || fail "S2 second STAR not refused"
grep -q 'Match by dispatch' "$SKILL" && grep -q 'superseded' "$SKILL" && pass "S2 messages matched by dispatch id" || fail "S2 message matching"
grep -q 'the same item: no new row' "$SKILL" && pass "S10 a repeated ref is not a second item" || fail "S10 repeated ref"
grep -q 'named in another open row' "$SKILL" && pass "S10 a worktree is never shared by two rows" || fail "S10 shared worktree"
grep -q 'queue items first' "$SKILL" && pass "S2 one order of effects per message" || fail "S2 effect order"
grep -q 'worker-stop' "$SKILL" && grep -q 'never starts a second worker' "$SKILL" && pass "S18 answers never double a running worker" || fail "S18 answer on a running worker"
grep -q 'add the same `merge-pr` item again' "$SKILL" && pass "S18 a merge reminder is not lost to a chat answer" || fail "S18 merge-pr reminder"
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
grep -q 'no-safe-verdict' "$SKILL" && grep -q 'a new review round' "$SKILL" && pass "R3 a head with no SAFE review goes back to review" || fail "R3 no-safe-verdict route"
# Second stress pass
grep -q 'last=<message id>' "$SKILL" && grep -q 'already applied' "$SKILL" && pass "T3 a replayed message is recognised by the row itself" || fail "T3 replay by message id"
grep -q 'cannot be read, STOP' "$SKILL" && grep -q 'read it back' "$SKILL" && grep -q 'take over' "$SKILL" && pass "T2 one STAR per home fails closed, with a way to take over" || fail "T2 coordinator lock"
grep -q 'a ref whose earlier row is `done` or `dropped`' "$SKILL" && pass "T4 a re-added ref gets its own name" || fail "T4 re-added ref"
grep -q -- '--project - --item' "$SKILL" && pass "T7 a message with no row has a place in the queue" || fail "T7 unmatched message"
grep -q 'strip punctuation' "$SKILL" && grep -q 'no letter or digit' "$SKILL" && pass "T16 answers are read without their punctuation" || fail "T16 answer punctuation"
grep -q 'clears every counter except `hold=`, `last=`, `start=`, `screen=` and `tracker=`' "$SKILL" && pass "T16 a retry answer clears the old counts" || fail "T16 counters on answer"
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
g "V1 away, back and stop are not a start" '`status`, `away`, `back`, `stop`, `draft-brief` and `post-report` are not a start'
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
g "V15 a quiet worker is still a running worker" '`ok` or `quiet'
g "V16 a second answer cannot revive a dropped row" 're-read the row'
g "V17 the automatic restart is per stage" '`restarts` goes back to 0'
g "V18 a brief without criteria is not built on a bare approve" 'still says `NEEDS CRITERIA`'
g "V19 a SAFE verdict needs a real head" 'A run shorter than 7 is not a verdict babysit can use'
g "V20 a check that prints nothing is pending" 'no line, or an exit that is not 0'
g "V21 an unreadable quiet window holds, for STAR too" 'anything but exit 0 with exactly `inside` or `outside`'
g "V22 an approval of an earlier commit is said so" 'approved on an earlier commit'
g "V23 the feedback cursor is passed back as it is" 'opaque'
g "V26 a lost queue item is noticed" '`missing`'
g "V29 inbox files are read in order" 'in file-name order'
g "V30 back runs a tick" 'then run a tick'
# Best model per stage
g "M1 each stage has its own model setting" '"stages"'
g "M1 a stage reads its own entry" 'stages.<stage>'
g "M2 the coordinator runs on Fable 5.1" 'Fable 5.1'
g "M3 a stage whose model cannot start falls back" 'falls back to `worker`'
g "M4 build, fix and babysit run the plan in their own session" '--executor session'
python3 - "$T/star.json" <<'PY2' && pass "M5 template: the best model per stage" || fail "M5 template stages"
import json, sys
d = json.load(open(sys.argv[1])); s = d["stages"]
assert set(s) == {"brief", "build", "fix", "review", "babysit", "screen", "post"}, sorted(s)
assert s["brief"] == {"agent": "claude", "model": "opus", "effort": "xhigh"}, s["brief"]
for k in ("build", "fix", "babysit", "screen"):
    assert s[k] == {"agent": "claude", "model": "opus", "effort": "xhigh", "executor": "session"}, (k, s[k])
assert s["post"] == s["brief"], s["post"]
assert s["review"] == {"agent": "codex", "model": "gpt-6-astra", "effort": "xhigh"}, s["review"]
assert d["worker"] == {"agent": "claude", "model": "opus", "effort": "xhigh"} and d["reviewer"] == s["review"]
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
g "I12 a settled reviewer's verdict is read from its file" 'head -n 1'
g "I7 a stalled prompt names the trust dialog" 'agent_prompt_stalled'
g "I7 dialogs that cannot be cleared reach the user" 'hold trust <path>'
g "I9 a worktree inside the repo is excluded" '.git/info/exclude'
g "I18 builds keep a slot while briefs draft" '`maxParallel - 1`'
grep -q 'reviewer-prompt.md' "$SKILL" && [ -f "$T/reviewer-prompt.md" ] && pass "the reviewer prompt is a template" || fail "reviewer template"
! grep -q 'payload.dispatchId' "$SKILL" && ! grep -q "orca orchestration task-create --spec" "$SKILL" && pass "no hand-rolled message reading or task creation left" || fail "hand-rolled steps left"
# Questions and the intake
g "Q1 a worker sets its own deadline" 'deadline=<minutes>'
g "Q2 a new ask supersedes the open one" 'Superseded by your newer question.'
g "Q3 one reminder before No answer" 'still waiting on you'
g "Q3 the reminder is counted" '`reask=1`'
g "B1 the intake section" '## Before you go'
g "B2 the brief's questions are queued" '--kind prep'
g "B3 the intake asks between ticks only" 'Between ticks, never inside one'
g "B4 a skipped decision takes its default" 'default taken'
g "B5 screen checks wait for the user" '`screen-queued`'
g "B5 the screen stage" '--screen-checks'
g "B5 the screen report" 'VERIFIED item='
g "B6 STAR decides an in-scope product call while you are away" 'decided while you were away'
g "B7 the brief report counts its asks" 'asks=<n>'
g "B8 later ends the walk-through" '"later" as any answer'
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
g "FR1 a retry keeps the attempt number, screen checks and status" '`counters=keep:hold,last,start,screen,tracker`'
g "FR2 lost screen-check and post workers restart once" 'a `briefing`, `reviewing`, `screening`, `posting` or `babysitting` row restarts once'
g "FR2 a restarted post worker does not post twice" 'already starts with the report'
g "FR6 stage-start runs in the background" 'like `gate-lock.sh` in a worker'
g "FR6 a start that printed nothing is replayed" '| no line, or a non-zero exit |'
g "FR12 failed screen checks can reach a fix" 'reads the failed checks as missed acceptance criteria'
grep -q 'a screen check recorded there as failed' "$T/reviewer-prompt.md" && pass "FR12 the reviewer reads failed screen checks" || fail "FR12 reviewer prompt"
# Finished worktrees (#19)
g "W1 finished worktrees are removed" 'sh S/worktree-clean.sh <item>'
g "W2 a kept worktree waits for the user" '`kept=1`'
g "W3 never with work in it" 'never with work in it'
# Issue #22
g "L1 head= is its leading hex run" 'leading run of hex characters'
grep -qF 'Never type \n inside a quoted --body' "$T/reviewer-prompt.md" && pass "L2 the reviewer sends real line breaks" || fail "L2 reviewer prompt"
# Issue #25
g "K1 a refused check-in is not a nudge" 'agent_prompt_blocked'
g "K2 busy has its own count" '`busy=<n>`'
g "K3 a long busy stretch goes to the user" 'silent and busy for 2 h'
# Issue #27
g "Z4 the exact-head check knows an explicit zero" 'PASS no approval required'
g "Z5 a repository gh cannot see goes to the user" 'export GH_TOKEN for <repo>'
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
g "C2 their own approve title" 'approve brief — criteria are proposed'
g "C3 the marker is removed on approval" 'remove each ` (proposed)` suffix'
g "C4 a re-draft keeps proposed criteria marked" 'on every re-draft, keep the earlier draft'
# Issue #29
g "Q1 plain chat, one question per message" 'one question per message'
g "Q2 the recommended option is labelled" '(Recommended)'
g "Q3 a nudge is never an answer" 'is never an answer'
g "Q4 the picker only before any worker" 'AskUserQuestion only for the first-run setup question, before any worker exists'
grep -qF 'AskUserQuestion only in the intake' "$SKILL" && fail "Q5 the old hard rule is gone" || pass "Q5 the old hard rule is gone"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
