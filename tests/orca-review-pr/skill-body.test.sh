#!/bin/sh
# Guards on skills/orca-review-pr/SKILL.md text that cannot be tested by running code.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/orca-review-pr/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
has() { tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qF -- "$2" && pass "$1" || fail "$1"; }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }

# The skill loader replaces $0..$9 in a skill body with the invocation's arguments.
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
has "resolve_bin loops over its arguments" 'resolve_bin() { for c in "$@"; do'
has "detect_ref reads its arguments in a loop" 'for a in "$@"; do n=$((n + 1));'

# The prompt names the skill (#208)
has "the plain prompt names juel:review-pr" '--prompt "${AGENT_PROMPT_PREFIX}juel:review-pr --pr $PR${REF:+ $REF}"'
if grep -nF '"$AGENT_PROMPT_PREFIX $PR' "$SKILL"; then fail "no prompt of the form '/ 1234'"; else pass "no prompt of the form '/ 1234'"; fi

# --yuna
has "--yuna argument" '| `--yuna <home> <n> [<n> ...]` |'
has "Yuna mode section" '## Yuna mode'
has "yuna prompt" '"${AGENT_PROMPT_PREFIX}juel:review-pr --pr $PR${REF:+ $REF} --yuna $YUNA_HOME --item $NAME"'
has "gh goes through the yuna wrapper" 'runs as `Y gh …` or `Y git …`'
has "nothing is asked" '**Nothing is asked.**'
has "fetch once per run" '**Fetch once per run.**'
has "SPAWNED line" 'SPAWNED item=review-<n> pr=<url> path=<path> branch=<head ref> throwaway=<orca branch> terminal=<handle>'
has "SKIPPED line" 'SKIPPED item=review-<n> reason=<one line>'
has "an existing worktree is skipped" 'a `review-<n>` worktree that already exists'
has "the teardown warning is not printed" 'the warning below is not printed'

# review fixes (F2)
has "yuna fetches the PR ref" 'fetch <remote> pull/<n>/head'
has "yuna checks the fetched head out detached" 'checkout --detach FETCH_HEAD'
has "the head is confirmed against headRefOid" 'rev-parse HEAD` equals the PR'"'"'s `headRefOid`'
has "gh pr checkout is not used under yuna" '`gh pr checkout` is not used under `--yuna`'
has "yuna skips the install tab" 'Under `--yuna` skip Step 7'
has "yuna copies only ignored files" 'check-ignore -q'
has "a failed spawn removes its worktree" 'removes it (check out the throwaway branch, then `orca worktree rm`, never `--force`)'
has "a dialog that stays is a SKIPPED line" 'SKIPPED item=review-<n> reason=a first-run dialog is still on screen'
has "both prompts use the resolved agent" '--agent "$AGENT_KIND"'
if grep -qF -- '--agent claude' "$SKILL"; then fail "no hardcoded --agent claude"; else pass "no hardcoded --agent claude"; fi

echo "---"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
