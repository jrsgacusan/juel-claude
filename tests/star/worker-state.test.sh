#!/bin/sh
# hooks/worker-state.sh (#208): a worker's hook events become <star home>/workers/<handle>.json.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$ROOT/hooks/worker-state.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$HOOK" ] || { echo "FAIL worker-state.sh missing"; exit 1; }
mkdir -p "$TMP/app/src" "$TMP/other" && (cd "$TMP/app" && git init -q . && git commit -q --allow-empty -m init)
H=$(HOME="$TMP/home" sh "$ROOT/skills/star/star-home.sh" --cwd "$TMP/app" init)
F="$H/workers/term_W.json"
# run <cwd> <handle> <json fields>
run() { printf '{"session_id":"s1","cwd":"%s",%s}' "$1" "$3" | env ORCA_TERMINAL_HANDLE="$2" sh "$HOOK"; }
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],"<none>"))' "$1" "$2" 2>/dev/null; }

out=$(run "$TMP/app" term_W '"hook_event_name":"StopFailure","error":"rate_limit","error_details":"429 too many"'); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "StopFailure: exit 0, nothing on stdout" || fail "StopFailure stdout/rc ($out)"
[ "$(field "$F" event)" = StopFailure ] && [ "$(field "$F" kind)" = rate_limit ] && [ "$(field "$F" handle)" = term_W ] \
  && [ "$(field "$F" session)" = s1 ] && [ "$(field "$F" message)" = "429 too many" ] && pass "StopFailure state: event, kind=error, handle, session, message" || fail "StopFailure fields ($(cat "$F" 2>/dev/null))"
python3 -c 'import json,sys; from datetime import datetime; d=json.load(open(sys.argv[1])); datetime.strptime(d["at"],"%Y-%m-%dT%H:%M:%SZ")' "$F" && pass "at is ISO with Z" || fail "at format"
run "$TMP/app/src" term_W '"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash","title":"t"' >/dev/null
[ "$(field "$F" event)" = Notification ] && [ "$(field "$F" kind)" = permission_prompt ] && pass "Notification state from a subfolder, kind=notification_type" || fail "Notification ($(cat "$F"))"
long=$(python3 -c 'print("x"*300)')
run "$TMP/app" term_W "\"hook_event_name\":\"Notification\",\"notification_type\":\"idle_prompt\",\"message\":\"$long\"" >/dev/null
[ "$(field "$F" message | wc -c | tr -d ' ')" -le 121 ] && pass "message is cut to 120 characters" || fail "message length"
for ev in SessionStart UserPromptSubmit Stop; do
  run "$TMP/app" term_W '"hook_event_name":"StopFailure","error":"overloaded"' >/dev/null
  out=$(run "$TMP/app" term_W "\"hook_event_name\":\"$ev\",\"prompt\":\"hi\""); [ -z "$out" ] || fail "$ev printed ($out)"
  [ "$(field "$F" event)" = clear ] && pass "$ev clears the state" || fail "$ev clear ($(cat "$F"))"
done
rm -f "$F"
run "$TMP/app" "" '"hook_event_name":"Stop"' >/dev/null; [ -z "$(ls "$H/workers" 2>/dev/null)" ] && pass "no ORCA_TERMINAL_HANDLE: nothing written" || fail "no handle"
run "$TMP/other" term_W '"hook_event_name":"Stop"' >/dev/null; [ ! -e "$F" ] && pass "outside a project: nothing written" || fail "outside project"
run "$TMP/app" "../evil" '"hook_event_name":"Stop"' >/dev/null; [ ! -e "$H/evil.json" ] && [ ! -e "$H/workers/../evil.json" ] && pass "a handle with a slash writes nothing" || fail "path escape"
run "$TMP/app" term_W '"hook_event_name":"PreToolUse"' >/dev/null; [ ! -e "$F" ] && pass "another event writes nothing" || fail "other event"
out=$(printf 'not json' | ORCA_TERMINAL_HANDLE=term_W sh "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "bad input exits 0 silently" || fail "bad input"
printf 'old' > "$H/workers/term_old.json"; python3 -c 'import os,time,sys; t=time.time()-8*86400; os.utime(sys.argv[1],(t,t))' "$H/workers/term_old.json"
run "$TMP/app" term_W '"hook_event_name":"Stop"' >/dev/null
[ ! -e "$H/workers/term_old.json" ] && [ -e "$F" ] && pass "files older than 7 days are removed" || fail "cleanup"
python3 - "$ROOT/hooks/hooks.json" <<'PY' && pass "hooks.json registers worker-state.sh for the five events" || fail "hooks.json"
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
for ev in ("SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "Notification"):
    cmds = [x["command"] for g in h[ev] for x in g["hooks"]]
    assert any("hooks/worker-state.sh" in c and "CLAUDE_PLUGIN_ROOT" in c for c in cmds), ev
PY
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
