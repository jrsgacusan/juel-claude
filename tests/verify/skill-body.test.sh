#!/bin/sh
# Guards on skills/verify/SKILL.md: the Electron surface (#74).
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/verify/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
gin() { printf '%s\n' "$2" | grep -qF -- "$3" && pass "$1" || fail "$1"; }
step2=$(sed -n '/^### Step 2:/,/^### Step 3:/p' "$SKILL")
gin "EL1 Step 2's table has an Electron window row" "$step2" '| Electron window |'
gin "EL2 hidden-window attaches a Playwright script over CDP" "$step2" 'chromium.connectOverCDP('
gin "EL3 the debugging port is a free port" "$step2" '--remote-debugging-port=<port>'
gin "EL4 a main-process check uses _electron.launch without the port" "$step2" '`_electron.launch` instead, without `--remote-debugging-port`'
gin "EL5 free memory is checked before each launch" "$step2" 'hostGate.minFreeGB'
gin "EL6 the brief can name a launch helper" "$step2" 'helper: <path>'
gin "EL7 never the user's own profile" "$step2" "never the user's own profile"
gin "EL8 cleanup runs when the check fails too" "$step2" 'also when the check fails or is stopped'
gin "EL9 packaged builds stay on the screen" "$step2" 'packaged or notarized builds'
gin "EL10 a resource that cannot be neutralised moves the check" "$step2" 'One that cannot be neutralised moves the check to'
for id in playwright-package electron; do
  grep -q "id: $id\$" "$SKILL" && pass "EL11 requires $id" || fail "EL11 requires $id"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d['skills']['verify']['soft'] else 1)" \
    "$ROOT/.claude-plugin/requirements.json" "$id" && pass "EL12 requirements.json lists $id as soft" || fail "EL12 requirements.json lists $id as soft"
done
# audit lane f: the evidence write rule
E2E="$ROOT/references/local-e2e.md"
grep -qF 'Inputs and build output are not evidence' "$E2E" && pass "F5 local-e2e holds the write rule" || fail "F5 local-e2e write rule"
grep -qF 'path, size and sha256' "$E2E" && pass "F5 local-e2e names path, size and sha256" || fail "F5 local-e2e path, size and sha256"
grep -qF 'as rule 5 of `references/local-e2e.md` says' "$SKILL" && pass "F5 verify points to the write rule" || fail "F5 verify points to the write rule"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
