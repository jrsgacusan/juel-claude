#!/bin/sh
# Runs skills/star/gh-token.sh against scratch STAR homes and a stub gh.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/gh-token.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL gh-token.sh missing"; exit 1; }
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
if [ "$1" = auth ] && [ "$2" = token ] && [ "$3" = --user ]; then
  [ "$4" = missing ] && exit 1
  printf 'tok_%s\n' "$4"
  exit 0
fi
exit 9
EOF
chmod +x "$TMP/bin/gh"

write() { mkdir -p "$1"; printf '%s\n' "$2" > "$1/star.json"; }
run() { env -u GH_TOKEN PATH="$TMP/bin:$PATH" sh "$SCRIPT" --home "$1"; }

H1="$TMP/cmd"; write "$H1" '{"tokenCmd": "echo tok_cmd"}'
[ "$(run "$H1")" = tok_cmd ] && pass "tokenCmd is run" || fail "tokenCmd"
H2="$TMP/login"; write "$H2" '{"tokenCmd": null, "ghLogin": "jrs-1"}'
[ "$(run "$H2")" = tok_jrs-1 ] && pass "null tokenCmd uses ghLogin" || fail "null tokenCmd"
H3="$TMP/absent"; write "$H3" '{"ghLogin": "jrs-1"}'
[ "$(run "$H3")" = tok_jrs-1 ] && pass "absent tokenCmd uses ghLogin" || fail "absent tokenCmd"
H4="$TMP/wins"; write "$H4" '{"tokenCmd": "echo tok_cmd", "ghLogin": "jrs-1"}'
[ "$(run "$H4")" = tok_cmd ] && pass "set tokenCmd wins" || fail "tokenCmd precedence"
H5="$TMP/malformed"; write "$H5" '{"tokenCmd": "printf a\nprintf b", "ghLogin": "jrs-1"}'
[ -z "$(run "$H5")" ] && pass "a malformed tokenCmd is not replaced" || fail "malformed tokenCmd"
H6="$TMP/fails"; write "$H6" '{"tokenCmd": "exit 3"}'
out=$(run "$H6"); rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && pass "a failing tokenCmd is silent" || fail "failing tokenCmd"
H7="$TMP/bad-login"; write "$H7" '{"tokenCmd": null, "ghLogin": "bad;login"}'
[ -z "$(run "$H7")" ] && pass "a bad ghLogin is silent" || fail "bad ghLogin"
H8="$TMP/missing-login"; write "$H8" '{"tokenCmd": null, "ghLogin": "missing"}'
[ -z "$(run "$H8")" ] && pass "a missing ghLogin is silent" || fail "missing ghLogin"
[ -z "$(run "$TMP/no-star-json")" ] && pass "a missing star.json is silent" || fail "missing star.json"
H9="$TMP/broken"; mkdir -p "$H9"; printf '{broken\n' > "$H9/star.json"
[ -z "$(run "$H9")" ] && pass "a broken star.json is silent" || fail "broken star.json"
JUEL_STAR_HOME="$H1" out=$(env -u GH_TOKEN PATH="$TMP/bin:$PATH" JUEL_STAR_HOME="$H1" sh "$SCRIPT"); rc=$?
[ "$out" = tok_cmd ] && [ "$rc" -eq 0 ] && pass "JUEL_STAR_HOME supplies the home" || fail "JUEL_STAR_HOME"
out=$(env -u GH_TOKEN PATH="$TMP/bin:$PATH" sh "$SCRIPT" --home 2>/dev/null); rc=$?
[ -z "$out" ] && [ "$rc" -eq 64 ] && pass "--home without a value is bad usage" || fail "--home usage"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
