#!/bin/sh
# Runs skills/babysit-pr/review-proof.sh against scratch review files.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/babysit-pr/review-proof.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
[ -f "$SCRIPT" ] || { echo "FAIL review-proof.sh missing"; exit 1; }
HEAD=0123456789abcdef0123456789abcdef01234567
w() { printf '%s\n\n1. something\n' "$2" > "$TMP/$1"; }
# t <name> <expected first word(s)> <file> [args...]
t() { name=$1; exp=$2; f=$3; shift 3
  out=$(sh "$SCRIPT" "$TMP/$f" --item SAVI-1 --head "$HEAD" "$@" 2>&1); rc=$?
  case "$out" in "$exp"*) [ "$rc" -eq 0 ] && echo "ok   $name" || { echo "FAIL $name (rc=$rc)"; fails=$((fails + 1)); } ;; *) echo "FAIL $name (got: $out)"; fails=$((fails + 1)) ;; esac; }
w SAVI-1-r1.md "VERDICT item=SAVI-1 round=1 SAFE findings=0 head=$HEAD"
t "a SAFE review of this head is proof" "OK round=1" SAVI-1-r1.md
w SAVI-1-r1.md "VERDICT item=SAVI-1 round=1 SAFE findings=2 head=0123456"
t "a 7-character head that starts the full one is enough" "OK round=1" SAVI-1-r1.md
w SAVI-1-r1.md "VERDICT item=SAVI-1 round=1 NOT-SAFE findings=2 head=$HEAD"
t "NOT-SAFE is not SAFE, whatever a word search says" "NO verdict" SAVI-1-r1.md
t "and it is the proof a fix needs" "OK round=1" SAVI-1-r1.md --verdict NOT-SAFE
w SAVI-1-r1.md "VERDICT item=SAVI-1 round=1 SAFE findings=0 head=0"
t "a one-character head proves nothing" "NO first line" SAVI-1-r1.md
w SAVI-1-r1.md "VERDICT item=SAVI-1 round=1 SAFE findings=0 head=fffffff"
t "a review of another commit is refused" "NO head" SAVI-1-r1.md
w SAVI-1-r1.md "VERDICT item=SAVI-2 round=1 SAFE findings=0 head=$HEAD"
t "a review of another item is refused" "NO item" SAVI-1-r1.md
w SAVI-1-r1.md "VERDICT item=SAVI-1 round=2 SAFE findings=0 head=$HEAD"
t "a round that is not the file's round is refused" "NO round" SAVI-1-r1.md
w SAVI-1-r1.md "VERDICT item=SAVI-1 round=1 SAFE findings=0 head=$HEAD"; w SAVI-1-r2.md "VERDICT item=SAVI-1 round=2 NOT-SAFE findings=1 head=$HEAD"
t "an older SAFE is refused once a later round exists" "NO newer" SAVI-1-r1.md
: > "$TMP/SAVI-1-r2-fix.md"; rm -f "$TMP/SAVI-1-r2.md"; w SAVI-1-r1.md "VERDICT item=SAVI-1 round=1 SAFE findings=0 head=$HEAD"
t "a fix-outcome file beside it is not a later round" "OK round=1" SAVI-1-r1.md
printf 'Review\nVERDICT item=SAVI-1 round=1 SAFE findings=0 head=%s\n' "$HEAD" > "$TMP/SAVI-1-r1.md"
t "the verdict must be the first line" "NO first line" SAVI-1-r1.md
t "a missing file is NO, not a crash" "NO file" nope-r1.md
out=$(sh "$SCRIPT" "$TMP/SAVI-1-r1.md" --item SAVI-1 --head abc 2>&1); rc=$?
[ "$rc" -eq 64 ] && echo "ok   a head shorter than 7 characters is bad usage" || { echo "FAIL short --head (rc=$rc $out)"; fails=$((fails + 1)); }
w review.md "VERDICT item=SAVI-1 round=1 SAFE findings=0 head=$HEAD"
t "a file not named <item>-r<k>.md is not proof" "NO name" review.md
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
