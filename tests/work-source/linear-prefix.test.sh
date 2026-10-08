#!/bin/sh
# Every skill that resolves the Linear prefix knows the Linear plugin's name for it (#30).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
for f in references/work-source.md skills/start/SKILL.md skills/daily-worktrees/SKILL.md skills/create-ticket/SKILL.md skills/ship-ticket/SKILL.md skills/star/SKILL.md; do
  grep -q 'mcp__plugin_linear_linear__' "$ROOT/$f" && pass "$f knows the plugin prefix" || fail "$f lacks mcp__plugin_linear_linear__"
done
if grep -n '`mcp__linear__` or `mcp__claude_ai_Linear__`' "$ROOT"/skills/*/SKILL.md; then fail "a two-prefix rule is left"; else pass "no two-prefix rule is left"; fi
grep -q 'save_comment' "$ROOT/skills/star/SKILL.md" && pass "post-report knows save_comment" || fail "post-report comment tool"
grep -qF 'call to `<LINEAR_COMMENT>` (§4.1)' "$ROOT/references/work-source.md" && pass "Z12 the confirmation rule covers both comment tools" || fail "Z12 the confirmation rule covers both comment tools"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
