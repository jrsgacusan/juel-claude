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
  "terminal read "*)
    f="$STUB_DIR/screen-$4.json"; [ -f "$f" ] || { echo '{"ok":false}'; exit 1; }
    cat "$f"; [ -f "$STUB_DIR/screen-$4.next" ] && mv "$STUB_DIR/screen-$4.next" "$f"; exit 0 ;;
  "terminal send "*) [ -f "$STUB_DIR/sendfail-$4" ] && { echo 'refused' >&2; exit 1; }; echo '{"ok":true}' ;;
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

# --- nudge (#214) ---
# screen <handle> <row>...: the rendered screen of that terminal
screen() { h=$1; shift; python3 -c 'import json,sys; print(json.dumps({"ok":True,"result":{"terminal":{"handle":sys.argv[1],"source":"screen","tail":sys.argv[2:]}}}))' "$h" "$@" > "$TMP/screen-$h.json"; }
# permrows <handle> <description> <command row>...: Claude Code's permission prompt in a box W (100) wide, the
# command on one screen row per argument
permrows() {
  python3 - "$TMP/screen-$1.json" "$1" "$2" "${W:-100}" "${@:3}" <<'PYEOF'
import json, sys
out, handle, desc, w = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
cmd = sys.argv[5:]
def row(t): return "│ " + t.ljust(w - 2) + " │"
tail = ["⏺ Bash(" + " ".join(cmd) + ")", "╭" + "─" * w + "╮", row("Bash command"), row(""), *[row("  " + c) for c in cmd]]
if desc: tail.append(row("  " + desc))
tail += [row(""), row("Do you want to proceed?"), row("❯ 1. Yes"), row("  2. Yes, and don't ask again for this command"),
         row("  3. No, and tell Claude what to do differently (esc)"), "╰" + "─" * w + "╯"]
json.dump({"ok": True, "result": {"terminal": {"handle": handle, "source": "screen", "tail": tail}}}, open(out, "w"))
PYEOF
}
# perm <handle> <command> [<description>]: the prompt for one command on one row
perm() { permrows "$1" "${3-Search the sources}" "$2"; }
sends() { grep -c 'terminal send' "$TMP/orca-calls" 2>/dev/null || true; }
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do Y add "N-$n" "terminal=tN$n" >/dev/null; done
CMD1='grep -rln "class ElectronApplication" node_modules/playwright-core'
perm tN1 "$CMD1"; : > "$TMP/orca-calls"
out=$(Y nudge N-1)
[ "$out" = "nudged N-1 permission: $CMD1" ] && pass "a read-only command is nudged" || fail "nudge read-only ($out)"
[ "$(grep -c 'terminal send --terminal tN1 --enter' "$TMP/orca-calls")" = 1 ] && [ "$(sends)" = 1 ] && pass "one Enter, nothing else" || fail "nudge keys ($(cat "$TMP/orca-calls"))"
[ "$(sed -n '$p' "$H/progress/N-1.log" | cut -d' ' -f2-)" = "nudged permission: $CMD1" ] && pass "the nudge is logged" || fail "nudge log ($(cat "$H/progress/N-1.log"))"
CMD2='node -e "require.resolve(\"playwright-core\")"'
perm tN2 "$CMD2"; : > "$TMP/orca-calls"
out=$(Y nudge N-2)
[ "$out" = "prompt N-2 new permission: $CMD2" ] && [ "$(sends)" = 0 ] && pass "node -e is reported, not sent" || fail "node -e ($out)"
out=$(Y nudge N-2)
[ "$out" = "prompt N-2 permission: $CMD2" ] && [ "$(sends)" = 0 ] && pass "the same dialog on a later tick has no new" || fail "node -e again ($out)"
perm tN3 'rm -rf build'; out=$(Y nudge N-3)
[ "$out" = "prompt N-3 new permission: rm -rf build" ] && [ "$(sends)" = 0 ] && pass "rm -rf is reported, not sent" || fail "rm -rf ($out)"
perm tN4 'cat package.json'
python3 -c 'import json; print(json.dumps({"ok":True,"result":{"terminal":{"source":"screen","tail":["Do you want to proceed?","❯ 1. Yes","  2. No"]}}}))' > "$TMP/screen-tN4.next"
: > "$TMP/orca-calls"; out=$(Y nudge N-4)
[ -z "$out" ] && [ "$(sends)" = 0 ] && pass "a dialog that changed between the two reads gets nothing" || fail "changed dialog ($out / $(cat "$TMP/orca-calls"))"
screen tN5 "Welcome to Claude Code" "Do you trust the files in this folder?" "❯ 1. No, exit" "  2. Yes, proceed"; : > "$TMP/orca-calls"
out=$(Y nudge N-5)
[ "$out" = "nudged N-5 trust dialog" ] && [ "$(sends)" = 2 ] && grep -q 'terminal send --terminal tN5 --text' "$TMP/orca-calls" && [ "$(grep -c 'tN5 --enter' "$TMP/orca-calls")" = 1 ] && pass "the trust dialog gets down, then Enter" || fail "trust ($out / $(cat "$TMP/orca-calls"))"
[ "$(sed -n '$p' "$H/progress/N-5.log" | cut -d' ' -f2-)" = "nudged trust dialog" ] && pass "the trust nudge is logged" || fail "trust log"
screen tN6 "WARNING: Claude Code running in Bypass Permissions mode" "❯ 1. No, exit" "  2. Yes, I accept"; : > "$TMP/orca-calls"
[ "$(Y nudge N-6)" = "nudged N-6 bypass dialog" ] && [ "$(sends)" = 2 ] && pass "the bypass dialog gets down, then Enter" || fail "bypass"
screen tN7 "⏺ Done." "" "❯ "; : > "$TMP/orca-calls"
[ -z "$(Y nudge N-7)" ] && [ "$(sends)" = 0 ] && pass "no dialog, no line" || fail "no dialog"
case "$(Y nudge N-8)" in "unknown N-8 "*) pass "an unreadable terminal is unknown" ;; *) fail "unknown ($(Y nudge N-8))" ;; esac
screen tN9 "Do you want to make this edit to src/app.ts?" "❯ 1. Yes" "  2. Yes, allow all edits during this session" "  3. No"
[ "$(Y nudge N-9)" = "prompt N-9 new edit: Do you want to make this edit to src/app.ts?" ] && pass "an edit dialog is reported as edit" || fail "edit ($(Y nudge N-9))"
screen tN10 "New MCP server found in .mcp.json: evil" "❯ 1. Use this and all future MCP servers in this project" "  2. Use this MCP server" "  3. Continue without using this MCP server"; : > "$TMP/orca-calls"
[ "$(Y nudge N-10)" = "prompt N-10 new mcp: New MCP server found in .mcp.json: evil" ] && [ "$(sends)" = 0 ] && pass "an MCP dialog is reported, never answered" || fail "mcp ($(Y nudge N-10))"
screen tN11 "Select a model" "❯ 1. Opus" "  2. Haiku"
[ "$(Y nudge N-11)" = "prompt N-11 new dialog: Select a model" ] && pass "another numbered question is a dialog" || fail "dialog ($(Y nudge N-11))"
python3 - "$H/items.json" <<'PY' && pass "the prompt fingerprint is kept, and cleared when the dialog is gone" || fail "prompt field"
import json, sys
rows = {r["item"]: r for r in json.load(open(sys.argv[1]))["items"]}
assert len(rows["N-2"]["prompt"]) == 12 and "prompt" not in rows["N-7"] and "prompt" not in rows["N-1"], rows["N-2"]
PY
screen tN12 "Welcome" "❯ 1. fix the build"
[ -z "$(Y nudge N-12)" ] && pass "a typed numbered prompt row is not a dialog" || fail "prompt row ($(Y nudge N-12))"
screen tN2 "Working"; screen tN3 "Working"; screen tN4 "Working"; screen tN5 "Working"; screen tN6 "Working"; screen tN9 "Working"; screen tN10 "Working"; screen tN11 "Working"
perm tN1 "$CMD1"
out=$(Y nudge)
[ "$(echo "$out" | sed -n 1p)" = "nudged N-1 permission: $CMD1" ] && [ "$(echo "$out" | sed -n 2p | cut -d' ' -f1-2)" = "unknown N-8" ] && [ "$(echo "$out" | wc -l | tr -d ' ')" = 2 ] && pass "no names: every running row with a terminal, in row order" || fail "nudge all ($out)"
# --- nudge: one row, a box, the unreadable re-read (review fixes) ---
for n in 21 22 23 24 25 26; do Y add "N-$n" "terminal=tN$n" >/dev/null; done
permrows tN21 "Search the sources" 'grep -rn foo src' 'npm install'; : > "$TMP/orca-calls"
out=$(Y nudge N-21)
[ "$out" = "prompt N-21 new permission: grep -rn foo src npm install Search the sources" ] && [ "$(sends)" = 0 ] && pass "a command on two rows is reported with its rows joined, never sent" || fail "two rows ($out)"
LONG='grep -rn "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
permrows tN23 "Search the sources" "$LONG"; : > "$TMP/orca-calls"
out=$(Y nudge N-23)
case "$out" in "prompt N-23 new permission: "*) [ "$(sends)" = 0 ] && pass "a row that reaches the box edge may be wrapped: reported, never sent" || fail "wrapped sent" ;; *) fail "wrapped ($out)" ;; esac
W=300 permrows tN24 "Search the sources" "$LONG\""; : > "$TMP/orca-calls"
out=$(Y nudge N-24)
[ "$out" = "nudged N-24 permission: $LONG\"" ] && pass "the same row in a wider box is a command" || fail "wide box ($out)"
python3 -c 'import json; print(json.dumps({"ok":True,"result":{"terminal":{"source":"screen","tail":["Bash command","","  grep -rn foo src","  Search the sources","","Do you want to proceed?","❯ 1. Yes","  2. Yes, and don'"'"'t ask again","  3. No, and tell Claude what to do differently (esc)"]}}}))' > "$TMP/screen-tN25.json"; : > "$TMP/orca-calls"
out=$(Y nudge N-25)
[ "$out" = "nudged N-25 permission: grep -rn foo src" ] && pass "without a border the longest row of the dialog is the width" || fail "no border ($out)"
for n in 27 28 29 30; do Y add "N-$n" "terminal=tN$n" >/dev/null; done
permrows tN27 "" 'grep -rn foo src' 'npm install'; : > "$TMP/orca-calls"
out=$(Y nudge N-27)
[ "$out" = "prompt N-27 new permission: grep -rn foo src npm install" ] && [ "$(sends)" = 0 ] && pass "a second row that runs (npm install) is a command row, not a description" || fail "npm row ($out)"
permrows tN28 "" 'grep -rn foo src' 'Npm install'; : > "$TMP/orca-calls"
out=$(Y nudge N-28)
[ "$out" = "prompt N-28 new permission: grep -rn foo src Npm install" ] && [ "$(sends)" = 0 ] && pass "a capitalised program still runs on a case-insensitive disk: not a description" || fail "Npm row ($out)"
permrows tN29 "" 'grep -rn foo src' 'Search the sources'; : > "$TMP/orca-calls"
out=$(Y nudge N-29)
[ "$out" = "nudged N-29 permission: grep -rn foo src" ] && pass "a capitalised prose row is the description" || fail "prose row ($out)"
permrows tN30 "" 'grep -rln "class ElectronApplication" node_modules/playwright-core' 'Check for the class'; : > "$TMP/orca-calls"
out=$(Y nudge N-30)
[ "$out" = "nudged N-30 permission: grep -rln \"class ElectronApplication\" node_modules/playwright-core" ] && pass "the issue's command with its description is nudged" || fail "issue row ($out)"
permrows tN27 "" 'grep -rn foo src' 'search the sources'; : > "$TMP/orca-calls"
out=$(Y nudge N-27); [ "$out" = "prompt N-27 new permission: grep -rn foo src search the sources" ] && pass "a lowercase second row is not a description" || fail "lowercase row ($out)"
perm tN26 'cat package.json'; echo '{"ok":false}' > "$TMP/screen-tN26.next"; : > "$TMP/orca-calls"
out=$(Y nudge N-26)
[ "$out" = "unknown N-26 terminal cannot be read" ] && [ "$(sends)" = 0 ] && pass "a failing second read is unknown, not silence" || fail "second read ($out)"
# a nudge leaves the sweep's step and quiet clock alone
Y add NQ "path=$(wt NQ)" branch=feat/NQ
printf '%s phase4 executing\n%s nudged permission: ls\n' "$(stamp $((NOW - 3 * 3600)))" "$(stamp "$NOW")" > "$P/NQ.log"
Y sweep | grep -qx 'quiet NQ 3h00m phase4' && pass "a nudged line is not the step, and does not reset the quiet clock" || fail "sweep ignores nudged ($(Y sweep | grep NQ))"
# the read-only rule, directly
yes_() { Y readonly "$1" >/dev/null 2>&1 && pass "read-only: $1" || fail "should be read-only: $1"; }
no_() { Y readonly "$1" >/dev/null 2>&1 && fail "should not be read-only: $1" || pass "not read-only: $1"; }
yes_ 'grep -rln "class ElectronApplication" node_modules/playwright-core'
yes_ 'ls -la src | head -20'
yes_ 'git log --oneline -5 && git status'
yes_ 'git --no-pager log --oneline -3'
yes_ 'find . -name "*.ts" -not -path "./node_modules/*"'
yes_ "sed -n '1,40p' src/a.ts"
yes_ "sed 's/a/b/g' a.ts"
yes_ 'git branch --list "feat/*"'
yes_ 'git branch'
yes_ 'command -v node'
yes_ "grep -rn 'a>b' src"
yes_ 'cat a.txt; wc -l a.txt || echo none'
no_ 'node -e "1"'
no_ 'rm -rf build'
no_ 'curl https://example.com'
no_ 'npm test'
no_ 'cat a > b'
no_ 'cat a >> b'
no_ 'cat < a'
no_ 'ls 2> err'
no_ 'ls &> err'
no_ 'echo $(rm x)'
no_ 'echo `rm x`'
no_ 'ls & rm x'
no_ 'ls; rm x'
no_ 'ls | xargs rm'
no_ 'sudo ls'
no_ 'find . -exec rm {} ;'
no_ 'find . -delete'
no_ 'find . -fprint out'
no_ 'find . -ok rm {} ;'
no_ "sed -i 's/a/b/' a.ts"
no_ "sed --in-place 's/a/b/' a.ts"
no_ "sed -n 'w out' a.ts"
no_ "sed 's/a/b/w out' a.ts"
no_ "sed -n '1W out' a.ts"
no_ "awk 'BEGIN{system(\"rm x\")}'"
no_ "awk '{print > \"f\"}' a"
no_ "awk '{print | \"sh\"}' a"
no_ 'git commit -m x'
no_ 'git push'
no_ 'git checkout main'
no_ 'git branch newbranch'
no_ 'git diff --output=out'
no_ 'git -c core.pager=sh log'
no_ 'sort -o out a'
no_ 'rg --pre sh foo'
no_ 'date -s tomorrow'
no_ 'grep -rn "a>b" src'
no_ "sed -n '/foo/p' a.ts"
no_ "$(printf 'ls\nls')"
no_ "echo \$'a'"
no_ 'echo ${HOME}'
no_ 'echo $HOME'
no_ 'echo (x)'
no_ 'echo {a,b}'
no_ 'echo hi!'
no_ 'cat <(ls)'
no_ 'echo a\b'
no_ 'echo "$HOME"'
no_ 'echo "a\b"'
no_ 'cat /etc/passwd'
no_ 'cat ~/.ssh/id_rsa'
no_ 'cat ~'
no_ 'cat ../x'
no_ 'cat a/../../x'
no_ 'grep -f/x pat a'
no_ 'grep --file=/x pat a'
no_ 'grep -rn foo /'
no_ 'jq -n env'
no_ 'jq . a.json'
no_ "awk '{print 1}' a.txt"
no_ 'awk 1 a.txt'
no_ 'git -C sub status'
no_ 'git -C /tmp/x diff --stat'
no_ 'git -c core.pager=x log'
no_ 'git --git-dir=x log'
no_ 'git --work-tree=x status'
no_ 'git --exec-path=x status'
no_ ''

# --- skip memory ---
[ "$(Y skip K-1 'a first-run dialog')" = new ] && [ "$(Y skip K-1 'a first-run dialog')" = seen ] && pass "skip: new, then seen" || fail "skip"
Y skip K-1 --clear; [ "$(Y skip K-1 'again')" = new ] && pass "skip --clear drops it" || fail "skip clear"
Y add K-1 >/dev/null; [ "$(Y skip K-1 'again')" = new ] && pass "add clears the item's skip" || fail "add clears skip"

# --- unpark, plan=, followup, queue (#215) ---
Y add U-1 "path=$(wt U-1)" branch=feat/U-1
printf '%s parked out of tries: regression gate plan=docs/superpowers/plans/fix.md\n' "$(stamp "$NOW")" > "$P/U-1.log"
out=$(Y sweep)
echo "$out" | grep -qx 'parked U-1 out of tries: regression gate' && pass "park plan is omitted from the note" || fail "park plan output ($out)"
[ "$(Y list | awk -F '\t' '$1=="U-1"{print $6}')" = "out of tries: regression gate" ] && pass "park note omits plan" || fail "park note"
python3 -c 'import json,sys; r=[x for x in json.load(open(sys.argv[1]))["items"] if x["item"]=="U-1"][0]; assert r["plan"]=="docs/superpowers/plans/fix.md" and r["parkedAt"]' "$H/items.json" && pass "park plan and parkedAt are stored" || fail "park row metadata"
printf '%s phase4 resumed: fix plan\n' "$(stamp $((NOW + 60)))" >> "$P/U-1.log"
out=$(YUKI_NOW=$((NOW + 120)) Y sweep)
echo "$out" | grep -qx 'unparked U-1 phase4' && [ "$(Y list | awk -F '\t' '$1=="U-1"{print $2}')" = running ] && pass "new work unparks a row" || fail "unpark ($out)"
Y add U-2 "path=$(wt U-2)" branch=feat/U-2
printf '%s parked out of tries: regression plan=fix.md\n' "$(stamp "$NOW")" > "$P/U-2.log"
Y sweep >/dev/null
printf '%s resumed plan fix.md\n' "$(stamp $((NOW + 60)))" >> "$P/U-2.log"
out=$(Y sweep)
if echo "$out" | grep -q '^unparked U-2 '; then
  fail "a resumed line unparks a row"
elif [ "$(Y list | awk -F '\t' '$1=="U-2"{print $2}')" = parked ]; then
  pass "yuki resume lines are not progress"
else
  fail "resume line changed parked state"
fi
Y add U-3 "path=$(wt U-3)" branch=feat/U-3
printf '%s parked out of tries: ci\n' "$(stamp "$NOW")" > "$P/U-3.log"
Y sweep >/dev/null
python3 - "$H/items.json" "$(stamp $((NOW + 60)))" <<'PY'
import json, sys
path, resumed = sys.argv[1:]
data = json.load(open(path))
next(row for row in data["items"] if row["item"] == "U-3").update(state="running", resumed=resumed)
json.dump(data, open(path, "w"))
PY
out=$(YUKI_NOW=$((NOW + 120)) Y sweep)
echo "$out" | grep -qx 'running U-3 parked 1m' && pass "a stale park does not re-park a resumed row" || fail "stale park ($out)"
printf '%s parked out of tries: ci\n' "$(stamp $((NOW + 180)))" >> "$P/U-3.log"
out=$(YUKI_NOW=$((NOW + 240)) Y sweep)
echo "$out" | grep -qx 'parked U-3 out of tries: ci' && pass "a new park after resume parks" || fail "new park ($out)"
Y add U-4 "path=$(wt U-4)" branch=feat/U-4
printf '%s phase5 executing\n' "$(stamp $((NOW - 3 * 3600)))" > "$P/U-4.log"
python3 - "$H/items.json" "$(stamp $((NOW - 600)))" <<'PY'
import json, sys
path, resumed = sys.argv[1:]
data = json.load(open(path))
next(row for row in data["items"] if row["item"] == "U-4").update(resumed=resumed)
json.dump(data, open(path, "w"))
PY
out=$(Y sweep)
echo "$out" | grep -qx 'running U-4 phase5 10m' && pass "quiet age starts from the resume" || fail "resume quiet clock ($out)"
Y add U-5 "path=$(wt U-5)" branch=feat/U-5 pr=https://github.com/o/r/pull/55
printf '%s phase8 reviewing\n%s followup #300\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/U-5.log"
: > "$TMP/orca-calls"; echo OPEN > "$TMP/pr-55"
out=$(Y sweep)
[ -z "$(Y queue)" ] && pass "follow-up is not queued before merge" || fail "premature follow-up queue ($(Y queue))"
echo MERGED > "$TMP/pr-55"; Y sweep >/dev/null
[ "$(Y queue)" = '#300' ] && pass "merged follow-up is queued" || fail "merged follow-up ($(Y queue))"
Y add issue-300 ref=#300 "path=$(wt U-300)"
[ -z "$(Y queue)" ] && pass "known follow-up is not queued again" || fail "known follow-up queued ($(Y queue))"
[ "$(Y config idleMinutes)" = 30 ] && [ "$(Y config unblock)" = null ] && pass "new config defaults" || fail "new config defaults"
Y config idleMinutes 4 2>/dev/null && fail "idleMinutes below 5 accepted" || pass "idleMinutes below 5 refused"
Y config idleMinutes 1441 2>/dev/null && fail "idleMinutes above 1440 accepted" || pass "idleMinutes above 1440 refused"
Y config unblock '"yes"' 2>/dev/null && fail "invalid unblock accepted" || pass "unblock accepts only null or merge"
Y config unblock '"merge"'; [ "$(Y config unblock)" = merge ] && Y config unblock null && pass "unblock merge can be set and cleared" || fail "unblock setting"
(cd "$APP" && PATH="$TMP/bin:$PATH" sh "$SCRIPT" --kind yuna queue 2>&1) | grep -q 'queue is a yuki command' && pass "yuna refuses queue" || fail "yuna queue refusal"

# --- sweep review fixes (#215) ---
st() { Y list | awk -F '\t' -v i="$1" '$1==i{print $2}'; }
fld() { python3 -c 'import json,sys; r=next(x for x in json.load(open(sys.argv[1]))["items"] if x["item"]==sys.argv[2]); print(r.get(sys.argv[3], "-"))' "$H/items.json" "$1" "$2"; }
X1=$(wt X-1); Y add X-1 "path=$X1"; Y set X-1 state=done >/dev/null; printf '\377\n' >> "$P/X-1.log"
X2=$(wt X-2); Y add X-2 "path=$X2"; printf '\377\n' > "$P/X-2.log"
X3=$(wt X-3); Y add X-3 "path=$X3"; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/X-3.log"
out=$(Y sweep 2>&1)
echo "$out" | grep -q '^running X-2 ' && echo "$out" | grep -q '^running X-3 ' && pass "invalid UTF-8 in done and running logs does not stop the sweep" || fail "invalid UTF-8 sweep ($out)"
: > "$P/X-1.log"; : > "$P/X-2.log"
Y add X-4 "path=$TMP/wt/not-created" pr=https://github.com/o/r/pull/804; echo CLOSED > "$TMP/pr-804"
printf '%s phase8 reviewing\n' "$(stamp "$NOW")" > "$P/X-4.log"; Y sweep >/dev/null
printf '%s phase8 reviewing again\n' "$(stamp $((NOW + 60)))" >> "$P/X-4.log"
out=$(YUKI_NOW=$((NOW + 120)) Y sweep)
[ -z "$(echo "$out" | grep '^unparked X-4 ')" ] && [ "$(st X-4)" = parked ] && pass "a newer line does not unpark a sweep PR-closed park" || fail "PR-closed park was unparked ($out)"
Y add X-5 "path=$TMP/wt/also-not-created"
printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/X-5.log"; Y sweep >/dev/null
printf '%s phase4 by hand\n' "$(stamp $((NOW + 180)))" >> "$P/X-5.log"
out=$(YUKI_NOW=$((NOW + 240)) Y sweep)
[ -z "$(echo "$out" | grep '^unparked X-5 ')" ] && [ "$(st X-5)" = parked ] && pass "a newer line does not unpark a sweep worktree-gone park" || fail "worktree-gone park was unparked ($out)"
X6=$(wt X-6); Y add X-6 "path=$X6"; printf '%s parked needs a person: key\n' "$(stamp "$NOW")" > "$P/X-6.log"; Y sweep >/dev/null
printf '%s phase4 executing\n' "$(stamp $((NOW + 60)))" >> "$P/X-6.log"; out=$(YUKI_NOW=$((NOW + 120)) Y sweep)
(YUKI_NOW=$((NOW + 180)) Y set X-6 state=parked note=held >/dev/null)
out=$(YUKI_NOW=$((NOW + 240)) Y sweep)
[ -z "$(echo "$out" | grep '^unparked X-6 ')" ] && [ "$(st X-6)" = parked ] && [ "$(fld X-6 parkedAt)" != - ] && pass "Y set stamps a manual park so sweep keeps it" || fail "manual park was unparked ($out)"
X7=$(wt X-7); Y add X-7 "path=$X7"; printf '%s parked out of tries: first plan=a.md\n' "$(stamp "$NOW")" > "$P/X-7.log"; Y sweep >/dev/null
printf '%s parked out of tries: gate plan=b.md\n' "$(stamp $((NOW + 60)))" >> "$P/X-7.log"
out=$(YUKI_NOW=$((NOW + 120)) Y sweep)
echo "$out" | grep -qx 'parked X-7 out of tries: gate' && [ "$(fld X-7 plan)" = b.md ] && pass "a newer worker park refreshes note and plan" || fail "newer park line ($out; plan $(fld X-7 plan))"
X8=$(wt X-8); Y add X-8 "path=$X8"; printf '%s parked out of tries: x plan=p.md  \n' "$(stamp "$NOW")" > "$P/X-8.log"
Y sweep >/dev/null
[ "$(Y list | awk -F '\t' '$1=="X-8"{print $6}')" = 'out of tries: x' ] && [ "$(fld X-8 plan)" = p.md ] && pass "split_plan accepts trailing spaces" || fail "trailing plan spaces"
X21=$(wt X-21); Y add X-21 "path=$X21"; Y set X-21 state=parked note=legacy >/dev/null
python3 - "$H/items.json" "$(stamp "$NOW")" <<'PY'
import json, sys
p, t = sys.argv[1:]
d = json.load(open(p))
r = next(x for x in d["items"] if x["item"] == "X-21")
r.pop("parkedAt", None)
r["updated"] = t
json.dump(d, open(p, "w"))
PY
printf '%s phase4 by hand\n' "$(stamp $((NOW + 60)))" > "$P/X-21.log"
(YUKI_NOW=$((NOW + 120)) Y sweep) | grep -qx 'unparked X-21 phase4' && pass "P17 a legacy parked row un-parks by updated" || fail "P17"
for spec in "Q-1 901 #702" "Q-2 902 #701" "Q-3 903 #702"; do set -- $spec; Y add "$1" "path=$(wt "$1")" "pr=https://github.com/o/r/pull/$2"; printf '%s phase8 x\n%s followup %s\n' "$(stamp "$NOW")" "$(stamp "$NOW")" "$3" > "$P/$1.log"; echo MERGED > "$TMP/pr-$2"; done
Y sweep >/dev/null
[ "$(Y queue | tr '\n' ' ')" = '#702 #701 ' ] && pass "P19 queue keeps row order and one line per ref" || fail "P19 ($(Y queue | tr '\n' ' '))"

# --- unblock (#215) ---
idle() { screen "$1" "⏺ Done." "" "────────────────────────────" "❯ " "────────────────────────────" "  ⏵⏵ bypass permissions on (shift+tab to cycle)"; }
tt() { python3 -c 'import os,sys; t=int(sys.argv[2]); os.utime(sys.argv[1], (t,t))' "$1" "$2"; }
sent() { grep -c "terminal send --terminal $1 --text" "$TMP/orca-calls" 2>/dev/null || true; }
Y config maxParallel 20
# The subcommand must be recognized even when its named row is absent.
[ "$(Y unblock V-404)" = 'unknown V-404 no such row' ] && pass "unblock command is available" || fail "unblock command dispatch"
# 1. Idle running row: one prompt, one line, one log line.
V1=$(wt V-1); Y add V-1 "path=$V1" branch=feat/V-1 terminal=tV1 ref=#901
printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/V-1.log"; idle tV1; : > "$TMP/orca-calls"
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock V-1)
[ "$out" = 'resumed V-1 idle 2h00m phase4' ] && pass "an idle running row resumes once" || fail "idle resume ($out)"
[ "$(sent tV1)" = 1 ] && grep -F 'yuki: resume V-1 (idle): no progress for 2h00m, last step phase4.' "$TMP/orca-calls" | grep -q -- '--enter$' && pass "idle resume sends one prompt with Enter" || fail "idle send count or command ($(sent tV1))"
grep -F 'skills/ship-ticket/SKILL.md' "$TMP/orca-calls" | grep -F 'Resumed by yuki' | grep -F 'run_in_background: true' | grep -F 'all parallel' | grep -F 'gate-lock.sh' | grep -F 'Ref #901' >/dev/null && pass "idle prompt carries the ship-ticket protocol and ref" || fail "idle prompt text"
[ "$(sed -n '$p' "$P/V-1.log" | cut -d' ' -f2-3)" = 'resumed idle' ] && pass "idle resume is logged" || fail "idle resume log"
# 2. Active turns, dialogs, typed prompts and recent activity are untouched.
V2=$(wt V-2); Y add V-2 "path=$V2" terminal=tV2; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/V-2.log"
screen tV2 "✻ Working… (12s · esc to interrupt)" "────────────────────────────" "❯ " "────────────────────────────"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-2)" ] && [ "$(sent tV2)" = 0 ] && pass "a running turn is not idle" || fail "running turn resumed"
V3=$(wt V-3); Y add V-3 "path=$V3" terminal=tV3; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/V-3.log"
screen tV3 "Do you want to proceed?" "❯ 1. Yes" "  2. No"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-3)" ] && [ "$(sent tV3)" = 0 ] && pass "a dialog is not idle" || fail "dialog resumed"
V4=$(wt V-4); Y add V-4 "path=$V4" terminal=tV4; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/V-4.log"
screen tV4 "⏺ Done." "" "────────────────────────────" "❯ fix the build" "────────────────────────────"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-4)" ] && [ "$(sent tV4)" = 0 ] && pass "a typed prompt is not idle" || fail "typed prompt resumed"
V5=$(wt V-5); Y add V-5 "path=$V5" terminal=tV5; printf '%s phase4 executing\n%s phase4 executing\n' "$(stamp "$NOW")" "$(stamp $((NOW + 7000)))" > "$P/V-5.log"
idle tV5
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-5)" ] && [ "$(sent tV5)" = 0 ] && pass "recent progress is activity" || fail "recent progress resumed"
V6=$(wt V-6); Y add V-6 "path=$V6" terminal=tV6; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/V-6.log"
(cd "$V6" && GIT_COMMITTER_DATE="@$((NOW + 7000)) +0000" git commit -q --allow-empty -m wip)
idle tV6
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-6)" ] && [ "$(sent tV6)" = 0 ] && pass "a recent commit is activity" || fail "recent commit resumed"
V7=$(wt V-7); Y add V-7 "path=$V7" terminal=tV7; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/V-7.log"
echo x > "$V7/a.txt"; tt "$V7/a.txt" $((NOW + 7080)); idle tV7
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-7)" ] && [ "$(sent tV7)" = 0 ] && pass "a recently changed file is activity" || fail "changed file resumed"
# 3. The same stall parks once; new work permits another resume.
out=$(YUKI_NOW=$((NOW + 7200 + 1900)) Y unblock V-1)
[ "$out" = 'parked V-1 idle after a resume' ] && [ "$(sent tV1)" = 1 ] && [ "$(Y list | awk -F '\t' '$1=="V-1"{print $2}')" = parked ] && pass "a repeated idle stall parks without another prompt" || fail "repeat idle stall ($out)"
V9=$(wt V-9); Y add V-9 "path=$V9" terminal=tV9; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/V-9.log"; idle tV9
[ "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-9)" = 'resumed V-9 idle 2h00m phase4' ] && pass "a first idle stall resumes" || fail "first V-9 resume"
printf '%s phase5 executing\n' "$(stamp $((NOW + 7300)))" >> "$P/V-9.log"
[ "$(YUKI_NOW=$((NOW + 7300 + 1900)) Y unblock V-9)" = 'resumed V-9 idle 31m phase5' ] && pass "new work permits a later idle resume" || fail "second V-9 resume"
# 4. A parked fix plan is resumed once, missing plans are dropped, busy screens are untouched.
V20=$(wt V-20); Y add V-20 "path=$V20" terminal=tV20
mkdir -p "$V20/docs/superpowers/plans"; : > "$V20/docs/superpowers/plans/fix.md"
printf '%s parked out of tries: gate plan=docs/superpowers/plans/fix.md\n' "$(stamp "$NOW")" > "$P/V-20.log"; Y sweep >/dev/null; idle tV20; : > "$TMP/orca-calls"
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock V-20)
[ "$out" = 'resumed V-20 plan docs/superpowers/plans/fix.md' ] && [ "$(Y list | awk -F '\t' '$1=="V-20"{print $2}')" = running ] && grep -F 'yuki: resume V-20 (plan ' "$TMP/orca-calls" >/dev/null && pass "a parked plan resumes once" || fail "plan resume ($out)"
: > "$V20/docs/superpowers/plans/fix2.md"; printf '%s parked out of tries: gate plan=docs/superpowers/plans/fix2.md\n' "$(stamp $((NOW + 7300)))" >> "$P/V-20.log"; (YUKI_NOW=$((NOW + 7300)) Y sweep >/dev/null)
out=$(YUKI_NOW=$((NOW + 7400)) Y unblock V-20)
echo "$out" | grep -q 'resumed V-20 plan' && fail "a plan is resumed twice" || [ "$(sent tV20)" = 1 ] && pass "a parked row gets only one plan resume" || fail "plan resume send count ($(sent tV20))"
V21=$(wt V-21); Y add V-21 "path=$V21" terminal=tV21; printf '%s parked out of tries: gate plan=nope.md\n' "$(stamp "$NOW")" > "$P/V-21.log"; Y sweep >/dev/null; idle tV21; : > "$TMP/orca-calls"
[ "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-21)" = 'unknown V-21 no such plan nope.md' ] && [ "$(sent tV21)" = 0 ] && pass "a missing fix plan is reported and dropped" || fail "missing plan"
python3 -c 'import json,sys; r=next(x for x in json.load(open(sys.argv[1]))["items"] if x["item"]=="V-21"); assert "plan" not in r' "$H/items.json" && pass "missing plan is removed from the row" || fail "missing plan retained"
V22=$(wt V-22); Y add V-22 "path=$V22" terminal=tV22; : > "$V22/plan.md"; printf '%s parked out of tries: gate plan=plan.md\n' "$(stamp "$NOW")" > "$P/V-22.log"; Y sweep >/dev/null
screen tV22 "✻ Working… (12s · esc to interrupt)" "────────────────────────────" "❯ " "────────────────────────────"; : > "$TMP/orca-calls"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-22)" ] && [ "$(sent tV22)" = 0 ] && pass "a live turn blocks plan resume" || fail "busy plan resumed"
# 5. The merge path is opt-in, eligible only after phase 6 or a PR, and runs once.
V30=$(wt V-30); Y add V-30 "path=$V30" terminal=tV30 pr=https://github.com/o/r/pull/30
printf '%s phase8 reviewing\n%s parked out of tries: ci red\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/V-30.log"; Y sweep >/dev/null; idle tV30; : > "$TMP/orca-calls"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-30)" ] && [ "$(sent tV30)" = 0 ] && pass "unblock is off by default" || fail "unblock ran while disabled"
Y config unblock '"merge"'
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock V-30)
[ "$out" = 'unblocking V-30 https://github.com/o/r/pull/30' ] && [ "$(Y list | awk -F '\t' '$1=="V-30"{print $2}')" = running ] && grep -F 'yuki: unblock V-30 (merge)' "$TMP/orca-calls" >/dev/null && pass "eligible parked PR is unblocked" || fail "unblock merge ($out)"
printf '%s parked out of tries: ci red\n' "$(stamp $((NOW + 7300)))" >> "$P/V-30.log"; (YUKI_NOW=$((NOW + 7300)) Y sweep >/dev/null)
out=$(YUKI_NOW=$((NOW + 7400)) Y unblock V-30)
echo "$out" | grep -q '^unblocking V-30 ' && fail "a row is unblocked twice" || [ "$(sent tV30)" = 1 ] && pass "unblock is once per row" || fail "unblock send count ($(sent tV30))"
V31=$(wt V-31); Y add V-31 "path=$V31" terminal=tV31; printf '%s phase7 reviewing\n%s parked needs a person: STRIPE_KEY\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/V-31.log"; Y sweep >/dev/null; idle tV31; : > "$TMP/orca-calls"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-31)" ] && [ "$(sent tV31)" = 0 ] && pass "a needs-a-person park is ineligible" || fail "needs-a-person unblocked"
V32=$(wt V-32); Y add V-32 "path=$V32" terminal=tV32; printf '%s phase4 executing\n%s parked out of tries: executor\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/V-32.log"; Y sweep >/dev/null; idle tV32; : > "$TMP/orca-calls"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-32)" ] && [ "$(sent tV32)" = 0 ] && pass "a pre-phase-6 row without a PR is ineligible" || fail "early row unblocked"
V33=$(wt V-33); Y add V-33 "path=$V33" terminal=tV33; mkdir -p "$V33/docs/superpowers/plans"; : > "$V33/docs/superpowers/plans/fix.md"
printf '%s phase6 verifying\n%s parked out of tries: gate plan=docs/superpowers/plans/fix.md\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/V-33.log"; Y sweep >/dev/null; idle tV33; : > "$TMP/orca-calls"
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock V-33)
[ "$out" = 'resumed V-33 plan docs/superpowers/plans/fix.md' ] && ! echo "$out" | grep -q '^unblocking' && pass "an unused plan takes priority over unblock" || fail "plan priority ($out)"
V34=$(wt V-34); Y add V-34 "path=$V34" terminal=tV34; printf '%s phase6 verifying\n%s parked out of tries: gate\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/V-34.log"; Y sweep >/dev/null; idle tV34; : > "$TMP/orca-calls"
[ "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-34)" = 'unblocking V-34 -' ] && pass "phase 6 permits unblock without a PR" || fail "phase 6 unblock"
# 6. An unreadable terminal is unknown, not silently idle.
V40=$(wt V-40); Y add V-40 "path=$V40" terminal=tV40; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/V-40.log"; : > "$TMP/orca-calls"
case "$(YUKI_NOW=$((NOW + 7200)) Y unblock V-40)" in 'unknown V-40 '*) pass "an unreadable terminal is unknown" ;; *) fail "unreadable terminal" ;; esac
(cd "$APP" && PATH="$TMP/bin:$PATH" sh "$SCRIPT" --kind yuna unblock 2>&1) | grep -q 'unblock is a yuki command' && pass "yuna refuses unblock" || fail "yuna unblock refusal"

# --- unblock review fixes (#215) ---
Y config unblock null
# P1 no names: running and parked rows with terminals, kept in row order.
R1=$(wt R-1); Y add R-1 "path=$R1" terminal=tR1; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/R-1.log"; idle tR1
R2=$(wt R-2); Y add R-2 "path=$R2" terminal=tR2; : > "$R2/p.md"; printf '%s parked out of tries: gate plan=p.md\n' "$(stamp "$NOW")" > "$P/R-2.log"; idle tR2
R3=$(wt R-3); Y add R-3 "path=$R3"; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/R-3.log"
Y sweep >/dev/null; : > "$TMP/orca-calls"
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock)
echo "$out" | grep -qx 'resumed R-1 idle 2h00m phase4' && echo "$out" | grep -qx 'resumed R-2 plan p.md' && ! echo "$out" | grep -q ' R-3 ' \
  && [ "$(echo "$out" | grep -n '^resumed R-1 ' | cut -d: -f1)" -lt "$(echo "$out" | grep -n '^resumed R-2 ' | cut -d: -f1)" ] \
  && [ "$(fld R-1 idleResumed)" != - ] && [ "$(st R-2)" = running ] && pass "P1 no names: all eligible rows run in row order" || fail "P1 no-arg ($out)"
# P2 the idle clock runs from the resume.
R4=$(wt R-4); Y add R-4 "path=$R4" terminal=tR4; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/R-4.log"; idle tR4; : > "$TMP/orca-calls"
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-4)
out=$(YUKI_NOW=$((NOW + 7800)) Y unblock R-4)
[ -z "$out" ] && [ "$(sent tR4)" = 1 ] && [ "$(st R-4)" = running ] && pass "P2 a stall 10m after the resume is left alone" || fail "P2 resume clock ($out)"
# P3 a plan resume is the first resume; its acknowledgement is not work.
R5=$(wt R-5); Y add R-5 "path=$R5" terminal=tR5; : > "$R5/p.md"; printf '%s parked out of tries: gate plan=p.md\n' "$(stamp "$NOW")" > "$P/R-5.log"; Y sweep >/dev/null; idle tR5; : > "$TMP/orca-calls"
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-5)
printf '%s phase4 resumed: rerun the hung verify shell\n' "$(stamp $((NOW + 7230)))" >> "$P/R-5.log"
out=$(YUKI_NOW=$((NOW + 7230 + 1900)) Y unblock R-5)
[ "$out" = 'parked R-5 idle after a resume' ] && [ "$(sent tR5)" = 1 ] && pass "P3 an acknowledgement after a plan resume does not count as work" || fail "P3 plan acknowledgement ($out, sent $(sent tR5))"
# P4 a footer below the prompt still marks a running turn.
R6=$(wt R-6); Y add R-6 "path=$R6" terminal=tR6; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/R-6.log"; : > "$TMP/orca-calls"
screen tR6 "⏺ Bash(npm test)" "" "────────────────────────────" "❯ " "────────────────────────────" "  ⏵⏵ bypass permissions on · esc to interrupt"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-6)" ] && [ "$(sent tR6)" = 0 ] && pass "P4 esc to interrupt in the footer is a running turn" || fail "P4 footer"
# P5 a spinner above a todo list is not idle.
R7=$(wt R-7); Y add R-7 "path=$R7" terminal=tR7; printf '%s phase5 executing\n' "$(stamp "$NOW")" > "$P/R-7.log"; : > "$TMP/orca-calls"
screen tR7 "✻ Waiting… (40m · esc to interrupt)" "  ⎿  ☐ run codex" "     ☐ review" "     ☐ verify" "     ☐ open PR" "" "────────────────────────────" "❯ " "────────────────────────────" "  ⏵⏵ bypass permissions on (shift+tab to cycle)"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-7)" ] && [ "$(sent tR7)" = 0 ] && pass "P5 a spinner above a todo list is a running turn" || fail "P5 spinner above todo list"
# P6 a dialog above an empty ruled prompt is not idle.
R8=$(wt R-8); Y add R-8 "path=$R8" terminal=tR8; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/R-8.log"; : > "$TMP/orca-calls"
screen tR8 "Do you want to proceed?" "❯ 1. Yes" "  2. No" "────────────────────────────" "❯ " "────────────────────────────"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-8)" ] && [ "$(sent tR8)" = 0 ] && pass "P6 a dialog next to an empty prompt is not idle" || fail "P6 dialog guard"
# P7 a changed file inside an untracked directory is activity.
R9=$(wt R-9); Y add R-9 "path=$R9" terminal=tR9; printf '%s phase5 executing\n' "$(stamp "$NOW")" > "$P/R-9.log"; idle tR9; : > "$TMP/orca-calls"
mkdir -p "$R9/newmod"; echo x > "$R9/newmod/a.ts"; tt "$R9/newmod/a.ts" $((NOW + 7140)); tt "$R9/newmod" "$NOW"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-9)" ] && [ "$(sent tR9)" = 0 ] && pass "P7 an edit inside a new folder is activity" || fail "P7 untracked folder"
# P8 a failed send changes nothing and the next tick retries.
R10=$(wt R-10); Y add R-10 "path=$R10" terminal=tR10; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/R-10.log"; idle tR10; touch "$TMP/sendfail-tR10"
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-10)
case "$out" in 'unknown R-10 send failed: '*) [ "$(fld R-10 idleResumed)" = - ] && [ "$(wc -l < "$P/R-10.log" | tr -d ' ')" = 1 ] && pass "P8a a failed idle send records nothing" || fail "P8a state ($out)" ;; *) fail "P8a send reason ($out)" ;; esac
rm "$TMP/sendfail-tR10"; [ "$(YUKI_NOW=$((NOW + 7260)) Y unblock R-10)" = 'resumed R-10 idle 2h01m phase4' ] && pass "P8b the next tick retries" || fail "P8b"
Y config unblock '"merge"'
R11=$(wt R-11); Y add R-11 "path=$R11" terminal=tR11; printf '%s phase6 verifying\n%s parked out of tries: gate\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/R-11.log"; Y sweep >/dev/null; idle tR11; touch "$TMP/sendfail-tR11"
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-11)
case "$out" in 'unknown R-11 send failed: '*) [ "$(st R-11)" = parked ] && [ "$(fld R-11 unblocked)" = - ] && pass "P8c a failed unblock send does not spend its one unblock" || fail "P8c state ($out)" ;; *) fail "P8c send reason ($out)" ;; esac
rm "$TMP/sendfail-tR11"; [ "$(YUKI_NOW=$((NOW + 7260)) Y unblock R-11)" = 'unblocking R-11 -' ] && pass "P8d the unblock is retried" || fail "P8d"
R22=$(wt R-22); Y add R-22 "path=$R22" terminal=tR22; : > "$R22/p.md"; printf '%s parked out of tries: gate plan=p.md\n' "$(stamp "$NOW")" > "$P/R-22.log"; Y sweep >/dev/null; idle tR22; touch "$TMP/sendfail-tR22"
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-22)
case "$out" in 'unknown R-22 send failed: '*) [ "$(st R-22)" = parked ] && [ "$(fld R-22 planResumed)" = - ] && [ "$(fld R-22 plan)" = p.md ] && pass "P8e a failed plan send keeps the plan unused" || fail "P8e state ($out)" ;; *) fail "P8e send reason ($out)" ;; esac
rm "$TMP/sendfail-tR22"; [ "$(YUKI_NOW=$((NOW + 7260)) Y unblock R-22)" = 'resumed R-22 plan p.md' ] && pass "P8f the plan is retried" || fail "P8f"
# P9 a busy screen or a dialog holds the unblock without spending it.
R12=$(wt R-12); Y add R-12 "path=$R12" terminal=tR12; printf '%s phase6 verifying\n%s parked out of tries: gate\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/R-12.log"; Y sweep >/dev/null; : > "$TMP/orca-calls"
screen tR12 "✻ Working… (12s · esc to interrupt)" "────────────────────────────" "❯ " "────────────────────────────"
a=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-12); screen tR12 "Do you want to proceed?" "❯ 1. Yes" "  2. No"; b=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-12); idle tR12; c=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-12)
[ -z "$a$b" ] && [ "$c" = 'unblocking R-12 -' ] && [ "$(sent tR12)" = 1 ] && pass "P9 busy and dialog screens hold the unblock until idle" || fail "P9 ($a|$b|$c)"
# P10 a PR in the log makes the row eligible.
R13=$(wt R-13); Y add R-13 "path=$R13" terminal=tR13; printf '%s phase5 executing\n%s pr https://github.com/o/r/pull/813\n%s parked out of tries: ci\n' "$(stamp "$NOW")" "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/R-13.log"; Y sweep >/dev/null; idle tR13
[ "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-13)" = 'unblocking R-13 https://github.com/o/r/pull/813' ] && pass "P10 a pr line in the log makes the row eligible" || fail "P10"
# P11 phase 5 without a PR is ineligible.
R14=$(wt R-14); Y add R-14 "path=$R14" terminal=tR14; printf '%s phase5 executing\n%s parked out of tries: ci\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/R-14.log"; Y sweep >/dev/null; idle tR14
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-14)" ] && pass "P11 phase5 without a PR is ineligible" || fail "P11"
# P12 a missing plan is dropped and a later tick can unblock.
R15=$(wt R-15); Y add R-15 "path=$R15" terminal=tR15; printf '%s phase6 verifying\n%s parked out of tries: gate plan=gone.md\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/R-15.log"; Y sweep >/dev/null; idle tR15
a=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-15); b=$(YUKI_NOW=$((NOW + 7800)) Y unblock R-15)
[ "$a" = 'unknown R-15 no such plan gone.md' ] && [ "$b" = 'unblocking R-15 -' ] && pass "P12 a dropped plan lets the next tick unblock" || fail "P12 ($a|$b)"
# P13 parks outside the out-of-tries allow-list never unblock.
R16=$(wt R-16); Y add R-16 "path=$R16" terminal=tR16 pr=https://github.com/o/r/pull/816; echo CLOSED > "$TMP/pr-816"; printf '%s phase8 reviewing\n' "$(stamp "$NOW")" > "$P/R-16.log"; (YUKI_NOW=$((NOW + 60)) Y sweep >/dev/null 2>&1 || true); idle tR16
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-16)" ] && pass "P13a a PR closed without a merge is not unblocked" || fail "P13a closed PR unblocked"
R17=$(wt R-17); Y add R-17 "path=$R17" terminal=tR17 pr=https://github.com/o/r/pull/817; printf '%s phase8 reviewing\n%s parked changes requested by alice, no push for 72 h\n' "$(stamp "$NOW")" "$(stamp "$NOW")" > "$P/R-17.log"; Y sweep >/dev/null; idle tR17
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-17)" ] && pass "P13b a person's changes request is not merged over" || fail "P13b changes-requested unblocked"
Y add R-26 "path=$TMP/wt/gone-R26" terminal=tR26; printf '%s phase8 reviewing\n' "$(stamp "$NOW")" > "$P/R-26.log"; Y sweep >/dev/null; idle tR26
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-26)" ] && [ "$(sent tR26)" = 0 ] && pass "P13c a worktree-gone park is not unblocked" || fail "P13c worktree gone"
R27=$(wt R-27); Y add R-27 "path=$R27" terminal=tR27; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/R-27.log"; idle tR27; : > "$TMP/orca-calls"
[ "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-27)" = 'resumed R-27 idle 2h00m phase4' ] && pass "P13d an idle worker gets its resume" || fail "P13d first resume"
a=$(YUKI_NOW=$((NOW + 9100)) Y unblock R-27); b=$(YUKI_NOW=$((NOW + 9100)) Y unblock R-27)
[ "$a" = 'parked R-27 idle after a resume' ] && [ -z "$(echo "$b" | grep '^unblocking R-27 ')" ] && [ "$(sent tR27)" = 1 ] && pass "P13d an idle-after-resume park is not unblocked" || fail "P13d repeated stall ($a|$b)"
# P14 a plan resume itself counts as the first resume.
R18=$(wt R-18); Y add R-18 "path=$R18" terminal=tR18; : > "$R18/p.md"; printf '%s parked out of tries: gate plan=p.md\n' "$(stamp "$NOW")" > "$P/R-18.log"; Y sweep >/dev/null; idle tR18; : > "$TMP/orca-calls"
a=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-18); b=$(YUKI_NOW=$((NOW + 9100)) Y unblock R-18)
[ "$a" = 'resumed R-18 plan p.md' ] && [ "$b" = 'parked R-18 idle after a resume' ] && [ "$(sent tR18)" = 1 ] && pass "P14 a plan resume counts as the first resume" || fail "P14 ($a|$b)"
# P15 idleMinutes is honored, and a nudge is not activity.
R19=$(wt R-19); Y add R-19 "path=$R19" terminal=tR19; printf '%s phase4 executing\n' "$(stamp "$NOW")" > "$P/R-19.log"; idle tR19; Y config idleMinutes 60
a=$(YUKI_NOW=$((NOW + 2700)) Y unblock R-19); b=$(YUKI_NOW=$((NOW + 3660)) Y unblock R-19); Y config idleMinutes 30
[ -z "$a" ] && [ "$b" = 'resumed R-19 idle 1h01m phase4' ] && pass "P15a idleMinutes sets the idle time" || fail "P15a ($a|$b)"
R20=$(wt R-20); Y add R-20 "path=$R20" terminal=tR20; printf '%s phase4 executing\n%s nudged permission: ls\n' "$(stamp "$NOW")" "$(stamp $((NOW + 7100)))" > "$P/R-20.log"; idle tR20
[ "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-20)" = 'resumed R-20 idle 2h00m phase4' ] && pass "P15b a nudged line is not activity" || fail "P15b"
# P16 plan and unblock resume lines are logged.
grep -q ' resumed plan docs/superpowers/plans/fix.md$' "$P/V-20.log" && grep -q ' resumed unblock$' "$P/V-30.log" && pass "P16 plan and unblock resumes are logged" || fail "P16"
# P18 idleMinutes accepts its endpoints and refuses a boolean.
Y config idleMinutes 5 && Y config idleMinutes 1440 && [ "$(Y config idleMinutes)" = 1440 ] && ! Y config idleMinutes true 2>/dev/null && Y config idleMinutes 30 && pass "P18 idleMinutes accepts 5 and 1440, refuses true" || fail "P18"
# A bad git path fails closed with a reason and no send.
mkdir -p "$TMP/not-a-worktree"; Y add R-23 "path=$TMP/not-a-worktree" terminal=tR23; idle tR23; : > "$TMP/orca-calls"
out=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-23)
case "$out" in 'unknown R-23 git failed: '*) [ "$(sent tR23)" = 0 ] && pass "a git failure is reported without sending" || fail "git failure sent a prompt" ;; *) fail "git failure reason ($out)" ;; esac
# A missing worktree keeps its parked plan.
Y add R-24 "path=$TMP/wt/gone-R24" terminal=tR24; Y set R-24 state=parked note=out-of-tries >/dev/null
python3 - "$H/items.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
r = next(x for x in d["items"] if x["item"] == "R-24")
r["plan"] = "p.md"
json.dump(d, open(p, "w"))
PY
idle tR24; : > "$TMP/orca-calls"; out=$(YUKI_NOW=$((NOW + 7200)) Y unblock R-24)
[ "$out" = 'unknown R-24 worktree gone' ] && [ "$(fld R-24 plan)" = p.md ] && [ "$(sent tR24)" = 0 ] && pass "a parked plan with no worktree is kept" || fail "missing plan worktree ($out)"
# A parked plan waits for the same idle interval as a running row.
R25=$(wt R-25); Y add R-25 "path=$R25" terminal=tR25; : > "$R25/p.md"; printf '%s parked out of tries: gate plan=p.md\n' "$(stamp "$NOW")" > "$P/R-25.log"; Y sweep >/dev/null
(cd "$R25" && GIT_COMMITTER_DATE="@$((NOW + 7140)) +0000" git commit -q --allow-empty -m recent)
idle tR25; : > "$TMP/orca-calls"
[ -z "$(YUKI_NOW=$((NOW + 7200)) Y unblock R-25)" ] && [ "$(sent tR25)" = 0 ] && pass "a parked plan with recent work waits" || fail "parked plan idle interval"

echo "---"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
