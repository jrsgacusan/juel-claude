#!/bin/sh
# Guards on skills/ship-tickets/SKILL.md: the local Orca coordinator.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/ship-tickets/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }

if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
grep -q '^name: ship-tickets$' "$SKILL" && pass "name" || fail "name"
grep -q 'juel:protocol v7' "$SKILL" && pass "protocol block" || fail "protocol block"
grep -q 'id: orca-terminal' "$SKILL" && pass "Orca terminal precondition" || fail "Orca terminal precondition"
grep -qi 'Approve / Edit / Drop' "$SKILL" && pass "brief approval" || fail "brief approval"
grep -q '"maxParallel": 3' "$SKILL" && grep -q '"maxInReview": 3' "$SKILL" && pass "pool defaults" || fail "pool defaults"
grep -q 'caffeinate' "$SKILL" && pass "keeps the Mac awake" || fail "caffeinate"
grep -q -- '--timeout-ms 540000' "$SKILL" && pass "bounded waits" || fail "bounded waits"
for s in queued building pr-draft reviewing fixing babysitting ready done escalated failed; do
  grep -q "\`$s\`" "$SKILL" && pass "state $s" || fail "state $s"
done
for c in '/juel:ship-ticket --unattended --brief' '--fix-review' '/juel:babysit-pr <n> --unattended --mark-ready --item <item>' 'VERDICT item=<item> round=<k>'; do
  grep -qF -- "$c" "$SKILL" && pass "stage: $c" || fail "stage: $c"
done
# Worktree is created and renamed before the build worker starts.
c=$(grep -n 'orca worktree create' "$SKILL" | head -1 | cut -d: -f1)
r=$(grep -n 'branch -m' "$SKILL" | head -1 | cut -d: -f1)
w=$(grep -n 'worker-start --task' "$SKILL" | head -1 | cut -d: -f1)
[ -n "$c" ] && [ -n "$r" ] && [ -n "$w" ] && [ "$c" -lt "$r" ] && [ "$r" -lt "$w" ] && pass "worktree created, renamed, then the worker starts" || fail "create/rename/start order ($c $r $w)"
grep -q 'free + inactive' "$SKILL" && grep -q '3 GB' "$SKILL" && pass "memory check" || fail "memory check"
grep -q 'lacks the line its stage owes' "$SKILL" && pass "missing line is failed" || fail "missing-line rule"
grep -q 'run-use --id' "$SKILL" && pass "resume rebinds" || fail "resume rebinds"
grep -q 'worker-release --dispatch' "$SKILL" && pass "workers released" || fail "worker-release"
grep -q 'PushNotification' "$SKILL" && pass "notifies the user" || fail "notification"
grep -q '30 min' "$SKILL" && pass "unanswered questions escalate" || fail "question timeout"
grep -q 'isDraft,reviewDecision,reviews,commits,headRefOid,mergeable,statusCheckRollup' "$SKILL" && pass "exact-head check" || fail "exact-head check"
grep -qi 'Never merge' "$SKILL" && pass "never merge" || fail "never merge"
grep -q 'ship-tickets' "$ROOT/README.md" && pass "README row" || fail "README row"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
