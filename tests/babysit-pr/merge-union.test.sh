#!/bin/sh
# Runs skills/babysit-pr/merge-union.sh on real merges in scratch repositories.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/babysit-pr/merge-union.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL merge-union.sh missing"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

repo() { R="$TMP/$1"; git init -q -b main "$R"; }
put() { mkdir -p "$(dirname "$R/$1")"; printf '%b' "$2" > "$R/$1"; }
commit() { git -C "$R" add -A && git -C "$R" commit -q -m "$1"; }
# feat merges main, as babysit-pr merges the base branch into the PR branch
merge() { git -C "$R" switch -q feat && git -C "$R" merge --no-edit main >/dev/null 2>&1; }
U() { sh "$SCRIPT" --repo-dir "$R"; }

# 1. appended rows, an in-line list, and a file with marker-like lines of its own
repo mech
put decisions.md '| id | who |\n|----|-----|\n| 1 | base |\n'
put tests.txt 'tests = [a, b]\n'
put notes.md 'A conflict looks like this:\n<<<<<<< ours\n=======\n>>>>>>> theirs\n'
commit base; git -C "$R" branch feat
put decisions.md '| id | who |\n|----|-----|\n| 1 | base |\n| 2 | main |\n'
put tests.txt 'tests = [a, b, d]\n'
put notes.md 'A conflict looks like this:\n<<<<<<< ours\n=======\n>>>>>>> theirs\nmain note\n'
commit main
git -C "$R" switch -q feat
put decisions.md '| id | who |\n|----|-----|\n| 1 | base |\n| 3 | feat |\n'
put tests.txt 'tests = [a, b, c]\n'
put notes.md 'A conflict looks like this:\n<<<<<<< ours\n=======\n>>>>>>> theirs\nfeat note\n'
commit feat
merge
out=$(U); rc=$?
[ $rc -eq 0 ] && pass "mechanical conflicts resolve (exit 0)" || fail "exit $rc ($out)"
[ "$(printf '%s\n' "$out" | sort | tr '\n' ' ')" = "resolved decisions.md resolved notes.md resolved tests.txt " ] && pass "one resolved line per file" || fail "lines ($out)"
[ "$(cat "$R/decisions.md")" = "$(printf '| id | who |\n|----|-----|\n| 1 | base |\n| 2 | main |\n| 3 | feat |')" ] && pass "appended rows: the base branch's first, then the PR's" || fail "rows ($(cat "$R/decisions.md"))"
[ "$(cat "$R/tests.txt")" = "tests = [a, b, d, c]" ] && pass "an in-line list keeps both entries" || fail "list ($(cat "$R/tests.txt"))"
grep -qx '<<<<<<< ours' "$R/notes.md" && [ "$(tail -n 2 "$R/notes.md" | tr '\n' ' ')" = "main note feat note " ] && pass "a file's own marker-like lines are left alone" || fail "notes ($(cat "$R/notes.md"))"
[ -z "$(git -C "$R" diff --name-only --diff-filter=U)" ] && git -C "$R" commit -q --no-edit && pass "nothing is left unmerged; the merge commits" || fail "still unmerged"

# 2. one mechanical file and one edited on both sides: nothing is written
repo mixed
put decisions.md '| 1 |\n'; put code.py 'x = 1\n'; commit base; git -C "$R" branch feat
put decisions.md '| 1 |\n| 2 |\n'; put code.py 'x = 2\n'; commit main
git -C "$R" switch -q feat; put decisions.md '| 1 |\n| 3 |\n'; put code.py 'x = 3\n'; commit feat
merge
out=$(U); rc=$?
[ $rc -eq 1 ] && pass "an edit on both sides is not mechanical (exit 1)" || fail "mixed exit $rc"
[ "$out" = "conflict code.py edited on both sides" ] && pass "only the file that is not mechanical is named" || fail "mixed out ($out)"
[ -n "$(git -C "$R" ls-files -u decisions.md)" ] && pass "all or nothing: the mechanical file is not staged either" || fail "partial write"
git -C "$R" merge --abort && pass "the merge still aborts cleanly" || fail "abort"

# 2b. insertions that would make a value neither side wrote: a spliced word (x = 101),
# or two insertions fused where they meet (["requests""numpy"], x = -+1)
edited_both() {
  repo "$1"; put v.py "$2"; commit base; git -C "$R" branch feat
  put v.py "$3"; commit main
  git -C "$R" switch -q feat; put v.py "$4"; commit feat
  merge
  out=$(U); rc=$?
  [ $rc -eq 1 ] && [ "$out" = "conflict v.py edited on both sides" ] && pass "$1: edited on both sides" || fail "$1: exit $rc ($out)"
  [ -n "$(git -C "$R" ls-files -u v.py)" ] && pass "$1: nothing is staged" || fail "$1: staged"
}
edited_both word 'x = 1\n' 'x = 10\n' 'x = 11\n'
edited_both quoted 'deps = []\n' 'deps = ["requests"]\n' 'deps = ["numpy"]\n'
edited_both sign 'x = 1\n' 'x = -1\n' 'x = +1\n'

# 3. shapes that are never mechanical
repo shapes
put package-lock.json '{\n  "a": 1\n}\n'; put old.txt 'one\n'; put blob.bin 'a\0b\n'; commit base; git -C "$R" branch feat
put package-lock.json '{\n  "a": 1,\n  "b": 2\n}\n'; git -C "$R" rm -q old.txt; put new.txt 'main\n'; put blob.bin 'a\0c\n'; commit main
git -C "$R" switch -q feat
put package-lock.json '{\n  "a": 1,\n  "c": 3\n}\n'; put old.txt 'two\n'; put new.txt 'feat\n'; put blob.bin 'a\0d\n'; commit feat
merge
out=$(U); rc=$?
[ $rc -eq 1 ] && pass "never-mechanical shapes exit 1" || fail "shapes exit $rc"
for line in 'conflict package-lock.json lockfile' 'conflict new.txt added on both sides' 'conflict old.txt deleted on one side' 'conflict blob.bin binary'; do
  printf '%s\n' "$out" | grep -qxF "$line" && pass "$line" || fail "missing: $line ($out)"
done

# 4. no merge in progress, and bad usage
repo clean; put a.txt 'x\n'; commit base
U >/dev/null 2>&1; [ $? -eq 2 ] && pass "no merge in progress is 2" || fail "no merge"
sh "$SCRIPT" --bogus >/dev/null 2>&1; [ $? -eq 64 ] && pass "bad usage is 64" || fail "usage"
for dir in "$TMP/nope" "$TMP/clean/a.txt"; do
  err=$(sh "$SCRIPT" --repo-dir "$dir" 2>&1 >/dev/null); rc=$?
  [ $rc -eq 2 ] && [ "$err" = "merge-union.sh: no such directory: $dir" ] && pass "a --repo-dir that is not a directory is 2" || fail "repo-dir $dir: exit $rc ($err)"
done

# 5. a resolved path is staged as written, never as a glob: n[1].md must not take n1.md along
repo glob
put 'n[1].md' '| 1 |\n'; commit base; git -C "$R" branch feat
put 'n[1].md' '| 1 |\n| 2 |\n'; commit main
git -C "$R" switch -q feat; put 'n[1].md' '| 1 |\n| 3 |\n'; commit feat
merge
put n1.md 'not part of the merge\n'
out=$(U); rc=$?
[ $rc -eq 0 ] && [ "$out" = "resolved n[1].md" ] && pass "a path with glob characters resolves" || fail "glob path: exit $rc ($out)"
[ "$(git -C "$R" status --porcelain -- n1.md)" = "?? n1.md" ] && pass "an untracked file the path would match as a glob stays untracked" || fail "n1.md was staged ($(git -C "$R" status --porcelain))"

# 6. a stage whose blob cannot be read is a conflict, never an empty text
repo blob
put b.md '| 1 |\n'; commit base; git -C "$R" branch feat
put b.md '| 1 |\n| 2 |\n'; commit main
git -C "$R" switch -q feat; put b.md '| 1 |\n| 3 |\n'; commit feat
merge
sha=$(git -C "$R" ls-files -u -- b.md | awk '$3 == 1 { print $2 }')
rm -f "$R/.git/objects/$(printf '%s' "$sha" | cut -c1-2)/$(printf '%s' "$sha" | cut -c3-)"
before=$(cat "$R/b.md")
out=$(U); rc=$?
[ $rc -eq 1 ] && [ "$out" = "conflict b.md unreadable blob" ] && pass "an unreadable blob is a conflict (exit 1)" || fail "unreadable blob: exit $rc ($out)"
[ "$(cat "$R/b.md")" = "$before" ] && [ -n "$(git -C "$R" ls-files -u b.md)" ] && pass "an unreadable blob: nothing is written or staged" || fail "unreadable blob: written ($(cat "$R/b.md"))"

# 7. one insertion that starts or ends with the other's whole text is edited on both sides,
# never theirs then ours (1, 2, 3, 2)
repo overlap
put t.md '| 1 |\n'; commit base; git -C "$R" branch feat
put t.md '| 1 |\n| 2 |\n| 3 |\n'; commit main
git -C "$R" switch -q feat; put t.md '| 1 |\n| 2 |\n'; commit feat
merge
out=$(U); rc=$?
[ $rc -eq 1 ] && [ "$out" = "conflict t.md edited on both sides" ] && pass "an overlapping insertion is edited on both sides (exit 1)" || fail "overlap: exit $rc ($out)"
[ -n "$(git -C "$R" ls-files -u t.md)" ] && pass "an overlapping insertion stays conflicted" || fail "overlap: staged ($(cat "$R/t.md"))"

# 8. the overlap is in whole lines: dist/ and app/dist/ share text but no line, so both are kept
repo lines
put .gitignore 'node_modules/\n'; commit base; git -C "$R" branch feat
put .gitignore 'node_modules/\ndist/\n'; commit main
git -C "$R" switch -q feat; put .gitignore 'node_modules/\napp/dist/\n'; commit feat
merge
out=$(U); rc=$?
[ $rc -eq 0 ] && [ "$out" = "resolved .gitignore" ] && pass "lines that only share text both resolve" || fail "shared text: exit $rc ($out)"
[ "$(cat "$R/.gitignore")" = "$(printf 'node_modules/\ndist/\napp/dist/')" ] && pass "lines that only share text: the base branch's first, then the PR's" || fail "shared text ($(cat "$R/.gitignore"))"

# 9. one insertion's lines inside the other's block are edited on both sides, never 0, 2, 1, 2, 3
repo midblock
put m.md '| 0 |\n'; commit base; git -C "$R" branch feat
put m.md '| 0 |\n| 2 |\n'; commit main
git -C "$R" switch -q feat; put m.md '| 0 |\n| 1 |\n| 2 |\n| 3 |\n'; commit feat
merge
out=$(U); rc=$?
[ $rc -eq 1 ] && [ "$out" = "conflict m.md edited on both sides" ] && pass "an insertion inside the other's block is edited on both sides (exit 1)" || fail "mid-block: exit $rc ($out)"
[ -n "$(git -C "$R" ls-files -u m.md)" ] && pass "an insertion inside the other's block stays conflicted" || fail "mid-block: staged ($(cat "$R/m.md"))"

# 10. one in-line insertion that contains the other's text is edited on both sides, never
# "node a && node x && node x && node y" (#85), whichever side is the longer
for longer in main feat; do
  repo "contain-$longer"
  put chain.txt 'run: node a\n'; commit base; git -C "$R" branch feat
  if [ "$longer" = main ]; then put chain.txt 'run: node a && node x && node y\n'; else put chain.txt 'run: node a && node x\n'; fi
  commit main
  git -C "$R" switch -q feat
  if [ "$longer" = main ]; then put chain.txt 'run: node a && node x\n'; else put chain.txt 'run: node a && node x && node y\n'; fi
  commit feat
  merge
  out=$(U); rc=$?
  [ $rc -eq 1 ] && [ "$out" = "conflict chain.txt edited on both sides" ] && pass "contain-$longer: an insertion inside the other is edited on both sides (exit 1)" || fail "contain-$longer: exit $rc ($out)"
  [ -n "$(git -C "$R" ls-files -u chain.txt)" ] && pass "contain-$longer: nothing is staged" || fail "contain-$longer: staged ($(cat "$R/chain.txt"))"
done

# 11. both sides only added lines, at more than one point: every insertion is kept, in order (#92)
repo points
put reg.txt 'a\nb\nc\n'; commit base; git -C "$R" branch feat
put reg.txt 'a\nx\nb\ny\nc\n'; commit main
git -C "$R" switch -q feat; put reg.txt 'a\nz\nb\nc\nw\n'; commit feat
merge
out=$(U); rc=$?
[ $rc -eq 0 ] && [ "$out" = "resolved reg.txt" ] && pass "insertions at several points resolve (exit 0)" || fail "points: exit $rc ($out)"
[ "$(tr '\n' ' ' < "$R/reg.txt")" = "a x z b y c w " ] && pass "insertions at several points: each point gets theirs, then ours" || fail "points ($(tr '\n' ' ' < "$R/reg.txt"))"

# 12. package.json: a test chain both sides added to, at different points and more than once (#85)
pkg() { printf '{\n  "name": "p",\n  "scripts": {\n    "build": "tsc",\n    "test": "%s"\n  }\n}\n' "$1"; }
chain() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["scripts"]["test"])' "$R/package.json" 2>/dev/null; }
repo pkg
pkg 'node a && node c' > "$R/package.json"; commit base; git -C "$R" branch feat
pkg 'node a && node b && node c' > "$R/package.json"; commit main
git -C "$R" switch -q feat; pkg 'node 0 && node a && node c && node d' > "$R/package.json"; commit feat
merge
out=$(U); rc=$?
[ $rc -eq 0 ] && [ "$out" = "resolved package.json" ] && pass "a package.json test chain resolves (exit 0)" || fail "pkg: exit $rc ($out)"
[ "$(chain)" = "node 0 && node a && node b && node c && node d" ] && pass "the chain is the ordered union: theirs, then ours, at each point" || fail "pkg chain ($(chain))"
[ "$(sed -n 4p "$R/package.json")" = '    "build": "tsc",' ] && [ -z "$(git -C "$R" diff --name-only --diff-filter=U)" ] && pass "the rest of package.json is untouched and nothing is left unmerged" || fail "pkg rest ($(cat "$R/package.json"))"

# 13. package.json: one side's addition contains the other's: each command once (#85)
repo pkgdup
pkg 'node a' > "$R/package.json"; commit base; git -C "$R" branch feat
pkg 'node a && node x' > "$R/package.json"; commit main
git -C "$R" switch -q feat; pkg 'node a && node x && node y' > "$R/package.json"; commit feat
merge
out=$(U); rc=$?
[ $rc -eq 0 ] && [ "$(chain)" = "node a && node x && node y" ] && pass "a command both sides added is kept once" || fail "pkgdup: exit $rc ($(chain))"

# 14. package.json: one command's name contains the other's: both kept, each exactly once (Review Focus 2)
repo pkgbak
pkg 'node a' > "$R/package.json"; commit base; git -C "$R" branch feat
pkg 'node a && node x.test.cjs' > "$R/package.json"; commit main
git -C "$R" switch -q feat; pkg 'node a && node x.test.cjs.bak' > "$R/package.json"; commit feat
merge
out=$(U); rc=$?
[ $rc -eq 0 ] && [ "$(chain)" = "node a && node x.test.cjs && node x.test.cjs.bak" ] && pass "commands that share text are both kept, each once" || fail "pkgbak: exit $rc ($(chain))"

# 15. package.json chains that are not append-only stay conflicts: a dropped command, a changed
# command, and a chain outside "scripts" (commands added at different points: the in-line rule
# above already joins two additions at the same point, in any file)
not_chain() {
  repo "$1"; printf "$2" 'node a && node b' > "$R/package.json"; commit base; git -C "$R" branch feat
  printf "$2" "$3" > "$R/package.json"; commit main
  git -C "$R" switch -q feat; printf "$2" "$4" > "$R/package.json"; commit feat
  merge
  out=$(U); rc=$?
  [ $rc -eq 1 ] && [ "$out" = "conflict package.json edited on both sides" ] && pass "$1: edited on both sides" || fail "$1: exit $rc ($out)"
}
SCRIPTS='{\n  "scripts": {\n    "test": "%s"\n  }\n}\n'
OTHER='{\n  "jest": {\n    "test": "%s"\n  },\n  "scripts": {}\n}\n'
not_chain dropped "$SCRIPTS" 'node a && node b && node x' 'node a && node y'
not_chain changed "$SCRIPTS" 'node a && node b && node x' 'node a && node b2 && node y'
not_chain outside "$OTHER" 'node a && node x && node b' 'node a && node b && node y'

# 16. --resolve: one file from three files, outside any repository or merge (I-1)
D="$TMP/resolve"; mkdir -p "$D/base" "$D/ours" "$D/theirs"
printf '| 1 |\n' > "$D/base/t.md"; printf '| 1 |\n| 3 |\n' > "$D/ours/t.md"; printf '| 1 |\n| 2 |\n' > "$D/theirs/t.md"
(cd "$D" && sh "$SCRIPT" --resolve base/t.md ours/t.md theirs/t.md > "$D/out"); rc=$?
[ $rc -eq 0 ] && [ "$(od -c "$D/out")" = "$(printf '| 1 |\n| 2 |\n| 3 |\n' | od -c)" ] && pass "--resolve prints the merged text exactly (exit 0)" || fail "--resolve: exit $rc ($(cat "$D/out"))"
printf 'x = 1\n' > "$D/base/v.py"; printf 'x = 3\n' > "$D/ours/v.py"; printf 'x = 2\n' > "$D/theirs/v.py"
out=$(cd "$D" && sh "$SCRIPT" --resolve base/v.py ours/v.py theirs/v.py); rc=$?
[ $rc -eq 1 ] && [ "$out" = "conflict edited on both sides" ] && pass "--resolve: an edit on both sides is a conflict (exit 1)" || fail "--resolve conflict: exit $rc ($out)"
pkg 'node a && node c' > "$D/base/b.json"; pkg 'node a && node c && node y' > "$D/ours/o.json"; pkg 'node a && node b && node c' > "$D/theirs/t.json"
out=$(sh "$SCRIPT" --resolve --path app/package.json "$D/base/b.json" "$D/ours/o.json" "$D/theirs/t.json"); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -qF '"test": "node a && node b && node c && node y"' && pass "--resolve --path package.json applies the chain rule" || fail "--resolve --path: exit $rc ($out)"
out=$(sh "$SCRIPT" --resolve "$D/base/b.json" "$D/ours/o.json" "$D/theirs/t.json"); rc=$?
[ $rc -eq 1 ] && pass "--resolve without --path goes by the ours file's name (o.json is no package.json)" || fail "--resolve name: exit $rc ($out)"
pkg 'node a && node c' > "$D/base/package.json"; pkg 'node a && node c && node y' > "$D/ours/package.json"; pkg 'node a && node b && node c' > "$D/theirs/package.json"
out=$(sh "$SCRIPT" --resolve "$D/base/package.json" "$D/ours/package.json" "$D/theirs/package.json"); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -qF '"test": "node a && node b && node c && node y"' && pass "--resolve takes the name from the ours file" || fail "--resolve ours name: exit $rc ($out)"
printf '{}\n' > "$D/base/yarn.lock"; printf '{}\n' > "$D/ours/yarn.lock"; printf '{}\n' > "$D/theirs/yarn.lock"
out=$(sh "$SCRIPT" --resolve "$D/base/yarn.lock" "$D/ours/yarn.lock" "$D/theirs/yarn.lock"); rc=$?
[ $rc -eq 1 ] && [ "$out" = "conflict lockfile" ] && pass "--resolve refuses a lockfile" || fail "--resolve lockfile: exit $rc ($out)"
sh "$SCRIPT" --resolve "$D/base/t.md" "$D/ours/t.md" >/dev/null 2>&1; [ $? -eq 64 ] && pass "--resolve with two files is 64" || fail "--resolve two files"
err=$(sh "$SCRIPT" --resolve "$D/base/t.md" "$D/ours/t.md" "$D/nope.md" 2>&1 >/dev/null); rc=$?
[ $rc -eq 64 ] && [ "$err" = "merge-union.sh: no such file: $D/nope.md" ] && pass "--resolve with a missing file is 64" || fail "--resolve missing: exit $rc ($err)"

# lane d: a package.json chain the base side reordered resolves when no side drops or repeats a
# command and ours only adds; a command both sides added, or one whose text another's contains, is
# written once (#103, Review Focus 3). Each case runs as a merge and again under --resolve.
# both_ways <name> <file> <writer> <base> <main> <feat> <want>: <writer>
# turns a text into the file, feat merges main, and <want> is what the merged file holds, or "conflict"
both_ways() {
  repo "$1"; "$3" "$4" > "$R/$2"; commit base; git -C "$R" branch feat
  "$3" "$5" > "$R/$2"; commit main
  git -C "$R" switch -q feat; "$3" "$6" > "$R/$2"; commit feat
  merge
  out=$(U); rc=$?
  F="$TMP/three-$1"; mkdir -p "$F"
  "$3" "$4" > "$F/base"; "$3" "$6" > "$F/ours"; "$3" "$5" > "$F/theirs"
  got=$(sh "$SCRIPT" --resolve --path "$2" "$F/base" "$F/ours" "$F/theirs"); grc=$?
  if [ "$7" = conflict ]; then
    [ $rc -eq 1 ] && [ "$out" = "conflict $2 edited on both sides" ] && pass "$1: edited on both sides" || fail "$1: exit $rc ($out)"
    [ $grc -eq 1 ] && [ "$got" = "conflict edited on both sides" ] && pass "$1: --resolve: a conflict too" || fail "$1: --resolve exit $grc ($(printf '%s' "$got" | tr '\n' ' '))"
  else
    want=$("$3" "$7")
    [ $rc -eq 0 ] && [ "$out" = "resolved $2" ] && [ "$(cat "$R/$2")" = "$want" ] && pass "$1: resolves to $7" || fail "$1: exit $rc ($out)"
    [ $grc -eq 0 ] && [ "$got" = "$want" ] && pass "$1: --resolve prints the same file" || fail "$1: --resolve exit $grc ($(printf '%s' "$got" | tr '\n' ' '))"
  fi
}
both_ways reordered package.json pkg 'node a && node b && node c' 'node b && node c && node x && node a' 'node a && node b && node c && node y' 'node b && node c && node y && node x && node a'
both_ways reorder-start package.json pkg 'node a && node b' 'node b && node a' 'node 0 && node a && node b' 'node 0 && node b && node a'
both_ways reorder-both package.json pkg 'node a && node b' 'node b && node a && node x' 'node a && node b && node x && node y' 'node b && node y && node a && node x'
both_ways reorder-bak package.json pkg 'node a && node b' 'node b && node a && node x.test.cjs' 'node a && node b && node x.test.cjs.bak' 'node b && node x.test.cjs.bak && node a && node x.test.cjs'
both_ways reorder-theirs-drops package.json pkg 'node a && node b && node c' 'node c && node b && node x' 'node a && node b && node c && node y' conflict
both_ways reorder-ours-drops package.json pkg 'node a && node b && node c' 'node b && node c && node a' 'node a && node c && node y' conflict
both_ways reorder-ours-moves package.json pkg 'node a && node b && node c' 'node b && node c && node a' 'node b && node a && node c && node y' conflict
both_ways reorder-repeat-base package.json pkg 'node a && node b && node a' 'node b && node a && node a' 'node a && node b && node a && node y' conflict
both_ways reorder-repeat-ours package.json pkg 'node a && node b && node c' 'node b && node c && node a' 'node a && node b && node c && node y && node y' conflict
both_ways reorder-repeat-theirs package.json pkg 'node a && node b && node c' 'node b && node c && node a && node b' 'node a && node b && node c && node y' conflict

# lane d: a one-line { a, b } list both sides only added names to, at different points, resolves to
# the base's order with theirs' then ours' names at each point, in theirs' style; a name dropped,
# moved or repeated, a value that is no plain name, or a changed suffix stays a conflict (#103)
one_line() { printf '%s\n' "$1"; }
both_ways exports x.js one_line 'module.exports = { a, b, c };' 'module.exports = { a, x, b, c, w };' 'module.exports = { a, y, b, z, c };' 'module.exports = { a, x, y, b, z, c, w };'
both_ways exports-both x.js one_line 'module.exports = { a, b };' 'module.exports = { a, x, b };' 'module.exports = { a, b, x };' 'module.exports = { a, x, b };'
both_ways exports-style x.js one_line 'export {a, b}' 'export {a, x, b,}' 'export { a, b, y }' 'export {a, x, b, y,}'
both_ways exports-dropped x.js one_line 'module.exports = { a, b, c };' 'module.exports = { a, x, c };' 'module.exports = { a, b, c, y };' conflict
both_ways exports-moved x.js one_line 'module.exports = { a, b };' 'module.exports = { b, a, x };' 'module.exports = { a, b, y };' conflict
both_ways exports-repeat x.js one_line 'module.exports = { a, b };' 'module.exports = { a, x, b, x };' 'module.exports = { a, b, y };' conflict
both_ways exports-value x.js one_line 'module.exports = { a, b };' 'module.exports = { a, x: 1, b };' 'module.exports = { a, b, y };' conflict
both_ways exports-suffix x.js one_line 'module.exports = { a, b };' 'module.exports = { a, x, b }' 'module.exports = { a, b, y };' conflict

# fix: #103 a brace list keeps its separator
# A brace glob or a shell brace expansion is a list too, but a space after its comma changes what it
# means. The merged list is joined with the separator all three sides use: "," or ", ". A list of one
# name has no separator and agrees with either. Sides that differ, or any other spacing (two spaces,
# a tab, a space before the comma), stay a conflict. Each case is a merge and a --resolve.
lint() { printf '{\n  %s: "eslint"\n}\n' "$1"; }
TAB=$(printf '\t')
both_ways brace-glob .lintstagedrc.json lint '"*.{js,ts}"' '"*.{cjs,js,ts}"' '"*.{js,ts,tsx}"' '"*.{cjs,js,ts,tsx}"'
both_ways brace-shell copy.sh one_line 'cp src/{a,b}.js dist/' 'cp src/{d,a,b}.js dist/' 'cp src/{a,b,c}.js dist/' 'cp src/{d,a,b,c}.js dist/'
both_ways brace-spaced copy.sh one_line 'cp src/{a, b}.js dist/' 'cp src/{d, a, b}.js dist/' 'cp src/{a, b, c}.js dist/' 'cp src/{d, a, b, c}.js dist/'
both_ways brace-one-name copy.sh one_line 'cp src/{a}.js dist/' 'cp src/{d,a}.js dist/' 'cp src/{a,c}.js dist/' 'cp src/{d,a,c}.js dist/'
both_ways brace-exports-spaced x.js one_line 'module.exports = { a, b };' 'module.exports = { a, x, b };' 'module.exports = { a, b, y };' 'module.exports = { a, x, b, y };'
both_ways brace-base-spaced copy.sh one_line 'cp src/{a, b}.js dist/' 'cp src/{d,a,b}.js dist/' 'cp src/{a, b, c}.js dist/' conflict
both_ways brace-ours-differs copy.sh one_line 'cp src/{a,b}.js dist/' 'cp src/{d,a,b}.js dist/' 'cp src/{a, b, c}.js dist/' conflict
both_ways brace-two-spaces copy.sh one_line 'cp src/{a,  b}.js dist/' 'cp src/{d,  a,  b}.js dist/' 'cp src/{a,  b,  c}.js dist/' conflict
both_ways brace-tab copy.sh one_line "cp src/{a,${TAB}b}.js dist/" "cp src/{d,${TAB}a,${TAB}b}.js dist/" "cp src/{a,${TAB}b,${TAB}c}.js dist/" conflict
both_ways brace-space-before copy.sh one_line 'cp src/{a ,b}.js dist/' 'cp src/{d ,a ,b}.js dist/' 'cp src/{a ,b ,c}.js dist/' conflict

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
