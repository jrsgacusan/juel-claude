#!/bin/sh
# Runs skills/star/release-record.sh against a scratch STAR home and a stub gh.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/release-record.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL release-record.sh missing"; exit 1; }
H="$TMP/home"; mkdir -p "$H/reviews/lstn" "$H/briefs/lstn" "$TMP/bin"
cp "$ROOT/skills/star/template/ledger.md" "$H/ledger.md"; cp "$ROOT/skills/star/template/open-loops.md" "$H/open-loops.md"
printf '| #12 | #12 | lstn | /w/a | ready | - | 2 | t | d | 0 | https://github.com/o/lstn/pull/12 | abc1234 | - | - | now |\n| #12 | #12 | web | /w/b | ready | - | 1 | t | d | 0 | https://github.com/o/web/pull/12 | fff0000 | - | - | now |\n' >> "$H/ledger.md"
: > "$H/reviews/lstn/#12-r1.md"; : > "$H/reviews/lstn/#12-r2.md"; : > "$H/briefs/lstn/#12.md"
sh "$ROOT/skills/star/loops.sh" --file "$H/open-loops.md" add --kind held --project lstn --item '#12' --title "set status in_review via linear" >/dev/null
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
[ "${STUB_FAIL:-}" = 1 ] && { echo "boom" >&2; exit 1; }
cat "$STUB_JSON"
EOF
chmod +x "$TMP/bin/gh"; ln -s "$(command -v python3)" "$TMP/bin/python3"
cat > "$TMP/merged.json" <<'EOF'
{"number":12,"title":"Add retry to the webhook","url":"https://github.com/o/lstn/pull/12","state":"MERGED",
 "mergeCommit":{"oid":"9e8d7c6b5a"},"mergedAt":"2026-10-07T03:04:05Z","mergedBy":{"login":"jrsgacusan"},
 "baseRefName":"main","headRefName":"feat/issue-12-retry",
 "reviews":[{"author":{"login":"ezra"},"state":"APPROVED"},{"author":{"login":"jp"},"state":"COMMENTED"},{"author":{"login":"ezra"},"state":"APPROVED"}],
 "statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]}
EOF
run() { PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged.json" sh "$SCRIPT" --home "$H" "$@"; }
out=$(run --project lstn --item '#12' --pr 12)
exp="$H/releases/2026-10-07-lstn-12.md"
[ "$out" = "$exp" ] && [ -f "$exp" ] && pass "record written, path printed" || fail "record path ($out)"
grep -q 'Add retry to the webhook' "$exp" && grep -q '9e8d7c6b5a' "$exp" && grep -q 'jrsgacusan' "$exp" && pass "title, merge commit, merger" || fail "core fields"
grep -q 'Approved by: ezra$' "$exp" && pass "approvers deduplicated, commenters excluded" || fail "approvers"
grep -q 'Checks on the PR head at merge: all passed' "$exp" && pass "checks" || fail "checks"
grep -q 'Second-model review rounds: 2' "$exp" && pass "same item in two projects: the lstn row is used" || fail "wrong ledger row"
grep -q 'reviews/lstn/#12-r1.md' "$exp" && grep -q 'reviews/lstn/#12-r2.md' "$exp" && pass "review files listed" || fail "review files"
grep -q 'set status in_review via linear' "$exp" && pass "open follow-ups listed" || fail "follow-ups"
out2=$(run --project lstn --item '#12' --pr 12)
[ "$out2" = "$H/releases/2026-10-07-lstn-12-v2.md" ] && pass "never overwrites" || fail "overwrote ($out2)"
sed 's/"state":"MERGED"/"state":"OPEN"/' "$TMP/merged.json" > "$TMP/open.json"
PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/open.json" sh "$SCRIPT" --home "$H" --project lstn --item '#12' --pr 12 >/dev/null 2>&1
[ $? -eq 1 ] && pass "an unmerged PR is refused" || fail "unmerged PR accepted"
PATH="$TMP/bin:/usr/bin:/bin" STUB_FAIL=1 STUB_JSON=/dev/null sh "$SCRIPT" --home "$H" --project lstn --item '#12' --pr 12 >/dev/null 2>&1
[ $? -eq 1 ] && pass "gh failure is an error" || fail "gh failure"

sh "$ROOT/skills/star/loops.sh" --file "$H/open-loops.md" add --kind merge-pr --project lstn --item '#12' --title "merge PR #12 — approved" >/dev/null
out3=$(run --project lstn --item '#12' --pr 12)
grep -q 'set status in_review via linear' "$out3" && ! grep -q 'merge PR #12 — approved' "$out3" && pass "the item's own merge-pr entry is not a follow-up" || fail "merge-pr listed as a follow-up"
grep -q '^- Worktree: /w/a' "$out3" && pass "worktree recorded (evidence lives there)" || fail "worktree missing"
grep -q 'Checks on the PR head at merge: all passed' "$out3" && pass "checks labelled honestly" || fail "checks label"
PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged.json" sh "$SCRIPT" --bogus >/dev/null 2>&1; [ $? -eq 64 ] && pass "bad usage is exit 64" || fail "usage exit code"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
