#!/bin/sh
# Runs skills/star/worker-probe.sh against a stub orca.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/worker-probe.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
[ -f "$SCRIPT" ] || { echo "FAIL worker-probe.sh missing"; exit 1; }
mkdir -p "$TMP/bin"
cat > "$TMP/bin/orca" <<'EOF'
#!/bin/sh
[ "${STUB_FAIL:-}" = 1 ] && { echo "runtime not reachable" >&2; exit 1; }
case "$*" in
  *worker-show*) cat "$STUB_DIR/show.json" ;;
  *worker-read*) cat "$STUB_DIR/read.json" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$TMP/bin/orca"; ln -s "$(command -v python3)" "$TMP/bin/python3"
# t <name> <expected> <stage> <state> <tail line>
t() {
  printf '{"result":{"worker":{"stage":"%s","state":"%s"}}}\n' "$3" "$4" > "$TMP/show.json"
  python3 -c 'import json,sys; print(json.dumps({"result":{"terminal":{"tail":["working on it", sys.argv[1]]}}}))' "$5" > "$TMP/read.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
  if [ "$out" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got: $out)"; fails=$((fails + 1)); fi
}
t "working worker" "ok" ready running "Ran 3 shell commands"
t "settled worker" "settled succeeded" settled succeeded "done"
t "usage limit" "stuck: usage limit" ready running "Claude usage limit reached. Your limit will reset at 3pm"
t "codex usage limit" "stuck: usage limit" ready running "You've hit your usage limit. Upgrade to Pro"
t "login" "stuck: login" ready running "Please run /login"
t "trust dialog" "stuck: trust dialog" ready running "Do you trust the files in this folder?"
t "exit dialog" "stuck: confirmation dialog" ready running "  2. No, exit"
t "a worker writing auth code is not stuck" "ok" ready running "editing src/login.ts to fix the login form"
printf '{"result":{"worker":{"stage":"ready","state":"running"}}}\n' > "$TMP/show.json"
printf '{"result":{"messages":[{"text":"hello"},{"text":"Not logged in · Please run /login"}]}}\n' > "$TMP/read.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "stuck: login" ] && echo "ok   transcript source is read too" || { echo "FAIL transcript source ($out)"; fails=$((fails + 1)); }
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" STUB_FAIL=1 ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
case "$out" in "unknown "*) echo "ok   orca failure is unknown, never stuck" ;; *) echo "FAIL orca failure ($out)"; fails=$((fails + 1)) ;; esac

# A worker that failed before its prompt landed is settled, whatever stage it stopped in.
printf '{"result":{"worker":{"stage":"dispatch_input","state":"failed"},"dispatch":{"status":"failed"}}}\n' > "$TMP/show.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "settled failed" ] && echo "ok   failed before the prompt is settled" || { echo "FAIL failed-before-prompt ($out)"; fails=$((fails + 1)); }
printf '{"result":{"worker":{"stage":"running","state":"running"},"dispatch":{"status":"completed"}}}\n' > "$TMP/show.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "settled completed" ] && echo "ok   a completed dispatch is settled" || { echo "FAIL completed dispatch ($out)"; fails=$((fails + 1)); }
printf '{"result":{}}\n' > "$TMP/show.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "unknown no worker record" ] && echo "ok   an empty result says nothing: only dispatch_not_found is gone" || { echo "FAIL empty worker-show ($out)"; fails=$((fails + 1)); }
for body in '' '{"ok":true,"result":null}' '[]' 'not json'; do
  printf '%s\n' "$body" > "$TMP/show.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1 2>&1)
  case "$out" in "unknown "*) echo "ok   orca printing '$body' is unknown, never gone" ;; *) echo "FAIL orca printing '$body' ($out)"; fails=$((fails + 1)) ;; esac
done
# Ordinary work that mentions these words is not a blocking screen.
t "a rebase hint is not a model switch" "ok" ready running "git: switch to main to continue the rebase"
t "a real model switch prompt" "stuck: model switch" ready running "Would you like to switch to Opus 5.5 to continue?"
t "a test name about logins is not a login screen" "ok" ready running "  ✓ returns 401 when the user is not logged in (12 ms)"
t "a question in prose is not a dialog" "ok" ready running "Do you want to proceed? I will continue anyway."
printf '{"result":{"worker":{"stage":"ready","state":"running"}}}\n' > "$TMP/show.json"
python3 -c 'import json; print(json.dumps({"result":{"terminal":{"tail":["Do you want to proceed?", "❯ 1. Yes", "  2. No"]}}}))' > "$TMP/read.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "stuck: confirmation dialog: Do you want to proceed?" ] && echo "ok   a question with numbered options is a dialog" || { echo "FAIL real dialog ($out)"; fails=$((fails + 1)); }
python3 -c 'import json; print(json.dumps({"result":{"messages":[{"text":"Please run /login"},{"text":"I fixed the login form and pushed."}]}}))' > "$TMP/read.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "ok" ] && echo "ok   only the newest transcript message counts" || { echo "FAIL old transcript message ($out)"; fails=$((fails + 1)); }
# A worker whose terminal has printed nothing for a while is quiet: STAR checks in on it.
cat > "$TMP/bin/orca" <<'EOF3'
#!/bin/sh
case "$*" in
  *"terminal list"*) [ "${STUB_LIST_FAIL:-}" = 1 ] && exit 1; cat "$STUB_DIR/list.json" ;;
  *worker-show*) cat "$STUB_DIR/show.json" ;;
  *worker-read*) cat "$STUB_DIR/read.json" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF3
printf '{"result":{"worker":{"stage":"ready","state":"running","agent_terminal_handle":"term_w1"}}}\n' > "$TMP/show.json"
python3 -c 'import json; print(json.dumps({"result":{"terminal":{"tail":["working on it"]}}}))' > "$TMP/read.json"
# 2026-10-07T12:00:00Z is 1791374400000 ms; the worker last printed 40 minutes before that
printf '{"result":{"terminals":[{"handle":"term_other","lastOutputAt":1791374399000},{"handle":"term_w1","lastOutputAt":%s}]}}\n' "$((1791374400000 - 40 * 60000))" > "$TMP/list.json"
q() { PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca STAR_NOW=2026-10-07T12:00:00Z "$@" sh "$SCRIPT" ctx_1; }
out=$(q env); [ "$out" = "quiet 40 term_w1" ] && echo "ok   no output for 40 minutes is quiet, with the terminal to write to" || { echo "FAIL quiet worker ($out)"; fails=$((fails + 1)); }
out=$(q env STAR_QUIET_MINUTES=60); [ "$out" = "ok" ] && echo "ok   the quiet threshold can be raised" || { echo "FAIL quiet threshold ($out)"; fails=$((fails + 1)); }
printf '{"result":{"terminals":[{"handle":"term_w1","lastOutputAt":%s}]}}\n' "$((1791374400000 - 3 * 60000))" > "$TMP/list.json"
out=$(q env); [ "$out" = "ok" ] && echo "ok   a worker that printed 3 minutes ago is ok" || { echo "FAIL recent output ($out)"; fails=$((fails + 1)); }
out=$(q env STUB_LIST_FAIL=1); [ "$out" = "ok" ] && echo "ok   an unreadable terminal list never makes a worker quiet" || { echo "FAIL terminal list failure ($out)"; fails=$((fails + 1)); }
printf '{"result":{"terminals":[]}}\n' > "$TMP/list.json"
out=$(q env); [ "$out" = "unknown terminal not listed" ] && echo "ok   a running worker whose terminal is not listed is unknown, not fine" || { echo "FAIL unlisted terminal ($out)"; fails=$((fails + 1)); }
printf '{"result":{"terminals":[{"handle":"term_w1","lastOutputAt":%s}]}}\n' "$((1791374400000 + 30 * 60000))" > "$TMP/list.json"
out=$(q env); [ "$out" = "unknown clock skew" ] && echo "ok   output dated in the future is unknown, not fine" || { echo "FAIL future lastOutputAt ($out)"; fails=$((fails + 1)); }
printf '{"result":{"terminals":[{"handle":"term_w1","lastOutputAt":%s}]}}\n' "$((1791374400000 - 1 * 60000))" > "$TMP/list.json"
for v in 0 -1 nan inf; do out=$(q env STAR_QUIET_MINUTES=$v); [ "$out" = "ok" ] || { echo "FAIL STAR_QUIET_MINUTES=$v made a busy worker ($out)"; fails=$((fails + 1)); }; done; echo "ok   a quiet threshold that is not a positive number falls back to 15"
printf '{"result":{"terminals":[{"handle":"term_w1","lastOutputAt":%s}]}}\n' "$((1791374400000 - 40 * 60000))" > "$TMP/list.json"
python3 -c 'import json; print(json.dumps({"result":{"terminal":{"tail":["Please run /login"]}}}))' > "$TMP/read.json"
python3 -c 'import json; print(json.dumps({"result":{"terminal":{"tail":["Do you want to make this edit to a.py?", "❯ 1. Yes", "  2. No"]}}}))' > "$TMP/read.json"
out=$(q env); [ "$out" = "stuck: confirmation dialog: Do you want to make this edit to a.py?" ] && echo "ok   a permission prompt on a silent terminal is stuck, never quiet" || { echo "FAIL dialog reported as ($out)"; fails=$((fails + 1)); }
python3 -c 'import json; print(json.dumps({"result":{"terminal":{"tail":["Please run /login"]}}}))' > "$TMP/read.json"
out=$(q env); [ "$out" = "stuck: login" ] && echo "ok   a blocking screen wins over quiet" || { echo "FAIL stuck vs quiet ($out)"; fails=$((fails + 1)); }

# orca reports errors as JSON on stdout with exit 1.
cat > "$TMP/bin/orca" <<'EOF2'
#!/bin/sh
printf '{"ok":false,"error":{"code":"%s","message":"x"}}\n' "$STUB_CODE"; exit 1
EOF2
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_CODE=dispatch_not_found ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "gone" ] && echo "ok   dispatch_not_found is gone" || { echo "FAIL dispatch_not_found ($out)"; fails=$((fails + 1)); }
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_CODE=runtime_error ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "unknown runtime_error" ] && echo "ok   other orca errors keep their code" || { echo "FAIL orca error code ($out)"; fails=$((fails + 1)); }

# Second stress pass: real blocking screens, taken from the Claude Code and Codex CLIs
cat > "$TMP/bin/orca" <<'EOF4'
#!/bin/sh
[ -n "${STUB_RAW:-}" ] && { printf '%s\n' "$STUB_RAW"; exit "${STUB_RC:-1}"; }
case "$*" in
  *"terminal list"*) exit 1 ;;
  *worker-show*) cat "$STUB_DIR/show.json" ;;
  *worker-read*) cat "$STUB_DIR/read.json" ;;
esac
EOF4
s() { # s <name> <expected> <line> [second line]
  printf '{"result":{"worker":{"stage":"ready","state":"running"}}}\n' > "$TMP/show.json"
  python3 -c 'import json,sys; print(json.dumps({"result":{"terminal":{"tail":["working on it"] + [a for a in sys.argv[1:] if a]}}}))' "$3" "${4:-}" > "$TMP/read.json"
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
  if [ "$out" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got: $out)"; fails=$((fails + 1)); fi
}
s "expired sign-in" "stuck: login" "Authentication required · Sign in again to continue"
s "bad auth token" "stuck: login" "Invalid auth token · Fix external auth token"
s "codex sign-in" "stuck: login" "Sign-in required."
s "credit balance" "stuck: usage limit" "Credit balance too low · Add funds: https://console.example"
s "model limit" "stuck: usage limit" "You've reached your Fable limit"
s "codex credit limit" "stuck: usage limit" "You've reached your workspace credit limit"
s "codex out of credits" "stuck: usage limit" "Your workspace is out of credits. Notify owner?"
s "claude model switch options" "stuck: model switch" "❯ 1. Switch to Opus 5.5 and continue" "  2. No, keep my current model"
s "codex model switch" "stuck: model switch" "Switch to gpt-6-luna for lower credit usage?" "  Keep current model"
s "codex approval prompt" "stuck: confirmation dialog: Would you like to run the following command?" "Would you like to run the following command?" "  1. Yes, proceed"
s "a blocking line inside a wide box" "stuck: login" "│ Please run /login$(printf '%250s' '')│"
s "prose that asks to run a command is not a dialog" "ok" "Would you like to run the following command? I can also skip it."
s "a worker's own sentence about keeping a model is not a dialog" "ok" "No, keep my current model"
s "press enter to continue" "stuck: waiting for input" "Press Enter to continue"
s "press enter to connect" "stuck: waiting for input" "Press Enter to connect to the server…"
s "a yes/no prompt" "stuck: waiting for input" "Overwrite config? [y/N]"
s "a password prompt" "stuck: waiting for input" "Password:"
s "a sentence that mentions a password is not a prompt" "ok" "the password: field is validated on submit"
s "a worker saying it will press Enter is not a prompt" "ok" "⏺ Next I fill the email field and press Enter to submit the form."
s "a worker describing a y/n prompt is not at one" "ok" "⏺ Phase 6: the CLI prompt shows Continue (y/n)" "⏺ Now checking the exit code."
s "a y/n prompt on the last line is one" "stuck: waiting for input" "⏺ running the installer" "Continue? (y/n)"
s "an edit permission prompt is a dialog" "stuck: confirmation dialog: Do you want to make this edit to loops.sh?" "Do you want to make this edit to loops.sh?" "❯ 1. Yes"
s "a create permission prompt is a dialog" "stuck: confirmation dialog: Do you want to create notes.md?" "Do you want to create notes.md?" "  2. No, and tell Claude what to do differently"
s "a numbered list in prose is not a dialog" "ok" "Plan:" "1. Yes, rename the column first"
for raw in '{"ok":false,"error":"dispatch_not_found"}' '{"ok":false,"error":{"code":"DISPATCH_NOT_FOUND"}}' '{"ok":false,"error":{"code":"runtime_error","data":{"code":"dispatch_not_found"}}}'; do
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_RAW="$raw" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1 2>&1)
  [ "$out" = "gone" ] && echo "ok   not-found in another shape is still gone" || { echo "FAIL not-found shape $raw ($out)"; fails=$((fails + 1)); }
done
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_RAW='{"ok":false,"error":"boom"}' ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1 2>&1)
case "$out" in "unknown "*) echo "ok   an error given as a string is unknown, not a crash" ;; *) echo "FAIL string error ($out)"; fails=$((fails + 1)) ;; esac

# Orca's failure reason travels with a failed settlement (#7)
printf '{"result":{"worker":{"stage":"settled","state":"failed"},"dispatch":{"status":"failed","last_failure":"agent_prompt_stalled"}}}\n' > "$TMP/show.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "settled failed agent_prompt_stalled" ] && echo "ok   a stalled prompt is named" || { echo "FAIL stalled prompt ($out)"; fails=$((fails + 1)); }
printf '{"result":{"worker":{"stage":"settled","state":"succeeded"},"dispatch":{"status":"completed","lastFailure":"agent_prompt_stalled"}}}\n' > "$TMP/show.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "settled succeeded" ] && echo "ok   a success carries no failure reason" || { echo "FAIL success with old reason ($out)"; fails=$((fails + 1)); }

# every case below uses a lock of its own, never this machine's real screen lock
export JUEL_SCREEN_LOCK="$TMP/screen.lock"
# capacity and rate limits are recoverable: stalled, not stuck, not ok (#41)
cat > "$TMP/bin/orca" <<'EOF5'
#!/bin/sh
case "$*" in
  *"terminal list"*) [ -f "$STUB_DIR/list5.json" ] || exit 1; cat "$STUB_DIR/list5.json" ;;
  *worker-show*) cat "$STUB_DIR/show.json" ;;
  *worker-read*) cat "$STUB_DIR/read.json" ;;
esac
EOF5
s "codex at capacity" "stalled: model at capacity" "Selected model is at capacity. Please try a different model."
s "an overloaded API" "stalled: model at capacity" "API Error: 529 {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\"}}"
s "a rate-limit error" "stalled: model at capacity" "API Error: 429 rate_limit_error"
s "a worker adding a rate limiter is not stalled" "ok" "added a rate limiter to the upload route"
s "a worker handling 429s is not stalled" "ok" "returns 429 Too Many Requests when the limit is hit"
s "a usage limit is still stuck" "stuck: usage limit" "You've hit your usage limit. Upgrade to Pro"
# B-3: the error type names are capacity only on a line that also carries an API error
s "a mid-screen JSON line naming rate_limit_error (code being read) is not stalled" "ok" '    "type": "rate_limit_error",' '  }'
s "code that checks for overloaded_error is not stalled" "ok" '    if (err.type === "overloaded_error") retry();' '  }'
s "a worker's own sentence about overloaded_error is not stalled" "ok" "Next I add a retry with backoff for overloaded_error responses." "Then I run the tests."
s "Claude Code's overloaded API error on the last line is stalled" "stalled: model at capacity" 'API Error: 529 {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
s "an error type in a line that starts with Error: is stalled" "stalled: model at capacity" "Error: overloaded_error, retrying in 5 seconds"
s "an error type next to a 5xx status is stalled" "stalled: model at capacity" "529 overloaded_error"
s "an error type next to a 4xx status is stalled" "stalled: model at capacity" "HTTP 429: rate_limit_error"
s "an error type in an API error line without a status is stalled" "stalled: model at capacity" "API error, retrying: rate_limit_error"

# progress, not the terminal, says whether a worker is stale
mkdir -p "$TMP/home/progress"
printf '{"result":{"worker":{"stage":"ready","state":"running","agent_terminal_handle":"term_w1"}}}\n' > "$TMP/show.json"
python3 -c 'import json; print(json.dumps({"result":{"terminal":{"tail":["working on it"]}}}))' > "$TMP/read.json"
NOW=1791374400
age() { python3 -c 'import os,sys; t=float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$1" "$((NOW - $2 * 60))"; }
pr() { PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca STAR_NOW=2026-10-07T12:00:00Z sh "$SCRIPT" ctx_1 --item ITEM-1 --home "$TMP/home" "$@"; }
: > "$TMP/home/progress/ITEM-1.log"; age "$TMP/home/progress/ITEM-1.log" 10
out=$(pr); [ "$out" = "ok" ] && pass_p=1 || pass_p=0
[ "$pass_p" = 1 ] && echo "ok   a progress line 10 minutes old is ok" || { echo "FAIL fresh progress ($out)"; fails=$((fails + 1)); }
age "$TMP/home/progress/ITEM-1.log" 45
out=$(pr); [ "$out" = "stale 45 term_w1" ] && echo "ok   no progress for 45 minutes is stale" || { echo "FAIL stale ($out)"; fails=$((fails + 1)); }
out=$(pr --deadline 60); [ "$out" = "ok" ] && echo "ok   the deadline can be raised" || { echo "FAIL deadline ($out)"; fails=$((fails + 1)); }
WT="$TMP/wt"; mkdir -p "$WT"; (cd "$WT" && git init -q . && GIT_COMMITTER_DATE="2026-10-07T11:55:00Z" git -c user.email=t@t -c user.name=t commit -q --allow-empty -m work)
# the worktree root and its files are backdated, so only the case's own commit or file sets the time
age "$WT" 120
out=$(pr --worktree "$WT"); [ "$out" = "ok" ] && echo "ok   a commit 5 minutes ago is progress" || { echo "FAIL commit progress ($out)"; fails=$((fails + 1)); }
(cd "$WT" && GIT_COMMITTER_DATE="2026-10-07T11:00:00Z" git -c user.email=t@t -c user.name=t commit -q --amend --allow-empty -m work)
printf 'x\n' > "$WT/edit.txt"; age "$WT/edit.txt" 2; age "$WT" 120
out=$(pr --worktree "$WT"); [ "$out" = "ok" ] && echo "ok   a file the worker just changed is progress" || { echo "FAIL file progress ($out)"; fails=$((fails + 1)); }
# no edit.txt: removing it leaves the root's time fresh, which a probe that read the root as a changed file would call progress
rm -f "$WT/edit.txt"; (cd "$WT" && GIT_COMMITTER_DATE="2026-10-07T11:00:00Z" git -c user.email=t@t -c user.name=t commit -q --amend --allow-empty -m work)
out=$(pr --worktree "$WT"); [ "$out" = "stale 45 term_w1" ] && echo "ok   an old commit and no changed file is stale" || { echo "FAIL old commit, no file ($out)"; fails=$((fails + 1)); }
rm -rf "$TMP/home/progress"
printf '{"result":{"terminals":[{"handle":"term_w1","lastOutputAt":%s}]}}\n' "$((NOW * 1000 - 40 * 60000))" > "$TMP/list5.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca STAR_NOW=2026-10-07T12:00:00Z sh "$SCRIPT" ctx_1 --item ITEM-2 --home "$TMP/home")
[ "$out" = "quiet 40 term_w1" ] && echo "ok   no progress source falls back to the terminal rule" || { echo "FAIL fallback ($out)"; fails=$((fails + 1)); }
rm -f "$TMP/list5.json"

# the item that holds the screen lock is named (#39)
export JUEL_SCREEN_LOCK_POLL=0.2
sleep 300 & WS=$!
sh "$ROOT/skills/ship-ticket/screen-lock.sh" acquire --holder ITEM-1 --pid $WS --wait-max 2 >/dev/null
mkdir -p "$TMP/home/progress"; : > "$TMP/home/progress/ITEM-1.log"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1 --item ITEM-1 --home "$TMP/home")
[ "$out" = "ok holds-screen 0" ] && echo "ok   the screen holder's row says so" || { echo "FAIL holds-screen ($out)"; fails=$((fails + 1)); }
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1 --item ITEM-9 --home "$TMP/home")
[ "$out" = "ok" ] && echo "ok   another row says nothing about the screen" || { echo "FAIL other row ($out)"; fails=$((fails + 1)); }
sh "$ROOT/skills/ship-ticket/screen-lock.sh" release --holder ITEM-1 >/dev/null; kill $WS 2>/dev/null; wait $WS 2>/dev/null
unset JUEL_SCREEN_LOCK JUEL_SCREEN_LOCK_POLL
sh "$SCRIPT" ctx_1 --item ITEM-1 >/dev/null 2>&1; [ $? -eq 64 ] && echo "ok   --item without --home is 64" || { echo "FAIL usage"; fails=$((fails + 1)); }

# the idle-looking holder of #39 is a stale or quiet row: it still names the screen, and for how long
export JUEL_SCREEN_LOCK="$TMP/screen.lock" JUEL_SCREEN_LOCK_POLL=0.2
sleep 300 & WS=$!
sh "$ROOT/skills/ship-ticket/screen-lock.sh" acquire --holder ITEM-1 --pid $WS --wait-max 2 >/dev/null
# 25 and a half minutes after the lock was taken, for the case that counts the minutes
LATER=$(python3 -c 'import time; from datetime import datetime, timezone; print(datetime.fromtimestamp(time.time() + 25 * 60 + 30, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')
mkdir -p "$TMP/home/progress"; : > "$TMP/home/progress/ITEM-1.log"; age "$TMP/home/progress/ITEM-1.log" 45
out=$(pr); [ "$out" = "stale 45 term_w1 holds-screen 0" ] && echo "ok   a stale holder still names the screen" || { echo "FAIL stale holder ($out)"; fails=$((fails + 1)); }
rm -f "$TMP/home/progress/ITEM-1.log"
printf '{"result":{"terminals":[{"handle":"term_w1","lastOutputAt":%s}]}}\n' "$((NOW * 1000 - 40 * 60000))" > "$TMP/list5.json"
out=$(pr); [ "$out" = "quiet 40 term_w1 holds-screen 0" ] && echo "ok   a quiet holder still names the screen" || { echo "FAIL quiet holder ($out)"; fails=$((fails + 1)); }
rm -f "$TMP/list5.json"; : > "$TMP/home/progress/ITEM-1.log"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca STAR_NOW="$LATER" sh "$SCRIPT" ctx_1 --item ITEM-1 --home "$TMP/home")
[ "$out" = "ok holds-screen 25" ] && echo "ok   the holder's row says how many minutes it has held the screen" || { echo "FAIL holds-screen minutes ($out)"; fails=$((fails + 1)); }
sh "$ROOT/skills/ship-ticket/screen-lock.sh" release --holder ITEM-1 >/dev/null; kill $WS 2>/dev/null; wait $WS 2>/dev/null
unset JUEL_SCREEN_LOCK JUEL_SCREEN_LOCK_POLL

# lane d: the probe reads the rendered screen, and answers only a bounded rm/rmdir prompt (#114)
export JUEL_SCREEN_LOCK="$TMP/screen.lock"
cat > "$TMP/bin/orca" <<'EOF6'
#!/bin/sh
case "$*" in
  *"terminal read"*) [ -f "$STUB_DIR/screen.json" ] || exit 1; cat "$STUB_DIR/screen.json" ;;
  *"terminal list"*) exit 1 ;;
  *worker-show*) cat "$STUB_DIR/show.json" ;;
  *worker-read*) cat "$STUB_DIR/read.json" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF6
H114="$TMP/home114"; mkdir -p "$H114/progress"; : > "$H114/progress/ITEM-1.log"; age "$H114/progress/ITEM-1.log" 40
SP=/private/tmp/claude-501/-Users-x-proj/0a1b2c3d/scratchpad
WT114="$TMP/w/app"; mkdir -p "$WT114" "$TMP/w/app2"
# Orca 1.4.198's worker-read: the hook transcript, which never shows a prompt
printf '{"ok":true,"result":{"source":"transcript","transcript":{"messages":[{"role":"assistant","blocks":[{"type":"text","text":"Running the test-coverage review."}]}]}}}\n' > "$TMP/read.json"
# b <name> <expected> <worktree or -> <screen line>...: a worker with a terminal whose screen shows the lines
b() {
  bname=$1 bwant=$2 bwt=$3; shift 3
  printf '{"result":{"worker":{"stage":"ready","state":"running","agent_terminal_handle":"term_w1"}}}\n' > "$TMP/show.json"
  python3 -c 'import json,sys; print(json.dumps({"ok":True,"result":{"terminal":{"handle":"term_w1","source":"screen","tail":sys.argv[1:]}}}))' "$@" > "$TMP/screen.json"
  if [ "$bwt" = - ]; then set --; else set -- --worktree "$bwt"; fi
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca STAR_NOW=2026-10-07T12:00:00Z sh "$SCRIPT" ctx_1 --item ITEM-1 --home "$H114" "$@")
  if [ "$out" = "$bwant" ]; then echo "ok   $bname"; else echo "FAIL $bname (got: $out)"; fails=$((fails + 1)); fi
}
# p <name> <expected> <worktree or -> <command line> [<operand>]: the safety prompt for one Bash command
p() {
  pname=$1 pwant=$2 pwt=$3 pcmd=$4 pop=${5:-'$S/$v'}
  b "$pname" "$pwant" "$pwt" "⏺ Task(Analyze test coverage)" "╭──────────────────────────────╮" "│ Bash command" "│   $pcmd" \
    "│   Remove the empty scratch folder" "│ Dangerous rmdir operation on possibly-empty variable path: $pop" \
    "│ Do you want to proceed?" "│ ❯ 1. Yes" "│   2. No" "╰──────────────────────────────╯"
}
STUCK='stuck: confirmation dialog: Dangerous rmdir operation on possibly-empty variable path: $S/$v'
DESC="Remove the empty scratch folder"
stuck_on() { printf 'stuck: confirmation dialog: Dangerous rmdir operation on possibly-empty variable path: %s' "$1"; }
p "the issue's prompt, inside the session scratchpad, is answered" "prompt bounded term_w1 $SP/x" "$WT114" "S=$SP; v=x; rmdir \$S/\$v"
p "a scratchpad spelled under /tmp is answered too" "prompt bounded term_w1 /tmp/claude-501/-Users-x-proj/0a1b2c3d/scratchpad/x" - "S=/tmp/claude-501/-Users-x-proj/0a1b2c3d/scratchpad; v=x; rmdir \$S/\$v"
p "an operand inside the row's worktree is answered" "prompt bounded term_w1 $WT114/build/out" "$WT114" "W=$WT114; v=out; rm -rf \$W/build/\$v" '$W/build/$v'
p "quoted values and the \${NAME} form are read" "prompt bounded term_w1 $SP/x" "$WT114" "S=\"$SP\"; v='x'; rmdir \${S}/\${v}" '${S}/${v}'
p "an operand outside both roots goes to the owner" "$STUCK" "$WT114" "S=/Users/x/Documents; v=x; rmdir \$S/\$v"
p "a worktree path without --worktree goes to the owner" 'stuck: confirmation dialog: Dangerous rmdir operation on possibly-empty variable path: $W/build/$v' - "W=$WT114; v=out; rm -rf \$W/build/\$v" '$W/build/$v'
# Review Focus 2: near misses never answer
p "a scratchpad look-alike user folder goes to the owner" "$STUCK" - "S=/tmp/claude-501x/-Users-x-proj/0a1b2c3d/scratchpad; v=x; rmdir \$S/\$v"
p "a scratchpad look-alike folder name goes to the owner" "$STUCK" - "S=/tmp/claude-501/a/b/scratchpadx; v=x; rmdir \$S/\$v"
p "a worktree prefix trick goes to the owner" 'stuck: confirmation dialog: Dangerous rmdir operation on possibly-empty variable path: $W/x' "$WT114" "W=$TMP/w/app2; rmdir \$W/x" '$W/x'
b "an earlier call's assignment is ignored and the dialog's own command decides" "prompt bounded term_w1 $SP/x" "$WT114" "⏺ Bash(S=/etc; ls \$S)" "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "$DESC" \
  "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "the same command in the transcript line and the dialog is answered" "prompt bounded term_w1 $SP/x" "$WT114" "⏺ Bash(S=$SP; v=x; rmdir \$S/\$v)" "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "$DESC" \
  "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
p "a value holding .. goes to the owner" "$STUCK" - "S=$SP/../../..; v=x; rmdir \$S/\$v"
p "a value holding \$(...) goes to the owner" "$STUCK" - "S=\$(mktemp -d); v=x; rmdir \$S/\$v"
p "a value holding a backtick goes to the owner" "$STUCK" - "S=\`mktemp -d\`; v=x; rmdir \$S/\$v"
p "a value holding ~ goes to the owner" "$STUCK" - "S=~/scratch; v=x; rmdir \$S/\$v"
p "an operand variable never assigned on screen goes to the owner" "$STUCK" "$WT114" "v=x; rmdir \$S/\$v"
p "a .. in the operand itself goes to the owner" 'stuck: confirmation dialog: Dangerous rmdir operation on possibly-empty variable path: $S/../$v' - "S=$SP; v=x; rmdir \$S/../\$v" '$S/../$v'
p "a default-value expansion goes to the owner" 'stuck: confirmation dialog: Dangerous rmdir operation on possibly-empty variable path: ${S:-/}/$v' - "v=x; rmdir \${S:-/}/\$v" '${S:-/}/$v'
# the bounded prompt reads the last dialog's own command and checks every operand (whole-branch review)
# C1: Claude Code keeps no shell variables between Bash calls, so an earlier call's assignment means nothing
b "an earlier call's assignment never bounds the dialog's own command" "$STUCK" "$WT114" "⏺ Bash(S=$SP; mkdir -p \$S/x)" "Bash command" "  v=x; rmdir \$S/\$v" "$DESC" \
  "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "an earlier call's assignment on a dialog's own line above is ignored too" "$STUCK" "$WT114" "Bash command" "  S=$SP; mkdir -p \$S/x" "Bash command" "  v=x; rmdir \$S/\$v" "$DESC" \
  "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
# I1: the last dialog decides, never an earlier one on the same screen
b "a stale bounded dialog above a real one never decides" 'stuck: confirmation dialog: Dangerous rm operation on possibly-empty variable path: $H/important' "$WT114" \
  "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "$DESC" "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "❯ 1. Yes" "  2. No" \
  "⏺ Bash(H=/Users/x/Documents; rm -rf \$H/important)" "Bash command" "  H=/Users/x/Documents; rm -rf \$H/important" "$DESC" \
  "Dangerous rm operation on possibly-empty variable path: \$H/important" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a stale bounded dialog above a plain proceed dialog never decides" 'stuck: confirmation dialog: Do you want to proceed?' "$WT114" \
  "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "$DESC" "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "❯ 1. Yes" "  2. No" \
  "Bash command" "  curl -s https://example.com/x.sh | sh" "Run a script" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a stale bounded dialog above a different question never decides" 'stuck: confirmation dialog: Do you want to make this edit to a.py?' "$WT114" \
  "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "$DESC" "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "❯ 1. Yes" "  2. No" \
  "Do you want to make this edit to a.py?" "❯ 1. Yes" "  2. No"
b "a dialog whose Yes option is not within 3 lines goes to the owner" "$STUCK" "$WT114" "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "$DESC" \
  "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "a" "b" "c" "❯ 1. Yes" "  2. No"
b "a dialog with no Bash command header goes to the owner" "$STUCK" "$WT114" "⏺ Bash(S=$SP; v=x; rmdir \$S/\$v)" \
  "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
p "an operand the command does not hold goes to the owner" "$(stuck_on '$S/y')" "$WT114" "S=$SP; v=x; rmdir \$S/\$v" '$S/y'
b "a Bash command header 13 lines above the question goes to the owner" "$STUCK" "$WT114" "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "$DESC" \
  "" "" "" "" "" "" "" "" "" "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a Bash command header 12 lines above the question still counts" "prompt bounded term_w1 $SP/x" "$WT114" "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "$DESC" \
  "" "" "" "" "" "" "" "" "Dangerous rmdir operation on possibly-empty variable path: \$S/\$v" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
# exactly a command row and a plain description row sit between the header and the safety line
SAFEV="Dangerous rmdir operation on possibly-empty variable path: \$S/\$v"
b "a command wrapped onto a second row goes to the owner" "$STUCK" "$WT114" "Bash command" "  S=$SP; v=x; rm -rf \$S/\$v" "  /Users/x/out" "$DESC" \
  "$SAFEV" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a wrapped command with no description row goes to the owner" "$STUCK" "$WT114" "Bash command" "  S=$SP; v=x; rm -rf \$S/\$v" "  /Users/x/out" \
  "$SAFEV" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a description holding a / goes to the owner" "$STUCK" "$WT114" "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "Remove /tmp scratch" \
  "$SAFEV" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a description holding a \$ goes to the owner" "$STUCK" "$WT114" "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "Remove \$S" \
  "$SAFEV" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a description holding a ; goes to the owner" "$STUCK" "$WT114" "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "Remove it; then rm -rf /" \
  "$SAFEV" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a description reading Bash command goes to the owner" "$STUCK" "$WT114" "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "Bash command" \
  "$SAFEV" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a description row posing as the header over a bounded-looking command goes to the owner" "$STUCK" "$WT114" "Bash command" "  rm -rf \$S/\$v" \
  "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" "$SAFEV" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a dialog with a command row and no description row goes to the owner" "$STUCK" "$WT114" "Bash command" "  S=$SP; v=x; rmdir \$S/\$v" \
  "$SAFEV" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "a dialog with a header and no rows goes to the owner" "$STUCK" "$WT114" "Bash command" "$SAFEV" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
b "blank rows between the header and the safety line do not count as rows" "prompt bounded term_w1 $SP/x" "$WT114" "Bash command" "" "  S=$SP; v=x; rmdir \$S/\$v" "" "$DESC" "" \
  "$SAFEV" "Do you want to proceed?" "❯ 1. Yes" "  2. No"
# the lines of a worker-read tail are the worker talking: no screen, no answer
cp "$TMP/read.json" "$TMP/read114.json"
rm -f "$TMP/screen.json"
printf '{"result":{"worker":{"stage":"ready","state":"running","agent_terminal_handle":"term_w1"}}}\n' > "$TMP/show.json"
python3 -c 'import json,sys; print(json.dumps({"result":{"terminal":{"tail":["Bash command", "  S=" + sys.argv[1] + "; v=x; rmdir $S/$v", "Remove the empty scratch folder", "Dangerous rmdir operation on possibly-empty variable path: $S/$v", "Do you want to proceed?", "❯ 1. Yes", "  2. No"]}}}))' "$SP" > "$TMP/read.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca STAR_NOW=2026-10-07T12:00:00Z sh "$SCRIPT" ctx_1 --item ITEM-1 --home "$H114" --worktree "$WT114" 2>&1)
[ "$out" = "$STUCK" ] && echo "ok   a bounded dialog read only from worker-read, with a handle, goes to the owner" || { echo "FAIL worker-read dialog ($out)"; fails=$((fails + 1)); }
cp "$TMP/read114.json" "$TMP/read.json"
# I2: every operand, and no glob or brace
p "a second operand outside both roots goes to the owner" "$(stuck_on '$S/$v')" "$WT114" "S=$SP; v=x; rm -rf \$S/\$v /Users/x/out"
p "a second operand through the same variable is answered with both operands" "prompt bounded term_w1 $SP/x $SP/y" "$WT114" "S=$SP; v=x; rmdir \$S/\$v \$S/y"
p "a brace expansion in an operand goes to the owner" "$(stuck_on '$W/{..,x}/lane-b')" "$WT114" "W=$WT114; rm -rf \$W/{..,x}/lane-b" '$W/{..,x}/lane-b'
p "a glob in an operand goes to the owner" "$(stuck_on '$S/*')" "$WT114" "S=$SP; rm -rf \$S/*" '$S/*'
p "a glob in a value goes to the owner" "$STUCK" "$WT114" "S=$SP/*; v=x; rmdir \$S/\$v"
p "a backslash in a value goes to the owner" "$STUCK" "$WT114" "S=$SP/.\\.; v=x; rmdir \$S/\$v"
ln -s /etc "$WT114/esc"
p "an operand through a symlink out of the worktree goes to the owner" "$(stuck_on '$W/esc/$v')" "$WT114" "W=$WT114; v=hosts; rm -rf \$W/esc/\$v" '$W/esc/$v'
# M1: only a plain run of assignments, then the removal
p "an unset between the assignment and the removal goes to the owner" "$(stuck_on '$S/x')" "$WT114" "S=$SP; unset S; rmdir \$S/x" '$S/x'
p "a prefix assignment on a command goes to the owner" "$(stuck_on '$HOME/x')" "$WT114" "HOME=$WT114 true; rm -rf \$HOME/x" '$HOME/x'
p "a += append goes to the owner" "$(stuck_on '$S/x')" "$WT114" "S=$SP; S+=/..; rmdir \$S/x" '$S/x'
p "a for loop over the variable goes to the owner" "$(stuck_on '$S/x')" "$WT114" "for S in /; do rmdir \$S/x; done" '$S/x'
p "mixed quoting in a value goes to the owner" "$(stuck_on '$S/x')" "$WT114" "S=$SP\"/y\"; rmdir \$S/x" '$S/x'
p "a statement after the removal goes to the owner" "$(stuck_on '$S/x')" "$WT114" "S=$SP; rmdir \$S/x; echo done" '$S/x'
p "an assignment after the removal goes to the owner" "$(stuck_on '$S/x')" "$WT114" "rmdir \$S/x; S=$SP" '$S/x'
p "a variable assigned twice in the command goes to the owner" "$(stuck_on '$S/x')" "$WT114" "S=$SP; S=/etc; rmdir \$S/x" '$S/x'
p "an assignment no operand uses goes to the owner" "$(stuck_on '$S/x')" "$WT114" "S=$SP; IFS=/; rmdir \$S/x" '$S/x'
p "an assignment to PATH goes to the owner" "$(stuck_on '$PATH/x')" "$WT114" "PATH=$SP/bin; rm -rf \$PATH/x" '$PATH/x'
p "a pipe goes to the owner" "$(stuck_on '$S/x')" "$WT114" "S=$SP; rmdir \$S/x | sh" '$S/x'
p "a command substitution after the removal goes to the owner" "$(stuck_on '$S/x')" "$WT114" "S=$SP; rmdir \$S/x \$(id)" '$S/x'
p "a redirect goes to the owner" "$(stuck_on '$S/x')" "$WT114" "S=$SP; rmdir \$S/x > /tmp/y" '$S/x'
p "a command that is not rm or rmdir goes to the owner" "$(stuck_on '$S/x')" "$WT114" "S=$SP; mv \$S/x /tmp/y" '$S/x'
# M2: strictly below a root, never the root itself
p "the worktree root itself goes to the owner" "$(stuck_on '$W')" "$WT114" "W=$WT114; rm -rf \$W" '$W'
p "the scratchpad root itself goes to the owner" "$(stuck_on '$S')" "$WT114" "S=$SP; rmdir \$S" '$S'
p "the scratchpad root with a trailing slash goes to the owner" "$(stuck_on '$S/')" "$WT114" "S=$SP; rmdir \$S/" '$S/'
b "a permission prompt with no safety line names its question" "stuck: confirmation dialog: Do you want to make this edit to a.py?" - "Do you want to make this edit to a.py?" "❯ 1. Yes" "  2. No"
# #123: a worker left at an empty prompt under Claude Code's "API Error:" line is stalled, whatever
# its progress log says. Claude Code 2.1.301 prints "API Error: <message>" in the turn's output; the
# prompt is a rule row, "❯", a rule row, then the footer ("esc to interrupt" in it while a turn runs)
APIRULE='──────────────────────────────────────────────────────'
APIFOOT='  ⏵⏵ bypass permissions on (shift+tab to cycle)'
b "#123 connection lost mid-response is stalled: api error" "stalled: api error" - "⏺ Running the regression gate." "  ⎿  API Error: Connection lost mid-response. The response above may be incomplete." "" "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
b "#123 server error mid-response is stalled: api error" "stalled: api error" - "⏺ Writing the fix plan." "  ⎿  API Error: Server error mid-response. The response above may be incomplete." "$APIRULE" "❯" "$APIRULE" "$APIFOOT" "  ? for shortcuts"
b "#123 an API error wrapped onto two rows is stalled too" "stalled: api error" - "⏺ Writing the fix plan." "  ⎿  API Error: Connection lost mid-response. The response above may be" "     incomplete." "$APIRULE" "$(printf '❯\302\240')" "$APIRULE" "$APIFOOT"
b "#123 a capacity API error keeps its label" "stalled: model at capacity" - '  ⎿  API Error: 529 {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}' "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
b "#123 an API error that asks for /login is still stuck: login" "stuck: login" - "  ⎿  API Error: 401 · Please run /login" "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
b "#123 docs that name API Error: are not a stall" "stale 40 term_w1" - "⏺ The docs say Claude Code prints API Error: <message> when a call fails." "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
b "#123 code that checks for API Error: is not a stall" "stale 40 term_w1" - "⏺ Read(src/errors.ts)" "  ⎿  if (line.startsWith('API Error:')) retry();" "" "✽ Reading… (12s · esc to interrupt)" "$APIRULE" "❯ " "$APIRULE" "  ⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt"
b "#123 an API error above further output is not a stall" "stale 40 term_w1" - "  ⎿  API Error: Connection lost mid-response. The response above may be incomplete." "⏺ Retried the call; the gate is green." "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
b "#123 a Retrying line is not a stall" "stale 40 term_w1" - "  ⎿  API Error: Connection lost mid-response · Retrying in 4 seconds… (attempt 2/10)" "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
b "#123 an API error under a running turn is not a stall" "stale 40 term_w1" - "  ⎿  API Error: Server error mid-response. The response above may be incomplete." "$APIRULE" "❯ " "$APIRULE" "  ⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt"
b "#123 an API error above a prompt a person is typing in is not a stall" "stale 40 term_w1" - "  ⎿  API Error: Connection lost mid-response. The response above may be incomplete." "$APIRULE" "❯ continue" "$APIRULE" "$APIFOOT"
# review fixes (#123): the timer of the issue keeps the progress log fresh, Claude Code prints its
# recap under an idle error, a boxed prompt counts, and only Claude Code's own error row is an error
age "$H114/progress/ITEM-1.log" 1
b "#123 a fresh progress log does not hide an API error" "stalled: api error" - "⏺ Running the regression gate." "  ⎿  API Error: Connection lost mid-response. The response above may be incomplete." "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
b "#123 a fresh progress log and a plain prompt stay ok" "ok" - "⏺ Running the regression gate." "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
b "#123 a recap under the API error is still stalled" "stalled: api error" - "  ⎿  API Error: Connection lost mid-response. The response above may be incomplete." "" "※ recap: Was running the gate when the call failed." "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
b "#123 a wrapped recap under the API error is still stalled" "stalled: api error" - "  ⎿  API Error: Server error mid-response. The response above may be incomplete." "※ recap: Was writing the fix plan for the second gate round when the model call failed and" "  nothing has run since." "$APIRULE" "❯" "$APIRULE" "$APIFOOT"
b "#123 an API error above a boxed prompt is stalled" "stalled: api error" - "  ⎿  API Error: Connection lost mid-response." "╭────────────────────────╮" "│ >                      │" "╰────────────────────────╯" "  ? for shortcuts"
b "#123 a recap alone is not an API error" "ok" - "⏺ Opened the PR." "※ recap: Opened PR #12." "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
b "#123 a wrapped row of the worker's own text is not an API error row" "ok" - "⏺ The handler now logs the line" "  API Error: Connection lost mid-response and retries." "$APIRULE" "❯ " "$APIRULE" "$APIFOOT"
age "$H114/progress/ITEM-1.log" 40
# the screen decides: a stale worker on a prompt is never stale, and a screen that cannot be read falls back
rm -f "$TMP/screen.json"
printf '{"result":{"worker":{"stage":"ready","state":"running","agent_terminal_handle":"term_w1"}}}\n' > "$TMP/show.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca STAR_NOW=2026-10-07T12:00:00Z sh "$SCRIPT" ctx_1 --item ITEM-1 --home "$H114" 2>&1)
[ "$out" = "stale 40 term_w1" ] && echo "ok   a screen that cannot be read falls back to worker-read, without a crash" || { echo "FAIL failed screen read ($out)"; fails=$((fails + 1)); }
printf '{"ok":true,"result":{"terminal":{"handle":"term_w1","source":"screen-unavailable","tail":[]}}}\n' > "$TMP/screen.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca STAR_NOW=2026-10-07T12:00:00Z sh "$SCRIPT" ctx_1 --item ITEM-1 --home "$H114" 2>&1)
[ "$out" = "stale 40 term_w1" ] && echo "ok   an unavailable screen falls back to worker-read" || { echo "FAIL unavailable screen ($out)"; fails=$((fails + 1)); }
rm -f "$TMP/screen.json"
printf '{"ok":true,"result":{"source":"transcript","transcript":{"messages":[{"role":"user","blocks":[{"type":"text","text":"hello"}]},{"role":"assistant","blocks":[{"type":"text","text":"Not logged in · Please run /login"}]}]}}}\n' > "$TMP/read.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca STAR_NOW=2026-10-07T12:00:00Z sh "$SCRIPT" ctx_1 --item ITEM-1 --home "$H114" 2>&1)
[ "$out" = "stuck: login" ] && echo "ok   the 1.4.198 transcript's newest message is read when there is no screen" || { echo "FAIL transcript shape ($out)"; fails=$((fails + 1)); }
# no terminal handle: the old tail is still read, and a prompt there is never answered (nothing to answer it in)
printf '{"result":{"worker":{"stage":"ready","state":"running"}}}\n' > "$TMP/show.json"
python3 -c 'import json,sys; print(json.dumps({"result":{"terminal":{"tail":["S=" + sys.argv[1] + "; v=x; rmdir $S/$v", "Dangerous rmdir operation on possibly-empty variable path: $S/$v", "Do you want to proceed?", "❯ 1. Yes", "  2. No"]}}}))' "$SP" > "$TMP/read.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1 2>&1)
[ "$out" = "$STUCK" ] && echo "ok   with no terminal to answer in, a bounded prompt still goes to the owner" || { echo "FAIL no handle ($out)"; fails=$((fails + 1)); }
unset JUEL_SCREEN_LOCK

# #123: the API error rule reads only the rendered screen: a worker-read tail is never "stalled: api error"
printf '{"result":{"worker":{"stage":"ready","state":"running"}}}\n' > "$TMP/show.json"
python3 -c 'import json; print(json.dumps({"result":{"terminal":{"tail":["  ⎿  API Error: Connection lost mid-response. The response above may be incomplete.", "──────────", "❯ ", "──────────"]}}}))' > "$TMP/read.json"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1 2>&1)
[ "$out" = "ok" ] && echo "ok   #123 a worker-read tail is never stalled: api error" || { echo "FAIL #123 worker-read tail ($out)"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
