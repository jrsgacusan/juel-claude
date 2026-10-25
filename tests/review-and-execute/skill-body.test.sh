#!/bin/sh
# Guards on skills/review-and-execute/SKILL.md.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/review-and-execute/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL review-and-execute SKILL.md missing"; exit 1; }
# has <name> <text>: the text is in $SKILL once line breaks and repeated spaces are folded
has() { tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qF -- "$2" && pass "$1" || fail "$1"; }
R128a="Each review agent writes its scratch files only under \`<scratchpad>/review-<agent>/\` (\`<agent>\` the agent's name), never in the build's scratchpad root: tell every agent so in its prompt."
has "#128 each review agent writes under its own scratch folder" "$R128a"
# lane c: #158 the stop and the check at the dispatch
has "C158i names session-tasks.sh" 'session-tasks.sh'
has "C158j the dispatch prompt carries the stop sentence" ' Stop before task <N>: the session runs it.'
has "C158k a ran line is a failed run" '`ran <N>` line is a failed run'
has "C158l the caller's Phase 5 escalation names the executor run" '`ESCALATION item=<item> phase=5 reason=out-of-tries step=executor`, `<item>` being the caller'"'"'s'

# audit lane e: #164 the executor check is executor-check.sh, and a usage limit runs the plan in the session
has "E164a the executor check runs executor-check.sh" 'sh <plugin root>/skills/ship-ticket/executor-check.sh <plugin root>'
has "E164b an older copy fails the check, a newer one passes" "(a link into an older version's copy fails it; a newer one passes)"
has "E164c an out-of-usage codex runs the plan in this session" '**Out of usage.**'
# lane e: STAR autonomy
has "AU1 the fallback equal to the executor is no fallback" 'resolves, through `executor-model.sh`, to the same model id as the executor, there is no fallback: skip straight to running the plan in this session'
tr '\n' ' ' < "$ROOT/skills/execute/SKILL.md" | tr -s ' ' | grep -qF -- 'resolves, through `executor-model.sh`, to the same model id as the executor, there is no fallback: skip straight to running the plan in this session' && pass "AU2 execute says the same" || fail "AU2 execute says the same"
! grep -qF 'reason=codex-failed' "$SKILL" && pass "AU3 codex-failed is gone" || fail "AU3 codex-failed is gone"
has "FX195 a fix plan carries the Scratch line and the Execution rules block" 'the `**Scratch:**` line (only when the docsRoot is inside the repository) and the `## Execution rules` block, exactly as `juel:ship-ticket`'"'"'s Phase 3 gives them'
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
