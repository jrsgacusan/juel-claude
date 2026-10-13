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
run() { printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"compact"}' "$1" | env -u CLAUDE_ENV_FILE ORCA_TERMINAL_HANDLE="$2" sh "$HOOK"; }
valid() { python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["hookEventName"]=="SessionStart"; t=d["additionalContext"]; assert "/juel:star" in t and "merge.sh" in t and sys.argv[1] in t, t' "$1" 2>/dev/null; }

owner term_A
run "$TMP/app" term_A | valid "$H" && pass "speaks to the owning terminal, valid JSON, names the folder" || fail "owning terminal"
run "$TMP/app/src" term_A | valid "$H" && pass "speaks from a subfolder of the project" || fail "subfolder"
out=$(run "$TMP/app" term_B); [ -z "$out" ] && pass "silent for another terminal in the same project" || fail "another terminal was told it is STAR ($out)"
out=$(run "$TMP/app" ""); [ -z "$out" ] && pass "silent outside an Orca terminal" || fail "no handle ($out)"
owner ""
out=$(run "$TMP/app" term_A); [ -z "$out" ] && pass "silent when STAR was stopped (no owner)" || fail "stopped STAR ($out)"
out=$(run "$TMP/other" term_A); rc=$?; [ "$rc" -eq 0 ] && [ -z "$out" ] && pass "silent outside a project" || fail "outside a project ($out)"
# the token: every session in the project gets tokenCmd as a command, never as a value (#91, #92)
token() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["tokenCmd"]=json.loads(sys.argv[2]); json.dump(d,open(p,"w"),indent=2)' "$H/star.json" "$1"; }
# envrun <cwd> <env file> [<handle>]: the hook with GH_TOKEN unset and CLAUDE_ENV_FILE set
envrun() { printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1" | env -u GH_TOKEN CLAUDE_ENV_FILE="$2" ORCA_TERMINAL_HANDLE="${3:-}" sh "$HOOK"; }
LINE='export GH_TOKEN="$(echo tok_$((40 + 2)))"'
token '"echo tok_$((40 + 2))"'
out=$(envrun "$TMP/app" "$TMP/env1" term_B)
[ -z "$out" ] && [ "$(cat "$TMP/env1" 2>/dev/null)" = "$LINE" ] && pass "a worker session gets the export line, and the hook stays silent" || fail "export line ($(cat "$TMP/env1" 2>/dev/null))"
# Review Focus 5: the command, never the token
[ -f "$TMP/env1" ] && ! grep -q 'tok_42' "$TMP/env1" && pass "the file holds the command, not the token" || fail "token value written"
[ "$(sh -c ". \"$TMP/env1\"; printf %s \"\$GH_TOKEN\"" 2>/dev/null)" = "tok_42" ] && pass "sourcing the file sets GH_TOKEN" || fail "sourced value"
envrun "$TMP/app" "$TMP/env1" term_B >/dev/null; [ "$(grep -c 'GH_TOKEN' "$TMP/env1" 2>/dev/null)" = 1 ] && pass "a second run writes nothing more" || fail "written twice"
printf 'export A=1' > "$TMP/env2"; envrun "$TMP/app/src" "$TMP/env2" >/dev/null
[ "$(sed -n 1p "$TMP/env2")" = "export A=1" ] && [ "$(sed -n 2p "$TMP/env2")" = "$LINE" ] && pass "it appends on a line of its own, from a subfolder, outside Orca too" || fail "append ($(cat "$TMP/env2"))"
owner term_A; out=$(envrun "$TMP/app" "$TMP/env3" term_A)
printf '%s' "$out" | valid "$H" && [ "$(cat "$TMP/env3" 2>/dev/null)" = "$LINE" ] && pass "STAR's own session gets the line and its context" || fail "coordinator token"
owner ""
printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$TMP/app" | GH_TOKEN=already CLAUDE_ENV_FILE="$TMP/env4" sh "$HOOK" >/dev/null
[ ! -s "$TMP/env4" ] && pass "a session that already has GH_TOKEN gets nothing" || fail "GH_TOKEN already set ($(cat "$TMP/env4"))"
out=$(printf '{"cwd":"%s"}' "$TMP/app" | env -u GH_TOKEN -u CLAUDE_ENV_FILE sh "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "no CLAUDE_ENV_FILE: nothing to write, exit 0" || fail "no env file"
token '"printf a\nprintf b"'; envrun "$TMP/app" "$TMP/env6" >/dev/null; [ ! -s "$TMP/env6" ] && pass "a tokenCmd of two lines writes nothing" || fail "two-line tokenCmd"
token null; envrun "$TMP/app" "$TMP/env5" >/dev/null; [ ! -s "$TMP/env5" ] && pass "tokenCmd null writes nothing" || fail "null tokenCmd"
token '"echo x"'; envrun "$TMP/other" "$TMP/env7" >/dev/null; [ ! -s "$TMP/env7" ] && pass "outside a project nothing is written" || fail "outside project"
owner term_A; printf 'not json' > "$H/star.json"
out=$(run "$TMP/app" term_A); rc=$?; [ "$rc" -eq 0 ] && [ -z "$out" ] && pass "a broken star.json is silent" || fail "broken star.json ($out)"
out=$(printf 'not json' | ORCA_TERMINAL_HANDLE=term_A sh "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "bad input is silent and exits 0" || fail "bad input"
python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]; assert h["matcher"]=="startup|resume|compact|clear"; assert "star-session.sh" in h["hooks"][0]["command"] and "CLAUDE_PLUGIN_ROOT" in h["hooks"][0]["command"]' "$ROOT/hooks/hooks.json" && pass "hooks.json registers it" || fail "hooks.json"
T="$ROOT/skills/star/template"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["maxParallel"]==3 and d["maxInReview"]==3 and d["quietHours"] is None and d["notified"]==[] and d["away"] is None and d["terminal"] is None; assert d["tokenCmd"] is None and list(d).index("tokenCmd") == list(d).index("quietHours") + 1' "$T/star.json" && pass "template star.json defaults" || fail "template star.json"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
