#!/bin/sh
# Claude Code substitutes $0..$9 in a skill body with the skill's positional arguments,
# so a shell snippet using $1 silently receives a word from the user's request.
# Usage: sh tests/team/skill-body.test.sh   (exit 0 = pass)
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
if grep -nE '\$[0-9]' "$ROOT/skills/team/SKILL.md"; then
  echo "FAIL skills/team/SKILL.md uses positional parameters (\$N); the skill loader substitutes them"
  exit 1
fi
echo "ok   no positional parameters in skills/team/SKILL.md"
