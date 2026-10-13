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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
