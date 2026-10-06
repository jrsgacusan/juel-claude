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
[ "$out" = "stuck: confirmation dialog" ] && echo "ok   a question with numbered options is a dialog" || { echo "FAIL real dialog ($out)"; fails=$((fails + 1)); }
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
out=$(q env); [ "$out" = "stuck: confirmation dialog" ] && echo "ok   a permission prompt on a silent terminal is stuck, never quiet" || { echo "FAIL dialog reported as ($out)"; fails=$((fails + 1)); }
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
s "codex approval prompt" "stuck: confirmation dialog" "Would you like to run the following command?" "  1. Yes, proceed"
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
s "an edit permission prompt is a dialog" "stuck: confirmation dialog" "Do you want to make this edit to loops.sh?" "❯ 1. Yes"
s "a create permission prompt is a dialog" "stuck: confirmation dialog" "Do you want to create notes.md?" "  2. No, and tell Claude what to do differently"
s "a numbered list in prose is not a dialog" "ok" "Plan:" "1. Yes, rename the column first"
for raw in '{"ok":false,"error":"dispatch_not_found"}' '{"ok":false,"error":{"code":"DISPATCH_NOT_FOUND"}}' '{"ok":false,"error":{"code":"runtime_error","data":{"code":"dispatch_not_found"}}}'; do
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_RAW="$raw" ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1 2>&1)
  [ "$out" = "gone" ] && echo "ok   not-found in another shape is still gone" || { echo "FAIL not-found shape $raw ($out)"; fails=$((fails + 1)); }
done
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_RAW='{"ok":false,"error":"boom"}' ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1 2>&1)
case "$out" in "unknown "*) echo "ok   an error given as a string is unknown, not a crash" ;; *) echo "FAIL string error ($out)"; fails=$((fails + 1)) ;; esac

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
