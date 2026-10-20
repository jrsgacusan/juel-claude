#!/bin/sh
# Runs skills/star/person-check.sh from a scratch folder.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/person-check.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL person-check.sh missing"; exit 1; }
cd "$TMP" || exit 1
PC() { sh "$SCRIPT" "$@"; }

want() { # want <command> <expected output>
  got=$(PC "$1" 2>&1); rc=$?
  [ "$got" = "$2" ] && [ "$rc" -eq 0 ] && pass "$1 -> $2" || fail "$1 -> '$got' ($rc), wanted '$2'"
}

want 'true' pass
want 'false' 'fail 1'
want 'exit 3' 'fail 3'
want "printf 'BlackHole 2ch\n' | grep -q 'BlackHole 2ch'" pass
want 'cat' pass
want 'gh auth status 2>/dev/null; true' pass
want 'ls nothing-here 2>&1 >/dev/null; true' pass
want "echo '>' | grep -q '>'" pass
want 'git rev-parse --is-inside-work-tree >/dev/null 2>&1; true' pass
want 'defaults read NSGlobalDomain AppleLocale >/dev/null 2>&1; true' pass
want 'launchctl list >/dev/null; true' pass

start=$(date +%s)
got=$(PERSON_CHECK_TIMEOUT=1 PC 'sleep 5')
end=$(date +%s)
[ "$got" = "timeout" ] && [ $((end - start)) -lt 4 ] && pass "a slow command is timeout in under 4 seconds" || fail "timeout ('$got', $((end - start))s)"

refuse() { # refuse <command>: prints "refused ..." and never runs it
  rm -rf marker
  got=$(PC "$1" 2>&1); rc=$?
  case "$got" in "refused "*) r=1 ;; *) r=0 ;; esac
  [ "$r" -eq 1 ] && [ "$rc" -eq 0 ] && [ ! -e marker ] && pass "refused: $1" || fail "refused: $1 ('$got', $rc, marker $([ -e marker ] && echo made || echo absent))"
}
refuse 'sudo true'
refuse 'echo hi > marker'
refuse 'echo hi >> marker'
refuse 'touch marker'
refuse 'rm -f marker'
refuse 'mkdir marker'
refuse 'brew install x'
refuse 'npm i x'
refuse 'pip install x'
refuse 'git push'
refuse 'git commit -m x'
refuse 'curl -o marker https://example.com'
refuse 'defaults write x y z'
refuse 'defaults delete x'
refuse 'launchctl bootout gui/501/x'
refuse 'true && rm -rf marker'

got=$(PC "echo 'x" 2>&1)
[ "$got" = "refused unreadable command" ] && pass "an unclosed quote is refused as unreadable" || fail "unclosed quote ('$got')"

out=$(PC 2>/dev/null); rc=$?
[ "$rc" -eq 64 ] && [ -z "$out" ] && pass "no argument is 64 with nothing on stdout" || fail "no argument ($rc, '$out')"
out=$(PC true true 2>/dev/null); rc=$?
[ "$rc" -eq 64 ] && [ -z "$out" ] && pass "two arguments is 64" || fail "two arguments ($rc)"
out=$(PC '' 2>/dev/null); rc=$?
[ "$rc" -eq 64 ] && [ -z "$out" ] && pass "an empty argument is 64" || fail "empty argument ($rc)"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
