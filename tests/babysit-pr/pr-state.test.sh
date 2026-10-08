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
if [ "${STUB_FAIL:-}" = 1 ]; then echo "${STUB_MSG:-boom}" >&2; exit 1; fi
[ -n "${STUB_DELAY:-}" ] && sleep "$STUB_DELAY"
if [ "$1" = "pr" ]; then
  n=$(( $(cat "$C" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$C"; f=pr
else
  n=$(cat "$C" 2>/dev/null || echo 1)
  case "$*" in
    */rules/branches/*) f=rules; [ -f "$D/rules.json" ] || { echo '[]'; exit 0; } ;;
    */protection*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    */check-runs*) f=checkruns ;;
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
check "cursor is the newest reported item, with the ids seen in that second" 'd["cursor"] == "2026-10-01T07:00:00Z#902"'
check "pr fields" 'd["state"] == "OPEN" and d["decision"] == "CHANGES_REQUESTED" and d["head"] == "abc123" and d["author"] == "me" and d["url"].endswith("/pull/7")'

run basic 7 --since '2026-10-01T04:00:00Z#501'
check "--since filters older items and the ids already seen in its second" 'ids == [503, 902]'
run basic 7 --since 2026-10-01T04:00:00Z
check "a bare time is strict, as it always was: its own second counts as seen" 'ids == [503, 902]'

run basic 7 --since '2026-10-01T07:00:00Z#902'
check "nothing new keeps the input cursor" 'ids == [] and d["cursor"] == "2026-10-01T07:00:00Z#902"'

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

# A snapshot that takes longer than what is left of the budget is not started: the call returns
# timeout instead of overshooting --max-seconds (4 gh calls at 0.5 s = ~2 s per snapshot).
STUB_DELAY=0.5; export STUB_DELAY
t0=$(date +%s)
run wait-feedback 10 --wait --interval 600 --max-seconds 3
t1=$(date +%s)
unset STUB_DELAY
check "wait: no snapshot started that cannot finish in the budget" 'd["wake"] == "timeout" and calls == 1'
if [ $((t1 - t0)) -le 3 ]; then echo "ok   wait: stays within --max-seconds"; else echo "FAIL wait: stays within --max-seconds ($((t1 - t0))s)"; fails=$((fails + 1)); fi

# A gh call slower than the whole budget is cut off at the budget: the first snapshot (4 calls
# at 2 s each) must not run the call 8 s past --max-seconds 1.
STUB_DELAY=2; export STUB_DELAY
t0=$(date +%s)
run wait-feedback 10 --wait --interval 600 --max-seconds 1
t1=$(date +%s)
unset STUB_DELAY
check "wait: a gh call slower than the budget ends as timeout with the reason" 'd["wake"] == "timeout" and "timed out" in d.get("error", "")'
if [ $((t1 - t0)) -le 3 ]; then echo "ok   wait: a slow first snapshot cannot overrun --max-seconds"; else echo "FAIL wait: slow first snapshot overran --max-seconds ($((t1 - t0))s)"; fails=$((fails + 1)); fi

# The snapshot says whether the PR is a draft and what it targets, so a PR someone turned back
# into a draft, or retargeted, is never reported ready.
fixture draftbase pr.json '{"state":"OPEN","reviewDecision":"APPROVED","headRefOid":"h","isDraft":true,"baseRefName":"release","author":{"login":"me"},"url":"https://github.com/o/r/pull/12"}'
fixture draftbase reviews.json ''
fixture draftbase inline.json ''
fixture draftbase comments.json ''
run draftbase 12
check "snapshot carries draft and base" 'd["draft"] is True and d["base"] == "release"'
run draftbase 12 --wait --interval 0
check "wait: an approved PR that is a draft again wakes as draft, not approved" 'd["wake"] == "draft"'
# An item that shares its second with the cursor is not lost: the cursor carries the ids it has seen.
fixture samesec pr.json '{"state":"OPEN","reviewDecision":"","headRefOid":"h","author":{"login":"me"},"url":"https://github.com/o/r/pull/13"}'
fixture samesec reviews.json ''
fixture samesec inline.json ''
fixture samesec comments.1.json '{"id":11,"user":{"login":"ezra","type":"User"},"body":"first","created_at":"2026-10-01T10:00:05Z","html_url":"i11"}'
fixture samesec comments.json '{"id":11,"user":{"login":"ezra","type":"User"},"body":"first","created_at":"2026-10-01T10:00:05Z","html_url":"i11"}
{"id":12,"user":{"login":"jp","type":"User"},"body":"same second","created_at":"2026-10-01T10:00:05Z","html_url":"i12"}'
run samesec 13
check "first snapshot sees one item" 'ids == [11] and d["cursor"] == "2026-10-01T10:00:05Z#11"'
PATH="$TMP/bin:/usr/bin:/bin" STUB_FIX="$TMP/fx/samesec" BABYSIT_GH_TIMEOUT=5 /bin/sh "$SCRIPT" 13 --since '2026-10-01T10:00:05Z#11' > "$TMP/out" 2> "$TMP/err"; echo $? > "$TMP/rc"
check "an item in the same second as the cursor is still reported, once" 'ids == [12] and d["cursor"] == "2026-10-01T10:00:05Z#11,12"'
PATH="$TMP/bin:/usr/bin:/bin" STUB_FIX="$TMP/fx/samesec" BABYSIT_GH_TIMEOUT=5 /bin/sh "$SCRIPT" 13 --since '2026-10-01T10:00:05Z#11,12' > "$TMP/out" 2> "$TMP/err"; echo $? > "$TMP/rc"
check "and never twice" 'ids == []'
# A review started before the cursor and submitted after it: its inline comments count from the submit time.
fixture lateinline pr.json '{"state":"OPEN","reviewDecision":"","headRefOid":"h","author":{"login":"me"},"url":"https://github.com/o/r/pull/14"}'
fixture lateinline reviews.json '{"id":70,"user":{"login":"ezra","type":"User"},"state":"COMMENTED","body":"","submitted_at":"2026-10-01T10:30:00Z","html_url":"r70"}'
fixture lateinline inline.json '{"id":701,"user":{"login":"ezra","type":"User"},"body":"this leaks a token","created_at":"2026-10-01T10:00:00Z","pull_request_review_id":70,"html_url":"c701","path":"a.py","line":3,"in_reply_to_id":null}'
fixture lateinline comments.json ''
run lateinline 14 --since 2026-10-01T10:15:00Z
check "inline comments are timed by their review's submit time" 'ids == [701]'
# While this run's own replies or mark-ready are deferred, approval must not wake it in a loop.
t0=$(date +%s); run draftbase 12 --wait --interval 600 --max-seconds 2 --hold-approval; t1=$(date +%s)
check "wait --hold-approval: an approved draft waits instead of waking at once" 'd["wake"] == "timeout"'
if [ $((t1 - t0)) -ge 1 ]; then echo "ok   wait --hold-approval really waits"; else echo "FAIL --hold-approval returned at once"; fails=$((fails + 1)); fi
run wait-closed 11 --wait --interval 0 --hold-approval
check "wait --hold-approval: closed still wakes" 'd["wake"] == "closed"'
run wait-feedback 10 --since garbage
check "a --since that is not a time is an error object, not a crash" '"--since" in d.get("error", "") and rc == 0'
run wait-feedback 10 --wait --quiet-since garbage --interval 0
check "a --quiet-since that is not a time is an error object, not a crash" '"--quiet-since" in d.get("error", "") and rc == 0'

STUB_FAIL=1; export STUB_FAIL
run wait-feedback 10 --wait --interval 0
check "wait: three errors in a row wake with errors" 'd["wake"] == "errors" and "exited 1" in d["error"]'
unset STUB_FAIL

# ---- an explicit zero in the base branch's rules (#27) ----
ZR='[{"type":"pull_request","parameters":{"required_approving_review_count":0}},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"CodeRabbit"}]}}]'
PEND='{"state":"OPEN","reviewDecision":"","headRefOid":"h","author":{"login":"me"},"baseRefName":"main","url":"https://github.com/o/r/pull/12","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]}'
GRN='{"state":"OPEN","reviewDecision":"","headRefOid":"h","author":{"login":"me"},"baseRefName":"main","url":"https://github.com/o/r/pull/12","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"CodeRabbit","status":"COMPLETED","conclusion":"SUCCESS"}]}'
fixture zero pr.1.json "$PEND"
fixture zero pr.json "$GRN"
fixture zero rules.json "$ZR"
fixture zero reviews.json ''
fixture zero inline.json ''
fixture zero comments.json ''
fixture zero checkruns.json '{"name":"CodeRabbit","app":{"slug":"coderabbitai"}}'
run zero 12
check "zero required: the snapshot says so" 'd["approval"] == "required" and d["required"] == 0'
check "zero required: a required check that has not reported is pending" 'd["checks"] == "pending"'
run zero 12 --wait --interval 0
check "zero required: wakes approved once every required check is green" 'd["wake"] == "approved" and calls == 2 and d["checks"] == "green"'

fixture zero-cr pr.json "$GRN"
fixture zero-cr rules.json "$ZR"
fixture zero-cr reviews.json '{"id":31,"user":{"login":"mstr-ezra","type":"User"},"state":"CHANGES_REQUESTED","body":"","submitted_at":"2026-10-01T03:00:00Z","html_url":"u31"}'
fixture zero-cr inline.json ''
fixture zero-cr comments.json ''
fixture zero-cr checkruns.json ''
run zero-cr 13 --since 2026-10-01T03:00:00Z --wait --interval 0 --max-seconds 0
check "zero required: changes requested never wakes approved" 'd["wake"] == "timeout" and d["changes_requested"] == ["mstr-ezra"]'

fixture norule pr.json "$GRN"
fixture norule reviews.json ''
fixture norule inline.json ''
fixture norule comments.json ''
run norule 15 --wait --interval 0 --max-seconds 0
check "no review rule: green alone never wakes approved" 'd["wake"] == "timeout" and d["approval"] == "none"'

# ---- bots that review (#27) ----
fixture bots pr.json '{"state":"OPEN","reviewDecision":"REVIEW_REQUIRED","headRefOid":"h","author":{"login":"me"},"baseRefName":"main","url":"https://github.com/o/r/pull/14","statusCheckRollup":[]}'
fixture bots rules.json "$ZR"
fixture bots checkruns.json '{"name":"CodeRabbit","app":{"slug":"coderabbitai"}}
{"name":"lint","app":{"slug":"github-actions"}}'
fixture bots reviews.json '{"id":41,"user":{"login":"coderabbitai[bot]","type":"Bot"},"state":"COMMENTED","body":"2 findings","submitted_at":"2026-10-01T01:00:00Z","html_url":"u41"}'
fixture bots inline.json '{"id":42,"user":{"login":"coderabbitai[bot]","type":"Bot"},"body":"P1: null deref","created_at":"2026-10-01T01:00:00Z","html_url":"c42","path":"a.py","line":9,"in_reply_to_id":null}'
fixture bots comments.json '{"id":43,"user":{"login":"linear[bot]","type":"Bot"},"body":"linkback","created_at":"2026-10-01T00:30:00Z","html_url":"i43"}
{"id":44,"user":{"login":"greptile-apps[bot]","type":"Bot"},"body":"summary","created_at":"2026-10-01T02:00:00Z","html_url":"i44"}
{"id":45,"user":{"login":"github-actions[bot]","type":"Bot"},"body":"coverage","created_at":"2026-10-01T02:30:00Z","html_url":"i45"}'
run bots 14
check "the required-check bot's review and inline findings are feedback" 'ids == [41, 42]'
check "a bot is never a reviewer to re-request" 'd["reviewers"] == []'
run bots 14 --review-bots 'greptile-apps[bot]'
check "a listed bot is kept too; the link-back bot and other bots are not" 'ids == [41, 42, 44]'

# ---- a repository gh cannot see (#27) ----
STUB_FAIL=1; STUB_MSG="GraphQL: Could not resolve to a Repository with the name 'o/r'. (repository)"; export STUB_FAIL STUB_MSG
run basic 7
check "a repository gh cannot see says how to fix it" '"gh cannot see o/r: export GH_TOKEN for this repository" in d["error"]'
unset STUB_FAIL STUB_MSG

echo
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
