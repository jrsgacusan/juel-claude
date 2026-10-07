#!/bin/sh
# Runs skills/ship-ticket/screen-lock.sh with a private lock file and a stand-in worker process.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/ship-ticket/screen-lock.sh"
TMP=$(mktemp -d)
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL screen-lock.sh missing"; rm -rf "$TMP"; exit 1; }
export JUEL_SCREEN_LOCK="$TMP/screen.lock" JUEL_SCREEN_LOCK_POLL=0.2
sleep 300 & W1=$!
sleep 300 & W2=$!
trap 'kill $W1 $W2 2>/dev/null; wait $W1 $W2 2>/dev/null; sh "$SCRIPT" release --holder A >/dev/null 2>&1; sh "$SCRIPT" release --holder B >/dev/null 2>&1; rm -rf "$TMP"' EXIT

[ "$(sh "$SCRIPT" status)" = "free" ] && pass "free to begin with" || fail "initial status"
# $(...) waits for every process holding stdout: this returns only if the keeper let go of it
out=$(sh "$SCRIPT" acquire --holder A --pid $W1 --wait-max 2)
case "$out" in "held by A since "*) pass "acquire returns at once, holding" ;; *) fail "acquire ($out)" ;; esac
case "$(sh "$SCRIPT" status)" in "held by A since "*) pass "status names the holder" ;; *) fail "status ($(sh "$SCRIPT" status))" ;; esac
out=$(sh "$SCRIPT" acquire --holder B --pid $W2 --wait-max 1); rc=$?
[ $rc -eq 75 ] && case "$out" in "busy, held by A since "*) true ;; *) false ;; esac && pass "a second holder waits, then 75 naming the first" || fail "busy ($rc $out)"
sh "$SCRIPT" acquire --holder A --pid $W1 --wait-max 1 >/dev/null && pass "the holder acquiring again succeeds" || fail "re-acquire"
sh "$SCRIPT" release --holder B >/dev/null 2>&1; [ $? -eq 65 ] && pass "another holder cannot release it" || fail "foreign release"

# the worker dies: the lock frees itself
kill $W1; wait $W1 2>/dev/null; i=0; while [ $i -lt 30 ] && [ "$(sh "$SCRIPT" status)" != "free" ]; do sleep 0.2; i=$((i + 1)); done
[ "$(sh "$SCRIPT" status)" = "free" ] && pass "a dead worker frees the screen" || fail "dead worker ($(sh "$SCRIPT" status))"

# release
out=$(sh "$SCRIPT" acquire --holder B --pid $W2 --wait-max 2); case "$out" in "held by B since "*) pass "the next holder gets it" ;; *) fail "next ($out)" ;; esac
[ "$(sh "$SCRIPT" release --holder B)" = "released" ] && [ "$(sh "$SCRIPT" status)" = "free" ] && pass "release frees it" || fail "release"
[ "$(sh "$SCRIPT" release --holder B)" = "free" ] && pass "releasing a free lock is fine" || fail "release free"

sh "$SCRIPT" acquire --pid $W2 >/dev/null 2>&1; [ $? -eq 64 ] && pass "acquire without --holder is 64" || fail "usage"
sh "$SCRIPT" acquire --holder C --pid 999999 >/dev/null 2>&1; [ $? -eq 64 ] && pass "a --pid that is not running is 64" || fail "dead pid"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
