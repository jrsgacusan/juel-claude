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
[ "${STUB_FAIL:-}" = 1 ] && { echo "HTTP 502" >&2; exit 1; }
cat "$STUB_JSON"
EOF
chmod +x "$TMP/bin/gh"; ln -s "$(command -v python3)" "$TMP/bin/python3"
OK='"state":"OPEN","isDraft":false,"headRefOid":"abc1234def","mergeable":"MERGEABLE","mergeCommit":null'
APPROVED='"reviewDecision":"APPROVED","reviews":[],"commits":[{"committedDate":"2026-10-01T00:00:00Z"}]'
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
t "empty decision with approval after the last commit" "PASS" "$OK,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\"}],\"commits\":[{\"committedDate\":\"2026-10-01T00:00:00Z\"}],$GREEN"
t "empty decision with a stale approval" "FAIL approval: none after the last commit" "$OK,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-09-30T00:00:00Z\"}],\"commits\":[{\"committedDate\":\"2026-10-01T00:00:00Z\"}],$GREEN"
t "empty decision with changes requested" "FAIL approval: changes requested by ezra" "$OK,\"reviewDecision\":null,\"reviews\":[{\"author\":{\"login\":\"jp\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\"},{\"author\":{\"login\":\"ezra\"},\"state\":\"CHANGES_REQUESTED\",\"submittedAt\":\"2026-10-03T00:00:00Z\"}],\"commits\":[{\"committedDate\":\"2026-10-01T00:00:00Z\"}],$GREEN"
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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
