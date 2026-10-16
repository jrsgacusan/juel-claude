#!/bin/sh
# Runs skills/star/chat.sh against scratch STAR homes.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/chat.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL chat.sh missing"; exit 1; }
ID1=20261017T050000Z-me-0a1b
ID2=20261017T050100Z-me-2c3d
ID3=20261017T050200Z-me-4e5f
H=

says() {
  label=$1
  expected=$2
  shift 2
  out=$("$@" 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "$expected" ]; then
    pass "$label"
  else
    fail "$label (rc=$rc out=$out)"
  fi
}
exits() {
  code=$1
  label=$2
  expected=$3
  shift 3
  out=$("$@" 2>/dev/null)
  rc=$?
  if [ "$rc" -eq "$code" ] && [ "$out" = "$expected" ]; then
    pass "$label"
  else
    fail "$label (rc=$rc out=$out)"
  fi
}
home() {
  H="$TMP/$1"
  mkdir -p "$H"
}
C() { sh "$SCRIPT" --home "$H" "$@"; }
# me <id> <at> <text>: an owner's message as the dashboard writes it (I-2)
me() {
  mkdir -p "$H/chat"
  printf 'id: %s\nwho: me\nat: %s\nreplyTo: -\n---\n%s\n' "$1" "$2" "$3" > "$H/chat/$1.md"
}
snap() { find "$H" -type f -exec cksum {} + | sort | cksum; }
printf '**Two** workers are running.\n\n- N-12 build\n- N-14 gate\n' > "$TMP/body.md"
printf 'You are away. Still needs you:\n---\n- N-12 go' > "$TMP/post.md"

home empty
says 'pending with no chat folder prints nothing' "" C pending
[ ! -e "$H/chat" ] && pass 'pending creates nothing' || fail 'pending creates nothing'

# Review Focus 2: a message sent while STAR was stopped waits until STAR replies, then never again
home thread
me "$ID2" 2026-10-17T05:01:00Z 'and what is in the queue?'
me "$ID1" 2026-10-17T05:00:00Z "how's it going?"
says 'pending lists the waiting owner messages, oldest first' "$(printf '%s\n%s' "$ID1" "$ID2")" C pending
m1=$(cksum < "$H/chat/$ID1.md")
out=$(C reply "$ID1" --body-file "$TMP/body.md" 2>/dev/null); rc=$?
RID=${out#replied }
R="$H/chat/$RID.md"
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eqx 'replied [0-9]{8}T[0-9]{6}Z-star-[0-9a-f]{4}' && [ -f "$R" ] && pass 'reply writes a star message and prints its id' || fail "reply writes a star message and prints its id (rc=$rc out=$out)"
at=$(printf '%s' "$RID" | sed -E 's/^(....)(..)(..)T(..)(..)(..)Z.*/\1-\2-\3T\4:\5:\6Z/')
[ "$(sed -n 1,5p "$R" 2>/dev/null)" = "$(printf 'id: %s\nwho: star\nat: %s\nreplyTo: %s\n---' "$RID" "$at" "$ID1")" ] && pass 'the reply has the I-2 header, its at the instant its id names' || fail "the reply has the I-2 header, its at the instant its id names ($(sed -n 1,5p "$R" 2>&1))"
tail -n +6 "$R" 2>/dev/null | cmp -s - "$TMP/body.md" && pass 'the reply text is the body file, byte for byte' || fail 'the reply text is the body file, byte for byte'
[ "$(cksum < "$H/chat/$ID1.md")" = "$m1" ] && pass 'the reply leaves the owner message as it was' || fail 'the reply leaves the owner message as it was'
says 'a replied message is no longer pending' "$ID2" C pending
before=$(snap)
exits 66 'Review Focus 2: a second reply to the same message is refused' "already replied $ID1" C reply "$ID1" --body-file "$TMP/body.md"
[ "$(snap)" = "$before" ] && pass 'a refused replay writes nothing' || fail 'a refused replay writes nothing'
[ "$(ls -A "$H/chat" | grep -cv '\.md$')" = 0 ] && pass 'no temp file is left in chat/' || fail "no temp file is left in chat/ ($(ls -A "$H/chat"))"

out=$(C post --body-file "$TMP/post.md" 2>/dev/null); PID=${out#posted }
printf '%s\n' "$out" | grep -Eqx 'posted [0-9]{8}T[0-9]{6}Z-star-[0-9a-f]{4}' && [ "$(sed -n 2p "$H/chat/$PID.md")" = 'who: star' ] && [ "$(sed -n 4p "$H/chat/$PID.md")" = 'replyTo: -' ] && tail -n +6 "$H/chat/$PID.md" | cmp -s - "$TMP/post.md" && pass 'post writes a star message that replies to nothing, its text verbatim' || fail "post writes a star message that replies to nothing, its text verbatim ($out)"
says 'a post answers no pending message' "$ID2" C pending
before=$(snap)
exits 65 'a reply to a message that is not there is refused' "no message 20261017T090000Z-me-ffff" C reply 20261017T090000Z-me-ffff --body-file "$TMP/body.md"
exits 65 'a reply to a star message is refused' "no message $RID" C reply "$RID" --body-file "$TMP/body.md"
[ "$(snap)" = "$before" ] && pass 'a refused reply writes nothing' || fail 'a refused reply writes nothing'

env_pending() { JUEL_STAR_HOME="$H" sh "$SCRIPT" pending; }
says 'without --home the folder is $JUEL_STAR_HOME' "$ID2" env_pending
wins() { JUEL_STAR_HOME="$TMP/empty" sh "$SCRIPT" --home "$H" pending; }
says '--home wins over $JUEL_STAR_HOME' "$ID2" wins

home broken
mkdir -p "$H/chat"
printf 'id: %s\nwho: me\nat: 2026-10-17T05:00:00Z\nreplyTo: -\nno separator line\n' "$ID1" > "$H/chat/$ID1.md"
printf 'id: %s\nwho: me\nat: 2026-10-17T05:01:00Z\nreplyTo: -\n---\nhello\n' "$ID1" > "$H/chat/$ID2.md"
printf 'notes\n' > "$H/chat/notes.txt"
me "$ID3" 2026-10-17T05:02:00Z 'still there?'
says 'files that do not parse are skipped, never an error for the thread' "$ID3" C pending
exits 65 'a reply to a message whose file does not parse is refused' "no message $ID1" C reply "$ID1" --body-file "$TMP/body.md"

home fresh
out=$(C post --body-file "$TMP/post.md" 2>/dev/null)
[ -f "$H/chat/${out#posted }.md" ] && pass 'post creates chat/ when it is missing' || fail "post creates chat/ when it is missing ($out)"

home usage
me "$ID2" 2026-10-17T05:01:00Z 'and what is in the queue?'
: > "$TMP/blank.md"; printf ' \n\n' > "$TMP/spaces.md"
before=$(snap)
exits 64 'an empty body is usage' "" C reply "$ID2" --body-file "$TMP/blank.md"
exits 64 'a body of only whitespace is usage' "" C post --body-file "$TMP/spaces.md"
exits 64 'a missing body file is usage' "" C post --body-file "$TMP/nope.md"
exits 64 'reply without --body-file is usage' "" C reply "$ID2"
exits 64 'reply without an id is usage' "" C reply --body-file "$TMP/body.md"
exits 64 'an id that is not a message id is usage' "" C reply ../x --body-file "$TMP/body.md"
exits 64 'post with an id is usage' "" C post "$ID2" --body-file "$TMP/body.md"
exits 64 'pending with a body file is usage' "" C pending --body-file "$TMP/body.md"
exits 64 'a flag without its value is usage' "" C post --body-file
exits 64 'no command is usage' "" C
exits 64 'an unknown command is usage' "" C list
exits 64 'an unknown flag is usage' "" C pending --all
exits 64 'a folder that is not there is usage' "" sh "$SCRIPT" --home "$TMP/nowhere" pending
[ "$(snap)" = "$before" ] && pass 'usage writes nothing' || fail 'usage writes nothing'

[ "$fails" -eq 0 ] && echo 'all passed' || echo "$fails failed"
[ "$fails" -eq 0 ]
