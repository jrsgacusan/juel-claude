#!/bin/sh
# Guards on skills/fleet-ship-tickets/SKILL.md: local intake for the fleet driver.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/fleet-ship-tickets/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
grep -q '^name: fleet-ship-tickets$' "$SKILL" && pass "name" || fail "name"
grep -q 'juel:protocol v7' "$SKILL" && pass "protocol block" || fail "protocol block"
grep -q 'id: fleet' "$SKILL" && pass "fleet dep" || fail "fleet dep"
grep -q 'mode: "driver"' "$SKILL" && pass "driver chat" || fail "driver chat"
grep -q 'references/fleet-driver.md' "$SKILL" && pass "driver rules referenced" || fail "driver rules"
grep -qi 'Approve / Edit / Drop' "$SKILL" && pass "brief approval" || fail "brief approval"
grep -q 'maxParallel' "$SKILL" && grep -q 'default 3' "$SKILL" && pass "capacity default" || fail "capacity default"
grep -q 'quietHours' "$SKILL" && pass "quiet hours" || fail "quiet hours"
grep -q '`status`' "$SKILL" && pass "status mode" || fail "status mode"
grep -q 'chat_resume' "$SKILL" && pass "resume offered" || fail "resume"
grep -qi 'Never merge' "$SKILL" && pass "never merge" || fail "never merge"
grep -qi 'domain tool' "$SKILL" && pass "prefix resolved" || fail "prefix resolution"
grep -qi 'Do not invoke `juel:daily-worktrees`' "$SKILL" && pass "no local worktrees" || fail "daily-worktrees rule"
grep -qi 'not monitoring' "$SKILL" && pass "says not monitoring" || fail "monitoring statement"
grep -q 'projectId' "$SKILL" && pass "projectId resolution" || fail "projectId"
grep -qi 'slug' "$SKILL" && pass "slug when ref is null" || fail "slug rule"
grep -q 'fleet-ship-tickets' "$ROOT/README.md" && pass "README row" || fail "README row"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
