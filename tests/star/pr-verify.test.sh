#!/bin/sh
# Runs skills/star/pr-verify.sh against a stub gh that prints one fixture.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/pr-verify.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
# the merge gate reads ownerApproval from STAR's folder (#124): never the owner's real one from a test
mkdir -p "$TMP/nohome"; export JUEL_STAR_HOME="$TMP/nohome"
[ -f "$SCRIPT" ] || { echo "FAIL pr-verify.sh missing"; exit 1; }
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
[ "${STUB_FAIL:-}" = 1 ] && { echo "${STUB_ERR:-HTTP 502}" >&2; exit 1; }
if [ "$1" = api ]; then
  case "$2" in
    graphql) if [ -n "${STUB_THREADS:-}" ]; then cat "$STUB_THREADS"; else echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}'; fi; exit "${STUB_THREADS_RC:-0}" ;;
    *"/git/ref/heads/"*)
      if [ -n "${STUB_TIP:-}" ]; then printf '{"ref":"refs/heads/x","object":{"sha":"%s"}}\n' "$STUB_TIP"; else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi ;;
    *"/rules/branches/"*)
      [ -n "${STUB_RULES_ERR:-}" ] && { echo "$STUB_RULES_ERR" >&2; exit 1; }
      if [ -n "${STUB_RULES:-}" ]; then cat "$STUB_RULES"; else echo '[]'; fi ;;
    *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  esac
  exit 0
fi
if [ -n "${STUB_SEQ:-}" ]; then
  n=$(($(cat "$STUB_SEQ/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$STUB_SEQ/n"
  if [ -f "$STUB_SEQ/$n.json" ]; then cat "$STUB_SEQ/$n.json"; else cat "$STUB_SEQ/last.json"; fi
  exit 0
fi
cat "$STUB_JSON"
EOF
chmod +x "$TMP/bin/gh"; ln -s "$(command -v python3)" "$TMP/bin/python3"
OK='"state":"OPEN","isDraft":false,"headRefOid":"abc1234def","mergeable":"MERGEABLE","mergeCommit":null'
APPROVED='"reviewDecision":"APPROVED","reviews":[{"author":{"login":"ezra"},"state":"APPROVED","submittedAt":"2026-10-02T00:00:00Z","commit":{"oid":"abc1234def"}}]'
GREEN='"statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"deploy","state":"SUCCESS"}]'
# what gh prints for url,baseRefName: review-rule.sh is asked about o/r main
BASE='"url":"https://github.com/o/r/pull/5","baseRefName":"main"'
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
t "empty decision with an approval of an older head" "FAIL approval: none on the current head" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\",\"commit\":{\"oid\":\"0ld0000aaa\"}}],\"commits\":[{\"committedDate\":\"2026-10-01T00:00:00Z\"}],$GREEN"
t "an approval with no commit on record does not count" "FAIL approval: none on the current head" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\"}],$GREEN"
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
tz() {
  printf '{%s}\n' "$3" > "$TMP/pr.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" STUB_RULES="${RULES:-$ZERO}" STUB_RULES_ERR="${RULES_ERR:-}" sh "$SCRIPT" 5 --head abc1234)
  if [ "$out" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got: $out)"; fails=$((fails + 1)); fi
}
APPROVED_HEAD='"reviews":[{"author":{"login":"ezra"},"state":"APPROVED","submittedAt":"2026-10-02T00:00:00Z","commit":{"oid":"abc1234def"}}]'
tz "zero required: green with no approval passes" "PASS no approval required" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN"
tz "zero required: an approval on the head is a plain pass" "PASS" "$OK,$BASE,\"reviewDecision\":\"\",$APPROVED_HEAD,$GREEN"
tz "zero required: changes requested still fail" "FAIL approval: changes requested by ezra" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"CHANGES_REQUESTED\",\"submittedAt\":\"2026-10-02T00:00:00Z\"}],$GREEN"
tz "zero required: a failing check still fails" "FAIL checks: ci" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"name\":\"ci\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}]"
tz "zero required: a blocked merge state is still pending" "PENDING merge state: blocked (a required check or review has not reported)" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN,\"mergeStateStatus\":\"BLOCKED\""
RULES="$BAD"
tz "unreadable rules are pending, never a wrong FAIL" "PENDING review rule: unreadable rules" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN"
unset RULES
RULES_ERR="gh: Not Found (HTTP 404)"
tz "rules gh cannot see say how to fix it" "PENDING gh cannot see o/r: export GH_TOKEN for this repository" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN"
RULES_ERR="gh: Server Error (HTTP 502)"
tz "a gh error on the rules is pending" "PENDING review rule: gh: Server Error (HTTP 502)" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN"
tz "an unreadable rule does not matter once the head is approved" "PASS" "$OK,$BASE,\"reviewDecision\":\"\",$APPROVED_HEAD,$GREEN"
tz "an unreadable rule never hides changes requested" "FAIL approval: changes requested by ezra" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"CHANGES_REQUESTED\",\"submittedAt\":\"2026-10-02T00:00:00Z\"}],$GREEN"
unset RULES_ERR
t "a rule review-rule.sh cannot be asked for is pending" "PENDING review rule: unreadable" "$OK,\"reviewDecision\":\"\",\"reviews\":[],$GREEN"
t "no review rule at all keeps today's rule" "FAIL approval: none on the current head" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN"
RULES="$TMP/one.json"; printf '[{"type":"pull_request","parameters":{"required_approving_review_count":1}}]\n' > "$RULES"
tz "a rule of one approval keeps today's rule" "FAIL approval: none on the current head" "$OK,$BASE,\"reviewDecision\":\"\",\"reviews\":[],$GREEN"
unset RULES

# a repository gh cannot see (#27)
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_FAIL=1 STUB_ERR="GraphQL: Could not resolve to a Repository with the name 'o/r'. (repository)" STUB_JSON=/dev/null sh "$SCRIPT" https://github.com/o/r/pull/5 --head abc1234)
[ "$out" = "PENDING gh cannot see o/r: export GH_TOKEN for this repository" ] && echo "ok   a repository gh cannot see says how to fix it" || { echo "FAIL cannot see ($out)"; fails=$((fails + 1)); }

# --merge-gate: STAR's merge gate. A hosted reviewer's review text is never read here.
AUTHOR='"author":{"login":"me"}'
PASSC='{"author":{"login":"me"},"body":"Codex gate: PASS (head abc1234def, round 2, gpt-6.1-sol xhigh)"}'
NOAPP='"reviewDecision":"","reviews":[]'
mg() { # mg <name> <expected> <json body> [extra args]
  printf '{%s}\n' "$3" > "$TMP/pr.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" STUB_THREADS="${THREADS:-}" STUB_THREADS_RC="${THREADS_RC:-0}" sh "$SCRIPT" 5 --head abc1234 --merge-gate ${4:-})
  if [ "$out" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got: $out)"; fails=$((fails + 1)); fi
}
# with a hosted reviewer: the babysit worker judged its review; the script asks for no approval
mg "hosted, PASS posted, green: PASS" "PASS hosted" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[$PASSC]" "--hosted"
mg "no codex PASS: FAIL" "FAIL no codex PASS for abc1234" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[]" "--hosted"
mg "a PASS by someone else does not count" "FAIL no codex PASS for abc1234 (posted by x, not the PR's author)" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[{\"author\":{\"login\":\"x\"},\"body\":\"Codex gate: PASS (head abc1234def, round 1, m e)\"}]" "--hosted"
printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"comments":{"nodes":[{"author":{"login":"greptile-apps"},"body":"The export ignores the filter."}]}}]}}}}}\n' > "$TMP/t1.json"
THREADS="$TMP/t1.json"
mg "a hosted reviewer's comment with no reply: FAIL" "FAIL 1 finding without a reply from the author" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[$PASSC]" "--hosted"
unset THREADS
printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"comments":{"nodes":[{"author":{"login":"greptile-apps"},"body":"Rename this."},{"author":{"login":"me"},"body":"Disposition: the name matches the API it wraps."}]}}]}}}}}\n' > "$TMP/t3.json"
THREADS="$TMP/t3.json"
mg "a hosted reviewer's comment the author answered: PASS" "PASS hosted" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[$PASSC]" "--hosted"
unset THREADS
printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"comments":{"nodes":[{"author":{"login":"ezra"},"body":"Please rename this."}]}}]}}}}}\n' > "$TMP/t2.json"
THREADS="$TMP/t2.json"
mg "an unanswered reviewer thread: FAIL" "FAIL 1 finding without a reply from the author" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[$PASSC]" "--hosted"
unset THREADS
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" sh "$SCRIPT" 5 --head abc1234 --hosted 2>/dev/null; echo "exit=$?")
[ "$out" = "exit=64" ] && echo "ok   --hosted alone exits 64" || { echo "FAIL --hosted alone ($out)"; fails=$((fails + 1)); }
# without a hosted reviewer: an approval on the head by someone other than the author, with write access
MEMBER_OK='"reviewDecision":"","reviews":[{"author":{"login":"ezra"},"authorAssociation":"MEMBER","state":"APPROVED","submittedAt":"2026-10-02T00:00:00Z","commit":{"oid":"abc1234def"}}]'
mg "no hosted reviewer, approved on the head: PASS" "PASS approved" "$OK,$BASE,$AUTHOR,$MEMBER_OK,$GREEN,\"comments\":[$PASSC]"
mg "an approval from someone without write access does not count" "PENDING approval: none on the current head from someone other than me" "$OK,$BASE,$AUTHOR,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"drive-by\"},\"authorAssociation\":\"CONTRIBUTOR\",\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\",\"commit\":{\"oid\":\"abc1234def\"}}],$GREEN,\"comments\":[$PASSC]"
mg "no hosted reviewer, no approval: PENDING" "PENDING approval: none on the current head from someone other than me" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[$PASSC]"
printf '{%s}\n' "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[$PASSC]" > "$TMP/pr.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" STUB_RULES="$ZERO" sh "$SCRIPT" 5 --head abc1234 --merge-gate)
[ "$out" = "PENDING approval: none on the current head from someone other than me" ] && echo "ok   an explicit zero rule does not waive STAR's approval" || { echo "FAIL zero rule in merge-gate mode ($out)"; fails=$((fails + 1)); }
mg "the author's own approval does not count" "PENDING approval: none on the current head from someone other than me" "$OK,$BASE,$AUTHOR,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"me\"},\"authorAssociation\":\"OWNER\",\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\",\"commit\":{\"oid\":\"abc1234def\"}}],$GREEN,\"comments\":[$PASSC]"
mg "changes requested still FAIL in merge-gate mode" "FAIL approval: changes requested by ezra" "$OK,$BASE,$AUTHOR,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"CHANGES_REQUESTED\",\"submittedAt\":\"2026-10-02T00:00:00Z\"}],$GREEN,\"comments\":[$PASSC]" "--hosted"
mg "a blocked merge state is PENDING in merge-gate mode" "PENDING merge state: blocked (a required check or review has not reported)" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"mergeStateStatus\":\"BLOCKED\",\"comments\":[$PASSC]" "--hosted"
# --hosted needs --merge-gate, and the script says so itself (not argparse's "unrecognized arguments")
err=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" sh "$SCRIPT" 5 --head abc1234 --hosted 2>&1 >/dev/null)
case "$err" in *"--hosted needs --merge-gate"*) echo "ok   --hosted alone says it needs --merge-gate" ;; *) echo "FAIL --hosted alone message (got: $err)"; fails=$((fails + 1)) ;; esac
# a hosted reviewer's review text is never read: whatever its markup says, the verdict is the same
HOSTED_TEXT='"reviewDecision":"","reviews":[{"author":{"login":"greptile-apps"},"authorAssociation":"NONE","state":"COMMENTED","submittedAt":"2026-10-02T00:00:00Z","commit":{"oid":"abc1234def"},"body":"<h3>Confidence Score: 1/5</h3> Do not merge. A markup nobody planned for."}]'
mg "a hosted reviewer's review text is never read" "PASS hosted" "$OK,$BASE,$AUTHOR,$HOSTED_TEXT,$GREEN,\"comments\":[$PASSC]" "--hosted"
# the gate is the head: a codex PASS or an approval for an earlier commit does not count
OLDPASS='{"author":{"login":"me"},"body":"Codex gate: PASS (head 0ld0000aaa, round 1, gpt-6.1-sol xhigh)"}'
mg "a codex PASS for an earlier head does not count" "FAIL no codex PASS for abc1234" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[$OLDPASS]" "--hosted"
mg "an approval of an earlier commit does not count" "PENDING approval: none on the current head from someone other than me" "$OK,$BASE,$AUTHOR,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"authorAssociation\":\"MEMBER\",\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-02T00:00:00Z\",\"commit\":{\"oid\":\"0ld0000aaa\"}}],$GREEN,\"comments\":[$PASSC]"
mg "logins are compared without a [bot] suffix" "PASS hosted" "$OK,$BASE,\"author\":{\"login\":\"ci[bot]\"},$NOAPP,$GREEN,\"comments\":[{\"author\":{\"login\":\"ci\"},\"body\":\"Codex gate: PASS (head abc1234def, round 1, m e)\"}]" "--hosted"
# review threads: only an unresolved one someone else opened counts, and only the author's own reply answers it
printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":true,"comments":{"nodes":[{"author":{"login":"ezra"},"body":"Old finding."}]}},{"isResolved":false,"comments":{"nodes":[{"author":{"login":"me"},"body":"A note to myself."}]}},{"isResolved":false,"comments":{"nodes":[{"author":{"login":"ezra"},"body":"Please rename this."}]}},{"isResolved":false,"comments":{"nodes":[{"author":{"login":"greptile-apps"},"body":"Handle the empty list."},{"author":{"login":"ezra"},"body":"Agreed."}]}}]}}}}}\n' > "$TMP/t5.json"
THREADS="$TMP/t5.json"
mg "resolved and own threads are skipped, a reply from someone else is no answer" "FAIL 2 findings without a reply from the author" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[$PASSC]" "--hosted"
unset THREADS
unreadable() { # unreadable <label> <what gh graphql printed>: a thread list that cannot be read is never "no findings"
  printf '%s\n' "$2" > "$TMP/t4.json"; THREADS="$TMP/t4.json"
  mg "review threads gh cannot read are pending ($1)" "PENDING gh: review threads unreadable" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[$PASSC]" "--hosted"
  unset THREADS
}
unreadable "not json" 'not json at all'
unreadable "no pull request" '{"data":{"repository":{"pullRequest":null}}}'
unreadable "errors only" '{"errors":[{"message":"boom"}]}'
# A-5: a partial answer is no answer: nodes that is not a list, or a gh that exits non-zero, never reads as "no findings"
unreadable "nodes null beside errors" '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":null}}}},"errors":[{"message":"Something went wrong"}]}'
unreadable "nodes an object" '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":{"x":1}}}}}}'
unreadable "nodes a string" '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":"none"}}}}}'
THREADS_RC=1
unreadable "an empty list, but gh exited 1" '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}'
unreadable "a thread nobody answered, but gh exited 1" '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"comments":{"nodes":[{"author":{"login":"ezra"},"body":"Rename this."}]}}]}}}}}'
unset THREADS_RC
# what the script asks gh for: a wrapper logs every call and hands it to the stub above
mkdir -p "$TMP/bin2"
cat > "$TMP/bin2/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_LOG"
exec "$GH_REAL" "$@"
EOF
chmod +x "$TMP/bin2/gh"
logged() { # logged <script args>: prints the verdict; every gh call lands in $TMP/gh.log
  rm -f "$TMP/gh.log"
  PATH="$TMP/bin2:$TMP/bin:/usr/bin:/bin" GH_LOG="$TMP/gh.log" GH_REAL="$TMP/bin/gh" STUB_JSON="$TMP/pr.json" sh "$SCRIPT" "$@"
}
printf '{%s}\n' "$OK,\"url\":\"https://github.com/o/r/pull/7\",\"baseRefName\":\"main\",$AUTHOR,$NOAPP,$GREEN,\"comments\":[$PASSC]" > "$TMP/pr.json"
out=$(logged https://github.com/o/r/pull/7 --head abc1234 --merge-gate --hosted)
[ "$out" = "PASS hosted" ] && echo "ok   merge-gate mode takes the PR as a URL" || { echo "FAIL merge-gate with a URL (got: $out)"; fails=$((fails + 1)); }
grep '^pr view ' "$TMP/gh.log" | grep -q ',author,comments$' && echo "ok   merge-gate mode asks gh for the author and the comments" || { echo "FAIL merge-gate fields ($(grep '^pr view ' "$TMP/gh.log"))"; fails=$((fails + 1)); }
grep '^api graphql ' "$TMP/gh.log" | grep -q ' owner=o .*name=r .*number=7$' && echo "ok   the thread query gets the owner, the name and the number" || { echo "FAIL thread query args ($(grep '^api graphql ' "$TMP/gh.log" | cut -c1-30))"; fails=$((fails + 1)); }
grep '^api graphql ' "$TMP/gh.log" | grep -q -- ' -f owner=o -f name=r -F number=7$' && echo "ok   the owner and the name go as strings (-f), only the number as a number (-F)" || { echo "FAIL thread query field types ($(grep '^api graphql ' "$TMP/gh.log" | sed 's/.*query=[^ ]* //'))"; fails=$((fails + 1)); }
printf '{%s}\n' "$OK,$BASE,$APPROVED,$GREEN" > "$TMP/pr.json"
out=$(logged 5 --head abc1234)
[ "$out" = "PASS" ] && ! grep -q -E 'author|comments|^api graphql ' "$TMP/gh.log" && echo "ok   without --merge-gate it asks gh for no author, no comments and no threads" || { echo "FAIL a plain run asks for more than v1 (got: $out)"; fails=$((fails + 1)); }

# #62: GitHub's head lag right after a push is waited out, not read as MOVED
SEQ="$TMP/seq"; LAGGED='"state":"OPEN","isDraft":false,"headRefOid":"ffff999000000000000000000000000000000000","headRefName":"feat/x","url":"https://github.com/o/r/pull/5","mergeable":"MERGEABLE","mergeCommit":null'
lag() { # lag <name> <expected> <branch tip> <lagging views, or all>
  rm -rf "$SEQ"; mkdir -p "$SEQ"
  if [ "$4" = all ]; then printf '{%s}\n' "$LAGGED,$APPROVED,$GREEN" > "$SEQ/last.json"
  else i=1; while [ "$i" -le "$4" ]; do printf '{%s}\n' "$LAGGED,$APPROVED,$GREEN" > "$SEQ/$i.json"; i=$((i + 1)); done
       printf '{%s}\n' "$OK,\"headRefName\":\"feat/x\",\"url\":\"https://github.com/o/r/pull/5\",$APPROVED,$GREEN" > "$SEQ/last.json"; fi
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_SEQ="$SEQ" STUB_TIP="$3" PR_VERIFY_SLEEP=0 sh "$SCRIPT" 5 --head abc1234)
  if [ "$out" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got: $out)"; fails=$((fails + 1)); fi
}
lag "a PR that still shows the old head while its branch is at the new one is waited out (#62)" "PASS" abc1234def 2
[ "$(cat "$SEQ/n")" = 3 ] && echo "ok   the wait reads the PR again until the head catches up" || { echo "FAIL lag views ($(cat "$SEQ/n"))"; fails=$((fails + 1)); }
lag "a lag that outlasts the wait is PENDING, not MOVED" "PENDING head: the PR still shows ffff999 while its branch is at abc1234" abc1234def all
lag "a branch at another head is a real move" "MOVED ffff999000000000000000000000000000000000" 9999999aaa all
lag "a branch tip gh cannot read is a move, as before" "MOVED ffff999000000000000000000000000000000000" "" all

# #59: the hosted reviewer's required status missing on the head is named, so STAR sends the row back for a refresh
HRULES="$TMP/hosted-rules.json"
printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"ci"},{"context":"Greptile Review"}]}}]\n' > "$HRULES"
CIONLY='"statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}],"mergeStateStatus":"BLOCKED"'
WITHG='"statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"Greptile Review","state":"SUCCESS"}],"mergeStateStatus":"CLEAN"'
RUNNING='"statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"IN_PROGRESS","conclusion":""}],"mergeStateStatus":"BLOCKED"'
mh() { # mh <name> <expected> <json body> <--hosted value or nothing>
  printf '{%s}\n' "$3" > "$TMP/pr.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" STUB_RULES="$HRULES" sh "$SCRIPT" 5 --head abc1234 --merge-gate --hosted $4)
  if [ "$out" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got: $out)"; fails=$((fails + 1)); fi
}
mh "the hosted reviewer's required status missing on the head is named (#59)" "PENDING hosted-status Greptile Review missing on abc1234" "$OK,$BASE,$AUTHOR,$NOAPP,$CIONLY,\"comments\":[$PASSC]" "greptile-apps[bot]"
mh "a login without [bot] finds it too" "PENDING hosted-status Greptile Review missing on abc1234" "$OK,$BASE,$AUTHOR,$NOAPP,$CIONLY,\"comments\":[$PASSC]" "greptile-apps"
mh "with the hosted status on the head, it passes" "PASS hosted" "$OK,$BASE,$AUTHOR,$NOAPP,$WITHG,\"comments\":[$PASSC]" "greptile-apps[bot]"
mh "checks still running come first: ask again later" "PENDING checks: ci" "$OK,$BASE,$AUTHOR,$NOAPP,$RUNNING,\"comments\":[$PASSC]" "greptile-apps[bot]"
mh "a bare --hosted never names it" "PENDING merge state: blocked (a required check or review has not reported)" "$OK,$BASE,$AUTHOR,$NOAPP,$CIONLY,\"comments\":[$PASSC]" ""
printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"ci"},{"context":"build"}]}}]\n' > "$HRULES"
mh "a missing required check that is not the hosted reviewer's stays a blocked merge state (Review Focus)" "PENDING merge state: blocked (a required check or review has not reported)" "$OK,$BASE,$AUTHOR,$NOAPP,$CIONLY,\"comments\":[$PASSC]" "greptile-apps[bot]"
printf '{"x":1}\n' > "$HRULES"
mh "rules that cannot be read never name a hosted status" "PENDING merge state: blocked (a required check or review has not reported)" "$OK,$BASE,$AUTHOR,$NOAPP,$CIONLY,\"comments\":[$PASSC]" "greptile-apps[bot]"

# #124: ownerApproval in STAR's star.json lets the owner's own PR merge where no rule asks for an approval
OWN="$TMP/own"; OTHER="$TMP/other"; OFF="$TMP/off"; ABSENT="$TMP/absent"; mkdir -p "$OWN" "$OTHER" "$OFF" "$ABSENT"
printf '{"ownerApproval": {"login": "me", "since": "2026-10-15T21:05:13Z", "words": "feel free to merge"}}\n' > "$OWN/star.json"
printf '{"ownerApproval": {"login": "someone-else", "since": "2026-10-15T21:05:13Z", "words": "merge"}}\n' > "$OTHER/star.json"
printf '{"ownerApproval": null}\n' > "$OFF/star.json"
printf '{"project": {"name": "app"}}\n' > "$ABSENT/star.json"
ONE="$TMP/one-approval.json"; printf '[{"type":"pull_request","parameters":{"required_approving_review_count":1}}]\n' > "$ONE"
SELF="PASS self-approved under the owner's grant"
WAIT="PENDING approval: none on the current head from someone other than me"
# oa <name> <expected> <home> <json body> [rules file] [rules error] [extra args]
oa() {
  printf '{%s}\n' "$4" > "$TMP/pr.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" STUB_RULES="${5:-}" STUB_RULES_ERR="${6:-}" STUB_THREADS="${THREADS:-}" sh "$SCRIPT" 5 --head abc1234 --merge-gate --home "$3" ${7:-})
  if [ "$out" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got: $out)"; fails=$((fails + 1)); fi
}
NOREV="$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[$PASSC]"
oa "#124 ownerApproval for the author, no review rule: self-approved" "$SELF" "$OWN" "$NOREV"
oa "#124 ownerApproval for the author, an explicit zero rule: self-approved" "$SELF" "$OWN" "$NOREV" "$ZERO"
oa "#124 a rule that requires one approval keeps waiting" "$WAIT" "$OWN" "$NOREV" "$ONE"
oa "#124 a rule that cannot be read stays pending" "PENDING review rule: unreadable rules" "$OWN" "$NOREV" "$BAD"
oa "#124 a rule gh errors on stays pending" "PENDING review rule: gh: Server Error (HTTP 502)" "$OWN" "$NOREV" "" "gh: Server Error (HTTP 502)"
oa "#124 ownerApproval for another login keeps waiting" "$WAIT" "$OTHER" "$NOREV"
oa "#124 ownerApproval null keeps waiting" "$WAIT" "$OFF" "$NOREV"
oa "#124 no ownerApproval key keeps waiting" "$WAIT" "$ABSENT" "$NOREV"
oa "#124 a home with no star.json keeps waiting" "$WAIT" "$TMP/nohome" "$NOREV"
oa "#124 an approval by a member still reads approved" "PASS approved" "$OWN" "$OK,$BASE,$AUTHOR,$MEMBER_OK,$GREEN,\"comments\":[$PASSC]"
oa "#124 a hosted reviewer still reads hosted" "PASS hosted" "$OWN" "$NOREV" "" "" "--hosted"
oa "#124 self-approval still needs the codex PASS" "FAIL no codex PASS for abc1234" "$OWN" "$OK,$BASE,$AUTHOR,$NOAPP,$GREEN,\"comments\":[]"
oa "#124 self-approval still needs green checks" "FAIL checks: ci" "$OWN" "$OK,$BASE,$AUTHOR,$NOAPP,\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"name\":\"ci\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}],\"comments\":[$PASSC]"
oa "#124 self-approval still waits for a branch that is behind" "PENDING merge state: behind the base branch" "$OWN" "$NOREV,\"mergeStateStatus\":\"BEHIND\""
oa "#124 self-approval never hides changes requested" "FAIL approval: changes requested by ezra" "$OWN" "$OK,$BASE,$AUTHOR,\"reviewDecision\":\"\",\"reviews\":[{\"author\":{\"login\":\"ezra\"},\"state\":\"CHANGES_REQUESTED\",\"submittedAt\":\"2026-10-02T00:00:00Z\"}],$GREEN,\"comments\":[$PASSC]"
THREADS="$TMP/t2.json"
oa "#124 self-approval still needs a reply on every thread" "FAIL 1 finding without a reply from the author" "$OWN" "$NOREV"
unset THREADS
printf '{%s}\n' "$NOREV" > "$TMP/pr.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" JUEL_STAR_HOME="$OWN" sh "$SCRIPT" 5 --head abc1234 --merge-gate)
[ "$out" = "$SELF" ] && echo "ok   #124 without --home the gate reads JUEL_STAR_HOME's star.json" || { echo "FAIL #124 default home (got: $out)"; fails=$((fails + 1)); }
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/pr.json" sh "$SCRIPT" 5 --head abc1234 --home "$OWN" 2>/dev/null; echo "exit=$?")
[ "$out" = "exit=64" ] && echo "ok   #124 --home without --merge-gate exits 64" || { echo "FAIL #124 --home alone ($out)"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
