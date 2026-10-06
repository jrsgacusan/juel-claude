#!/bin/sh
# Runs skills/babysit-pr/pr-state.sh against a stub gh fed from fixture files.
# Usage: sh tests/babysit-pr/pr-state.test.sh   (exit 0 = all cases pass)
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/babysit-pr/pr-state.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PY=$(command -v python3)
fails=0

# The stub: `gh pr view` bumps a call counter; `gh api` reads the current counter.
# A fixture <name>.<n>.json wins over <name>.json for call n. API fixtures are JSONL,
# matching `gh api --paginate ... --jq '.[]'`.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
D="$STUB_FIX"; C="$D/.calls"
if [ "${STUB_FAIL:-}" = 1 ]; then echo "boom" >&2; exit 1; fi
if [ "$1" = "pr" ]; then
  n=$(( $(cat "$C" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$C"; f=pr
else
  n=$(cat "$C" 2>/dev/null || echo 1)
  case "$*" in
    */reviews*) f=reviews ;;
    */pulls/*/comments*) f=inline ;;
    */issues/*/comments*) f=comments ;;
    *) echo "unexpected gh call: $*" >&2; exit 9 ;;
  esac
fi
if [ -f "$D/$f.$n.json" ]; then cat "$D/$f.$n.json"; elif [ -f "$D/$f.json" ]; then cat "$D/$f.json"; fi
EOF
chmod +x "$TMP/bin/gh"
ln -s "$PY" "$TMP/bin/python3"

# fixture <case> <file> <content>
fixture() { mkdir -p "$TMP/fx/$1"; printf '%s\n' "$3" > "$TMP/fx/$1/$2"; }

# run <case> <args...>: output to $TMP/out
run() {
  c=$1; shift
  rm -f "$TMP/fx/$c/.calls"
  PATH="$TMP/bin:/usr/bin:/bin" STUB_FIX="$TMP/fx/$c" BABYSIT_GH_TIMEOUT=5 /bin/sh "$SCRIPT" "$@" > "$TMP/out" 2> "$TMP/err"
  echo $? > "$TMP/rc"
  cat "$TMP/fx/$c/.calls" 2>/dev/null > "$TMP/calls" || echo 0 > "$TMP/calls"
}

# check <name> <python expr over d (dict), rc (int), calls (int)>
check() {
  if "$PY" - "$TMP/out" "$TMP/rc" "$TMP/calls" "$2" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1]).read())
rc = int(open(sys.argv[2]).read())
calls = int(open(sys.argv[3]).read().strip() or 0)
ids = [i["id"] for i in d.get("new_feedback", [])]
assert eval(sys.argv[4]), (d, rc, calls)
PY
  then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

# ---- basic: every source, bots, author, empty bodies, thread replies ----
fixture basic pr.json '{"state":"OPEN","reviewDecision":"CHANGES_REQUESTED","headRefOid":"abc123","author":{"login":"me"},"url":"https://github.com/o/r/pull/7"}'
fixture basic reviews.json '{"id":1,"user":{"login":"linear-code[bot]","type":"Bot"},"state":"COMMENTED","body":"bot says","submitted_at":"2026-10-01T00:01:00Z","html_url":"u1"}
{"id":2,"user":{"login":"mstr-ezra","type":"User"},"state":"APPROVED","body":"","submitted_at":"2026-10-01T01:00:00Z","html_url":"u2"}
{"id":3,"user":{"login":"me","type":"User"},"state":"COMMENTED","body":"self note","submitted_at":"2026-10-01T02:00:00Z","html_url":"u3"}
{"id":4,"user":{"login":"mstr-ezra","type":"User"},"state":"CHANGES_REQUESTED","body":"Please fix X","submitted_at":"2026-10-01T03:00:00Z","html_url":"u4"}
{"id":5,"user":{"login":"mstr-johnpaul","type":"User"},"state":"COMMENTED","body":"","submitted_at":"2026-10-01T04:00:00Z","html_url":"u5"}'
fixture basic inline.json '{"id":501,"user":{"login":"mstr-johnpaul","type":"User"},"body":"rename this","created_at":"2026-10-01T04:00:00Z","html_url":"c501","path":"a.py","line":3,"in_reply_to_id":null}
{"id":502,"user":{"login":"me","type":"User"},"body":"done","created_at":"2026-10-01T05:00:00Z","html_url":"c502","path":"a.py","line":3,"in_reply_to_id":501}
{"id":503,"user":{"login":"mstr-ezra","type":"User"},"body":"agree","created_at":"2026-10-01T06:00:00Z","html_url":"c503","path":"a.py","line":null,"original_line":3,"in_reply_to_id":501}'
fixture basic comments.json '{"id":901,"user":{"login":"linear-code[bot]","type":"Bot"},"body":"linkback","created_at":"2026-10-01T00:00:05Z","html_url":"i901"}
{"id":902,"user":{"login":"mstr-ezra","type":"User"},"body":"also update docs","created_at":"2026-10-01T07:00:00Z","html_url":"i902"}
{"id":903,"user":{"login":"me","type":"User"},"body":"thanks","created_at":"2026-10-01T08:00:00Z","html_url":"i903"}'

run basic 7
check "exit 0" 'rc == 0'
check "bots, author and empty APPROVED/COMMENTED reviews excluded, sorted by time" 'ids == [4, 501, 503, 902]'
check "kinds" '[i["kind"] for i in d["new_feedback"]] == ["review", "inline", "inline", "comment"]'
check "CHANGES_REQUESTED review carries its state and body" 'd["new_feedback"][0]["review_state"] == "CHANGES_REQUESTED" and d["new_feedback"][0]["body"] == "Please fix X"'
check "thread reply keeps in_reply_to and falls back to original_line" 'd["new_feedback"][2]["in_reply_to"] == 501 and d["new_feedback"][2]["line"] == 3'
check "reviewers: humans who reviewed or commented, sorted, no bots or author" 'd["reviewers"] == ["mstr-ezra", "mstr-johnpaul"]'
check "cursor is the newest reported item" 'd["cursor"] == "2026-10-01T07:00:00Z"'
check "pr fields" 'd["state"] == "OPEN" and d["decision"] == "CHANGES_REQUESTED" and d["head"] == "abc123" and d["author"] == "me" and d["url"].endswith("/pull/7")'

run basic 7 --since 2026-10-01T04:00:00Z
check "--since is strict and filters older items" 'ids == [503, 902]'

run basic 7 --since 2026-10-01T07:00:00Z
check "nothing new keeps the input cursor" 'ids == [] and d["cursor"] == "2026-10-01T07:00:00Z"'

# ---- decision empty string becomes null ----
fixture nodecision pr.json '{"state":"OPEN","reviewDecision":"","headRefOid":"h","author":{"login":"me"},"url":"https://github.com/o/r/pull/8"}'
fixture nodecision reviews.json ''
fixture nodecision inline.json ''
fixture nodecision comments.json ''
run nodecision 8
check "empty reviewDecision is null; empty sources ok" 'd["decision"] is None and ids == [] and d["reviewers"] == [] and d["cursor"] is None'

# ---- errors ----
STUB_FAIL=1; export STUB_FAIL
run basic 7
check "gh non-zero becomes error, exit 0" 'rc == 0 and "exited 1" in d["error"] and "boom" in d["error"]'
unset STUB_FAIL

fixture notjson pr.json 'not json'
run notjson 7
check "non-JSON gh output becomes error" 'rc == 0 and "error" in d'

mkdir -p "$TMP/nogh"; ln -s "$PY" "$TMP/nogh/python3"
PATH="$TMP/nogh:/usr/bin:/bin" /bin/sh "$SCRIPT" 7 > "$TMP/out" 2>/dev/null; echo $? > "$TMP/rc"; echo 0 > "$TMP/calls"
check "gh missing becomes error" 'rc == 0 and "not found" in d["error"]'

# ---- --wait ----
fixture wait-approve pr.1.json '{"state":"OPEN","reviewDecision":"","headRefOid":"h","author":{"login":"me"},"url":"https://github.com/o/r/pull/9"}'
fixture wait-approve pr.2.json '{"state":"OPEN","reviewDecision":"REVIEW_REQUIRED","headRefOid":"h","author":{"login":"me"},"url":"https://github.com/o/r/pull/9"}'
fixture wait-approve pr.3.json '{"state":"OPEN","reviewDecision":"APPROVED","headRefOid":"h","author":{"login":"me"},"url":"https://github.com/o/r/pull/9"}'
fixture wait-approve reviews.json ''
fixture wait-approve inline.json ''
fixture wait-approve comments.json ''
run wait-approve 9 --wait --interval 0
check "wait: polls until APPROVED, empty decision never wakes" 'd["wake"] == "approved" and calls == 3 and d["decision"] == "APPROVED"'

fixture wait-feedback pr.json '{"state":"OPEN","reviewDecision":"","headRefOid":"h","author":{"login":"me"},"url":"https://github.com/o/r/pull/10"}'
fixture wait-feedback reviews.json ''
fixture wait-feedback inline.json ''
fixture wait-feedback comments.1.json ''
fixture wait-feedback comments.json '{"id":77,"user":{"login":"mstr-ezra","type":"User"},"body":"nit","created_at":"2026-10-01T09:00:00Z","html_url":"i77"}'
run wait-feedback 10 --wait --interval 0
check "wait: wakes on the first new feedback" 'd["wake"] == "feedback" and calls == 2 and ids == [77]'

fixture wait-closed pr.json '{"state":"MERGED","reviewDecision":"APPROVED","headRefOid":"h","author":{"login":"me"},"url":"https://github.com/o/r/pull/11"}'
fixture wait-closed reviews.json ''
fixture wait-closed inline.json ''
fixture wait-closed comments.json '{"id":78,"user":{"login":"mstr-ezra","type":"User"},"body":"late","created_at":"2026-10-01T09:00:00Z","html_url":"i78"}'
run wait-closed 11 --wait --interval 0
check "wait: closed/merged wins over feedback" 'd["wake"] == "closed" and calls == 1'

run wait-feedback 10 --wait --interval 0 --silence-hours 24 --quiet-since 2020-01-01T00:00:00Z
check "wait: silence fires when quiet too long" 'd["wake"] == "silence" and calls == 1 and d["state"] == "OPEN"'

run wait-feedback 10 --wait --interval 0 --max-seconds 0
check "wait: --max-seconds 0 returns timeout after one poll" 'd["wake"] == "timeout" and calls == 1'

# An interval longer than the budget must still sleep (up to the budget) and poll again,
# not return timeout after a single poll: the unattended form is --interval 600 --max-seconds 540.
t0=$(date +%s)
run wait-feedback 10 --wait --interval 5 --max-seconds 1
t1=$(date +%s)
check "wait: interval longer than the budget still sleeps and polls again" 'd["wake"] == "feedback" and calls == 2'
if [ $((t1 - t0)) -lt 4 ]; then echo "ok   wait: sleep is capped by the budget"; else echo "FAIL wait: sleep is capped by the budget ($((t1 - t0))s)"; fails=$((fails + 1)); fi

STUB_FAIL=1; export STUB_FAIL
run wait-feedback 10 --wait --interval 0
check "wait: three errors in a row wake with errors" 'd["wake"] == "errors" and "exited 1" in d["error"]'
unset STUB_FAIL

echo
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
