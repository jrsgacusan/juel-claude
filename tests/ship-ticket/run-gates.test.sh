#!/bin/sh
# Runs skills/ship-ticket/run-gates.sh against scratch gate manifests.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/ship-ticket/run-gates.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL run-gates.sh missing"; exit 1; }
mkdir -p "$TMP/repo/packages/api" "$TMP/repo/packages/my web"; R=$(cd "$TMP/repo" && pwd -P)
m() { printf '%s\n' "$1" > "$TMP/gates.json"; }
run() { (cd "$R/packages/api" && sh "$SCRIPT" "$TMP/gates.json" --root "$R" "$@"); }

m '{"test":{"cmd":"pwd > '"$TMP"'/t.pwd","cwd":"packages/api"},"lint":{"cmd":"pwd > '"$TMP"'/l.pwd","cwd":"packages/my web"},"typecheck":null,"build":{"cmd":"pwd > '"$TMP"'/b.pwd","cwd":"."}}'
run >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$TMP/t.pwd")" = "$R/packages/api" ] && [ "$(cat "$TMP/l.pwd")" = "$R/packages/my web" ] && [ "$(cat "$TMP/b.pwd")" = "$R" ] && pass "each gate runs in its own cwd, taken from the root, spaces and all" || fail "gate cwd (rc=$rc)"
# a command with quotes, && and an env assignment runs exactly as written
m '{"test":{"cmd":"X=1 sh -c '"'"'printf \"%s\" \"it'"'"'\\'"'"''"'"'s $X\" > '"$TMP"'/q.out'"'"' && echo second >> '"$TMP"'/q.out","cwd":"."},"lint":null,"typecheck":null,"build":null}'
run >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q "it's 1second" "$TMP/q.out" && pass "quotes, && and VAR=value in a command survive" || fail "quoted command (rc=$rc: $(cat "$TMP/q.out" 2>/dev/null))"
# the first red gate stops the run with its own exit code; later gates do not run
rm -f "$TMP/after"
m '{"test":{"cmd":"exit 3","cwd":"."},"lint":{"cmd":"touch '"$TMP"'/after","cwd":"."},"typecheck":null,"build":null}'
err=$(run 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 3 ] && [ ! -e "$TMP/after" ] && case "$err" in *"test failed (exit 3)"*) true ;; *) false ;; esac && pass "a red gate stops the run and names itself" || fail "red gate (rc=$rc $err)"
# only the named gates
rm -f "$TMP/after"; run lint >/dev/null 2>&1; [ $? -eq 0 ] && [ -e "$TMP/after" ] && pass "gates can be picked by name" || fail "picking a gate"
m '{"test":null,"lint":null,"typecheck":null,"build":null}'
out=$(run 2>&1); [ $? -eq 0 ] && case "$out" in *"no gates"*) pass "an all-null manifest is green and says so" ;; *) fail "all-null manifest ($out)" ;; esac
# what cannot run is never mistaken for a red gate
sh "$SCRIPT" "$TMP/missing.json" --root "$R" >/dev/null 2>&1; [ $? -eq 71 ] && pass "a missing manifest is exit 71" || fail "missing manifest"
m 'not json'; run >/dev/null 2>&1; [ $? -eq 71 ] && pass "a broken manifest is exit 71" || fail "broken manifest"
m '{"test":{"cmd":"true","cwd":"no/such/dir"},"lint":null,"typecheck":null,"build":null}'; run >/dev/null 2>&1; [ $? -eq 71 ] && pass "a gate whose cwd does not exist is exit 71" || fail "missing cwd"
m '{"test":{"cmd":"true","cwd":"../outside"},"lint":null,"typecheck":null,"build":null}'; run >/dev/null 2>&1; [ $? -eq 71 ] && pass "a cwd outside the root is refused" || fail "cwd outside the root"
m '{"test":{"cmd":"true","cwd":"."}}'; run nosuch >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown gate name is exit 64" || fail "unknown gate name"
sh "$SCRIPT" >/dev/null 2>&1; [ $? -eq 64 ] && pass "no manifest is exit 64" || fail "usage"

# a gate's own exit code must never read as the wrapper's "busy", "could not run" or "ran too long"
for c in 64 71 75 124; do
  m '{"test":{"cmd":"exit '"$c"'","cwd":"."},"lint":null,"typecheck":null,"build":null}'
  err=$(run 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 1 ] && case "$err" in *"test failed (exit $c)"*) true ;; *) false ;; esac && pass "a gate that exits $c is plain red (1), with its real code in the message" || fail "gate exit $c came out as $rc"
done
m '{"test":{"cmd":"true","cwd":7},"lint":null,"typecheck":null,"build":null}'; run >/dev/null 2>&1; [ $? -eq 71 ] && pass "a cwd that is not text is exit 71, not a crash" || fail "non-string cwd"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
