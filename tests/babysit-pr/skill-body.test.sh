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
# Issue #27
g "Z1 an explicit zero needs no approval" '`required: 0`'
g "Z2 review bots are configurable" 'config.reviewBots'
g "Z3 a token gh lacks is escalated at once" 'gh cannot see'
# Issue #28
g "U1 mechanical conflicts go through the script" 'merge-union.sh'
grep -qF 'the mechanical resolution failed' "$SKILL" && fail "U2 a red gate after a union no longer resets and escalates" || pass "U2 a red gate after a union no longer resets and escalates"
# STAR closed loop: the gate on every push, the hosted reviewer, dispositions (#40)
for l in 'codex-gate.sh' 'post-pass' 'RESCOPE item=<item> reason=hosted-review review=' 'RESCOPE item=<item> reason=gate review=' '@greptileai' 'triggerOnUpdates' 'Disposition:' 'the way a person would' 'When you cannot tell, it is not clean' 'hosted-p<n>.md' '--executor-model' 'hostedReviewer' 'mark ready first' 'progress/<item>.log' 'stands in for this approval'; do
  grep -qF -- "$l" "$SKILL" && pass "has: $l" || fail "has: $l"
done
grep -qF 'after the second-model review said SAFE' "$SKILL" && fail "the old SAFE wording is gone" || pass "the old SAFE wording is gone"
# Final fixes C-1: a NOT-SAFE gate is fixed from its review file with the recipe of ship-ticket's gate loop,
# never through receive-review-and-execute, which reads PR comments only
gate_row=$(grep -F 'every push is gated first' "$SKILL")
[ "$(printf '%s\n' "$gate_row" | grep -c .)" -eq 1 ] && pass "C1 one table row holds the push gate" || fail "C1 one table row holds the push gate"
grow() { printf '%s\n' "$gate_row" | grep -qF -- "$2" && pass "$1" || fail "$1"; }
grow "C1a the gate's findings are read from its review file" '<star.reviews>/<item>-r<k>.md'
grow "C1b each P0 and P1 finding is validated against the brief" 'superpowers:receiving-code-review'
grow "C1c a finding outside the brief's scope is the brief-violation escalation" 'reason=brief-violation'
grow "C1d the fix is planned as a new -vN plan" '(`superpowers:writing-plans`, a new `-vN`)'
grow "C1e the plan runs on the executor and its model script" 'executor-model.sh'
grow "C1f with the capacity rule" 'capacity rule'
grow "C1g the regression gate goes through the gate lock" 'through the gate lock'
grow "C1h the round's -fix.md sits in the reviews folder" '<star.reviews>/<item>-r<k>-fix.md'
grow "C1i the push waits for a SAFE round and is never forced" 'the push waits for a SAFE round and is never forced'
printf '%s\n' "$gate_row" | grep -qF 'through `receive-review-and-execute --unattended' && fail "C1j the gate's findings no longer go through receive-review-and-execute" || pass "C1j the gate's findings no longer go through receive-review-and-execute"
g "C1k the hard rule allows the executor's fix plan for the gate" 'from a fix plan the executor runs'
# Final fixes C-2: with a hosted reviewer, a Phase 4 push that only merges the base branch in has no review of its own
# and gets no third pass, so it keeps the clean judgement and READY may follow it
hosted_row=$(grep -F 'a hosted reviewer (`hostedReviewer` set)' "$SKILL")
[ "$(printf '%s\n' "$hosted_row" | grep -c .)" -eq 1 ] && pass "C2 one table row holds the hosted reviewer" || fail "C2 one table row holds the hosted reviewer"
printf '%s\n' "$hosted_row" | grep -qF "push that only merges the base branch in keeps the hosted review's clean judgement (the codex gate re-gates that push, or carries its SAFE across a merge that brings no change to a file this branch changes, as \`carry-check.sh\` decides), so \`READY\` may follow it" && pass "C2 a base-only merge push keeps the clean judgement" || fail "C2 a base-only merge push keeps the clean judgement"
printf '%s\n' "$hosted_row" | grep -qF 'Never ask it for a third pass' && pass "C2 the third pass is still never asked for" || fail "C2 the third pass is still never asked for"
# Progress step tokens (spec 5, feeds #70)
progress_row=$(grep -F '| progress |' "$SKILL")
prow() { printf '%s\n' "$progress_row" | grep -qF -- "$2" && pass "$1" || fail "$1"; }
for t in '`phase<N>`' '`ready`' '`wait-hosted`' '`wait-ci`' '`executor`' '`regression-gate`' '`gate-r<k>`' '`post-pass`' '`sync`' '`report`'; do
  prow "P2a babysit's progress row names $t" "$t"
done
grep -qF '"<phase or wake>"' "$SKILL" && fail "P2b the free-form step field is gone" || pass "P2b the free-form step field is gone"
# Issue #60: the executor fallback reaches STAR through the report
g "N60c babysit carries the executor fallback NOTE" 'NOTE: executor skill missing, the plan ran in this session'
g "N60d the report line count includes it" 'That is 11 lines at most'
# Issues #63, #66, #71: the gate round from the worker's side
grow "G66c babysit counts verdict files only" 'error logs, raw files and run files never count'
grow "G66d babysit reruns the same round after an ERROR" 'run the same round once more'
grow "G63c babysit passes the evidence folder" '--evidence <its "evidenceDir">'
grow "G71b babysit reads only the verdict line" 'read only the last line of its output'
grow "G64b babysit quotes a gate-down line whole" 'quoted whole: an `ERROR gate-down'
# Issue #69: the build marks ready; babysit only when quiet hours kept it a draft
g "Y69f mark-ready does nothing on a ready PR" 'A PR the build already marked ready is left as it is'
g "Y69g pass 1 is the review started on ready, by either stage" 'Pass 1 is the review it started when the PR was marked ready, by the build or by this skill.'
grep -q 'Never mark it ready a second time' "$SKILL" && pass "Y69h still never marked ready twice" || fail "Y69h still never marked ready twice"
# Issue #58: a PR that turns dirty while Phase 2 waits
g "D58a a conflict wake runs the base sync" '| `conflict` |'
g "D58b any snapshot with merge dirty does too" 'a snapshot whose `merge` is `dirty`'
g "D58c behind is left to Phase 4 and the merge gate" '`behind` is not acted on here'
g "D58d the sync is counted in the report" 'base-syncs=<s>'
g "D58e a stale dirty with nothing to merge waits 60 s and looks again" 'wait 60 seconds and run the script again instead of re-entering `--wait`'
# Issue #59: a status refresh is not a pass
hosted_row=$(grep -F 'a hosted reviewer (`hostedReviewer` set)' "$SKILL")
hrow() { printf '%s\n' "$hosted_row" | grep -qF -- "$2" && pass "$1" || fail "$1"; }
hrow "S59a a synced head with no hosted status gets a refresh" '**status refresh**'
hrow "S59b it never counts toward maxPasses" 'never counts toward `maxPasses`'
hrow "S59c it is waited for before READY" 'Wait for its review of that head before `READY`'
hrow "S59d a refresh that is not clean is a failed last pass" 'as a last pass that is not clean'
g "S59e Phase 1 refreshes a head STAR sent back" 'status refresh (the hosted-reviewer row in "Unattended mode") before the first wait'
# Issue #72: a re-review that only edits the summary comment
g "H72a a hosted-pass item is judged, not answered" 'A `hosted-pass` item gets no reply'
g "H72b the wake routes it to the hosted-reviewer row" '`kind: hosted-pass`'
g "H72c babysit names its hosted reviewer to pr-state" 'Pass `--hosted <login>` to `pr-state.sh`'
g "H72d the Phase 2 wait passes it too" '[--review-bots <logins>] [--hosted <login>]'
# Issue #56: one instruction for the report's shape
g "W56c the worker_done body is the report lines only" 'The `worker_done` body is these report lines and nothing else.'
g "W56d it overrides Orca's preamble" "It overrides any request for a prose summary, Orca's worker preamble included."
# Issue #55: research MCPs
settings_row=$(grep -F '| settings |' "$SKILL")
printf '%s\n' "$settings_row" | grep -qF '`mcps`' && pass "M55e babysit reads mcps" || fail "M55e babysit reads mcps"
printf '%s\n' "$settings_row" | grep -qF 'only when your own session lists its tools' && pass "M55f only tools its own session lists" || fail "M55f only tools its own session lists"
# lane f: carry, owner carry, hosted passes, fix plans, decisions, token, lock wait, gate red (#75, #77, #78, #81, #82, #83, #88, #89, #90, #93)
gate_row=$(grep -F 'every push is gated first' "$SKILL")
grow "L75a a base-only merge push is checked by carry-check" 'sh <carry-check.sh> --from <G> --head <the merge head>'
grow "L75b the carried receipt goes through post-pass" '--carried-from <G> --reason'
grow "L75c a NO line, or no SAFE round, gets the codex round" 'no SAFE round yet'
grow "L75d post-pass refusing the carry gets the codex round" '`ERROR not carried: …`'
g "L75e Phase 4 points at the carry" 'carries the last SAFE with no codex round'
g "L75f a conflict wake's push is gated the same way" 'the push'"'"'s gate, a carry of the last SAFE when the merge brings no change to a file this branch changes, as `carry-check.sh` decides'
g "L82a an owner's carried PASS is proof" 'It prints `OK carried round=<k>` for an owner'
g "L82b both OK forms are proof" 'Both `OK` forms are proof.'
g "L82c its receipt is posted by post-pass in Phase 1" 'names a `<item>-r<k>-carried.md` file) | in Phase 1'
g "L82d never a hand-written receipt" 'never write one by hand'
hosted_row=$(grep -F 'a hosted reviewer (`hostedReviewer` set)' "$SKILL")
hrow "L93a the pass record" '<star.reviews>/<item>-hosted.log'
hrow "L93b passes are counted from the file" 'a restarted run counts them from the file, never from memory'
hrow "L93c the last pass reviews a current head" 'so the last pass reviews a head that is current with the base'
hrow "L93d refreshOutsideCap false escalates" 'reason=hosted-cap'
settings_row=$(grep -F '| settings |' "$SKILL")
printf '%s\n' "$settings_row" | grep -qF '`refreshOutsideCap`, true when absent' && pass "L93e settings name refreshOutsideCap" || fail "L93e settings name refreshOutsideCap"
g "L93f Phase 1's refresh honours the setting" 'false and every pass used'
gate_row=$(grep -F 'every push is gated first' "$SKILL")
grow "L81e babysit's gate fix plan carries a Base line" '`**Base:** spec implemented at <the full head>; apply only the tasks below.`'
grow "L78d babysit's gate fix plan names its files" 'name their files in a `**Files:**` block'
grow "L78e babysit runs the scope check after the plan" 'sh <scope-check.sh> <the plan> <the head before the executor> --before <that record file>'
grow "L77d babysit's capacity retries resume from the ledger" "each try resumes from the plan's ledger"
grow "L81f the in-session run is told the Base line wins" "The plan's Base line overrides its Spec"
g "L88a gh cannot see reads the notes for a token rule first" 'may name a `GH_TOKEN` rule'
g "L88b the token prefix goes on every later GitHub command" 'an `export` does not outlive one shell call'
g "L88c tokenCmd is named as the lasting fix" 'the plugin'"'"'s session hook already gives every session the token'
g "L90c a red fixed outside runtime is refunded" 'A red is refunded, and does not count toward the two'
g "L90d the Phase 4 red row counts the same way" 'counted as the row above counts them'
g "L89d babysit's gate lock reports its wait" '--progress <star.home>/progress/<item>.log -- sh <run-gates.sh>'
g "L83c decisions are read after every background step" '| after every background step (an executor run, a gate round, the regression gate, a CI poll, a Phase 2 wake) |'
g "L83d through orca's unread messages" 'orca orchestration check --unread --json'

# lane h: reviewer mode
review_mode=$(awk '/^## Reviewer mode/ { f = 1; next } /^## / { f = 0 } f' "$SKILL")
rv() { printf '%s\n' "$review_mode" | grep -qF -- "$2" && pass "$1" || fail "$1"; }
g "RV1 another author is reviewer mode" 'Any other author is **reviewer mode**'
g "RV2 the description names reviewer mode" 'it runs reviewer mode instead'
g "RV3 threads are resolved only by review-pr's gated post" 'resolved only by `juel:review-pr`'
rv "RV4 STAR never runs it" 'STAR never runs reviewer mode'
rv "RV5 it needs a review of yours first" 'Review it first with /juel:review-pr'
rv "RV6 a dirty tree is never discarded" 'never discard them'
rv "RV7 it never pushes" 'It never commits, pushes, merges, runs gates or edits the author'
rv "RV8 it waits as a reviewer" '--as-reviewer <you> --reviewed-head <reviewed head> --settle-minutes 30'
rv "RV9 a re-request wakes it" '`rerequested`'
rv "RV10 a settled head wakes it" '`settled`'
rv "RV11 it follows a force-push" 'gh pr checkout <pr> --force'
rv "RV12 each round runs review-pr" '/juel:review-pr --pr <pr> --since <reviewed head> --from-babysit'
rv "RV13 the cursor moves after every round" 'set the cursor to now'
rv "RV14 an approval ends it" '`REVIEW-PR posted verdict=APPROVE'
rv "RV15 not posted moves the reviewed head" '`REVIEW-PR not-posted head=<sha>`'
rv "RV16 a moved head waits to settle" '`REVIEW-PR head-moved'
rv "RV17 a stop is reported" '`REVIEW-PR stopped reason=<why>`'
rv "RV18 Phase 4 has nothing to push" 'SKIPPED: "reviewer mode: nothing to push"'
g "RV19 review-pr is a HARD dependency" '| juel:review-pr | skill | HARD |'
g "RV20 an interactive user is a SOFT context" '| interactive user | context | SOFT |'
g "RV21 --reviewed accepts the owner's carried proof" '`<item>-r<k>-carried.md` when the owner shipped'
rv "RV22 the snapshot's cursor is never taken" 'never takes the `cursor` the snapshot prints'

# review fixes: reviewer-mode waits and stops (R10, R12, R13), the gate fix plan's scope check (#78), the gate lock's holder (#76), carried proof and the carry round (#75)
review_mode=$(awk '/^## Reviewer mode/ { f = 1; next } /^## / { f = 0 } f' "$SKILL")
rv "R10a every reviewer-mode wait after the first passes the settle sighting" 'Every wait after the first passes `--head-seen <the last snapshot'"'"'s head_seen>`, in both forms'
rv "R10b that covers the waits after errors and silence" 'after `errors`, `silence` or `timeout`'
printf '%s\n' "$review_mode" | grep -qF 'and `--head-seen <the last snapshot'"'"'s head_seen>` on every repeat' && fail "R10c the Codex-only head-seen wording is gone" || pass "R10c the Codex-only head-seen wording is gone"
rv "R12a silence names what the wait is for" 'no re-request or settled push for 72 h, still waiting'
printf '%s\n' "$review_mode" | grep -qF 'no response from the author for 72 h' && fail "R12b the author-response wording is gone" || pass "R12b the author-response wording is gone"
rv "R13a an unattended run prints the stop as an escalation" 'ESCALATION item=<item> phase=8 reason=preflight needs=the PR'"'"'s author is <login>: reviewer mode runs only interactively'
gate_row=$(grep -F 'every push is gated first' "$SKILL")
grow "R1a babysit records what is already changed before the executor" 'sh <scope-check.sh> --record "$(git rev-parse --git-path juel_scope_before)"'
grow "R1b the record is taken right before the executor runs" 'Right before the executor runs'
grow "R1c the check reads that record" 'sh <scope-check.sh> <the plan> <the head before the executor> --before <that record file>'
grow "R1d a file in the record is never outside" 'a file in the record is never `outside`'
grow "R1e an unchecked plan is reported and passed" '`unchecked …` means nothing was checked: say so in the round'"'"'s evidence line and go on'
gates_row=$(grep -F '| gates run directly |' "$SKILL")
[ "$(printf '%s\n' "$gates_row" | grep -c .)" -eq 1 ] && pass "R4a one table row holds the direct gate run" || fail "R4a one table row holds the direct gate run"
printf '%s\n' "$gates_row" | grep -qF -- '--holder "<star.project>/<item>"' && pass "R4b under a star brief the lock holder names the project" || fail "R4b under a star brief the lock holder names the project"
printf '%s\n' "$gates_row" | grep -qF 'without a `star:` brief, leave out `--progress` and use `--holder "<item>"`' && pass "R4c without a star brief it stays the item" || fail "R4c without a star brief it stays the item"
grow "R11a the carry names the round of G's review" '`<g>` is the round of G'"'"'s review'
grow "R11b the carried receipt posts G's round" 'post-pass --pr <url> --round <g> --head <the pushed head>'
grow "R11c the codex round keeps its own count" 'Round `k` is 1 plus the highest `k`'
markready_row=$(grep -F '| `--mark-ready` on a draft PR |' "$SKILL")
[ "$(printf '%s\n' "$markready_row" | grep -c .)" -eq 1 ] && pass "R9a one table row holds the mark-ready proof" || fail "R9a one table row holds the mark-ready proof"
mrow() { printf '%s\n' "$markready_row" | grep -qF -- "$2" && pass "$1" || fail "$1"; }
mrow "R9b a NO may be a merge made after the review" 'A `NO …` is not final yet when the head is a merge of the base branch made after the review'
mrow "R9c the newest SAFE review is the starting point" 'the newest `<star.reviews>/<item>-r<k>.md` says `SAFE`'
mrow "R9d carry-check judges the current head" 'sh <carry-check.sh> --from <its head=> --head <the PR'"'"'s current headRefOid> --base <remote>/<base>'
mrow "R9e a carry is proof as well" '`OK carried from …` is proof as well'
mrow "R9f any other NO still escalates" 'Any other `NO …`'
mrow "R9g the deferred ready re-checks the proof" 'again right before a deferred'

# lane g: step 0a, the hosted log, the round count, messages, gate once per PR, CI and dependencies (#109, #96, #108, #99, #97, #102, #105)
g "#109i babysit's Phase 3 merges the base only when the PR conflicts" 'It merges the base branch in only when the PR conflicts with it (a `behind` PR is synced in Phase 4)'
g "#96a Phase 1 rebuilds a missing hosted log from the PR" 'sh <script> <pr> --hosted <login> --hosted-passes > <log>.tmp'
g "#96b an error line writes no file" 'An `error` line writes no file'
g "#96c a second error is the pr-state-errors escalation" 'A second `error` → `ESCALATION item=<item> phase=8 reason=pr-state-errors'
g "#96d a missing log is never zero passes" 'A missing log is never read as zero passes.'
hosted_row=$(grep -F 'a hosted reviewer (`hostedReviewer` set)' "$SKILL")
hrow "#96e the hosted row says how the record is rebuilt" 'A missing file is rebuilt from the PR in Phase 1 step 9'
g "#96f the hosted refresh is step 10" '10. Under a `star:` brief with a hosted reviewer: when the PR'"'"'s head has no status'
g "#96g reviewer mode skips both steps" '9 (the hosted log) and 10 (the hosted refresh) do not apply'
gate_row=$(grep -F 'every push is gated first' "$SKILL")
grow "#108a NOT-SAFE rounds count from the newest SAFE round or the last push" 'NOT-SAFE rounds are counted since the newest SAFE round or the last push, whichever is later.'
grow "#108b an unpushed SAFE round starts a fresh count" 'A SAFE round that could not be pushed, because the PR needed a base merge first, starts a fresh count.'
printf '%s\n' "$gate_row" | grep -qF 'NOT-SAFE round for this push' && fail "#108c the per-push count is gone" || pass "#108c the per-push count is gone"
g "#99a messages are read only with --json" 'Read messages only with `--unread --json` (or `--peek --json` to look without consuming them).'
g "#99b a body a plain check consumed is read back" 'if that happened, run `orca orchestration check --all --json` and read the bodies'
grep -oE 'orchestration check[^`]*' "$SKILL" | grep -vxF 'orchestration check' | grep -vqF -- '--json' && fail "#99c every orchestration check carries --json" || pass "#99c every orchestration check carries --json"
phase() { awk -v h="## Phase $1:" 'index($0, h) == 1 { f = 1; next } /^## / { f = 0 } f' "$SKILL"; }
phase 3 | grep -qF 'Gate the round as `juel:ship-ticket`'"'"'s "Gate once per PR" says' && pass "#97a Phase 3 gates a round once per PR" || fail "#97a Phase 3 gates a round once per PR"
phase 3 | grep -qF -- '--root <repo root> sweep' && pass "#97b a round runs the sweep" || fail "#97b a round runs the sweep"
phase 4 | grep -qF 'Gate the push as `juel:ship-ticket`'"'"'s "Gate once per PR" says' && pass "#97c Phase 4 gates the push once per PR" || fail "#97c Phase 4 gates the push once per PR"
phase 4 | grep -qF 'and none after a clean merge' && fail "#97d a clean base merge no longer skips the tests" || pass "#97d a clean base merge no longer skips the tests"
grep -qF 'Run every gate' "$SKILL" && fail "#97e no step runs every gate on every push" || pass "#97e no step runs every gate on every push"
g "#97f the conflict wake runs what step 3 asks of a base-only merge push" 'the tests step 3 asks of a push that only merges the base'
gate_row=$(grep -F 'every push is gated first' "$SKILL")
grow "#97g a carried merge runs what Phase 4 step 3 asks of a base-only merge push" 'no codex round: run the tests Phase 4 step 3 asks of a push that only merges the base branch in'
grow "#97h a gate fix round runs its tests and the sweep" 'Then run the tests for the files the plan changed and the sweep through the gate lock'
printf '%s\n' "$gate_row" | grep -qF 'the regression gate through the gate lock' && fail "#97i no full gate on a carry or a fix round" || pass "#97i no full gate on a carry or a fix round"
gates_row=$(grep -F '| gates run directly |' "$SKILL")
printf '%s\n' "$gates_row" | grep -qF 'The sweep is the same `run-gates.sh` line with `sweep` after `--root <repo root>`' && pass "#102a the sweep runs through the gate lock" || fail "#102a the sweep runs through the gate lock"
ci_row=$(grep -F 'wait for CI and the approval' "$SKILL")
crow() { printf '%s\n' "$ci_row" | grep -qF -- "$2" && pass "$1" || fail "$1"; }
crow "#102b no CI only when the base head has none either" "only when the base branch's head has no check runs either"
crow "#102c it reads the base head's check runs" 'commits/<base>/check-runs --jq .total_count'
crow "#102d a PR that is not DIRTY escalates ci-missing" 'reason=ci-missing cursor=<last cursor> needs=no CI ran on head <sha> (PR <mergeStateStatus>)'
crow "#102e a DIRTY PR is the conflict wake first" 'On a `DIRTY` PR the `conflict` wake acts first'
crow "#102f and the report carries the NOTE" 'NOTE: no CI ran on head <sha7> (PR DIRTY)'
printf '%s\n' "$ci_row" | grep -qF 'and "this repo has no CI" after that' && fail "#102g a head with no checks is no longer read as no CI" || pass "#102g a head with no checks is no longer read as no CI"
report_row=$(grep -F '| Phase 5 report |' "$SKILL")
printf '%s\n' "$report_row" | grep -qF '`NOTE: no CI ran on head <sha7> (PR DIRTY)` once' && pass "#102h the report lists the NOTE" || fail "#102h the report lists the NOTE"
g "#105a Phase 1 checks for missing dependencies before any gate" 'Then, before any gate runs, check for missing dependencies'
g "#105b it runs the install once" 'When one is missing, run the install command once'
g "#105c a failed install is gate-unavailable" 'reason=gate-unavailable needs=dependencies did not install: <one line>'
gates_row=$(grep -F '| gates run directly |' "$SKILL")
printf '%s\n' "$gates_row" | grep -qF 'Exit 71 with `dependencies are not installed` in its message: run the install command once' && pass "#105d exit 71 for missing dependencies installs once" || fail "#105d exit 71 for missing dependencies installs once"
printf '%s\n' "$gates_row" | grep -qF 'a second 71 is the `gate-unavailable` escalation' && pass "#105e a second 71 is gate-unavailable" || fail "#105e a second 71 is gate-unavailable"
# fix: the install step names a package.json that declares dependencies (#105)
g "F105a Phase 1 installs for a package.json that declares dependencies" 'a `package.json` at the repo root, or in a gate'"'"'s `cwd`, that declares dependencies (a non-empty'
g "F105b it names the four dependency keys and workspaces" '`dependencies`, `devDependencies`, `optionalDependencies` or `peerDependencies`, or a `workspaces` key)'
g "F105c it counts node_modules, .pnp.cjs and .pnp.js as installed" 'with no `node_modules` folder, `.pnp.cjs` or `.pnp.js` file there or in any folder above it up to the repo root.'
grep -qF 'with no `node_modules` folder and no' "$SKILL" && fail "F105d the old condition (any package.json) is gone" || pass "F105d the old condition (any package.json) is gone"
# fix: one NOTE line names every outside-merged path (#106)
report_row=$(grep -F '| Phase 5 report |' "$SKILL")
printf '%s\n' "$report_row" | grep -qF '`NOTE: scope outside-merged <path>[, <path> ...]` once, relayed from `receive-review-and-execute`' && pass "F106a the report carries the outside-merged NOTE, relayed once" || fail "F106a the report carries the outside-merged NOTE, relayed once"
printf '%s\n' "$report_row" | grep -qF 'That is 11 lines at most' && pass "F106b the report line count includes it" || fail "F106b the report line count includes it"
# lane g: a base-only merge push runs the sweep, the carry and base-moved wording (#111, #110, #113)
phase 4 | grep -qF 'branch in runs the sweep, `sh <run-gates.sh> <the --gates-file manifest> --root <repo root> sweep`' && pass "#111a a base-only merge push runs the sweep" || fail "#111a a base-only merge push runs the sweep"
phase 4 | grep -qF '`test` command), after a clean merge too: the base can change a call that an untouched file on' && pass "#111b after a clean merge too" || fail "#111b after a clean merge too"
phase 4 | grep -qF 'A red gate there keeps the merge commit and is step 3'"'"'s red,' && pass "#111c a red gate after a mechanical merge keeps the merge" || fail "#111c a red gate after a mechanical merge keeps the merge"
grep -qF 'conflict resolution changed' "$SKILL" && fail "#111d no push tests only the conflict resolution's files" || pass "#111d no push tests only the conflict resolution's files"
gate_row=$(grep -F 'every push is gated first' "$SKILL")
grow "#110a a carry needs a merge that changes no file of this branch" 'is gated by a carry when a script proves the merge brings no change to a file this branch changes'
printf '%s\n' "$gate_row" | grep -qF 'when a script proves the merge added nothing of its own' && fail "#110b the carry no longer says added nothing of its own" || pass "#110b the carry no longer says added nothing of its own"
phase 4 | grep -qF 'file this branch changes, as `carry-check.sh` decides, carries the last SAFE with no codex round.' && pass "#110c Phase 4 step 4 names carry-check's rule" || fail "#110c Phase 4 step 4 names carry-check's rule"
grow "#113a a base-moved round merges the base first" 'The gate printing `ERROR base-moved …`: the base changed a file this branch changes.'
grow "#113b it merges as Phase 4 step 1 does and runs the sweep" 'Merge it in as Phase 4 step 1 does'
grow "#113c it is not an ERROR retry" 'it is not an `ERROR` retry, never counts toward the second `ERROR`, and casts no vote toward `gate.maxRounds`.'
grow "#113d any other ERROR still waits 10 minutes" 'The gate printing any other `ERROR`: wait 10 minutes and run the same round once more'
g "#113e base-moved is the one behind merge outside Phase 4" 'A gate round that prints `ERROR base-moved` is the one case where a `behind` PR is merged outside Phase 4.'
# fix-3: babysit describes a carried merge as one that brings no change to a branch file, as carry-check.sh decides (#110)
carry_new='brings no change to a file this branch changes, as `carry-check.sh` decides'
grep -qF 'added nothing of its own' "$SKILL" && fail "fix-3 M8a no row says a carried merge added nothing of its own" || pass "fix-3 M8a no row says a carried merge added nothing of its own"
printf '%s\n' "$markready_row" | grep -qF "no codex round is spent on a merge that $carry_new" && pass "fix-3 M8b the mark-ready row names carry-check's rule" || fail "fix-3 M8b the mark-ready row names carry-check's rule"
[ "$(printf '%s\n' "$hosted_row" | grep -oF -- "$carry_new" | wc -l | tr -d ' ')" -eq 2 ] && pass "fix-3 M8c the hosted-reviewer row names carry-check's rule twice" || fail "fix-3 M8c the hosted-reviewer row names carry-check's rule twice"
conflict_row=$(grep -F '| `conflict` |' "$SKILL")
printf '%s\n' "$conflict_row" | grep -qF "a carry of the last SAFE when the merge $carry_new" && pass "fix-3 M8d the conflict row names carry-check's rule" || fail "fix-3 M8d the conflict row names carry-check's rule"

# #122: one hosted pass per head
g "B122a a second run on a passed head is a refresh (#122)" 'A second hosted run on a head that already has a `pass` line in `<item>-hosted.log`'
g "B122b it never counts: a head gets at most one pass line (#122)" 'is logged as `refresh head=<sha>` and never counted as a pass, so a head gets at most one `pass` line (#122)'
g "B122c passes are counted per distinct head (#122)" 'Passes are counted per distinct head: the passes used are the distinct heads with a `pass` line in that file'
g "B122d the last pass reads distinct heads (#122)" 'the record holds `pass` lines for `maxPasses` minus 1 distinct heads'
grep -qF 'The passes used are the `pass` lines in that file' "$SKILL" && fail "B122e the raw pass-line count is gone (#122)" || pass "B122e the raw pass-line count is gone (#122)"
# #123: progress lines come only from the step they name
g "B123a a progress line comes only from its own step (#123)" 'A progress line is written only by the step it names, at that step, never by a background or detached timer loop the worker starts'
g "B123b gate-lock.sh --progress stays the one repeating writer (#123)" '`gate-lock.sh --progress` stays the one writer that repeats, since it lives only as long as the gate it waits for'
g "B120a the base sync names the edit next to an insertion (#120)" 'to one list), or one side inserted lines right after a line the other side edited (#120), or'

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
