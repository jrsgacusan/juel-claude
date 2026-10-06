#!/bin/sh
# Guards on skills/receive-review-and-execute/SKILL.md: unattended mode never asks and never half-executes.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/receive-review-and-execute/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }

grep -q '| `--unattended` | off |' "$SKILL" && pass "flag documented" || fail "flag documented"
grep -q 'print `CONFLICT: <each conflicted file>` and stop' "$SKILL" && pass "conflict reported, not asked" || fail "conflict handling"
grep -q 'do not execute anything, including the' "$SKILL" && pass "no partial execution on ambiguity" || fail "ambiguity stops execution"
grep -q 'AMBIGUOUS: <author> <file:line>' "$SKILL" && pass "ambiguous findings reported" || fail "AMBIGUOUS line"
grep -q 'Ask via\|ask via' "$SKILL" && pass "interactive path kept" || fail "interactive path"

grep -q 'prints `STOPPED: <reason>`' "$SKILL" && pass "every unattended stop is reported" || fail "STOPPED line"
grep -q '| AskUserQuestion | context | HARD |' "$SKILL" && pass "interactive runs still stop headless" || fail "AskUserQuestion HARD"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
