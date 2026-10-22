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
# the gate lock is a scratch file: a test never reads or signals the machine's real one
export JUEL_GATE_LOCK="$TMP/gate.lock"

# the project: a repo with an ignored .env, its STAR folder with schema 2 settings, rows and briefs
APP="$TMP/app"; mkdir -p "$APP"
(cd "$APP" && git init -q -b main . && printf '.env\n' > .gitignore && git add .gitignore && git commit -q -m init)
APP=$(cd "$APP" && pwd -P)
printf 'TOKEN=1\n' > "$APP/.env"
H=$(HOME="$TMP/home" sh "$S/star-home.sh" --cwd "$APP" init)
settings() { python3 - "$H/star.json" "$@" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["project"]["orcaRepo"] = "repo_1"
d["stages"] = {k: {"agent": "claude", "model": "opus", "effort": "high" if k == "brief" else "xhigh"}
               for k in ("brief", "build", "babysit", "post")}
d["worker"] = {"agent": "claude", "model": "opus", "effort": "xhigh"}
d.pop("reviewer", None)
d["hostGate"] = {"minFreeGB": 3, "maxAgents": 40, "maxSwapGB": 11, "minDiskGB": 25}
d["away"] = None
for kv in sys.argv[2:]:
    path, value = kv.split("=", 1)
    node, keys = d, path.split(".")
    for k in keys[:-1]:
        node = node.setdefault(k, {})
    node[keys[-1]] = json.loads(value)
json.dump(d, open(p, "w"), indent=2)
PY
}
settings
L() { sh "$S/ledger.sh" --home "$H" "$@"; }
brief() {
  mkdir -p "$H/briefs/app"
  printf -- '---\njuel_brief: 1\nbranch: feat/%s-x\nbaseBranch: main\ndeliverable: pr\n---\n## Work item\nx\n' "$(echo "$1" | tr 'A-Z' 'a-z')" > "$H/briefs/app/$1.md"
}
review() { mkdir -p "$H/reviews/app"; printf 'VERDICT item=%s round=%s SAFE findings=0 head=abc1234\n' "$1" "$2" > "$H/reviews/app/$1-r$2.md"; }
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
    # a previous session's rendered screen (#119), as Orca returns it: screen-<handle>.json
    h=$(printf '%s' "$*" | sed -n 's/.*--terminal \([^ ]*\).*/\1/p')
    if [ -n "$h" ] && [ -f "$STUB_DIR/screen-$h.json" ]; then cat "$STUB_DIR/screen-$h.json"; exit 0; fi
    n=$(cat "$STUB_DIR/tr" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_DIR/tr"
    if [ -f "$STUB_DIR/dialog-always" ] || [ "$n" -le "$(cat "$STUB_DIR/dialog-reads" 2>/dev/null || echo 0)" ]; then
      echo '{"ok":true,"result":{"screen":"Do you trust the files in this folder?  1. Yes, proceed  2. No, exit"}}'
    else echo '{"ok":true,"result":{"screen":"> ready"}}'; fi ;;
  "terminal send") echo '{"ok":true}' ;;
  "terminal close")
    [ -f "$STUB_DIR/close-fail" ] && { echo '{"ok":false,"error":{"message":"terminal is busy"}}'; exit 1; }
    echo '{"ok":true}' ;;
  "orchestration worker-show")
    id=$(printf '%s' "$*" | sed -n 's/.*--dispatch \([^ ]*\).*/\1/p')
    if [ -f "$STUB_DIR/show-$id.json" ]; then cat "$STUB_DIR/show-$id.json"
    else printf '{"ok":true,"result":{"dispatch":{"id":"%s"},"terminal":null,"observation":{"status":"missing","exactWorker":false},"terminalResource":null}}\n' "$id"; fi ;;
  "terminal list")
    case "$*" in
      *--limit*)
        # every terminal Orca lists (#119): list-all.json, else each terminal a worker-show fixture names
        [ -f "$STUB_DIR/list-all-fail" ] && { echo '{"ok":false,"error":{"message":"runtime not reachable"}}'; exit 1; }
        if [ -f "$STUB_DIR/list-all.json" ]; then cat "$STUB_DIR/list-all.json"
        else python3 - "$STUB_DIR" <<'PY'
import glob, json, os, sys
listed = []
for p in sorted(glob.glob(os.path.join(sys.argv[1], "show-*.json"))):
    t = (json.load(open(p)).get("result") or {}).get("terminal")
    if isinstance(t, dict) and t.get("handle"):
        listed.append({"handle": t["handle"], "lastOutputAt": t.get("lastOutputAt")})
print(json.dumps({"ok": True, "result": {"terminals": listed, "totalCount": len(listed), "truncated": False}}))
PY
        fi ;;
      *)
        if [ -f "$STUB_DIR/terminals.json" ]; then cat "$STUB_DIR/terminals.json"
        else echo '{"ok":true,"result":{"terminals":[],"totalCount":0,"truncated":false}}'; fi ;;
    esac ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$TMP/bin/orca"
reset() { rm -f "$TMP/calls" "$TMP/ws" "$TMP"/ws-fail-* "$TMP/tr" "$TMP/dialog-always" "$TMP/dialog-reads" "$TMP/task-fail" \
                "$TMP"/show-*.json "$TMP/terminals.json" "$TMP/close-fail" "$TMP/list-all.json" "$TMP/list-all-fail" \
                "$TMP"/screen-*.json; }
ST() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_REPO="$APP" ORCA_CLI_COMMAND=orca STAR_FREE_GB=${FREE:-16} \
       STAR_AGENTS=${AGENTS:-3} STAR_SWAP_GB=${SWAP:-1} STAR_DISK_GB=${DISK:-500} \
       STAR_TRUST_POLL=0.01 CLAUDE_CONFIG_DIR="$TMP/cfg" sh "$SCRIPT" --home "$H" "$@"; }
# the --retry-request a start sends: the UUID5 of the STAR folder and STAR's readable id (#163)
rq() { python3 -c 'import sys, uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "juel-star:" + sys.argv[1] + "#" + sys.argv[2]))' "$(cd "$H" && pwd)" "$1"; }

# brief: in the main checkout, ids recorded, one-line spec, request ids
reset
out=$(ST brief SPH-11)
[ "$out" = "started task=task_aa11 dispatch=ctx_bb1" ] && pass "brief starts (task id read through a raw newline)" || fail "brief ($out)"
[ "$(L get SPH-11 state)" = "briefing" ] && [ "$(L get SPH-11 task)" = "task_aa11" ] && [ "$(L get SPH-11 dispatch)" = "ctx_bb1" ] && pass "the row is written" || fail "row ($(L get SPH-11))"
[ "$(L get SPH-11 counters.start)" = "1" ] && [ "$(L get SPH-11 counters.live)" = "-" ] && pass "start=1, live cleared" || fail "counters ($(L get SPH-11 counters))"
grep -q "task-create --spec /juel:star draft-brief SPH-11 --project app --item SPH-11 --out $H/briefs/app/SPH-11.md --task-title" "$TMP/calls" && pass "the brief prompt, on one line" || fail "brief prompt ($(cat "$TMP/calls"))"
grep -q -- "--retry-request $(rq star-SPH-11-brief-r0-s1) " "$TMP/calls" && grep -q -- "worker-start --task task_aa11 --worktree path:$APP .*--retry-request $(rq star-SPH-11-brief-r0-s1-w1)" "$TMP/calls" && pass "request ids on both calls" || fail "request ids"
grep -q 'terminal create' "$TMP/calls" && fail "a trusted path opened a trust terminal" || pass "a trusted path needs no trust terminal"

# the host gate: each of its four checks holds, and nothing is called
reset; out=$(FREE=1 ST brief SPH-11); [ "$out" = "hold memory 1" ] && [ ! -f "$TMP/calls" ] && pass "low memory holds" || fail "memory ($out)"
reset; out=$(AGENTS=41 ST brief SPH-11); [ "$out" = "hold agents 41" ] && [ ! -f "$TMP/calls" ] && pass "too many agents hold" || fail "agents ($out)"
reset; out=$(SWAP=12 ST brief SPH-11); [ "$out" = "hold swap 12" ] && [ ! -f "$TMP/calls" ] && pass "too much swap holds" || fail "swap ($out)"
reset; out=$(DISK=10 ST brief SPH-11); [ "$out" = "hold disk 10" ] && [ ! -f "$TMP/calls" ] && pass "too little disk holds" || fail "disk ($out)"
settings 'hostGate.maxAgents=50'
reset; out=$(AGENTS=45 ST brief SPH-11); case "$out" in "started "*) pass "the host gate's limits come from star.json" ;; *) fail "custom limit ($out)" ;; esac
settings

# a re-scope brief names the review that sent it back
reset; L set SPH-11 state=inbox counters.rescope=SPH-11-r3.md >/dev/null
ST brief SPH-11 >/dev/null
grep -q -- "draft-brief SPH-11 --project app --item SPH-11 --out $H/briefs/app/SPH-11.md --rescope $H/reviews/app/SPH-11-r3.md --task-title" "$TMP/calls" && pass "a re-scope brief gets --rescope" || fail "rescope prompt ($(grep task-create "$TMP/calls"))"
L set SPH-11 counters.rescope=- >/dev/null

# Review Focus 4 (v1): a start that died before recording its task replays the same ids
reset; L set SPH-11 stage=brief counters.start=7 counters.live=7 task=- dispatch=- >/dev/null
ST brief SPH-11 >/dev/null
grep -q -- "--retry-request $(rq star-SPH-11-brief-r0-s7) " "$TMP/calls" && pass "a replay reuses the request id" || fail "replay id ($(cat "$TMP/calls"))"
reset; ST brief SPH-11 >/dev/null
grep -q -- "--retry-request $(rq star-SPH-11-brief-r0-s8) " "$TMP/calls" && pass "a new start gets a new one" || fail "new id"

# worker-start: one retry with --retry-of; a refused effort steps down
reset; printf '{"ok":false,"result":{"dispatch":{"id":"ctx_dead1"}},"error":{"message":"setup failed"}}\n' > "$TMP/ws-fail-1"
out=$(ST brief SPH-11)
case "$out" in "started task=task_aa11 dispatch=ctx_bb2") pass "a failed start is retried once" ;; *) fail "retry ($out)" ;; esac
grep -q -- "--retry-of ctx_dead1 --retry-request $(rq star-SPH-11-brief-r0-s9-w2)" "$TMP/calls" && pass "the retry links the failed dispatch" || fail "retry-of"
reset; printf '{"ok":false,"error":{"message":"effort high is not supported by this model"}}\n' > "$TMP/ws-fail-1"
ST brief SPH-11 >/dev/null; sed -n '$p' "$TMP/calls" | grep -q -- '--effort medium' && pass "a refused effort steps down one level" || fail "effort"

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
# a fullscreen launch closed seconds after it starts is a failed fullscreen boot: two of those turn
# fullscreen off for the whole Claude config, and STAR's own session then gets no clicks
grep -q -- '--command CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 claude --dangerously-skip-permissions' "$TMP/calls" && pass "the trust terminal runs Claude on the classic renderer" || fail "trust terminal renderer ($(grep 'terminal create' "$TMP/calls" | head -1))"
grep -q "task-create --spec /juel:ship-ticket --unattended --brief $H/briefs/app/SPH-11.md --task-title" "$TMP/calls" && pass "the build prompt carries no executor flag" || fail "build prompt ($(grep task-create "$TMP/calls"))"

# a dialog on screen is cleared with Down then Enter
reset; L add SPH-12 ref=SPH-12 project=app state=queued >/dev/null; brief SPH-12; echo 1 > "$TMP/dialog-reads"
out=$(ST build SPH-12)
case "$out" in "started "*) pass "a dialog is cleared and the build starts" ;; *) fail "dialog cleared ($out)" ;; esac
grep -q 'terminal send --terminal term_tt1 --enter' "$TMP/calls" && pass "Enter was sent after the dialog" || fail "enter"

# a dialog that never goes away is a hold, and nothing is started
reset; L add SPH-13 ref=SPH-13 project=app state=queued >/dev/null; brief SPH-13; touch "$TMP/dialog-always"
out=$(ST build SPH-13)
[ "$out" = "hold trust $APP/.worktrees/app/SPH-13" ] && ! grep -q task-create "$TMP/calls" && pass "a stuck dialog holds" || fail "stuck dialog ($out)"

# being away adds nothing to the build command: no quiet-hours flag anywhere
trust "$APP" "$WT"
settings 'away="2026-10-09T08:00:00Z"'
reset; L set SPH-11 state=queued >/dev/null
ST build SPH-11 >/dev/null
grep -q task-create "$TMP/calls" && ! grep -q -- '--quiet-hours' "$TMP/calls" && pass "away adds no quiet-hours flag" || fail "away flag ($(grep task-create "$TMP/calls"))"
settings

# babysit: the PR number, the cursor, and the item's newest review as proof
review SPH-11 1; review SPH-11 2
reset; L set SPH-11 state=babysit-queued pr=https://github.com/o/r/pull/42 "cursor=2026-10-07T07:00:00Z#c1" >/dev/null
ST babysit SPH-11 >/dev/null
grep -q "/juel:babysit-pr 42 --unattended --mark-ready --reviewed $H/reviews/app/SPH-11-r2.md --item SPH-11 --brief $H/briefs/app/SPH-11.md --gates-file $H/gates/app/SPH-11.json --since 2026-10-07T07:00:00Z#c1 --task-title" "$TMP/calls" && pass "the babysit prompt proves with the newest review" || fail "babysit prompt ($(grep task-create "$TMP/calls"))"

# a review a v1 reviewer wrote inside the worktree (#35) moves into the STAR folder first
REL=${H#"$APP"/}; WR="$WT/$REL/reviews/app/SPH-11-r3.md"
reset; mkdir -p "$(dirname "$WR")"; echo 'VERDICT item=SPH-11 round=3 SAFE findings=0 head=abc1234' > "$WR"
L set SPH-11 state=babysit-queued >/dev/null; ST babysit SPH-11 >/dev/null
[ -f "$H/reviews/app/SPH-11-r3.md" ] && [ ! -e "$WR" ] && grep -q -- "--reviewed $H/reviews/app/SPH-11-r3.md" "$TMP/calls" && pass "a review left in the worktree moves to the STAR folder and becomes the newest" || fail "review not moved"
reset; echo 'stray' > "$WT/$REL/reviews/app/SPH-11-r2.md"; L set SPH-11 state=babysit-queued >/dev/null; ST babysit SPH-11 >/dev/null
grep -q VERDICT "$H/reviews/app/SPH-11-r2.md" && [ -f "$WT/$REL/reviews/app/SPH-11-r2.md" ] && pass "a review already in the STAR folder is never overwritten" || fail "home review overwritten"
rm -rf "$WT/${REL%%/*}"

# a babysit with no review to prove the gate is refused before anything is written
WT14="$APP/.worktrees/app/SPH-14"; git -C "$APP" worktree add -q -b feat/sph-14-x "$WT14" >/dev/null 2>&1; trust "$APP" "$WT" "$WT14"
L add SPH-14 ref=SPH-14 project=app state=babysit-queued pr=https://github.com/o/r/pull/43 "worktree=$WT14" >/dev/null; brief SPH-14
reset; out=$(ST babysit SPH-14)
[ "$out" = "failed brief: SPH-14 has no review to prove its PR was gated" ] && [ "$(L get SPH-14 state)" = "babysit-queued" ] && pass "no review: refused, row untouched" || fail "no review ($out)"

# one row per worktree
reset; L set SPH-12 "worktree=$WT" state=babysit-queued pr=https://github.com/o/r/pull/44 >/dev/null
out=$(ST babysit SPH-12); case "$out" in "failed in-use: $WT is already in use by SPH-11") pass "a worktree in another open row is refused" ;; *) fail "in-use ($out)" ;; esac

# a refused model falls back to worker; a second failure is failed; task-create failing is named
WT12="$APP/.worktrees/app/SPH-12"; trust "$APP" "$WT" "$WT12" "$WT14"; review SPH-12 1
L set SPH-12 "worktree=$WT12" >/dev/null
settings 'stages.babysit={"agent":"claude","model":"fable","effort":"xhigh"}'
reset; printf '{"ok":false,"error":{"message":"model fable is not available to this account"}}\n' > "$TMP/ws-fail-1"
out=$(ST babysit SPH-12)
case "$out" in "started task=task_aa11 dispatch=ctx_bb2 fallback opus: model fable is not available to this account") pass "a refused model falls back to worker" ;; *) fail "fallback ($out)" ;; esac
settings
reset; printf '{"ok":false,"error":{"message":"no"}}\n' > "$TMP/ws-fail-1"; cp "$TMP/ws-fail-1" "$TMP/ws-fail-2"
out=$(ST babysit SPH-12); [ "$out" = "failed worker-start: no" ] && [ "$(L get SPH-12 counters.live)" = "-" ] && pass "a second failure is failed, live cleared" || fail "second failure ($out)"
reset; touch "$TMP/task-fail"
out=$(ST babysit SPH-12); [ "$out" = "failed task-create: task store down" ] && pass "a failed task-create is named" || fail "task-create ($out)"

# a launch failure that names a model, when the stage is the worker's own setting, is an ordinary retry
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

# #181: parallel build starts in one repository all start, and a rename that collides on git's temp log is retried
reset
for n in 31 32 33; do L add SPH-$n ref=SPH-$n project=app state=queued >/dev/null; brief SPH-$n; done
for n in 31 32 33; do ST build SPH-$n > "$TMP/par-$n.out" 2>&1 & done
wait
ok=1
for n in 31 32 33; do
  case "$(cat "$TMP/par-$n.out")" in "started task="*) ;; *) ok=0; fail "#181 parallel start SPH-$n ($(cat "$TMP/par-$n.out"))" ;; esac
  [ "$(git -C "$APP/.worktrees/app/SPH-$n" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "feat/sph-$n-x" ] || { ok=0; fail "#181 SPH-$n is not on its brief branch"; }
done
[ "$ok" -eq 1 ] && pass "three build starts at once in one repository all start"

REALGIT=$(command -v git)
cat > "$TMP/bin/git" <<EOF
#!/bin/sh
case " \$* " in
  *" branch -m "*)
    if [ ! -f "$TMP/rename-failed" ]; then
      : > "$TMP/rename-failed"
      echo "error: unable to move logfile logs/refs/heads/orca/x to logs/refs/.tmp-renamed-log: File exists" >&2
      exit 128
    fi ;;
esac
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/bin/git"
reset; rm -f "$TMP/rename-failed"; L add SPH-34 ref=SPH-34 project=app state=queued >/dev/null; brief SPH-34
out=$(ST build SPH-34)
case "$out" in "started task="*) [ -f "$TMP/rename-failed" ] && pass "a branch rename that collides on git's temp log is retried once" || fail "#181 the wrapper never failed a rename" ;; *) fail "#181 retry ($out)" ;; esac
rm -f "$TMP/bin/git"

# a trust hold after the row is written puts the row back and keeps the start replayable
WT21="$APP/.worktrees/app/SPH-21"; git -C "$APP" worktree add -q -b feat/sph-21-x "$WT21" >/dev/null 2>&1
L add SPH-21 ref=SPH-21 project=app state=babysit-queued "worktree=$WT21" pr=https://github.com/o/r/pull/21 >/dev/null; brief SPH-21; review SPH-21 1
settings 'stages.babysit={"agent":"codex","model":"gpt-6.1-sol","effort":"xhigh"}'
reset; touch "$TMP/dialog-always"; printf '{"ok":false,"error":{"message":"model gpt-6.1-sol is not available to this account"}}\n' > "$TMP/ws-fail-1"
out=$(ST babysit SPH-21)
[ "$out" = "hold trust $WT21" ] && pass "a refused codex stage falls back to claude and holds on trust" || fail "late hold ($out)"
[ "$(L get SPH-21 state)" = "babysit-queued" ] && pass "the row goes back to its waiting state" || fail "row left running ($(L get SPH-21 state))"
[ "$(L get SPH-21 task)" = "task_aa11" ] && [ "$(L get SPH-21 counters.live)" != "-" ] && pass "the task and live= are kept for the replay" || fail "replay state lost ($(L get SPH-21))"
reset; trust "$APP" "$WT" "$WT12" "$WT14" "$WT21"
out=$(ST babysit SPH-21)
case "$out" in "started task=task_aa11 "*) ! grep -q task-create "$TMP/calls" && pass "the next start reuses the task instead of making a second" || fail "a second task was created" ;; *) fail "replay after hold ($out)" ;; esac
settings

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

# a brief's notBefore holds its build until that time (#87)
nb() { # nb <item> <notBefore value>: a queued row whose brief has that notBefore
  L add "$1" ref="$1" project=app state=queued >/dev/null 2>&1 || L set "$1" state=queued >/dev/null
  mkdir -p "$H/briefs/app"
  printf -- '---\njuel_brief: 1\nbranch: feat/%s-x\nbaseBranch: main\ndeliverable: pr\nnotBefore: %s\n---\n## Work item\nx\n' "$(echo "$1" | tr 'A-Z' 'a-z')" "$2" > "$H/briefs/app/$1.md"
}
reset; nb SPH-60 2099-01-01
out=$(ST build SPH-60)
case "$out" in "wait until 2099-01-01T00:00:00"*) pass "a date still ahead holds the build" ;; *) fail "notBefore ahead ($out)" ;; esac
[ ! -f "$TMP/calls" ] && [ "$(L get SPH-60 state)" = "queued" ] && pass "nothing is created or written while it waits" || fail "notBefore wrote ($(cat "$TMP/calls" 2>/dev/null))"
settings
reset; out=$(export TZ=Asia/Manila; ST build SPH-60)
[ "$out" = "wait until 2099-01-01T00:00:00+08:00" ] && ! grep -q quietHours "$H/star.json" && pass "a date alone is midnight in the machine's local zone" || fail "zone ($out)"
reset; nb SPH-60 2099-01-01T09:00:00Z; out=$(ST build SPH-60)
[ "$out" = "wait until 2099-01-01T09:00:00+00:00" ] && pass "an ISO time with Z is read as UTC" || fail "iso Z ($out)"
reset; nb SPH-60 2099-01-01T09:00:00; out=$(ST build SPH-60)
case "$out" in "failed brief: notBefore 2099-01-01T09:00:00 is not a date"*) pass "a time with no offset is refused, not guessed" ;; *) fail "naive time ($out)" ;; esac
reset; nb SPH-60 "next week"; out=$(ST build SPH-60)
case "$out" in "failed brief: notBefore next week is not a date"*) pass "words are refused" ;; *) fail "words ($out)" ;; esac
reset; nb SPH-60 2000-01-01; out=$(ST build SPH-60)
case "$out" in "started "*) pass "a date already past starts the build" ;; *) fail "past date ($out)" ;; esac
# the babysit proof is the newest round's carried file when the owner carried that round (#82)
reset; printf 'CARRIED item=SPH-11 round=3 head=%s from=SPH-11-r3.md decision=N-7\nship it\nDeferred: the findings in SPH-11-r3.md\n' abc1234abc1234abc1234abc1234abc1234abc12 > "$H/reviews/app/SPH-11-r3-carried.md"
L set SPH-11 state=babysit-queued >/dev/null; ST babysit SPH-11 >/dev/null
grep -q -- "--reviewed $H/reviews/app/SPH-11-r3-carried.md --item SPH-11" "$TMP/calls" && pass "a carried newest round is the proof" || fail "carried proof ($(grep task-create "$TMP/calls"))"
reset; review SPH-11 4; L set SPH-11 state=babysit-queued >/dev/null; ST babysit SPH-11 >/dev/null
grep -q -- "--reviewed $H/reviews/app/SPH-11-r4.md --item SPH-11" "$TMP/calls" && pass "a carry of an older round never stands for a newer one" || fail "older carry ($(grep task-create "$TMP/calls"))"
# a previous session must be gone, or provably idle, before a stage starts (#76)
ms_ago() { python3 -c 'import sys, time; print(int((time.time() - float(sys.argv[1]) * 60) * 1000))' "$1"; }
show() { # show <dispatch> <handle> <ownershipState> <retainedReason or -> <exactWorker> [<minutes since it wrote>] [<worktree>] [<releaseState>] [<dispatch status>]
  reason=null; [ "$4" = - ] || reason="\"$4\""
  printf '{"ok":true,"result":{"dispatch":{"id":"%s","status":"%s"},"terminal":{"handle":"%s","connected":true,"agentIdentity":"claude","lastOutputAt":%s,"worktreePath":"%s"},"observation":{"status":"live","exactWorker":%s},"terminalResource":{"ownershipState":"%s","releaseState":"%s","retainedReason":%s,"ownerDispatchId":"%s","terminalHandle":"%s"}}}\n' \
    "$1" "${9:-dispatched}" "$2" "$(ms_ago "${6:-0}")" "${7:-$APP}" "$5" "$3" "${8:-not_requested}" "$reason" "$1" "$2" > "$TMP/show-$1.json"
}
line() { printf '%s\n' "$1" | sed -n "${2}p"; }
L add SPH-40 ref=SPH-40 project=app state=inbox dispatch=ctx_old40 >/dev/null
reset; show ctx_old40 term_old40 owned - true
out=$(ST brief SPH-40)
[ "$(line "$out" 1)" = "ended previous session term_old40" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && pass "the dispatch's own terminal is closed, then the stage starts" || fail "owned session ($out)"
grep -q 'orchestration worker-show --dispatch ctx_old40 --json' "$TMP/calls" && grep -q 'terminal close --terminal term_old40' "$TMP/calls" && pass "it asks Orca, then closes that terminal" || fail "owned session calls ($(cat "$TMP/calls"))"
# Review Focus 4: a terminal a person took over is never closed; working, it holds the start
reset; L set SPH-40 state=inbox dispatch=ctx_old41 >/dev/null; show ctx_old41 term_old41 user_owned user_takeover false 1
out=$(ST brief SPH-40)
[ "$out" = "hold session term_old41 (user_takeover)" ] && pass "a taken-over terminal that just wrote holds the start" || fail "active takeover ($out)"
! grep -q 'terminal close' "$TMP/calls" && ! grep -q task-create "$TMP/calls" && [ "$(L get SPH-40 dispatch)" = "ctx_old41" ] && [ "$(L get SPH-40 state)" = "inbox" ] && pass "nothing is closed, created or written" || fail "active takeover side effects ($(cat "$TMP/calls"))"
# Review Focus 4: quiet, it is kept open and the stage starts, so retained terminals never hold every restart
reset; L set SPH-40 state=inbox dispatch=ctx_old48 >/dev/null; show ctx_old48 term_old48 user_owned user_takeover false 20
out=$(ST brief SPH-40)
[ "$(line "$out" 1)" = "kept previous session term_old48 (user_takeover)" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && ! grep -q 'terminal close' "$TMP/calls" && pass "a quiet taken-over terminal is kept open, and the stage starts" || fail "quiet takeover ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_old42 >/dev/null; show ctx_old42 term_old42 owned identity_unproven true 2
out=$(ST brief SPH-40); [ "$out" = "hold session term_old42 (identity_unproven)" ] && pass "an unproven identity that just wrote holds" || fail "unproven ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_old43 >/dev/null; show ctx_old43 term_old43 owned - false 3
out=$(ST brief SPH-40); [ "$out" = "hold session term_old43 (identity_unproven)" ] && pass "a terminal Orca cannot tie to the exact worker holds" || fail "not exact ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_old44 >/dev/null; show ctx_old44 term_old44 owned - true; touch "$TMP/close-fail"
out=$(ST brief SPH-40); [ "$out" = "hold session term_old44 (close failed: terminal is busy)" ] && ! grep -q task-create "$TMP/calls" && pass "a close that fails holds" || fail "close failed ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_gone45 >/dev/null
out=$(ST brief SPH-40); case "$out" in "started "*) ! grep -q 'terminal close' "$TMP/calls" && pass "a dispatch whose terminal is gone starts at once" || fail "gone closed something" ;; *) fail "gone ($out)" ;; esac
# a replayed start never ends its own dispatch
reset; L set SPH-40 state=inbox stage=brief counters.start=9 counters.live=9 task=task_live9 dispatch=ctx_live9 >/dev/null; show ctx_live9 term_live9 owned - true
out=$(ST brief SPH-40)
[ "$out" = "started task=task_live9 dispatch=ctx_live9" ] && ! grep -q 'worker-show' "$TMP/calls" 2>/dev/null && pass "a replay is not checked against itself" || fail "replay ($out; $(cat "$TMP/calls" 2>/dev/null))"

# the gate the lock says this item holds is stopped, whatever its terminal's state; another item's is left alone
# (the holder label is <project name>/<item>, as ship-ticket and babysit-pr pass it to gate-lock.sh)
holder() { # holder <label> [<lock file>]: hold the scratch gate lock, or that slot file, the way gate-lock.sh does (its own group), until signalled
  python3 - "${2:-$JUEL_GATE_LOCK}" "$1" <<'PY' &
import fcntl, os, sys, time
os.setpgrp()
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
os.ftruncate(fd, 0)
os.write(fd, f"{sys.argv[2]} pid={os.getpid()} pgid={os.getpgrp()} token=0123456789abcdef\n".encode())
time.sleep(60)
PY
  HPID=$!
  i=0; while [ $i -lt 50 ] && ! grep -q "pid=$HPID " "${2:-$JUEL_GATE_LOCK}" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
}
gone() { i=0; while [ $i -lt 30 ] && kill -0 "$1" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done; ! kill -0 "$1" 2>/dev/null; }
holder app/SPH-40
reset; L set SPH-40 state=inbox dispatch=ctx_gone46 >/dev/null
out=$(ST brief SPH-40)
[ "$(line "$out" 1)" = "stopped previous gate pgid=$HPID" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && pass "a gate left running after its terminal closed is named and the stage starts" || fail "orphaned gate ($out)"
gone "$HPID" && pass "its process group got the TERM" || { fail "gate left running"; kill "$HPID" 2>/dev/null; }
holder app/SPH-40
reset; L set SPH-40 state=inbox dispatch=ctx_old49 >/dev/null; show ctx_old49 term_old49 owned - true
out=$(ST brief SPH-40)
[ "$(line "$out" 1)" = "stopped previous gate pgid=$HPID" ] && [ "$(line "$out" 2)" = "ended previous session term_old49" ] && case "$(line "$out" 3)" in "started "*) true ;; *) false ;; esac && gone "$HPID" && pass "the gate goes first, then the session, then the start" || { fail "gate then session ($out)"; kill "$HPID" 2>/dev/null; }
holder app/SPH-99
reset; L set SPH-40 state=inbox dispatch=ctx_old47 >/dev/null; show ctx_old47 term_old47 owned - true
out=$(ST brief SPH-40)
kill -0 "$HPID" 2>/dev/null && ! printf '%s' "$out" | grep -q 'stopped previous gate' && pass "another item's gate is left alone" || fail "another item's gate was stopped ($out)"
kill "$HPID" 2>/dev/null; wait "$HPID" 2>/dev/null
holder app/SPH-40
reset; L set SPH-40 state=inbox dispatch=ctx_old52 >/dev/null; show ctx_old52 term_old52 user_owned user_takeover false 1
out=$(ST brief SPH-40)
[ "$out" = "hold session term_old52 (user_takeover)" ] && kill -0 "$HPID" 2>/dev/null && pass "a hold leaves the gate alone: the live session may be the one running it" || fail "hold stopped the gate ($out)"
kill "$HPID" 2>/dev/null; wait "$HPID" 2>/dev/null
reset; L set SPH-40 state=inbox dispatch=ctx_gone50 >/dev/null; printf 'SPH-40 pid=999999 pgid=999999 token=0123456789abcdef\n' > "$JUEL_GATE_LOCK"
out=$(ST brief SPH-40); case "$out" in "started "*) pass "stale text in a lock nobody holds is ignored" ;; *) fail "stale lock text ($out)" ;; esac

# for build and babysit, any other claude or codex terminal live in the worktree holds the start
WT50="$APP/.worktrees/app/SPH-50"; git -C "$APP" worktree add -q -b feat/sph-50-x "$WT50" >/dev/null 2>&1
L add SPH-50 ref=SPH-50 project=app state=babysit-queued pr=https://github.com/o/r/pull/50 "worktree=$WT50" >/dev/null; brief SPH-50; review SPH-50 1
trust "$APP" "$WT50"
terms() { # terms <handle> <agentIdentity or null> <minutes since it last wrote> [<worktree>]
  python3 - "$TMP/terminals.json" "$1" "$2" "$3" "${4:-$WT50}" <<'PY'
import json, sys, time
p, h, ident, ago, path = sys.argv[1:]
t = {"handle": h, "worktreePath": path, "agentIdentity": None if ident == "null" else ident,
     "lastOutputAt": int((time.time() - float(ago) * 60) * 1000), "connected": True}
json.dump({"ok": True, "result": {"terminals": [t], "totalCount": 1, "truncated": False}}, open(p, "w"))
PY
}
reset; terms term_wt1 claude 1
out=$(ST babysit SPH-50)
[ "$out" = "hold session term_wt1 (live in the worktree)" ] && grep -q "terminal list --worktree path:$WT50 --json" "$TMP/calls" && ! grep -q task-create "$TMP/calls" && pass "a claude terminal that just wrote in the worktree holds the start" || fail "live worktree terminal ($out)"
reset; terms term_wt2 codex 2; out=$(ST babysit SPH-50)
[ "$out" = "hold session term_wt2 (live in the worktree)" ] && pass "so does a codex one" || fail "codex terminal ($out)"
reset; terms term_wt3 claude 20; L set SPH-50 state=babysit-queued >/dev/null; out=$(ST babysit SPH-50)
case "$out" in "started "*) pass "a terminal quiet for 20 minutes does not" ;; *) fail "quiet terminal ($out)" ;; esac
reset; terms term_wt4 null 0; L set SPH-50 state=babysit-queued >/dev/null; out=$(ST babysit SPH-50)
case "$out" in "started "*) pass "a plain shell does not" ;; *) fail "plain shell ($out)" ;; esac
reset; L set SPH-50 state=babysit-queued dispatch=ctx_old51 >/dev/null; show ctx_old51 term_old51 owned - true 0 "$WT50"; terms term_old51 claude 0
out=$(ST babysit SPH-50)
[ "$(line "$out" 1)" = "ended previous session term_old51" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && pass "the terminal just ended is not counted again" || fail "ended then listed ($out)"
reset; terms term_wt5 claude 0; L set SPH-40 state=inbox dispatch=- >/dev/null; ST brief SPH-40 >/dev/null
! grep -q 'terminal list' "$TMP/calls" && pass "a brief in the main checkout does not look at its terminals" || fail "brief listed terminals"
# usage: the v1-only stages and --round are gone; unknown items
for gone in review fix screen; do ST "$gone" SPH-11 >/dev/null 2>&1; [ $? -eq 64 ] || fail "stage $gone still runs"; done; pass "review, fix and screen are not stages any more"
ST --round 1 babysit SPH-11 >/dev/null 2>&1; [ $? -eq 64 ] && pass "--round is gone" || fail "--round"
ST brief NOPE-1 >/dev/null 2>&1; [ $? -eq 4 ] && pass "an unknown item is 4" || fail "unknown item"

# review fixes: the gate lock is one file per user for every project, so the holder label names the project (#76)
for other in other-project/SPH-40 SPH-40; do
  holder "$other"
  reset; L set SPH-40 state=inbox dispatch=ctx_old53 >/dev/null; show ctx_old53 term_old53 owned - true
  out=$(ST brief SPH-40)
  kill -0 "$HPID" 2>/dev/null && ! printf '%s' "$out" | grep -q 'stopped previous gate' && pass "a gate held as $other is not this project's SPH-40" || fail "stopped a gate held as $other ($out)"
  kill "$HPID" 2>/dev/null; wait "$HPID" 2>/dev/null
done

# lane a: a released previous dispatch is gone: its terminal is closed best-effort and the stage starts (#95)
reset; L set SPH-40 state=inbox dispatch=ctx_rel80 >/dev/null; show ctx_rel80 term_rel80 released - false 1 "$APP" released
out=$(ST brief SPH-40)
[ "$(line "$out" 1)" = "ended previous session term_rel80" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && grep -q 'terminal close --terminal term_rel80 --json' "$TMP/calls" && pass "a released dispatch that just wrote is ended, and the stage starts" || fail "released ($out)"
# Review Focus 2: closing a terminal Orca already closed fails, and the start still goes on
reset; L set SPH-40 state=inbox dispatch=ctx_rel81 >/dev/null; show ctx_rel81 term_rel81 released - false 1 "$APP" released; touch "$TMP/close-fail"
out=$(ST brief SPH-40)
[ "$(line "$out" 1)" = "ended previous session term_rel81" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && ! printf '%s\n' "$out" | grep -q 'hold session' && pass "a released dispatch whose close fails still starts" || fail "released close failed ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_rel82 >/dev/null; show ctx_rel82 term_rel82 owned - false 1 "$APP" released
out=$(ST brief SPH-40); [ "$(line "$out" 1)" = "ended previous session term_rel82" ] && pass "releaseState released alone ends it" || fail "releaseState only ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_rel83 >/dev/null; show ctx_rel83 term_rel83 released - false 1
out=$(ST brief SPH-40); [ "$(line "$out" 1)" = "ended previous session term_rel83" ] && pass "ownershipState released alone ends it" || fail "ownershipState only ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_rel84 >/dev/null; show ctx_rel84 term_rel84 user_owned user_takeover false 1 "$APP" released
out=$(ST brief SPH-40); [ "$(line "$out" 1)" = "ended previous session term_rel84" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && grep -q 'terminal close --terminal term_rel84 --json' "$TMP/calls" && pass "D1g a released dispatch's own terminal is closed even when Orca marks it user_takeover (#175)" || fail "D1g released takeover ($out)"
reset; L set SPH-50 state=babysit-queued dispatch=ctx_rel85 >/dev/null; show ctx_rel85 term_rel85 released - false 0 "$WT50" released; terms term_rel85 claude 0
out=$(ST babysit SPH-50)
[ "$(line "$out" 1)" = "ended previous session term_rel85" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && pass "a released terminal still listed in the worktree does not hold" || fail "released then listed ($out)"

# #175: stage-start.sh close <dispatch> closes only the settled dispatch's own terminal
CL() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_REPO="$APP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" --home "$H" close "$@"; }
reset; show ctx_d1a term_d1a user_owned user_takeover false 1 "$APP" released
out=$(CL ctx_d1a); [ "$out" = "closed term_d1a" ] && grep -q 'terminal close --terminal term_d1a --json' "$TMP/calls" && pass "D1a a released dispatch's own terminal is closed despite user_takeover" || fail "D1a ($out)"
reset; show ctx_d1b term_d1b owned identity_unproven false 1 "$APP" released
out=$(CL ctx_d1b); [ "$out" = "closed term_d1b" ] && pass "D1b identity_unproven is closed too" || fail "D1b ($out)"
reset; show ctx_d1c term_d1c user_owned user_takeover false 1 "$APP" released
sed 's/"ownerDispatchId":"ctx_d1c"/"ownerDispatchId":"ctx_other"/' "$TMP/show-ctx_d1c.json" > "$TMP/x" && mv "$TMP/x" "$TMP/show-ctx_d1c.json"
out=$(CL ctx_d1c); [ "$out" = "kept term_d1c (user_takeover)" ] && ! grep -q 'terminal close' "$TMP/calls" && pass "D1c a terminal owned by another dispatch is kept" || fail "D1c ($out)"
reset; show ctx_d1d term_d1d owned - true 1 "$APP" not_requested
out=$(CL ctx_d1d); [ "$out" = "kept term_d1d (running)" ] && ! grep -q 'terminal close' "$TMP/calls" && pass "D1d a running dispatch's terminal is kept" || fail "D1d ($out)"
# I2 (#175, the shape Orca really reports): after worker-release a taken-over terminal stays
# releaseState retained, ownershipState user_owned, while the dispatch itself says completed
reset; show ctx_d1r term_d1r user_owned user_takeover false 1 "$APP" retained completed
out=$(CL ctx_d1r); [ "$out" = "closed term_d1r" ] && grep -q 'terminal close --terminal term_d1r --json' "$TMP/calls" && pass "I2a a completed dispatch's own retained takeover terminal is closed" || fail "I2a ($out)"
reset; show ctx_d1s term_d1s owned identity_unproven false 1 "$APP" retained failed
out=$(CL ctx_d1s); [ "$out" = "closed term_d1s" ] && pass "I2b a failed dispatch's own unproven terminal is closed" || fail "I2b ($out)"
reset; show ctx_d1t term_d1t user_owned user_takeover false 1 "$APP" retained dispatched
out=$(CL ctx_d1t); case "$out" in "kept term_d1t "*) ! grep -q 'terminal close' "$TMP/calls" ;; *) false ;; esac && pass "I2c a dispatch still out keeps its taken-over terminal" || fail "I2c ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_d1u >/dev/null; show ctx_d1u term_d1u user_owned user_takeover false 1 "$APP" retained completed
out=$(ST brief SPH-40); [ "$(line "$out" 1)" = "ended previous session term_d1u" ] && pass "I2d the previous completed dispatch's taken-over terminal is closed before the stage starts" || fail "I2d ($out)"
reset
out=$(CL ctx_d1e); [ "$out" = "none" ] && pass "D1e a dispatch with no terminal gives none" || fail "D1e ($out)"
reset; show ctx_d1e2 term_d1e2 released - false 1 "$APP" released
printf '{"ok":true,"result":{"terminals":[{"handle":"term_other","lastOutputAt":1}],"totalCount":1,"truncated":false}}\n' > "$TMP/list-all.json"
out=$(CL ctx_d1e2); [ "$out" = "none" ] && ! grep -q 'terminal close' "$TMP/calls" && pass "D1e a terminal Orca no longer lists gives none" || fail "D1e2 ($out)"
reset; show ctx_d1f term_d1f user_owned user_takeover false 1 "$APP" released; touch "$TMP/close-fail"
printf '{"ok":true,"result":{"terminals":[{"handle":"term_d1f","lastOutputAt":1}],"totalCount":1,"truncated":false}}\n' > "$TMP/list-all.json"
out=$(CL ctx_d1f); [ "$out" = "kept term_d1f (close failed: terminal is busy)" ] && pass "D1f a failed close of a listed terminal is kept" || fail "D1f ($out)"
out=$(CL 2>&1); code=$?; [ "$code" = 64 ] && pass "close without a dispatch is usage" || fail "close usage ($code $out)"
# D1h: owned by another dispatch with user_takeover keeps today's behaviour
reset; L set SPH-40 state=inbox dispatch=ctx_d1h >/dev/null; show ctx_d1h term_d1h user_owned user_takeover false 1 "$APP" released
sed 's/"ownerDispatchId":"ctx_d1h"/"ownerDispatchId":"ctx_other"/' "$TMP/show-ctx_d1h.json" > "$TMP/x" && mv "$TMP/x" "$TMP/show-ctx_d1h.json"
out=$(ST brief SPH-40); [ "$out" = "hold session term_d1h (user_takeover)" ] && ! grep -q 'terminal close' "$TMP/calls" && pass "D1h a released terminal owned by another dispatch still holds" || fail "D1h ($out)"
# #119: a terminal Orca no longer lists is gone, whatever worker-show still says about it; a list
# that cannot be read, or is cut short, proves nothing and keeps today's behaviour
started_only() { [ "$(printf '%s\n' "$1" | wc -l | tr -d ' ')" = 1 ] && case "$1" in "started "*) true ;; *) false ;; esac; }
others() { printf '{"ok":true,"result":{"terminals":[{"handle":"term_other","lastOutputAt":1}],"totalCount":1,"truncated":%s}}\n' "${1:-false}" > "$TMP/list-all.json"; }
reset; L set SPH-40 state=inbox dispatch=ctx_i119a >/dev/null; show ctx_i119a term_i119a user_owned user_takeover false 1 "$APP" retained; others
out=$(ST brief SPH-40)
started_only "$out" && grep -q 'terminal list --limit 500 --json' "$TMP/calls" && ! grep -q 'terminal close' "$TMP/calls" && pass "#119 a retained takeover terminal Orca no longer lists is gone: the stage starts, nothing is closed" || fail "#119 unlisted takeover ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119b >/dev/null; show ctx_i119b term_i119b owned identity_unproven true 2; others
out=$(ST brief SPH-40); started_only "$out" && pass "#119 an unlisted unproven terminal starts too" || fail "#119 unlisted unproven ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119c >/dev/null; show ctx_i119c term_i119c owned - true; others; touch "$TMP/close-fail"
out=$(ST brief SPH-40); started_only "$out" && grep -q 'terminal close --terminal term_i119c --json' "$TMP/calls" && pass "#119 the dispatch's own terminal is still closed first, and a failed close of a terminal Orca no longer lists does not hold" || fail "#119 unlisted owned ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119g >/dev/null; show ctx_i119g term_i119g user_owned user_takeover false 20 "$APP" retained; others
out=$(ST brief SPH-40); started_only "$out" && pass "#119 an unlisted quiet terminal gets no kept line: it is gone" || fail "#119 unlisted quiet ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119d >/dev/null; show ctx_i119d term_i119d user_owned user_takeover false 1 "$APP" retained
out=$(ST brief SPH-40); [ "$out" = "hold session term_i119d (user_takeover)" ] && pass "#119 a listed taken-over terminal that just wrote still holds" || fail "#119 listed takeover ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119e >/dev/null; show ctx_i119e term_i119e user_owned user_takeover false 1 "$APP" retained; touch "$TMP/list-all-fail"
out=$(ST brief SPH-40); [ "$out" = "hold session term_i119e (user_takeover)" ] && pass "#119 a terminal list that cannot be read keeps the hold" || fail "#119 unreadable list ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119f >/dev/null; show ctx_i119f term_i119f user_owned user_takeover false 1 "$APP" retained; others true
out=$(ST brief SPH-40); [ "$out" = "hold session term_i119f (user_takeover)" ] && pass "#119 a truncated list proves nothing: the hold stays" || fail "#119 truncated list ($out)"
# #119: a listed taken-over terminal whose only recent output is Claude Code's recap line is quiet:
# kept, and the stage starts. Claude Code 2.1.301 renders the recap as "※ recap: <text>" (wrapped
# rows indented under it) above the prompt: a rule row, "❯", a rule row, then the footer
screen_of() { # screen_of <handle> <row>...: the rendered screen Orca returns for that terminal
  sh_handle=$1; shift
  python3 -c 'import json,sys; print(json.dumps({"ok":True,"result":{"terminal":{"handle":sys.argv[1],"source":"screen","tail":sys.argv[2:]}}}))' "$sh_handle" "$@" > "$TMP/screen-$sh_handle.json"
}
PROMPT_RULE='────────────────────────────────────────────────────────────'
PROMPT_FOOT='  ⏵⏵ bypass permissions on (shift+tab to cycle)'
reset; L set SPH-40 state=inbox dispatch=ctx_i119h >/dev/null; show ctx_i119h term_i119h user_owned user_takeover false 1 "$APP" retained
screen_of term_i119h "⏺ Opened PR #12 and pushed the fix." "" "※ recap: Fixed the login redirect and opened PR #12; waiting for review." "" "$PROMPT_RULE" "$(printf '❯\302\240')" "$PROMPT_RULE" "$PROMPT_FOOT"
out=$(ST brief SPH-40)
[ "$(line "$out" 1)" = "kept previous session term_i119h (user_takeover)" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && grep -q 'terminal read --terminal term_i119h --screen --json' "$TMP/calls" && ! grep -q 'terminal close' "$TMP/calls" && pass "#119 a recap-only screen is quiet: kept, and the stage starts" || fail "#119 recap only ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119i >/dev/null; show ctx_i119i term_i119i user_owned user_takeover false 1 "$APP" retained
screen_of term_i119i "※ recap: Fixed the login redirect, opened PR #12 and answered both review threads; the" "  gate is green and the PR waits for the hosted reviewer." "$PROMPT_RULE" "❯" "$PROMPT_RULE" "$PROMPT_FOOT" "  ? for shortcuts"
out=$(ST brief SPH-40); [ "$(line "$out" 1)" = "kept previous session term_i119i (user_takeover)" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && pass "#119 a recap wrapped onto two rows is still quiet" || fail "#119 wrapped recap ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119p >/dev/null; show ctx_i119p term_i119p user_owned user_takeover false 1 "$APP" retained
screen_of term_i119p "⏺ Opened PR #12." "※ recap: Fixed the login" "  redirect," "  opened PR" "  #12 and" "  answered" "  both review" "  threads; the" "  gate is green," "  waiting." "$PROMPT_RULE" "❯" "$PROMPT_RULE" "$PROMPT_FOOT"
out=$(ST brief SPH-40); [ "$(line "$out" 1)" = "kept previous session term_i119p (user_takeover)" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && pass "#119 a recap wrapped onto nine rows is still quiet" || fail "#119 long wrapped recap ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119q >/dev/null; show ctx_i119q term_i119q user_owned user_takeover false 1 "$APP" retained
screen_of term_i119q "※ recap: Opened PR #12." "  waiting for review." "⏺ Now fixing the review comments." "  editing src/login.ts" "$PROMPT_RULE" "❯" "$PROMPT_RULE" "$PROMPT_FOOT"
out=$(ST brief SPH-40); [ "$out" = "hold session term_i119q (user_takeover)" ] && pass "#119 an old recap with a later turn under it still holds" || fail "#119 old recap with later turn ($out)"
# a person typing, a turn still running, work output after the recap, or no prompt: the hold stays
recap_hold() { # recap_hold <name> <row>...
  rh_name=$1; shift
  reset; L set SPH-40 state=inbox dispatch=ctx_i119j >/dev/null; show ctx_i119j term_i119j user_owned user_takeover false 1 "$APP" retained
  screen_of term_i119j "$@"
  out=$(ST brief SPH-40); [ "$out" = "hold session term_i119j (user_takeover)" ] && pass "#119 $rh_name still holds" || fail "#119 $rh_name ($out)"
}
recap_hold "a recap above a prompt a person is typing in" "※ recap: Fixed the login redirect." "$PROMPT_RULE" "❯ also check the logout page" "$PROMPT_RULE" "$PROMPT_FOOT"
recap_hold "a recap above a running turn" "※ recap: Fixed the login redirect." "" "✽ Thinking… (12s · esc to interrupt)" "$PROMPT_RULE" "❯ " "$PROMPT_RULE" "  ⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt"
recap_hold "work output after the recap" "※ recap: Fixed the login redirect." "" "⏺ Running the tests again." "  ⎿  12 passed" "$PROMPT_RULE" "❯ " "$PROMPT_RULE" "$PROMPT_FOOT"
recap_hold "a footer that says a turn runs" "※ recap: Fixed the login redirect." "$PROMPT_RULE" "❯ " "$PROMPT_RULE" "  ⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt"
recap_hold "a recap with no prompt under it" "※ recap: Fixed the login redirect."

# review fixes (#119): a list that cannot prove it is whole proves nothing, a recap counts only once
# Orca released the dispatch, a screen Orca does not call a screen is not read, and the boxed prompt
# and the babysit start of the issue work too
listing() { printf '%s\n' "$1" > "$TMP/list-all.json"; }
hold_case() { # hold_case <name> <handle>: the start must still hold on that terminal
  out=$(ST brief SPH-40); [ "$out" = "hold session $2 (user_takeover)" ] && pass "#119 $1 keeps the hold" || fail "#119 $1 ($out)"
}
taken_over() { reset; L set SPH-40 state=inbox dispatch=ctx_i119k >/dev/null; show ctx_i119k term_i119k user_owned user_takeover false 1 "$APP" retained; }
taken_over; listing '{"ok":true,"result":{"terminals":[],"hostScope":{"hostIds":["local"],"omittedHostIds":["remote-1"]},"totalCount":0,"truncated":false}}'
hold_case "a list that left out a host" term_i119k
taken_over; listing '{"ok":false,"error":{"message":"runtime restarting"},"result":{"terminals":[]}}'
hold_case "an ok:false list printed with exit 0" term_i119k
taken_over; listing '{"ok":true,"result":{"terminals":[{"handle":"term_other"}],"totalCount":3,"truncated":false}}'
hold_case "a list with fewer rows than its totalCount" term_i119k
taken_over; listing '{"ok":true,"result":{"terminals":[{"handle":"term_other"}],"totalCount":1}}'
hold_case "a list that does not say it is untruncated" term_i119k
reset; L set SPH-40 state=inbox dispatch=ctx_i119l >/dev/null; show ctx_i119l term_i119l user_owned user_takeover false 1
screen_of term_i119l "※ recap: Waiting for the codex executor to finish." "$PROMPT_RULE" "❯ " "$PROMPT_RULE" "$PROMPT_FOOT"
out=$(ST brief SPH-40); [ "$out" = "hold session term_i119l (user_takeover)" ] && pass "#119 a recap on the terminal of a dispatch Orca has not released still holds" || fail "#119 active recap ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119m >/dev/null; show ctx_i119m term_i119m user_owned user_takeover false 1 "$APP" retained
python3 -c 'import json; print(json.dumps({"ok":True,"result":{"terminal":{"handle":"term_i119m","source":"scrollback","tail":["※ recap: x.","──────────","❯ ","──────────"]}}}))' > "$TMP/screen-term_i119m.json"
out=$(ST brief SPH-40); [ "$out" = "hold session term_i119m (user_takeover)" ] && pass "#119 a recap Orca does not call a screen keeps the hold" || fail "#119 scrollback ($out)"
reset; L set SPH-40 state=inbox dispatch=ctx_i119n >/dev/null; show ctx_i119n term_i119n user_owned user_takeover false 1 "$APP" retained
screen_of term_i119n "※ recap: Fixed the login redirect." "╭────────────────────────╮" "│ >                      │" "╰────────────────────────╯" "  ? for shortcuts"
out=$(ST brief SPH-40); [ "$(line "$out" 1)" = "kept previous session term_i119n (user_takeover)" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && pass "#119 a recap above a boxed prompt is quiet" || fail "#119 boxed prompt ($out)"
reset; L set SPH-50 state=babysit-queued dispatch=ctx_i119o >/dev/null; show ctx_i119o term_i119o user_owned user_takeover false 1 "$WT50" retained; others
out=$(ST babysit SPH-50); started_only "$out" && pass "#119 the babysit start of the issue goes on past an unlisted takeover terminal" || fail "#119 babysit ($out)"

# lane a: the .claude copy skips a nested worktree and anything that is not a regular file, and goes on past a file it cannot read (#98)
# the ignore rules go in .git/info/exclude, so the committed .gitignore is untouched
mkdir -p "$APP/.claude/worktrees/loose"
printf '/.claude/settings.local.json\n/.claude/locked.json\n/.claude/dirlink\n/.claude/worktrees/\n' >> "$APP/.git/info/exclude"
echo '{}' > "$APP/.claude/settings.local.json"
echo 'secret' > "$APP/.claude/locked.json"
echo 'notes' > "$APP/.claude/worktrees/loose/notes.txt"
ln -s worktrees "$APP/.claude/dirlink"
git -C "$APP" worktree add -q --detach "$APP/.claude/worktrees/side" >/dev/null 2>&1
[ "$(id -u)" -eq 0 ] || chmod 000 "$APP/.claude/locked.json"
L add SPH-70 ref=SPH-70 project=app state=queued >/dev/null; brief SPH-70
WT70="$APP/.worktrees/app/SPH-70"; trust "$APP" "$WT70"
reset; out=$(ST build SPH-70 2>"$TMP/err70")
case "$out" in "started "*) pass "a nested .claude worktree does not stop a build" ;; *) fail "nested .claude worktree ($out; $(tail -1 "$TMP/err70"))" ;; esac
[ -f "$WT70/.claude/settings.local.json" ] && pass "the ignored .claude settings file is still copied" || fail ".claude settings not copied"
[ ! -e "$WT70/.claude/worktrees" ] && [ ! -e "$WT70/.claude/dirlink" ] && [ ! -L "$WT70/.claude/dirlink" ] && pass "nothing under .claude/worktrees/ and no link to a folder is copied" || fail "copied a worktree or a link ($(ls -A "$WT70/.claude" 2>&1))"
if [ "$(id -u)" -ne 0 ]; then
  grep -qx 'stage-start.sh: could not copy .claude/locked.json (Permission denied)' "$TMP/err70" && [ ! -e "$WT70/.claude/locked.json" ] && pass "a file it cannot read is named on stderr, and the start goes on" || fail "unreadable file ($(tail -1 "$TMP/err70"))"
fi
chmod 644 "$APP/.claude/locked.json"

# lane a: a gate held in a gate-lock slot file is stopped, whatever the slot count says (#97)
printf '1\n' > "$JUEL_GATE_LOCK.slots"
holder app/SPH-40 "$JUEL_GATE_LOCK.2"
reset; L set SPH-40 state=inbox dispatch=ctx_gone90 >/dev/null
out=$(ST brief SPH-40)
[ "$(line "$out" 1)" = "stopped previous gate pgid=$HPID" ] && case "$(line "$out" 2)" in "started "*) true ;; *) false ;; esac && pass "a gate held in slot 2 is named and the stage starts, though the slot count is 1" || fail "slot 2 gate ($out)"
gone "$HPID" && pass "the slot 2 gate's process group got the TERM" || { fail "slot 2 gate left running"; kill "$HPID" 2>/dev/null; }
wait "$HPID" 2>/dev/null
rm -f "$JUEL_GATE_LOCK.2" "$JUEL_GATE_LOCK.slots"

# lane d: feedback STAR left beside a brief that was still drafting gives the brief stage --feedback (#112)
reset; L add SPH-80 ref=SPH-80 project=app >/dev/null
printf -- '- 2026-10-15 09:30 keep the old export name\n' > "$H/briefs/app/SPH-80.md.feedback.md"
ST brief SPH-80 >/dev/null
grep -q -- "draft-brief SPH-80 --project app --item SPH-80 --out $H/briefs/app/SPH-80.md --feedback --task-title" "$TMP/calls" && pass "a feedback side file alone gives --feedback" || fail "side file ($(grep task-create "$TMP/calls"))"
reset; L add SPH-81 ref=SPH-81 project=app >/dev/null
ST brief SPH-81 >/dev/null
grep -q -- "--out $H/briefs/app/SPH-81.md --task-title" "$TMP/calls" && pass "no side file and no ## Feedback: no --feedback" || fail "no feedback ($(grep task-create "$TMP/calls"))"
reset; L add SPH-82 ref=SPH-82 project=app >/dev/null; brief SPH-82; printf '## Feedback\n- 2026-10-15 09:40 smaller scope\n' >> "$H/briefs/app/SPH-82.md"
ST brief SPH-82 >/dev/null
grep -q -- "--out $H/briefs/app/SPH-82.md --feedback --task-title" "$TMP/calls" && pass "a brief's own ## Feedback still gives --feedback" || fail "brief feedback ($(grep task-create "$TMP/calls"))"

# #163: Orca 1.4.230 takes only a UUID as --retry-request; two folders never share one
reset; ST brief SPH-11 >/dev/null
grep -o -- '--retry-request [^ ]*' "$TMP/calls" | cut -d' ' -f2 | grep -vqiE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' && fail "#163 a request id Orca refuses ($(grep -o -- '--retry-request [^ ]*' "$TMP/calls"))" || pass "#163 every request id is a UUID"
[ "$(rq star-SPH-11-brief-r0-s1)" != "$(python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "juel-star:/elsewhere/star#star-SPH-11-brief-r0-s1"))')" ] && pass "#163 another folder gets another id" || fail "#163 folder in the id"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
