#!/bin/sh
# Guards on skills/start/SKILL.md: provider-agnostic fetch.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/start/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }

if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
step2=$(sed -n '/^### Step 2:/,/^### Step 3:/p' "$SKILL")
for p in linear jira github file; do
  printf '%s\n' "$step2" | grep -q "^| \`$p\` |" && pass "fetch row $p" || fail "fetch row $p"
done
printf '%s\n' "$step2" | grep -q 'never picks the provider by itself' && pass "Linear/Jira key shape is not a provider" || fail "key shape ambiguity rule"
printf '%s\n' "$step2" | grep -q '## Work Source' && pass "Work Source block in the chain" || fail "Work Source block"
printf '%s\n' "$step2" | grep -q 'do not fall back to `gh` or the web' && pass "Linear no-fallback rule kept" || fail "Linear no-fallback rule"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
