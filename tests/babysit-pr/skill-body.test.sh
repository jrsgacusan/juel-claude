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
grep -q 'wait for CI and the approval' "$SKILL" && pass "READY waits for CI" || fail "READY waits for CI"
grep -q 'Nothing deferred is lost' "$SKILL" && pass "deferred actions flushed or held" || fail "deferred flush"
grep -q '| `--since <iso>` |' "$SKILL" && pass "resumable cursor" || fail "--since cursor"
grep -q 'reason=no-review' "$SKILL" && pass "review wait is bounded" || fail "no-review bound"
grep -q 'when `decision` is null' "$SKILL" && pass "approval without required review" || fail "null decision approval"
grep -q 'first line of the `worker_done` body' "$SKILL" && pass "READY rides worker_done" || fail "worker_done body"
grep -q 'gate.lock' "$SKILL" && pass "unattended gates take the lock" || fail "gate lock"
grep -q 'fleet' "$SKILL" && fail "no fleet wording" || pass "no fleet wording"
grep -q 'gate-lock.sh' "$SKILL" && pass "S2 babysit gates use gate-lock.sh" || fail "S2 gate-lock.sh"
grep -q '| `--brief <path>` |' "$SKILL" && pass "S5 brief accepted" || fail "S5 --brief"
grep -q 'add-reviewer <each reviewer' "$SKILL" && pass "S13 dismissed approval re-requested" || fail "S13 re-request"
grep -q -- '--only <ids>' "$SKILL" && pass "S14 only this round's feedback" || fail "S14 --only"
grep -q '`cancel`' "$SKILL" && pass "S21 cancelled checks rejected" || fail "S21 cancel bucket"
grep -q 'empty string' "$SKILL" && pass "S20 empty decision normalized" || fail "S20 empty decision"
grep -q 'reason=unanswered-question' "$SKILL" && pass "S4 unanswered question escalates" || fail "S4 unanswered-question"
grep -q '| `--gates-file <path>` |' "$SKILL" && pass "T11 gate manifest accepted" || fail "T11 --gates-file"
grep -q 'whose approval is now older than the last commit' "$SKILL" && pass "T8 stale approval re-requested" || fail "T8 stale approval"
grep -q 'background, like `codex exec`' "$SKILL" && pass "T1 gates run backgrounded" || fail "T1 backgrounded gates"
grep -q 'at most 12 lines' "$SKILL" && pass "report capped at 12 lines" || fail "12-line cap"
grep -q 'DRAFT <path>' "$SKILL" && grep -q 'candidate decisions' "$SKILL" && pass "ambiguous review comes with a draft" || fail "DRAFT on ambiguous review"
grep -q 'MERGED item=<item> pr=<url>' "$SKILL" && pass "a merge seen while babysitting is reported" || fail "MERGED report"
grep -q 'cursor=<last cursor>' "$SKILL" && grep -q 'ESCALATION item=<item> phase=8 reason=<reason> cursor=' "$SKILL" && pass "escalations carry the cursor" || fail "escalation cursor"
grep -q 'one `HELD` line for all deferred' "$SKILL" && pass "deferred actions fit the 12-line cap" || fail "aggregate HELD"
grep -q 'star.notes' "$SKILL" && grep -q '## Decisions' "$SKILL" && pass "reads notes and decisions first" || fail "notes and decisions"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
