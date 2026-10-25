#!/bin/sh
# Runs skills/star/merge.sh against a stub gh.
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
mkdir -p "$TMP/nohome"; export JUEL_STAR_HOME="$TMP/nohome"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/calls"
printf '%s %s %s\n' "${GH_TOKEN:-none}" "$1" "$2" >> "$STUB_DIR/tokens"
case "$1 $2" in
  "repo view") [ -f "$STUB_DIR/repo-fail" ] && { echo "HTTP 403: Resource not accessible" >&2; exit 1; }; cat "$STUB_DIR/repo.json" ;;
  "pr view")
    case "$*" in
      *state,mergeCommit*) [ -f "$STUB_DIR/state-fail" ] && { echo "HTTP 502" >&2; exit 1; }; cat "$STUB_DIR/state.json" ;;
      *mergeStateStatus*) cat "$STUB_DIR/pre.json" ;;
      *) cat "$STUB_DIR/pr.json" ;;
    esac ;;
  "pr comment") [ -f "$STUB_DIR/comment-fail" ] && { echo "HTTP 502" >&2; exit 1; }; cp "$5" "$STUB_DIR/posted" ;;
  "pr merge") [ -f "$STUB_DIR/merge-err" ] && { cat "$STUB_DIR/merge-err" >&2; exit 1; }; exit 0 ;;
  "api -X") # the REST merge: rest-status picks the answer, rest-err is its message
    case "$(cat "$STUB_DIR/rest-status" 2>/dev/null)" in
      200) echo '{"merged":true}'; exit 0 ;;
      *) echo "{\"message\":\"x\"}"; cat "$STUB_DIR/rest-err" >&2; exit 1 ;;
    esac ;;
  "api "*) case "$2" in *rules/branches*) if [ -f "$STUB_DIR/rules.json" ]; then cat "$STUB_DIR/rules.json"; else echo '[]'; fi ;; *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;; esac ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$TMP/bin/gh"
state() { # state <GitHub's word for the PR after the merge call> [merge state] [head]
  printf '{"state":"%s","mergeCommit":{"oid":"9e8d7c6b5a49382716051423324150617e8f9a0b"},"headRefOid":"%s","mergeStateStatus":"%s"}\n' "$1" "${3:-$HEAD}" "${2:-CLEAN}" > "$TMP/state.json"
}
pre() { printf '{"headRefOid":"%s","mergeStateStatus":"%s"}\n' "$HEAD" "$1" > "$TMP/pre.json"; }
reset() { rm -f "$TMP/calls" "$TMP/tokens" "$TMP/posted" "$TMP/merge-err" "$TMP/repo-fail" "$TMP/state-fail" "$TMP/rules.json" "$TMP/rest-status" "$TMP/rest-err" "$TMP/comment-fail"; pre CLEAN; printf '{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}\n' > "$TMP/repo.json"; printf '{"author":{"login":"me"},"comments":[],"baseRefName":"dev"}\n' > "$TMP/pr.json"; state MERGED; }
M() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" sh "$SCRIPT" "$PR" --head "$HEAD" "$@"; }

reset; out=$(M)
[ "$out" = "MERGED 9e8d7c6b5a49382716051423324150617e8f9a0b" ] && pass "with no window it merges" || fail "merge ($out)"
grep -q "pr merge $PR --squash --match-head-commit $HEAD" "$TMP/calls" && pass "squash first, pinned to the head" || fail "merge call ($(cat "$TMP/calls"))"
[ "$(cat "$TMP/posted")" = "Merging head $HEAD: codex PASS, required checks green." ] && pass "B1g the comment names the gates, with no hosted reviewer" || fail "comment ($(cat "$TMP/posted"))"
reset; out=$(M --quiet-hours "22:00-07:00@UTC" 2> "$TMP/err"); rc=$?
[ "$rc" -eq 64 ] && [ -z "$out" ] && [ ! -f "$TMP/calls" ] && grep -qx 'merge.sh: unknown argument: --quiet-hours' "$TMP/err" && pass "--quiet-hours is refused with 64 and nothing happens" || fail "quiet flag (rc=$rc, out=$out, err=$(cat "$TMP/err"))"
reset; printf '{"squashMergeAllowed":false,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}\n' > "$TMP/repo.json"
M >/dev/null; grep -q -- "--merge --match-head-commit" "$TMP/calls" && pass "merge when squash is not allowed" || fail "method order"
# Review Focus 5
reset; printf '{"squashMergeAllowed":false,"mergeCommitAllowed":false,"rebaseMergeAllowed":false}\n' > "$TMP/repo.json"
out=$(M); [ "$out" = "FAIL merge methods: the repository allows no merge method" ] && ! grep -q 'pr merge' "$TMP/calls" && pass "no allowed method is a FAIL" || fail "no method ($out)"
reset; touch "$TMP/repo-fail"
out=$(M); [ "$out" = "FAIL merge methods: HTTP 403: Resource not accessible" ] && pass "unreadable settings are a FAIL, never a guess" || fail "repo fail ($out)"
reset; printf '{"author":{"login":"me"},"comments":[{"author":{"login":"me"},"body":"Merging head %s: codex PASS, required checks green."}]}\n' "$HEAD" > "$TMP/pr.json"
out=$(M); [ ! -f "$TMP/posted" ] && case "$out" in "MERGED "*) true ;; *) false ;; esac && pass "B1j the merge comment is posted once per head" || fail "comment twice ($out)"
reset; printf 'GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN CLEAN 1111111111111111111111111111111111111111
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
reset; out=$(M --dry-run); [ "$out" = "DRY-RUN squash $HEAD" ] && ! grep -q 'pr merge\|pr comment' "$TMP/calls" && pass "a dry run posts and merges nothing" || fail "dry run ($out)"
PATH="$TMP/bin:$PATH" sh "$SCRIPT" "$PR" --head abc1234 >/dev/null 2>&1; [ $? -eq 64 ] && pass "a short head is 64" || fail "usage head"
reset; out=$(M --grant "$TMP/g.md" 2>/dev/null); rc=$?; [ "$rc" -eq 64 ] && [ -z "$out" ] && [ ! -f "$TMP/calls" ] && pass "B1a --grant is unknown argument, 64" || fail "B1a ($rc, $out)"
# with --home and --item, a head a worker may still push to is never merged (#80)
APP="$TMP/app"; mkdir -p "$APP"; (cd "$APP" && git init -q -b main . && git commit -q --allow-empty -m init)
SH=$(HOME="$TMP/home" sh "$ROOT/skills/star/star-home.sh" --cwd "$APP" init)
LD() { sh "$ROOT/skills/star/ledger.sh" --home "$SH" "$@"; }
LD add ITEM-1 ref=ITEM-1 project=app state=verifying >/dev/null
MW() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" QUIET_NOW=${NOW:-2026-10-09T12:00:00Z} sh "$SCRIPT" "$PR" --head "$HEAD" --home "$SH" --item ITEM-1 "$@"; }
MW0() { env -u GH_TOKEN PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" QUIET_NOW=${NOW:-2026-10-09T12:00:00Z} sh "$SCRIPT" "$PR" --head "$HEAD" --home "$SH" --item ITEM-1 "$@"; }
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null
out=$(MW); [ "$out" = "$MERGED_LINE" ] && pass "a verifying row with no dispatch merges" || fail "no dispatch ($out)"
reset; LD set ITEM-1 state=verifying dispatch=ctx_babysit9 >/dev/null
out=$(MW); [ "$out" = "$MERGED_LINE" ] && pass "a verifying row that still names its last babysit dispatch merges" || fail "verifying with a dispatch ($out)"
bad=""
for st in briefing building babysitting posting; do
  reset; LD set ITEM-1 state=$st dispatch=ctx_w1 >/dev/null
  out=$(MW); { [ "$out" = "FAIL live worker ctx_w1" ] && [ ! -f "$TMP/calls" ]; } || bad="$bad $st($out)"
done
[ -z "$bad" ] && pass "a row in any worker stage is refused before anything is posted" || fail "worker stages:$bad"
# #137: with no GH_TOKEN, merge.sh uses the account configured in star.json; an existing token wins
python3 - "$SH/star.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["tokenCmd"] = "echo tok_star"; json.dump(d, open(p, "w"), indent=2)
PY
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null
out=$(MW0)
[ "$out" = "$MERGED_LINE" ] && [ -s "$TMP/tokens" ] && ! grep -v '^tok_star ' "$TMP/tokens" >/dev/null && pass "#137 merge.sh runs gh as star.json's tokenCmd account" || fail "#137 merge token ($(cat "$TMP/tokens" 2>/dev/null))"
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null
out=$(GH_TOKEN=already MW)
[ "$out" = "$MERGED_LINE" ] && [ -s "$TMP/tokens" ] && ! grep -v '^already ' "$TMP/tokens" >/dev/null && pass "#137 a GH_TOKEN already set is kept" || fail "#137 existing merge token ($(cat "$TMP/tokens" 2>/dev/null))"
python3 - "$SH/star.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["tokenCmd"] = None; json.dump(d, open(p, "w"), indent=2)
PY
reset; LD set ITEM-1 state=babysitting dispatch=ctx_w5 >/dev/null
out=$(MW); [ "$out" = "FAIL live worker ctx_w5" ] && pass "a live worker holds the merge" || fail "live worker ($out)"
reset; out=$(PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" sh "$SCRIPT" "$PR" --head "$HEAD" --home "$SH" --item NOPE-9)
case "$out" in "FAIL ledger: "*) [ ! -f "$TMP/calls" ] && pass "an item with no row is a FAIL, never a merge" || fail "no row called gh" ;; *) fail "no row ($out)" ;; esac
PATH="$TMP/bin:$PATH" sh "$SCRIPT" "$PR" --head "$HEAD" --home "$SH" >/dev/null 2>&1; [ $? -eq 64 ] && pass "--home without --item is 64" || fail "usage home"
PATH="$TMP/bin:$PATH" sh "$SCRIPT" "$PR" --head "$HEAD" --item ITEM-1 >/dev/null 2>&1; [ $? -eq 64 ] && pass "--item without --home is 64" || fail "usage item"
# B1: the project's merge method, owner branches, the hosted reviewer clause, the home
cfg() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.update(json.loads(sys.argv[2])); json.dump(d,open(p,"w"),indent=2)' "$SH/star.json" "$1"; }
cfg '{"mergeMethod":null,"ownerBranches":[],"hostedReviewer":null}'
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null
out=$(MW); [ "$out" = "$MERGED_LINE" ] && grep -q -- "pr merge $PR --squash" "$TMP/calls" && pass "B1b a passing PR merges with no grant" || fail "B1b ($out)"
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null; cfg '{"mergeMethod":"merge"}'
out=$(MW); grep -q -- "pr merge $PR --merge --match-head-commit $HEAD" "$TMP/calls" && pass "B1c mergeMethod merge is used when the repo allows it" || fail "B1c ($out)"
out=$(MW --dry-run); [ "$out" = "DRY-RUN merge $HEAD" ] && pass "B1c dry run names the method" || fail "B1c dry ($out)"
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null; printf '{"squashMergeAllowed":true,"mergeCommitAllowed":false,"rebaseMergeAllowed":false}\n' > "$TMP/repo.json"
out=$(MW); rc=$?
[ "$out" = "FAIL merge methods: merge not allowed" ] && [ "$rc" -eq 0 ] && [ ! -f "$TMP/posted" ] && ! grep -q 'pr merge' "$TMP/calls" && pass "B1d a method the repo does not allow is a FAIL, no comment, no merge" || fail "B1d ($out, rc=$rc)"
out=$(MW --dry-run); [ "$out" = "FAIL merge methods: merge not allowed" ] && pass "B1d the same on a dry run" || fail "B1d dry ($out)"
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null; cfg '{"mergeMethod":null}'
out=$(MW); grep -q -- "pr merge $PR --squash" "$TMP/calls" && pass "B1e a null mergeMethod keeps the squash-first order" || fail "B1e ($out)"
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null; cfg '{"ownerBranches":["main"]}'; printf '{"author":{"login":"me"},"comments":[],"baseRefName":"main"}\n' > "$TMP/pr.json"
out=$(MW); [ "$out" = "FAIL owner branch main" ] && [ ! -f "$TMP/posted" ] && ! grep -q 'pr merge' "$TMP/calls" && pass "B1f an owner branch is never merged" || fail "B1f ($out)"
out=$(MW --dry-run); [ "$out" = "FAIL owner branch main" ] && pass "B1f the same on a dry run" || fail "B1f dry ($out)"
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null; cfg '{"ownerBranches":["main"]}'
out=$(MW); [ "$out" = "$MERGED_LINE" ] && pass "B1f a PR on another base merges" || fail "B1f other base ($out)"
cfg '{"ownerBranches":[]}'
HOSTED='{"login":"greptile-apps[bot]","minScore":4,"maxPasses":2,"refreshOutsideCap":true,"paused":false}'
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null; cfg "{\"hostedReviewer\":$HOSTED}"
out=$(MW --hosted 'greptile-apps[bot]'); [ "$(cat "$TMP/posted")" = "Merging head $HEAD: codex PASS, required checks green, greptile-apps[bot] passed." ] && pass "B1h R4 --hosted <login> names the hosted reviewer" || fail "B1h ($(cat "$TMP/posted" 2>/dev/null))"
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null
out=$(MW); [ "$(cat "$TMP/posted")" = "Merging head $HEAD: codex PASS, required checks green." ] && pass "B1i R4 star.json's hostedReviewer is not read: no clause without --hosted" || fail "B1i ($(cat "$TMP/posted" 2>/dev/null))"
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null; cfg '{"hostedReviewer":null}'
out=$(MW --hosted 2>/dev/null); rc=$?; [ "$rc" -eq 64 ] && [ ! -f "$TMP/calls" ] && pass "R4 --hosted without a login is 64" || fail "R4 bare --hosted ($rc, $out)"
# R-4: a home whose star.json exists but cannot be parsed is a FAIL, never a merge
cp "$SH/star.json" "$TMP/star.json.keep"
reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null; printf '{not json' > "$SH/star.json"
out=$(MW); rc=$?
case "$out" in "FAIL settings: "*) [ "$rc" -eq 0 ] && [ ! -f "$TMP/posted" ] && ! grep -q 'pr merge' "$TMP/calls" 2>/dev/null && pass "R4 an unparsable star.json is FAIL settings, no comment, no merge" || fail "R4 side effects ($out, rc=$rc)" ;; *) fail "R4 unparsable ($out)" ;; esac
out=$(MW --dry-run); case "$out" in "FAIL settings: "*) pass "R4 the same on a dry run" ;; *) fail "R4 dry ($out)" ;; esac
printf '[1]\n' > "$SH/star.json"
out=$(MW); case "$out" in "FAIL settings: "*) pass "R4 a star.json that is not an object is FAIL settings" ;; *) fail "R4 non-object ($out)" ;; esac
rm -f "$SH/star.json"; reset; LD set ITEM-1 state=verifying dispatch=- >/dev/null
out=$(MW); [ "$out" = "$MERGED_LINE" ] && pass "R4 a missing star.json is still no settings" || fail "R4 missing ($out)"
cp "$TMP/star.json.keep" "$SH/star.json"
cfg '{"hostedReviewer":null}'
reset; cfg '{"mergeMethod":"rebase"}'
out=$(JUEL_STAR_HOME="$SH" PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" sh "$SCRIPT" "$PR" --head "$HEAD"); grep -q -- "pr merge $PR --rebase" "$TMP/calls" && pass "B1k with no --home, JUEL_STAR_HOME names the home" || fail "B1k ($out)"
cfg '{"mergeMethod":null}'

# audit lane G: a required check that has not reported is PENDING, not a FAIL (#167)
reset; printf 'GraphQL: Required status check "ci" is expected. (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN
out=$(M); rc=$?
[ "$out" = "PENDING check ci not reported" ] && [ "$rc" -eq 0 ] && pass "G a required check not reported is PENDING, exit 0" || fail "G pending ($out, rc=$rc)"
reset; printf 'GraphQL: Required status check "ci" is expected. (mergePullRequest)\n' > "$TMP/merge-err"; state MERGED
out=$(M); [ "$out" = "MERGED 9e8d7c6b5a49382716051423324150617e8f9a0b" ] && pass "G the same error on a merged PR is MERGED" || fail "G pending but merged ($out)"
reset; printf 'GraphQL: Pull request is not mergeable (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN
out=$(M); case "$out" in "FAIL merge: "*) pass "G any other merge error is still FAIL merge" ;; *) fail "G other error ($out)" ;; esac

# audit lane D: any missing-required-check refusal is PENDING, even when the state cannot be read
reset; printf 'GraphQL: 2 of 3 required status checks are expected. (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN
out=$(M); rc=$?
[ "$out" = "PENDING check required checks not reported" ] && [ "$rc" -eq 0 ] && pass "D '2 of 3 required status checks are expected' is PENDING with no name" || fail "D plural ($out, rc=$rc)"
reset; printf 'GraphQL: Required status check "ci/build" is expected, 2 of 3 required status checks are expected.\n' > "$TMP/merge-err"; state OPEN
out=$(M); [ "$out" = "PENDING check ci/build not reported" ] && pass "D the first quoted name is used" || fail "D named ($out)"
reset; printf 'GraphQL: Required status check "ci" is expected. (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN; touch "$TMP/state-fail"
out=$(M); rc=$?
[ "$out" = "PENDING check ci not reported" ] && [ "$rc" -eq 0 ] && pass "D a missing-check refusal whose state cannot be read is PENDING" || fail "D unreadable ($out, rc=$rc)"


# #193: the comment follows the merge; a refusal is classified by reading the PR again
reset; printf 'GraphQL: Pull request is not mergeable (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN
M >/dev/null; [ ! -f "$TMP/posted" ] && ! grep -q 'pr comment' "$TMP/calls" && pass "#193 a refused merge leaves no comment" || fail "#193 comment on a refusal"
reset; M >/dev/null; [ "$(cat "$TMP/posted")" = "Merging head $HEAD: codex PASS, required checks green." ] && pass "#193 a merged PR gets the comment" || fail "#193 comment after merge"
reset; touch "$TMP/comment-fail"
out=$(M 2>"$TMP/err"); [ "$out" = "$MERGED_LINE" ] && grep -q '^merge.sh: comment failed: HTTP 502' "$TMP/err" && pass "#193 a comment that fails after the merge is MERGED with a note on stderr" || fail "#193 comment failure ($out, $(cat "$TMP/err"))"
reset; printf 'GraphQL: Head branch is not up to date with the base branch\n' > "$TMP/merge-err"; state OPEN BEHIND
out=$(M); [ "$out" = "PENDING merge state: behind the base branch" ] && pass "#193 a BEHIND refusal on the same head is its own PENDING line, not head moved" || fail "#193 behind ($out)"
reset; printf 'GraphQL: Head branch is not up to date with the base branch\n' > "$TMP/merge-err"; state OPEN BEHIND 2222222222222222222222222222222222222222
out=$(M); [ "$out" = "FAIL head moved" ] && pass "#193 a different head is head moved even when BEHIND" || fail "#193 moved behind ($out)"
reset; printf 'GraphQL: Pull request is not mergeable (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN DIRTY
out=$(M); [ "$out" = "FAIL merge: conflicts with the base" ] && pass "#193 a DIRTY PR is conflicts with the base" || fail "#193 dirty ($out)"
reset; printf 'GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)\n' > "$TMP/merge-err"; state OPEN; touch "$TMP/state-fail"
out=$(M); [ "$out" = "FAIL head moved" ] && pass "#193 with the PR unreadable the error text still says head moved" || fail "#193 unreadable moved ($out)"

# #193: a BEHIND PR on a base with no strict, unknown or queue rule merges through the REST endpoint
RESTCALL="api -X PUT repos/o/r/pulls/5/merge -f sha=$HEAD -f merge_method=squash"
reset; pre BEHIND; echo 200 > "$TMP/rest-status"
out=$(M); [ "$out" = "$MERGED_LINE" ] && grep -qx "$RESTCALL" "$TMP/calls" && ! grep -q 'pr merge' "$TMP/calls" && pass "#193 BEHIND on a free base: REST merge pinned to the head, 200 is MERGED" || fail "#193 rest ($out, $(cat "$TMP/calls"))"
[ "$(cat "$TMP/posted")" = "Merging head $HEAD: codex PASS, required checks green." ] && pass "#193 the REST merge is followed by the comment" || fail "#193 rest comment"
reset; pre CLEAN; M >/dev/null; ! grep -q '^api -X' "$TMP/calls" && grep -q 'pr merge' "$TMP/calls" && pass "#193 a PR that is not BEHIND keeps gh pr merge" || fail "#193 clean path"
reset; pre BEHIND; printf '[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[]}}]\n' > "$TMP/rules.json"
M >/dev/null; grep -q 'pr merge' "$TMP/calls" && ! grep -q '^api -X' "$TMP/calls" && pass "#193 a strict base keeps gh pr merge" || fail "#193 strict"
reset; pre BEHIND; printf '[{"type":"merge_queue","parameters":{}}]\n' > "$TMP/rules.json"
M >/dev/null; grep -q 'pr merge' "$TMP/calls" && ! grep -q '^api -X' "$TMP/calls" && pass "#193 a merge queue keeps gh pr merge" || fail "#193 queue"
reset; pre BEHIND; echo 409 > "$TMP/rest-status"; printf 'gh: Head branch was modified (HTTP 409)\n' > "$TMP/rest-err"; state OPEN BEHIND 3333333333333333333333333333333333333333
out=$(M); [ "$out" = "FAIL head moved" ] && ! [ -f "$TMP/posted" ] && pass "#193 REST 409 with a different head is head moved" || fail "#193 rest 409 ($out)"
reset; pre BEHIND; echo 405 > "$TMP/rest-status"; printf 'gh: Pull Request is not mergeable (HTTP 405)\n' > "$TMP/rest-err"; state OPEN DIRTY
out=$(M); [ "$out" = "FAIL merge: conflicts with the base" ] && pass "#193 REST 405 on a conflicted PR is conflicts with the base" || fail "#193 rest 405 dirty ($out)"
reset; pre BEHIND; echo 405 > "$TMP/rest-status"; printf 'gh: Required status check "ci" is expected. (HTTP 405)\n' > "$TMP/rest-err"; state OPEN BEHIND
out=$(M); [ "$out" = "PENDING check ci not reported" ] && pass "#193 REST 405 for a required check is PENDING check" || fail "#193 rest 405 check ($out)"
reset; pre BEHIND; echo 422 > "$TMP/rest-status"; printf 'gh: Validation Failed (HTTP 422)\n' > "$TMP/rest-err"; state OPEN
out=$(M); [ "$out" = "FAIL merge: gh: Validation Failed (HTTP 422)" ] && pass "#193 REST 422 is FAIL merge with its first line" || fail "#193 rest 422 ($out)"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
