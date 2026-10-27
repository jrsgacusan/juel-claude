#!/bin/sh
# Guards on skills/cmux-review-pr/SKILL.md text that cannot be tested by running code.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/cmux-review-pr/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
has() { tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qF -- "$2" && pass "$1" || fail "$1"; }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }

# The skill loader replaces $0..$9 in a skill body with the invocation's arguments.
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
has "resolve_bin loops over its arguments" 'resolve_bin() { for c in "$@"; do'
has "detect_ref reads its arguments in a loop" 'for a in "$@"; do n=$((n + 1));'
has "copy_untracked names its arguments" 'src=; dst=; n=0'

echo "---"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
