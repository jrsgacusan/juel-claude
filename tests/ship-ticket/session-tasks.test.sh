#!/bin/sh
# Runs skills/ship-ticket/session-tasks.sh against fixture plans and ledgers (#158).
# Usage: sh tests/ship-ticket/session-tasks.test.sh   (exit 0 = all cases pass)
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/ship-ticket/session-tasks.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL session-tasks.sh missing"; exit 1; }

P="$TMP/plan.md"
cat > "$P" <<'PLAN'
# A plan

### Task 1: one

Do a thing.

### Task 2: two

**Run:** session

Do another.

### Task 3: three

Plain.

### Task 4: four
**Run:** session
PLAN
run() { out=$(sh "$SCRIPT" "$@" 2>/dev/null); rc=$?; }

run "$P"
[ "$out" = "$(printf 'session 2\nsession 4')" ] && [ "$rc" -eq 0 ] && pass "S1 session tasks in plan order" || fail "S1 (rc $rc: $out)"

run "$P" --ledger "$TMP/none.md"
[ "$out" = "$(printf 'session 2\nsession 4\nuntil 2')" ] && [ "$rc" -eq 0 ] && pass "S2 an absent ledger is empty" || fail "S2 (rc $rc: $out)"

printf 'Task 1: complete (commit abc)\nTask 2: complete (session, commits a..b, tests: x → ok)\n' > "$TMP/l3.md"
run "$P" --ledger "$TMP/l3.md"
[ "$out" = "$(printf 'session 2\nsession 4\nuntil 4')" ] && [ "$rc" -eq 0 ] && pass "S3 a session completion moves the stop on" || fail "S3 (rc $rc: $out)"

printf 'Task 2: complete (commit abc)\n' > "$TMP/l4.md"
run "$P" --ledger "$TMP/l4.md"
[ "$out" = "$(printf 'session 2\nsession 4\nran 2\nuntil 4')" ] && [ "$rc" -eq 1 ] && pass "S4 an executor-run session task is reported and fails" || fail "S4 (rc $rc: $out)"

printf 'Task 2: complete (session, x)\nTask 4: complete (session, y)\n' > "$TMP/l5.md"
run "$P" --ledger "$TMP/l5.md"
[ "$out" = "$(printf 'session 2\nsession 4')" ] && [ "$rc" -eq 0 ] && pass "S5 no until once every session task is done" || fail "S5 (rc $rc: $out)"

cat > "$TMP/p6.md" <<'PLAN'
### Task 1: one

Intro line.
**Run:** session
PLAN
run "$TMP/p6.md"
[ -z "$out" ] && [ "$rc" -eq 0 ] && pass "S6 a marker on the second non-blank line is not a session task" || fail "S6 (rc $rc: $out)"

run
[ "$rc" -eq 64 ] && pass "S7 no plan is a usage error" || fail "S7 (rc $rc)"

run "$TMP/missing.md"
[ "$rc" -eq 64 ] && pass "S8 an unreadable plan is a usage error" || fail "S8 (rc $rc)"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
