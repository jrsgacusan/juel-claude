#!/bin/sh
# Guards on skills/review-pr/SKILL.md text that cannot be tested by running code.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/review-pr/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }

g() { grep -qF -- "$2" "$SKILL" && pass "$1" || fail "$1"; }
ng() { grep -qF -- "$2" "$SKILL" && fail "$1" || pass "$1"; }
# The text of one "### Step <n>:" section, up to the next ### or ## heading.
step() { awk -v h="### Step $1:" 'index($0, h) == 1 { f = 1; print; next } /^### |^## / { f = 0 } f' "$SKILL"; }
srow() { step "$2" | grep -qF -- "$3" && pass "$1" || fail "$1"; }

# Task H1: the arguments, the PR, and your earlier threads
g "H1a --pr argument" '| `--pr <n or url>` |'
g "H1b --since argument" '| `--since <sha>` |'
g "H1c --from-babysit argument" '| `--from-babysit` |'
srow "H1d --pr needs the PR head checked out" 1 'check out the PR head first'
srow "H1e a stop under babysit is a result line" 1 'REVIEW-PR stopped reason=<the stop message>'
srow "H1f the title fallback reads the chosen PR" 1 'gh pr view $PR_SEL --json title'
srow "H1g the threads query is paginated" 1 'gh api graphql --paginate'
srow "H1h it reads reviewThreads" 1 'reviewThreads(first: 100, after: $endCursor)'
srow "H1i it keeps only your unresolved threads" 1 'select(.isResolved == false and .comments.nodes[0].author.login =='
g "H1j babysit is a SOFT dependency in the Preflight" '| juel:babysit-pr | skill | SOFT | ships with this plugin | watch the PR by hand |'
g "H1k and in the frontmatter" 'fallback: watch the PR by hand'

# Task H2: the report path Step 5 wrote is the one Steps 6 and 7 use
g "H2a Step 5 records the path it wrote" 'set `REPORT` to the path actually written'
srow "H2b Step 6 appends to that file" 6 'the same `$REPORT` file Step 5 wrote'
srow "H2c Step 7's guard reads that file" 7 '"$REPORT" | head -1'
ng "H2d no step reads a hard-coded report name" '"${docsRoot}/findings/findings-review.md"'
srow "H2e Posted goes into that file" 7 'section of `$REPORT`, the file Step 6 already'
g "H2f the versioning edge case says so" 'Steps 6 and 7 then use the file actually written'
ng "H2g no hard-coded name in Step 7's prose" 'remains in `findings-review.md`'

# Task H3: the re-review scope and the prior-thread buckets
srow "H3a a re-review passes its scope to the agents" 2 'Re-review: review only the changes in git diff <SINCE>..HEAD'
srow "H3b a force-push falls back to the whole diff" 2 'is not an ancestor of HEAD: reviewed the whole PR diff'
srow "H3c under --pr the reviewed commit is the head Step 1 fetched" 2 'Under `--pr`, `REVIEWED_COMMIT` is Step 1'"'"'s `PR_HEAD`'
srow "H3d Step 4 judges every prior thread" 4 '**Prior threads.** Judge each prior thread'
srow "H3e a thread can stay open" 4 '**still open**'
srow "H3f the report has five sections" 5 'exactly five sections'
srow "H3g the fifth is Prior threads" 5 '5. **Prior threads**'
srow "H3h Step 6 appends the sixth" 6 'Append a sixth section to the same `$REPORT` file'
g "H3i the overview names the re-review" 'With `--since`, the same cycle is a re-review'

# Task H4: the verdict answers "good to merge?"
srow "H4a every finding is blocking or not" 6 '**Blocking or not.**'
srow "H4b blocking means harm on merge" 6 'merging as it stands would cause harm'
srow "H4c the verdict answers one question" 6 'is this PR good to merge as it stands?'
srow "H4d an open blocking thread requests changes" 6 'thread still open with `blocking: yes`'
srow "H4e only a would-be blocker is COMMENT" 6 'Any Ambiguous finding that would block if it were confirmed'
ng "H4f the old ambiguous-or-partial rule is gone" 'Any Ambiguous finding remains, or any Requirement-alignment item is **partial**'
srow "H4g the report says good to merge" 6 '**Good to merge:** yes. <one sentence>'
srow "H4h it never disagrees with the verdict" 6 'It is yes exactly when the verdict is `APPROVE`.'
srow "H4i a prior thread is never posted twice" 6 '**Never post a prior thread twice.**'
g "H4j the plan lists threads to resolve" '**Threads to resolve** (resolved after the review posts, Step 7):'
g "H4k the plan lists thread replies" '| <thread node id> | <first comment databaseId> | Still open at <short sha>: <why> |'
g "H4l empty thread tables keep their header" 'The two thread tables follow the same rule.'
srow "H4m Step 6 reads Prior threads too" 6 'Confirmed, Ambiguous and Prior threads sections'

# Task H5: posting, the thread replies and resolves, the result lines, the hand-off
srow "H5a the user picks the verdict" 7 'Which verdict should this review carry?'
srow "H5b the draft's verdict comes first" 7 'the other two follow in the order'
srow "H5c a changed verdict is recorded" 7 'chosen by the user at post time over'
srow "H5d the payload carries the chosen verdict" 7 'the verdict chosen in the Verdict question'
srow "H5e a skip under babysit is a result line" 7 'REVIEW-PR stopped reason=<the SKIPPED reason>'
srow "H5f a moved head under babysit is a result line" 7 'REVIEW-PR head-moved from=<REVIEWED_COMMIT> to=<COMMIT>'
srow "H5g not posting under babysit is a result line" 7 'REVIEW-PR not-posted head=<COMMIT>'
srow "H5h posting under babysit is a result line" 7 'REVIEW-PR posted verdict=<the event that posted> commit=<COMMIT> url=<REVIEW_URL>'
srow "H5i a gh failure under babysit is a result line" 7 'REVIEW-PR stopped reason=gh api: <the error'
srow "H5j fixed threads are resolved" 7 'resolveReviewThread(input: {threadId: $threadId})'
srow "H5k open threads get a reply" 7 'gh api -X POST "repos/<REPO>/pulls/<PR>/comments/'
srow "H5l a posted review hands off to babysit" 7 'invoke `/juel:babysit-pr <PR>`'
g "H5m the edge cases say when" 'Hand off to `/juel:babysit-pr <PR>` (reviewer mode), unless `--from-babysit`'
srow "H5n Step 7 reads the chosen PR" 7 'gh pr view $PR_SEL --json headRefOid --jq'

# review fixes: scratch ignores stay out of the reviewed branch, the reviewed head is Step 1's, and --pr reaches every gh pr view
srow "F2a the scratch ignores go to the local exclude file" 5 '$(git rev-parse --git-path info/exclude)'
srow "F2b only when git does not already ignore them" 5 'git check-ignore -q'
srow "F2c never to the repo's .gitignore" 5 'never to `.gitignore`'
srow "F2d a review must not dirty the branch it reviews" 5 'must not dirty the branch it reviews'
ng "F2e Step 5 no longer adds entries to the repo's .gitignore" "Ensure the repo's \`.gitignore\` contains"
srow "F3a the fetch after the agents is not taken under --pr" 2 'Do not fetch it again'
srow "F3b a push during the review would be marked as reviewed" 2 'a push that lands while the agents run'
srow "F3c without --pr it is fetched as before" 2 'Without `--pr`'
step 2 | grep -qF 'gh pr view $PR_SEL --json headRefOid' && fail "F3d Step 2 does not fetch the head again under --pr" || pass "F3d Step 2 does not fetch the head again under --pr"
g "F6b the open-PR preflight row passes the chosen PR" '| open PR | context | SOFT | `gh pr view $PR_SEL --json number` |'
srow "F6c Step 7's skip rule 2 passes the chosen PR" 7 '(`gh pr view $PR_SEL --json number` fails)'
g "F6d the frontmatter check stays static" 'check: "gh pr view --json number"'

# lane c: #145 the exclude entries are anchored, and an earlier review's unanchored lines are dropped first
g "C145o the docs root entry comes from docsRoot" 'for d in "${docsRoot#"$ROOT"/}" .superpowers; do'
g "C145p each entry is appended anchored" "printf '/%s/\n' \"\$d\" >> \"\$EXCLUDE\""
g "C145q an earlier review's unanchored lines are dropped first" "grep -vxF -e 'superpowers/' -e '.superpowers/' \"\$EXCLUDE\""
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
