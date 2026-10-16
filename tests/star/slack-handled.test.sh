#!/bin/sh
# Runs skills/star/slack-handled.sh against scratch STAR homes.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/slack-handled.sh"
LOOPS="$ROOT/skills/star/loops.sh"
TEMPLATE="$ROOT/skills/star/template/open-loops.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL slack-handled.sh missing"; exit 1; }
ID=C1-1729070000.123456
SHORT=C1-1729070000.12345
D=2026-10-16-app-slack-$ID.md
SD=2026-10-16-app-slack-$SHORT.md
OLD=2026-10-14-app-slack-$ID.md
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
  shift 2
  out=$("$@" 2>/dev/null)
  rc=$?
  if [ "$rc" -eq "$code" ] && [ -z "$out" ]; then
    pass "$label"
  else
    fail "$label (rc=$rc out=$out)"
  fi
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
closed_item() {
  n=$(reply_item "$1")
  L set-answer "$n" "$2" >/dev/null
  L close "$n" >/dev/null
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
says 'new message gets new' "new" S "$ID"

home open
draft "$D"
reply_item "$D" >/dev/null
before=$(snap)
says 'an open slack-reply item handles the draft' "handled drafted $D" S "$ID"
says 'open handled adds no draft and no queue item' "$before" snap

home sent
draft "$D"
closed_item "$D" send
sent "$D"
before=$(snap)
says 'a sent reply handles the draft' "handled sent $D" S "$ID"
says 'sent handled adds no draft and no queue item' "$before" snap

home sent-missing-draft
draft "$D"
closed_item "$D" send
sent "$D"
rm "$H/drafts/$D"
before=$(snap)
says 'a sent reply handles a removed draft' "handled sent $D" S "$ID"
says 'sent handled with no draft adds no draft and no queue item' "$before" snap

home skipped
draft "$D"
closed_item "$D" skip
before=$(snap)
says 'an archived reply handles the draft' "handled drafted $D" S "$ID"
says 'archived handled adds no draft and no queue item' "$before" snap

home later
draft "$OLD"
closed_item "$OLD" skip
before=$(snap)
says 'an older archived draft is handled' "handled drafted $OLD" S "$ID"
says 'older handled adds no draft and no queue item' "$before" snap

home rewrote
draft "$D"
closed_item "$D" 'rewrite: shorter'
reply_item "$D" >/dev/null
before=$(snap)
says 'an open rewrite still handles the draft' "handled drafted $D" S "$ID"
says 'rewrite handled adds no draft and no queue item' "$before" snap

home orphan
draft "$D"
says 'an orphan draft is queued' "queue $H/drafts/$D" S "$ID"

home orphans
draft "$OLD"
draft "$D"
says 'the newest orphan draft is queued' "queue $H/drafts/$D" S "$ID"

home heldonly
draft "$D"
L add --kind held --project app --item slack --title 'look at it' --body "$(printf 'draft: %s\nOptions: done' "$H/drafts/$D")" >/dev/null
says 'a held item mentioning a draft does not handle it' "queue $H/drafts/$D" S "$ID"

home prefix
draft "$SD"
closed_item "$SD" send
sent "$SD"
says 'a longer id does not match a shorter sent id' "new" S "$ID"
says 'the shorter id matches its own sent draft' "handled sent $SD" S "$SHORT"

home short
draft "$D"
says 'a shorter id does not match a longer draft' "new" S "$SHORT"

home linked
mkdir "$TMP/vault"
mv "$H/open-loops.md" "$TMP/vault/"
ln -s "$TMP/vault/open-loops.md" "$H/open-loops.md"
draft "$D"
closed_item "$D" skip
if [ -f "$TMP/vault/open-loops-archive.md" ] && [ ! -e "$H/open-loops-archive.md" ]; then
  pass 'loops.sh archives a linked queue beside its target'
else
  fail 'loops.sh archives a linked queue beside its target'
fi
says 'a linked queue handles the draft' "handled drafted $D" S "$ID"
before=$(snap)
says 'linked handled adds no draft and no queue item' "$before" snap

home ticked
draft "$D"
L add --kind slack-reply --project app --item slack \
  --title 'Ria in #eng: is the CSV export landing today?' \
  --body "$(printf 'draft: `%s`\nmessage: https://acme.slack.com/archives/C1/p1729070000123456\nSuggest: It ships Friday.\nOptions: send (recommended) / rewrite: <how> / skip' "$H/drafts/$D")" >/dev/null
before=$(snap)
says 'a ticked draft path handles the draft' "handled drafted $D" S "$ID"
says 'ticked handled adds no draft and no queue item' "$before" snap

home longsent
sent "$D"
says 'a long sent id does not match a shorter id' "new" S "$SHORT"

home mixed
draft "$OLD"
closed_item "$OLD" skip
draft "$D"
before=$(snap)
says 'only the older handled draft is reported' "handled drafted $OLD" S "$ID"
says 'mixed handled adds no draft and no queue item' "$before" snap

home answerline
draft "$D"
other=2026-10-16-app-slack-C2-1729070000.000001.md
n=$(reply_item "$other")
python3 - "$H/open-loops.md" "$n" "$H/drafts/$D" <<'PY'
import sys
path, item_id, draft = sys.argv[1:]
lines = open(path, encoding='utf-8').read().splitlines()
heading = f"### {item_id} · "
start = next(i for i, line in enumerate(lines) if line.startswith(heading))
answer = next(i for i in range(start + 1, len(lines)) if lines[i].startswith('Answer:'))
lines[answer:answer + 1] = ['Answer: rewrite: shorter', f'draft: {draft}']
open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
PY
says 'a draft line after a typed Answer is ignored' "queue $H/drafts/$D" S "$ID"

home noanswer
draft "$D"
n=$(reply_item "$other")
held=$(L add --kind held --project app --item slack --title 'look at it' --body "draft: $H/drafts/$D\\nOptions: done")
python3 - "$H/open-loops.md" "$n" "$held" <<'PY'
import sys
path, item_id, held_id = sys.argv[1:]
lines = open(path, encoding='utf-8').read().splitlines()
heading = f"### {item_id} · "
start = next(i for i, line in enumerate(lines) if line.startswith(heading))
answer = next(i for i in range(start + 1, len(lines)) if lines[i].startswith('Answer:'))
lines.pop(answer)
held_heading = f"### {held_id} · "
held_at = next(i for i, line in enumerate(lines) if line.startswith(held_heading))
assert held_at > start
open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
PY
says 'a draft line after a missing Answer is ignored' "queue $H/drafts/$D" S "$ID"

home gone
draft "$D"
closed_item "$D" skip
rm "$H/drafts/$D"
says 'an item whose draft is gone does not count, so the message reads as new' "new" S "$ID"

home lookalike
draft "2026-10-16-app-slack-X$ID.md"
says 'a lookalike id does not match' "new" S "$ID"

home rel
draft "$D"
rel_cmd() { (cd "$TMP" && sh "$SCRIPT" --home rel "$ID"); }
says 'a relative home returns an absolute draft path' "queue $(cd "$TMP" && pwd -P)/rel/drafts/$D" rel_cmd

home sentbroken
sent "$D"
rm "$H/open-loops.md"
mkdir "$H/open-loops.md"
exits 2 'a broken queue fails closed after a sent reply' S "$ID"

home conflict
draft "$D"
reply_item "$D" >/dev/null
printf '<<<<<<< ours\n=======\n>>>>>>> theirs\n' >> "$H/open-loops.md"
exits 2 'an open queue with conflict markers fails closed' S "$ID"

home conflictarchive
printf '# Closed loops\n\n<<<<<<< HEAD\n' > "$H/open-loops-archive.md"
exits 2 'an archive with conflict markers fails closed' S "$ID"

home danglingdrafts
ln -s "$TMP/nowhere" "$H/drafts"
exits 2 'a dangling drafts link fails closed' S "$ID"

home danglinglog
ln -s "$TMP/nowhere" "$H/sent.log"
exits 2 'a dangling sent log link fails closed' S "$ID"

home danglingarchive
ln -s "$TMP/nowhere" "$H/open-loops-archive.md"
exits 2 'a dangling archive link fails closed' S "$ID"

home bad
exits 64 'invalid id C1-* is usage' S 'C1-*'
exits 64 'invalid id C1 1.2 is usage' S 'C1 1.2'
exits 64 'invalid id ../C1-1.2 is usage' S '../C1-1.2'
exits 64 'invalid id .C1 is usage' S '.C1'
exits 64 'invalid empty id is usage' S ''
exits 64 'no-id is usage' S
exits 64 'two-ids is usage' S C1-1.2 C1-3.4
exits 64 'no-home-value is usage' sh "$SCRIPT" --home
exits 64 'unknown-option is usage' S --nope C1-1.2

home unread
draft "$D"
rm "$H/open-loops.md"
mkdir "$H/open-loops.md"
exits 2 'open-loops directory is unreadable' S "$ID"

home noqueue
rm "$H/open-loops.md"
exits 2 'missing open-loops is an error' S "$ID"

home badarchive
mkdir "$H/open-loops-archive.md"
exits 2 'archive directory is unreadable' S "$ID"

home draftsfile
printf x > "$H/drafts"
exits 2 'drafts file is an error' S "$ID"

if [ "$(id -u)" -ne 0 ]; then
  home locked
  draft "$D"
  reply_item "$D" >/dev/null
  chmod 000 "$H/open-loops.md"
  exits 2 'unreadable queue is an error' S "$ID"

  home lockedlog
  sent "$D"
  chmod 000 "$H/sent.log"
  exits 2 'unreadable sent log is an error' S "$ID"
fi

[ "$fails" -eq 0 ] && echo 'all passed' || echo "$fails failed"
[ "$fails" -eq 0 ]
