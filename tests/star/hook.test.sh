#!/bin/sh
# The SessionStart hook speaks only inside a STAR home.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$ROOT/hooks/star-session.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$HOOK" ] || { echo "FAIL star-session.sh missing"; exit 1; }
mkdir -p "$TMP/star" "$TMP/other"; cp "$ROOT/skills/star/template/star.json" "$TMP/star/star.json"

out=$(printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"compact"}' "$TMP/other" | sh "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "silent elsewhere" || fail "silent elsewhere ($out)"
out=$(printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"compact"}' "$TMP/star" | sh "$HOOK")
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["hookEventName"]=="SessionStart"; assert "/juel:star" in d["additionalContext"] and "Resume" in d["additionalContext"]' && pass "speaks in a STAR home, valid JSON" || fail "STAR home output ($out)"
out=$(printf 'not json' | sh "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "bad input is silent and exits 0" || fail "bad input"
python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]; assert h["matcher"]=="startup|resume|compact|clear"; assert "star-session.sh" in h["hooks"][0]["command"] and "CLAUDE_PLUGIN_ROOT" in h["hooks"][0]["command"]' "$ROOT/hooks/hooks.json" && pass "hooks.json registers it" || fail "hooks.json"
T="$ROOT/skills/star/template"
grep -q 'Never merge' "$T/CLAUDE.md" && grep -q 'Resume' "$T/CLAUDE.md" && grep -q '/juel:star' "$T/CLAUDE.md" && pass "template CLAUDE.md carries the standing rules" || fail "template CLAUDE.md"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["maxParallel"]==3 and d["maxInReview"]==3 and d["quietHours"] is None' "$T/star.json" && pass "template star.json defaults" || fail "template star.json"
[ -f "$T/memory/global.md" ] && [ -f "$T/gitignore" ] && pass "memory and gitignore templates" || fail "templates missing"

python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["notifiedThrough"]==0' "$T/star.json" && pass "notification cursor starts at 0" || fail "notifiedThrough default"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "away" in d and d["away"] is None' "$T/star.json" && pass "away starts off" || fail "away default"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
