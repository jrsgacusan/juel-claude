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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
