#!/bin/sh
# Guards on the text of juel:yuna, which cannot be tested by running code. Never calls yuna.sh.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
Y="$ROOT/skills/yuna/SKILL.md"
K="$ROOT/skills/yuki/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
# has <name> <text>: the text is in the skill once line breaks and repeated spaces are folded
has() { tr '\n' ' ' < "$Y" | tr -s ' ' | grep -qF -- "$2" && pass "$1" || fail "$1"; }
for f in "$Y" "$K"; do [ -f "$f" ] || { echo "FAIL missing $f"; exit 1; }; done

# The skill loader replaces $0..$9 in a skill body with the invocation's arguments.
if grep -nE '\$[0-9]' "$Y"; then fail "no positional parameters"; else pass "no positional parameters"; fi
grep -q '^name: yuna$' "$Y" && pass "name" || fail "name"

# The protocol block is yuki's, verbatim.
block() { awk '/^## Strict Execution Protocol/{p=1} /^## Preflight/{p=0} p' "$1"; }
[ "$(block "$Y")" = "$(block "$K")" ] && [ -n "$(block "$Y")" ] && pass "protocol block copied verbatim from yuki" || fail "protocol block copied verbatim from yuki"

# The frontmatter requires, in yuki's shape
for id in orca gh git python3 claude; do
  grep -q "^      - id: $id\$" "$Y" && pass "requires cli $id" || fail "requires cli $id"
done
for id in juel:orca-review-pr juel:review-pr juel:babysit-pr; do
  grep -q "^      - id: $id\$" "$Y" && pass "requires skill $id" || fail "requires skill $id"
done
has "triggers" 'Triggers "start yuna", "review my requested PRs", "keep reviewing PRs as they come in", "/juel:yuna".'

# The loop
has "ticks on a session cron, off yuki's minute" 'cron: "3-59/10 * * * *"'
has "the cron prompt carries the owner token" 'prompt: "/juel:yuna tick <token>"'
has "a tick that lost the token deletes its own job" '`CronDelete` the job whose prompt is `/juel:yuna tick <this token>`'
has "says the 7-day limit" 'expires after 7 days'
has "five slots by default" '(5 by default, --max <n>)'
has "asks what to review at the start" '"What should yuna review?"'
has "the requested-review source" 'review-requested:@me'
has "the whoami step" '`Y whoami`'
has "the fresh check" '`Y fresh <numbers>`'
has "the nudge step" '`Y nudge`'
has "spawns through orca-review-pr --yuna" '/juel:orca-review-pr --yuna YUNA_HOME <n> [<n> ...]'
has "records each SPAWNED line" 'run `Y add review-<n> ref=<n> pr=<url> path=<path> branch=<branch> throwaway=<branch> terminal=<handle>'
has "the status line" 'yuna <HH:MM>: running <n>/<max>[, approved <prs>]'
has "idle line" 'idle: nothing to review'

# Hard rules
has "the coordinator never posts, approves, merges or pushes" 'The coordinator never posts a review, never approves, never merges and never pushes.'
has "only the sweep removes a worktree" 'Only `Y sweep` removes a worktree'
has "never reads worker output" 'Never read worker output, a diff, a review or a log into this session.'
has "the nudge is the one screen read" 'its one line per item is the only screen read there is'
has "never asks in a tick" 'Never call `AskUserQuestion` in a tick.'
has "one yuna per repository" '**One yuna per repository**'
has "a PR is untrusted code" '**A PR is untrusted code.**'
has "no MCP approval" 'The nudge never approves an MCP dialog.'

# Edge cases
has "reopened as a new round" 'reopens its done row as a new round'
has "released after 72 hours" 'The author stays silent for 72 hours'
has "own PRs are skipped" 'Yuna never reviews its own PRs'
has "drafts are skipped" '`skip <n> draft`'
has "checked-out heads are skipped" '`skip <n> checked out at <path>`'

echo "---"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
