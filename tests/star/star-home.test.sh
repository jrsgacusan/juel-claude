#!/bin/sh
# Runs skills/star/star-home.sh against scratch git repos.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/star-home.sh"
TMP=$(mktemp -d); trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL star-home.sh missing"; exit 1; }
mkrepo() { mkdir -p "$1" && (cd "$1" && git init -q . && git commit -q --allow-empty -m init); }
real() { (cd "$1" && pwd -P); }

# a plain repo: the folder is under docs/superpowers/context/star of the main checkout
mkrepo "$TMP/app"; APP=$(real "$TMP/app")
[ "$(sh "$SCRIPT" --cwd "$APP" path)" = "$APP/docs/superpowers/context/star" ] && pass "path in a plain repo" || fail "path in a plain repo ($(sh "$SCRIPT" --cwd "$APP" path))"
[ ! -e "$APP/docs" ] && pass "path creates nothing" || fail "path created files"
mkdir -p "$APP/src/deep"
[ "$(sh "$SCRIPT" --cwd "$APP/src/deep" path)" = "$APP/docs/superpowers/context/star" ] && pass "a subfolder resolves to the same folder" || fail "subfolder"
(cd "$APP" && git worktree add -q "$TMP/app wt" -b wt)
[ "$(sh "$SCRIPT" --cwd "$TMP/app wt" path)" = "$APP/docs/superpowers/context/star" ] && pass "a linked worktree resolves to the main checkout's folder" || fail "linked worktree ($(sh "$SCRIPT" --cwd "$TMP/app wt" path))"
[ "$(cd "$APP/src" && sh "$SCRIPT" path)" = "$APP/docs/superpowers/context/star" ] && pass "the current directory is the default" || fail "default cwd"

mkrepo "$TMP/my app"; SP=$(real "$TMP/my app")
HS=$(sh "$SCRIPT" --cwd "$SP" init) && [ "$HS" = "$SP/docs/superpowers/context/star" ] && [ -f "$HS/star.json" ] && (cd "$SP" && git check-ignore -q "$HS/star.json") && pass "a checkout path with a space works" || fail "path with a space ($HS)"

# init: creates once, never overwrites, makes git ignore it without touching .gitignore
H=$(sh "$SCRIPT" --cwd "$APP" init)
[ "$H" = "$APP/docs/superpowers/context/star" ] && [ -f "$H/open-loops.md" ] && [ -f "$H/ledger.md" ] && [ -f "$H/star.json" ] && pass "init creates the folder from the template" || fail "init"
for d in inbox briefs reviews gates releases drafts memory specs reports items grants progress; do [ -d "$H/$d" ] || fail "init did not create $d"; done; pass "init creates the subfolders"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["project"]=={"name":"app","repo":sys.argv[2]}, d["project"]; assert d["maxParallel"]==3' "$H/star.json" "$APP" && pass "init records the project in star.json" || fail "project block"
(cd "$APP" && git check-ignore -q "$H/open-loops.md") && pass "git ignores the folder" || fail "folder not ignored"
[ ! -e "$APP/.gitignore" ] && [ -z "$(cd "$APP" && git status --porcelain)" ] && pass ".gitignore untouched, nothing shows as a change" || fail "repo shows changes: $(cd "$APP" && git status --porcelain)"
echo "my answer" >> "$H/open-loops.md"; python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["maxParallel"]=5; json.dump(d,open(p,"w"))' "$H/star.json"
sh "$SCRIPT" --cwd "$APP" init >/dev/null; sh "$SCRIPT" --cwd "$TMP/app wt" init >/dev/null
grep -q '^my answer$' "$H/open-loops.md" && python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["maxParallel"]==5' "$H/star.json" && pass "init never overwrites what is there" || fail "init overwrote a file"
[ "$(grep -c 'context/star' "$APP/.git/info/exclude")" = 1 ] && pass "the exclude line is written once" || fail "exclude lines: $(grep -c 'context/star' "$APP/.git/info/exclude")"

# a repo that already ignores docs/: nothing is added
mkrepo "$TMP/ign"; IGN=$(real "$TMP/ign"); printf 'docs/\n' > "$IGN/.gitignore"; (cd "$IGN" && git add .gitignore && git commit -q -m ignore)
sh "$SCRIPT" --cwd "$IGN" init >/dev/null
! grep -q 'context/star' "$IGN/.git/info/exclude" 2>/dev/null && pass "an already ignored folder adds no exclude line" || fail "exclude line added although ignored"

# docsRoot: the dotted folder when it has content, and the workflow config
mkrepo "$TMP/dot"; DOT=$(real "$TMP/dot"); mkdir -p "$DOT/docs/.superpowers/specs"; : > "$DOT/docs/.superpowers/specs/x.md"
[ "$(sh "$SCRIPT" --cwd "$DOT" path)" = "$DOT/docs/.superpowers/context/star" ] && pass "an existing docs/.superpowers is used" || fail "dotted docsRoot"
mkrepo "$TMP/emp"; EMP=$(real "$TMP/emp"); mkdir -p "$EMP/docs/.superpowers"
[ "$(sh "$SCRIPT" --cwd "$EMP" path)" = "$EMP/docs/superpowers/context/star" ] && pass "an empty docs/.superpowers is not" || fail "empty dotted docsRoot"
mkrepo "$TMP/cfg"; CFG=$(real "$TMP/cfg"); mkdir -p "$CFG/.claude"; printf '{"docsRoot": "notes/sp"}\n' > "$CFG/.claude/workflow.json"
[ "$(sh "$SCRIPT" --cwd "$CFG" path)" = "$CFG/notes/sp/context/star" ] && pass "workflow.json docsRoot wins" || fail "workflow.json docsRoot"
printf '{"docsRoot": "local/sp"}\n' > "$CFG/.claude/workflow.local.json"
[ "$(sh "$SCRIPT" --cwd "$CFG" path)" = "$CFG/local/sp/context/star" ] && pass "workflow.local.json wins over workflow.json" || fail "workflow.local.json"
printf 'not json\n' > "$CFG/.claude/workflow.local.json"
[ "$(sh "$SCRIPT" --cwd "$CFG" path)" = "$CFG/notes/sp/context/star" ] && pass "a broken config file is skipped" || fail "broken config"

# Review focus 2: a docsRoot outside the repo works and writes no exclude line
mkrepo "$TMP/out"; OUT=$(real "$TMP/out"); mkdir -p "$OUT/.claude" "$TMP/elsewhere"; ELSE=$(real "$TMP/elsewhere")
printf '{"docsRoot": "%s"}\n' "$ELSE" > "$OUT/.claude/workflow.json"
HO=$(sh "$SCRIPT" --cwd "$OUT" init 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && [ "$HO" = "$ELSE/context/star" ] && [ -f "$HO/star.json" ] && ! grep -q 'context/star' "$OUT/.git/info/exclude" 2>/dev/null && pass "a docsRoot outside the repo works, with no exclude line" || fail "outside docsRoot (rc=$rc $HO)"

# Review focus 1: no usable checkout
mkdir -p "$TMP/plain"; sh "$SCRIPT" --cwd "$TMP/plain" path >/dev/null 2>&1; [ $? -eq 1 ] && [ ! -e "$TMP/plain/docs" ] && pass "outside a git repo is exit 1 and creates nothing" || fail "outside a repo"
git init -q --bare "$TMP/bare.git"; sh "$SCRIPT" --cwd "$TMP/bare.git" init >/dev/null 2>&1; [ $? -eq 1 ] && [ ! -e "$TMP/bare.git/docs" ] && pass "a bare repository is exit 1" || fail "bare repository"
sh "$SCRIPT" bogus >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown command is exit 64" || fail "usage"
sh "$SCRIPT" >/dev/null 2>&1; [ $? -eq 64 ] && pass "no command is exit 64" || fail "no command"

# Review focus 3: an exclude file that cannot be written does not stop init
mkrepo "$TMP/ro"; RO=$(real "$TMP/ro"); mkdir -p "$RO/.git/info"; : > "$RO/.git/info/exclude"; chmod 444 "$RO/.git/info/exclude"; chmod 555 "$RO/.git/info"
HR=$(sh "$SCRIPT" --cwd "$RO" init 2> "$TMP/ro.err"); rc=$?
chmod 755 "$RO/.git/info"
[ "$rc" -eq 0 ] && [ -f "$HR/star.json" ] && grep -q 'could not make git ignore' "$TMP/ro.err" && pass "an unwritable exclude file is a warning, not a failure" || fail "unwritable exclude (rc=$rc: $(cat "$TMP/ro.err"))"

# Review focus 4: ten at once
mkrepo "$TMP/race"; RACE=$(real "$TMP/race")
i=0; while [ $i -lt 10 ]; do i=$((i + 1)); sh "$SCRIPT" --cwd "$RACE" init >/dev/null 2>&1 & done; wait
HRA="$RACE/docs/superpowers/context/star"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["project"]["name"]=="race"' "$HRA/star.json" && cmp -s "$HRA/ledger.md" "$ROOT/skills/star/template/ledger.md" && [ "$(grep -c 'context/star' "$RACE/.git/info/exclude")" = 1 ] && pass "ten init calls at once leave one intact folder" || fail "concurrent init"

# Review: git lists the git directory, not the checkout, for a submodule and for a separate git dir
mkrepo "$TMP/lib"; mkrepo "$TMP/super"; SUP=$(real "$TMP/super")
(cd "$SUP" && git -c protocol.file.allow=always submodule add -q "$TMP/lib" libs/sub >/dev/null 2>&1 && git commit -q -m sub)
HSUB=$(sh "$SCRIPT" --cwd "$SUP/libs/sub" init 2>/dev/null)
[ "$HSUB" = "$SUP/libs/sub/docs/superpowers/context/star" ] && [ -f "$HSUB/star.json" ] && [ ! -e "$SUP/.git/modules/libs/sub/docs" ] && (cd "$SUP/libs/sub" && git check-ignore -q "$HSUB/star.json") && pass "a submodule's folder is in its checkout, not in the git directory" || fail "submodule ($HSUB)"
git init -q --separate-git-dir "$TMP/sep.git" "$TMP/sep" && (cd "$TMP/sep" && git commit -q --allow-empty -m init); SEP=$(real "$TMP/sep")
[ "$(sh "$SCRIPT" --cwd "$SEP" path 2>/dev/null)" = "$SEP/docs/superpowers/context/star" ] && [ ! -e "$TMP/sep.git/docs" ] && pass "a separate git dir: the folder is in the checkout" || fail "separate git dir ($(sh "$SCRIPT" --cwd "$SEP" path 2>&1))"
(cd "$SEP" && git worktree add -q "$TMP/sepwt" -b w)
[ "$(sh "$SCRIPT" --cwd "$SEP" path 2>/dev/null)" = "$SEP/docs/superpowers/context/star" ] && pass "a separate git dir with linked worktrees, from the main checkout" || fail "separate git dir, main checkout"
sh "$SCRIPT" --cwd "$TMP/sepwt" init >/dev/null 2>&1; [ $? -eq 1 ] && [ ! -e "$TMP/sep.git/docs" ] && [ ! -e "$TMP/sepwt/docs" ] && pass "a linked worktree whose main checkout git cannot name is exit 1" || fail "separate git dir, linked worktree"

# Review: a project folder that was moved keeps its name and gets its new path
mkrepo "$TMP/before"; sh "$SCRIPT" --cwd "$TMP/before" init >/dev/null; mv "$TMP/before" "$TMP/after"; AFT=$(real "$TMP/after")
HM=$(sh "$SCRIPT" --cwd "$AFT" init)
python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["project"]; assert d=={"name":"before","repo":sys.argv[2]}, d' "$HM/star.json" "$AFT" 2>/dev/null && pass "a moved project keeps its name and records its new path" || fail "moved project"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["project"]["orcaRepo"]="r1"; json.dump(d,open(p,"w"))' "$HM/star.json"; sh "$SCRIPT" --cwd "$AFT" init >/dev/null
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["project"]["orcaRepo"]=="r1"' "$HM/star.json" && pass "init keeps what STAR learned about the project" || fail "init dropped a learned field"

# the template no longer ships a repo of its own
T="$ROOT/skills/star/template"
[ ! -e "$T/CLAUDE.md" ] && [ ! -e "$T/gitignore" ] && [ ! -e "$T/memory/global.md" ] && pass "the template has no CLAUDE.md, gitignore or global notes" || fail "template still ships repo files"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "project" in d and d["project"] is None' "$T/star.json" && pass "template star.json has an empty project" || fail "template project key"

# migrate: a v1 home to schema 2
mkrepo "$TMP/mig"; MIG=$(real "$TMP/mig"); HM2=$(sh "$SCRIPT" --cwd "$MIG" init)
python3 - "$HM2/star.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["maxParallel"] = 5
d["stages"] = {"brief": {"agent": "claude", "model": "opus", "effort": "high"},
               "build": {"agent": "claude", "model": "opus", "effort": "xhigh", "executor": "session"},
               "fix": {"agent": "claude", "model": "opus", "effort": "xhigh", "executor": "session"},
               "review": {"agent": "codex", "model": "gpt-6-astra", "effort": "xhigh"},
               "screen": {"agent": "claude", "model": "opus", "effort": "xhigh"},
               "babysit": {"agent": "claude", "model": "opus", "effort": "xhigh", "executor": "session"},
               "post": {"agent": "claude", "model": "opus", "effort": "xhigh"}}
d["reviewer"] = {"agent": "codex", "model": "gpt-6-astra", "effort": "xhigh"}
d.pop("schema", None)
json.dump(d, open(p, "w"), indent=2)
PY
v1row() { printf '| %s | %s | mig | /w/%s | %s | %s | 1 | t1 | %s | 0 | https://x/pull/1 | abc1234 | - | - | - | 2026-10-08T12:00:00Z |\n' "$1" "$1" "$1" "$2" "$3" "$4" >> "$HM2/ledger.md"; }
v1row A pr-draft review -; v1row B reviewing review ctx_r1; v1row C screen-queued screen -; v1row D ready babysit -; v1row E building build ctx_b1; v1row F done babysit -; v1row G verifying babysit -
mkdir -p "$HM2/briefs/mig"
printf -- '---\njuel_brief: 1\n---\n## Work item\nx\n## Decisions\n- 2026-10-08 an earlier answer\n## Feedback\n- 2026-10-08 a note\n' > "$HM2/briefs/mig/A.md"
printf -- '---\njuel_brief: 1\n---\n## Work item\nx\n' > "$HM2/briefs/mig/C.md"
printf -- '---\njuel_brief: 1\napproved: 2026-10-08T09:00:00Z\n---\n## Work item\nx\n' > "$HM2/briefs/mig/D.md"
Q="$HM2/open-loops.md"; LS="$ROOT/skills/star/loops.sh"
sh "$LS" --file "$Q" add --kind approve-brief --project mig --item A --title "approve brief" --body "x" >/dev/null
sh "$LS" --file "$Q" add --kind prep --project mig --item C --title "a question" --body "x" >/dev/null
sh "$LS" --file "$Q" add --kind escalation --project mig --item E --title "stuck" --body "x" >/dev/null
out=$(sh "$SCRIPT" --cwd "$MIG" migrate)
[ "$out" = "$(printf 'stop ctx_r1\nmigrated rows=5')" ] && [ ! -e "$HM2/migrate-stops.txt" ] && pass "migrate names the worker to stop, moves five rows, then forgets the stop list" || fail "migrate output ($out)"
LG() { sh "$ROOT/skills/star/ledger.sh" --home "$HM2" get "$@"; }
[ "$(LG A state)/$(LG A stage)" = "queued/build" ] && [ "$(LG B state)/$(LG B dispatch)" = "queued/-" ] && [ "$(LG C state)" = "brief-ready" ] && [ "$(LG D state)/$(LG D stage)" = "brief-ready/build" ] && [ "$(LG G state)/$(LG G stage)" = "brief-ready/build" ] && [ "$(LG E state)" = "building" ] && [ "$(LG F state)" = "done" ] && pass "each v1 state lands where the table says" || fail "rows ($(sh "$ROOT/skills/star/ledger.sh" --home "$HM2" list))"
grep -q '### D1 Merge under a go' "$HM2/briefs/mig/D.md" && grep -q 'once you say go, the build resumes the gate loop on its existing PR, and STAR merges it under that go' "$HM2/briefs/mig/D.md" && pass "a v1 PR that waited for its merge waits for a go in the next batch" || fail "ready record ($(cat "$HM2/briefs/mig/D.md"))"
python3 - "$HM2/star.json" <<'PY' && pass "star.json is schema 2 and keeps the owner's own values" || fail "star.json after migrate"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == 2 and d["maxParallel"] == 5, d
assert set(d["stages"]) == {"brief", "build", "babysit", "post"}, d["stages"]
assert all("executor" not in s for s in d["stages"].values()), d["stages"]
assert "reviewer" not in d
assert d["executor"] == {"model": "latest-luna", "effort": "xhigh", "fallback": "latest-sol"}, d["executor"]
assert d["gate"]["model"] == "gpt-6-astra" and d["gate"]["maxRounds"] == 3, d["gate"]
assert d["hostedReviewer"] is None and d["hostGate"]["maxAgents"] == 40 and d["progressDeadlineMin"] == 30
PY
[ -f "$HM2/star.json.v1.bak" ] && [ -f "$HM2/ledger.md.v1.bak" ] && grep -q '"reviewer"' "$HM2/star.json.v1.bak" && pass "v1 files are backed up first" || fail "backups"
python3 - "$HM2/briefs/mig/A.md" <<'PY' && pass "the decision record lands inside ## Decisions, before ## Feedback" || fail "decision record placement ($(cat "$HM2/briefs/mig/A.md"))"
import re, sys
t = open(sys.argv[1]).read()
d = t.index("## Decisions"); r = t.index("### D1 Resume under the closed loop"); f = t.index("## Feedback")
assert d < r < f, (d, r, f)
assert "Source: star-home.sh migrate" in t
PY
grep -q '^## Decisions$' "$HM2/briefs/mig/C.md" && grep -q '### D1 Screen checks become person-only steps' "$HM2/briefs/mig/C.md" && pass "a brief without ## Decisions gets one" || fail "decisions section added"
open=$(sh "$LS" --file "$Q" list)
printf '%s\n' "$open" | grep -q "$(printf '\tapprove-brief\t')" && fail "approve-brief left open" || pass "approve-brief items are closed"
printf '%s\n' "$open" | grep -q "$(printf '\tprep\t')" && fail "prep left open" || pass "prep items are closed"
printf '%s\n' "$open" | grep -q "$(printf '\tescalation\t')" && pass "other items stay open" || fail "escalation was closed"
cp "$HM2/star.json" "$TMP/after.json"
[ "$(sh "$SCRIPT" --cwd "$MIG" migrate)" = "current" ] && cmp -s "$HM2/star.json" "$TMP/after.json" && pass "a second migrate changes nothing" || fail "migrate twice"

# migrate: a queue loops.sh cannot read stops it with exit 1, and the rerun still names the worker to stop
mkrepo "$TMP/mig2"; MIG2=$(real "$TMP/mig2"); HM3=$(sh "$SCRIPT" --cwd "$MIG2" init)
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.pop("schema",None); json.dump(d,open(p,"w"))' "$HM3/star.json"
printf '| R | R | mig2 | /w/R | reviewing | review | 1 | t1 | ctx_r2 | 0 | https://x/pull/2 | abc1234 | - | - | - | 2026-10-08T12:00:00Z |\n' >> "$HM3/ledger.md"
printf '<<<<<<< HEAD\n' >> "$HM3/open-loops.md"
sh "$SCRIPT" --cwd "$MIG2" migrate >/dev/null 2> "$TMP/mig2.err"; rc=$?
[ "$rc" -eq 1 ] && grep -q 'loops.sh list' "$TMP/mig2.err" && grep -qx 'stop ctx_r2' "$HM3/migrate-stops.txt" && pass "a queue loops.sh cannot read stops migrate with exit 1, and the stop list is kept" || fail "broken queue (rc=$rc: $(cat "$TMP/mig2.err"))"
grep -v '^<<<<<<< HEAD$' "$HM3/open-loops.md" > "$TMP/q2"; cat "$TMP/q2" > "$HM3/open-loops.md"
out=$(sh "$SCRIPT" --cwd "$MIG2" migrate)
[ "$out" = "$(printf 'stop ctx_r2\nmigrated rows=0')" ] && [ ! -e "$HM3/migrate-stops.txt" ] && pass "the rerun names the worker the stopped run had moved on" || fail "rerun ($out)"

# B-1: the stop lines are printed before the first row moves, so a run that fails still names them
unschema() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.pop("schema",None); json.dump(d,open(p,"w"))' "$1/star.json"; }
v1at() { printf '| %s | %s | p | /w/%s | %s | %s | 1 | t1 | %s | 0 | https://x/pull/1 | abc1234 | - | - | - | 2026-10-08T12:00:00Z |\n' "$2" "$2" "$2" "$3" "$4" "$5" >> "$1/ledger.md"; }
mkrepo "$TMP/mig3"; MIG3=$(real "$TMP/mig3"); HM4=$(sh "$SCRIPT" --cwd "$MIG3" init); unschema "$HM4"
v1at "$HM4" F fixing fix ctx_f3
printf '<<<<<<< HEAD\n' >> "$HM4/open-loops.md"
out=$(sh "$SCRIPT" --cwd "$MIG3" migrate 2> "$TMP/mig3.err"); rc=$?
[ "$rc" -ne 0 ] && [ "$out" = "stop ctx_f3" ] && grep -q 'loops.sh list' "$TMP/mig3.err" && grep -qx 'stop ctx_f3' "$HM4/migrate-stops.txt" && pass "a failing migrate prints the stop line of a live v1 fixing worker and keeps the stop list" || fail "failing migrate (rc=$rc, stdout: $out, stderr: $(cat "$TMP/mig3.err"))"
out=$(sh "$SCRIPT" --cwd "$MIG3" migrate 2>/dev/null); rc=$?
[ "$rc" -ne 0 ] && [ "$out" = "stop ctx_f3" ] && pass "a rerun that finds the stop list prints it again, even when it fails again" || fail "failing rerun (rc=$rc, stdout: $out)"
printf 'not a ledger\n' > "$HM4/ledger.md"
out=$(sh "$SCRIPT" --cwd "$MIG3" migrate 2> "$TMP/mig3b.err"); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "stop ctx_f3" ] && grep -q 'ledger.sh list' "$TMP/mig3b.err" && pass "a rerun that fails before it moves anything still prints the stop list it found" || fail "rerun with a broken ledger (rc=$rc, stdout: $out)"

# a failure while the rows are moving: the second row's move is refused by a stand-in ledger.sh
mkrepo "$TMP/mig4"; MIG4=$(real "$TMP/mig4"); HM5=$(sh "$SCRIPT" --cwd "$MIG4" init); unschema "$HM5"
v1at "$HM5" A reviewing review ctx_a4; v1at "$HM5" B fixing fix ctx_b4
STUB="$TMP/stubskill"; mkdir -p "$STUB"; cp "$SCRIPT" "$STUB/star-home.sh"; ln -s "$ROOT/skills/star/loops.sh" "$STUB/loops.sh"
printf '#!/bin/sh\ncase "$*" in *" set B "*) echo "refused" >&2; exit 2 ;; esac\nexec sh "%s" "$@"\n' "$ROOT/skills/star/ledger.sh" > "$STUB/ledger.sh"
out=$(sh "$STUB/star-home.sh" --cwd "$MIG4" migrate 2> "$TMP/mig4.err"); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "$(printf 'stop ctx_a4\nstop ctx_b4')" ] && grep -q 'ledger.sh set B' "$TMP/mig4.err" && pass "a migrate that fails while moving rows has already named every worker to stop" || fail "failing while moving (rc=$rc, stdout: $out, stderr: $(cat "$TMP/mig4.err"))"
out=$(sh "$SCRIPT" --cwd "$MIG4" migrate)
[ "$out" = "$(printf 'stop ctx_a4\nstop ctx_b4\nmigrated rows=1')" ] && [ ! -e "$HM5/migrate-stops.txt" ] && pass "the rerun prints each stop line once and deletes the stop list when it succeeds" || fail "rerun after a failed move ($out)"

# a folder already at schema 2 that still has a stop list (the run stopped after writing star.json)
mkrepo "$TMP/cur"; CUR=$(real "$TMP/cur"); HC=$(sh "$SCRIPT" --cwd "$CUR" init)
printf 'stop ctx_x\n' > "$HC/migrate-stops.txt"
out=$(sh "$SCRIPT" --cwd "$CUR" migrate)
[ "$out" = "$(printf 'stop ctx_x\ncurrent')" ] && [ ! -e "$HC/migrate-stops.txt" ] && pass "a current folder with a leftover stop list prints it, then forgets it" || fail "current with a stop list ($out)"

# B-2: an open row that is not in a v1 state but still sits at a removed stage cannot be started by v2
mkrepo "$TMP/mig5"; MIG5=$(real "$TMP/mig5"); HM6=$(sh "$SCRIPT" --cwd "$MIG5" init); unschema "$HM6"
v1at "$HM6" E escalated fix -; v1at "$HM6" X failed review -; v1at "$HM6" Z babysitting screen -
v1at "$HM6" D done fix -; v1at "$HM6" P dropped review -; v1at "$HM6" K queued build -; v1at "$HM6" R reviewing review ctx_r6
out=$(sh "$SCRIPT" --cwd "$MIG5" migrate)
LG5() { sh "$ROOT/skills/star/ledger.sh" --home "$HM6" get "$@"; }
[ "$(LG5 E state)/$(LG5 E stage)" = "escalated/build" ] && [ "$(LG5 X state)/$(LG5 X stage)" = "failed/build" ] && [ "$(LG5 Z state)/$(LG5 Z stage)" = "babysitting/build" ] && pass "an open row left at a removed stage reads stage build and keeps its state" || fail "restaged rows ($(sh "$ROOT/skills/star/ledger.sh" --home "$HM6" list))"
[ "$(LG5 D stage)" = "fix" ] && [ "$(LG5 P stage)" = "review" ] && [ "$(LG5 K stage)" = "build" ] && pass "done and dropped rows keep their stage, and a row already at build is left alone" || fail "closed rows ($(sh "$ROOT/skills/star/ledger.sh" --home "$HM6" list))"
[ "$out" = "$(printf 'stop ctx_r6\nmigrated rows=1')" ] && [ "$(LG5 R state)/$(LG5 R stage)" = "queued/build" ] && pass "only the row moved out of a v1 state is counted" || fail "restage count ($out)"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
