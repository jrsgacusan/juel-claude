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
  *"/contents/.github/workflows/"*) n=${2##*/workflows/}; n=${n%%\?*}; f="wf-$n" ;;
  *"/contents/.github/workflows"*) f=workflows ;;
  *) echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
if [ -f "$STUB_DIR/$f.err" ]; then cat "$STUB_DIR/$f.err" >&2; exit 1; fi
cat "$STUB_DIR/$f.json"
EOF
chmod +x "$TMP/bin/gh"; ln -s "$(command -v python3)" "$TMP/bin/python3"
# by default: no rulesets, and classic protection is not readable (404), as for most callers
reset() { rm -f "$TMP"/rules.* "$TMP"/protection.* "$TMP"/workflows.* "$TMP"/wf-* "$TMP/calls"; printf 'gh: HTTP 502\n' > "$TMP/workflows.err"; printf '[]\n' > "$TMP/rules.json"; printf 'gh: Not Found (HTTP 404)\n' > "$TMP/protection.err"; }
R() { PATH="$TMP/bin:/usr/bin:/bin" STUB_DIR="$TMP" sh "$SCRIPT" "$@"; }

reset
[ "$(R o/r main)" = "none" ] && pass "no rules is none" || fail "no rules ($(R o/r main))"

reset; printf 'gh: Resource not accessible by integration (HTTP 403)\n' > "$TMP/protection.err"
[ "$(R o/r main)" = "none" ] && pass "a classic 403 is no classic rule, as a 404 is" || fail "classic 403 ($(R o/r main))"

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

reset; printf '[{"type":"pull_request","parameters":{"required_approving_review_count":0}}]\n' > "$TMP/rules.json"
printf 'HTTP 502: Bad gateway\n' > "$TMP/protection.err"
case "$(R o/r main)" in "unknown "*) pass "an unreadable classic rule is unknown, never required 0" ;; *) fail "unreadable classic ($(R o/r main))" ;; esac

reset; printf '[{"type":"pull_request","parameters":{"required_approving_review_count":0}}]\n' > "$TMP/rules.json"
[ "$(R o/r main)" = "required 0" ] && pass "a classic 404 is no classic rule" || fail "classic 404 ($(R o/r main))"

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

# audit lane d: strict line when the base requires up-to-date branches
reset; printf '[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci"}]}}]\n' > "$TMP/rules.json"
[ "$(R o/r main | tr '\n' ' ')" = "none check ci strict " ] && pass "a strict ruleset prints strict after the checks" || fail "strict ruleset ($(R o/r main))"

# #193: a merge_queue rule prints queue, before strict
reset; printf '[{"type":"merge_queue","parameters":{}},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci"}]}}]\n' > "$TMP/rules.json"
[ "$(R o/r main | tr '\n' ' ')" = "none check ci queue strict " ] && pass "a merge queue rule prints queue before strict" || fail "queue ($(R o/r main))"
# #212: on a queue base, no-merge-group when no workflow at the base declares a merge_group trigger
QUEUE_RULES='[{"type":"merge_queue","parameters":{}},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci"}]}}]'
wf() { # wf <name> <yaml text>: a workflow file at the base, as the contents API returns it
  rm -f "$TMP/workflows.err"
  if [ -f "$TMP/workflows.json" ]; then python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d.append({"name":sys.argv[2],"type":"file"}); json.dump(d,open(sys.argv[1],"w"))' "$TMP/workflows.json" "$1"
  else printf '[{"name":"%s","type":"file"}]\n' "$1" > "$TMP/workflows.json"; fi
  printf '{"content":"%s","encoding":"base64"}\n' "$(printf '%s' "$2" | base64 | tr -d '\n')" > "$TMP/wf-$1.json"
}
reset; printf '%s\n' "$QUEUE_RULES" > "$TMP/rules.json"; wf ci.yml "$(printf 'on:\n  pull_request:\n')"
[ "$(R o/r main | tr '\n' ' ')" = "none check ci queue no-merge-group strict " ] && pass "#212 a queue base with no merge_group workflow prints no-merge-group, between queue and strict" || fail "#212 no-merge-group ($(R o/r main))"
grep -q 'repos/o/r/contents/.github/workflows?ref=main' "$TMP/calls" && pass "#212 the workflows are read at the base" || fail "#212 workflows call ($(cat "$TMP/calls"))"
reset; printf '%s\n' "$QUEUE_RULES" > "$TMP/rules.json"; wf ci.yml "$(printf 'on:\n  pull_request:\n')"; wf queue.yaml "$(printf 'on:\n  merge_group:\n    types: [checks_requested]\n')"
[ "$(R o/r main | tr '\n' ' ')" = "none check ci queue strict " ] && pass "#212 a merge_group trigger in any workflow file prints no warning" || fail "#212 merge_group ($(R o/r main))"
reset; printf '%s\n' "$QUEUE_RULES" > "$TMP/rules.json"; wf ci.yml "$(printf 'on: [push, merge_group]\n')"
[ "$(R o/r main | grep -c no-merge-group)" = 0 ] && pass "#212 the inline list form counts" || fail "#212 inline list"
reset; printf '%s\n' "$QUEUE_RULES" > "$TMP/rules.json"; wf ci.yml "$(printf 'on:\n  push:\n# merge_group: later\n')"
[ "$(R o/r main | grep -c no-merge-group)" = 1 ] && pass "#212 a commented-out trigger does not count" || fail "#212 comment"
reset; printf '%s\n' "$QUEUE_RULES" > "$TMP/rules.json"
[ "$(R o/r main | tr '\n' ' ')" = "none check ci queue strict " ] && pass "#212 workflows that cannot be read print nothing extra" || fail "#212 unreadable ($(R o/r main))"
reset; printf '%s\n' "$QUEUE_RULES" > "$TMP/rules.json"; wf ci.yml "$(printf 'on:\n  pull_request:\n')"; printf 'gh: HTTP 502\n' > "$TMP/wf-ci.yml.err"; rm -f "$TMP/wf-ci.yml.json"
[ "$(R o/r main | grep -c no-merge-group)" = 0 ] && pass "#212 a workflow file that cannot be read prints nothing extra" || fail "#212 unreadable file"
reset; printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[]}}]\n' > "$TMP/rules.json"; wf ci.yml "x"
R o/r main >/dev/null; ! grep -q 'contents' "$TMP/calls" && pass "#212 a base with no queue reads no workflows" || fail "#212 read workflows without a queue"

reset; printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[]}}]\n' > "$TMP/rules.json"
R o/r main | grep -qx queue && fail "queue printed with no merge_queue rule" || pass "no merge_queue rule prints no queue"

reset; printf '[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"required_status_checks":[{"context":"ci"}]}}]\n' > "$TMP/rules.json"
R o/r main | grep -qx strict && fail "a non-strict ruleset printed strict" || pass "a non-strict ruleset prints no strict"

reset; rm -f "$TMP/protection.err"
printf '{"required_status_checks":{"strict":true,"contexts":["build"]}}\n' > "$TMP/protection.json"
[ "$(R o/r main | tr '\n' ' ')" = "none check build strict " ] && pass "strict classic protection prints strict" || fail "strict classic ($(R o/r main))"

reset; rm -f "$TMP/protection.err"
printf '{"required_status_checks":{"strict":true,"contexts":["build"]}}\n' > "$TMP/protection.json"
printf '[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[]}}]\n' > "$TMP/rules.json"
[ "$(R o/r main | grep -cx strict)" = "1" ] && pass "both strict prints strict once" || fail "both strict ($(R o/r main))"

reset; printf 'HTTP 502: Bad gateway\n' > "$TMP/rules.err"
[ "$(R o/r main | grep -c .)" = "1" ] && ! R o/r main | grep -qx strict && pass "an unknown result stays the only line" || fail "unknown only ($(R o/r main))"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
