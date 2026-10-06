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
grep -q 'juel:protocol v7' "$SKILL" && pass "protocol block" || fail "protocol block"
for id in orca-terminal star-home; do grep -q "id: $id" "$SKILL" && pass "requires $id" || fail "requires $id"; done
for m in '`/juel:star add' '`/juel:star status`' '`/juel:star stop`' 'draft-brief <ref> --project <name> --out <path>'; do
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
grep -q 'JUEL_STAR_HOME' "$SKILL" && pass "home override" || fail "home override"
grep -q 'git init' "$SKILL" && grep -q 'template' "$SKILL" && pass "first run creates the docs repo" || fail "first run"
grep -q 'orca terminal send --terminal' "$SKILL" && pass "add nudges STAR" || fail "add nudge"
grep -q 'the item waits in the inbox' "$SKILL" && pass "add works when STAR is down" || fail "add when STAR is down"
grep -q 'at most 12 lines' "$SKILL" && grep -q 'never opens a review' "$SKILL" && pass "STAR reads one line, never the files" || fail "small-context rule"
grep -q 'NOTE:' "$SKILL" && grep -q 'memory/<project>.md' "$SKILL" && pass "notes appended to project memory" || fail "memory notes"
grep -q 'state: idle' "$SKILL" && grep -q 'ends its turn' "$SKILL" && pass "idle ends the turn" || fail "idle rule"
grep -q 'restart-or-drop' "$SKILL" && grep -q 'restarts once' "$SKILL" && pass "restart recovery" || fail "restart recovery"
grep -q 'git commit' "$SKILL" && grep -q 'never fatal' "$SKILL" && pass "commit per tick, push never fatal" || fail "commit rule"
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
grep -q -- 'check --ack <delivery_id> --wait' "$SKILL" && pass "F4 deliveries acknowledged" || fail "F4 ack"
grep -q 'issue-<n>' "$SKILL" && grep -q -- '--item <name>' "$SKILL" && grep -q '| item | ref | project |' "$SKILL" && pass "F5 one item name everywhere" || fail "F5 item naming"
grep -q '## Decisions' "$SKILL" && grep -q -- '--feedback' "$SKILL" && pass "F7 answers reach the restarted stage" || fail "F7 decisions"
grep -q 'cursor=<iso>' "$SKILL" && grep -q 'MERGED item=' "$SKILL" && pass "F7/F8 escalation cursor and worker-seen merges" || fail "F7/F8 cursor, MERGED"
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
grep -q 'One STAR per home' "$SKILL" && grep -q 'orca terminal list --json' "$SKILL" && pass "S2 one STAR per home" || fail "S2 second STAR not refused"
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
grep -q '"notified"' "$SKILL" && ! grep -q 'notifiedThrough' "$T/star.json" && [ "$(grep -c 'notifiedThrough' "$SKILL")" = 1 ] && pass "S14 notifications tracked per item" || fail "S14 notified list"
grep -q 'memory below 3 GB' "$SKILL" && pass "S14 a long memory hold reaches the user" || fail "S14 memory hold"
grep -q '30 min from now' "$SKILL" && pass "S14 a question's deadline is set when it is asked" || fail "S14 question deadline"
grep -q 'repo path, never by name' "$SKILL" && pass "S17 projects are matched by repo path" || fail "S17 project identity"
grep -q 'ESCALATION item=<name> phase=0 reason=needs-human-input' "$SKILL" && ! grep -q 'item=<ref> phase=0' "$SKILL" && pass "S11 brief escalations carry the item name" || fail "S11 brief escalation name"
grep -q 'first 12 lines' "$SKILL" && grep -q 'BRIEF-VIOLATION:' "$SKILL" && grep -q 'need no action' "$SKILL" && pass "S11 every report line has a rule" || fail "S11 report grammar"
grep -q 'A-Za-z0-9._-' "$SKILL" && pass "S1 item names are safe as paths" || fail "S1 item name rule"
grep -q 'no task' "$SKILL" && grep -q 'lost twice' "$SKILL" && pass "S18 rows that never started and second losses are defined" || fail "S18 reconcile gaps"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["notified"]==[]' "$T/star.json" && pass "template star.json has the notified list" || fail "template notified"
# Review of the stress fixes
grep -q 'A `question` is always answered with `reply`' "$SKILL" && grep -q 'An `escalation` answer for a row whose worker is still running' "$SKILL" && pass "R1 a waiting worker gets its reply, not a side message" || fail "R1 question vs running-worker rule"
grep -q 'creating the file with only that section' "$SKILL" && grep -q 'before step 2' "$SKILL" && pass "R2 a brief-stage answer reaches the step that asked" || fail "R2 brief escalation answer"
grep -q 'no-safe-verdict' "$SKILL" && grep -q 'a new review round' "$SKILL" && pass "R3 a head with no SAFE review goes back to review" || fail "R3 no-safe-verdict route"
grep -q 'Bring an older home up to date' "$SKILL" && pass "R8 older homes are migrated on resume" || fail "R8 migration"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
