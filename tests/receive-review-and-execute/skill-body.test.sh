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
grep -q 'fleet' "$SKILL" && fail "no fleet wording" || pass "no fleet wording"
grep -q '| `--brief <path>` |' "$SKILL" && pass "S5 brief accepted" || fail "S5 --brief"
grep -q 'BRIEF-VIOLATION:' "$SKILL" && pass "S5 out-of-scope requests stop" || fail "S5 BRIEF-VIOLATION"
grep -q '| `--only <ids>` |' "$SKILL" && pass "S14 only listed items acted on" || fail "S14 --only"
grep -q 'gate-lock.sh' "$SKILL" && pass "T9 executor heavy commands locked" || fail "T9 executor lock"
# Stress test pass fixes
grep -q 'STOPPED: missing PR number' "$SKILL" && pass "S4 a missing PR number never asks unattended" || fail "S4 missing PR"
grep -q 'STOPPED: cannot pick a remote' "$SKILL" && pass "S4 an unclear remote never asks unattended" || fail "S4 remote"
# Final pass
grep -qF '## Decisions' "$SKILL" && pass "R1 a decision settles the finding it answers" || fail "R1 decisions not read"
grep -qF 'one command with its arguments' "$SKILL" && pass "R2 the gate line never leaves part of a command outside the lock" || fail "R2 gate command form"
grep -q 'id: orca' "$SKILL" && grep -q 'id: python3' "$SKILL" && pass "R3 orca and python3 are declared" || fail "R3 requirements"
grep -qF -- '| `--executor <session|codex>` |' "$SKILL" && pass "X5 receive-review takes the executor choice" || fail "X5 --executor"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
