#!/bin/sh
# Guards on skills/babysit-pr/SKILL.md text that cannot be tested by running code.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/babysit-pr/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }

# The skill loader substitutes $0..$9 in a skill body with words from the user's request.
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
grep -q 'Never merge the PR' "$SKILL" && pass "never merges" || fail "never-merge rule missing"
grep -q 'Never resolve review threads' "$SKILL" && pass "never resolves threads" || fail "never-resolve rule missing"
grep -q 'Never force-push' "$SKILL" && pass "never force-pushes" || fail "never-force-push rule missing"
grep -q 'in_reply_to' "$SKILL" && pass "replies go to the thread root" || fail "thread-root reply rule missing"
grep -q 'wake' "$SKILL" && pass "uses pr-state wake values" || fail "wake handling missing"
grep -q 'new feedback arrived while' "$SKILL" && pass "post-push re-check present" || fail "post-push re-check missing"

# An approval with change requests gets fixes, a push and replies, but no new review request.
grep -q 'Skip this step when the round.s `decision` is `APPROVED`' "$SKILL" && pass "no re-request on an approved PR" || fail "re-request is not skipped for an approved PR"

grep -q '^## Unattended mode' "$SKILL" && pass "unattended mode documented" || fail "unattended mode"
grep -q 'Always the foreground form with `--max-seconds 540`' "$SKILL" && pass "unattended waits in the foreground" || fail "unattended foreground wait"
grep -q 'READY item=<item> pr=<url> head=<pushed sha>' "$SKILL" && pass "unattended READY line" || fail "READY line"
grep -q 'Never mark it ready a second time' "$SKILL" && pass "marked ready once" || fail "mark-ready once"
grep -q '\*\*deferred\*\*' "$SKILL" && pass "quiet hours defer reviewer-facing actions" || fail "quiet-hours deferral"
grep -q 'Fixes, gates and pushes never wait' "$SKILL" && pass "pushes continue in quiet hours" || fail "pushes in quiet hours"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
