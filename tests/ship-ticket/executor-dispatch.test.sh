#!/bin/sh
# Every codex exec plan dispatch runs on the model executor-model.sh resolves, keeps --sandbox
# right after `codex exec` (validate.mjs check 8 finds sites by that prefix), and has a capacity rule.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
for s in ship-ticket review-and-execute receive-review-and-execute execute; do
  F="$ROOT/skills/$s/SKILL.md"
  lines=$(grep -E '^codex exec ' "$F")
  [ -n "$lines" ] || { fail "$s has no codex exec line"; continue; }
  printf '%s\n' "$lines" | grep -vqE '^codex exec --sandbox workspace-write -m <model> -c model_reasoning_effort="<effort>" ' && fail "$s: a dispatch line without the resolved model" || pass "$s: every dispatch line carries the resolved model"
  grep -q 'executor-model.sh' "$F" && pass "$s: resolves the model with executor-model.sh" || fail "$s: executor-model.sh"
  grep -q 'At capacity' "$F" && grep -q 'fallback model' "$F" && pass "$s: has the capacity rule" || fail "$s: capacity rule"
done
for s in review-and-execute receive-review-and-execute; do
  grep -qF -- '| `--executor-model <id|latest-<family>>` |' "$ROOT/skills/$s/SKILL.md" && pass "$s takes --executor-model" || fail "$s --executor-model"
done
# Issues #57 and #60
for s in ship-ticket review-and-execute receive-review-and-execute execute; do
  F="$ROOT/skills/$s/SKILL.md"
  grep -E '^codex exec ' "$F" | grep -vqF '<add-dirs>' && fail "#57 $s: a dispatch line without <add-dirs>" || pass "#57 $s: every dispatch line takes <add-dirs>"
  grep -qF -- '`--add-dir <git-dir> --add-dir <common-dir>`' "$F" && grep -qF -- '--git-common-dir' "$F" && pass "#57 $s: a linked worktree adds its git dirs" || fail "#57 $s: a linked worktree adds its git dirs"
  grep -qF 'test -f ~/.codex/skills/claude-plan-executor/SKILL.md' "$F" && pass "#60 $s: checks that the executor skill resolves" || fail "#60 $s: checks that the executor skill resolves"
  grep -qF 'Right before the line, check that the skill resolves' "$F" && pass "#60 $s: checks again right before each dispatch" || fail "#60 $s: checks again right before each dispatch"
done
for s in ship-ticket review-and-execute receive-review-and-execute; do
  F="$ROOT/skills/$s/SKILL.md"
  grep -qF 'node <plugin root>/scripts/link-agent-skills.mjs' "$F" && pass "#60 $s: an unattended run relinks once" || fail "#60 $s: an unattended run relinks once"
  grep -qF 'NOTE: executor skill missing, the plan ran in this session' "$F" && pass "#60 $s: the session fallback is reported" || fail "#60 $s: the session fallback is reported"
done
grep -qF 'NOTE: executor skill missing' "$ROOT/skills/execute/SKILL.md" && fail "#60 execute: interactive only, it stops instead" || pass "#60 execute: interactive only, it stops instead"
# lane e: #77 #78 #81 the executor resumes from the shared ledger, stays in its Files blocks, and applies Base plans
EX="$ROOT/assets/codex-skills/claude-plan-executor/SKILL.md"
PC="$ROOT/assets/codex-skills/claude-plan-executor/references/plan-contract.md"
grep -qF '.superpowers/sdd/<plan file name without .md>/progress.md' "$EX" && grep -qF '.superpowers/sdd/<plan file name without .md>/progress.md' "$PC" && pass "#77 the executor and its contract name the shared ledger" || fail "#77 ledger path"
grep -qF 'Task <N>: complete (commits <a7>..<b7>, tests: <command> → <result>)' "$EX" && grep -qF 'Task <N>: complete (uncommitted, tests: <command> → <result>)' "$EX" && pass "#77 the executor writes the superpowers done lines" || fail "#77 done lines"
grep -qF '# SDD ledger — plan: <plan file path>' "$EX" && pass "#77 the ledger's first line is the superpowers literal" || fail "#77 identity line"
grep -qF 'Start at the first task without one.' "$EX" && grep -qF 'never apply its edits a second time' "$EX" && pass "#77 a resumed run finishes a half-applied task, never redoes it" || fail "#77 resume rule"
grep -qF 'Change only what each task'"'"'s `**Files:**` block names' "$EX" && grep -qF 'goes under a `Notes:` heading' "$EX" && pass "#78 the executor stays inside each task's Files block" || fail "#78 scope rule"
grep -qF 'into concrete code or design changes before editing' "$EX" && fail "#78 the widening heuristic is still there" || pass "#78 the widening heuristic is gone"
grep -qF '**Base:** spec implemented at <sha>; apply only the tasks below.' "$EX" && grep -qF 'never stop because the' "$EX" && pass "#81 a Base plan is applied, never stopped as already done" || fail "#81 Base rule in the executor"
grep -qF '**Base:** spec implemented at <full sha>; apply only the tasks below.' "$PC" && pass "#81 the contract documents the Base line" || fail "#81 Base line in the contract"
grep -qF '`**Files:**` block per task' "$PC" && pass "#78 the contract requires a Files block per task" || fail "#78 Files block in the contract"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
