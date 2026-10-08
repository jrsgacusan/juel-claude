#!/bin/sh
# Runs skills/star/ids.sh against a scratch STAR folder.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/ids.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL ids.sh missing"; exit 1; }
H="$TMP/home"; mkdir -p "$H"
I() { sh "$SCRIPT" --home "$H" "$@"; }

[ "$(I reserve docs/decisions.md --item A --count 2 --floor 40 | tr '\n' ' ')" = "41 42 " ] && pass "the first ids follow the floor" || fail "first reserve"
[ "$(I reserve docs/decisions.md --item B --count 1 --floor 40)" = "43" ] && pass "a floor below next takes next" || fail "next wins"
[ "$(I reserve docs/decisions.md --item C --count 1 --floor 50)" = "51" ] && pass "a floor above next wins" || fail "floor wins"
[ "$(I reserve db/migrations --item A --count 1 --floor 0)" = "1" ] && pass "each sequence counts on its own" || fail "second sequence"
[ "$(I list --item A | tr '\n' ' ')" = "db/migrations A 1 docs/decisions.md A 41 docs/decisions.md A 42 " ] && pass "list --item shows one item's ids" || fail "list item ($(I list --item A))"
[ "$(I list | wc -l | tr -d ' ')" = "5" ] && pass "list shows every reservation" || fail "list all"

# five workers at the same instant never share an id
for n in 1 2 3 4 5; do I reserve race --item "P$n" --count 3 --floor 0 > "$TMP/race$n" & done; wait
[ "$(cat "$TMP"/race* | sort -n | uniq | wc -l | tr -d ' ')" = "15" ] && pass "parallel reservations never collide" || fail "race ($(cat "$TMP"/race* | tr '\n' ' '))"

I reserve x --item A --count 0 --floor 0 >/dev/null 2>&1; [ $? -eq 64 ] && pass "a count of 0 is 64" || fail "count 0"
I reserve x --item A --count 1 >/dev/null 2>&1; [ $? -eq 64 ] && pass "a missing --floor is 64" || fail "no floor"
I reserve x --item 'bad name' --count 1 --floor 0 >/dev/null 2>&1; [ $? -eq 64 ] && pass "an item name with a space is 64" || fail "item name"
I nope >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown command is 64" || fail "unknown command"
sh "$SCRIPT" --home "$TMP/missing" list >/dev/null 2>&1; [ $? -eq 2 ] && pass "a missing STAR folder is 2" || fail "no home"
printf 'not json' > "$H/ids.json"
I list >/dev/null 2>&1; [ $? -eq 2 ] && pass "a damaged ids.json is 2, never overwritten" || fail "bad json"
[ "$(cat "$H/ids.json")" = "not json" ] && pass "the damaged file is left as it was" || fail "bad json rewritten"
for bad in '{"sequences":{"d":5}}' '{"sequences":{"d":{"next":"abc","reserved":[]}}}'; do
  printf '%s' "$bad" > "$H/ids.json"
  err=$(I list 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 2 ] && case "$err" in *"is not an ids ledger: fix or remove it") true ;; *) false ;; esac \
    && pass "list refuses the malformed ledger $bad with 2" || fail "list $bad ($rc: $err)"
  I reserve d --item A --count 1 --floor 0 >/dev/null 2>&1; [ $? -eq 2 ] && pass "reserve refuses the malformed ledger $bad with 2" || fail "reserve $bad"
  [ "$(cat "$H/ids.json")" = "$bad" ] && pass "the malformed ledger $bad is left as it was" || fail "malformed ledger rewritten ($bad)"
done

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
