#!/bin/sh
# Guards on skills/ship-tickets/SKILL.md: the local Orca coordinator.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/ship-tickets/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }

if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
grep -q '^name: ship-tickets$' "$SKILL" && pass "name" || fail "name"
grep -q 'juel:protocol v7' "$SKILL" && pass "protocol block" || fail "protocol block"
grep -q 'id: orca-terminal' "$SKILL" && pass "Orca terminal precondition" || fail "Orca terminal precondition"
grep -qi 'Approve / Edit / Drop' "$SKILL" && pass "brief approval" || fail "brief approval"
grep -q '"maxParallel": 3' "$SKILL" && grep -q '"maxInReview": 3' "$SKILL" && pass "pool defaults" || fail "pool defaults"
grep -q 'caffeinate' "$SKILL" && pass "keeps the Mac awake" || fail "caffeinate"
grep -q -- '--timeout-ms 540000' "$SKILL" && pass "bounded waits" || fail "bounded waits"
for s in queued building pr-draft reviewing fixing babysitting ready done escalated failed; do
  grep -q "\`$s\`" "$SKILL" && pass "state $s" || fail "state $s"
done
for c in '/juel:ship-ticket --unattended --brief' '--fix-review' '/juel:babysit-pr <n> --unattended --mark-ready --item <item>' 'VERDICT item=<item> round=<k>'; do
  grep -qF -- "$c" "$SKILL" && pass "stage: $c" || fail "stage: $c"
done
# Worktree is created and renamed before the build worker starts.
c=$(grep -n 'orca worktree create' "$SKILL" | head -1 | cut -d: -f1)
r=$(grep -n 'branch -m' "$SKILL" | head -1 | cut -d: -f1)
w=$(grep -n 'worker-start --task' "$SKILL" | head -1 | cut -d: -f1)
[ -n "$c" ] && [ -n "$r" ] && [ -n "$w" ] && [ "$c" -lt "$r" ] && [ "$r" -lt "$w" ] && pass "worktree created, renamed, then the worker starts" || fail "create/rename/start order ($c $r $w)"
grep -q 'free + inactive' "$SKILL" && grep -q '3 GB' "$SKILL" && pass "memory check" || fail "memory check"
grep -q 'lacks the line its stage owes' "$SKILL" && pass "missing line is failed" || fail "missing-line rule"
grep -q 'run-use --id' "$SKILL" && pass "resume rebinds" || fail "resume rebinds"
grep -q 'worker-release --dispatch' "$SKILL" && pass "workers released" || fail "worker-release"
grep -q 'PushNotification' "$SKILL" && pass "notifies the user" || fail "notification"
grep -q '30 min' "$SKILL" && pass "unanswered questions escalate" || fail "question timeout"
grep -q 'isDraft,reviewDecision,reviews,commits,headRefOid,mergeable,statusCheckRollup' "$SKILL" && pass "exact-head check" || fail "exact-head check"
grep -qi 'Never merge' "$SKILL" && pass "never merge" || fail "never merge"
grep -q 'ship-tickets' "$ROOT/README.md" && pass "README row" || fail "README row"

# Review fixes (team test pass)
grep -q 'Never call AskUserQuestion inside the loop' "$SKILL" && pass "S4 questions never block the loop" || fail "S4 non-blocking questions"
grep -q 'processed.log' "$SKILL" && pass "S3 processed messages recorded" || fail "S3 processed.log"
grep -q 'Write the row before every `task-create`' "$SKILL" && pass "S3 intent persisted before starts" || fail "S3 intent before start"
grep -q 'matches no ledger row' "$SKILL" && pass "S3 unmatched messages kept" || fail "S3 unmatched messages"
grep -q '`verifying`' "$SKILL" && pass "S6 verifying state" || fail "S6 verifying state"
grep -q 'settled without a processed `worker_done`' "$SKILL" && pass "S7 settled-without-report reconciled" || fail "S7 settlement reconciliation"
grep -q '`babysit-queued`' "$SKILL" && pass "S9 restarts go through the review pool" || fail "S9 babysit-queued"
grep -q 'pwd -P' "$SKILL" && grep -q 'absolute' "$SKILL" && pass "S10 absolute batch paths" || fail "S10 absolute BATCH"
grep -q '  path: <absolute path' "$SKILL" && pass "S11 file items carry their path" || fail "S11 item.path"
grep -q -- '--gates-file <BATCH>/gates/<item>.json' "$SKILL" && pass "S12 gates passed to babysit" || fail "S12 gates handoff"
grep -q 'notify: pending' "$SKILL" && pass "S15 notification state persisted" || fail "S15 notify marker"
grep -q '<item>-r<k>-fix.md' "$SKILL" && pass "S16 fix report reaches the next reviewer" || fail "S16 fix report"
grep -q 'Save every reviewer body' "$SKILL" && pass "S17 every review saved first" || fail "S17 save first"
grep -q 'command -v <agent>' "$SKILL" && pass "S18 worker CLIs checked in preflight" || fail "S18 agent CLI check"
grep -q 'ps -p <pid> -o comm=' "$SKILL" && pass "S19 caffeinate reconciled" || fail "S19 caffeinate"
grep -q 'empty string' "$SKILL" && pass "S20 empty reviewDecision normalized" || fail "S20 empty decision"
grep -q '`default` means: pass neither `--model` nor `--effort`' "$SKILL" && pass "S22 default model sentinel" || fail "S22 default sentinel"
grep -q -- '--brief <BATCH>/briefs/<item>.md --gates' "$SKILL" && pass "S5 babysit gets the brief" || fail "S5 babysit brief"
# Third test pass
grep -q 'Write the whole ledger right after each message' "$SKILL" && pass "T3 ledger written per message" || fail "T3 per-message ledger write"
grep -q -- '-fix-receipt.md' "$SKILL" && pass "T4 fix file never overwritten" || fail "T4 fix receipt"
grep -q 'retry-not-before' "$SKILL" && pass "T5 verification retry waits a tick" || fail "T5 retry-not-before"
grep -q 'SAFE` | state `babysit-queued`' "$SKILL" && pass "T6 SAFE queues babysitting" || fail "T6 SAFE → babysit-queued"
grep -q 'and release its dispatch' "$SKILL" && pass "T7 silent settlement releases" || fail "T7 release on settlement"
grep -q 'git show-ref --verify' "$SKILL" && pass "T12 existing branch handled" || fail "T12 existing branch"
grep -q 'ls-files --others' "$SKILL" && pass "T12 only untracked .claude files copied" || fail "T12 .claude copy"
grep -q "find . -maxdepth 1" "$SKILL" && pass "T14 no-match-safe copy" || fail "T14 find copy"
grep -q 'No answer during quiet hours' "$SKILL" && pass "T13 quiet-hours questions escalate at once" || fail "T13 quiet questions"
grep -q 'gates/<item>.json' "$SKILL" && grep -q -- '--gates-file' "$SKILL" && pass "T11 gate manifest" || fail "T11 gate manifest"
sed -n '/^---$/,/^---$/p' "$SKILL" | grep -q 'id: claude' && pass "T17 claude CLI declared" || fail "T17 claude CLI"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
