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
grep -q 'whose approval is for an older commit' "$SKILL" && ! grep -q 'submitted after the last commit' "$SKILL" && pass "T8 stale approval judged by commit, re-requested" || fail "T8 stale approval"
grep -q 'background, like `codex exec`' "$SKILL" && pass "T1 gates run backgrounded" || fail "T1 backgrounded gates"
grep -q 'at most 12 lines' "$SKILL" && pass "report capped at 12 lines" || fail "12-line cap"
grep -q 'DRAFT <path>' "$SKILL" && grep -q 'candidate decisions' "$SKILL" && pass "ambiguous review comes with a draft" || fail "DRAFT on ambiguous review"
grep -q 'MERGED item=<item> pr=<url>' "$SKILL" && pass "a merge seen while babysitting is reported" || fail "MERGED report"
grep -q 'cursor=<last cursor>' "$SKILL" && grep -q 'ESCALATION item=<item> phase=8 reason=<reason> cursor=' "$SKILL" && pass "escalations carry the cursor" || fail "escalation cursor"
grep -q 'one `HELD` line for all deferred' "$SKILL" && pass "deferred actions fit the 12-line cap" || fail "aggregate HELD"
grep -q 'star.notes' "$SKILL" && grep -q '## Decisions' "$SKILL" && pass "reads notes and decisions first" || fail "notes and decisions"
grep -q 'SENT replies=<n> review-requests=<m>' "$SKILL" && pass "reports what it sent" || fail "SENT line"
# Stress test pass fixes
grep -q '| `--reviewed <path>` |' "$SKILL" && grep -q 'reason=no-safe-verdict' "$SKILL" && pass "S5 mark-ready needs a SAFE review on this head" || fail "S5 SAFE proof"
grep -q 'quiet-hours.sh' "$SKILL" && ! grep -q 'date +%H:%M' "$SKILL" && grep -q '`always`' "$SKILL" && pass "S6 the quiet window is decided by the script" || fail "S6 quiet-hours.sh"
grep -q 'reason=ci-stuck' "$SKILL" && pass "S15 the CI wait is bounded" || fail "S15 ci-stuck"
grep -q 'reason=gate-busy' "$SKILL" && pass "S15 a busy gate lock is bounded" || fail "S15 gate-busy"
grep -q 'commit.oid' "$SKILL" && pass "S8 approvals are matched to the head commit" || fail "S8 approval by commit"
grep -q 'Under `--unattended`: `git merge --abort`' "$SKILL" && pass "S4 final-sync conflict never asks" || fail "S4 phase 4 conflict"
grep -q 'never dropped to fit' "$SKILL" && pass "S11 the report keeps what STAR needs" || fail "S11 report priority"
! grep -q 'JUEL_GATE_LOCK=<star.home>' "$SKILL" && pass "T1 no gate lock path to pass" || fail "T1 gate lock path"
grep -q 'taken from the repo root' "$SKILL" && ! grep -q '(cd <cwd> && <cmd>)' "$SKILL" && pass "T9 each gate runs from the repo root" || fail "T9 gate cwd"
grep -q 'at least 7 characters' "$SKILL" && grep -q 'newest review file' "$SKILL" && pass "T5 the SAFE proof must be exact and current" || fail "T5 SAFE proof"
grep -q 'anything but `inside` or `outside`' "$SKILL" && pass "T6 a broken quiet-hours check holds, never sends" || fail "T6 quiet helper failure"
grep -q '| `draft` |' "$SKILL" && grep -q 'reason=pr-draft-again' "$SKILL" && grep -q "the snapshot's \`base\`" "$SKILL" && pass "T6 a PR made draft again or retargeted is not reported ready" || fail "T6 draft and base"
grep -q 'reason=blocked-without-feedback' "$SKILL" && pass "T13 a bot-only block does not wait 72 hours" || fail "T13 bot-only block"
grep -q 'ask the coordinator' "$SKILL" && pass "a stuck worker asks the coordinator before giving up" || fail "ask when stuck"
grep -q 'again right before a deferred' "$SKILL" && pass "R3 a deferred mark-ready re-checks the proof" || fail "R3 deferred mark-ready"
# Final pass
g() { grep -qF -- "$2" "$SKILL" && pass "$1" || fail "$1"; }
g "B1 gates run from the manifest, never from a hand-quoted string" 'run-gates.sh'
g "B2 the SAFE proof is checked by the script" 'review-proof.sh'
g "B3 an approved PR waits out the quiet window without spinning" '--hold-approval'
g "B4 escalations carry the cursor the round started from" 'the cursor this round started from'
g "B5 READY waits for checks whether or not Phase 4 pushed" 'whether or not Phase 4 pushed'
g "B5 a head with no checks yet is not green at once" 'no checks reported'
g "B6 the approval rule matches the final check" 'latest review'
g "B7 a draft is never reported ready" 'before `READY`'
g "B8 the cursor is passed back as it is" 'opaque'
g "B9 the report starts with its state line" 'body starts with it'
grep -q 'id: orca' "$SKILL" && pass "B10 orca is declared" || fail "B10 orca not declared"
g "X4 babysit passes the executor choice on" '--executor'
grep -qF 'STAR-ISSUE: <one line>' "$SKILL" && pass "babysit can report friction with STAR" || fail "STAR-ISSUE line"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
