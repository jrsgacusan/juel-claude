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
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
