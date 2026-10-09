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
mkdir -p "$TMP/bin" "$TMP/nocodex" "$TMP/noexec"
cat > "$TMP/bin/codex" <<'EOF'
#!/bin/sh
[ "$1 $2" = "debug models" ] || { echo "unexpected: $*" >&2; exit 9; }
[ -n "${STUB_RC:-}" ] && exit "$STUB_RC"
cat "$STUB_MODELS"
EOF
chmod +x "$TMP/bin/codex"
printf '#!/bin/sh\nexit 0\n' > "$TMP/noexec/codex"; chmod -x "$TMP/noexec/codex"
ln -s "$(command -v python3)" "$TMP/bin/python3"; ln -s "$(command -v python3)" "$TMP/nocodex/python3"
ln -s "$(command -v python3)" "$TMP/noexec/python3"
MODELS=$FIX
t() { # t <name> <expected> [args...]: the line must match and the exit status must be 0
  name=$1; expected=$2; shift 2
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_MODELS="$MODELS" sh "$SCRIPT" "$@" 2>/dev/null); rc=$?
  if [ "$out" = "$expected" ] && [ "$rc" -eq 0 ]; then pass "$name"; else fail "$name (got: $out, exit $rc)"; fi
}
t "the default is the newest luna at xhigh" "gpt-6-luna xhigh"
t "a retiring luna is never the latest" "gpt-6-luna low" --model latest-luna --effort low
# the fixture ranks gpt-5.5-sol first on purpose: only the legacy rule keeps it from winning
t "latest-sol skips the previous and older sols" "gpt-6.1-sol xhigh" --model latest-sol
t "an effort above the model's highest steps down" "gpt-6-luna max" --model latest-luna --effort ultra
t "a listed id is used as given" "gpt-5.6-luna xhigh" --model gpt-5.6-luna
t "a missing effort takes the highest below it" "gpt-5.5-luna medium" --model gpt-5.5-luna --effort high
t "an effort below the model's lowest takes the lowest" "gpt-5.5-luna low" --model gpt-5.5-luna --effort minimal
t "a hidden model is not listed" "default gpt-7-luna-preview is not listed" --model gpt-7-luna-preview
# the only terra in the fixture calls itself older
t "a family with no current model" "default no current terra model is listed" --model latest-terra
out=$(PATH="$TMP/nocodex:/usr/bin:/bin" sh "$SCRIPT" 2>/dev/null)
[ "$out" = "default codex not found on PATH" ] && pass "no codex is default, not a failure" || fail "no codex ($out)"
out=$(PATH="$TMP/noexec:/usr/bin:/bin" sh "$SCRIPT" 2>/dev/null); rc=$?
case "$out" in
  "default codex could not start: "?*) [ "$rc" -eq 0 ] && pass "a codex that cannot start is default, not a crash" || fail "unstartable codex exit $rc" ;;
  *) fail "unstartable codex ($out)" ;;
esac
out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_MODELS="$FIX" STUB_RC=1 sh "$SCRIPT" 2>/dev/null)
[ "$out" = "default codex debug models exited 1" ] && pass "a failing codex is default" || fail "failing codex ($out)"
printf 'not json\n' > "$TMP/bad.json"; MODELS="$TMP/bad.json"
t "unreadable output is default" "default codex debug models printed something unreadable"
# rows of odd shape: a priority that is null, missing or text goes last and stops nobody
cat > "$TMP/odd.json" <<'EOF'
{"models": [
  {"slug": "odd-null-luna", "visibility": "list", "priority": null, "description": "Fast.", "supported_reasoning_levels": [{"effort": "xhigh"}], "upgrade": null},
  {"slug": "odd-missing-luna", "visibility": "list", "description": "Fast.", "supported_reasoning_levels": [{"effort": "xhigh"}], "upgrade": null},
  {"slug": "odd-text-luna", "visibility": "list", "priority": "first", "description": "Fast.", "supported_reasoning_levels": [{"effort": "xhigh"}], "upgrade": null},
  {"slug": "gpt-6-luna", "visibility": "list", "priority": 5, "description": "Fast.", "supported_reasoning_levels": [{"effort": "low"}, {"effort": "xhigh"}], "upgrade": null},
  {"slug": "bare-luna", "visibility": "list", "priority": 9, "description": "Fast.", "supported_reasoning_levels": [], "upgrade": null}
]}
EOF
MODELS="$TMP/odd.json"
t "a row with no usable priority goes last and stops nobody" "gpt-6-luna xhigh"
t "a model that lists no efforts gets the one asked for" "bare-luna ultra" --model bare-luna --effort ultra
printf '{"models": [{"slug": "gpt-6-luna", "visibility": "list", "priority": 1, "description": "Fast.", "supported_reasoning_levels": 5, "upgrade": null}]}\n' > "$TMP/odd-levels.json"
MODELS="$TMP/odd-levels.json"
t "an effort list of the wrong shape is default, not a crash" "default unexpected catalog shape: TypeError"
# legacy is a legacy word; the older inside bolder and folder is not
cat > "$TMP/words.json" <<'EOF'
{"models": [
  {"slug": "gpt-5-nova", "visibility": "list", "priority": 1, "description": "Legacy coding model.", "supported_reasoning_levels": [{"effort": "xhigh"}], "upgrade": null},
  {"slug": "gpt-6-nova", "visibility": "list", "priority": 2, "description": "Bolder answers for folder-sized tasks.", "supported_reasoning_levels": [{"effort": "xhigh"}], "upgrade": null}
]}
EOF
MODELS="$TMP/words.json"
t "only whole words make a model legacy" "gpt-6-nova xhigh" --model latest-nova
MODELS=$FIX
for v in nan inf 0 abc; do
  out=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_MODELS="$FIX" EXECUTOR_MODEL_TIMEOUT="$v" sh "$SCRIPT" 2>/dev/null); rc=$?
  [ "$out" = "gpt-6-luna xhigh" ] && [ "$rc" -eq 0 ] && pass "a timeout of $v means 30 seconds" || fail "timeout $v ($out, exit $rc)"
done
sh "$SCRIPT" --effort turbo >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown effort is 64" || fail "unknown effort"
sh "$SCRIPT" --model >/dev/null 2>&1; [ $? -eq 64 ] && pass "a flag with no value is 64" || fail "empty flag"
PATH="$TMP/bin:/usr/bin:/bin" STUB_MODELS="$FIX" sh "$SCRIPT" --model latest- >/dev/null 2>&1; [ $? -eq 64 ] && pass "latest- with no family is 64" || fail "empty family"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
