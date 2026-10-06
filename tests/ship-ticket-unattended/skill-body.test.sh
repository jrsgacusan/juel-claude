#!/bin/sh
# Guards on skills/ship-ticket/SKILL.md: unattended, brief and fix modes for juel:ship-tickets workers.
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
grep -q 'gate.lock' "$SKILL" && grep -q 'mkdir' "$SKILL" && pass "gate lock" || fail "gate lock"
grep -q 'older than 2 h' "$SKILL" && pass "stale lock reclaimed" || fail "stale lock"
grep -q 'Under `--unattended`, this phase is SKIPPED' "$SKILL" && pass "phase 8 left to the coordinator" || fail "phase 8 unattended"
grep -q 'HELD item=<item> action=open a draft PR from <compare-url>' "$SKILL" && pass "no-gh unattended path" || fail "no-gh unattended path"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
