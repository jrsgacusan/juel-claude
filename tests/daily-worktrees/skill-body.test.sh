#!/bin/sh
# Guards on skills/daily-worktrees/SKILL.md: provider-agnostic text.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/daily-worktrees/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }

if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
# Provider tools may be named only on that provider's row of the recipe table.
bad=$(grep -n 'LINEAR_PREFIX\|save_issue\|list_issues' "$SKILL" | grep -v ':| `linear` |')
[ -z "$bad" ] && pass "Linear calls only in the linear recipe row" || { echo "$bad"; fail "Linear calls only in the linear recipe row"; }
for p in linear jira github file; do
  grep -q "^| \`$p\` |" "$SKILL" && pass "recipe row $p" || fail "recipe row $p"
done
grep -q '`list`' "$SKILL" && pass "list capability named" || fail "list capability missing"
grep -q '`update_status`' "$SKILL" && pass "update_status capability named" || fail "update_status capability missing"
grep -q '## Work Source' "$SKILL" && pass "Work Source block documented" || fail "Work Source block missing"
grep -q 'Linear Worktrees Config' "$SKILL" && pass "legacy fallback still documented" || fail "legacy fallback missing"
grep -q '{type}/{slug}' "$SKILL" && pass "slug when ref is null" || fail "no-ref branch pattern missing"
if sed -n '/^---$/,/^---$/p' "$SKILL" | grep -q 'id: linear'; then fail "no linear frontmatter dep"; else pass "no linear frontmatter dep"; fi

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
