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

# lane b: #102 the sweep gate runs only when named; #105 a gate without its dependencies fails fast
rm -f "$TMP/sw.test" "$TMP/sw.sweep"
m '{"test":{"cmd":"touch '"$TMP"'/sw.test","cwd":"."},"lint":null,"typecheck":null,"build":null,"sweep":{"cmd":"touch '"$TMP"'/sw.sweep","cwd":"packages/api"}}'
run >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -e "$TMP/sw.test" ] && [ ! -e "$TMP/sw.sweep" ] && pass "#102 the default run never runs sweep" || fail "#102 default run and sweep (rc=$rc)"
rm -f "$TMP/sw.test"
run sweep >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -e "$TMP/sw.sweep" ] && [ ! -e "$TMP/sw.test" ] && pass "#102 sweep runs when named, and only it" || fail "#102 named sweep (rc=$rc)"
rm -f "$TMP/sw.test"
m '{"test":{"cmd":"touch '"$TMP"'/sw.test","cwd":"."},"lint":null,"typecheck":null,"build":null,"sweep":null}'
run sweep >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -e "$TMP/sw.test" ] && pass "#102 a null sweep runs the test entry" || fail "#102 null sweep (rc=$rc)"
rm -f "$TMP/sw.test"
m '{"test":{"cmd":"touch '"$TMP"'/sw.test","cwd":"."},"lint":null,"typecheck":null,"build":null}'
run sweep >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -e "$TMP/sw.test" ] && pass "#102 a missing sweep runs the test entry" || fail "#102 missing sweep (rc=$rc)"
m '{"test":null,"lint":null,"typecheck":null,"build":null,"sweep":null}'
out=$(run sweep 2>&1); rc=$?
[ "$rc" -eq 0 ] && case "$out" in *"no gates"*) true ;; *) false ;; esac && pass "#102 sweep and test both null: nothing to run, exit 0" || fail "#102 nothing to sweep (rc=$rc: $out)"
err=$(run nosuch 2>&1); case "$err" in *"known: test, lint, typecheck, build, sweep"*) pass "#102 the usage names sweep" ;; *) fail "#102 usage ($err)" ;; esac
# a gate whose cwd has a package.json and no node_modules or .pnp.cjs up to the root: exit 71, one
# line, and no gate runs, not even an earlier one that has no package.json
mkdir -p "$TMP/deps/packages/web" "$TMP/deps/docs"; D=$(cd "$TMP/deps" && pwd -P)
printf '{}\n' > "$D/package.json"; printf '{}\n' > "$D/packages/web/package.json"
drun() { (cd "$D" && sh "$SCRIPT" "$TMP/gates.json" --root "$D" "$@"); }
rm -f "$TMP/d.test" "$TMP/d.lint"
m '{"test":{"cmd":"touch '"$TMP"'/d.test","cwd":"docs"},"lint":{"cmd":"touch '"$TMP"'/d.lint","cwd":"packages/web"},"typecheck":null,"build":null}'
err=$(drun 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 71 ] && [ "$err" = "run-gates.sh: lint: dependencies are not installed (no node_modules for packages/web/package.json)" ] && [ ! -e "$TMP/d.test" ] && [ ! -e "$TMP/d.lint" ] && pass "#105 missing dependencies are exit 71 with one line, before any gate runs" || fail "#105 missing dependencies (rc=$rc: $err)"
m '{"test":{"cmd":"true","cwd":"."},"lint":null,"typecheck":null,"build":null}'
err=$(drun 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 71 ] && [ "$err" = "run-gates.sh: test: dependencies are not installed (no node_modules for ./package.json)" ] && pass "#105 the root's own package.json is checked too" || fail "#105 root package.json (rc=$rc: $err)"
# node_modules at the root covers a sub-package (npm workspaces install there), and so does .pnp.cjs
m '{"test":{"cmd":"touch '"$TMP"'/d.test","cwd":"docs"},"lint":{"cmd":"touch '"$TMP"'/d.lint","cwd":"packages/web"},"typecheck":null,"build":null}'
mkdir "$D/node_modules"; rm -f "$TMP/d.test" "$TMP/d.lint"
drun >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -e "$TMP/d.test" ] && [ -e "$TMP/d.lint" ] && pass "#105 node_modules at the root covers a sub-package" || fail "#105 root node_modules (rc=$rc)"
rmdir "$D/node_modules"; : > "$D/.pnp.cjs"
drun >/dev/null 2>&1; [ $? -eq 0 ] && pass "#105 a .pnp.cjs at the root counts as installed" || fail "#105 .pnp.cjs"
rm -f "$D/.pnp.cjs"
# a cwd with no package.json is never checked, even when the root has one and nothing is installed
m '{"test":{"cmd":"true","cwd":"docs"},"lint":null,"typecheck":null,"build":null}'
drun >/dev/null 2>&1; [ $? -eq 0 ] && pass "#105 a gate whose cwd has no package.json is not checked" || fail "#105 cwd without package.json"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
