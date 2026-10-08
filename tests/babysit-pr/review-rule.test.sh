#!/bin/sh
# Runs skills/babysit-pr/review-rule.sh against a stub gh fed from fixture files.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/babysit-pr/review-rule.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL review-rule.sh missing"; exit 1; }
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/calls"
case "$*" in
  *"/rules/branches/"*) f=rules ;;
  *"/protection"*) f=protection ;;
  *) echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
if [ -f "$STUB_DIR/$f.err" ]; then cat "$STUB_DIR/$f.err" >&2; exit 1; fi
cat "$STUB_DIR/$f.json"
EOF
chmod +x "$TMP/bin/gh"; ln -s "$(command -v python3)" "$TMP/bin/python3"
# by default: no rulesets, and classic protection is not readable (404), as for most callers
reset() { rm -f "$TMP"/rules.* "$TMP"/protection.* "$TMP/calls"; printf '[]\n' > "$TMP/rules.json"; printf 'gh: Not Found (HTTP 404)\n' > "$TMP/protection.err"; }
R() { PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" sh "$SCRIPT" "$@"; }

reset
[ "$(R o/r main)" = "none" ] && pass "no rules is none" || fail "no rules ($(R o/r main))"

reset; printf '[{"type":"pull_request","parameters":{"required_approving_review_count":0}},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"CodeRabbit"},{"context":"ci"}]}}]\n' > "$TMP/rules.json"
out=$(R o/r main)
[ "$(printf '%s\n' "$out" | sed -n 1p)" = "required 0" ] && pass "an explicit zero is required 0" || fail "explicit zero ($out)"
[ "$(printf '%s\n' "$out" | sed -n '2,$p' | tr '\n' ' ')" = "check CodeRabbit check ci " ] && pass "the required checks are listed" || fail "checks ($out)"

reset; printf '[{"type":"pull_request","parameters":{"required_approving_review_count":0}},{"type":"pull_request","parameters":{"required_approving_review_count":2}}]\n' > "$TMP/rules.json"
[ "$(R o/r main)" = "required 2" ] && pass "the highest count wins" || fail "highest count ($(R o/r main))"

reset; rm -f "$TMP/protection.err"
printf '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":["build"]}}\n' > "$TMP/protection.json"
printf '[{"type":"pull_request","parameters":{"required_approving_review_count":0}}]\n' > "$TMP/rules.json"
out=$(R o/r main)
[ "$(printf '%s\n' "$out" | sed -n 1p)" = "required 1" ] && printf '%s\n' "$out" | grep -qx 'check build' && pass "readable classic protection counts, and its higher count wins" || fail "classic protection ($out)"

reset; printf '[{"type":"pull_request","parameters":{}}]\n' > "$TMP/rules.json"
[ "$(R o/r main)" = "required 1" ] && pass "a review rule with no count is read as 1, never 0" || fail "missing count ($(R o/r main))"

reset; printf 'HTTP 502: Bad gateway\n' > "$TMP/rules.err"
case "$(R o/r main)" in "unknown "*) pass "unreadable rules are unknown" ;; *) fail "unreadable ($(R o/r main))" ;; esac

reset; printf 'gh: Not Found (HTTP 404)\n' > "$TMP/rules.err"
[ "$(R o/r main)" = "unknown gh cannot see o/r: export GH_TOKEN for this repository" ] && pass "a repository gh cannot see says how to fix it" || fail "cannot see ($(R o/r main))"

reset; printf '{"x":1}\n' > "$TMP/rules.json"
[ "$(R o/r main)" = "unknown unreadable rules" ] && pass "rules that are not a list are unknown" || fail "shape ($(R o/r main))"

reset; R o/r release/2.0 >/dev/null
grep -q 'repos/o/r/rules/branches/release/2.0' "$TMP/calls" && pass "a base with a slash is read as it is" || fail "slash base ($(cat "$TMP/calls"))"

mkdir -p "$TMP/nogh"; ln -s "$(command -v python3)" "$TMP/nogh/python3"
[ "$(PATH="$TMP/nogh:/usr/bin:/bin" sh "$SCRIPT" o/r main)" = "unknown gh not found on PATH" ] && pass "no gh is unknown" || fail "no gh"

R o/r >/dev/null 2>&1; [ $? -eq 64 ] && pass "a missing base is 64" || fail "usage base"
R norepo main >/dev/null 2>&1; [ $? -eq 64 ] && pass "a repo without its owner is 64" || fail "usage repo"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
