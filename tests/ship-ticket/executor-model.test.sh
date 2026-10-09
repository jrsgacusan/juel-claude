#!/bin/sh
# Runs skills/ship-ticket/executor-model.sh against a stub codex that prints a model catalog.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/ship-ticket/executor-model.sh"
FIX="$ROOT/tests/ship-ticket/fixtures/codex-models-2026-10.json"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL executor-model.sh missing"; exit 1; }
mkdir -p "$TMP/bin" "$TMP/nocodex"
cat > "$TMP/bin/codex" <<'EOF'
#!/bin/sh
[ "$1 $2" = "debug models" ] || { echo "unexpected: $*" >&2; exit 9; }
[ -n "${STUB_RC:-}" ] && exit "$STUB_RC"
cat "$STUB_MODELS"
EOF
chmod +x "$TMP/bin/codex"
ln -s "$(command -v python3)" "$TMP/bin/python3"; ln -s "$(command -v python3)" "$TMP/nocodex/python3"
MODELS=$FIX
t() { # t <name> <expected> [args...]
  name=$1; expected=$2; shift 2
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_MODELS="$MODELS" sh "$SCRIPT" "$@" 2>/dev/null)
  if [ "$out" = "$expected" ]; then pass "$name"; else fail "$name (got: $out)"; fi
}
t "the default is the newest luna at xhigh" "gpt-6-luna xhigh"
t "a retiring luna is never the latest" "gpt-6-luna low" --model latest-luna --effort low
t "latest-sol skips the previous and older sols" "gpt-6.1-sol xhigh" --model latest-sol
t "an effort above the model's highest steps down" "gpt-6-luna max" --model latest-luna --effort ultra
t "a listed id is used as given" "gpt-5.6-luna xhigh" --model gpt-5.6-luna
t "a missing effort takes the highest below it" "gpt-5.5-luna medium" --model gpt-5.5-luna --effort high
t "a hidden model is not listed" "default gpt-7-luna-preview is not listed" --model gpt-7-luna-preview
t "a family with no current model" "default no current terra model is listed" --model latest-terra
out=$(PATH="$TMP/nocodex:/usr/bin:/bin" sh "$SCRIPT" 2>/dev/null)
[ "$out" = "default codex not found on PATH" ] && pass "no codex is default, not a failure" || fail "no codex ($out)"
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_MODELS="$FIX" STUB_RC=1 sh "$SCRIPT" 2>/dev/null)
[ "$out" = "default codex debug models exited 1" ] && pass "a failing codex is default" || fail "failing codex ($out)"
printf 'not json\n' > "$TMP/bad.json"; MODELS="$TMP/bad.json"
t "unreadable output is default" "default codex debug models printed something unreadable"
MODELS=$FIX
sh "$SCRIPT" --effort turbo >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown effort is 64" || fail "unknown effort"
sh "$SCRIPT" --model >/dev/null 2>&1; [ $? -eq 64 ] && pass "a flag with no value is 64" || fail "empty flag"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
