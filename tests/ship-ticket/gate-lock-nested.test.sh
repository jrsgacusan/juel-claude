#!/bin/sh
# #132: gate-lock.test.sh passes when a gate runs it inside gate-lock.sh. Every lock here is a scratch
# file: JUEL_GATE_TEST_DIR moves the default lock into this test's folder, so the real machine-wide
# lock is never taken.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GL="$ROOT/skills/ship-ticket/gate-lock.sh"
SUITE="$ROOT/tests/ship-ticket/gate-lock.test.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
grep -q 'JUEL_GATE_TEST_DIR' "$GL" || { echo "FAIL #132 gate-lock.sh has no test-only default-lock override"; exit 1; }
PROBE='ok   the default lock is one file per user under /tmp, in or out of a git repo'
mkdir -p "$TMP/d1"
out=$(env -u JUEL_GATE_LOCK_HELD JUEL_GATE_TEST_DIR="$TMP/d1" JUEL_GATE_LOCK="$TMP/outer.lock" sh "$GL" --holder nested-scratch --wait-max 60 -- sh "$SUITE" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qF "$PROBE" && pass "#132 the suite passes inside a gate on a scratch lock" || { fail "#132 inside a scratch lock (rc=$rc)"; printf '%s\n' "$out" | grep '^FAIL' | head -10; }
mkdir -p "$TMP/d2"; JUEL_GATE_TEST_DIR="$TMP/d2" sh "$GL" --slots 2 >/dev/null
out=$(env -u JUEL_GATE_LOCK -u JUEL_GATE_LOCK_HELD JUEL_GATE_TEST_DIR="$TMP/d2" sh "$GL" --holder nested-default --wait-max 60 -- sh "$SUITE" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qF "$PROBE" && pass "#132 the suite passes inside a gate that holds its default lock" || { fail "#132 inside the default lock (rc=$rc)"; printf '%s\n' "$out" | grep '^FAIL' | head -10; }
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
