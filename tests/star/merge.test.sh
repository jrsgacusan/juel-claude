#!/bin/sh
# Runs skills/star/merge.sh against a stub gh, with the real quiet-hours.sh on a fixed clock.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/merge.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL merge.sh missing"; exit 1; }
HEAD=abc1234def5678901234567890123456789abcde
PR=https://github.com/o/r/pull/5
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/calls"
case "$1 $2" in
  "repo view") [ -f "$STUB_DIR/repo-fail" ] && { echo "HTTP 403: Resource not accessible" >&2; exit 1; }; cat "$STUB_DIR/repo.json" ;;
  "pr view")
    case "$*" in *state*) [ -f "$STUB_DIR/state-fail" ] && { echo "HTTP 502" >&2; exit 1; }; cat "$STUB_DIR/state.json" ;; *) cat "$STUB_DIR/pr.json" ;; esac ;;
  "pr comment") cp "$5" "$STUB_DIR/posted" ;;
  "pr merge") [ -f "$STUB_DIR/merge-err" ] && { cat "$STUB_DIR/merge-err" >&2; exit 1; }; exit 0 ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$TMP/bin/gh"
grant() { printf -- '---\ndate: 2026-10-09T08:00:00Z\nitems: [ITEM-1]\n---\n%s\n' "$1" > "$TMP/grant.md"; }
state() { # state <GitHub's word for the PR after the merge call>
  printf '{"state":"%s","mergeCommit":{"oid":"9e8d7c6b5a49382716051423324150617e8f9a0b"}}\n' "$1" > "$TMP/state.json"
}
reset() { rm -f "$TMP/calls" "$TMP/posted" "$TMP/merge-err" "$TMP/repo-fail" "$TMP/state-fail"; printf '{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}\n' > "$TMP/repo.json"; printf '{"author":{"login":"me"},"comments":[]}\n' > "$TMP/pr.json"; state MERGED; grant "go"; }
M() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" QUIET_NOW=${NOW:-2026-10-09T12:00:00Z} sh "$SCRIPT" "$PR" --head "$HEAD" --grant "$TMP/grant.md" "$@"; }

reset; out=$(M --quiet-hours "22:00-07:00@UTC")
[ "$out" = "MERGED 9e8d7c6b5a49382716051423324150617e8f9a0b" ] && pass "outside quiet hours it merges" || fail "merge ($out)"
grep -q "pr merge $PR --squash --match-head-commit $HEAD" "$TMP/calls" && pass "squash first, pinned to the head" || fail "merge call ($(cat "$TMP/calls"))"
[ "$(cat "$TMP/posted")" = "Merging head $HEAD under your go of 2026-10-09T08:00:00Z: \"go\"" ] && pass "the go is quoted on the PR first" || fail "comment ($(cat "$TMP/posted"))"
reset; out=$(NOW=2026-10-09T23:00:00Z M --quiet-hours "22:00-07:00@UTC")
[ "$out" = "HELD quiet hours" ] && [ ! -f "$TMP/calls" ] && pass "inside quiet hours nothing happens" || fail "quiet ($out)"
reset; out=$(M --quiet-hours "nonsense")
[ "$out" = "HELD quiet hours" ] && pass "a window that cannot be judged holds" || fail "bad window ($out)"
reset; printf '{"squashMergeAllowed":false,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}\n' > "$TMP/repo.json"
M >/dev/null; grep -q -- "--merge --match-head-commit" "$TMP/calls" && pass "merge when squash is not allowed" || fail "method order"
# Review Focus 5
reset; printf '{"squashMergeAllowed":false,"mergeCommitAllowed":false,"rebaseMergeAllowed":false}\n' > "$TMP/repo.json"
out=$(M); [ "$out" = "FAIL merge methods: the repository allows no merge method" ] && ! grep -q 'pr merge' "$TMP/calls" && pass "no allowed method is a FAIL" || fail "no method ($out)"
reset; touch "$TMP/repo-fail"
out=$(M); [ "$out" = "FAIL merge methods: HTTP 403: Resource not accessible" ] && pass "unreadable settings are a FAIL, never a guess" || fail "repo fail ($out)"
reset; printf '{"author":{"login":"me"},"comments":[{"author":{"login":"me"},"body":"Merging head %s under your go of 2026-10-09T08:00:00Z: \\"go\\""}]}\n' "$HEAD" > "$TMP/pr.json"
out=$(M); [ ! -f "$TMP/posted" ] && case "$out" in "MERGED "*) true ;; *) false ;; esac && pass "the grant comment is posted once per head" || fail "comment twice ($out)"
reset; printf 'GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN
out=$(M); [ "$out" = "FAIL head moved" ] && pass "a moved head is FAIL head moved" || fail "moved ($out)"
reset; printf 'GraphQL: Pull request is not mergeable (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN
out=$(M); [ "$out" = "FAIL merge: GraphQL: Pull request is not mergeable (mergePullRequest)" ] && pass "another refusal is named" || fail "refused ($out)"
# A-3: a merge call that errors may still have merged; one that worked but cannot be confirmed prints no line
MERGED_LINE="MERGED 9e8d7c6b5a49382716051423324150617e8f9a0b"
reset; printf 'error connecting to api.github.com\n' > "$TMP/merge-err"
out=$(M); [ "$out" = "$MERGED_LINE" ] && [ "$(grep -c 'state,mergeCommit' "$TMP/calls")" = 1 ] && pass "a merge call that errors on a PR GitHub says is merged is MERGED, after one state read" || fail "errored but merged ($out)"
reset; printf 'GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)\n' > "$TMP/merge-err"
out=$(M); [ "$out" = "$MERGED_LINE" ] && pass "a head-moved refusal on a PR that is merged is MERGED, not FAIL head moved" || fail "moved but merged ($out)"
reset; printf 'GraphQL: Pull request is not mergeable (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN; touch "$TMP/state-fail"
out=$(M); [ "$out" = "FAIL merge: GraphQL: Pull request is not mergeable (mergePullRequest)" ] && pass "a refusal whose state cannot be read stays the FAIL" || fail "refused, state unreadable ($out)"
reset; touch "$TMP/state-fail"
out=$(M 2>"$TMP/err"); rc=$?
[ -z "$out" ] && [ "$rc" -ne 0 ] && [ "$rc" -ne 64 ] && [ -s "$TMP/err" ] && pass "a merge call that worked but whose state cannot be read prints no line and exits non-zero, not 64" || fail "state unreadable after a good call (rc=$rc, out=$out)"
reset; printf '{"mergeCommit":null}\n' > "$TMP/state.json"
out=$(M 2>/dev/null); rc=$?
[ -z "$out" ] && [ "$rc" -ne 0 ] && [ "$rc" -ne 64 ] && pass "a state with no state in it is just as unreadable" || fail "no state field (rc=$rc, out=$out)"
reset; state OPEN
out=$(M); [ "$out" = "FAIL merge: GitHub says OPEN after the merge call" ] && pass "a merge call that worked on a PR GitHub says is open is a FAIL" || fail "open after a good call ($out)"
# Review Focus 4: quotes, line breaks and a long message go through --body-file, cut at 500
reset; long=$(python3 -c 'print("say \"yes\" and $(rm -rf x) `id` " * 80)'); grant "$(printf 'line one\nline two %s' "$long")"
out=$(M); case "$out" in "MERGED "*) pass "an awkward go message still merges" ;; *) fail "awkward go ($out)" ;; esac
grep -q -- "--body-file" "$TMP/calls" && ! grep -q -- "--body " "$TMP/calls" && pass "the comment goes through a file" || fail "body flag"
python3 - "$TMP/posted" <<'PY' && pass "the words are kept on one line and cut at 500 characters" || fail "cut"
import sys
t = open(sys.argv[1]).read()
words = t.split(': "', 1)[1].rstrip().rstrip('"')
assert "\n" not in t.rstrip("\n") and len(words) == 500 and words.endswith("...") and words.startswith("line one line two"), (len(words), t[:80])
PY
reset; out=$(M --dry-run); [ "$out" = "DRY-RUN squash $HEAD" ] && ! grep -q 'pr merge\|pr comment' "$TMP/calls" && pass "a dry run posts and merges nothing" || fail "dry run ($out)"
reset; printf -- '---\nitems: [ITEM-1]\n---\n\n' > "$TMP/grant.md"
out=$(M); case "$out" in "FAIL grant: no date or no words"*) pass "a grant with no words is a FAIL" ;; *) fail "empty grant ($out)" ;; esac
PATH="$TMP/bin:$PATH" sh "$SCRIPT" "$PR" --head abc1234 --grant "$TMP/grant.md" >/dev/null 2>&1; [ $? -eq 64 ] && pass "a short head is 64" || fail "usage head"
PATH="$TMP/bin:$PATH" sh "$SCRIPT" "$PR" --head "$HEAD" >/dev/null 2>&1; [ $? -eq 64 ] && pass "no grant is 64" || fail "usage grant"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
