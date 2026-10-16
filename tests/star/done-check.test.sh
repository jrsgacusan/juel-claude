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
PASSC="{\"author\":{\"login\":\"me\"},\"body\":\"Codex gate: PASS (head $HEAD, round 2, gpt-6.1-sol xhigh)\"}"
D() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" sh "$SCRIPT" --home "$H" "$@"; }
t() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got: $3)"; fi; }

pr "$HEAD" "$PASSC"
t "a SAFE newest review, the PR's head and its PASS is OK" "OK" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
t "a short head is enough when it is the start of the real one" "OK" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head abc1234)"
pr "ffff1234def5678901234567890123456789abcde" "$PASSC"
t "another PR head is a mismatch" "MISMATCH head: the PR's head is ffff123, the report says abc1234" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
pr "$HEAD" ""
t "no PASS comment is a mismatch" "MISMATCH pass: no codex PASS on the PR for abc1234" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
pr "$HEAD" "{\"author\":{\"login\":\"someone\"},\"body\":\"Codex gate: PASS (head $HEAD, round 2, gpt-6.1-sol xhigh)\"}"
t "a PASS from someone else does not count" "MISMATCH pass: PASS posted by someone, not the PR's author" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
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
# #82: the owner's carried PASS of the newest round is proof
printf 'VERDICT item=ITEM-1 round=3 NOT-SAFE findings=2 head=%s\n' "$HEAD" > "$H/reviews/app/ITEM-1-r3.md"
printf 'CARRIED item=ITEM-1 round=3 head=%s from=ITEM-1-r3.md decision=N-4\nship it\nDeferred: the findings in ITEM-1-r3.md\n' "$HEAD" > "$H/reviews/app/ITEM-1-r3-carried.md"
pr "$HEAD" "$PASSC"
t "the newest round's carried PASS is proof (#82)" "OK" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
printf 'CARRIED item=ITEM-1 round=3 head=%s from=ITEM-1-r3.md decision=N-4\nship it\n' fff1234def5678901234567890123456789abcde > "$H/reviews/app/ITEM-1-r3-carried.md"
out=$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")
case "$out" in "MISMATCH review: head: "*) pass "a carried PASS of another head is a mismatch" ;; *) fail "carried head ($out)" ;; esac
mv "$H/reviews/app/ITEM-1-r3-carried.md" "$H/reviews/app/ITEM-1-r2-carried.md"
out=$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")
case "$out" in "MISMATCH review: verdict: "*) pass "a carried PASS of an older round does not stand in for the newest" ;; *) fail "older carried ($out)" ;; esac
rm -f "$H/reviews/app/ITEM-1-r3.md" "$H/reviews/app/ITEM-1-r2-carried.md"
t "an item with no review is a mismatch" "MISMATCH review: no review for ITEM-2 in $H/reviews/app" "$(D ITEM-2 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
touch "$TMP/gh-fail"
t "gh failing is pending" "PENDING gh: HTTP 502: Bad Gateway" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
rm -f "$TMP/gh-fail"
D ITEM-1 --pr x >/dev/null 2>&1; [ $? -eq 64 ] && pass "no --head is 64" || fail "usage"
D ITEM-1 --pr x --head xyz >/dev/null 2>&1; [ $? -eq 64 ] && pass "a head that is not hex is 64" || fail "usage hex"
# lane a: #110 a SAFE review of an earlier head counts when carry-check.sh carries it to the PR's head
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$TMP/repo"; mkdir -p "$R"
g() { git -C "$R" "$@"; }
s7() { printf '%.7s' "$1"; }
g init -q -b main
printf '1\n2\n3\n4\n5\n' > "$R/app.txt"; printf 'x\n' > "$R/other.txt"
g add . && g commit -qm base
g checkout -qb feat; printf '1 feat\n2\n3\n4\n5\n' > "$R/app.txt"; g commit -qam feature; GATED=$(g rev-parse HEAD)
H2="$TMP/home2"; mkdir -p "$H2/reviews/app"
printf '{"project": {"name": "app", "repo": "%s"}}\n' "$R" > "$H2/star.json"
printf 'VERDICT item=ITEM-3 round=1 SAFE findings=0 head=%s\n' "$GATED" > "$H2/reviews/app/ITEM-3-r1.md"
prb() { printf '{"author":{"login":"me"},"baseRefName":"main","headRefOid":"%s","comments":[{"author":{"login":"me"},"body":"Codex gate: PASS (head %s, carried from %s)"}]}\n' "$1" "$1" "$GATED" > "$TMP/pr.json"; }
D2() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" sh "$SCRIPT" --home "$H2" "$@"; }
# Review Focus 1: base changes only to a file the branch never touched carry, so done-check passes it
g checkout -q main; printf 'y\n' > "$R/other.txt"; g commit -qam "main moves"; g update-ref refs/remotes/origin/main main
g checkout -q feat; g merge -q --no-edit origin/main; M1=$(g rev-parse HEAD)
prb "$M1"
t "#110 a SAFE review carried across a merge that touched no branch file is OK" "OK" "$(D2 ITEM-3 --pr https://github.com/o/r/pull/7 --head "$M1")"
# Review Focus 1: a clean merge whose base side changed a file the branch changed is not carried
g checkout -q main; printf '1\n2\n3\n4\n5 main\n' > "$R/app.txt"; g commit -qam "main app"; g update-ref refs/remotes/origin/main main
g checkout -q feat; g merge -q --no-edit origin/main; M2=$(g rev-parse HEAD)
prb "$M2"
t "#110 a SAFE review is not carried across a merge into a branch file" "MISMATCH review: not carried: $(s7 "$M2") brings base changes to app.txt, a file this branch changes: the gate reviews the merge" "$(D2 ITEM-3 --pr https://github.com/o/r/pull/7 --head "$M2")"
# the remote is found as codex-gate.sh post-pass finds it
g update-ref -d refs/remotes/origin/main
t "#110 no remote-tracking branch for the base is not carried" "MISMATCH review: not carried: no single remote-tracking branch for the base main (found: none)" "$(D2 ITEM-3 --pr https://github.com/o/r/pull/7 --head "$M2")"
g update-ref refs/remotes/origin/main main
# a PR head the repo does not have
NOPE=1234567890123456789012345678901234567890
prb "$NOPE"
t "#110 a head git does not know is not carried, and says why" "MISMATCH review: not carried: carry-check failed: carry-check.sh: --head: git knows no commit $NOPE" "$(D2 ITEM-3 --pr https://github.com/o/r/pull/7 --head "$NOPE")"
# a NOT-SAFE review of an earlier head is never carried
printf 'VERDICT item=ITEM-3 round=1 NOT-SAFE findings=1 head=%s\n' "$GATED" > "$H2/reviews/app/ITEM-3-r1.md"
prb "$M1"
out=$(D2 ITEM-3 --pr https://github.com/o/r/pull/7 --head "$M1")
case "$out" in "MISMATCH review: verdict: "*) pass "#110 a NOT-SAFE review is never carried" ;; *) fail "#110 NOT-SAFE carried ($out)" ;; esac

# #137: a receipt by another login is named
pr "$HEAD" "{\"author\":{\"login\":\"a1\"},\"body\":\"Codex gate: PASS (head $HEAD, round 2, m e)\"},{\"author\":{\"login\":\"a2\"},\"body\":\"Codex gate: PASS (head $HEAD, round 2, m e)\"},{\"author\":{\"login\":\"a1\"},\"body\":\"Codex gate: PASS (head $HEAD, round 2, m e)\"}"
t "#137 receipts by two other logins name both, once each" "MISMATCH pass: PASS posted by a1, a2, not the PR's author" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
pr "$HEAD" "{\"author\":{\"login\":\"a1\"},\"body\":\"Codex gate: PASS (head fff1234def5678901234567890123456789abcde, round 1, m e)\"}"
t "#137 a receipt by another login for another head is no receipt at all" "MISMATCH pass: no codex PASS on the PR for abc1234" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
pr "$HEAD" "$PASSC"

printf '{"author":null,"headRefOid":"%s","comments":[{"author":null,"body":"Codex gate: PASS (head %s, round 2, m e)"}]}\n' "$HEAD" "$HEAD" > "$TMP/pr.json"
t "#137 an empty login is never the author's receipt" "MISMATCH pass: no codex PASS on the PR for abc1234" "$(D ITEM-1 --pr https://github.com/o/r/pull/5 --head "$HEAD")"
pr "$HEAD" "$PASSC"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
