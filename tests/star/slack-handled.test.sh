#!/bin/sh
# Runs skills/star/slack-handled.sh against scratch STAR homes.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/slack-handled.sh"
LOOPS="$ROOT/skills/star/loops.sh"
TEMPLATE="$ROOT/skills/star/template/open-loops.md"
TMP=$(mktemp -d)
trap 'chmod -R u+rwx "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL slack-handled.sh missing"; exit 1; }
ID=C1-1729070000.123456
D=2026-10-16-app-slack-$ID.md
OLD=2026-10-14-app-slack-$ID.md
H=

t() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got: $3)"; fi
}
home() {
  H="$TMP/$1"
  mkdir -p "$H"
  cp "$TEMPLATE" "$H/open-loops.md"
}
S() { sh "$SCRIPT" --home "$H" "$@"; }
L() { sh "$LOOPS" --file "$H/open-loops.md" "$@"; }
draft() {
  mkdir -p "$H/drafts"
  printf 'to: slack C1 1729070000.123456\nIt ships Friday.\n' > "$H/drafts/$1"
}
reply_item() {
  body=$(printf 'draft: %s\nmessage: https://acme.slack.com/archives/C1/p1729070000123456\nSuggest: It ships Friday.\nOptions: send (recommended) / rewrite: <how> / skip' "$H/drafts/$1")
  L add --kind slack-reply --project app --item slack \
    --title 'Ria in #eng: is the CSV export landing today?' --body "$body"
}
sent() {
  printf '2026-10-16T05:10:00Z\tSTAR\tslack\tslack reply %s\n' "$1" >> "$H/sent.log"
}
snap() {
  {
    ls -1 "$H/drafts" 2>/dev/null || true
    cat "$H/open-loops.md" 2>/dev/null || true
    cat "$H/open-loops-archive.md" 2>/dev/null || true
  } | cksum
}

home none
t 'new message gets new' new "$(S "$ID")"

home open
draft "$D"
reply_item "$D" >/dev/null
before=$(snap)
t 'an open slack-reply item handles the draft' 'handled drafted '"$D" "$(S "$ID")"
t 'open handled adds no draft and no queue item' "$before" "$(snap)"

home sent
draft "$D"
n=$(reply_item "$D")
L close "$n" >/dev/null
sent "$D"
before=$(snap)
t 'a sent reply handles the draft' 'handled sent '"$D" "$(S "$ID")"
t 'sent handled adds no draft and no queue item' "$before" "$(snap)"

home sent-missing-draft
draft "$D"
n=$(reply_item "$D")
L close "$n" >/dev/null
sent "$D"
rm "$H/drafts/$D"
before=$(snap)
t 'a sent reply handles a removed draft' 'handled sent '"$D" "$(S "$ID")"
t 'sent handled with no draft adds no draft and no queue item' "$before" "$(snap)"

home skipped
draft "$D"
n=$(reply_item "$D")
L close "$n" >/dev/null
before=$(snap)
t 'an archived reply handles the draft' 'handled drafted '"$D" "$(S "$ID")"
t 'archived handled adds no draft and no queue item' "$before" "$(snap)"

home later
draft "$OLD"
n=$(reply_item "$OLD")
L close "$n" >/dev/null
before=$(snap)
t 'an older archived draft is handled' 'handled drafted '"$OLD" "$(S "$ID")"
t 'older handled adds no draft and no queue item' "$before" "$(snap)"

home rewrote
draft "$D"
n=$(reply_item "$D")
L close "$n" >/dev/null
reply_item "$D" >/dev/null
before=$(snap)
t 'an open rewrite still handles the draft' 'handled drafted '"$D" "$(S "$ID")"
t 'rewrite handled adds no draft and no queue item' "$before" "$(snap)"

home orphan
draft "$D"
t 'an orphan draft is queued' "queue $H/drafts/$D" "$(S "$ID")"

home orphans
draft "$OLD"
draft "$D"
t 'the newest orphan draft is queued' "queue $H/drafts/$D" "$(S "$ID")"

home heldonly
draft "$D"
L add --kind held --project app --item slack --title 'look at it' --body "$(printf 'draft: %s\nOptions: done' "$H/drafts/$D")" >/dev/null
t 'a held item mentioning a draft does not handle it' "queue $H/drafts/$D" "$(S "$ID")"

home prefix
draft 2026-10-16-app-slack-C1-1729070000.12345.md
n=$(reply_item 2026-10-16-app-slack-C1-1729070000.12345.md)
L close "$n" >/dev/null
sent 2026-10-16-app-slack-C1-1729070000.12345.md
t 'a longer id does not match a shorter sent id' new "$(S "$ID")"
t 'the shorter id matches its own sent draft' 'handled sent 2026-10-16-app-slack-C1-1729070000.12345.md' "$(S C1-1729070000.12345)"

home short
draft "$D"
t 'a shorter id does not match a longer draft' new "$(S C1-1729070000.12345)"

home bad
for bad in 'C1-*' 'C1 1.2' '../C1-1.2' '.C1' ''; do
  out=$(S "$bad" 2>/dev/null); rc=$?
  [ "$rc" -eq 64 ] && [ -z "$out" ] && pass "invalid id $bad is usage" || fail "invalid id $bad (rc=$rc out=$out)"
done
for label in no-id two-ids no-home-value unknown-option; do
  case "$label" in
    no-id) out=$(S 2>/dev/null); rc=$? ;;
    two-ids) out=$(S C1-1.2 C1-3.4 2>/dev/null); rc=$? ;;
    no-home-value) out=$(sh "$SCRIPT" --home 2>/dev/null); rc=$? ;;
    unknown-option) out=$(S --nope C1-1.2 2>/dev/null); rc=$? ;;
  esac
  [ "$rc" -eq 64 ] && [ -z "$out" ] && pass "$label is usage" || fail "$label (rc=$rc out=$out)"
done

home unread
draft "$D"
rm "$H/open-loops.md"
mkdir "$H/open-loops.md"
out=$(S "$ID" 2>/dev/null); rc=$?
[ "$rc" -eq 2 ] && [ -z "$out" ] && pass 'open-loops directory is unreadable' || fail "open-loops directory (rc=$rc out=$out)"

home noqueue
rm "$H/open-loops.md"
out=$(S "$ID" 2>/dev/null); rc=$?
[ "$rc" -eq 2 ] && [ -z "$out" ] && pass 'missing open-loops is an error' || fail "missing open-loops (rc=$rc out=$out)"

home badarchive
mkdir "$H/open-loops-archive.md"
out=$(S "$ID" 2>/dev/null); rc=$?
[ "$rc" -eq 2 ] && [ -z "$out" ] && pass 'archive directory is unreadable' || fail "archive directory (rc=$rc out=$out)"

home draftsfile
printf x > "$H/drafts"
out=$(S "$ID" 2>/dev/null); rc=$?
[ "$rc" -eq 2 ] && [ -z "$out" ] && pass 'drafts file is an error' || fail "drafts file (rc=$rc out=$out)"

if [ "$(id -u)" -ne 0 ]; then
  home locked
draft "$D"
reply_item "$D" >/dev/null
chmod 000 "$H/open-loops.md"
  out=$(S "$ID" 2>/dev/null); rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && pass 'unreadable queue is an error' || fail "unreadable queue (rc=$rc out=$out)"

  home lockedlog
  sent "$D"
  chmod 000 "$H/sent.log"
  out=$(S "$ID" 2>/dev/null); rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && pass 'unreadable sent log is an error' || fail "unreadable sent log (rc=$rc out=$out)"
fi

[ "$fails" -eq 0 ] && echo 'all passed' || echo "$fails failed"
[ "$fails" -eq 0 ]
