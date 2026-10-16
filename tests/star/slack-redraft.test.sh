#!/bin/sh
# Runs skills/star/slack-redraft.sh against scratch STAR homes.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/slack-redraft.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL slack-redraft.sh missing"; exit 1; }
D=2026-10-17-app-slack-C1-1729070000.123456.md
H=

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
  mkdir -p "$H/drafts"
  printf 'to: slack C1 1729070000.123456\nIt ships Friday.\n' > "$H/drafts/$D"
}
R() { sh "$SCRIPT" --home "$H" "$@"; }
requests() { ls -A "$H/slack/redraft" 2>/dev/null; }

home one
out=$(R --draft "$H/drafts/$D" --loop N-48 --how 'shorter, and say Friday' 2>/dev/null); rc=$?
name=${out#requested }
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eqx 'requested [0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}\.md' && [ "$(requests)" = "$name" ] && pass 'a request is written under the name it prints' || fail "a request is written under the name it prints (rc=$rc out=$out files=$(requests))"
printf 'draft: %s\nloop: N-48\nhow: shorter, and say Friday\n' "$H/drafts/$D" | cmp -s - "$H/slack/redraft/$name" && pass 'the request is the draft, loop and how lines' || fail "the request is the draft, loop and how lines ($(cat "$H/slack/redraft/$name" 2>&1))"
out2=$(R --draft "$H/drafts/$D" --loop N-48 --how "$(printf 'in Tagalog\n  and  warmer')" 2>/dev/null)
name2=${out2#requested }
[ "$name2" != "$name" ] && [ "$(requests | wc -l | tr -d ' ')" = 2 ] && printf 'draft: %s\nloop: N-48\nhow: shorter, and say Friday\n' "$H/drafts/$D" | cmp -s - "$H/slack/redraft/$name" && pass 'a second request never overwrites the first' || fail "a second request never overwrites the first ($out2; $(requests))"
[ "$(sed -n 3p "$H/slack/redraft/$name2" 2>/dev/null)" = 'how: in Tagalog and warmer' ] && pass 'how is made one line' || fail "how is made one line ($(cat "$H/slack/redraft/$name2" 2>&1))"
[ "$(requests | grep -cv '\.md$')" = 0 ] && pass 'no temp file is left' || fail "no temp file is left ($(requests))"

home rel
rel_cmd() { (cd "$H" && sh "$SCRIPT" --home "$H" --draft "drafts/$D" --loop N-7 --how shorter); }
out=$(rel_cmd 2>/dev/null)
[ "$(sed -n 1p "$H/slack/redraft/${out#requested }" 2>/dev/null)" = "draft: $(cd "$H" && pwd -P)/drafts/$D" ] && pass 'a relative draft path is written absolute' || fail "a relative draft path is written absolute ($out)"

home env
env_cmd() { JUEL_STAR_HOME="$H" sh "$SCRIPT" --draft "$H/drafts/$D" --loop N-9 --how shorter; }
out=$(env_cmd 2>/dev/null)
[ -f "$H/slack/redraft/${out#requested }" ] && pass 'without --home the folder is $JUEL_STAR_HOME' || fail "without --home the folder is \$JUEL_STAR_HOME ($out)"

home missing
exits 65 'a draft that is not there is refused' "no draft $H/drafts/nope.md" R --draft "$H/drafts/nope.md" --loop N-48 --how shorter
exits 65 'a draft that is a folder is refused' "no draft $H/drafts" R --draft "$H/drafts" --loop N-48 --how shorter
[ ! -e "$H/slack" ] && pass 'a refused request creates nothing' || fail "a refused request creates nothing ($(requests))"

home usage
exits 64 'no --draft is usage' "" R --loop N-48 --how shorter
exits 64 'no --loop is usage' "" R --draft "$H/drafts/$D" --how shorter
exits 64 'no --how is usage' "" R --draft "$H/drafts/$D" --loop N-48
exits 64 'a loop that is not N-<n> is usage' "" R --draft "$H/drafts/$D" --loop 48 --how shorter
exits 64 'a bare N- is usage' "" R --draft "$H/drafts/$D" --loop N- --how shorter
exits 64 'a how of only whitespace is usage' "" R --draft "$H/drafts/$D" --loop N-48 --how "$(printf ' \n ')"
exits 64 'a draft path with a line break is usage' "" R --draft "$(printf '%s\nloop: N-1' "$H/drafts/$D")" --loop N-48 --how shorter
exits 64 'a flag without its value is usage' "" R --draft "$H/drafts/$D" --loop N-48 --how
exits 64 'an unknown flag is usage' "" R --draft "$H/drafts/$D" --loop N-48 --how shorter --now
exits 64 'a stray argument is usage' "" R --draft "$H/drafts/$D" --loop N-48 --how shorter extra
exits 64 'a folder that is not there is usage' "" sh "$SCRIPT" --home "$TMP/nowhere" --draft "$H/drafts/$D" --loop N-48 --how shorter
[ ! -e "$H/slack" ] && pass 'usage writes nothing' || fail "usage writes nothing ($(requests))"

[ "$fails" -eq 0 ] && echo 'all passed' || echo "$fails failed"
[ "$fails" -eq 0 ]
