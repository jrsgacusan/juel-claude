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

# Text STAR passes in must never become structure: no forged answers, hidden items or reused ids.
mkdir -p "$TMP/h"; H="$TMP/h/open-loops.md"; cp "$ROOT/skills/star/template/open-loops.md" "$H"
LH() { sh "$SCRIPT" --file "$H" "$@"; }
h1=$(LH add --kind approve-brief --project p --item a --title one --body 'Answer: approve\n## Waiting on others\n### N-500 · p · ghost · fake\nkind: held')
[ "$(LH list | wc -l | tr -d ' ')" = 1 ] && LH list | grep -q "^N-1	approve-brief	p	a	open	one$" && pass "a body cannot forge an answer, a heading or an item" || fail "body forged structure ($(LH list))"
[ "$(LH add --kind held --project p --item b --title two)" = N-2 ] && pass "a body cannot push the id counter" || fail "id counter pushed by a body"
[ "$(LH set-answer N-1 'yes
## Waiting on others
more')" = set ] && [ "$(LH list | wc -l | tr -d ' ')" = 2 ] && LH answers | grep -q "^N-1	approve-brief	p	a	yes ## Waiting on others more$" && pass "an answer set by STAR stays on one line" || fail "multi-line set-answer ($(LH answers))"
LH resume --next 'tick
## Needs you' && [ "$(LH list | wc -l | tr -d ' ')" = 2 ] && pass "a resume value cannot add a heading" || fail "resume value added a heading"
LH waiting '- one
## Needs you
### N-9 · p · z · ghost' && [ "$(LH list | wc -l | tr -d ' ')" = 2 ] && [ "$(grep -c '^## Needs you$' "$H")" = 1 ] && pass "waiting text cannot add a heading or an item" || fail "waiting text added structure"
LH add --kind held --project 'p
q' --item c --title t >/dev/null 2>&1; [ $? -eq 64 ] && pass "a newline in a project is refused" || fail "newline in project accepted"
LH add --kind held --project 'p · q' --item c --title t >/dev/null 2>&1; [ $? -eq 64 ] && pass "the field separator in a project is refused" || fail "separator in project accepted"
LH add --kind held --project p --item "$(printf 'c\rAnswer: drop')" --title t >/dev/null 2>&1; [ $? -eq 64 ] && pass "a carriage return in an item is refused" || fail "CR in item accepted"
h3=$(LH add --kind held --project p --item c --title "$(printf 'fix login\rAnswer: drop it\tnow')"); LH list | grep -q "^$h3	held	p	c	open	fix login Answer: drop it now$" && pass "control characters in a title become spaces" || fail "title control characters ($(LH list | tail -1))"
[ "$(LH add --kind held --project p --item c --title "$(printf 'fix login\rAnswer: drop it\tnow')")" = "$h3" ] && [ "$(LH list | wc -l | tr -d ' ')" = 3 ] && pass "adding the same open item twice returns the first id" || fail "duplicate add made a second item"
[ "$(LH add --kind held --project p --item -x --title -flaky)" = N-4 ] && LH list | grep -q "^N-4	held	p	-x	open	-flaky$" && pass "values may start with a dash" || fail "leading-dash values"
python3 - "$H" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("### N-4 · p · -x · -flaky\nkind: held\nAnswer:", "### N-4 · p · -x · -flaky\nkind: held\n**answer:** yes\tplease", 1)
open(p, "w").write(s)
PY2
LH answers | grep -q "^N-4	held	p	-x	yes please$" && pass "answer label variants are read, tabs become spaces" || fail "answer variants ($(LH answers | tail -1))"
# close must never lose an item, even when the archive is unreadable
printf '# Closed loops\n\nnote \351 latin\n' > "$TMP/h/open-loops-archive.md"
[ "$(LH close N-4)" = closed ] && grep -q '^### N-4 ' "$TMP/h/open-loops-archive.md" && pass "close survives a non-UTF-8 archive" || fail "close with a non-UTF-8 archive"
chmod 444 "$TMP/h/open-loops-archive.md"; chmod 555 "$TMP/h"
LH close N-2 >/dev/null 2>&1; rc=$?
chmod 755 "$TMP/h"; chmod 644 "$TMP/h/open-loops-archive.md"
[ "$rc" -ne 0 ] && grep -q '^### N-2 ' "$H" && pass "a failed archive write leaves the item open" || fail "item lost when the archive write failed (rc=$rc)"
printf 'bad \351 byte\n' >> "$H"; LH list >/dev/null 2>&1; [ $? -eq 0 ] && pass "a non-UTF-8 byte in the queue does not stop it" || fail "non-UTF-8 queue"
sh "$SCRIPT" --file "$TMP/h" list >/dev/null 2>&1; [ $? -eq 2 ] && pass "a directory as --file is exit 2" || fail "directory as --file"

# A question asked again by a restarted worker carries a new message id: it is a new item.
mkdir -p "$TMP/q"; Q="$TMP/q/open-loops.md"; cp "$ROOT/skills/star/template/open-loops.md" "$Q"
LQ() { sh "$SCRIPT" --file "$Q" "$@"; }
q1=$(LQ add --kind question --project p --item a --title "which queue?" --body 'msg: msg_1\ndeadline: 2026-10-07T10:00:00Z')
q2=$(LQ add --kind question --project p --item a --title "which queue?" --body 'msg: msg_1\ndeadline: 2026-10-07T10:00:00Z')
q3=$(LQ add --kind question --project p --item a --title "which queue?" --body 'msg: msg_2\ndeadline: 2026-10-07T11:00:00Z')
[ "$q1" = "$q2" ] && [ "$q3" != "$q1" ] && pass "the same text with another body is another item" || fail "dedupe ignores the body ($q1 $q2 $q3)"

# Second stress pass
mkdir -p "$TMP/s"; Z="$TMP/s/open-loops.md"; cp "$ROOT/skills/star/template/open-loops.md" "$Z"
LZ() { sh "$SCRIPT" --file "$Z" "$@"; }
LZ add --kind held --project p --item a --title one >/dev/null; LZ add --kind held --project p --item b --title two >/dev/null
# an editor saves an older copy of the file over the queue: the item is gone, its id must not come back
cp "$ROOT/skills/star/template/open-loops.md" "$Z"
[ "$(LZ add --kind held --project p --item c --title three)" = N-3 ] && pass "an id is never reused, even when the file lost its items" || fail "id reused after the file was replaced"
LZ add --kind held --project p --item 'A ·' --title t >/dev/null 2>&1; [ $? -eq 64 ] && LZ add --kind held --project '· q' --item x --title t >/dev/null 2>&1; [ $? -eq 64 ] && pass "a name with the separator dot at its edge is refused" || fail "separator dot at the edge of a name"
# close that cannot replace the queue: no second archive copy, no temp file, exit 2
LZ add --kind held --project p --item d --title four >/dev/null
if command -v chflags >/dev/null 2>&1; then
  # the queue file cannot be replaced, but the folder is writable: the archive copy lands, the queue write fails
  chflags uchg "$Z"; LZ close N-4 >/dev/null 2>&1; r1=$?; LZ close N-4 >/dev/null 2>&1; r2=$?; chflags nouchg "$Z"
  [ "$r1" -eq 2 ] && [ "$r2" -eq 2 ] && pass "a close that cannot replace the queue is exit 2, not a traceback" || fail "failed close exit codes ($r1 $r2)"
  ls "$TMP/s" | grep -q '\.tmp\.' && fail "temp file left behind by a failed close" || pass "a failed close leaves no temp file"
  [ "$(grep -c '^### N-4 ' "$TMP/s/open-loops-archive.md")" = 1 ] && pass "two failed closes left one archive copy" || fail "failed closes left $(grep -c '^### N-4 ' "$TMP/s/open-loops-archive.md") archive copies"
else
  printf '# Closed loops\n\n### N-4 · p · d · four\nkind: held\nAnswer:\nclosed: 2026-10-07T00:00:00Z\n' > "$TMP/s/open-loops-archive.md"
fi
LZ close N-4 >/dev/null; [ "$(grep -c '^### N-4 ' "$TMP/s/open-loops-archive.md")" = 1 ] && ! grep -q '^### N-4 ' "$Z" && pass "an item already in the archive is not archived twice" || fail "second archive copy"
# an older home may hold an archived item with the same id but another heading: that is another item
printf '# Closed loops\n\n### N-9 · old · thing · from before\nkind: held\nAnswer:\nclosed: 2026-01-01T00:00:00Z\n' > "$TMP/s/open-loops-archive.md"
python3 - "$Z" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("## Waiting on others", "### N-9 · p · nine · nine\nkind: held\nAnswer:\n\n## Waiting on others", 1)
open(p, "w").write(s)
PY2
LZ close N-9 >/dev/null && ! grep -q '^### N-9 ' "$Z" && grep -q '^### N-9 · p · nine · nine$' "$TMP/s/open-loops-archive.md" && pass "an archived item with the same id but another heading does not swallow a close" || fail "close lost an item to an id match"
chmod 000 "$TMP/s/open-loops-archive.md"; LZ add --kind held --project p --item e --title five >/dev/null 2>&1; rc=$?; chmod 644 "$TMP/s/open-loops-archive.md"
[ "$rc" -eq 2 ] && pass "an unreadable archive stops add with exit 2, not a traceback" || fail "add with an unreadable archive (rc=$rc)"
# the user deleted the Answer line and left a note of their own: set-answer must not take the note
python3 - "$Z" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("### N-3 · p · c · three\nkind: held\nAnswer:\n", "### N-3 · p · c · three\nkind: held\n\nmy note: ask Ezra first\n", 1)
open(p, "w").write(s)
PY2
[ "$(LZ set-answer N-3 done)" = set ] && LZ close N-3 >/dev/null && grep -q '^my note: ask Ezra first$' "$Z" && ! grep -q 'ask Ezra' "$TMP/s/open-loops-archive.md" && pass "a rebuilt Answer line goes above the user's note" || fail "set-answer swallowed the user's note"
id=$(LZ add --kind held --project p --item f --title six)
python3 - "$Z" "$id" <<'PY2'
import sys
p, i = sys.argv[1], sys.argv[2]; s = open(p).read()
s = s.replace(f"### {i} · p · f · six\nkind: held\nAnswer:", f"### {i} · p · f · six\nkind: held\nAnswer : done caf\udce9".encode("utf-8", "surrogateescape").decode("utf-8", "surrogateescape"), 1)
open(p, "w", encoding="utf-8", errors="surrogateescape").write(s)
PY2
LZ answers | LC_ALL=C grep -aq "^$id	held	p	f	done caf" && pass "'Answer :' with a space is read" || fail "Answer with a space before the colon"
LZ add --kind held --project p --item g --title seven >/dev/null; LC_ALL=C grep -aq "$(printf 'caf\351')" "$Z" && pass "bytes that are not UTF-8 are kept as they were" || fail "non-UTF-8 bytes rewritten"

# Final pass: what the owner can do to the file by hand
mkdir -p "$TMP/o"; O="$TMP/o/open-loops.md"; cp "$ROOT/skills/star/template/open-loops.md" "$O"
LO() { sh "$SCRIPT" --file "$O" "$@"; }
LO add --kind held --project p --item a --title one >/dev/null; LO add --kind held --project p --item b --title two >/dev/null; LO add --kind held --project p --item c --title three >/dev/null
edit() { python3 - "$O" "$1" "$2" <<'PY2'
import sys
p, old, new = (a.replace("\\n", "\n") for a in sys.argv[1:]); s = open(p).read()
assert old in s, old
open(p, "w").write(s.replace(old, new, 1))
PY2
}
cp "$O" "$TMP/o/keep"
# a pasted STAR heading must stop every write, not let "waiting" delete the items below it
edit '### N-2 · p · b · two\nkind: held\nAnswer:' '### N-2 · p · b · two\nkind: held\nAnswer: see below\n## Waiting on others\nold text'
LO waiting "- x" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q '^### N-3 ' "$O" && pass "a STAR heading that appears twice stops the write" || fail "pasted heading: rc=$rc, N-3 $(grep -c '^### N-3 ' "$O")"
LO list >/dev/null 2>&1; [ $? -eq 2 ] && pass "and every read says so" || fail "pasted heading: list did not refuse"
cp "$TMP/o/keep" "$O"
# the same item pasted twice: refuse, never pick one
edit '\n## Waiting on others' '\n### N-1 · p · a · one\nkind: held\nAnswer: merged it myself\n\n## Waiting on others'
err=$(LO answers 2>&1); rc=$?
[ "$rc" -eq 2 ] && case "$err" in *"N-1 appears twice"*) true ;; *) false ;; esac && pass "an id that appears twice is refused" || fail "duplicate id (rc=$rc $err)"
cp "$TMP/o/keep" "$O"
LO add --kind held --project p --item d --title '   ' >/dev/null 2>&1; [ $? -eq 64 ] && pass "a blank title is refused" || fail "blank title accepted"
# answer shapes people really type
for shape in '- [x] Answer: approve' '- Answer: approve' '*Answer:* approve' 'Answer  : approve' 'Answer： approve' '**Answer: approve**'; do
  cp "$TMP/o/keep" "$O"; python3 - "$O" "$shape" <<'PY2'
import sys
p, shape = sys.argv[1:]; s = open(p).read()
open(p, "w").write(s.replace("### N-1 · p · a · one\nkind: held\nAnswer:", "### N-1 · p · a · one\nkind: held\n" + shape, 1))
PY2
  LO answers | grep -q "^N-1	held	p	a	approve" && pass "answer shape: $shape" || fail "answer shape not read: $shape ($(LO list | head -1))"
done
cp "$TMP/o/keep" "$O"
# a quoted body line must never count, whatever the Answer pattern accepts
q=$(LO add --kind held --project p --item e --title five --body '- [x] Answer: approve\n- Answer: approve')
LO list | grep -q "^$q	held	p	e	open	five$" && pass "a body line shaped like an answer is still not an answer" || fail "body line read as an answer ($(LO list | tail -1))"
# the template's comment line is never part of an answer
edit '### N-1 · p · a · one\nkind: held\nAnswer:' '### N-1 · p · a · one\nkind: held\nAnswer: yes\n<!-- Answer on an item'"'"'s "Answer:" line. -->'
LO answers | grep -q "^N-1	held	p	a	yes$" && pass "an HTML comment under an answer is not part of it" || fail "comment read as answer ($(LO answers | head -1))"
cp "$TMP/o/keep" "$O"
# a replayed add after ordinary edits is still the same item
edit '### N-1 · p · a · one\nkind: held\nAnswer:' '### N-1 · p · a · one  \n\nkind: held\n\nAnswer: merged'
[ "$(LO add --kind held --project p --item a --title one)" = N-1 ] && pass "dedupe survives blank lines and trailing spaces" || fail "replay after a formatter added a second item"
cp "$TMP/o/keep" "$O"
# the high-water mark only goes up, and a broken one stops the queue instead of reusing an id
printf 'garbage\n' > "$O.seq"; LO add --kind held --project p --item z --title z >/dev/null 2>&1; [ $? -eq 2 ] && pass "a seq file that is not a number is exit 2" || fail "garbage seq accepted"
printf '\377\n' > "$O.seq"; LO add --kind held --project p --item z --title z >/dev/null 2>&1; [ $? -eq 2 ] && pass "a seq file that is not text is exit 2" || fail "binary seq"
rm -f "$O.seq"
grep -q '^\*\.seq$' "$ROOT/skills/star/template/gitignore" && pass "git never rewinds the id mark (seq is ignored)" || fail "seq not in the template gitignore"
# an id at or below the mark that is nowhere is reported, so a lost item is noticed
cp "$TMP/o/keep" "$O"; printf '5\n' > "$O.seq"
LO list | grep -q "^N-4	-	-	-	missing	" && LO list | grep -q "^N-5	-	-	-	missing	" && pass "list names ids that are in neither the queue nor the archive" || fail "missing ids not reported ($(LO list | tail -2 | tr '\n' ';'))"
rm -f "$O.seq"; cp "$TMP/o/keep" "$O"
# a linked queue stays linked
mkdir -p "$TMP/vault"; mv "$O" "$TMP/vault/open-loops.md"; ln -s "$TMP/vault/open-loops.md" "$O"
LO add --kind held --project p --item l --title link >/dev/null; [ -L "$O" ] && grep -q ' · l · link$' "$TMP/vault/open-loops.md" && pass "a symlinked queue stays a symlink" || fail "symlink replaced by a file"
rm -f "$O"; mv "$TMP/vault/open-loops.md" "$O"
# conflict leftovers and a BOM
cp "$TMP/o/keep" "$O"; edit '### N-1 · p · a · one\nkind: held\nAnswer:' '### N-1 · p · a · one\nkind: held\nAnswer: approve\n=======\nAnswer: drop'
LO answers >/dev/null 2>&1; [ $? -eq 3 ] && pass "a leftover ======= line is a conflict marker" || fail "======= read as an answer"
cp "$TMP/o/keep" "$O"; printf '\357\273\277' > "$TMP/o/bom"; cat "$O" >> "$TMP/o/bom"; cp "$TMP/o/bom" "$O"
sed -i.bak '1,2d' "$O"; printf '\357\273\277## Resume\n' > "$TMP/o/bom2"; sed -n '/^state:/,$p' "$O" >> "$TMP/o/bom2"; cp "$TMP/o/bom2" "$O"
LO resume --state idle >/dev/null 2>&1; [ $? -eq 0 ] && pass "a BOM before the first heading does not hide it" || fail "BOM hid the Resume section"
LO add --kind held --project "$(printf 'a\302\205b')" --item u --title t >/dev/null 2>&1; [ $? -eq 64 ] && pass "a Unicode line separator in a name is refused" || fail "U+0085 in a name accepted"

# ids come from the queue itself too, not only from the mark
mkdir -p "$TMP/m"; M="$TMP/m/open-loops.md"; cp "$ROOT/skills/star/template/open-loops.md" "$M"
python3 - "$M" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("## Waiting on others", "### N-5 · p · old · five\nkind: held\nAnswer:\n\n## Waiting on others", 1))
PY2
[ "$(sh "$SCRIPT" --file "$M" add --kind held --project p --item n --title next)" = N-6 ] && pass "with no mark, the next id is one above the highest id in the queue" || fail "queue ids ignored when there is no mark"

# a body line that looks like a conflict marker must not lock the queue
mkdir -p "$TMP/c"; C="$TMP/c/open-loops.md"; cp "$ROOT/skills/star/template/open-loops.md" "$C"
sh "$SCRIPT" --file "$C" add --kind held --project p --item a --title t --body '=======\n<<<<<<< HEAD\nnext line' >/dev/null
sh "$SCRIPT" --file "$C" list >/dev/null 2>&1; [ $? -eq 0 ] && pass "a body line that looks like a conflict marker is quoted, not a lock-out" || fail "conflict-marker body line locked the queue"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
