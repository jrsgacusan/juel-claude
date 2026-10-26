#!/bin/sh
# Runs skills/yuki/yuki.sh against a scratch repo with real git worktrees, a stub gh and a stub orca
# whose `worktree rm` really removes the git worktree.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/yuki/yuki.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL yuki.sh missing"; exit 1; }

APP="$TMP/app"; mkdir -p "$APP"
(cd "$APP" && git init -q -b main . && git commit -q --allow-empty -m init)
APP=$(cd "$APP" && pwd -P)

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/gh-calls"
case "$*" in
  "pr view "*" --json state")
    n=${3##*/}
    printf '{"state":"%s"}\n' "$(cat "$STUB_DIR/pr-$n" 2>/dev/null || echo OPEN)" ;;
  "pr list --head "*) cat "$STUB_DIR/head-$4" 2>/dev/null || echo '[]' ;;
  "pr list --state merged"*) cat "$STUB_DIR/merged" 2>/dev/null ;;
  "api repos/{owner}/{repo}/pulls/"*"/reviews"*)
    n=${2#repos/\{owner\}/\{repo\}/pulls/}; n=${n%%/*}
    cat "$STUB_DIR/reviews-$n" 2>/dev/null || true ;;
  "api repos/{owner}/{repo}/issues/"*"/comments"*)
    n=${2#repos/\{owner\}/\{repo\}/issues/}; n=${n%%/*}
    cat "$STUB_DIR/comments-$n" 2>/dev/null || true ;;
  "api repos/{owner}/{repo} --jq .full_name")
    [ -z "${STUB_NOBODY:-}" ] && [ "${GH_TOKEN:-}" = "tok-jrsgacusan" ] && echo jrsgacusan/app || { echo "HTTP 404: Not Found" >&2; exit 1; } ;;
  "auth status") printf '  - Logged in to github.com account mstr-juel (keyring)\n  - Logged in to github.com account jrsgacusan (/x/hosts.yml)\n' ;;
  "auth token --user "*) echo "tok-$4" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF
cat > "$TMP/bin/orca" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/orca-calls"
case "$*" in
  "worktree rm --worktree path:"*)
    p=${4#path:}
    common=$(git -C "$p" rev-parse --path-format=absolute --git-common-dir)
    git --git-dir="$common" worktree remove "$p" || exit 1
    echo '{"ok":true,"result":{"removed":true}}' ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$TMP/bin/gh" "$TMP/bin/orca"
NOW=$(date -u +%s)
Y() { (cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" ORCA_CLI_COMMAND="$TMP/bin/orca" YUKI_NOW="${YUKI_NOW:-$NOW}" sh "$SCRIPT" "$@"); }
stamp() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
wt() { git -C "$APP" worktree add -q -b "feat/$1" "$TMP/wt/$1" main 2>/dev/null; echo "$TMP/wt/$1"; }

# --- path, init, config ---
H=$(Y init)
[ "$H" = "$APP/.git/yuki" ] && [ -f "$H/yuki.json" ] && [ -d "$H/progress" ] && pass "init makes the folder inside .git" || fail "init ($H)"
[ "$(Y path)" = "$H" ] && pass "path prints the same folder" || fail "path"
[ "$(Y config maxParallel)" = "5" ] && pass "five slots by default" || fail "default maxParallel"
[ "$(Y config repo)" = "$APP" ] && pass "init records the main checkout" || fail "repo"
Y config maxParallel 3
Y init >/dev/null
[ "$(Y config maxParallel)" = "3" ] && pass "init again keeps the settings" || fail "re-init overwrote"
Y config maxParallel 0 2>/dev/null && fail "maxParallel 0 accepted" || pass "maxParallel 0 refused"
Y config mergeMethod squash 2>/dev/null && fail "bare string accepted" || pass "config values are JSON"
Y config mergeMethod '"squash"'
[ "$(Y config mergeMethod)" = "squash" ] && pass "a string key reads back bare" || fail "mergeMethod"
(cd "$TMP" && sh "$SCRIPT" path >/dev/null 2>&1); [ $? -eq 1 ] && pass "outside a repo: exit 1" || fail "outside repo exit"

# --- rows and slots ---
[ "$(Y free)" = "3" ] && pass "all slots free" || fail "free empty"
Y add SPH-1 "path=$(wt SPH-1)" branch=feat/SPH-1 terminal=term_1
Y add SPH-2 "path=$(wt SPH-2)" branch=feat/SPH-2
[ "$(Y free)" = "1" ] && pass "two running rows take two slots" || fail "free after add ($(Y free))"
Y add SPH-1 2>/dev/null && fail "a known item was added twice" || pass "a known item is refused"
Y add "bad name" 2>/dev/null && fail "a bad item name was accepted" || pass "item names are checked"
[ "$(Y known | tr '\n' ' ')" = "SPH-1 SPH-2 " ] && pass "known lists every item" || fail "known"
Y set SPH-2 state=nope 2>/dev/null && fail "unknown state accepted" || pass "states are checked"

# --- sweep ---
P="$H/progress"
printf '%s phase4 executing\n%s parked needs a secret: STRIPE_KEY\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/SPH-1.log"
printf '%s pr https://github.com/o/r/pull/2\n' "$(stamp "$NOW")" > "$P/SPH-2.log"; echo MERGED > "$TMP/pr-2"
C=$(wt SPH-3); Y add SPH-3 "path=$C" branch=feat/SPH-3 pr=https://github.com/o/r/pull/3; echo MERGED > "$TMP/pr-3"; echo x > "$C/scratch.txt"
Y config maxParallel 8
Y add SPH-4 "path=$(wt SPH-4)" branch=feat/SPH-4; printf '%s phase3 writing the plan\n' "$(stamp $((NOW - 600)))" > "$P/SPH-4.log"
Y add SPH-5 "path=$(wt SPH-5)" branch=feat/SPH-5; printf '%s phase4 executing\n' "$(stamp $((NOW - 3 * 3600)))" > "$P/SPH-5.log"
mkdir -p "$TMP/head-feat"; printf '[{"url":"https://github.com/o/r/pull/6"}]\n' > "$TMP/head-feat/SPH-6"
Y add SPH-6 "path=$(wt SPH-6)" branch=feat/SPH-6; echo CLOSED > "$TMP/pr-6"
Y add SPH-7 "path=$TMP/wt/never-made" branch=feat/SPH-7
out=$(Y sweep)
echo "$out" | grep -qx 'parked SPH-1 needs a secret: STRIPE_KEY' && pass "a worker's park is applied" || fail "park ($out)"
echo "$out" | grep -qx "done SPH-2 https://github.com/o/r/pull/2 removed $TMP/wt/SPH-2" && [ ! -d "$TMP/wt/SPH-2" ] && pass "a merged PR's worktree is removed" || fail "merged removal ($out)"
echo "$out" | grep -qx "merged SPH-3 https://github.com/o/r/pull/3 kept $C: uncommitted changes" && [ -d "$C" ] && pass "a dirty worktree is kept" || fail "dirty kept ($out)"
echo "$out" | grep -qx 'running SPH-4 phase3 10m' && pass "a fresh worker is running" || fail "running ($out)"
echo "$out" | grep -qx 'quiet SPH-5 3h00m phase4' && pass "no progress for 2 h and no PR: quiet" || fail "quiet ($out)"
echo "$out" | grep -qx 'parked SPH-6 PR closed without a merge' && pass "a PR closed unmerged parks the item" || fail "closed ($out)"
echo "$out" | grep -qx 'parked SPH-7 worktree gone' && pass "a missing worktree parks the item" || fail "gone ($out)"
grep -q -- '--force' "$TMP/orca-calls" && fail "orca rm used --force" || pass "never --force"
[ "$(Y list --state running | cut -f1 | tr '\n' ' ')" = "SPH-4 SPH-5 " ] && pass "only live rows stay running" || fail "states after sweep"
[ "$(Y free)" = "6" ] && pass "parked and merged rows free their slots" || fail "free after sweep ($(Y free))"
[ "$(Y list | awk -F'\t' '$1=="SPH-2"{print $5}')" = "https://github.com/o/r/pull/2" ] && pass "the PR url is recorded" || fail "pr recorded"
out2=$(Y sweep)
[ "$(echo "$out2" | wc -l | tr -d ' ')" = "2" ] && pass "a second sweep only reports live rows" || fail "second sweep ($out2)"
echo "$out2" | grep -qx 'running SPH-5 phase4 3h00m quiet' && pass "quiet is reported once" || fail "quiet once ($out2)"
printf '%s phase5 reviewing\n' "$(stamp "$NOW")" >> "$P/SPH-5.log"
Y sweep | grep -qx 'running SPH-5 phase5 0m' && [ "$(Y list | awk -F'\t' '$1=="SPH-5"{print $6}')" = "-" ] && pass "a new progress line clears quiet" || fail "quiet cleared"

# --- host ---
[ "$(YUKI_FREE_GB=1 Y host)" = "low 1.0 GB" ] && pass "below minFreeGB is low" || fail "host low"
[ "$(YUKI_FREE_GB=7.25 Y host)" = "ok 7.2 GB" ] && pass "above minFreeGB is ok" || fail "host ok"
case "$(Y host)" in ok\ *|low\ *) pass "the real memory reading parses" ;; *) fail "host real ($(Y host))" ;; esac

# --- owner and heartbeat ---
[ "$(Y owner)" = "none" ] && pass "no owner before a beat" || fail "owner none"
Y beat tok123
[ "$(Y owner)" = "tok123 0" ] && pass "a beat names the owner" || fail "owner after beat ($(Y owner))"
[ "$(YUKI_NOW=$((NOW + 1500)) Y owner)" = "tok123 25" ] && pass "owner reports minutes since the beat" || fail "owner age"

# --- deps ---
# rows now: SPH-1 parked, SPH-2 done, SPH-3 merged (kept), SPH-4 SPH-5 running, SPH-6 SPH-7 parked
Y deps set SPH-10 --why "no links, no code from another item"
Y deps set SPH-11 SPH-2 SPH-3 --why "linear: blocked by SPH-2, SPH-3"
Y deps set SPH-12 SPH-4 SPH-11 --why "code: uses the endpoint SPH-4 adds"
Y deps set SPH-13 SPH-99 --why "linear: blocked by SPH-99 (not in the source)"
Y deps set SPH-14 SPH-15 --why "code"; Y deps set SPH-15 SPH-14 --why "linear"
Y deps set SPH-16 SPH-6 --why "linear"
Y deps set SPH-17 SPH-17 --why x 2>/dev/null && fail "an item may block itself" || pass "an item never blocks itself"
Y deps set SPH-18 SPH-2 2>/dev/null && fail "a record without --why" || pass "a record needs its reason"
[ "$(Y deps unchecked SPH-10 SPH-19 SPH-11 SPH-20 | tr '\n' ' ')" = "SPH-19 SPH-20 " ] && pass "unchecked lists items with no record" || fail "unchecked"
[ "$(Y deps external SPH-11 SPH-12 SPH-13 | tr '\n' ' ')" = "SPH-11 SPH-99 " ] && pass "external lists blockers yuki has no row for" || fail "external ($(Y deps external SPH-11 SPH-12 SPH-13 | tr '\n' ' '))"
g=$(Y deps gate SPH-10 SPH-11 SPH-12 SPH-13 SPH-14 SPH-16 SPH-19)
echo "$g" | grep -qx 'ready SPH-10' && pass "no blockers: ready" || fail "ready none ($g)"
echo "$g" | grep -qx 'ready SPH-11' && pass "done and merged rows clear their dependents" || fail "cleared ($g)"
echo "$g" | grep -qx 'wait SPH-12 on SPH-4,SPH-11' && pass "a running row and an unspawned item block" || fail "open ($g)"
echo "$g" | grep -qx 'wait SPH-13 on SPH-99' && pass "an outside blocker blocks until the tracker says done" || fail "external open ($g)"
echo "$g" | grep -qx 'cycle SPH-14 SPH-15 SPH-14' && pass "a cycle is reported, not waited on silently" || fail "cycle ($g)"
echo "$g" | grep -qx 'wait SPH-16 on SPH-6' && pass "a parked blocker still blocks" || fail "parked blocks ($g)"
echo "$g" | grep -qx 'wait SPH-19 on unchecked' && pass "an unchecked item never starts" || fail "unchecked gate ($g)"
[ "$(Y deps gate SPH-13 --done SPH-99)" = "ready SPH-13" ] && pass "--done clears an outside blocker" || fail "--done"
[ "$(Y deps gate SPH-14 --done SPH-15)" = "ready SPH-14" ] && pass "a cleared link breaks the cycle" || fail "cycle broken"
[ "$(Y deps list | awk -F'\t' '$1=="SPH-10"{print $2}')" = "-" ] && pass "a record with no blockers lists as -" || fail "list"

# --- bot ---
printf '101\n102\n' > "$TMP/merged"
printf 'github-actions[bot]\nalice\n' > "$TMP/reviews-101"
printf 'copilot-pull-request-reviewer[bot]\n' > "$TMP/reviews-102"
[ "$(Y bot)" = "copilot-pull-request-reviewer[bot]" ] && pass "a reviewing bot is found" || fail "bot found ($(Y bot))"
: > "$TMP/reviews-102"; printf 'greptile-apps[bot]\n' > "$TMP/comments-102"
[ "$(Y bot)" = "greptile-apps[bot]" ] && pass "greptile found by its summary comment" || fail "greptile ($(Y bot))"
: > "$TMP/comments-102"
[ "$(Y bot)" = "none" ] && pass "CI bots are not reviewers" || fail "bot none ($(Y bot))"
mkdir -p "$APP/.claude"; printf '{"config":{"reviewBots":["coderabbitai[bot]"]}}\n' > "$APP/.claude/workflow.json"
[ "$(Y bot)" = "coderabbitai[bot]" ] && pass "config.reviewBots wins" || fail "reviewBots ($(Y bot))"

# --- access: the gh binary sees only its active account; yuki finds the one that can see the repo ---
A() { (cd "$APP" && env -u GH_TOKEN CLAUDE_ENV_FILE="$TMP/envfile" PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" sh "$SCRIPT" "$@"); }
Y config tokenCmd null
[ "$(STUB_NOBODY=1 A access)" = "none HTTP 404: Not Found; tried mstr-juel, jrsgacusan" ] && pass "no account that can see the repo: none" || fail "access none ($(STUB_NOBODY=1 A access))"
(STUB_NOBODY=1 A access >/dev/null); [ $? -eq 1 ] && pass "none exits 1" || fail "none exit"
[ "$(A access)" = "token jrsgacusan" ] && pass "the account that can see it is found" || fail "access token ($(A access))"
[ "$(Y config tokenCmd)" = "gh auth token --user jrsgacusan" ] && pass "tokenCmd is a command, never the token" || fail "tokenCmd ($(Y config tokenCmd))"
[ "$(cat "$TMP/envfile")" = 'export GH_TOKEN="$(gh auth token --user jrsgacusan)"' ] && pass "this session's env file gets the export line" || fail "env file ($(cat "$TMP/envfile"))"
[ "$(A access)" = "ok" ] && [ "$(grep -c GH_TOKEN "$TMP/envfile")" = 1 ] && pass "with tokenCmd set, gh sees the repo, and nothing is written twice" || fail "access ok"
[ "$(A gh api 'repos/{owner}/{repo}' --jq .full_name)" = "jrsgacusan/app" ] && pass "Y gh carries the token" || fail "Y gh passthrough"
[ "$(A git -C "$APP" rev-parse --abbrev-ref HEAD)" = "main" ] && pass "Y git runs git" || fail "Y git passthrough"
printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$TMP/wt/SPH-4" | env -u GH_TOKEN CLAUDE_ENV_FILE="$TMP/hookenv" sh "$ROOT/hooks/star-session.sh" >/dev/null
[ "$(cat "$TMP/hookenv" 2>/dev/null)" = 'export GH_TOKEN="$(gh auth token --user jrsgacusan)"' ] && pass "the session hook gives a worker's worktree yuki's token" || fail "hook ($(cat "$TMP/hookenv" 2>/dev/null))"

echo "---"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
