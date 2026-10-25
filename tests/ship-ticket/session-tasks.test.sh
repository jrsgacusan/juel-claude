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
[ "$out" = "$(printf 'session 2\nsession 4\nuntil 2\nnext 1')" ] && [ "$rc" -eq 0 ] && pass "S2 an absent ledger is empty" || fail "S2 (rc $rc: $out)"

printf 'Task 1: complete (commit abc)\nTask 2: complete (session, commits a..b, tests: x → ok)\n' > "$TMP/l3.md"
run "$P" --ledger "$TMP/l3.md"
[ "$out" = "$(printf 'session 2\nsession 4\nuntil 4\nnext 3')" ] && [ "$rc" -eq 0 ] && pass "S3 a session completion moves the stop on" || fail "S3 (rc $rc: $out)"

printf 'Task 2: complete (commit abc)\n' > "$TMP/l4.md"
run "$P" --ledger "$TMP/l4.md"
[ "$out" = "$(printf 'session 2\nsession 4\nran 2\nuntil 4\nnext 1')" ] && [ "$rc" -eq 1 ] && pass "S4 an executor-run session task is reported and fails" || fail "S4 (rc $rc: $out)"

printf 'Task 2: complete (session, x)\nTask 4: complete (session, y)\n' > "$TMP/l5.md"
run "$P" --ledger "$TMP/l5.md"
[ "$out" = "$(printf 'session 2\nsession 4\nnext 1')" ] && [ "$rc" -eq 0 ] && pass "S5 no until once every session task is done" || fail "S5 (rc $rc: $out)"

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

# next / foreign (#196, #203): where to resume, and a ledger that belongs to another plan
run "$P" --ledger "$TMP/none.md"
[ "$(printf '%s\n' "$out" | tail -n 1)" = "next 1" ] && pass "S9 an absent ledger resumes at the first task" || fail "S9 (rc $rc: $out)"

run "$P" --ledger "$TMP/l3.md"
[ "$(printf '%s\n' "$out" | tail -n 1)" = "next 3" ] && [ "$rc" -eq 0 ] && pass "S10 next is the first task without a complete line, of any kind" || fail "S10 (rc $rc: $out)"

printf 'Task 1: complete (a)\nTask 2: complete (session, b)\nTask 3: complete (c)\nTask 4: complete (session, d)\n' > "$TMP/l11.md"
run "$P" --ledger "$TMP/l11.md"
[ "$(printf '%s\n' "$out" | tail -n 1)" = "next none" ] && [ "$rc" -eq 0 ] && pass "S11 next none when every task is complete" || fail "S11 (rc $rc: $out)"

printf 'Task 1: complete (a)\nTask 3: complete (c)\n' > "$TMP/l12.md"
run "$P" --ledger "$TMP/l12.md"
[ "$(printf '%s\n' "$out" | tail -n 1)" = "next 2" ] && pass "S12 a gap in the ledger is where it resumes" || fail "S12 (rc $rc: $out)"

printf '# SDD ledger \xe2\x80\x94 plan: docs/plans/other-plan.md\nTask 1: complete (a)\n' > "$TMP/l13.md"
run "$P" --ledger "$TMP/l13.md"
[ "$(printf '%s\n' "$out" | tail -n 1)" = "foreign docs/plans/other-plan.md" ] && [ "$rc" -eq 1 ] && ! printf '%s' "$out" | grep -q '^next' && pass "S13 a ledger naming another plan is foreign, exit 1, no next" || fail "S13 (rc $rc: $out)"

printf '# SDD ledger \xe2\x80\x94 plan: docs/plans/other-plan.md\nTask 1: complete (a)\nTask 2: complete (b)\n' > "$TMP/l13b.md"
run "$P" --ledger "$TMP/l13b.md"
[ "$out" = "$(printf 'session 2\nsession 4\nforeign docs/plans/other-plan.md')" ] && [ "$rc" -eq 1 ] && pass "S13b a foreign ledger prints the session lines and foreign only: no ran, until or next" || fail "S13b (rc $rc: $out)"

printf '# SDD ledger \xe2\x80\x94 plan: some/dir/plan.md\nTask 1: complete (a)\n' > "$TMP/l14.md"
run "$P" --ledger "$TMP/l14.md"
[ "$(printf '%s\n' "$out" | tail -n 1)" = "next 2" ] && [ "$rc" -eq 0 ] && pass "S14 the same plan file name under another directory is not foreign" || fail "S14 (rc $rc: $out)"

printf '# SDD ledger \xe2\x80\x94 plan: docs/plans/plan.md\n' > "$TMP/l15.md"
run "$P" --ledger "$TMP/l15.md"
[ "$(printf '%s\n' "$out" | tail -n 1)" = "next 1" ] && pass "S15 a header-only ledger resumes at the first task" || fail "S15 (rc $rc: $out)"

run "$TMP/p6.md" --ledger "$TMP/none.md"
[ "$out" = "next 1" ] && pass "S16 next is printed for a plan with no session task" || fail "S16 (rc $rc: $out)"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
