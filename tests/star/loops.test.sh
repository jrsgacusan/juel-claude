#!/bin/sh
# Runs skills/star/loops.sh against a scratch open-loops.md.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/loops.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL loops.sh missing"; exit 1; }
F="$TMP/open-loops.md"; cp "$ROOT/skills/star/template/open-loops.md" "$F"
L() { sh "$SCRIPT" --file "$F" "$@"; }

id1=$(L add --kind approve-brief --project lstn --item SAVI-1 --title "approve brief" --body "briefs/lstn/SAVI-1.md")
id2=$(L add --kind merge-pr --project web --item '#12' --title "merge PR #12")
[ "$id1" = N-1 ] && [ "$id2" = N-2 ] && pass "ids count up" || fail "ids count up ($id1 $id2)"
grep -q '^### N-1 · lstn · SAVI-1 · approve brief$' "$F" && grep -q '^briefs/lstn/SAVI-1.md$' "$F" && pass "item written" || fail "item written"
[ "$(L answers | wc -l | tr -d ' ')" = 0 ] && pass "no answers yet" || fail "no answers yet"

# The user answers N-1 on two lines and adds a free note of their own.
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("briefs/lstn/SAVI-1.md\nAnswer:", "briefs/lstn/SAVI-1.md\nAnswer: approve\nbut keep the old endpoint", 1)
s = s.replace("## Waiting on others", "my own note: call Ezra\n\n## Waiting on others")
open(p, "w").write(s)
PY
out=$(L answers)
printf '%s\n' "$out" | grep -q "^N-1	approve-brief	lstn	SAVI-1	approve but keep the old endpoint$" && pass "multi-line answer" || fail "multi-line answer ($out)"

id3=$(L add --kind question --project lstn --item SAVI-2 --title "which queue?")
grep -q '^Answer: approve$' "$F" && grep -q '^my own note: call Ezra$' "$F" && pass "free text survives" || fail "free text survives an add"
[ "$(L set-answer N-1 drop)" = kept ] && grep -q '^Answer: approve$' "$F" && pass "set-answer never overwrites the user" || fail "set-answer overwrote"
[ "$(L set-answer "$id3" 'use the default queue')" = set ] && L answers | grep -q "^N-3	question	lstn	SAVI-2	use the default queue$" && pass "set-answer fills an empty slot" || fail "set-answer"
L list | grep -q "^N-2	merge-pr	web	#12	open	merge PR #12$" && pass "list" || fail "list"

[ "$(L close N-1)" = closed ] && ! grep -q '^### N-1 ' "$F" && grep -q '^### N-1 · lstn · SAVI-1 · approve brief$' "$TMP/open-loops-archive.md" && grep -q 'but keep the old endpoint' "$TMP/open-loops-archive.md" && pass "close archives the item with its answer" || fail "close"
grep -q '^### N-2 ' "$F" && grep -q '^my own note: call Ezra$' "$F" && pass "close leaves the rest alone" || fail "close damaged the file"
[ "$(L add --kind held --project web --item x --title t)" = N-4 ] && pass "ids never reuse an archived number" || fail "id reuse"
L close N-99 >/dev/null 2>&1; [ $? -eq 4 ] && pass "unknown id is exit 4" || fail "unknown id"

L resume --state running --run run_abc --pools "build 2/3 · review 1/3" --next "wait for SAVI-2"
grep -q '^state: running$' "$F" && grep -q '^run: run_abc$' "$F" && grep -q '^next: wait for SAVI-2$' "$F" && grep -Eq '^last tick: 20[0-9]{2}-' "$F" && pass "resume block rewritten" || fail "resume block"
L resume --state idle
grep -q '^state: idle$' "$F" && grep -q '^run: run_abc$' "$F" && pass "resume keeps fields it was not given" || fail "resume dropped a field"
L waiting "- web · #12 · PR in review
- lstn · SAVI-9 · waiting on Ezra"
grep -q '^- web · #12 · PR in review$' "$F" && grep -q '^- lstn · SAVI-9 · waiting on Ezra$' "$F" && grep -q '^### N-2 ' "$F" && pass "waiting section replaced" || fail "waiting"
L waiting "- only this now"
! grep -q 'SAVI-9 · waiting' "$F" && grep -q '^- only this now$' "$F" && pass "waiting replaces, never appends" || fail "waiting appended"
# A note the user left under the last item is theirs: it is neither that item's answer nor closed with it.
L list | grep -q "^N-2	merge-pr	web	#12	open	" && pass "a note after a blank line is not an answer" || fail "note read as an answer"
L close N-2 >/dev/null
grep -q '^my own note: call Ezra$' "$F" && ! grep -q 'my own note' "$TMP/open-loops-archive.md" && pass "closing an item leaves the user's note in place" || fail "close took the user's note"
[ "$(tail -c 1 "$F" | od -An -c | tr -d ' ')" = '\n' ] && pass "file always ends with a newline" || fail "no trailing newline"

printf '<<<<<<< HEAD\n' >> "$F"; L list >/dev/null 2>&1; [ $? -eq 3 ] && pass "conflict markers refuse" || fail "conflict markers"
sh "$SCRIPT" --file "$TMP/nope.md" list >/dev/null 2>&1; [ $? -eq 2 ] && pass "missing file is exit 2" || fail "missing file"
ls "$TMP" | grep -q '\.tmp\.' && fail "no temp files left" || pass "no temp files left"

# Headings the user pastes into an answer must not hide the items below it.
mkdir -p "$TMP/g"; G="$TMP/g/open-loops.md"; cp "$ROOT/skills/star/template/open-loops.md" "$G"
LG() { sh "$SCRIPT" --file "$G" "$@"; }
LG add --kind escalation --project p --item a --title one --body 'briefs/p/a.md\nOptions: answer / drop' >/dev/null
LG add --kind held --project p --item b --title two >/dev/null
LG add --kind held --project p --item c --title three >/dev/null
grep -q '^briefs/p/a.md$' "$G" && grep -q '^Options: answer / drop$' "$G" && pass "a literal \\n in --body becomes a new line" || fail "literal \\n in --body"
python3 - "$G" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("Options: answer / drop\nAnswer:", "Options: answer / drop\nAnswer: yes, and\n## a heading I pasted\n### a sub note\nmore", 1)
open(p, "w").write(s)
PY
[ "$(LG list | wc -l | tr -d ' ')" = 3 ] && pass "pasted headings do not hide later items" || fail "pasted headings hid items ($(LG list | wc -l))"
LG answers | grep -q "^N-1	escalation	p	a	yes, and ## a heading I pasted ### a sub note more$" && pass "pasted headings stay in the answer" || fail "answer truncated at a pasted heading ($(LG answers))"
LG close N-1 >/dev/null; ! grep -q 'a sub note' "$G" && grep -q 'a sub note' "$TMP/g/open-loops-archive.md" && grep -q '^### N-2 ' "$G" && pass "close takes the whole answer and nothing else" || fail "close with pasted headings"
[ "$(LG set-answer N-2 -drop)" = set ] && LG answers | grep -q "^N-2	held	p	b	-drop$" && pass "an answer may start with a dash" || fail "leading dash answer"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
