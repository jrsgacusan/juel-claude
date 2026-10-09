#!/bin/sh
# Guards on skills/ship-ticket/SKILL.md: unattended, brief and fix modes for juel:star workers.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/ship-ticket/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
for f in '--unattended' '--brief <path>' '--quiet-hours <HH:MM-HH:MM@tz>' '--executor-model <id|latest-<family>>' '--executor-effort <level>'; do
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
grep -q 'gate.lock' "$SKILL" && pass "gate lock" || fail "gate lock"
grep -q 'kernel lock' "$SKILL" && ! grep -q 'reclaims a lock whose' "$SKILL" && pass "gate lock is a kernel lock, nothing to reclaim" || fail "gate lock description"
grep -q 'Under `--unattended`, this phase is SKIPPED' "$SKILL" && pass "phase 8 left to the coordinator" || fail "phase 8 unattended"
grep -q 'HELD item=<item> action=open a draft PR from <compare-url>' "$SKILL" && pass "no-gh unattended path" || fail "no-gh unattended path"
grep -q 'gate-lock.sh' "$SKILL" && pass "S2 gates run through gate-lock.sh" || fail "S2 gate-lock.sh"
grep -q 'Phase 5.s targeted tests' "$SKILL" && pass "S2 Phase 5 gates locked too" || fail "S2 phase 5 locked"
grep -q 'unanswered-question' "$SKILL" && pass "S4 unanswered-question escalation" || fail "S4 unanswered-question"
grep -q 'Tier C is never used' "$SKILL" && pass "S12 no interactive Tier C unattended" || fail "S12 Tier C"
grep -q 'item.path' "$SKILL" && pass "S11 file status write targets item.path" || fail "S11 item.path"
grep -q -- '-fix.md' "$SKILL" && grep -q 'Disposition:' "$SKILL" && pass "S16 every finding left unfixed has a disposition" || fail "S16 dispositions"
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
grep -q 'more than two `HELD` lines' "$SKILL" && pass "S11 held lines are aggregated" || fail "S11 HELD aggregate"
! grep -q 'JUEL_GATE_LOCK=<star.home>' "$SKILL" && grep -q '/tmp/juel.gate.<uid>.lock' "$SKILL" && pass "T1 one gate lock per user, no path to pass" || fail "T1 gate lock path"
grep -q 'A gate inside an invoked skill' "$SKILL" && pass "T8 gates inside invoked skills are covered" || fail "T8 nested gates"
grep -q 'anything but `inside` or `outside`' "$SKILL" && pass "T6 a broken quiet-hours check holds, never sends" || fail "T6 quiet helper failure"
grep -q 'ask the coordinator' "$SKILL" && grep -q 'three times' "$SKILL" && pass "a stuck worker asks the coordinator before giving up" || fail "ask when stuck"
grep -q 'anything else only a person can supply' "$SKILL" && pass "R9 needs-human-input covers what it is used for" || fail "R9 reason 6 definition"
# Final pass
g() { grep -qF -- "$2" "$SKILL" && pass "$1" || fail "$1"; }
g "W1 gates run from the manifest, never from a hand-quoted string" 'run-gates.sh'
! grep -qF "sh -c '<test command> && <lint command>'" "$SKILL" && pass "W1 the hand-quoted gate line is gone" || fail "W1 hand-quoted gate line still there"
g "W4 the gate's own exit codes are not a red gate" 'gate-unavailable'
g "W5 every invoked skill is told the run is unattended" 'Unattended run: the approved brief'
g "W6 verification steps the user gave in a decision count" 'verification steps given under `## Decisions`'
grep -q 'id: orca' "$SKILL" && pass "W7 orca is declared (a worker asks the coordinator through it)" || fail "W7 orca not declared"
# Who runs the plan
g "X1 the plan executor is a choice" '| `--executor <session|codex>` |'
g "X2 session means this session runs the plan" 'superpowers:executing-plans'
grep -qF -- '--executor' "$ROOT/skills/review-and-execute/SKILL.md" && pass "X3 review-and-execute takes the same choice" || fail "X3 review-and-execute --executor"
# STAR issues #7 to #18: reports, the screen, status
for gone in '`--screen-checks <file>`' '`--fix-review <file>`' 'VERIFIED item=' 'SCREEN path=' 'FIXED item=' 'blocked: needs you at the screen' 'Screen-check mode' 'Fix mode ('; do
  grep -qF -- "$gone" "$SKILL" && fail "removed: $gone" || pass "removed: $gone"
done
for l in 'REPORTED item=' 'RESCOPE item=<item> reason=gate review=' 'DONE item=<item> pr=<url> head=<sha> review=<path>' 'STAR-ISSUE:' 'screen-lock.sh' 'renew --holder' 'Status: skipped (STAR owns the status)' 'deliverable: report' 'screen-busy' 'Decisions made without you' 'executor-model.sh' 'codex-gate.sh' 'post-pass' 'review-unavailable' 'red-first' 'progress/<item>.log' 'Mobbin' 'context7' 'frontend-design' 'auto: playwright' 'auto: computer-use' 'gate.maxRounds' 'Resume on an existing draft PR' 'was removed in v2'; do
  grep -qF -- "$l" "$SKILL" && pass "has: $l" || fail "has: $l"
done
# Issue #26
g "I1 shared ids are reserved, not counted" 'ids.sh'
g "Z10 --floor takes the number only" '`<highest>` is the number only (40 for D-040)'
grep -qF 'When `ids.sh` exits' "$SKILL" && grep -qF 'non-zero or is missing, escalate `needs-human-input`, and never take the next number yourself' "$SKILL" && pass "Z10 an ids.sh that cannot run is escalated" || fail "Z10 an ids.sh that cannot run is escalated"
g "Z11 Codex gets the ids in the plan" 'With `executor: codex`, reserve the ids while writing the plan and put them in it.'
# Issue #33
g "E1 an existing PR is updated, not opened" 'url=<url> existing'
g "E2 its body keeps the author's text" '<!-- juel:update -->'
g "E3 never rebased or force-pushed" 'never by rebasing'
# Issue #32
g "T32a Phase 5 runs targeted tests only" 'run only the tests for the files remediation changed'
g "T32b project instructions on test scope win" 'say something else about test scope, they win'
grep -qF 'run the `test` and `lint` commands resolved in Phase 4' "$SKILL" && fail "T32c the full run after remediation is gone" || pass "T32c the full run after remediation is gone"
# Issue #21
g "T21a the evidence names its head" 'evidence head=<sha>'
g "T21b a test-only fix reuses it" 'evidence reused from <evidence head> for <HEAD>'
g "T21c any doubt runs the whole phase" 'or any doubt about a file'
# Issue #24
g "T24a a cleanup entry can be handed off" 'handed-off'
g "T24b handed-off records are listed in the PR" 'Left for you to clean up'
g "T24c and held for the user" 'action=clean up <identifier> on <service>'
grep -qF 'handed-off' "$ROOT/references/local-e2e.md" && pass "T24d rule 3 knows handed-off" || fail "T24d local-e2e rule 3"
# Task 13-15 review, round 1
g "T21d a file the app loads is runtime whatever its extension" 'is runtime whatever its extension'
grep -qF 'docs, `*.md` and `docs/`' "$SKILL" && fail "T21e every Markdown file no longer counts as outside runtime" || pass "T21e every Markdown file no longer counts as outside runtime"
g "T21f the failure row defers to the reuse case" "re-run phase 6 in full (except step 6's evidence-reuse case)"
g "T24e a PR template gets the handed-off section" 'the one section added to a template'
g "T24f an existing PR gets it inside its update section" '(plus **Left for you to clean up** when Phase 6 handed off an entry)'
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
