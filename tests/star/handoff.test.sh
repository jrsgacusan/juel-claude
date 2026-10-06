#!/bin/sh
# Runs skills/star/handoff.sh against a scratch STAR home.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/handoff.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL handoff.sh missing"; exit 1; }
H="$TMP/home"; mkdir -p "$H"
T="$ROOT/skills/star/template"
cp "$T/open-loops.md" "$T/ledger.md" "$T/star.json" "$H/"
L() { sh "$ROOT/skills/star/loops.sh" --file "$H/open-loops.md" "$@"; }
L add --kind approve-brief --project lstn --item SAVI-1 --title "approve brief" >/dev/null
L add --kind merge-pr --project web --item issue-12 --title "merge PR #12 — approved, green" >/dev/null
L add --kind question --project lstn --item SAVI-2 --title "which queue?" >/dev/null
L add --kind held --project web --item issue-9 --title "set status in_review" >/dev/null
row() { printf '| %s | %s | %s | /w/%s | %s | - | 1 | t | d | 0 | %s | abc1234 | - | - | - | %s |\n' "$1" "$1" "$2" "$1" "$3" "$4" "$5" >> "$H/ledger.md"; }
row SAVI-1 lstn brief-ready - 2026-10-07T12:00:00Z
row SAVI-2 lstn building - 2026-10-07T12:30:00Z
row issue-12 web ready https://github.com/o/web/pull/12 2026-10-07T12:40:00Z
row issue-7 web done https://github.com/o/web/pull/7 2026-10-07T15:00:00Z
row issue-3 web done https://github.com/o/web/pull/3 2026-10-06T09:00:00Z
row SAVI-5 lstn escalated - 2026-10-07T11:00:00Z
printf '2026-10-07T12:59:00Z\tlstn\tSAVI-2\told message before leaving\n2026-10-07T14:10:00Z\tweb\tissue-12\tbabysit: 2 replies, 1 review request\n' > "$H/sent.log"
HO() { STAR_NOW="$1" STAR_MEM_GB=5 sh "$SCRIPT" --home "$H" "$2" ${3:-} ${4:-}; }
away() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("away"))' "$H/star.json"; }

[ "$(HO 2026-10-07T13:00:00Z due)" = not-away ] && pass "not away by default" || fail "not away by default"
out=$(HO 2026-10-07T13:00:00Z start)
F="$H/handoff.md"
[ "$out" = "$F" ] && [ -f "$F" ] && pass "start writes handoff.md and prints its path" || fail "start ($out)"
[ "$(away)" = 2026-10-07T13:00:00Z ] && pass "away recorded in star.json" || fail "away not recorded ($(away))"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["maxParallel"]==3 and "worker" in d' "$H/star.json" && pass "star.json keeps its other settings" || fail "star.json damaged"
sec() { sed -n "/^### $1/,/^##/p" "$F"; }
sec "A\." | grep -q 'N-1 · lstn · SAVI-1 · approve brief' && sec "A\." | grep -q 'N-3 · lstn · SAVI-2 · which queue' && ! sec "A\." | grep -q 'N-2' && pass "A: what blocks work" || fail "part A"
sec "B\." | grep -q 'N-2 · web · issue-12 · merge PR #12' && sec "B\." | grep -q 'N-4 · web · issue-9' && ! sec "B\." | grep -q 'N-1 ' && pass "B: what can wait" || fail "part B"
sec "C\." | grep -q 'lstn · SAVI-2 · building' && sec "C\." | grep -qi 'draft PR' && ! sec "C\." | grep -q 'issue-7' && pass "C: what runs overnight, finished items left out" || fail "part C"
grep -q 'open-loops.md' "$F" && ! grep -q '^Answer:' "$F" && pass "one place to answer: no Answer slots here" || fail "answer slots duplicated"

[ "$(HO 2026-10-07T13:30:00Z due --hours 4)" = not-due ] && [ "$(HO 2026-10-07T17:01:00Z due --hours 4)" = due ] && pass "a summary is due 4 hours after leaving" || fail "due"
HO 2026-10-07T17:01:00Z summary >/dev/null
S1=$(sed -n '/^### 2026-10-07T17:01:00Z/,/^### /p' "$F")
printf '%s\n' "$S1" | grep -q 'ready for your merge.*web issue-12' && pass "summary: PRs ready" || fail "summary ready PRs"
printf '%s\n' "$S1" | grep -q 'Merged since.*web issue-7' && ! printf '%s\n' "$S1" | grep -q 'issue-3' && pass "summary: merged since the last one only" || fail "summary merged"
printf '%s\n' "$S1" | grep -q 'Stopped.*lstn SAVI-5' && pass "summary: escalated and failed items" || fail "summary stopped"
printf '%s\n' "$S1" | grep -q 'babysit: 2 replies, 1 review request' && ! printf '%s\n' "$S1" | grep -q 'old message before leaving' && pass "summary: messages sent since the last one only" || fail "summary sent"
printf '%s\n' "$S1" | grep -q 'Host: 5 GB' && pass "summary: host health" || fail "summary host"
[ "$(printf '%s\n' "$S1" | grep -c 'N-[1-4] ')" -ge 1 ] && for n in 1 2 3 4; do printf '%s\n' "$S1" | grep -q "N-$n" || fail "summary misses N-$n"; done; pass "summary: the full needs-you list"
[ "$(HO 2026-10-07T17:05:00Z due --hours 4)" = not-due ] && pass "not due right after a summary" || fail "due after summary"
HO 2026-10-07T21:10:00Z summary >/dev/null
a=$(grep -n '^### 2026-10-07T21:10:00Z' "$F" | cut -d: -f1); b=$(grep -n '^### 2026-10-07T17:01:00Z' "$F" | cut -d: -f1); c=$(grep -n '^## Before you go' "$F" | cut -d: -f1)
[ -n "$a" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && pass "newest summary first, before-you-go kept below" || fail "summary order ($a $b $c)"
sed -n '/^### 2026-10-07T21:10:00Z/,/^### /p' "$F" | grep -q 'issue-7' && fail "second summary repeats old merges" || pass "second summary reports only what is new"
HO 2026-10-07T21:11:00Z latest | grep -q '^### 2026-10-07T21:10:00Z' && ! HO 2026-10-07T21:11:00Z latest | grep -q '17:01:00Z' && pass "latest prints only the newest summary" || fail "latest"
HO 2026-10-08T05:00:00Z end >/dev/null
[ "$(away)" = None ] && [ "$(HO 2026-10-08T05:01:00Z due)" = not-away ] && grep -q '^back: 2026-10-08T05:00:00Z' "$F" && pass "end clears away and stamps the file" || fail "end"
HO 2026-10-08T05:02:00Z summary >/dev/null 2>&1; [ $? -eq 1 ] && pass "no summary when not away" || fail "summary while not away"
# An empty home still produces a readable file.
E="$TMP/empty"; mkdir -p "$E"; cp "$T/open-loops.md" "$T/ledger.md" "$T/star.json" "$E/"
STAR_NOW=2026-10-07T13:00:00Z sh "$SCRIPT" --home "$E" start >/dev/null && grep -q 'Nothing' "$E/handoff.md" && pass "an empty queue and ledger still write a handoff" || fail "empty home"

# Repeated, odd and concurrent use must not lose what was written.
N="$TMP/n"; mkdir -p "$N"; cp "$T/open-loops.md" "$T/ledger.md" "$T/star.json" "$N/"
HN() { STAR_NOW="$1" STAR_MEM_GB=5 sh "$SCRIPT" --home "$N" "$2" ${3:-} ${4:-}; }
awayn() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("away"))' "$N/star.json"; }
rown() { printf '| %s | %s | p | /w/%s | %s | - | 1 | t | d | 0 | %s | abc1234 | - | - | - | %s |\n' "$1" "$1" "$1" "$2" "$3" "$4" >> "$N/ledger.md"; }
rown a fix-queued - 2026-10-07T12:00:00Z
rown b ready 'https://x/pull/1' 2026-10-07T12:00:00Z
printf '| c | c | p | /w/c | ready | - | 1 | t | d | 0 | https://x/pull/2 | abc1234 | - | - | 2026-10-07T12:00:00Z |\n' >> "$N/ledger.md"
printf '| d | d | p | /w/d | escalated | - | 1 | t | d | 0 | - | abc1234 | a \\| b | - | - | 2026-10-07T12:00:00Z |\n' >> "$N/ledger.md"
printf '| e | e | p | /w/e | done | - | 1 | t | d | 0 | https://x/pull/5 | abc1234 | - | - | - | 2026-10-07 15:30 |\n' >> "$N/ledger.md"
HN 2026-10-07T13:00:00Z start >/dev/null
grep -q 'p · a · fix-queued: ' "$N/handoff.md" && pass "a fix waiting for a slot is listed under what runs" || fail "fix-queued missing from part C"
grep -q '1 ledger row' "$N/handoff.md" && pass "start says when a ledger row could not be read" || fail "start hid an unreadable ledger row"
HN 2026-10-07T17:01:00Z summary >/dev/null
SN=$(sed -n '/^### 2026-10-07T17:01:00Z/,/^### /p' "$N/handoff.md")
printf '%s\n' "$SN" | grep -q 'Ledger rows unreadable: 1' && pass "summary says when a ledger row could not be read" || fail "summary hid an unreadable ledger row"
printf '%s\n' "$SN" | grep -q 'Stopped.*p d (escalated)' && pass "an escaped pipe in a cell does not drop the row" || fail "escaped pipe dropped a row"
printf '%s\n' "$SN" | grep -q 'workers running: 0' && pass "a waiting fix is not a running worker" || fail "fix-queued counted as running"
printf '%s\n' "$SN" | grep -q 'Merged since.*p e' && pass "a date with a space instead of T still counts" || fail "space-separated date ignored"
out=$(HN 2026-10-07T18:00:00Z start 2>/dev/null)
[ "$out" = "$N/handoff.md" ] && grep -q '^### 2026-10-07T17:01:00Z' "$N/handoff.md" && [ "$(awayn)" = 2026-10-07T13:00:00Z ] && pass "away twice keeps the summaries and the first away time" || fail "second away wiped the handoff"
i=0; while [ $i -lt 30 ]; do i=$((i + 1)); printf '2026-10-07T18:%02d:00Z\tp\ta\tmsg %s\n' "$i" "$i" >> "$N/sent.log"; done
HN 2026-10-07T21:30:00Z summary >/dev/null
SN=$(sed -n '/^### 2026-10-07T21:30:00Z/,/^### /p' "$N/handoff.md")
printf '%s\n' "$SN" | grep -q 'msg 30' && printf '%s\n' "$SN" | grep -q '(+20 earlier)' && ! printf '%s\n' "$SN" | grep -q 'msg 20;' && pass "a long sent list shows the newest 10 and a count" || fail "sent list not capped"
# the user deletes the Summaries heading and adds a dated note of their own
python3 - "$N/handoff.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read().replace("## Summaries\n", "", 1)
open(p, "w").write(s)
PY2
[ "$(HN 2026-10-08T01:31:00Z due)" = due ] && HN 2026-10-08T01:31:00Z summary >/dev/null 2>&1 && grep -q '^## Summaries$' "$N/handoff.md" && grep -q '^### 2026-10-08T01:31:00Z' "$N/handoff.md" && pass "a deleted Summaries heading is put back" || fail "summary without a Summaries heading"
[ "$(HN 2026-10-08T01:40:00Z due)" = not-due ] && pass "not due after the repaired summary" || fail "due loops after a repaired summary"
python3 - "$N/handoff.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read().replace("## Summaries\n", "## Summaries\n\n### 2031-01-01T00:00:00Z\nmy own note\n", 1)
open(p, "w").write(s)
PY2
[ "$(HN 2026-10-08T06:00:00Z due)" = due ] && pass "a note dated in the future does not stop the summaries" || fail "future-dated note stopped summaries"
for m in 01 02 03 04 05 06 07 08 09 10; do HN "2026-10-08T06:$m:00Z" summary >/dev/null 2>&1 & done; wait
[ "$(grep -c '^### 2026-10-08T06:' "$N/handoff.md")" = 10 ] && pass "ten summaries at once all land" || fail "concurrent summaries lost ($(grep -c '^### 2026-10-08T06:' "$N/handoff.md") of 10)"
HN 2026-10-08T07:00:00Z end >/dev/null
out=$(HN 2026-10-08T07:05:00Z end 2>&1)
[ "$out" = "not away" ] && [ "$(grep -c '^back: ' "$N/handoff.md")" = 1 ] && pass "back while not away says so and stamps nothing" || fail "second end ($out)"
# away times the user or another tool wrote in other forms
setaway() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["away"]=sys.argv[2]; json.dump(d, open(p,"w"), indent=2)' "$N/star.json" "$1"; }
setaway '2026-10-08T21:00:00+08:00'
[ "$(HN 2026-10-08T14:00:00Z due)" = not-due ] && [ "$(HN 2026-10-08T17:01:00Z due)" = due ] && pass "an away time with an offset is understood" || fail "away with an offset"
setaway 'whenever'; rm -f "$N/handoff.md"
[ "$(HN 2026-10-08T14:00:00Z due 2>/dev/null)" = due ] && pass "an unreadable away time is due, not silent forever" || fail "garbage away is never due"
# a star.json that is not an object changes nothing
B="$TMP/b"; mkdir -p "$B"; cp "$T/open-loops.md" "$T/ledger.md" "$B/"; printf '[1, 2]\n' > "$B/star.json"
STAR_NOW=2026-10-07T13:00:00Z sh "$SCRIPT" --home "$B" start >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$B/handoff.md" ] && pass "a broken star.json stops start before anything is written" || fail "broken star.json (rc=$rc)"

# Second stress pass
D="$TMP/d"; mkdir -p "$D"; cp "$T/open-loops.md" "$T/ledger.md" "$T/star.json" "$D/"
HD() { STAR_NOW="$1" STAR_MEM_GB=5 sh "$SCRIPT" --home "$D" "$2" ${3:-}; }
HD 2026-10-07T12:00:00Z start >/dev/null; HD 2026-10-07T16:00:00Z summary >/dev/null; rm -f "$D/handoff.md"
HD 2026-10-07T17:00:00Z start >/dev/null 2>&1
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["away"])' "$D/star.json")" = 2026-10-07T12:00:00Z ] && [ -f "$D/handoff.md" ] && pass "a deleted handoff file is rewritten without moving the away time" || fail "start reset the away time"
head -3 "$T/ledger.md" | tail -2 >> "$D/ledger.md"
printf '| a | a | p | /w/a | building | - | 1 | t | d | 0 | - | abc | - | - | - | 2026-10-07T12:00:00Z |\n' >> "$D/ledger.md"
HD 2026-10-07T20:30:00Z summary >/dev/null
sed -n '/^### 2026-10-07T20:30:00Z/,/^### /p' "$D/handoff.md" | grep -q 'Items: building 1$' && pass "a pasted second header row is not an item" || fail "second header row counted ($(grep -m1 'Items:' "$D/handoff.md"))"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
