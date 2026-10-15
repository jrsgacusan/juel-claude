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
  grep -qF 'cmp -s ~/.codex/skills/claude-plan-executor/SKILL.md <plugin root>/assets/codex-skills/claude-plan-executor/SKILL.md' "$F" && pass "#118 $s: checks that the executor skill is this plugin's own copy" || fail "#118 $s: checks that the executor skill is this plugin's own copy"
  grep -qF 'Right before the line, check that the skill is current' "$F" && pass "#118 $s: checks again right before each dispatch" || fail "#118 $s: checks again right before each dispatch"
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

# lane e: #77 #78 #81 the three dispatching skills ignore the ledger folder, resume, scope-check and pass on Base
for s in execute review-and-execute receive-review-and-execute; do
  F="$ROOT/skills/$s/SKILL.md"
  grep -qF 'git check-ignore -q .superpowers/x' "$F" && grep -qF 'BASE_SHA=$(git rev-parse HEAD)' "$F" && pass "#77 $s: ignores the ledger folder and notes the start commit" || fail "#77 $s: ledger folder or start commit"
  grep -qF 'ledger: the tasks a stopped run finished are not done again' "$F" && pass "#77 $s: a capacity retry resumes from the ledger" || fail "#77 $s: capacity resume"
  grep -qF 'sh <scope-check.sh> <the plan'"'"'s path> "$BASE_SHA"' "$F" && grep -qF 'revert: out-of-scope edits in <files>' "$F" && pass "#78 $s: the scope check runs after the executor" || fail "#78 $s: scope check"
  grep -qF "The plan's Base line overrides its Spec: apply the tasks, and do not re-check the spec for completeness." "$F" && pass "#81 $s: the session fallback honours Base" || fail "#81 $s: Base sentence"
done
for s in review-and-execute receive-review-and-execute; do
  F="$ROOT/skills/$s/SKILL.md"
  grep -qF '**Base:** spec implemented at <full sha>; apply only the tasks below.' "$F" && pass "#81 $s: its fix plans carry the Base line" || fail "#81 $s: Base line in its plans"
  grep -qF 'Give every task a `**Files:**` block' "$F" && pass "#78 $s: its plans name each task's files" || fail "#78 $s: Files block in its plans"
done

# fix-1: R1 R5 R4 the four dispatchers record what already differs before the executor and check with --before
for s in execute review-and-execute receive-review-and-execute ship-ticket; do
  F="$ROOT/skills/$s/SKILL.md"
  grep -qF 'BEFORE=$(git rev-parse --git-path juel_scope_before)' "$F" && grep -qF 'sh <scope-check.sh> --record "$BEFORE"' "$F" && pass "#78 $s: it records the paths that already differ, right after noting the base" || fail "#78 $s: scope record"
  grep -qF -- '--before' "$F" && grep -qF 'never restore or delete a file the record lists' "$F" && pass "#78 $s: the check passes --before and never reverts the user's own work" || fail "#78 $s: --before"
  grep -qF '`unchecked the plan names no files`' "$F" && pass "#78 $s: an unchecked plan reverts nothing" || fail "#78 $s: unchecked"
done
for s in execute review-and-execute receive-review-and-execute; do
  F="$ROOT/skills/$s/SKILL.md"
  grep -qF 'sh <scope-check.sh> <the plan'"'"'s path> "$BASE_SHA" --before "$BEFORE"' "$F" && pass "#78 $s: the check line carries --before" || fail "#78 $s: check line"
done
F="$ROOT/skills/ship-ticket/SKILL.md"
grep -qF 'sh <scope-check.sh> <the plan> <that sha> --before <the record>' "$F" && pass "#78 ship-ticket: the check line carries --before" || fail "#78 ship-ticket: check line"
grep -qF 'Modify: `path/to/file.py:120-145`' "$F" && grep -qF 'Create: `path/to/new.py`' "$F" && grep -qF 'Test: `tests/test_file.py`' "$F" && pass "#78 ship-ticket: its Files example names each path in backticks" || fail "#78 ship-ticket: Files example backticks"

# lane e: #115 the executor never force-adds, and its check unstages only newly added ignored paths
grep -qF '**Never `git add -f` (`--force`).**' "$EX" && pass "#115 the executor never force-adds" || fail "#115 the executor never force-adds"
grep -qF '`not committed: <path> is git-ignored`' "$EX" && pass "#115 an ignored path is reported, not committed" || fail "#115 the not-committed report line"
grep -qF '`git diff --cached --no-renames --name-only --diff-filter=A | git check-ignore --no-index --stdin`' "$EX" && grep -qF '`git rm --cached -q -- <path>` (the file stays on disk), then commit.' "$EX" && pass "#115 the check runs before each commit and unstages what it prints" || fail "#115 the pre-commit check"
grep -qF 'The executor never runs `git add -f`, and never commits a path the repository ignores.' "$PC" && pass "#115 the contract says it too" || fail "#115 the contract sentence"
# Review Focus 4: run the check exactly as the skill writes it
CHECK=$(sed -n 's/.*`\(git diff --cached [^`]*\)`.*/\1/p' "$EX" | head -1)
G=$(mktemp -d); trap 'rm -rf "$G"' EXIT
(cd "$G" && git init -q . && printf '*.log\nevidence/\n' > .gitignore && printf 'kept on purpose\n' > old.log && printf 'a\n' > src.txt \
  && git add .gitignore src.txt && git add -f old.log && git -c user.email=t@t -c user.name=t commit -qm init)
printf 'changed\n' >> "$G/old.log"; mkdir -p "$G/evidence"; printf 'png\n' > "$G/evidence/shot.png"; printf 'b\n' > "$G/new.txt"
(cd "$G" && git add old.log new.txt && git add -f evidence/shot.png && git mv -f src.txt evidence/src.txt)
out=$(cd "$G" && sh -c "$CHECK")
[ -n "$CHECK" ] && [ "$out" = "$(printf 'evidence/shot.png\nevidence/src.txt')" ] && pass "#115 the check prints a new or renamed ignored path, never a tracked one an ignore rule matches" || fail "#115 the check in a scratch repo (got: $out)"

# lane e: #118 a link that resolves into another version's copy is not current, and the ledger is written per task
for s in ship-ticket review-and-execute receive-review-and-execute execute; do
  grep -qF 'test -f ~/.codex/skills/claude-plan-executor/SKILL.md' "$ROOT/skills/$s/SKILL.md" && fail "#118 $s: a link that only resolves is still accepted" || pass "#118 $s: a link that only resolves is no longer enough"
done
grep -qF "Right after the task's commit, before the next task's first step, append" "$EX" && pass "#118 the executor writes each ledger line right after the task's commit" || fail "#118 ledger timing"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
