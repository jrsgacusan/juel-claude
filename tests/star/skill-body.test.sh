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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
