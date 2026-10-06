#!/bin/sh
# Runs skills/ship-ticket/gate-lock.sh against a scratch lock path.
# Usage: sh tests/ship-ticket/gate-lock.test.sh   (exit 0 = all cases pass)
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/ship-ticket/gate-lock.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL gate-lock.sh missing"; exit 1; }

LOCK="$TMP/gate.lock"
export JUEL_GATE_LOCK="$LOCK" JUEL_GATE_LOCK_POLL=0.2

# 1. A free lock: the command runs, its exit code passes through, the lock is gone after.
sh "$SCRIPT" --holder t1 -- sh -c 'exit 3'; rc=$?
[ "$rc" -eq 3 ] && pass "exit code passes through" || fail "exit code passes through ($rc)"
[ ! -e "$LOCK" ] && pass "lock released after the command" || fail "lock released after the command"

# 2. Held by a live process: give up after --wait-max with exit 75 and leave the lock alone.
sleep 30 & live=$!
mkdir "$LOCK"; printf 'other %s %s\n' "$live" "$(date +%s)" > "$LOCK/holder"
sh "$SCRIPT" --holder t2 --wait-max 1 -- true 2>/dev/null; rc=$?
[ "$rc" -eq 75 ] && pass "busy lock returns 75" || fail "busy lock returns 75 ($rc)"
[ -f "$LOCK/holder" ] && grep -q "^other $live " "$LOCK/holder" && pass "live holder kept" || fail "live holder kept"
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null

# 3. Held by a dead process: reclaimed at once.
sh "$SCRIPT" --holder t3 --wait-max 1 -- true; rc=$?
[ "$rc" -eq 0 ] && pass "dead holder reclaimed" || fail "dead holder reclaimed ($rc)"
[ ! -e "$LOCK" ] && pass "reclaimed lock released" || fail "reclaimed lock released"

# 4. An acquisition that never wrote its holder: reclaimed once older than the threshold.
mkdir "$LOCK"
JUEL_GATE_LOCK_INCOMPLETE_SECONDS=0 sh "$SCRIPT" --holder t4 --wait-max 2 -- true; rc=$?
[ "$rc" -eq 0 ] && pass "holderless lock reclaimed after the threshold" || fail "holderless lock reclaimed ($rc)"

# 5. Two gates never overlap: the second starts after the first ends.
sh "$SCRIPT" --holder a -- sh -c "date +%s > '$TMP/a.start'; sleep 2; date +%s > '$TMP/a.end'" &
first=$!
sleep 0.5
sh "$SCRIPT" --holder b --wait-max 10 -- sh -c "date +%s > '$TMP/b.start'"
wait "$first"
[ "$(cat "$TMP/b.start")" -ge "$(cat "$TMP/a.end")" ] && pass "second gate waits for the first" || fail "gates overlapped"

# 6. Killing the holder releases the lock.
sh "$SCRIPT" --holder k -- sleep 30 &
k=$!
sleep 0.5
kill -TERM "$k"; wait "$k" 2>/dev/null
sleep 0.2
[ ! -e "$LOCK" ] && pass "lock released when the holder is killed" || fail "lock released when the holder is killed"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
