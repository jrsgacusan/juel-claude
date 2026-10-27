#!/bin/sh
# Runs skills/yuna/yuna.sh (yuki.sh --kind yuna) against a scratch repo with real git worktrees, a stub gh
# and a stub orca whose `worktree rm` really removes the git worktree, after noting the branch it had.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/yuna/yuna.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -x "$SCRIPT" ] || { echo "FAIL yuna.sh missing or not executable"; exit 1; }

APP="$TMP/app"; mkdir -p "$APP"
(cd "$APP" && git init -q -b main . && git commit -q --allow-empty -m init)
APP=$(cd "$APP" && pwd -P)

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'GHEOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/gh-calls"
case "$*" in
  "api user --jq .login")
    [ -n "${STUB_NOUSER:-}" ] && { echo "HTTP 401: Bad credentials" >&2; exit 1; }
    echo reviewer-bot ;;
  "pr view "*" --json state")
    n=${3##*/}
    printf '{"state":"%s"}\n' "$(cat "$STUB_DIR/pr-$n" 2>/dev/null || echo OPEN)" ;;
  "pr view "*" --json state,isDraft,author,headRefOid,headRefName")
    cat "$STUB_DIR/prview-$3" 2>/dev/null || { echo "Could not resolve to a PullRequest" >&2; exit 1; } ;;
  "api repos/{owner}/{repo}/pulls/"*"/reviews --paginate --jq .[]")
    n=${2#repos/\{owner\}/\{repo\}/pulls/}; n=${n%%/*}
    cat "$STUB_DIR/reviews-$n" 2>/dev/null || true ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
GHEOF
cat > "$TMP/bin/orca" <<'ORCAEOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/orca-calls"
case "$*" in
  "worktree rm --worktree path:"*)
    p=${4#path:}
    echo "$(git -C "$p" rev-parse --abbrev-ref HEAD) $p" >> "$STUB_DIR/rm-branches"
    common=$(git -C "$p" rev-parse --path-format=absolute --git-common-dir)
    git --git-dir="$common" worktree remove "$p" || exit 1
    echo '{"ok":true,"result":{"removed":true}}' ;;
  "terminal read "*)
    f="$STUB_DIR/screen-$4.json"; [ -f "$f" ] || { echo '{"ok":false}'; exit 1; }
    cat "$f" ;;
  "terminal send "*) echo '{"ok":true}' ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
ORCAEOF
chmod +x "$TMP/bin/gh" "$TMP/bin/orca"
NOW=$(date -u +%s)
Y() { (cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" ORCA_CLI_COMMAND="$TMP/bin/orca" YUKI_NOW="${YUKI_NOW:-$NOW}" sh "$SCRIPT" "$@"); }
# at <epoch> <cmd>...: run a command with the script's clock set, in a subshell so nothing leaks
at() { t=$1; shift; (YUKI_NOW=$t; export YUKI_NOW; "$@"); }
no_user() { (STUB_NOUSER=1; export STUB_NOUSER; Y "$@"); }
stamp() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
# wt <name>: a worktree on feat/<name> with an Orca-style throwaway branch thr/<name> to leave for
wt() { git -C "$APP" branch -q "thr/$1" main 2>/dev/null; git -C "$APP" worktree add -q -b "feat/$1" "$TMP/wt/$1" main 2>/dev/null; echo "$TMP/wt/$1"; }
# review <n> <login> <state> <epoch> <commit>: one submitted review line for PR <n>
review() { printf '{"user":{"login":"%s"},"state":"%s","submitted_at":"%s","commit_id":"%s"}\n' "$2" "$3" "$(stamp "$4")" "$5" >> "$TMP/reviews-$1"; }
# prview <n> <login> <draft> <state> <oid> <branch>
prview() { printf '{"state":"%s","isDraft":%s,"author":{"login":"%s"},"headRefOid":"%s","headRefName":"%s"}\n' "$4" "$3" "$2" "$5" "$6" > "$TMP/prview-$1"; }

# --- init, config, error prefix ---
H=$(Y init)
[ "$H" = "$APP/.git/yuna" ] && [ -f "$H/yuna.json" ] && [ -d "$H/progress" ] && pass "init makes <git common dir>/yuna with yuna.json" || fail "init ($H)"
[ "$(Y path)" = "$H" ] && pass "path prints the same folder" || fail "path"
python3 - "$H/yuna.json" "$APP" <<'PY' && pass "yuna.json has yuna's keys and defaults" || fail "yuna.json keys"
import json, sys
d = json.load(open(sys.argv[1]))
want = {"maxParallel": 5, "intervalMinutes": 10, "sources": [], "minFreeGB": 3, "quietHours": 2, "repo": sys.argv[2],
        "owner": None, "cron": None, "tokenCmd": None, "reviewer": None}
for k, v in want.items():
    assert d[k] == v, (k, d.get(k))
assert "bot" not in d and "mergeMethod" not in d, d
PY
[ ! -e "$APP/.git/yuki" ] && pass "nothing is written into yuki's folder" || fail "yuki folder created"
err=$(Y set nope state=done 2>&1 >/dev/null); case "$err" in "yuna.sh: no row nope") pass "errors start yuna.sh:" ;; *) fail "error prefix ($err)" ;; esac
Y bot >/dev/null 2>"$TMP/err"; rc=$?; [ "$rc" -eq 64 ] && [ "$(cat "$TMP/err")" = "yuna.sh: bot is a yuki command" ] && pass "bot is refused with 64" || fail "bot ($rc $(cat "$TMP/err"))"
Y deps list >/dev/null 2>"$TMP/err"; rc=$?; [ "$rc" -eq 64 ] && [ "$(cat "$TMP/err")" = "yuna.sh: deps is a yuki command" ] && pass "deps is refused with 64" || fail "deps ($rc $(cat "$TMP/err"))"
(cd "$APP" && sh "$ROOT/skills/yuki/yuki.sh" whoami >/dev/null 2>"$TMP/err"); [ $? -eq 64 ] && pass "whoami is yuna only" || fail "yuki whoami"
Y config maxParallel 20

# --- whoami ---
[ "$(no_user whoami 2>&1 >/dev/null)" = "yuna.sh: gh: HTTP 401: Bad credentials" ] && pass "whoami failure: yuna.sh: gh: <error>" || fail "whoami error"
no_user whoami >/dev/null 2>&1; [ $? -eq 1 ] && pass "whoami failure exits 1" || fail "whoami exit"
[ "$(Y whoami)" = "reviewer-bot" ] && [ "$(Y config reviewer)" = "reviewer-bot" ] && pass "whoami prints the login and stores it as reviewer" || fail "whoami"

# --- fresh ---
HEAD1=1111111aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
prview 11 alice false OPEN "$HEAD1" feat/p11
prview 12 alice false OPEN "$HEAD1" feat/p12
prview 13 reviewer-bot false OPEN "$HEAD1" feat/p13
prview 14 alice true OPEN "$HEAD1" feat/p14
prview 15 alice false CLOSED "$HEAD1" feat/p15
prview 16 alice false OPEN "$HEAD1" feat/p16; review 16 reviewer-bot COMMENTED "$((NOW - 100))" "$HEAD1"
prview 17 alice false OPEN "$HEAD1" feat/p17; git -C "$APP" worktree add -q -b feat/p17 "$TMP/wt/p17" main
prview 19 alice false OPEN "$HEAD1" feat/p19; Y add review-19 ref=19 >/dev/null; Y set review-19 state=done
prview 20 alice false OPEN "$HEAD1" feat/p20; Y add review-20 ref=20 >/dev/null; Y set review-20 state=parked
prview 21 alice false OPEN "$HEAD1" feat/p21; Y add review-21 ref=21 >/dev/null; Y set review-21 state=ended
prview 22 alice false OPEN "$HEAD1" feat/p22; Y add review-22 ref=22 >/dev/null; Y set review-22 state=dropped
prview 23 alice false OPEN "$HEAD1" feat/p23; review 23 reviewer-bot APPROVED "$((NOW - 100))" 2222222bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
Y add review-12 ref=12 >/dev/null
out=$(Y fresh 11 12 13 14 15 16 17 18 19 20 21 22 23)
want="fresh 11
skip 12 row running
skip 13 mine
skip 14 draft
skip 15 not open
skip 16 reviewed 1111111
skip 17 checked out at $TMP/wt/p17
skip 18 gh: Could not resolve to a PullRequest
fresh 19
skip 20 row parked
skip 21 row ended
skip 22 row dropped
fresh 23"
[ "$out" = "$want" ] && pass "fresh: one line per PR in order, each skip with its reason" || { fail "fresh ($out)"; }
(cd "$TMP" && env PATH="$TMP/bin:$PATH" sh "$SCRIPT" fresh 11 >/dev/null 2>&1); [ $? -ne 0 ] && pass "fresh outside a repository fails" || fail "fresh outside"

# --- add reopens a done row ---
[ "$(Y list | awk -F'\t' '$1=="review-19"{print $2}')" = "done" ] && pass "review-19 is done" || fail "setup done"
Y add review-19 ref=19 "path=$TMP/wt/new19" pr=https://github.com/o/r/pull/19 >/dev/null
python3 - "$H/items.json" <<'PY' && pass "add reopens a done row: running, new values, rounds 2" || fail "reopen"
import json, sys
r = {x["item"]: x for x in json.load(open(sys.argv[1]))["items"]}["review-19"]
assert r["state"] == "running" and r["rounds"] == 2 and r["path"].endswith("/new19") and r["pr"].endswith("/19"), r
assert len([x for x in json.load(open(sys.argv[1]))["items"] if x["item"] == "review-19"]) == 1
PY
Y add review-19 2>/dev/null && fail "a running row was added again" || pass "a running row is refused"
Y add review-20 2>/dev/null && fail "a parked row was added again" || pass "a parked row is refused"
Y set review-19 state=done; Y add review-19 >/dev/null
[ "$(python3 -c 'import json,sys; print({x["item"]: x for x in json.load(open(sys.argv[1]))["items"]}["review-19"]["rounds"])' "$H/items.json")" = 3 ] && pass "each reopening raises rounds by one" || fail "rounds 3"
Y set review-19 state=ended; Y list --state ended | cut -f1 | grep -qx review-19 && pass "ended is a state" || fail "ended state"
Y set review-19 state=merged 2>/dev/null && fail "merged is yuki's state" || pass "merged is refused under yuna"

# --- sweep: rules 1 to 7 ---
P="$H/progress"
for r in review-12 review-19 review-20 review-21 review-22; do Y set "$r" state=dropped; done
add() { # add <n> <progress step text|-> : a running row with a worktree, a throwaway branch and a PR
  n=$1; Y add "review-$n" ref="$n" "path=$(wt "p$n" >/dev/null; echo "$TMP/wt/p$n")" branch="feat/p$n" "throwaway=thr/p$n" "pr=https://github.com/o/r/pull/$n" terminal="t$n" >/dev/null
}
# rule 1: parked by the worker
add 31; printf '%s review 1 \n%s parked needs a secret\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/review-31.log"
# rule 2: merged, closed, and merged with a dirty worktree
add 32; echo MERGED > "$TMP/pr-32"
add 33; echo CLOSED > "$TMP/pr-33"
add 34; echo MERGED > "$TMP/pr-34"; echo x > "$TMP/wt/p34/scratch.txt"
# rule 2 with a throwaway branch that cannot be left
add 35; echo MERGED > "$TMP/pr-35"; Y set review-35 throwaway=thr/nope
# rule 3: approved
add 41; printf '%s approved https://x/r1 abc\n' "$(stamp "$((NOW + 1700))")" > "$P/review-41.log"; review 41 reviewer-bot APPROVED "$((NOW + 1700))" abc
add 42; printf '%s posted APPROVE https://x/r1\n' "$(stamp "$((NOW + 1500))")" > "$P/review-42.log"; review 42 reviewer-bot APPROVED "$((NOW + 800))" abc
add 43; printf '%s posted APPROVE https://x/r1\n' "$(stamp "$((NOW + 1500))")" > "$P/review-43.log"; review 43 reviewer-bot APPROVED "$((NOW + 1500))" abc
add 44; printf '%s posted ok\n' "$(stamp "$((NOW + 1700))")" > "$P/review-44.log"; review 44 reviewer-bot APPROVED "$((NOW + 100))" abc; review 44 reviewer-bot CHANGES_REQUESTED "$((NOW + 900))" def
add 45; printf '%s review 2\n' "$(stamp "$((NOW + 1700))")" > "$P/review-45.log"; review 45 reviewer-bot APPROVED "$((NOW - 7200))" abc
add 46; printf '%s posted ok\n' "$(stamp "$((NOW + 1700))")" > "$P/review-46.log"; review 46 someone-else APPROVED "$((NOW + 100))" abc
add 47; printf '%s posted ok\n' "$(stamp "$((NOW + 1700))")" > "$P/review-47.log"; review 47 reviewer-bot APPROVED "$((NOW + 100))" abc; review 47 reviewer-bot PENDING "$((NOW + 1000))" def
# rule 4: released
add 51; printf '%s released author silent for 72 h\n' "$(stamp "$((NOW + 1700))")" > "$P/review-51.log"
# rule 5: the worktree is gone
add 61; rm -rf "$TMP/wt/p61"; git -C "$APP" worktree prune
# rule 6: quiet; a worker waiting on its author is not
add 71; printf '%s review 1 \n' "$(stamp "$((NOW - 3 * 3600))")" > "$P/review-71.log"
add 72; printf '%s wait author\n' "$(stamp "$((NOW - 3 * 3600))")" > "$P/review-72.log"
# rule 7: running
add 81; printf '%s review 1 \n' "$(stamp "$((NOW + 1200))")" > "$P/review-81.log"
out=$(at $((NOW + 1800)) Y sweep)
echo "$out" | grep -qx 'parked review-31 needs a secret' && pass "rule 1: the worker's park" || fail "rule 1 ($out)"
echo "$out" | grep -qx "done review-32 https://github.com/o/r/pull/32 removed $TMP/wt/p32 merged" && [ ! -d "$TMP/wt/p32" ] && pass "rule 2: a merged PR's worktree is removed" || fail "rule 2 merged ($out)"
echo "$out" | grep -qx "done review-33 https://github.com/o/r/pull/33 removed $TMP/wt/p33 closed" && pass "rule 2: a closed PR is done too" || fail "rule 2 closed ($out)"
echo "$out" | grep -qx "ended review-34 https://github.com/o/r/pull/34 kept $TMP/wt/p34: uncommitted changes" && [ -d "$TMP/wt/p34" ] && pass "rule 2: a dirty worktree is kept, the row ended" || fail "rule 2 dirty ($out)"
echo "$out" | grep -q "^ended review-35 .* kept $TMP/wt/p35: cannot leave the PR branch: " && [ -d "$TMP/wt/p35" ] && pass "a throwaway that cannot be checked out keeps the worktree" || fail "rule 2 throwaway ($out)"
echo "$out" | grep -qx "done review-41 https://github.com/o/r/pull/41 removed $TMP/wt/p41 approved" && pass "rule 3: approved step plus an approving review" || fail "rule 3 step ($out)"
echo "$out" | grep -qx "done review-42 https://github.com/o/r/pull/42 removed $TMP/wt/p42 approved" && pass "rule 3: an approval 15 minutes old is enough" || fail "rule 3 age ($out)"
echo "$out" | grep -qx 'running review-43 posted 5m' && pass "rule 3: a fresh approval without the approved step waits" || fail "rule 3 fresh ($out)"
echo "$out" | grep -qx 'running review-44 posted 1m' && pass "rule 3: a later change request cancels the approval" || fail "rule 3 later review ($out)"
echo "$out" | grep -q '^running review-45 review 1m' && pass "rule 3: an approval from before this round does not count" || fail "rule 3 old round ($out)"
echo "$out" | grep -qx 'running review-46 posted 1m' && pass "rule 3: someone else's approval does not count" || fail "rule 3 other ($out)"
echo "$out" | grep -qx "done review-47 https://github.com/o/r/pull/47 removed $TMP/wt/p47 approved" && pass "rule 3: a pending review does not hide the approval" || fail "rule 3 pending ($out)"
echo "$out" | grep -qx "done review-51 https://github.com/o/r/pull/51 removed $TMP/wt/p51 released" && pass "rule 4: a released PR is removed" || fail "rule 4 ($out)"
echo "$out" | grep -qx 'parked review-61 worktree gone' && pass "rule 5: a missing worktree parks the row" || fail "rule 5 ($out)"
echo "$out" | grep -qx 'quiet review-71 3h30m review' && pass "rule 6: no progress for quietHours is quiet, once" || fail "rule 6 ($out)"
echo "$out" | grep -qx 'running review-72 wait 3h30m' && pass "rule 6: a worker waiting on its author is not quiet" || fail "rule 6 wait ($out)"
echo "$out" | grep -qx 'running review-81 review 10m' && pass "rule 7: otherwise running" || fail "rule 7 ($out)"
out2=$(at $((NOW + 1800)) Y sweep)
echo "$out2" | grep -qx 'running review-71 review 3h30m quiet' && pass "a later sweep prints the running line ending quiet" || fail "quiet again ($out2)"
[ "$(sort "$TMP/rm-branches" | awk '{print $1}' | tr '\n' ' ')" = "thr/p32 thr/p33 thr/p41 thr/p42 thr/p47 thr/p51 " ] && pass "removal checks out the throwaway branch first" || fail "throwaway first ($(cat "$TMP/rm-branches"))"
grep -q -- '--force' "$TMP/orca-calls" && fail "orca rm used --force" || pass "never --force"
[ "$(Y list --state ended | cut -f1 | tr '\n' ' ')" = "review-34 review-35 " ] && pass "ended rows free their slot but stay listed" || fail "ended rows ($(Y list --state ended | cut -f1 | tr '\n' ' '))"
[ "$(Y list --state done | cut -f1 | sort | tr '\n' ' ')" = "review-32 review-33 review-41 review-42 review-47 review-51 " ] && pass "done rows" || fail "done rows"
# a reopened round does not inherit the previous round's end
at $((NOW + 1800)) Y add review-41 ref=41 "path=$(wt p41b)" "throwaway=thr/p41b" "pr=https://github.com/o/r/pull/41" >/dev/null
# approved, then pushed again: the old approval and the old released/approved step do not end the new round
at $((NOW + 3600)) Y sweep | grep -q '^running review-41 reopened' && pass "a reopened row sweeps as running, not as last round's approval" || fail "reopened sweep ($(at $((NOW + 3600)) Y sweep | grep review-41))"
[ "$(Y free)" = "$((20 - $(Y list --state running | wc -l | tr -d ' ')))" ] && pass "free counts running rows only" || fail "free"

# --- nudge works for yuna rows too ---
python3 -c 'import json; print(json.dumps({"ok":True,"result":{"terminal":{"source":"screen","tail":["Bash command","  ls src","  List the sources","Do you want to proceed?","❯ 1. Yes","  2. No"]}}}))' > "$TMP/screen-t81.json"
[ "$(Y nudge review-81)" = "nudged review-81 permission: ls src" ] && pass "yuna nudges a read-only command" || fail "yuna nudge ($(Y nudge review-81))"
tail -n1 "$P/review-81.log" | grep -q ' nudged permission: ls src$' && at $((NOW + 1800)) Y sweep | grep -qx 'running review-81 review 10m' && pass "and the sweep ignores that line" || fail "nudge vs sweep"

echo "---"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
