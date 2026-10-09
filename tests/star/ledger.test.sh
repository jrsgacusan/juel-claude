#!/bin/sh
# Runs skills/star/ledger.sh against a scratch STAR folder.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/ledger.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL ledger.sh missing"; exit 1; }
H="$TMP/star"; mkdir -p "$H"; cp "$ROOT/skills/star/template/ledger.md" "$H/ledger.md"
L() { STAR_NOW=2026-10-07T10:00:00Z sh "$SCRIPT" --home "$H" "$@"; }

# names
[ "$(L name SPH-11)" = "SPH-11" ] && pass "a tracker ref is its own name" || fail "name SPH-11 ($(L name SPH-11))"
[ "$(L name '#412')" = "issue-412" ] && pass "a GitHub ref becomes issue-<n>" || fail "name #412"
[ "$(L name '/work/specs/My Spec File.md')" = "my-spec-file" ] && pass "a spec path becomes its kebab-case file name" || fail "name spec path ($(L name '/work/specs/My Spec File.md'))"
[ "$(L name 'a b/c')" = "c" ] && pass "only the last path part counts" || fail "name a b/c"

# add, and refusing a second row
[ "$(L add SPH-11 ref=SPH-11 project=app)" = "added SPH-11" ] && pass "add" || fail "add"
L add SPH-11 ref=SPH-11 project=app >/dev/null 2>&1; [ $? -eq 65 ] && pass "the same item twice is refused (65)" || fail "duplicate item"
L add other ref=SPH-11 project=app >/dev/null 2>&1; [ $? -eq 65 ] && pass "an open row for the ref refuses a second (65)" || fail "duplicate open ref"
[ "$(L name SPH-11)" = "open SPH-11" ] && pass "name says open for a ref with an open row" || fail "name open"
[ "$(L get SPH-11 state)" = "inbox" ] && [ "$(L get SPH-11 updated)" = "2026-10-07T10:00:00Z" ] && pass "a new row is inbox, stamped" || fail "new row defaults"

# set: one argument per field, cleaned, never split
L set SPH-11 "worktree=/tmp/a b c" state=queued >/dev/null
[ "$(L get SPH-11 worktree)" = "/tmp/a b c" ] && pass "a value with spaces stays one cell" || fail "spaces"
[ "$(grep -c '^| ' "$H/ledger.md")" -eq 2 ] && pass "still one row (header + 1)" || fail "row count $(grep -c '^| ' "$H/ledger.md")"
L set SPH-11 "head=a|b" >/dev/null; [ "$(L get SPH-11 head)" = "a/ b" ] && pass "a pipe becomes '/ '" || fail "pipe ($(L get SPH-11 head))"
L set SPH-11 "cursor=one
two" >/dev/null; [ "$(L get SPH-11 cursor)" = "one/ two" ] && pass "a line break becomes '/ '" || fail "newline"
L set SPH-11 head= >/dev/null; [ "$(L get SPH-11 head)" = "-" ] && pass "an empty value is -" || fail "empty"
STAR_NOW=2026-10-07T11:00:00Z sh "$SCRIPT" --home "$H" set SPH-11 round=1 >/dev/null
[ "$(L get SPH-11 updated)" = "2026-10-07T11:00:00Z" ] && pass "every write stamps updated" || fail "stamp"

# counters
L set SPH-11 counters.silent=+1 >/dev/null; L set SPH-11 counters.silent=+1 counters.last=msg_1 >/dev/null
[ "$(L get SPH-11 counters.silent)" = "2" ] && [ "$(L get SPH-11 counters.last)" = "msg_1" ] && pass "+1 counts and a word key sets" || fail "counters ($(L get SPH-11 counters))"
L set SPH-11 counters.hold=3 counters.silent=- >/dev/null
[ "$(L get SPH-11 counters)" = "last=msg_1 hold=3" ] && pass "- removes a key" || fail "remove ($(L get SPH-11 counters))"
L set SPH-11 counters=keep:hold >/dev/null; [ "$(L get SPH-11 counters)" = "hold=3" ] && pass "keep: drops every other key" || fail "keep ($(L get SPH-11 counters))"
L set SPH-11 counters=- >/dev/null; [ "$(L get SPH-11 counters)" = "-" ] && pass "counters=- clears them" || fail "clear"
L set SPH-11 counters.kept=1 >/dev/null && [ "$(L get SPH-11 counters.kept)" = "1" ] && pass "kept= is a counter (#19)" || fail "kept counter"
L set SPH-11 counters.busy=+1 >/dev/null && L set SPH-11 counters.busy=+1 >/dev/null && [ "$(L get SPH-11 counters.busy)" = "2" ] && pass "busy= counts refused check-ins (#25)" || fail "busy counter"
L set SPH-11 counters.busy=- >/dev/null
L set SPH-11 counters.synced=abc1234 >/dev/null && [ "$(L get SPH-11 counters.synced)" = "abc1234" ] && pass "synced= holds a base head (#28)" || fail "synced word"
L set SPH-11 counters.synced=+1 >/dev/null 2>&1; [ $? -eq 64 ] && pass "synced= does not count" || fail "synced +1"
L set SPH-11 counters.synced=- >/dev/null
L set SPH-11 counters=- >/dev/null
[ "$(L get SPH-11 counters.silent)" = "-" ] && pass "an absent counter reads -" || fail "absent counter"

# refusals
L set SPH-11 updated=x >/dev/null 2>&1; [ $? -eq 64 ] && pass "updated cannot be set" || fail "updated set"
L set SPH-11 state=sleeping >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown state is refused" || fail "bad state"
L set SPH-11 counters.bogus=1 >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown counter is refused" || fail "bad counter"
L set SPH-11 counters.last=+1 >/dev/null 2>&1; [ $? -eq 64 ] && pass "a word key does not count" || fail "word +1"
L set nope state=queued >/dev/null 2>&1; [ $? -eq 4 ] && pass "an unknown item is 4" || fail "unknown item"
L set SPH-11 round >/dev/null 2>&1; [ $? -eq 64 ] && pass "a field without = is refused" || fail "no ="

# list and counts
[ "$(L list --state queued | cut -f1,2)" = "$(printf 'SPH-11\tqueued')" ] && pass "list --state" || fail "list ($(L list))"
[ "$(L counts)" = "queued 1" ] && pass "counts" || fail "counts ($(L counts))"

# a finished ref gets a new name
L set SPH-11 state=dropped >/dev/null
[ "$(L name SPH-11)" = "SPH-11-2" ] && pass "a ref whose row is dropped gets -2" || fail "suffix ($(L name SPH-11))"

# Review Focus 2: a hand-edited file with a blank line between rows and trailing spaces
L add SPH-12 ref=SPH-12 project=app >/dev/null
python3 - "$H/ledger.md" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split("\n")
i = next(i for i, l in enumerate(lines) if l.startswith("| SPH-12 "))
lines[i] = lines[i] + "   "
lines.insert(i, "")
open(p, "w").write("\n".join(lines))
PY
[ "$(L get SPH-12 state)" = "inbox" ] && pass "a blank line between rows and trailing spaces are read" || fail "hand-edited file"
L set SPH-12 state=queued >/dev/null && [ "$(L counts | grep -c .)" -eq 2 ] && pass "and a write keeps both rows" || fail "rewrite after hand edit"

# a broken row stops every command
printf '| x | y | z |\n' >> "$H/ledger.md"
L get SPH-11 state >/dev/null 2>&1; [ $? -eq 2 ] && pass "a broken row is exit 2" || fail "broken row"
sed -i.bak '$d' "$H/ledger.md"

# the lock: parallel adds lose nothing
i=0; while [ $i -lt 15 ]; do L add "P-$i" "ref=P-$i" project=app >/dev/null & i=$((i + 1)); done; wait
[ "$(L list | grep -c '^P-')" -eq 15 ] && pass "15 parallel adds keep 15 rows" || fail "parallel adds ($(L list | grep -c '^P-'))"

# v2: four stages, no review, fix or screen states, the new counters
L add V2-1 ref=V2-1 project=app >/dev/null
for gone in pr-draft reviewing fix-queued fixing screen-queued screening ready; do
  L set V2-1 "state=$gone" >/dev/null 2>&1; [ $? -eq 64 ] || fail "state $gone is still accepted"
done; pass "the seven v1-only states are refused"
for gone in review fix screen; do
  L set V2-1 "stage=$gone" >/dev/null 2>&1; [ $? -eq 64 ] || fail "stage $gone is still accepted"
done; pass "the three v1-only stages are refused"
L set V2-1 state=babysit-queued stage=babysit counters.capacity=+1 counters.mismatch=1 counters.mergefail=1 counters.rescoped=1 counters.rescope=V2-1-r3.md counters.batch=B-20261009T081200Z counters.parent=SPH-11 >/dev/null
[ "$(L get V2-1 counters.rescope)" = "V2-1-r3.md" ] && [ "$(L get V2-1 counters.batch)" = "B-20261009T081200Z" ] && [ "$(L get V2-1 counters.capacity)" = "1" ] && [ "$(L get V2-1 counters.parent)" = "SPH-11" ] && pass "the new counters and words are kept" || fail "new counters ($(L get V2-1 counters))"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
