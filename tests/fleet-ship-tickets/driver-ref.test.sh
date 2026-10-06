#!/bin/sh
# Guards on references/fleet-driver.md: the fleet driver chat's rules.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
REF="$ROOT/references/fleet-driver.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$REF" ] || { echo "FAIL fleet-driver.md missing"; exit 1; }
for s in queued dispatched acked running escalated pr-draft done failed; do
  grep -q "\`$s\`" "$REF" && pass "state $s" || fail "state $s"
done
grep -q 'ledger.md' "$REF" && pass "ledger file" || fail "ledger file"
grep -q 'open-loops.md' "$REF" && pass "open-loops file" || fail "open-loops file"
grep -q 'ACK <item> <worktree>' "$REF" && pass "ack line" || fail "ack line"
grep -q 'ESCALATION item=' "$REF" && pass "escalation line" || fail "escalation line"
grep -q 'HELD item=' "$REF" && pass "held line" || fail "held line"
grep -qi 'deterministic' "$REF" && grep -q 'requestId' "$REF" && pass "deterministic requestId" || fail "deterministic requestId"
grep -q 'never re-run automatically\|never re-run' "$REF" && pass "failed never auto-rerun" || fail "failed rerun rule"
grep -qi 'never poll' "$REF" && pass "no polling" || fail "no polling"
grep -q 'Never merge' "$REF" && pass "never merge" || fail "never merge"
grep -q 'juel_brief: 1' "$REF" && pass "brief format" || fail "brief format"
grep -q -- '--unattended --brief' "$REF" && pass "child command" || fail "child command"
grep -q 'maxParallel' "$REF" && pass "capacity gate" || fail "capacity gate"
grep -qi 'slug' "$REF" && pass "slug when ref is null" || fail "slug rule"
grep -qi 'capability probe' "$REF" && pass "capability probe" || fail "capability probe"
grep -q 'clean-tree' "$REF" && pass "brief placement reason stated" || fail "brief placement reason"
grep -q 'Verify placement' "$REF" && pass "child placement verified" || fail "child placement check"
grep -q 'do not create' "$REF" && grep -q 'ackRetry' "$REF" && pass "ACK recovery reuses the chat" || fail "ACK recovery"
grep -q 'never held by a worker that is no longer running' "$REF" && pass "silent end frees the slot" || fail "silent end rule"
# Review stage (steps 8-10)
for s in reviewing fixing babysitting ready; do
  grep -q "\`$s\`" "$REF" && pass "state $s" || fail "state $s"
done
grep -q 'VERDICT item=<item> round=<round> SAFE' "$REF" && grep -q 'VERDICT item=<item> round=<round> NOT-SAFE' "$REF" && pass "review verdict grammar" || fail "review verdict grammar"
grep -q 'REVIEW-FINDINGS item=<item> round=<round>' "$REF" && pass "findings go back to the same worker" || fail "REVIEW-FINDINGS message"
grep -q 'NOT-SAFE`, round 3' "$REF" && pass "review rounds capped at 3" || fail "review round cap"
grep -q 'CONTINUE item=<item> phase=8' "$REF" && pass "babysit continues in the worker" || fail "CONTINUE message"
grep -q 'isDraft,reviewDecision,headRefOid,mergeable,statusCheckRollup' "$REF" && pass "exact-head verification" || fail "exact-head verification"
grep -q 'maxInReview' "$REF" && pass "separate review pool" || fail "review pool"
grep -q 'never ask a worker to' "$REF" && pass "merge never delegated" || fail "merge never delegated"
grep -q 'MERGED item=<item>' "$REF" && pass "ready becomes done only on merge" || fail "MERGED handling"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
