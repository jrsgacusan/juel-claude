#!/bin/sh
# The SessionStart hook speaks only to the terminal that owns STAR for the project it is in.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$ROOT/hooks/star-session.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$HOOK" ] || { echo "FAIL star-session.sh missing"; exit 1; }
mkdir -p "$TMP/app/src" "$TMP/other" && (cd "$TMP/app" && git init -q . && git commit -q --allow-empty -m init)
H=$(sh "$ROOT/skills/star/star-home.sh" --cwd "$TMP/app" init)
owner() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["terminal"]=(sys.argv[2] or None); json.dump(d,open(p,"w"),indent=2)' "$H/star.json" "$1"; }
# run <cwd> <handle>
run() { printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"compact"}' "$1" | ORCA_TERMINAL_HANDLE="$2" sh "$HOOK"; }
valid() { python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["hookEventName"]=="SessionStart"; t=d["additionalContext"]; assert "/juel:star" in t and "merge.sh" in t and sys.argv[1] in t, t' "$1" 2>/dev/null; }

owner term_A
run "$TMP/app" term_A | valid "$H" && pass "speaks to the owning terminal, valid JSON, names the folder" || fail "owning terminal"
run "$TMP/app/src" term_A | valid "$H" && pass "speaks from a subfolder of the project" || fail "subfolder"
out=$(run "$TMP/app" term_B); [ -z "$out" ] && pass "silent for another terminal in the same project" || fail "another terminal was told it is STAR ($out)"
out=$(run "$TMP/app" ""); [ -z "$out" ] && pass "silent outside an Orca terminal" || fail "no handle ($out)"
owner ""
out=$(run "$TMP/app" term_A); [ -z "$out" ] && pass "silent when STAR was stopped (no owner)" || fail "stopped STAR ($out)"
out=$(run "$TMP/other" term_A); rc=$?; [ "$rc" -eq 0 ] && [ -z "$out" ] && pass "silent outside a project" || fail "outside a project ($out)"
owner term_A; printf 'not json' > "$H/star.json"
out=$(run "$TMP/app" term_A); rc=$?; [ "$rc" -eq 0 ] && [ -z "$out" ] && pass "a broken star.json is silent" || fail "broken star.json ($out)"
out=$(printf 'not json' | ORCA_TERMINAL_HANDLE=term_A sh "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "bad input is silent and exits 0" || fail "bad input"
python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]; assert h["matcher"]=="startup|resume|compact|clear"; assert "star-session.sh" in h["hooks"][0]["command"] and "CLAUDE_PLUGIN_ROOT" in h["hooks"][0]["command"]' "$ROOT/hooks/hooks.json" && pass "hooks.json registers it" || fail "hooks.json"
T="$ROOT/skills/star/template"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["maxParallel"]==3 and d["maxInReview"]==3 and d["quietHours"] is None and d["notified"]==[] and d["away"] is None and d["terminal"] is None' "$T/star.json" && pass "template star.json defaults" || fail "template star.json"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
