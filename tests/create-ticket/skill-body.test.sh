#!/bin/sh
# Guards on skills/create-ticket/SKILL.md: provider-agnostic ticket creation.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/create-ticket/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }
[ -d "$ROOT/skills/create-linear-ticket" ] && fail "old skill dir removed" || pass "old skill dir removed"

if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
grep -q '^name: create-ticket$' "$SKILL" && pass "renamed" || fail "frontmatter name"
grep -q 'create-linear-ticket' "$SKILL" && fail "no old name in body" || pass "no old name in body"
grep -q 'Step 0' "$SKILL" && pass "Step 0 present" || fail "Step 0 missing"
grep -q '`create`' "$SKILL" && pass "create capability named" || fail "create capability missing"
grep -q 'inline.*cannot create\|`inline`.*STOP' "$SKILL" && pass "inline stops" || fail "inline stop missing"
grep -q 'Preview (MANDATORY' "$SKILL" && pass "preview mandatory" || fail "preview not mandatory"
grep -q 'Do NOT implement, do NOT write a spec file, do NOT invoke writing-plans' "$SKILL" && pass "scoping contract intact" || fail "scoping contract changed"
# LINEAR_PREFIX may appear only on lines that are inside the Linear recipe (marked "Linear:" or a linear table row).
bad=$(grep -n 'LINEAR_PREFIX' "$SKILL" | grep -v -i 'linear' )
[ -z "$bad" ] && pass "Linear calls only in Linear rows" || { echo "$bad"; fail "Linear calls only in Linear rows"; }
for r in README.md references/work-source.md .claude-plugin/requirements.json; do
  grep 'create-linear-ticket' "$ROOT/$r" | grep -qv 'formerly `create-linear-ticket`' && fail "no old name in $r" || pass "no old name in $r"
done

grep -q 'the same directory `juel:daily-worktrees` lists' "$SKILL" && pass "file target matches daily-worktrees" || fail "file target dir"
grep -q 'the Work Source block.s `project`' "$SKILL" && pass "project default from any source" || fail "project default"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
