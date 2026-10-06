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
for d in inbox briefs reviews gates releases drafts memory; do [ -d "$H/$d" ] || fail "init did not create $d"; done; pass "init creates the subfolders"
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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
