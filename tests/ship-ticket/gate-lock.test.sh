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

# 7. kill -9 on the wrapper: the gate command keeps running, so the lock must stay held until it ends.
sh "$SCRIPT" --holder v -- sh -c "sleep 3; date +%s > '$TMP/v.end'" &
v=$!
sleep 0.5
kill -9 "$v" 2>/dev/null; wait "$v" 2>/dev/null
sh "$SCRIPT" --holder w --wait-max 10 -- sh -c "date +%s > '$TMP/w.start'"
[ -f "$TMP/v.end" ] && [ "$(cat "$TMP/w.start")" -ge "$(cat "$TMP/v.end")" ] && pass "SIGKILLed wrapper's command still holds the lock" || fail "lock reclaimed while the killed wrapper's command ran"

# 8. SIGHUP (terminal closed) stops the whole command group and releases the lock.
sh "$SCRIPT" --holder h -- sh -c "sleep 30; echo late > '$TMP/h.late'" &
h=$!
sleep 0.5
kill -HUP "$h"; wait "$h" 2>/dev/null
sleep 0.5
[ ! -e "$LOCK" ] && pass "SIGHUP releases the lock" || fail "SIGHUP releases the lock"
sleep 1; [ ! -f "$TMP/h.late" ] && pass "SIGHUP stops the gate command" || fail "SIGHUP left the gate command running"

# 9. An empty holder file (killed mid-write) is treated like a missing one: reclaimed after the threshold.
mkdir "$LOCK"; : > "$LOCK/holder"
JUEL_GATE_LOCK_INCOMPLETE_SECONDS=0 sh "$SCRIPT" --holder e --wait-max 2 -- true; rc=$?
[ "$rc" -eq 0 ] && pass "empty holder reclaimed after the threshold" || fail "empty holder reclaimed ($rc)"

# 10. A wrapper only removes the lock if it still owns it.
sh "$SCRIPT" --holder o -- sh -c "rm -rf '$LOCK'; mkdir '$LOCK'; echo 'other 1 1 x' > '$LOCK/holder'"
[ -f "$LOCK/holder" ] && grep -q '^other ' "$LOCK/holder" && pass "release leaves another owner's lock alone" || fail "release removed another owner's lock"
rm -rf "$LOCK"

# 11. --wait-max is honoured even with a long poll interval.
sleep 30 & live=$!
mkdir "$LOCK"; printf 'other %s %s %s\n' "$live" "$live" "$(date +%s)" > "$LOCK/holder"
t0=$(date +%s); JUEL_GATE_LOCK_POLL=30 sh "$SCRIPT" --holder p --wait-max 1 -- true 2>/dev/null; rc=$?; t1=$(date +%s)
[ "$rc" -eq 75 ] && [ $((t1 - t0)) -le 3 ] && pass "wait deadline honoured with a long poll" || fail "wait deadline overshot (rc=$rc, $((t1 - t0))s)"
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null; rm -rf "$LOCK"

# 12. Outside a git repo with no JUEL_GATE_LOCK: refuse, create nothing.
(cd "$TMP" && mkdir -p nogit && cd nogit && env -u JUEL_GATE_LOCK sh "$SCRIPT" -- true 2>/dev/null); rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$TMP/nogit/juel" ] && pass "refuses outside a git repo" || fail "ran outside a git repo (rc=$rc)"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
