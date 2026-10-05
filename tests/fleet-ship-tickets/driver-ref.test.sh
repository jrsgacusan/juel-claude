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
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
