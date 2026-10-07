#!/bin/sh
# Runs skills/star/messages.sh against a stub orca that answers from numbered files.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/messages.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL messages.sh missing"; exit 1; }
mkdir -p "$TMP/bin" "$TMP/home"
cat > "$TMP/bin/orca" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_DIR/calls"
n=$(cat "$STUB_DIR/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_DIR/n"
f="$STUB_DIR/r$n.json"; [ -f "$f" ] || f="$STUB_DIR/empty.json"
[ -f "$f.exit" ] && { cat "$f"; exit "$(cat "$f.exit")"; }
cat "$f"
EOF
chmod +x "$TMP/bin/orca"
printf '{"ok":true,"result":{"messages":[]}}\n' > "$TMP/empty.json"
reset() { rm -f "$TMP"/r*.json "$TMP"/r*.json.exit "$TMP/n" "$TMP/calls" "$TMP/home/processed.log"; }
M() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" --home "$TMP/home" "$@"; }
hb() { printf '{"id":"%s","type":"heartbeat","subject":"alive","body":"","payload":"{\\"dispatchId\\":\\"ctx_9\\"}","created_at":"2026-10-07T07:00:00Z"}' "$1"; }
done_msg() { printf '{"id":"%s","type":"worker_done","subject":"done","body":"%s","payload":"{\\"dispatchId\\":\\"%s\\"}","created_at":"2026-10-07T07:00:00Z"}' "$1" "$2" "$3"; }

# heartbeats are dropped from a batch that also holds a report
reset
printf '{"ok":true,"result":{"deliveryId":"dl_1","messages":[%s,%s,%s]}}\n' "$(hb msg_h1)" "$(done_msg msg_1 'DONE item=SPH-11 pr=https://x/pull/1' ctx_1)" "$(hb msg_h2)" > "$TMP/r1.json"
out=$(M)
[ "$(printf '%s\n' "$out" | sed -n 1p)" = "delivery dl_1 1" ] && pass "only the report counts" || fail "delivery line ($out)"
[ "$(printf '%s\n' "$out" | sed -n 2p)" = "msg msg_1 worker_done ctx_1 2026-10-07T07:00:00Z" ] && pass "the msg line carries the dispatch" || fail "msg line ($out)"
[ "$(printf '%s\n' "$out" | sed -n 3p)" = "  DONE item=SPH-11 pr=https://x/pull/1" ] && pass "body lines are indented" || fail "body ($out)"
printf '%s\n' "$out" | grep -q heartbeat && fail "a heartbeat leaked" || pass "no heartbeat in the output"

# a heartbeat-only batch without --wait is acknowledged and is none
reset
printf '{"ok":true,"result":{"deliveryId":"dl_2","messages":[%s]}}\n' "$(hb msg_h3)" > "$TMP/r1.json"
[ "$(M)" = "none" ] && grep -q -- '--ack dl_2' "$TMP/calls" && pass "heartbeat-only: acked, none" || fail "heartbeat-only ($(cat "$TMP/calls"))"

# with --wait, a heartbeat-only batch is acked and the wait goes on to the real message
reset
printf '{"ok":true,"result":{"deliveryId":"dl_3","messages":[%s]}}\n' "$(hb msg_h4)" > "$TMP/r1.json"
printf '{"ok":true,"result":{"deliveryId":"dl_4","messages":[%s]}}\n' "$(done_msg msg_2 'FIXED item=A head=abc1234' ctx_2)" > "$TMP/r2.json"
out=$(M --wait --timeout-ms 5000)
[ "$(printf '%s\n' "$out" | sed -n 1p)" = "delivery dl_4 1" ] && sed -n 2p "$TMP/calls" | grep -q -- '--ack dl_3 --wait' && pass "the wait continues after acking heartbeats" || fail "wait after heartbeats ($out / $(cat "$TMP/calls"))"

# --ack is passed through on the first call
reset; M --ack dl_9 >/dev/null
grep -q -- '--ack dl_9' "$TMP/calls" && pass "--ack is passed to orca" || fail "--ack"

# a long body is cut at 12 lines
reset
body=$(i=1; while [ $i -le 14 ]; do printf 'line %s\\n' $i; i=$((i + 1)); done)
printf '{"ok":true,"result":{"deliveryId":"dl_5","messages":[%s]}}\n' "$(done_msg msg_3 "$body" ctx_3)" > "$TMP/r1.json"
out=$(M)
[ "$(printf '%s\n' "$out" | grep -c '^  line')" -eq 12 ] && printf '%s\n' "$out" | grep -qx 'cut 2' && pass "12 body lines, then cut 2" || fail "cut ($out)"

# a raw line break inside a JSON string is still read (printf's format turns \n into a real one)
reset
printf '{"ok":true,"result":{"deliveryId":"dl_6","messages":[{"id":"msg_4","type":"worker_done","body":"VERDICT item=A round=1 SAFE findings=0 head=abc1234\nNOTE: x","payload":{"dispatchId":"ctx_4"},"created_at":"2026-10-07T07:00:00Z"}]}}\n' > "$TMP/r1.json"
out=$(M); printf '%s\n' "$out" | grep -qx '  NOTE: x' && pass "raw newline in a string is read" || fail "lenient JSON ($out)"

# a message already in processed.log is skipped, and an all-processed batch is acked
reset
printf 'msg_5 ctx_5 2026-10-07T07:00:00Z\n' > "$TMP/home/processed.log"
printf '{"ok":true,"result":{"deliveryId":"dl_7","messages":[%s]}}\n' "$(done_msg msg_5 'DONE item=B pr=https://x/pull/2' ctx_5)" > "$TMP/r1.json"
[ "$(M)" = "none" ] && grep -q -- '--ack dl_7' "$TMP/calls" && pass "processed messages are skipped" || fail "processed"

# a question's deadline: default 30, its own deadline=, capped at 240
reset
q() { printf '{"id":"%s","type":"question","body":"%s","payload":"{\\"dispatchId\\":\\"ctx_6\\"}","created_at":"2026-10-07T07:00:00Z"}' "$1" "$2"; }
printf '{"ok":true,"result":{"deliveryId":"dl_8","messages":[%s,%s,%s]}}\n' "$(q msg_6 'Which flag?')" "$(q msg_7 'Sign in to the app please deadline=60')" "$(q msg_8 'Drag the DMG deadline=999')" > "$TMP/r1.json"
out=$(M)
printf '%s\n' "$out" | grep -qx 'msg msg_6 question ctx_6 2026-10-07T07:00:00Z deadline=2026-10-07T07:30:00Z' && pass "default deadline 30 minutes" || fail "default deadline ($out)"
printf '%s\n' "$out" | grep -q 'msg_7 .*deadline=2026-10-07T08:00:00Z' && pass "deadline=60 from the question" || fail "deadline=60"
printf '%s\n' "$out" | grep -q 'msg_8 .*deadline=2026-10-07T11:00:00Z' && pass "a deadline over 240 is cut to 240" || fail "deadline cap"

# a "Rejected heartbeat" notice and other types are dropped
reset
printf '{"ok":true,"result":{"deliveryId":"dl_9","messages":[{"id":"msg_9","type":"escalation","subject":"Rejected heartbeat: alive","body":"Orca rejected this heartbeat","created_at":"2026-10-07T07:00:00Z"},{"id":"msg_10","type":"status","body":"x","created_at":"2026-10-07T07:00:00Z"}]}}\n' > "$TMP/r1.json"
[ "$(M)" = "none" ] && pass "rejected-heartbeat notices and other types are dropped" || fail "rejected heartbeat"

# Review Focus 1: a wait that times out is none, not unknown
reset
printf '{"ok":false,"error":{"code":"timeout","message":"no message before the timeout"}}\n' > "$TMP/r1.json"; echo 1 > "$TMP/r1.json.exit"
[ "$(M --wait --timeout-ms 100)" = "none" ] && pass "a timed-out wait is none" || fail "timeout ($(M --wait --timeout-ms 100))"

# Review Focus 5: Orca replaying the same heartbeat delivery forever ends in none
reset
i=1; while [ $i -le 60 ]; do printf '{"ok":true,"result":{"deliveryId":"dl_x","messages":[%s]}}\n' "$(hb msg_hx)" > "$TMP/r$i.json"; i=$((i + 1)); done
[ "$(M --wait --timeout-ms 600000)" = "none" ] && [ "$(wc -l < "$TMP/calls")" -le 52 ] && pass "a replay loop gives up" || fail "replay loop ($(wc -l < "$TMP/calls") calls)"

# orca failing is unknown
reset; printf 'runtime not reachable\n' > "$TMP/r1.json"; echo 1 > "$TMP/r1.json.exit"
case "$(M)" in "unknown "*) pass "orca failure is unknown" ;; *) fail "orca failure ($(M))" ;; esac

M --bogus >/dev/null 2>&1; [ $? -eq 64 ] && pass "bad usage is 64" || fail "usage"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
