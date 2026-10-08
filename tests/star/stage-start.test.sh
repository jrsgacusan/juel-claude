#!/bin/sh
# Runs skills/star/stage-start.sh against a scratch repo, a real ledger and a stub orca.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
S="$ROOT/skills/star"
SCRIPT="$S/stage-start.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL stage-start.sh missing"; exit 1; }

# the project: a repo with an ignored .env, its STAR folder, two rows and their briefs
APP="$TMP/app"; mkdir -p "$APP"
(cd "$APP" && git init -q -b main . && printf '.env\n' > .gitignore && git add .gitignore && git commit -q -m init)
APP=$(cd "$APP" && pwd -P)
printf 'TOKEN=1\n' > "$APP/.env"
H=$(sh "$S/star-home.sh" --cwd "$APP" init)
python3 - "$H/star.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["project"]["orcaRepo"] = "repo_1"; json.dump(d, open(p, "w"), indent=2)
PY
L() { sh "$S/ledger.sh" --home "$H" "$@"; }
brief() {
  mkdir -p "$H/briefs/app"
  printf -- '---\njuel_brief: 1\nbranch: feat/%s-x\nbaseBranch: main\ndeliverable: pr\n---\n## Work item\nx\n' "$(echo "$1" | tr 'A-Z' 'a-z')" > "$H/briefs/app/$1.md"
}
L add SPH-11 ref=SPH-11 project=app >/dev/null; brief SPH-11
mkdir -p "$TMP/cfg"
trust() { python3 -c 'import json,sys; print(json.dumps({"projects": {p: {"hasTrustDialogAccepted": True} for p in sys.argv[1:]}}))' "$@" > "$TMP/cfg/.claude.json"; }
trust "$APP"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/orca" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/calls"
case "$1 $2" in
  "orchestration task-create")
    [ -f "$STUB_DIR/task-fail" ] && { echo '{"ok":false,"error":{"message":"task store down"}}'; exit 1; }
    # Orca 1.4.198 echoes text back with a raw line break inside a JSON string
    printf '{"ok":true,"result":{"task":{"id":"task_aa11","spec":"line one\nline two"}}}\n' ;;
  "orchestration worker-start")
    n=$(cat "$STUB_DIR/ws" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_DIR/ws"
    if [ -f "$STUB_DIR/ws-fail-$n" ]; then cat "$STUB_DIR/ws-fail-$n"; exit 1; fi
    printf '{"ok":true,"result":{"dispatch":{"id":"ctx_bb%s","status":"ready"}}}\n' "$n" ;;
  "worktree create")
    name=$(printf '%s' "$*" | sed -n 's/.*--name \([^ ]*\).*/\1/p')
    wt="$STUB_REPO/.worktrees/app/$name"
    git -C "$STUB_REPO" worktree add -q -b "orca/$name" "$wt" >/dev/null 2>&1
    printf '{"ok":true,"result":{"worktree":{"path":"%s"}}}\n' "$wt" ;;
  "terminal create") echo '{"ok":true,"result":{"terminal":{"handle":"term_tt1"}}}' ;;
  "terminal read")
    n=$(cat "$STUB_DIR/tr" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_DIR/tr"
    if [ -f "$STUB_DIR/dialog-always" ] || [ "$n" -le "$(cat "$STUB_DIR/dialog-reads" 2>/dev/null || echo 0)" ]; then
      echo '{"ok":true,"result":{"screen":"Do you trust the files in this folder?  1. Yes, proceed  2. No, exit"}}'
    else echo '{"ok":true,"result":{"screen":"> ready"}}'; fi ;;
  "terminal send"|"terminal close") echo '{"ok":true}' ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$TMP/bin/orca"
reset() { rm -f "$TMP/calls" "$TMP/ws" "$TMP"/ws-fail-* "$TMP/tr" "$TMP/dialog-always" "$TMP/dialog-reads" "$TMP/task-fail"; }
ST() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_REPO="$APP" ORCA_CLI_COMMAND=orca STAR_FREE_GB=${FREE:-16} \
       STAR_TRUST_POLL=0.01 CLAUDE_CONFIG_DIR="$TMP/cfg" sh "$SCRIPT" --home "$H" "$@"; }

# brief: in the main checkout, ids recorded, one-line spec, request ids
reset
out=$(ST brief SPH-11)
[ "$out" = "started task=task_aa11 dispatch=ctx_bb1" ] && pass "brief starts (task id read through a raw newline)" || fail "brief ($out)"
[ "$(L get SPH-11 state)" = "briefing" ] && [ "$(L get SPH-11 task)" = "task_aa11" ] && [ "$(L get SPH-11 dispatch)" = "ctx_bb1" ] && pass "the row is written" || fail "row ($(L get SPH-11))"
[ "$(L get SPH-11 counters.start)" = "1" ] && [ "$(L get SPH-11 counters.live)" = "-" ] && pass "start=1, live cleared" || fail "counters ($(L get SPH-11 counters))"
grep -q "task-create --spec /juel:star draft-brief SPH-11 --project app --item SPH-11 --out $H/briefs/app/SPH-11.md --task-title" "$TMP/calls" && pass "the brief prompt, on one line" || fail "brief prompt ($(cat "$TMP/calls"))"
grep -q -- '--retry-request star-SPH-11-brief-r0-s1 ' "$TMP/calls" && grep -q -- "worker-start --task task_aa11 --worktree path:$APP .*--retry-request star-SPH-11-brief-r0-s1-w1" "$TMP/calls" && pass "request ids on both calls" || fail "request ids"
grep -q 'terminal create' "$TMP/calls" && fail "a trusted path opened a trust terminal" || pass "a trusted path needs no trust terminal"

# memory
reset; out=$(FREE=1 ST brief SPH-11); [ "$out" = "hold memory 1" ] && [ ! -f "$TMP/calls" ] && pass "low memory holds and calls nothing" || fail "memory ($out)"

# build: worktree created inside the repo, put on the brief's branch, env copied, excluded, trust cleared
reset; L set SPH-11 state=queued >/dev/null
out=$(ST build SPH-11)
WT="$APP/.worktrees/app/SPH-11"
case "$out" in "started task=task_aa11 dispatch=ctx_bb1") pass "build starts" ;; *) fail "build ($out)" ;; esac
[ "$(L get SPH-11 worktree)" = "$WT" ] && pass "the worktree is recorded" || fail "worktree cell ($(L get SPH-11 worktree))"
[ "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" = "feat/sph-11-x" ] && pass "on the brief's branch" || fail "branch"
[ -f "$WT/.env" ] && pass "the ignored .env is copied" || fail ".env"
grep -qx '/.worktrees/' "$APP/.git/info/exclude" && [ -z "$(git -C "$APP" status --porcelain)" ] && pass "the main checkout stays clean (#9)" || fail "exclude ($(git -C "$APP" status --porcelain))"
grep -q "terminal create --worktree path:$WT" "$TMP/calls" && grep -q 'terminal close --terminal term_tt1' "$TMP/calls" && pass "an untrusted worktree gets a trust terminal, then it closes" || fail "trust terminal"
grep -q 'terminal send' "$TMP/calls" && fail "keys were sent with no dialog on screen" || pass "no keys without a dialog"

# a dialog on screen is cleared with Down then Enter
reset; L add SPH-12 ref=SPH-12 project=app state=queued >/dev/null; brief SPH-12; echo 1 > "$TMP/dialog-reads"
out=$(ST build SPH-12)
case "$out" in "started "*) pass "a dialog is cleared and the build starts" ;; *) fail "dialog cleared ($out)" ;; esac
grep -q 'terminal send --terminal term_tt1 --enter' "$TMP/calls" && pass "Enter was sent after the dialog" || fail "enter"

# a dialog that never goes away is a hold, and nothing is started
reset; L add SPH-13 ref=SPH-13 project=app state=queued >/dev/null; brief SPH-13; touch "$TMP/dialog-always"
out=$(ST build SPH-13)
[ "$out" = "hold trust $APP/.worktrees/app/SPH-13" ] && ! grep -q task-create "$TMP/calls" && pass "a stuck dialog holds" || fail "stuck dialog ($out)"
[ "$(grep -c 'terminal send --terminal term_tt1 --enter' "$TMP/calls")" -le 3 ] && pass "at most 3 rounds of keys" || fail "rounds"

# review: codex, the prompt in a file, round 1
reset; L set SPH-11 state=pr-draft >/dev/null
out=$(ST review SPH-11)
SPEC="$H/specs/app/SPH-11-review-r1.md"
case "$out" in "started "*) pass "review starts" ;; *) fail "review ($out)" ;; esac
[ -f "$SPEC" ] && grep -q 'VERDICT item=SPH-11 round=1 SAFE' "$SPEC" && grep -q "Brief (the approved contract): $H/briefs/app/SPH-11.md" "$SPEC" && pass "the reviewer prompt is filled in" || fail "spec file"
grep -q "task-create --spec You are STAR's second-model reviewer for SPH-11. Read $SPEC and do exactly what it says. --task-title" "$TMP/calls" && pass "the review spec is one line" || fail "review spec line"
grep -q 'worker-start .*--agent codex --model gpt-6-astra --effort xhigh' "$TMP/calls" && pass "review runs on stages.review" || fail "review agent"
[ "$(L get SPH-11 round)" = "1" ] && pass "review round is row round + 1" || fail "round"

# Review Focus 4: a start that died before recording its task replays the same ids
reset; L set SPH-11 counters.start=4 counters.live=4 task=- dispatch=- >/dev/null
ST review SPH-11 >/dev/null
grep -q -- '--retry-request star-SPH-11-review-r1-s4 ' "$TMP/calls" && pass "a replay reuses the request id" || fail "replay id ($(cat "$TMP/calls"))"
reset; ST --round 1 review SPH-11 >/dev/null
grep -q -- '--retry-request star-SPH-11-review-r1-s5 ' "$TMP/calls" && pass "a deliberate re-run gets a new one" || fail "rerun id"

# worker-start: one retry with --retry-of; a refused effort steps down; a refused model falls back
reset; printf '{"ok":false,"result":{"dispatch":{"id":"ctx_dead1"}},"error":{"message":"setup failed"}}\n' > "$TMP/ws-fail-1"
out=$(ST --round 1 review SPH-11)
case "$out" in "started task=task_aa11 dispatch=ctx_bb2") pass "a failed start is retried once" ;; *) fail "retry ($out)" ;; esac
grep -q -- '--retry-of ctx_dead1 --retry-request star-SPH-11-review-r1-s6-w2' "$TMP/calls" && pass "the retry links the failed dispatch" || fail "retry-of"
reset; printf '{"ok":false,"error":{"message":"effort xhigh is not supported by this model"}}\n' > "$TMP/ws-fail-1"
ST --round 1 review SPH-11 >/dev/null; sed -n '$p' "$TMP/calls" | grep -q -- '--effort high' && pass "a refused effort steps down one level" || fail "effort"
python3 - "$H/star.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["stages"]["fix"]["model"] = "fable"; json.dump(d, open(p, "w"), indent=2)
PY
reset; L set SPH-11 state=fix-queued >/dev/null; trust "$APP" "$WT"
printf '{"ok":false,"error":{"message":"model fable is not available to this account"}}\n' > "$TMP/ws-fail-1"
out=$(ST fix SPH-11)
case "$out" in "started task=task_aa11 dispatch=ctx_bb2 fallback opus: model fable is not available to this account") pass "a refused model falls back to worker" ;; *) fail "fallback ($out)" ;; esac
grep -q -- "--fix-review $H/reviews/app/SPH-11-r1.md --executor session" "$TMP/calls" && pass "the fix prompt names the round's review" || fail "fix prompt"
reset; printf '{"ok":false,"error":{"message":"no"}}\n' > "$TMP/ws-fail-1"; cp "$TMP/ws-fail-1" "$TMP/ws-fail-2"
out=$(ST fix SPH-11); [ "$out" = "failed worker-start: no" ] && [ "$(L get SPH-11 counters.live)" = "-" ] && pass "a second failure is failed, live cleared" || fail "second failure ($out)"

# task-create failing
reset; touch "$TMP/task-fail"
out=$(ST fix SPH-11); [ "$out" = "failed task-create: task store down" ] && pass "a failed task-create is named" || fail "task-create ($out)"

# babysit: the PR number and the cursor
reset; L set SPH-11 state=babysit-queued pr=https://github.com/o/r/pull/42 "cursor=2026-10-07T07:00:00Z#c1" >/dev/null
ST babysit SPH-11 >/dev/null
grep -q "/juel:babysit-pr 42 --unattended --mark-ready --reviewed $H/reviews/app/SPH-11-r1.md --item SPH-11 --brief $H/briefs/app/SPH-11.md --gates-file $H/gates/app/SPH-11.json --executor session --since 2026-10-07T07:00:00Z#c1" "$TMP/calls" && pass "the babysit prompt" || fail "babysit prompt ($(grep task-create "$TMP/calls"))"

# one row per worktree
reset; L set SPH-12 "worktree=$WT" state=fix-queued >/dev/null
out=$(ST fix SPH-12); case "$out" in "failed in-use: $WT is already in use by SPH-11") pass "a worktree in another open row is refused" ;; *) fail "in-use ($out)" ;; esac

# a launch failure that names a model, on a stage whose setting only adds an executor, is an ordinary retry
L set SPH-12 "worktree=$APP/.worktrees/app/SPH-12" >/dev/null
reset; printf '{"ok":false,"result":{"dispatch":{"id":"ctx_dead2"}},"error":{"message":"model access check failed"}}\n' > "$TMP/ws-fail-1"
out=$(ST babysit SPH-11)
case "$out" in *fallback*) fail "the same model reported as a fallback ($out)" ;; "started "*) pass "no fallback when the fallback is the same model" ;; *) fail "babysit retry ($out)" ;; esac
grep -q -- '--retry-of ctx_dead2' "$TMP/calls" && pass "it retries with --retry-of instead" || fail "no --retry-of on the plain retry"

# the main checkout on the brief's branch is never reused as a build worktree
reset; L add SPH-20 ref=SPH-20 project=app state=queued >/dev/null; brief SPH-20
git -C "$APP" switch -q -c feat/sph-20-x
out=$(ST build SPH-20)
case "$out" in "failed branch: "*) pass "a brief branch checked out in the main checkout is not built there" ;; *) fail "main checkout reused ($out)" ;; esac
[ "$(L get SPH-20 worktree)" != "$APP" ] && pass "the main checkout is not recorded as the worktree" || fail "worktree cell is the main checkout"
git -C "$APP" switch -q main

# a trust hold after the row is written puts the row back and keeps the start replayable
WT21="$APP/.worktrees/app/SPH-21"; git -C "$APP" worktree add -q -b feat/sph-21-x "$WT21" >/dev/null 2>&1
L add SPH-21 ref=SPH-21 project=app state=pr-draft "worktree=$WT21" >/dev/null; brief SPH-21
python3 - "$H/star.json" <<'PY2'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["reviewer"] = {"agent": "claude", "model": "opus", "effort": "xhigh"}; json.dump(d, open(p, "w"), indent=2)
PY2
reset; touch "$TMP/dialog-always"; printf '{"ok":false,"error":{"message":"model gpt-6-astra is not available to this account"}}\n' > "$TMP/ws-fail-1"
out=$(ST review SPH-21)
[ "$out" = "hold trust $WT21" ] && pass "a refused codex review falls back to claude and holds on trust" || fail "late hold ($out)"
[ "$(L get SPH-21 state)" = "pr-draft" ] && pass "the row goes back to its waiting state" || fail "row left running ($(L get SPH-21 state))"
[ "$(L get SPH-21 task)" = "task_aa11" ] && [ "$(L get SPH-21 counters.live)" != "-" ] && pass "the task and live= are kept for the replay" || fail "replay state lost ($(L get SPH-21))"
reset; trust "$APP" "$WT" "$WT21"
out=$(ST review SPH-21)
case "$out" in "started task=task_aa11 "*) ! grep -q task-create "$TMP/calls" && pass "the next start reuses the task instead of making a second" || fail "a second task was created" ;; *) fail "replay after hold ($out)" ;; esac

# an existing PR's branch is fetched and tracked, never renamed from Orca's (#33)
git init -q --bare "$TMP/remote.git"
git -C "$APP" remote add origin "$TMP/remote.git"
git -C "$APP" push -q origin main
git -C "$APP" switch -q -c feat/sph-30-existing
git -C "$APP" commit -q --allow-empty -m "the PR's own work"
git -C "$APP" push -q origin feat/sph-30-existing
PRHEAD=$(git -C "$APP" rev-parse HEAD)
git -C "$APP" switch -q main; git -C "$APP" branch -q -D feat/sph-30-existing
git -C "$APP" update-ref -d refs/remotes/origin/feat/sph-30-existing
L add SPH-30 ref=SPH-30 project=app state=queued >/dev/null
printf -- '---\njuel_brief: 1\nbranch: feat/sph-30-existing\nbaseBranch: main\nexistingPr: https://github.com/o/r/pull/30\ndeliverable: pr\n---\n## Work item\nx\n' > "$H/briefs/app/SPH-30.md"
WT30="$APP/.worktrees/app/SPH-30"
reset; trust "$APP" "$WT30"
out=$(ST build SPH-30)
case "$out" in "started "*) pass "an existing PR's item starts" ;; *) fail "existing PR start ($out)" ;; esac
[ "$(git -C "$WT30" rev-parse --abbrev-ref HEAD)" = "feat/sph-30-existing" ] && pass "the worktree is on the PR's branch" || fail "branch ($(git -C "$WT30" rev-parse --abbrev-ref HEAD))"
[ "$(git -C "$WT30" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" = "origin/feat/sph-30-existing" ] && pass "it tracks the remote branch" || fail "upstream"
[ "$(git -C "$WT30" rev-parse HEAD)" = "$PRHEAD" ] && pass "it starts at the PR's head" || fail "head"
git -C "$APP" show-ref --verify --quiet refs/heads/orca/SPH-30 && fail "Orca's branch was left behind" || pass "Orca's own branch is deleted"

# usage and unknown items
ST nope SPH-11 >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown stage is 64" || fail "usage"
ST brief NOPE-1 >/dev/null 2>&1; [ $? -eq 4 ] && pass "an unknown item is 4" || fail "unknown item"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
