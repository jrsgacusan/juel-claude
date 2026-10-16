#!/bin/sh
# #136: every skill that invokes a superpowers: skill says how to call it on a host that registers it unprefixed.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
RULE=$(cat <<'EOF'
Call each `superpowers:` skill by that name; when the Skill tool answers "Unknown skill", call the same name without the `superpowers:` prefix, and use whichever answered for the rest of the run.
EOF
)
n=0
for f in "$ROOT"/skills/*/SKILL.md; do
  name=$(basename "$(dirname "$f")")
  [ "$name" = doctor ] && continue
  grep -q 'superpowers:' "$f" || continue
  n=$((n + 1))
  c=$(tr '\n' ' ' < "$f" | tr -s ' ' | grep -oF -- "$RULE" | wc -l | tr -d ' ')
  [ "$c" = 1 ] && pass "#136 $name says the superpowers fallback once" || fail "#136 $name says the superpowers fallback $c times"
done
[ "$n" -ge 8 ] && pass "#136 every invoking skill is checked ($n)" || fail "#136 only $n invoking skills found"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
