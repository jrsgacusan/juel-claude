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
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
