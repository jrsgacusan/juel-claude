#!/bin/sh
# Runs skills/star/done-check.sh against a scratch STAR home and a stub gh.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/done-check.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL done-check.sh missing"; exit 1; }
H="$TMP/home"; mkdir -p "$H/reviews/app"
printf '{"project": {"name": "app"}}\n' > "$H/star.json"
HEAD=abc1234def5678901234567890123456789abcde
printf 'VERDICT item=ITEM-1 round=1 NOT-SAFE findings=1 head=%s\n' 0123456789012345678901234567890123456789 > "$H/reviews/app/ITEM-1-r1.md"
printf 'VERDICT item=ITEM-1 round=2 SAFE findings=0 head=%s\n' "$HEAD" > "$H/reviews/app/ITEM-1-r2.md"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
[ -f "$STUB_DIR/gh-fail" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
cat "$STUB_DIR/pr.json"
EOF
chmod +x "$TMP/bin/gh"
pr() { printf '{"author":{"login":"me"},"headRefOid":"%s","comments":[%s]}\n' "$1" "$2" > "$TMP/pr.json"; }
PASSC="{\"author\":{\"login\":\"me\"},\"body\":\"Codex gate: PASS (head $HEAD, round 2, gpt-6-astra xhigh)\"}"
D() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" sh "$SCRIPT" --home "$H" "$@"; }
t() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got: $3)"; fi; }

pr "$HEAD" "$PASSC"
t "a SAFE newest review, the PR's head and its PASS is OK" "OK" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
t "a short head is enough when it is the start of the real one" "OK" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head abc1234)"
pr "ffff1234def5678901234567890123456789abcde" "$PASSC"
t "another PR head is a mismatch" "MISMATCH head: the PR's head is ffff123, the report says abc1234" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
pr "$HEAD" ""
t "no PASS comment is a mismatch" "MISMATCH pass: no codex PASS on the PR for abc1234" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
pr "$HEAD" "{\"author\":{\"login\":\"someone\"},\"body\":\"Codex gate: PASS (head $HEAD, round 2, gpt-6-astra xhigh)\"}"
t "a PASS from someone else does not count" "MISMATCH pass: no codex PASS on the PR for abc1234" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
pr "$HEAD" "$PASSC"
mv "$H/reviews/app/ITEM-1-r2.md" "$TMP/r2.keep"
printf 'VERDICT item=ITEM-1 round=2 SAFE findings=0 head=%s\n' fff1234def5678901234567890123456789abcde > "$H/reviews/app/ITEM-1-r2.md"
out=$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")
case "$out" in "MISMATCH review: head: "*) pass "a review of another commit is a mismatch" ;; *) fail "stale review ($out)" ;; esac
mv "$TMP/r2.keep" "$H/reviews/app/ITEM-1-r2.md"
printf 'VERDICT item=ITEM-1 round=3 NOT-SAFE findings=2 head=%s\n' "$HEAD" > "$H/reviews/app/ITEM-1-r3.md"
out=$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")
case "$out" in "MISMATCH review: verdict: "*) pass "the newest review decides, and NOT-SAFE is a mismatch" ;; *) fail "newest review ($out)" ;; esac
rm -f "$H/reviews/app/ITEM-1-r3.md"
t "an item with no review is a mismatch" "MISMATCH review: no review for ITEM-2 in $H/reviews/app" "$(D ITEM-2 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
touch "$TMP/gh-fail"
t "gh failing is pending" "PENDING gh: HTTP 502: Bad Gateway" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
rm -f "$TMP/gh-fail"
D ITEM-1 --pr x >/dev/null 2>&1; [ $? -eq 64 ] && pass "no --head is 64" || fail "usage"
D ITEM-1 --pr x --head xyz >/dev/null 2>&1; [ $? -eq 64 ] && pass "a head that is not hex is 64" || fail "usage hex"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
