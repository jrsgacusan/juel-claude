#!/bin/sh
# Runs skills/star/pr-verify.sh against a stub gh that prints one fixture.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/pr-verify.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
[ -f "$SCRIPT" ] || { echo "FAIL pr-verify.sh missing"; exit 1; }
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
[ "${STUB_FAIL:-}" = 1 ] && { echo "${STUB_ERR:-HTTP 502}" >&2; exit 1; }
if [ "$1" = api ]; then
  case "$2" in
    *"/rules/branches/"*) if [ -n "${STUB_RULES:-}" ]; then cat "$STUB_RULES"; else echo '[]'; fi ;;
    *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  esac
  exit 0
fi
cat "$STUB_JSON"
EOF
chmod +x "$TMP/bin/gh"; ln -s "$(command -v python3)" "$TMP/bin/python3"
OK='"state":"OPEN","isDraft":false,"headRefOid":"abc1234def","mergeable":"MERGEABLE","mergeCommit":null'
APPROVED='"reviewDecision":"APPROVED","reviews":[{"author":{"login":"ezra"},"state":"APPROVED","submittedAt":"2026-10-02T00:00:00Z","commit":{"oid":"abc1234def"}}]'
GREEN='"statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"deploy","state":"SUCCESS"}]'
# t <name> <expected line> <json body> [extra args]
t() {
  printf '{%s}\n' "$3" > "$TMP/pr.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" sh "$SCRIPT" 5 --head abc1234 ${4:-})
  if [ "$out" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got: $out)"; fails=$((fails + 1)); fi
}
t "approved and green passes" "PASS" "$OK,$APPROVED,$GREEN"
t "no checks passes" "PASS" "$OK,$APPROVED,\"statusCheckRollup\":[]"
t "head moved" "MOVED ffff999" "\"state\":\"OPEN\",\"isDraft\":false,\"headRefOid\":\"ffff999\",\"mergeable\":\"MERGEABLE\",$APPROVED,$GREEN"
t "merged" "MERGED 9e8d7c6" "\"state\":\"MERGED\",\"isDraft\":false,\"headRefOid\":\"abc1234def\",\"mergeable\":\"UNKNOWN\",\"mergeCommit\":{\"oid\":\"9e8d7c6\"},$APPROVED,$GREEN"
t "closed" "FAIL closed" "\"state\":\"CLOSED\",\"isDraft\":false,\"headRefOid\":\"abc1234def\",\"mergeable\":\"UNKNOWN\",$APPROVED,$GREEN"
t "draft" "FAIL draft" "\"state\":\"OPEN\",\"isDraft\":true,\"headRefOid\":\"abc1234def\",\"mergeable\":\"MERGEABLE\",$APPROVED,$GREEN"
t "review required" "FAIL approval: REVIEW_REQUIRED" "$OK,\"reviewDecision\":\"REVIEW_REQUIRED\",\"reviews\":[],\"commits\":[],$GREEN"
t "empty decision with an approval of the current head" "PASS" "$OK,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\",\"commit\":{\"oid\":\"abc1234def\"}}],$GREEN"
# The approval is newer than the head's commit date (a commit made earlier, pushed later), but it is for another commit.
t "empty decision with an approval of an older head" "FAIL approval: none on the current head" "$OK,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\",\"commit\":{\"oid\":\"0ld0000aaa\"}}],\"commits\":[{\"committedDate\":\"2026-10-01T00:00:00Z\"}],$GREEN"
t "an approval with no commit on record does not count" "FAIL approval: none on the current head" "$OK,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\"}],$GREEN"
t "two deleted accounts are two reviewers" "FAIL approval: changes requested by a deleted account" "$OK,\"reviewDecision\":\"\",\"reviews\":[{\"id\":\"R1\",\"author\":null,\"state\":\"CHANGES_REQUESTED\",\"submittedAt\":\"2026-10-02T00:00:00Z\"},{\"id\":\"R2\",\"author\":null,\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-03T00:00:00Z\",\"commit\":{\"oid\":\"abc1234def\"}}],$GREEN"
t "empty decision with changes requested" "FAIL approval: changes requested by ezra" "$OK,\"reviewDecision\":null,\"reviews\":[{\"author\":{\"login\":\"jp\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\",\"commit\":{\"oid\":\"abc1234def\"}},{\"author\":{\"login\":\"ezra\"},\"state\":\"CHANGES_REQUESTED\",\"submittedAt\":\"2026-10-03T00:00:00Z\"}],\"commits\":[{\"committedDate\":\"2026-10-01T00:00:00Z\"}],$GREEN"
t "failed check" "FAIL checks: ci" "$OK,$APPROVED,\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"name\":\"ci\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}]"
t "cancelled check is not a pass" "FAIL checks: ci" "$OK,$APPROVED,\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"name\":\"ci\",\"status\":\"COMPLETED\",\"conclusion\":\"CANCELLED\"}]"
t "running check" "PENDING checks: ci" "$OK,$APPROVED,\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"name\":\"ci\",\"status\":\"IN_PROGRESS\",\"conclusion\":\"\"}]"
t "pending commit status" "PENDING checks: deploy" "$OK,$APPROVED,\"statusCheckRollup\":[{\"__typename\":\"StatusContext\",\"context\":\"deploy\",\"state\":\"PENDING\"}]"
t "unknown mergeable" "PENDING mergeable" "\"state\":\"OPEN\",\"isDraft\":false,\"headRefOid\":\"abc1234def\",\"mergeable\":\"UNKNOWN\",$APPROVED,$GREEN"
t "conflicts" "FAIL conflicts" "\"state\":\"OPEN\",\"isDraft\":false,\"headRefOid\":\"abc1234def\",\"mergeable\":\"CONFLICTING\",$APPROVED,$GREEN"
t "a recorded head longer than the real one is not a match" "MOVED abc1234def" "$OK,$APPROVED,$GREEN" "--head abc1234defff"
t "a missing head is pending" "PENDING gh: no head" "\"state\":\"OPEN\",\"isDraft\":false,\"mergeable\":\"MERGEABLE\",$APPROVED,$GREEN"
printf '{%s}\n' "$OK,$APPROVED,$GREEN" > "$TMP/pr.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" sh "$SCRIPT" 5 --head abc12)
[ "$out" = "FAIL bad head: abc12" ] && echo "ok   a head shorter than 7 is refused, not MOVED" || { echo "FAIL short head ($out)"; fails=$((fails + 1)); }

out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_FAIL=1 STUB_JSON=/dev/null sh "$SCRIPT" 5 --head abc1234)
case "$out" in "PENDING gh: "*) echo "ok   gh failure is pending, not a verdict" ;; *) echo "FAIL gh failure ($out)"; fails=$((fails + 1)) ;; esac
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && echo "ok   one line only" || { echo "FAIL one line only"; fails=$((fails + 1)); }

t "an upper-case recorded head still matches" "PASS" "$OK,$APPROVED,$GREEN" "--head ABC1234"
t "check runs that are not a list are unreadable, never a pass" "PENDING gh: unreadable output" "$OK,$APPROVED,\"statusCheckRollup\":{\"x\":1}"
many=$(python3 -c 'import json; print(json.dumps([{"__typename":"CheckRun","name":"c%d" % i,"status":"IN_PROGRESS","conclusion":""} for i in range(1, 9)]))')
t "a long list of checks is cut short" "PENDING checks: c1, c2, c3, c4, c5 (+3 more)" "$OK,$APPROVED,\"statusCheckRollup\":$many"
for body in '[]' 'null' '"oops"' '502'; do
  printf '%s\n' "$body" > "$TMP/pr.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" sh "$SCRIPT" 5 --head abc1234 2>&1)
  [ "$out" = "PENDING gh: unreadable output" ] && echo "ok   gh printing $body is pending" || { echo "FAIL gh printing $body ($out)"; fails=$((fails + 1)); }
done
printf '{%s}\n' "$OK,$APPROVED,$GREEN" > "$TMP/pr.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STAR_GH_TIMEOUT=abc STUB_JSON="$TMP/pr.json" sh "$SCRIPT" 5 --head abc1234 2>&1)
[ "$out" = "PASS" ] && echo "ok   a bad STAR_GH_TIMEOUT falls back to the default" || { echo "FAIL bad STAR_GH_TIMEOUT ($out)"; fails=$((fails + 1)); }

# Second stress pass
t "a PR with no state is unreadable, never a pass" "PENDING gh: unreadable output" "\"state\":null,\"isDraft\":false,\"headRefOid\":\"abc1234def\",\"mergeable\":\"MERGEABLE\",\"mergeCommit\":null,$APPROVED,$GREEN"
t "a lower-case merged state is still merged" "MERGED 9e8d7c6" "\"state\":\"merged\",\"isDraft\":false,\"headRefOid\":\"abc1234def\",\"mergeable\":\"UNKNOWN\",\"mergeCommit\":{\"oid\":\"9e8d7c6\"},$APPROVED,$GREEN"
t "a review decision that is not text is unreadable" "PENDING gh: unreadable output" "$OK,\"reviewDecision\":[\"APPROVED\"],\"reviews\":[],$GREEN"

# Final pass
t "a review rule satisfied by an approval of an earlier commit passes, and says so" "PASS approval is on an earlier commit" "$OK,\"reviewDecision\":\"APPROVED\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\",\"commit\":{\"oid\":\"0ld0000aaa\"}}],$GREEN"
t "required checks that have not reported block the pass" "PENDING merge state: blocked (a required check or review has not reported)" "$OK,$APPROVED,\"mergeStateStatus\":\"BLOCKED\",\"statusCheckRollup\":[]"
t "a branch behind its base is pending, not a pass" "PENDING merge state: behind the base branch" "$OK,$APPROVED,\"mergeStateStatus\":\"BEHIND\",$GREEN"
t "a clean merge state passes" "PASS" "$OK,$APPROVED,\"mergeStateStatus\":\"CLEAN\",$GREEN"
for bad in '"headRefOid":7' '"mergeCommit":"x"' '"reviews":[{"author":"x","state":"APPROVED"}]' '"statusCheckRollup":[{"conclusion":7}]'; do
  printf '{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"","headRefOid":"abc1234def","reviews":[],"statusCheckRollup":[],%s}\n' "$bad" > "$TMP/pr.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" sh "$SCRIPT" 5 --head abc1234 2>&1); rc=$?
  case "$out" in PASS*) echo "FAIL odd shape $bad printed PASS"; fails=$((fails + 1)) ;; *) [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && echo "ok   odd shape $bad is one line, never a crash" || { echo "FAIL odd shape $bad (rc=$rc: $(printf '%s' "$out" | head -1))"; fails=$((fails + 1)); } ;; esac
done

# an explicit zero in the base branch's rules (#27)
ZERO="$TMP/zero.json"; printf '[{"type":"pull_request","parameters":{"required_approving_review_count":0}}]\n' > "$ZERO"
BAD="$TMP/bad.json"; printf '{"x":1}\n' > "$BAD"
BASE='"url":"https://github.com/o/r/pull/5","baseRefName":"main"'
tz() {
  printf '{%s}\n' "$3" > "$TMP/pr.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" STUB_RULES="${RULES:-$ZERO}" sh "$SCRIPT" 5 --head abc1234)
  if [ "$out" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got: $out)"; fails=$((fails + 1)); fi
}
APPROVED_HEAD='"reviews":[{"author":{"login":"ezra"},"state":"APPROVED","submittedAt":"2026-10-02T00:00:00Z","commit":{"oid":"abc1234def"}}]'
tz "zero required: green with no approval passes" "PASS no approval required" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN"
tz "zero required: an approval on the head is a plain pass" "PASS" "$OK,$BASE,\"reviewDecision\":\"\",$APPROVED_HEAD,$GREEN"
tz "zero required: changes requested still fail" "FAIL approval: changes requested by ezra" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"CHANGES_REQUESTED\",\"submittedAt\":\"2026-10-02T00:00:00Z\"}],$GREEN"
tz "zero required: a failing check still fails" "FAIL checks: ci" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"name\":\"ci\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}]"
tz "zero required: a blocked merge state is still pending" "PENDING merge state: blocked (a required check or review has not reported)" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN,\"mergeStateStatus\":\"BLOCKED\""
RULES="$BAD" tz "unreadable rules keep today's rule" "FAIL approval: none on the current head" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN"
t "no review rule at all keeps today's rule" "FAIL approval: none on the current head" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN"

# a repository gh cannot see (#27)
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_FAIL=1 STUB_ERR="GraphQL: Could not resolve to a Repository with the name 'o/r'. (repository)" STUB_JSON=/dev/null sh "$SCRIPT" https://github.com/o/r/pull/5 --head abc1234)
[ "$out" = "PENDING gh cannot see o/r: export GH_TOKEN for this repository" ] && echo "ok   a repository gh cannot see says how to fix it" || { echo "FAIL cannot see ($out)"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
