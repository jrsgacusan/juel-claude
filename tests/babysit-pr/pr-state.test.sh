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
echo "$*" >> "$D/.log"
if [ "${STUB_FAIL:-}" = 1 ]; then echo "${STUB_MSG:-boom}" >&2; exit 1; fi
[ -n "${STUB_DELAY:-}" ] && sleep "$STUB_DELAY"
if [ "$1" = "pr" ]; then
  n=$(( $(cat "$C" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$C"; f=pr
else
  n=$(cat "$C" 2>/dev/null || echo 1)
  case "$*" in
    */pulls/[!0-9]*|*/issues/[!0-9]*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;  # a REST path takes the number, as the real API does
    */rules/branches/*) f=rules; [ -f "$D/rules.json" ] || { echo '[]'; exit 0; } ;;
    */protection*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    */check-runs*) f=checkruns ;;
    */commits/*/status*) f=statuses ;;
    */reviews*) f=reviews ;;
    */pulls/*/comments*) f=inline ;;
    */pulls/*/commits*) f=commits ;;
    */issues/*/comments*) f=comments ;;
    */issues/*/timeline*) f=timeline ;;
    *) echo "unexpected gh call: $*" >&2; exit 9 ;;
  esac
fi
[ -n "${STUB_FAIL_ROUTE:-}" ] && [ "$STUB_FAIL_ROUTE" = "$f" ] && { echo "boom" >&2; exit 1; }
if [ -f "$D/$f.$n.json" ]; then cat "$D/$f.$n.json"; elif [ -f "$D/$f.json" ]; then cat "$D/$f.json"; fi
EOF
chmod +x "$TMP/bin/gh"
ln -s "$PY" "$TMP/bin/python3"

# fixture <case> <file> <content>
fixture() { mkdir -p "$TMP/fx/$1"; printf '%s\n' "$3" > "$TMP/fx/$1/$2"; }

# run <case> <args...>: output to $TMP/out
run() {
  c=$1; shift
  rm -f "$TMP/fx/$c/.calls" "$TMP/fx/$c/.log"
  PATH="$TMP/bin:/usr/bin:/bin" STUB_FIX="$TMP/fx/$c" BABYSIT_GH_TIMEOUT=5 /bin/sh "$SCRIPT" "$@" > "$TMP/out" 2> "$TMP/err"
  echo $? > "$TMP/rc"
  cat "$TMP/fx/$c/.calls" 2>/dev/null > "$TMP/calls" || echo 0 > "$TMP/calls"
  cat "$TMP/fx/$c/.log" 2>/dev/null > "$TMP/log" || : > "$TMP/log"
}

# check <name> <python expr over d (dict), rc (int), calls (int)>
check() {
  if "$PY" - "$TMP/out" "$TMP/rc" "$TMP/calls" "$2" "$TMP/log" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1]).read())
rc = int(open(sys.argv[2]).read())
calls = int(open(sys.argv[3]).read().strip() or 0)
try:
    log = open(sys.argv[5]).read().splitlines()
except OSError:
    log = []
ids = [i["id"] for i in d.get("new_feedback", [])]
assert eval(sys.argv[4]), (d, rc, calls)
PY
  then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

# check_rc <name> <code>: a usage error, so no JSON on stdout and no gh call at all
check_rc() {
  if [ "$(cat "$TMP/rc")" = "$2" ] && [ ! -s "$TMP/out" ] && [ ! -s "$TMP/log" ]; then echo "ok   $1"
  else echo "FAIL $1 (rc $(cat "$TMP/rc"), $(wc -l < "$TMP/log" | tr -d ' ') gh calls)"; fails=$((fails + 1)); fi
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

# ---- the PR argument: STAR's ledger holds a URL (#70) ----
run basic https://github.com/o/r/pull/7
check "a PR URL gives the same snapshot as its number" 'rc == 0 and "error" not in d and ids == [4, 501, 503, 902]'
run basic https://github.com/o/r/pull/7/files --hosted greptile-apps[bot]
check "a PR URL with a path after the number, and --hosted, still reads the number" 'rc == 0 and "error" not in d and d["hosted"] == "none"'
fixture byname pr.json '{"state":"OPEN","reviewDecision":"","headRefOid":"abc123","author":{"login":"me"},"url":"https://github.com/o/r/pull/7","number":7}'
fixture byname reviews.json ''
fixture byname inline.json ''
fixture byname comments.json '{"id":902,"user":{"login":"mstr-ezra","type":"User"},"body":"also update docs","created_at":"2026-10-01T07:00:00Z","html_url":"i902"}'
run byname feat/my-branch
check "a branch name takes the number gh returned for it" 'rc == 0 and "error" not in d and ids == [902]'

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
run zero 12 --wait --interval 0 --max-seconds 5
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

# A required GitHub Actions job is CI, not a reviewer: its bot counts only when listed.
fixture actions pr.json '{"state":"OPEN","reviewDecision":"REVIEW_REQUIRED","headRefOid":"h","author":{"login":"me"},"baseRefName":"main","url":"https://github.com/o/r/pull/16","statusCheckRollup":[]}'
fixture actions rules.json '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"lint"},{"context":"CodeRabbit"}]}}]'
fixture actions checkruns.json '{"name":"lint","app":{"slug":"github-actions"}}
{"name":"CodeRabbit","app":{"slug":"coderabbitai"}}'
fixture actions reviews.json ''
fixture actions inline.json ''
fixture actions comments.json '{"id":61,"user":{"login":"github-actions[bot]","type":"Bot"},"body":"coverage 91%","created_at":"2026-10-01T02:30:00Z","html_url":"i61"}
{"id":62,"user":{"login":"coderabbitai[bot]","type":"Bot"},"body":"walkthrough","created_at":"2026-10-01T02:40:00Z","html_url":"i62"}'
run actions 16
check "a required Actions job never makes github-actions[bot] feedback" 'ids == [62]'
run actions 16 --review-bots 'github-actions[bot]'
check "--review-bots opts github-actions[bot] in" 'ids == [61, 62] and d["reviewers"] == []'

# ---- a repository gh cannot see (#27) ----
STUB_FAIL=1; STUB_MSG="GraphQL: Could not resolve to a Repository with the name 'o/r'. (repository)"; export STUB_FAIL STUB_MSG
run basic 7
check "a repository gh cannot see says how to fix it" '"gh cannot see o/r: export GH_TOKEN for this repository" in d["error"]'
unset STUB_FAIL STUB_MSG

# ---- the merge state (#58) ----
# mpr <isDraft> <mergeStateStatus> <mergeable>: a PR view with GitHub's two merge fields
mpr() { printf '{"state":"OPEN","reviewDecision":"","headRefOid":"h","isDraft":%s,"mergeStateStatus":"%s","mergeable":"%s","author":{"login":"me"},"url":"https://github.com/o/r/pull/20"}' "$1" "$2" "$3"; }
merge_case() { fixture "$1" pr.json "$(mpr "$2" "$3" "$4")"; for f in reviews inline comments; do fixture "$1" "$f.json" ''; done; }
merge_case m-dirty false DIRTY CONFLICTING
run m-dirty 20
check "merge: DIRTY is dirty" 'd["merge"] == "dirty"'
merge_case m-draft true DRAFT CONFLICTING
run m-draft 20
check "merge: a draft with conflicts is dirty, though GitHub says DRAFT" 'd["merge"] == "dirty"'
merge_case m-behind false BEHIND MERGEABLE
run m-behind 20
check "merge: BEHIND is behind" 'd["merge"] == "behind"'
merge_case m-blocked false BLOCKED MERGEABLE
run m-blocked 20
check "merge: BLOCKED is blocked" 'd["merge"] == "blocked"'
merge_case m-clean false CLEAN MERGEABLE
run m-clean 20
check "merge: CLEAN is clean" 'd["merge"] == "clean"'
merge_case m-unstable false UNSTABLE MERGEABLE
run m-unstable 20
check "merge: UNSTABLE (a red check that is not required) still merges cleanly" 'd["merge"] == "clean"'
merge_case m-unknown false UNKNOWN UNKNOWN
run m-unknown 20
check "merge: still computing is unknown" 'd["merge"] == "unknown"'
run basic 7
check "merge: a PR view without the fields is unknown" 'd["merge"] == "unknown"'

run m-dirty 20 --wait --interval 0 --max-seconds 5
check "wait: a dirty PR wakes conflict at once" 'd["wake"] == "conflict" and calls == 1'
run m-dirty 20 --wait --interval 0 --max-seconds 5 --hold-approval
check "wait: conflict wakes even while approval is held" 'd["wake"] == "conflict"'
fixture m-turns pr.1.json "$(mpr false CLEAN MERGEABLE)"
fixture m-turns pr.json "$(mpr false DIRTY CONFLICTING)"
for f in reviews inline comments; do fixture m-turns "$f.json" ''; done
run m-turns 20 --wait --interval 0 --max-seconds 5
check "wait: a PR that turns dirty while waiting wakes conflict on that poll" 'd["wake"] == "conflict" and calls == 2'
run m-behind 20 --wait --interval 0 --max-seconds 0
check "wait: behind never wakes (CI still runs on a behind head)" 'd["wake"] == "timeout"'
merge_case m-dirty-fb false DIRTY CONFLICTING
fixture m-dirty-fb comments.json '{"id":81,"user":{"login":"mstr-ezra","type":"User"},"body":"see the conflict","created_at":"2026-10-01T09:00:00Z","html_url":"i81"}'
run m-dirty-fb 20 --wait --interval 0
check "wait: new feedback is reported before the conflict" 'd["wake"] == "feedback" and d["merge"] == "dirty"'

# ---- the hosted reviewer: its status on the head, and a summary edited in place (#72) ----
HEADX=abc1234def5678abc1234def5678abc1234def56
hpr() { printf '{"state":"OPEN","reviewDecision":"","headRefOid":"%s","isDraft":false,"mergeStateStatus":"CLEAN","mergeable":"MERGEABLE","baseRefName":"main","author":{"login":"me"},"url":"https://github.com/o/r/pull/30"}' "$HEADX"; }
hosted_case() { fixture "$1" pr.json "$(hpr)"; for f in reviews inline comments; do fixture "$1" "$f.json" ''; done; }
hosted_case h-success
fixture h-success checkruns.json '{"name":"Greptile Review","app":{"slug":"greptile-apps"},"status":"completed","conclusion":"success"}
{"name":"ci","app":{"slug":"github-actions"},"status":"completed","conclusion":"success"}'
run h-success 30 --hosted 'greptile-apps[bot]'
check "hosted: a finished check run of its app is success" 'd["hosted"] == "success"'
run h-success 30
check "hosted: without --hosted the key is null" 'd["hosted"] is None'
hosted_case h-pending
fixture h-pending checkruns.json '{"name":"Greptile Review","app":{"slug":"greptile-apps"},"status":"in_progress","conclusion":null}'
run h-pending 30 --hosted 'greptile-apps[bot]'
check "hosted: a running check run is pending" 'd["hosted"] == "pending"'
hosted_case h-failure
fixture h-failure checkruns.json '{"name":"Greptile Review","app":{"slug":"greptile-apps"},"status":"completed","conclusion":"failure"}'
run h-failure 30 --hosted 'greptile-apps[bot]'
check "hosted: a failed check run is failure" 'd["hosted"] == "failure"'
hosted_case h-none
fixture h-none checkruns.json '{"name":"ci","app":{"slug":"github-actions"},"status":"completed","conclusion":"success"}'
run h-none 30 --hosted 'greptile-apps[bot]'
check "hosted: no run of its app on the head is none" 'd["hosted"] == "none"'
hosted_case h-status
fixture h-status statuses.json '{"context":"Greptile Review","state":"success","creator":{"login":"greptile-apps[bot]"}}'
run h-status 30 --hosted 'greptile-apps[bot]'
check "hosted: a commit status it created counts too" 'd["hosted"] == "success"'
STUB_FAIL_ROUTE=checkruns; export STUB_FAIL_ROUTE
run h-success 30 --hosted 'greptile-apps[bot]'
check "hosted: a check-runs call that fails is unknown, never none" 'd["hosted"] == "unknown"'
unset STUB_FAIL_ROUTE

GOLD='{"id":50,"user":{"login":"greptile-apps[bot]","type":"Bot"},"created_at":"2026-10-01T10:00:00Z","updated_at":"2026-10-01T10:00:00Z","html_url":"i50","body":"Confidence 3/5\n<sub>Last reviewed commit: <a href=\"https://github.com/o/r/commit/0dd0000aaa0dd0000aaa0dd0000aaa0dd0000aaa\">0dd0000</a></sub>"}'
GNEW='{"id":50,"user":{"login":"greptile-apps[bot]","type":"Bot"},"created_at":"2026-10-01T10:00:00Z","updated_at":"2026-10-01T11:00:00Z","html_url":"i50","body":"Confidence 5/5\nLast reviewed commit: [abc1234](https://github.com/o/r/commit/abc1234def5678abc1234def5678abc1234def56)"}'
hosted_case h-edit
fixture h-edit comments.1.json "$GOLD"
fixture h-edit comments.json "$GNEW"
run h-edit 30 --hosted 'greptile-apps[bot]' --since '2026-10-01T10:00:00Z#50'
check "hosted-pass: a summary naming an older head is not feedback" 'ids == []'
run h-edit 30 --hosted 'greptile-apps[bot]' --since '2026-10-01T10:00:00Z#50' --wait --interval 0 --max-seconds 5
check "hosted-pass: the summary edited in place to name the head wakes the wait" 'd["wake"] == "feedback" and calls == 2 and [i["kind"] for i in d["new_feedback"]] == ["hosted-pass"]'
check "hosted-pass: it carries the full head, its edit time and an id that names the edit" 'd["new_feedback"][0]["head"] == "'"$HEADX"'" and d["new_feedback"][0]["at"] == "2026-10-01T11:00:00Z" and ids == ["50@2026-10-01T11:00:00Z"] and d["cursor"] == "2026-10-01T11:00:00Z#50@2026-10-01T11:00:00Z"'
hosted_case h-new
fixture h-new comments.json "$GNEW"
run h-new 30 --hosted 'greptile-apps[bot]' --since '2026-10-01T11:00:00Z#50@2026-10-01T11:00:00Z'
check "hosted-pass: the same edit is never reported twice" 'ids == []'
fixture h-new comments.json "$(printf '%s' "$GNEW" | sed 's/T11:00:00Z/T12:00:00Z/')"
run h-new 30 --hosted 'greptile-apps[bot]' --since '2026-10-01T11:00:00Z#50@2026-10-01T11:00:00Z'
check "hosted-pass: a later edit that names the head again is new (a status refresh)" 'ids == ["50@2026-10-01T12:00:00Z"]'
run h-new 30 --review-bots 'greptile-apps[bot]' --since '2026-10-01T10:00:00Z#50'
check "hosted-pass: --review-bots alone keeps today's plain comment, timed by its creation" 'ids == []'
hosted_case h-first
fixture h-first comments.json "$(printf '%s' "$GNEW" | sed 's/T11:00:00Z/T10:00:00Z/')"
run h-first 30 --hosted 'greptile-apps[bot]' --since 2026-10-01T09:00:00Z
check "hosted-pass: a first summary that names the head is a hosted pass, reported once" '[i["kind"] for i in d["new_feedback"]] == ["hosted-pass"] and ids == ["50@2026-10-01T10:00:00Z"]'
hosted_case h-short
fixture h-short comments.json '{"id":51,"user":{"login":"greptile-apps[bot]","type":"Bot"},"created_at":"2026-10-01T10:00:00Z","updated_at":"2026-10-01T11:30:00Z","html_url":"i51","body":"Last reviewed commit: abc1234"}'
run h-short 30 --hosted 'greptile-apps[bot]' --since '2026-10-01T10:00:00Z#51'
check "hosted-pass: a bare short sha in the footer is read too" 'ids == ["51@2026-10-01T11:30:00Z"]'

# lane c: reviewer mode, a PR someone else authored, watched by the user who reviewed it
HA=aaaaaaa1111111aaaaaaa1111111aaaaaaa11111
HB=bbbbbbb2222222bbbbbbb2222222bbbbbbb22222
HC=ccccccc3333333ccccccc3333333ccccccc33333
# rpr <head> [<state> <decision> <draft> <mergeStateStatus> <mergeable>]: alice's PR #40
rpr() { printf '{"state":"%s","reviewDecision":"%s","headRefOid":"%s","isDraft":%s,"mergeStateStatus":"%s","mergeable":"%s","baseRefName":"main","author":{"login":"alice"},"url":"https://github.com/o/r/pull/40"}' "${2:-OPEN}" "${3:-CHANGES_REQUESTED}" "$1" "${4:-false}" "${5:-CLEAN}" "${6:-MERGEABLE}"; }
RREV='{"id":70,"user":{"login":"me","type":"User"},"state":"CHANGES_REQUESTED","body":"two things","submitted_at":"2026-10-02T09:00:00Z","html_url":"r70"}
{"id":71,"user":{"login":"alice","type":"User"},"state":"COMMENTED","body":"answered inline","submitted_at":"2026-10-02T10:00:00Z","html_url":"r71"}'
RINL='{"id":801,"user":{"login":"me","type":"User"},"body":"this leaks","created_at":"2026-10-02T09:00:00Z","pull_request_review_id":70,"html_url":"c801","path":"a.py","line":3,"in_reply_to_id":null}
{"id":802,"user":{"login":"alice","type":"User"},"body":"fixed in the next push","created_at":"2026-10-02T10:05:00Z","html_url":"c802","path":"a.py","line":3,"in_reply_to_id":801}
{"id":803,"user":{"login":"bob","type":"User"},"body":"+1 on the leak","created_at":"2026-10-02T10:10:00Z","html_url":"c803","path":"a.py","line":3,"in_reply_to_id":801}'
RCOM='{"id":901,"user":{"login":"alice","type":"User"},"body":"pushed","created_at":"2026-10-02T10:20:00Z","html_url":"i901"}
{"id":902,"user":{"login":"bob","type":"User"},"body":"lgtm from me","created_at":"2026-10-02T10:30:00Z","html_url":"i902"}
{"id":903,"user":{"login":"me","type":"User"},"body":"will look","created_at":"2026-10-02T10:40:00Z","html_url":"i903"}'
# The timeline holds the first request (before the user's review), a commit (no created_at), a team
# request and another user's request: none is a re-request of "me" after the review.
RTL='{"event":"review_requested","created_at":"2026-10-02T08:00:00Z","requested_reviewer":{"login":"me","type":"User"}}
{"event":"committed","sha":"x"}
{"event":"review_requested","created_at":"2026-10-02T11:00:00Z","requested_team":{"slug":"core"}}
{"event":"review_requested","created_at":"2026-10-02T11:30:00Z","requested_reviewer":{"login":"carol","type":"User"}}'
RREQ='{"event":"review_requested","created_at":"2026-10-02T12:00:00Z","requested_reviewer":{"login":"me","type":"User"}}'
# reviewer_case <case> <pr json> [<one more timeline line>]
reviewer_case() {
  fixture "$1" pr.json "$2"
  fixture "$1" reviews.json "$RREV"; fixture "$1" inline.json "$RINL"; fixture "$1" comments.json "$RCOM"
  if [ -n "${3:-}" ]; then fixture "$1" timeline.json "$RTL
$3"; else fixture "$1" timeline.json "$RTL"; fi
}
reviewer_case r-base "$(rpr "$HB")"
reviewer_case r-req "$(rpr "$HB")" "$RREQ"

run r-base 40 --reviewed-head "$HA"
check_rc "reviewer flags: --reviewed-head without --as-reviewer is a usage error, before any gh call" 64
run r-base 40 --settle-minutes 5
check_rc "reviewer flags: --settle-minutes without --as-reviewer is a usage error" 64
run r-base 40 --head-seen "$HB@2026-10-02T10:00:00Z"
check_rc "reviewer flags: --head-seen without --as-reviewer is a usage error" 64
run r-base 40 --as-reviewer me
check_rc "reviewer flags: --as-reviewer without --reviewed-head is a usage error" 64
run r-base 40 --as-reviewer '' --reviewed-head "$HA"
check_rc "reviewer flags: an empty --as-reviewer is a usage error" 64
run r-base 40 --as-reviewer me --reviewed-head nothex
check_rc "reviewer flags: a --reviewed-head that is not a sha is a usage error" 64
run r-base 40 --as-reviewer me --reviewed-head "$HA" --settle-minutes -1
check_rc "reviewer flags: a negative --settle-minutes is a usage error" 64
run r-base 40 --as-reviewer me --reviewed-head "$HA" --head-seen "$HB"
check_rc "reviewer flags: a --head-seen without @<iso> is a usage error" 64
run r-base 40 --as-reviewer me --reviewed-head "$HA" --head-seen "$HB@yesterday"
check_rc "reviewer flags: a --head-seen whose time is not ISO is a usage error" 64
run r-base 40 --as-reviewer me --reviewed-head "$HA"
check "reviewer flags: a whole set runs and exits 0" 'rc == 0 and "error" not in d'

run r-base 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z
check "reviewer snapshot: new_feedback holds only the author's items after the cursor" 'ids == [71, 802, 901] and all(i["author"] == "alice" for i in d["new_feedback"])'
check "reviewer snapshot: no reviewers to re-request" 'd["reviewers"] == []'
check "reviewer snapshot: the first request, a team request and another user's request are no re-request" 'd["requested"] is None'
check "reviewer snapshot: head_seen names the full head and a UTC time" 'd["head_seen"].startswith("'"$HB"'@") and d["head_seen"].endswith("Z")'
check "reviewer snapshot: the timeline is read, paginated" 'any("--paginate" in l and "/issues/40/timeline" in l for l in log)'
run r-base 40 --since 2026-10-02T09:00:00Z
check "without --as-reviewer: the author is still excluded, as today" 'ids == [803, 902, 903] and d["reviewers"] == ["bob", "me"]'
check "without --as-reviewer: no requested or head_seen key" '"requested" not in d and "head_seen" not in d'
check "without --as-reviewer: the timeline is never read" 'not any("timeline" in l for l in log)'

run r-req 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z
check "reviewer snapshot: a re-request of the user after the cursor gives its time" 'd["requested"] == "2026-10-02T12:00:00Z"'
run r-req 40 --as-reviewer Me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z
check "reviewer snapshot: the login compares without case, as GitHub logins do" 'd["requested"] == "2026-10-02T12:00:00Z"'
run r-req 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T12:00:00Z
check "reviewer snapshot: a request in the cursor's own second never counts (Review Focus 3)" 'd["requested"] is None'
run r-req 40 --as-reviewer me --reviewed-head "$HA" --since '2026-10-02T12:00:00Z#903'
check "reviewer snapshot: a cursor with ids still counts only requests after its second" 'd["requested"] is None'
run r-req 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T13:00:00Z
check "reviewer snapshot: a request before the cursor never counts" 'd["requested"] is None'

run r-base 40 --as-reviewer me --reviewed-head "$HA" --head-seen "$HB@2026-10-02T10:00:00Z"
check "reviewer snapshot: --head-seen keeps its time while its sha is the head" 'd["head_seen"] == "'"$HB"'@2026-10-02T10:00:00Z"'
run r-base 40 --as-reviewer me --reviewed-head "$HA" --head-seen "bbbbbbb@2026-10-02T10:00:00Z"
check "reviewer snapshot: a short --head-seen sha that starts the head counts; the full head is printed" 'd["head_seen"] == "'"$HB"'@2026-10-02T10:00:00Z"'
run r-base 40 --as-reviewer me --reviewed-head "$HA" --head-seen "$HC@2026-10-02T10:00:00Z"
check "reviewer snapshot: a --head-seen for another sha starts the clock again" 'd["head_seen"].startswith("'"$HB"'@") and not d["head_seen"].endswith("2026-10-02T10:00:00Z")'

STUB_FAIL_ROUTE=timeline; export STUB_FAIL_ROUTE
run r-req 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z
check "reviewer snapshot: a timeline that cannot be read is an error, never 'not requested'" 'rc == 0 and "exited 1" in d.get("error", "")'
unset STUB_FAIL_ROUTE

run r-req 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z --wait --interval 0 --max-seconds 5
check "reviewer wait: a re-request wakes rerequested" 'd["wake"] == "rerequested" and calls == 1'
run r-base 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z --settle-minutes 0 --wait --interval 0 --max-seconds 5
check "reviewer wait: a new head that has stayed put long enough wakes settled" 'd["wake"] == "settled" and calls == 1'
run r-req 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z --settle-minutes 0 --wait --interval 0 --max-seconds 5
check "reviewer wait: a re-request wins over a settled head" 'd["wake"] == "rerequested"'
run r-base 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z --wait --interval 0 --max-seconds 0
check "reviewer wait: a head first seen now is not settled at the default 30 minutes" 'd["wake"] == "timeout"'
run r-base 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z --head-seen "$HB@2020-01-01T00:00:00Z" --wait --interval 0 --max-seconds 5
check "reviewer wait: --head-seen carries an old sighting, so it settles at once" 'd["wake"] == "settled" and d["head_seen"] == "'"$HB"'@2020-01-01T00:00:00Z"'
run r-base 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z --head-seen "$HC@2020-01-01T00:00:00Z" --wait --interval 0 --max-seconds 0
check "reviewer wait: an old sighting of another head does not settle this one" 'd["wake"] == "timeout"'
run r-base 40 --as-reviewer me --reviewed-head "$HB" --since 2026-10-02T09:00:00Z --settle-minutes 0 --wait --interval 0 --max-seconds 0
check "reviewer wait: the reviewed head itself never settles" 'd["wake"] == "timeout"'
run r-base 40 --as-reviewer me --reviewed-head bbbbbbb --since 2026-10-02T09:00:00Z --settle-minutes 0 --wait --interval 0 --max-seconds 0
check "reviewer wait: a short --reviewed-head that starts the head is that head" 'd["wake"] == "timeout"'

# A force-push: the new head is no descendant of the reviewed one. The script never asks git or
# GitHub how two heads relate, so it settles like any other new head.
reviewer_case r-force "$(rpr fffffff9999999fffffff9999999fffffff99999)"
run r-force 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z --settle-minutes 0 --wait --interval 0 --max-seconds 5
check "reviewer wait: a force-pushed head settles like any other new head" 'd["wake"] == "settled" and not any("compare" in l for l in log)'

# One --wait call keeps head_seen across its polls: poll 1 sees the reviewed head, poll 2 the new
# one, and a later poll finds it has stayed put for 0.02 min. Losing head_seen between polls
# would restart the clock every poll and end in timeout.
reviewer_case r-mem "$(rpr "$HB")"
fixture r-mem pr.1.json "$(rpr "$HA")"
run r-mem 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z --settle-minutes 0.02 --wait --interval 0.5 --max-seconds 8
check "reviewer wait: one --wait keeps head_seen across polls, so the new head settles" 'd["wake"] == "settled" and calls >= 3'

reviewer_case r-quiet "$(rpr "$HB" OPEN APPROVED true DIRTY CONFLICTING)"
run r-quiet 40 --as-reviewer me --reviewed-head "$HB" --since 2026-10-02T09:00:00Z --wait --interval 0 --max-seconds 0
check "reviewer wait: the author's comments, a conflict, an approval and a draft never wake it" 'd["wake"] == "timeout" and ids == [71, 802, 901] and d["merge"] == "dirty" and d["decision"] == "APPROVED"'
reviewer_case r-closed "$(rpr "$HB" MERGED APPROVED)" "$RREQ"
run r-closed 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z --settle-minutes 0 --wait --interval 0 --max-seconds 5
check "reviewer wait: closed wins over a re-request and a settled head" 'd["wake"] == "closed"'
run r-quiet 40 --as-reviewer me --reviewed-head "$HB" --since 2026-10-02T09:00:00Z --wait --interval 0 --silence-hours 72 --quiet-since 2020-01-01T00:00:00Z
check "reviewer wait: silence still fires" 'd["wake"] == "silence"'
STUB_FAIL_ROUTE=timeline; export STUB_FAIL_ROUTE
run r-req 40 --as-reviewer me --reviewed-head "$HA" --since 2026-10-02T09:00:00Z --wait --interval 0
check "reviewer wait: three unreadable timelines in a row wake errors" 'd["wake"] == "errors"'
unset STUB_FAIL_ROUTE

# review fixes: a --settle-minutes that is not finite passed the < 0 check and never settled
run r-base 40 --as-reviewer me --reviewed-head "$HA" --settle-minutes nan
check_rc "reviewer flags: --settle-minutes nan is a usage error" 64
run r-base 40 --as-reviewer me --reviewed-head "$HA" --settle-minutes inf
check_rc "reviewer flags: --settle-minutes inf is a usage error" 64
run r-base 40 --as-reviewer me --reviewed-head "$HA" --settle-minutes nan
grep -q 'settle-minutes' "$TMP/err" && echo "ok   reviewer flags: the nan error names the flag" || { echo "FAIL reviewer flags: the nan error names the flag"; fails=$((fails + 1)); }

# lane e: #96 --hosted-passes rebuilds the hosted reviewer's pass log from the PR's reviews
PA=aaaaaaa4444444aaaaaaa4444444aaaaaaa44444
PB=bbbbbbb5555555bbbbbbb5555555bbbbbbb55555
PC=ccccccc6666666ccccccc6666666ccccccc66666
# check_lines <name> <code> <want>: exactly these stdout lines (none when <want> is empty) and this exit code
check_lines() {
  got=$(cat "$TMP/out")
  if [ "$(cat "$TMP/rc")" = "$2" ] && [ "$got" = "$3" ] && { [ -n "$3" ] || [ ! -s "$TMP/out" ]; }; then echo "ok   $1"
  else echo "FAIL $1 (rc $(cat "$TMP/rc"): $got)"; fails=$((fails + 1)); fi
}
# Out of order on purpose: two hosted reviews of head A, one of head B, a pending one on head C, and a human's.
PREV='{"id":93,"user":{"login":"greptile-apps[bot]","type":"Bot"},"state":"COMMENTED","body":"2 findings","commit_id":"'"$PB"'","submitted_at":"2026-10-13T11:00:00Z","html_url":"r93"}
{"id":91,"user":{"login":"greptile-apps[bot]","type":"Bot"},"state":"COMMENTED","body":"3 findings","commit_id":"'"$PA"'","submitted_at":"2026-10-13T09:00:00Z","html_url":"r91"}
{"id":92,"user":{"login":"greptile-apps[bot]","type":"Bot"},"state":"COMMENTED","body":"refreshed","commit_id":"'"$PA"'","submitted_at":"2026-10-13T10:00:00Z","html_url":"r92"}
{"id":94,"user":{"login":"mstr-ezra","type":"User"},"state":"APPROVED","body":"","commit_id":"'"$PC"'","submitted_at":"2026-10-13T12:00:00Z","html_url":"r94"}
{"id":95,"user":{"login":"greptile-apps[bot]","type":"Bot"},"state":"PENDING","body":"","commit_id":"'"$PC"'","html_url":"r95"}'
hosted_case passes
fixture passes reviews.json "$PREV"
PWANT=$(printf '2026-10-13T09:00:00Z pass 1 head=%s\n2026-10-13T11:00:00Z pass 2 head=%s' "$PA" "$PB")
run passes 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "hosted-passes: one pass per distinct head, oldest first; a pending and a human review add none" 0 "$PWANT"
grep -q -- '--paginate repos/o/r/pulls/30/reviews' "$TMP/log" && grep -q -- '--paginate repos/o/r/issues/30/comments' "$TMP/log" && [ "$(wc -l < "$TMP/log" | tr -d ' ')" = 3 ] && echo "ok   hosted-passes: reads the PR, its reviews and its comments, paginated, and nothing else" || { echo "FAIL hosted-passes: gh calls ($(cat "$TMP/log"))"; fails=$((fails + 1)); }
run passes https://github.com/o/r/pull/30 --hosted 'Greptile-Apps[bot]' --hosted-passes
check_lines "hosted-passes: a PR URL and the login in another case read the same passes" 0 "$PWANT"
hosted_case passes-none
fixture passes-none reviews.json '{"id":96,"user":{"login":"mstr-ezra","type":"User"},"state":"COMMENTED","body":"nit","commit_id":"'"$PA"'","submitted_at":"2026-10-13T09:00:00Z","html_url":"r96"}'
run passes-none 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "hosted-passes: no review by the hosted login prints nothing, exit 0" 0 ''
STUB_FAIL_ROUTE=reviews; export STUB_FAIL_ROUTE
run passes 30 --hosted 'greptile-apps[bot]' --hosted-passes
unset STUB_FAIL_ROUTE
check_lines "hosted-passes: reviews GitHub cannot read print one error line, exit 1" 1 'error gh exited 1: boom'
run passes 30 --hosted-passes
check_rc "hosted-passes: without --hosted is a usage error, before any gh call" 64
run passes 30 --hosted 'greptile-apps[bot]' --hosted-passes --wait
check_rc "hosted-passes: with --wait is a usage error" 64
run passes 30 --hosted 'greptile-apps[bot]' --hosted-passes --as-reviewer me --reviewed-head "$PA"
check_rc "hosted-passes: with --as-reviewer is a usage error" 64

# lane c: #116 --hosted-passes also counts a pass the hosted reviewer left only as its summary comment
# gpc <id> <login> <updated_at> <footer>: a conversation comment, created an hour before it was last edited
gpc() { printf '{"id":%s,"user":{"login":"%s","type":"Bot"},"created_at":"2026-10-13T00:00:00Z","updated_at":"%s","html_url":"c%s","body":"Confidence 4/5\\n%s"}' "$1" "$2" "$3" "$1" "$4"; }
hosted_case hp-comment
fixture hp-comment comments.json "$(gpc 60 'greptile-apps[bot]' 2026-10-13T08:00:00Z "Last reviewed commit: [abc1234](https://github.com/o/r/commit/$HEADX)")"
run hp-comment 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "#116 a summary comment alone is a pass, timed by its last edit" 0 "2026-10-13T08:00:00Z pass 1 head=$HEADX"
grep -q -- '--paginate repos/o/r/issues/30/comments' "$TMP/log" && ! grep -q 'pulls/30/commits' "$TMP/log" && echo "ok   #116 reads the comments, paginated, and no commit list when every footer sha is full" || { echo "FAIL #116 comment calls ($(cat "$TMP/log"))"; fails=$((fails + 1)); }
hosted_case hp-same
fixture hp-same reviews.json "$PREV"
fixture hp-same comments.json "$(gpc 61 'greptile-apps[bot]' 2026-10-13T12:30:00Z 'Last reviewed commit: aaaaaaa')"
run hp-same 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "#116 a footer naming a head a review names adds no line, and the review's time stands" 0 "$PWANT"
hosted_case hp-order
fixture hp-order reviews.json '{"id":97,"user":{"login":"greptile-apps[bot]","type":"Bot"},"state":"COMMENTED","body":"1 finding","commit_id":"'"$PA"'","submitted_at":"2026-10-13T09:00:00Z","html_url":"r97"}'
fixture hp-order comments.json "$(gpc 62 'greptile-apps[bot]' 2026-10-13T08:30:00Z "<sub>Last reviewed commit: <a href=\\\"https://github.com/o/r/commit/$PB\\\">bbbbbbb</a></sub>")"
run hp-order 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "#116 a review of one head and a footer naming another are two passes, by time" 0 "$(printf '2026-10-13T08:30:00Z pass 1 head=%s\n2026-10-13T09:00:00Z pass 2 head=%s' "$PB" "$PA")"
hosted_case hp-none
fixture hp-none comments.json "$(gpc 63 'greptile-apps[bot]' 2026-10-13T08:00:00Z 'no footer here')
$(gpc 64 'mstr-ezra' 2026-10-13T08:00:00Z "Last reviewed commit: $PA")"
run hp-none 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "#116 a comment with no footer, or a footer by someone else, is no pass" 0 ''
hosted_case hp-short
fixture hp-short comments.json "$(gpc 65 'greptile-apps[bot]' 2026-10-13T08:00:00Z 'Last reviewed commit: abc1234')"
run hp-short 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "#116 a bare short footer sha is expanded from the PR's head" 0 "2026-10-13T08:00:00Z pass 1 head=$HEADX"
hosted_case hp-commits
fixture hp-commits comments.json "$(gpc 66 'greptile-apps[bot]' 2026-10-13T08:00:00Z 'Last reviewed commit: ccccccc')"
fixture hp-commits commits.json '{"sha":"'"$PA"'"}
{"sha":"'"$PC"'"}'
run hp-commits 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "#116 a short footer sha no review or head names is expanded from the PR's commits" 0 "2026-10-13T08:00:00Z pass 1 head=$PC"
grep -q -- '--paginate repos/o/r/pulls/30/commits' "$TMP/log" && echo "ok   #116 the commit list is read, paginated, only to expand a short sha" || { echo "FAIL #116 commits call ($(cat "$TMP/log"))"; fails=$((fails + 1)); }
hosted_case hp-unknown
fixture hp-unknown comments.json "$(gpc 67 'greptile-apps[bot]' 2026-10-13T08:00:00Z 'Last reviewed commit: eeeeeee')"
fixture hp-unknown commits.json '{"sha":"'"$PA"'"}'
run hp-unknown 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "#116 a short footer sha nothing resolves still counts, printed as given" 0 "2026-10-13T08:00:00Z pass 1 head=eeeeeee"
STUB_FAIL_ROUTE=comments; export STUB_FAIL_ROUTE
run hp-comment 30 --hosted 'greptile-apps[bot]' --hosted-passes
unset STUB_FAIL_ROUTE
check_lines "#116 comments GitHub cannot read print one error line, exit 1" 1 'error gh exited 1: boom'
STUB_FAIL_ROUTE=commits; export STUB_FAIL_ROUTE
run hp-commits 30 --hosted 'greptile-apps[bot]' --hosted-passes
unset STUB_FAIL_ROUTE
check_lines "#116 a commit list GitHub cannot read prints one error line, exit 1" 1 'error gh exited 1: boom'

echo
# star-issues-remaining #129: a hosted run that reviewed nothing is "skipped", never a pass
SKIPPED="Greptile skipped this review: it would exceed your organization's monthly flex usage limit."
hosted_case hp-skip
python3 - "$TMP/fx/hp-skip/reviews.json" "$PA" "$PB" "$PC" <<'PY2'
import json, sys
path, pa, pb, pc = sys.argv[1:]
rows = [
 {"id":81,"user":{"login":"greptile-apps[bot]","type":"Bot"},"state":"COMMENTED","body":"3 findings","commit_id":pa,"submitted_at":"2026-10-13T09:00:00Z","html_url":"r81"},
 {"id":82,"user":{"login":"greptile-apps[bot]","type":"Bot"},"state":"COMMENTED","body":"Greptile skipped this review: it would exceed your organization's monthly flex usage limit.","commit_id":pb,"submitted_at":"2026-10-13T10:00:00Z","html_url":"r82"},
 {"id":83,"user":{"login":"greptile-apps[bot]","type":"Bot"},"state":"COMMENTED","body":"3 files were skipped (generated code)\n1 finding","commit_id":pc,"submitted_at":"2026-10-13T11:00:00Z","html_url":"r83"},
]
with open(path, "w") as f:
 for row in rows: f.write(json.dumps(row)+"\n")
PY2
run hp-skip 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "#129 a skipped run between two real passes is skipped, and the passes stay 1 and 2" 0 "$(printf '2026-10-13T09:00:00Z pass 1 head=%s\n2026-10-13T10:00:00Z skipped head=%s %s\n2026-10-13T11:00:00Z pass 2 head=%s' "$PA" "$PB" "$SKIPPED" "$PC")"
hosted_case hp-skip-comment
python3 - "$TMP/fx/hp-skip-comment/comments.json" "$PA" <<'PY2'
import json, sys
path, pa = sys.argv[1:]
rows = [
 {"id":84,"user":{"login":"greptile-apps[bot]"},"created_at":"2026-10-13T11:00:00Z","updated_at":"2026-10-13T12:00:00Z","html_url":"c84","body":"**Review skipped**\n\nUsage limit reached for this billing period."},
 {"id":85,"user":{"login":"greptile-apps[bot]"},"created_at":"2026-10-13T00:00:00Z","updated_at":"2026-10-13T08:00:00Z","html_url":"c85","body":"Confidence Score: 4/5\nReview skipped for vendored files\nLast reviewed commit: "+pa},
]
with open(path, "w") as f:
 for row in rows: f.write(json.dumps(row)+"\n")
PY2
run hp-skip-comment 30 --hosted 'greptile-apps[bot]' --hosted-passes
check_lines "#129 a summary comment that reviewed nothing is skipped on the PR's head; one with a score is a pass" 0 "$(printf '2026-10-13T08:00:00Z pass 1 head=%s\n2026-10-13T12:00:00Z skipped head=%s Review skipped' "$PA" "$HEADX")"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
