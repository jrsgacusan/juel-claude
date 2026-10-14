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
grep -q 'merge-union.sh' "$SKILL" && pass "U3 mechanical conflicts are resolved before asking" || fail "U3 merge-union"
# lane e: #89 a plan's gate lines never carry --progress: the executor's sandbox cannot write STAR's folder
grep -qF 'A plan step'"'"'s `gate-lock.sh` line never carries `--progress`' "$SKILL" && pass "#89 plan gate lines never carry --progress" || fail "#89 the --progress rule for plan gate lines"
grep -qF -- '--progress <star.home>' "$SKILL" && fail "#89 a plan gate line is told to write STAR's progress log" || pass "#89 no plan gate line writes STAR's progress log"
# lane g: step 0a merges only a conflicting PR, and an outside-merged path is never restored (#109, #106)
grep -qF -- '| `--sync` | off |' "$SKILL" && pass "#109a --sync is an argument" || fail "#109a --sync is an argument"
grep -qF 'gh pr view <PR> --json mergeable --jq .mergeable' "$SKILL" && pass "#109b step 0a reads whether the PR conflicts" || fail "#109b step 0a reads whether the PR conflicts"
grep -qF '`CONFLICTING`, or `--sync` given: merge it in' "$SKILL" && pass "#109c it merges only a conflicting PR, or with --sync" || fail "#109c it merges only a conflicting PR, or with --sync"
grep -qF 'read it again up to 3 times, 10 seconds apart' "$SKILL" && pass "#109d UNKNOWN is read again" || fail "#109d UNKNOWN is read again"
grep -qF 'Base not merged: the PR is <MERGEABLE|UNKNOWN>' "$SKILL" && pass "#109e otherwise it fixes the PR head and says so" || fail "#109e otherwise it fixes the PR head and says so"
grep -qF "merges the PR's base branch in first when the PR conflicts with its base, or with --sync, then fetches" "$SKILL" && pass "#109f the description says when it merges" || fail "#109f the description says when it merges"
grep -qF -e "merge the PR's base branch in before reading anything" -e 'why: phase 2 merges the base branch and must not merge' -e "Step 0a merges the PR's base branch first;" -e '0a. Merge PR base branch\n(git' "$SKILL" && fail "#109g no reference still merges on every run" || pass "#109g no reference still merges on every run"
grep -qF 'when the PR conflicts with its base (or with `--sync`)' "$ROOT/README.md" && pass "#109h the README says when it merges" || fail "#109h the README says when it merges"
for s in execute review-and-execute receive-review-and-execute; do
  F="$ROOT/skills/$s/SKILL.md"
  grep -qF 'An `outside-merged <path>` line is never restored' "$F" && pass "#106a $s: an outside-merged path is never restored" || fail "#106a $s: an outside-merged path is never restored"
  grep -qF "in the run's summary" "$F" && pass "#106b $s: run interactively, it goes in the summary" || fail "#106b $s: run interactively, it goes in the summary"
done
for s in review-and-execute receive-review-and-execute; do
  grep -qF 'NOTE: scope outside-merged <path>' "$ROOT/skills/$s/SKILL.md" && pass "#106c $s: unattended, it is a fixed NOTE" || fail "#106c $s: unattended, it is a fixed NOTE"
done
# fix: one NOTE line names every outside-merged path (#106)
for s in review-and-execute receive-review-and-execute; do
  F="$ROOT/skills/$s/SKILL.md"
  grep -qF 'end your output with one line naming every such path,' "$F" && grep -qF '`NOTE: scope outside-merged <path>[, <path> ...]`' "$F" && pass "F106a $s: unattended, one NOTE line names every path" || fail "F106a $s: unattended, one NOTE line names every path"
  grep -qF 'NOTE: scope outside-merged <path>`' "$F" && fail "F106b $s: the NOTE is no longer per path" || pass "F106b $s: the NOTE is no longer per path"
done
# fix: step 6 pushes a merge commit only when step 0a made one (#109)
grep -qF '6. Do not push here. The merge commit, when step 0a made one, is pushed with the remediation commits.' "$SKILL" && pass "F109a step 6 pushes a merge commit only when step 0a made one" || fail "F109a step 6 pushes a merge commit only when step 0a made one"
grep -qF '6. Do not push here. The merge commit is pushed' "$SKILL" && fail "F109b step 6 no longer assumes a merge commit" || pass "F109b step 6 no longer assumes a merge commit"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
