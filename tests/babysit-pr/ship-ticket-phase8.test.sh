#!/bin/sh
# ship-ticket must hand the opened PR to juel:babysit-pr as Phase 8.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
S="$ROOT/skills/ship-ticket/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
awk '/^## Phases/{p=1;next} /^## /{p=0} p' "$S" | grep -q '^8\. Babysit PR' && pass "phase 8 listed" || fail "phase 8 not in Phases"
grep -q '^### Phase 8 — Babysit PR' "$S" && pass "phase 8 section" || fail "phase 8 section missing"
grep -q '/juel:babysit-pr <pr-number> --gates' "$S" && pass "delegates with gates" || fail "delegation line missing"
grep -q 'p7 -> p8' "$S" && pass "workflow edge" || fail "workflow edge missing"
grep -q 'id: juel:babysit-pr' "$S" && pass "requirement" || fail "requirement missing"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
