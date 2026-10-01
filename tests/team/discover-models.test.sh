#!/bin/sh
# Runs skills/team/discover-models.sh against stub codex/claude binaries.
# Usage: sh tests/team/discover-models.test.sh   (exit 0 = all cases pass)
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/team/discover-models.sh"
FIX="$ROOT/tests/team/fixtures"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PY=$(command -v python3)
fails=0

# stub <dir> <name> <shell body>
stub() {
  mkdir -p "$1"
  printf '#!/bin/sh\n%s\n' "$3" > "$1/$2"
  chmod +x "$1/$2"
  ln -sf "$PY" "$1/python3"
}

# run <bin dir> <timeout seconds>: output to $TMP/out, exit code to $TMP/rc
run() {
  PATH="$1:/usr/bin:/bin" TEAM_DISCOVER_TIMEOUT="$2" /bin/sh "$SCRIPT" > "$TMP/out" 2> "$TMP/err"
  echo $? > "$TMP/rc"
}

# check <name> <python assertion over `lines` (list of dicts), `rc` (int) and `raw` (str)>
check() {
  if "$PY" - "$TMP/out" "$TMP/rc" "$2" <<'PY'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
rc = int(open(sys.argv[2]).read())
raw = open(sys.argv[1]).read()
assert eval(sys.argv[3]), (lines, rc)
PY
  then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

CODEX_OK="cat '$FIX/codex-models.json'"
CLAUDE_OK="cat > /dev/null; cat '$FIX/claude-stream.jsonl'"

# 1. both providers healthy
B="$TMP/ok"; stub "$B" codex "$CODEX_OK"; stub "$B" claude "$CLAUDE_OK"; run "$B" 5
check "exit 0" 'rc == 0'
check "codex listed, sorted by priority, hidden dropped" \
  '[l["id"] for l in lines if l["provider"] == "codex"] == ["gpt-6.1-sol", "gpt-6-astra", "gpt-5.5"]'
check "codex efforts flattened" \
  'next(l for l in lines if l["id"] == "gpt-6-astra")["efforts"] == ["low", "ultra"]'
check "codex retiring and legacy flags" \
  'set(next(l for l in lines if l["id"] == "gpt-5.5")["flags"]) == {"retiring", "legacy"}'
check "codex default effort kept" \
  'next(l for l in lines if l["id"] == "gpt-6.1-sol")["default_effort"] == "low"'
check "base_instructions never printed" '"SECRET-BASE-INSTRUCTIONS" not in raw'
check "claude skips default and disabled" \
  '[l["id"] for l in lines if l["provider"] == "claude"] == ["opus", "claude-fable-5-1", "haiku"]'
check "claude null efforts become []" \
  'next(l for l in lines if l["id"] == "haiku")["efforts"] == []'
check "claude alias flag only on versionless ids" \
  '[l["id"] for l in lines if "alias" in l["flags"]] == ["opus", "haiku"]'
check "claude resolves_to carried" \
  'next(l for l in lines if l["id"] == "opus")["resolves_to"] == "claude-opus-5-5"'

# 2. codex missing
B="$TMP/nocodex"; stub "$B" claude "$CLAUDE_OK"; run "$B" 5
check "codex missing: unavailable line, claude still listed, exit 0" \
  'rc == 0 and any(l.get("provider") == "codex" and "not found" in l.get("unavailable", "") for l in lines) and any(l.get("provider") == "claude" and "id" in l for l in lines)'

# 3. claude missing
B="$TMP/noclaude"; stub "$B" codex "$CODEX_OK"; run "$B" 5
check "claude missing: unavailable line, codex still listed" \
  'rc == 0 and any(l.get("provider") == "claude" and "not found" in l.get("unavailable", "") for l in lines) and any(l.get("provider") == "codex" and "id" in l for l in lines)'

# 4. codex catalog without a models key
B="$TMP/badshape"; stub "$B" codex 'echo "{\"nope\": 1}"'; stub "$B" claude "$CLAUDE_OK"; run "$B" 5
check "codex malformed: unavailable mentions shape" \
  'any(l.get("provider") == "codex" and "shape" in l.get("unavailable", "") for l in lines)'

# 5. codex prints non-JSON
B="$TMP/notjson"; stub "$B" codex 'echo garbage'; stub "$B" claude "$CLAUDE_OK"; run "$B" 5
check "codex not json: unavailable line" \
  'any(l.get("provider") == "codex" and "unavailable" in l for l in lines)'

# 6. codex exits nonzero
B="$TMP/codexfail"; stub "$B" codex 'echo boom >&2; exit 3'; stub "$B" claude "$CLAUDE_OK"; run "$B" 5
check "codex nonzero: reason has exit code and stderr" \
  'any(l.get("provider") == "codex" and "exited 3" in l["unavailable"] and "boom" in l["unavailable"] for l in lines if "unavailable" in l)'

# 7. claude hangs: timeout fires fast
B="$TMP/hang"; stub "$B" codex "$CODEX_OK"; stub "$B" claude 'sleep 20'
start=$(date +%s); run "$B" 1; elapsed=$(( $(date +%s) - start ))
check "claude hang: timed out line" \
  'any(l.get("provider") == "claude" and "timed out" in l.get("unavailable", "") for l in lines)'
if [ "$elapsed" -le 6 ]; then echo "ok   claude hang: finished in ${elapsed}s"; else echo "FAIL claude hang took ${elapsed}s"; fails=$((fails + 1)); fi

# 8. claude output without control_response
B="$TMP/noresp"; stub "$B" codex "$CODEX_OK"; stub "$B" claude 'cat > /dev/null; echo "{\"type\":\"system\"}"'; run "$B" 5
check "claude no control_response: unavailable line" \
  'any(l.get("provider") == "claude" and "control_response" in l.get("unavailable", "") for l in lines)'

# 9. empty model list
B="$TMP/empty"; stub "$B" codex 'echo "{\"models\": []}"'; stub "$B" claude "$CLAUDE_OK"; run "$B" 5
check "codex empty list: unavailable no models" \
  'any(l.get("provider") == "codex" and "no models" in l.get("unavailable", "") for l in lines)'

# 10. codex catalog entries are not objects (AttributeError territory): still exit 0, claude still listed
B="$TMP/strings"; stub "$B" codex 'echo "{\"models\": [\"gpt-x\"]}"'; stub "$B" claude "$CLAUDE_OK"; run "$B" 5
check "codex string entries: unavailable shape, claude still listed, exit 0" \
  'rc == 0 and any(l.get("provider") == "codex" and "shape" in l.get("unavailable", "") for l in lines) and any(l.get("provider") == "claude" and "id" in l for l in lines)'

# 11. codex description is not a string
B="$TMP/baddesc"; stub "$B" codex 'echo "{\"models\": [{\"slug\": \"a\", \"visibility\": \"list\", \"description\": {\"x\": 1}}]}"'; stub "$B" claude "$CLAUDE_OK"; run "$B" 5
check "codex non-string description: unavailable, exit 0" \
  'rc == 0 and any(l.get("provider") == "codex" and "unavailable" in l for l in lines)'

echo
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
