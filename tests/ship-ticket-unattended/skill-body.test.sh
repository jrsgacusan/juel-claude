#!/bin/sh
# Guards on skills/ship-ticket/SKILL.md: unattended/brief mode for fleet workers.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/ship-ticket/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
for f in '--unattended' '--brief <path>' '--quiet-hours <HH:MM-HH:MM@tz>'; do
  grep -q -- "$f" "$SKILL" && pass "flag $f" || fail "flag $f"
done
grep -q '## Unattended mode' "$SKILL" && pass "section" || fail "section"
grep -q 'ACK <item> <worktree-path>' "$SKILL" && pass "ack line" || fail "ack line"
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
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
