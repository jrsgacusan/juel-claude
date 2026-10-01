#!/bin/sh
# Guards on skills/team/SKILL.md text that tests cannot reach by running code.
# Usage: sh tests/team/skill-body.test.sh   (exit 0 = pass)
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/team/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# Claude Code substitutes $0..$9 in a skill body with the skill's positional arguments,
# so a shell snippet using $1 silently receives a word from the user's request.
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters (\$N); the skill loader substitutes them"
else pass "no positional parameters"; fi

# A worker stuck at an interactive prompt sends no worker_done/escalation/question, so the
# wait loop alone never notices it; the skill must look at each worker's terminal.
grep -q 'stuck at a prompt' "$SKILL" && pass "stalled-worker check present" || fail "stalled-worker check missing"

# worker-release can answer `retained`; the user must hear which terminals are still open.
grep -q 'reports `retained`' "$SKILL" && pass "retained release reported" || fail "retained release not handled"

# Blind copies must redact self-identification only, never whole topical lines.
if grep -q 'Remove any line that names a model or provider' "$SKILL"; then fail "blind copy strips whole lines"
elif grep -q 'self-identification' "$SKILL"; then pass "blind copy redacts self-identification only"
else fail "blind copy rule missing"; fi

# A missing claude CLI means Codex-only; the alias fallback is only for a failed listing.
grep -q 'claude not found on PATH' "$SKILL" && pass "missing claude CLI plans Codex-only" || fail "missing claude CLI falls into alias fallback"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
