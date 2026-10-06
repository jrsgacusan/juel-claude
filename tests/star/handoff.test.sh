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
row() { printf '| %s | %s | %s | /w/%s | %s | - | 1 | t | d | 0 | %s | abc1234 | - | - | %s |\n' "$1" "$1" "$2" "$1" "$3" "$4" "$5" >> "$H/ledger.md"; }
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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
