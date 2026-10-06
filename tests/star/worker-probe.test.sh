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
[ "$out" = "gone" ] && echo "ok   no worker record is gone" || { echo "FAIL empty worker-show ($out)"; fails=$((fails + 1)); }
# orca reports errors as JSON on stdout with exit 1.
cat > "$TMP/bin/orca" <<'EOF2'
#!/bin/sh
printf '{"ok":false,"error":{"code":"%s","message":"x"}}\n' "$STUB_CODE"; exit 1
EOF2
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_CODE=dispatch_not_found ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "gone" ] && echo "ok   dispatch_not_found is gone" || { echo "FAIL dispatch_not_found ($out)"; fails=$((fails + 1)); }
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_CODE=runtime_error ORCA_CLI_COMMAND=orca sh "$SCRIPT" ctx_1)
[ "$out" = "unknown runtime_error" ] && echo "ok   other orca errors keep their code" || { echo "FAIL orca error code ($out)"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
