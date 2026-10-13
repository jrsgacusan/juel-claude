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
# #82: an owner's carried PASS, written by "carry" and accepted as proof for its head
mkdir -p "$TMP/c"; w c/SAVI-1-r2.md "VERDICT item=SAVI-1 round=2 NOT-SAFE findings=1 head=$HEAD"
out=$(sh "$SCRIPT" carry --reviews "$TMP/c" --item SAVI-1 --round 2 --head "$HEAD" --decision N-7 --note "ship it, the
retry finding goes to a follow-up" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "wrote $TMP/c/SAVI-1-r2-carried.md" ] && echo "ok   carry writes the carried PASS" || { echo "FAIL carry ($rc $out)"; fails=$((fails + 1)); }
exp=$(printf 'CARRIED item=SAVI-1 round=2 head=%s from=SAVI-1-r2.md decision=N-7\nship it, the retry finding goes to a follow-up\nDeferred: the findings in SAVI-1-r2.md' "$HEAD")
[ "$(cat "$TMP/c/SAVI-1-r2-carried.md" 2>/dev/null)" = "$exp" ] && echo "ok   the carried file is three lines, the note on one" || { echo "FAIL carried file ($(cat "$TMP/c/SAVI-1-r2-carried.md" 2>/dev/null))"; fails=$((fails + 1)); }
t "a carried PASS is proof for its head" "OK carried round=2" c/SAVI-1-r2-carried.md
t "a short --head that starts the carried head is enough" "OK carried round=2" c/SAVI-1-r2-carried.md --head 0123456
t "a carried PASS of another head is refused" "NO head" c/SAVI-1-r2-carried.md --head fffffffffffffffffffffffffffffffffffffff0
t "a carried PASS never answers --verdict NOT-SAFE" "NO verdict" c/SAVI-1-r2-carried.md --verdict NOT-SAFE
w c/SAVI-1-r3.md "VERDICT item=SAVI-1 round=3 NOT-SAFE findings=1 head=$HEAD"
t "a carried PASS is refused once a later round exists" "NO newer" c/SAVI-1-r2-carried.md
rm -f "$TMP/c/SAVI-1-r3.md"
cp "$TMP/c/SAVI-1-r2-carried.md" "$TMP/c/keep"
printf 'CARRIED item=SAVI-1 round=2 head=0123456 from=SAVI-1-r2.md decision=N-7\n' > "$TMP/c/SAVI-1-r2-carried.md"
t "a carried head shorter than 40 characters is refused" "NO first line" c/SAVI-1-r2-carried.md
printf 'CARRIED item=SAVI-1 round=2 head=%s from=SAVI-1-r1.md decision=N-7\n' "$HEAD" > "$TMP/c/SAVI-1-r2-carried.md"
t "a carried PASS must name its own round's review" "NO from" c/SAVI-1-r2-carried.md
mv "$TMP/c/keep" "$TMP/c/SAVI-1-r2-carried.md"
mv "$TMP/c/SAVI-1-r2.md" "$TMP/c/r2.keep"
t "a carried PASS whose round review is gone is refused" "NO from" c/SAVI-1-r2-carried.md
mv "$TMP/c/r2.keep" "$TMP/c/SAVI-1-r2.md"
# e <name> <expected start> <exit> <carry args...>
e() { name=$1; exp=$2; want=$3; shift 3
  out=$(sh "$SCRIPT" carry --reviews "$TMP/c" --item SAVI-1 "$@" 2>&1); rc=$?
  case "$out" in "$exp"*) [ "$rc" -eq "$want" ] && echo "ok   $name" || { echo "FAIL $name (rc=$rc)"; fails=$((fails + 1)); } ;; *) echo "FAIL $name (got: $out)"; fails=$((fails + 1)) ;; esac; }
e "carry never overwrites a carried PASS" "ERROR $TMP/c/SAVI-1-r2-carried.md exists" 1 --round 2 --head "$HEAD" --decision N-8 --note again
e "carry needs that round's review beside it" "ERROR no SAVI-1-r5.md in $TMP/c" 1 --round 5 --head "$HEAD" --decision N-8 --note x
w c/SAVI-1-r3.md "VERDICT item=SAVI-1 round=3 NOT-SAFE findings=1 head=$HEAD"
e "carry refuses a round a later one replaced" "ERROR round 3 is newer than round 2" 1 --round 2 --head "$HEAD" --decision N-8 --note x
rm -f "$TMP/c/SAVI-1-r3.md"
e "carry takes only the full head" "ERROR --head must be the full 40-character commit" 1 --round 2 --head 0123456 --decision N-8 --note x
e "carry with no --note is bad usage" "" 64 --round 2 --head "$HEAD" --decision N-8
e "a decision id is one word" "" 64 --round 2 --head "$HEAD" --decision "N 8" --note x
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
