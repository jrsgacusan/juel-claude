#!/bin/sh
# Guards on skills/ship-ticket/SKILL.md: unattended, brief and fix modes for juel:star workers.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/ship-ticket/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
for f in '--unattended' '--brief <path>' '--quiet-hours <HH:MM-HH:MM@tz>' '--fix-review <file>'; do
  grep -q -- "$f" "$SKILL" && pass "flag $f" || fail "flag $f"
done
grep -q '## Unattended mode' "$SKILL" && pass "section" || fail "section"
grep -q 'ESCALATION item=' "$SKILL" && pass "escalation line" || fail "escalation line"
for r in 'brief-violation' 'codex-failed' 'verification-failed' 'gate-red' 'merge-conflict' 'needs-human-input' 'stack-unavailable'; do
  grep -qi "$r" "$SKILL" && pass "escalation: $r" || fail "escalation: $r"
done
grep -q 'gh pr create --draft' "$SKILL" && pass "draft PR under unattended" || fail "draft PR"
grep -qi 'instead of calling the provider.s `fetch`' "$SKILL" && pass "--brief skips fetch" || fail "--brief skips fetch"
grep -q 'HELD item=' "$SKILL" && pass "HELD on missing connector" || fail "HELD line"
grep -q 'Pause for explicit user confirmation between every phase' "$SKILL" && pass "interactive unchanged" || fail "interactive gating text changed"
grep -qi 'never marked PASS' "$SKILL" && pass "unverifiable never PASS" || fail "unverifiable rule"
grep -q 'Never merge the PR from this skill' "$SKILL" && pass "never merge" || fail "never merge"
grep -q 'do not invoke `juel:start`' "$SKILL" && pass "--brief bypasses juel:start" || fail "--brief bypasses juel:start"
grep -q 'once at the start' "$SKILL" && pass "quiet window checked per action" || fail "quiet window per action"
grep -q 'without `--brief` is refused' "$SKILL" && pass "unattended requires brief" || fail "unattended requires brief"
for l in 'PHASE <n> <item>' 'PR item=<item> url=<url> draft' 'DONE item=<item> pr=<url>'; do
  grep -qF "$l" "$SKILL" && pass "line $l" || fail "line $l"
done
grep -q 'reason=preflight' "$SKILL" && pass "preflight stop escalates" || fail "preflight stop escalation"
grep -q 'Clean up before escalating' "$SKILL" && pass "cleanup before escalation" || fail "cleanup before escalation"
grep -q 'gh pr create --draft --base <baseBranch>' "$SKILL" && pass "draft PR uses the brief base" || fail "draft PR base"
grep -q 'the `--brief`.s `baseBranch` → explicit argument' "$SKILL" && pass "brief base heads the chain" || fail "brief base chain"
for p in linear jira github file; do
  grep -q "^   | \`$p\` |" "$SKILL" && pass "phase 7 status row $p" || fail "phase 7 status row $p"
done
grep -q 'ship a Linear ticket' "$SKILL" && fail "description is source-neutral" || pass "description is source-neutral"
for gone in 'REVIEW-FINDINGS' 'CONTINUE item=' 'ACK <item>' 'fleet-ship-tickets'; do
  grep -q -- "$gone" "$SKILL" && fail "removed: $gone" || pass "removed: $gone"
done
grep -q 'first line of the `worker_done` body' "$SKILL" && pass "report rides worker_done" || fail "worker_done body"
grep -q 'FIXED item=<item> head=<sha>' "$SKILL" && pass "fix mode line" || fail "FIXED line"
grep -q 'Phases 1–3 are SKIPPED' "$SKILL" && pass "fix mode skips planning" || fail "fix mode phases"
grep -q 'gate.lock' "$SKILL" && pass "gate lock" || fail "gate lock"
grep -q 'kernel lock' "$SKILL" && ! grep -q 'reclaims a lock whose' "$SKILL" && pass "gate lock is a kernel lock, nothing to reclaim" || fail "gate lock description"
grep -q 'Under `--unattended`, this phase is SKIPPED' "$SKILL" && pass "phase 8 left to the coordinator" || fail "phase 8 unattended"
grep -q 'HELD item=<item> action=open a draft PR from <compare-url>' "$SKILL" && pass "no-gh unattended path" || fail "no-gh unattended path"
grep -q 'gate-lock.sh' "$SKILL" && pass "S2 gates run through gate-lock.sh" || fail "S2 gate-lock.sh"
grep -q 'Phase 5.s `test` and `lint`' "$SKILL" && pass "S2 Phase 5 gates locked too" || fail "S2 phase 5 locked"
grep -q 'unanswered-question' "$SKILL" && pass "S4 unanswered-question escalation" || fail "S4 unanswered-question"
grep -q 'Tier C is never used' "$SKILL" && pass "S12 no interactive Tier C unattended" || fail "S12 Tier C"
grep -q 'item.path' "$SKILL" && pass "S11 file status write targets item.path" || fail "S11 item.path"
grep -q 'outcome per finding' "$SKILL" && pass "S16 fix report per finding" || fail "S16 fix outcomes"
grep -q 'older than 2 h' "$SKILL" && fail "S8 no age-only stale rule" || pass "S8 no age-only stale rule"
grep -q 'run_in_background: true' "$SKILL" && grep -q 'gate-lock.sh' "$SKILL" && grep -q 'background, like `codex exec`' "$SKILL" && pass "T1 gate runs backgrounded" || fail "T1 backgrounded gate"
grep -q 'heavy verification commands in the plan' "$SKILL" && pass "T9 executor heavy commands locked" || fail "T9 executor lock"
grep -q 'at most 12 lines' "$SKILL" && pass "report capped at 12 lines" || fail "12-line cap"
grep -q 'GATES <path>' "$SKILL" && pass "gate manifest written to a file" || fail "GATES path"
grep -q 'NOTE: <one line>' "$SKILL" && pass "one NOTE line allowed" || fail "NOTE line"
grep -q 'star.notes' "$SKILL" && pass "reads the memory notes first" || fail "memory notes"
grep -q 'GATES {"test":' "$SKILL" && fail "no inline gate JSON in the report" || pass "no inline gate JSON in the report"
grep -q 'item.name' "$SKILL" && pass "item named by the brief's item.name" || fail "item.name"
grep -q '## Decisions' "$SKILL" && pass "brief decisions are binding" || fail "Decisions"
grep -q 'batch-dir' "$SKILL" && fail "no stale batch-dir paths" || pass "no stale batch-dir paths"
grep -q '`always`' "$SKILL" && pass "quiet window can be always" || fail "always window"
# Stress test pass fixes
grep -q 'Nothing is asked at the terminal' "$SKILL" && pass "S4 no prompt survives unattended" || fail "S4 catch-all for prompts"
grep -q 'needs=verification steps' "$SKILL" && pass "S4 an empty checklist escalates" || fail "S4 empty checklist"
grep -q 'needs=browser verification of' "$SKILL" && pass "S4 no browser tool escalates" || fail "S4 browser fallback"
grep -q 'quiet-hours.sh' "$SKILL" && ! grep -q 'date +%H:%M' "$SKILL" && pass "S6 the quiet window is decided by the script" || fail "S6 quiet-hours.sh"
grep -q 'needs=a valid --quiet-hours window' "$SKILL" && pass "S6 an unreadable window stops the run at the start" || fail "S6 window validation"
grep -q 'gate-busy' "$SKILL" && pass "S15 a busy gate lock is bounded" || fail "S15 gate-busy"
grep -q 'the later one wins' "$SKILL" && pass "S12 contradictory decisions have an order" || fail "S12 decision precedence"
grep -q 'needs=a findings file' "$SKILL" && pass "S12 fix mode checks its findings file first" || fail "S12 fix-review preflight"
grep -q 'more than two `HELD` lines' "$SKILL" && pass "S11 held lines are aggregated" || fail "S11 HELD aggregate"
! grep -q 'JUEL_GATE_LOCK=<star.home>' "$SKILL" && grep -q '/tmp/juel.gate.<uid>.lock' "$SKILL" && pass "T1 one gate lock per user, no path to pass" || fail "T1 gate lock path"
grep -q 'A gate inside an invoked skill' "$SKILL" && pass "T8 gates inside invoked skills are covered" || fail "T8 nested gates"
grep -q "its \`round=\` is the round in the file's name" "$SKILL" && grep -q 'its `head=` is the commit this worktree is on' "$SKILL" && pass "T5 fix mode refuses a stale review" || fail "T5 fix-review freshness"
grep -q 'anything but `inside` or `outside`' "$SKILL" && pass "T6 a broken quiet-hours check holds, never sends" || fail "T6 quiet helper failure"
grep -q 'ask the coordinator' "$SKILL" && grep -q 'three times' "$SKILL" && pass "a stuck worker asks the coordinator before giving up" || fail "ask when stuck"
grep -q 'anything else only a person can supply' "$SKILL" && pass "R9 needs-human-input covers what it is used for" || fail "R9 reason 6 definition"
# Final pass
g() { grep -qF -- "$2" "$SKILL" && pass "$1" || fail "$1"; }
g "W1 gates run from the manifest, never from a hand-quoted string" 'run-gates.sh'
! grep -qF "sh -c '<test command> && <lint command>'" "$SKILL" && pass "W1 the hand-quoted gate line is gone" || fail "W1 hand-quoted gate line still there"
g "W2 fix mode checks its review with the script" 'review-proof.sh'
g "W3 a fix with nothing to change does not fail on an empty commit" 'nothing to commit'
g "W4 the gate's own exit codes are not a red gate" 'gate-unavailable'
g "W5 every invoked skill is told the run is unattended" 'Unattended run: the approved brief'
g "W6 verification steps the user gave in a decision count" 'verification steps given under `## Decisions`'
grep -q 'id: orca' "$SKILL" && pass "W7 orca is declared (a worker asks the coordinator through it)" || fail "W7 orca not declared"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
