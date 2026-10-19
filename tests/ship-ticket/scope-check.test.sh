#!/bin/sh
# Runs skills/ship-ticket/scope-check.sh against a scratch repository and plan (#78).
# Usage: sh tests/ship-ticket/scope-check.test.sh   (exit 0 = all cases pass)
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/ship-ticket/scope-check.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL scope-check.sh missing"; exit 1; }

R="$TMP/repo"
mkdir -p "$R/src" "$R/tests/fixtures" "$R/docs/plans"
g() { git -C "$R" "$@"; }
git -c init.defaultBranch=main init -q "$R"
g config user.email t@example.com; g config user.name t; g config commit.gpgsign false
for f in a b c d gone; do printf '%s\n' "$f" > "$R/src/$f.sh"; done
g add -A; g commit -qm base
BASE=$(g rev-parse HEAD)
cat > "$R/docs/plans/p.md" <<'EOF'
# A plan

### Task 1: one

**Files:**
- Modify: `src/a.sh:1-3`
- Create: `src/new.sh`
- Test: `tests/fixtures/`

### Task 2: two

**Files:**
- Modify: `src/b.sh`
- Delete: `src/gone.sh`

The prose also mentions `src/c.sh`, which names nothing: only Files lines count.
EOF
check() { (cd "$TMP" && sh "$SCRIPT" "$R/docs/plans/p.md" "$BASE" --repo-dir "$R"); }

# 1. Only named files changed (committed or not, created, deleted, or under a named folder): ok.
printf 'a2\n' > "$R/src/a.sh"; g add src/a.sh; g commit -qm "task 1"
printf 'b2\n' > "$R/src/b.sh"
printf 'n\n' > "$R/src/new.sh"
printf '{}\n' > "$R/tests/fixtures/x.json"
g rm -q src/gone.sh
out=$(check); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ok" ] && pass "#78 only named files changed: ok" || fail "#78 named files (rc=$rc: $out)"

# 2. The executor's ledger and the plan's own folder are never outside.
mkdir -p "$R/.superpowers/sdd/p"; printf '# SDD ledger\n' > "$R/.superpowers/sdd/p/progress.md"
printf 'notes\n' > "$R/docs/plans/p-notes.md"
out=$(check); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ok" ] && pass "#78 the ledger and the plan's folder are ignored" || fail "#78 ledger or plan folder (rc=$rc: $out)"

# 3. Files no Files block names are listed, sorted: one named only in prose, a new one, one with a space.
printf 'c2\n' > "$R/src/c.sh"
printf 'x\n' > "$R/src/extra.sh"
printf 'x\n' > "$R/src/with space.sh"
out=$(check); rc=$?
want=$(printf 'outside src/c.sh\noutside src/extra.sh\noutside src/with space.sh')
[ "$rc" -eq 1 ] && [ "$out" = "$want" ] && pass "#78 unnamed files are listed, sorted, exit 1" || fail "#78 unnamed files (rc=$rc: $out)"

# 4. A committed change counts as much as a working-tree one.
g add src/c.sh; g commit -qm "widened"
out=$(check); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "$want" ] && pass "#78 a committed unnamed change is still outside" || fail "#78 committed change (rc=$rc: $out)"

# 5. An unnamed deletion is outside; a file git ignores is not.
g rm -q src/d.sh
printf '*.log\n' >> "$R/.git/info/exclude"; : > "$R/build.log"
out=$(check); rc=$?
want=$(printf 'outside src/c.sh\noutside src/d.sh\noutside src/extra.sh\noutside src/with space.sh')
[ "$rc" -eq 1 ] && [ "$out" = "$want" ] && pass "#78 an unnamed deletion is outside, an ignored file is not" || fail "#78 deletion or ignored file (rc=$rc: $out)"

# 6. Paths are the repository's, whatever the current directory is.
out2=$(cd "$R/src" && sh "$SCRIPT" "$R/docs/plans/p.md" "$BASE"); rc=$?
[ "$rc" -eq 1 ] && [ "$out2" = "$want" ] && pass "#78 run from a subfolder, paths are the repository's" || fail "#78 subfolder (rc=$rc: $out2)"

# 7. A plan at the repository's top skips only itself, never the whole repository.
cp "$R/docs/plans/p.md" "$R/plan.md"
out3=$(cd "$TMP" && sh "$SCRIPT" "$R/plan.md" "$BASE" --repo-dir "$R"); rc=$?
if printf '%s\n' "$out3" | grep -qx 'outside plan.md'; then
  fail "#78 a top-level plan listed itself"
elif [ "$rc" -eq 1 ] && printf '%s\n' "$out3" | grep -qx 'outside src/c.sh'; then
  pass "#78 a plan at the top skips only itself"
else
  fail "#78 top-level plan (rc=$rc: $out3)"
fi
rm -f "$R/plan.md"

# 8. Bad usage is exit 64, and so is a plan, a sha or a folder it cannot use.
sh "$SCRIPT" >/dev/null 2>&1; [ $? -eq 64 ] && pass "no arguments is exit 64" || fail "no arguments"
sh "$SCRIPT" "$TMP/no-such-plan.md" "$BASE" --repo-dir "$R" >/dev/null 2>&1; [ $? -eq 64 ] && pass "a missing plan is exit 64" || fail "missing plan"
sh "$SCRIPT" "$R/docs/plans/p.md" deadbeef --repo-dir "$R" >/dev/null 2>&1; [ $? -eq 64 ] && pass "a sha that is not a commit is exit 64" || fail "bad sha"
mkdir -p "$TMP/nogit"; sh "$SCRIPT" "$R/docs/plans/p.md" "$BASE" --repo-dir "$TMP/nogit" >/dev/null 2>&1; [ $? -eq 64 ] && pass "a folder outside git is exit 64" || fail "not a repository"
sh "$SCRIPT" "$R/docs/plans/p.md" "$BASE" --bogus >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown flag is exit 64" || fail "unknown flag"

# 9. R1: work that existed before the executor ran is never outside; --record notes it.
R2="$TMP/repo2"
h() { git -C "$R2" "$@"; }
mkdir -p "$R2/src" "$R2/docs/plans"
git -c init.defaultBranch=main init -q "$R2"
h config user.email t@example.com; h config user.name t; h config commit.gpgsign false
for f in a b c; do printf '%s\n' "$f" > "$R2/src/$f.sh"; done
printf 'node_modules/\n' > "$R2/.gitignore"
cat > "$R2/docs/plans/q.md" <<'EOF'
### Task 1: one

**Files:**
- Modify: `src/a.sh`
EOF
h add -A; h commit -qm base
BASE2=$(h rev-parse HEAD)
BEFORE="$TMP/before"
# The state before dispatch: the skill's own .gitignore edit, an untracked file, a tracked edit of the user's.
printf 'superpowers/\n' >> "$R2/.gitignore"
printf 'mine\n' > "$R2/my-notes.txt"
printf 'b-user\n' > "$R2/src/b.sh"
out=$(cd "$TMP" && sh "$SCRIPT" --record "$BEFORE" --repo-dir "$R2"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "recorded 3" ] && pass "#78 --record prints 'recorded <n>' and exits 0" || fail "#78 --record (rc=$rc: $out)"
got=$(tr '\0' '\n' < "$BEFORE" | sort)
want=$(printf '.gitignore\nmy-notes.txt\nsrc/b.sh')
[ "$got" = "$want" ] && pass "#78 --record writes every changed and untracked path, NUL-separated" || fail "#78 record file ($got)"
check2() { (cd "$TMP" && sh "$SCRIPT" "$R2/docs/plans/q.md" "$BASE2" "$@" --repo-dir "$R2"); }
printf 'a2\n' > "$R2/src/a.sh"
out=$(check2); rc=$?
want=$(printf 'outside .gitignore\noutside my-notes.txt\noutside src/b.sh')
[ "$rc" -eq 1 ] && [ "$out" = "$want" ] && pass "#78 without --before, work from before the executor reads as outside" || fail "#78 no --before (rc=$rc: $out)"
out=$(check2 --before "$BEFORE"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ok" ] && pass "#78 --before: an uncommitted edit, an untracked file and a .gitignore edit are not outside" || fail "#78 --before (rc=$rc: $out)"
printf 'c2\n' > "$R2/src/c.sh"
printf 'x\n' > "$R2/src/extra.sh"
out=$(check2 --before "$BEFORE"); rc=$?
want=$(printf 'outside src/c.sh\noutside src/extra.sh')
[ "$rc" -eq 1 ] && [ "$out" = "$want" ] && pass "#78 --before: a file that was clean at record time is still outside" || fail "#78 --before outside (rc=$rc: $out)"
: > "$TMP/empty-before"
out=$(check2 --before "$TMP/empty-before"); rc=$?
want=$(printf 'outside .gitignore\noutside my-notes.txt\noutside src/b.sh\noutside src/c.sh\noutside src/extra.sh')
[ "$rc" -eq 1 ] && [ "$out" = "$want" ] && pass "#78 an empty --before file excuses nothing" || fail "#78 empty --before (rc=$rc: $out)"
check2 --before "$TMP/no-such-before" >/dev/null 2>&1; [ $? -eq 64 ] && pass "#78 an unreadable --before file is exit 64" || fail "#78 unreadable --before"
check2 --before >/dev/null 2>&1; [ $? -eq 64 ] && pass "#78 --before without a value is exit 64" || fail "#78 --before needs a value"
(cd "$TMP" && sh "$SCRIPT" --record "$TMP/no-dir/before" --repo-dir "$R2") >/dev/null 2>&1; [ $? -eq 64 ] && pass "#78 a --record file that cannot be written is exit 64" || fail "#78 unwritable --record"
(cd "$TMP" && sh "$SCRIPT" --record "$TMP/x-before" --repo-dir "$TMP/nogit") >/dev/null 2>&1; [ $? -eq 64 ] && pass "#78 --record outside a repository is exit 64" || fail "#78 --record outside git"
(cd "$TMP" && sh "$SCRIPT" --record >/dev/null 2>&1); [ $? -eq 64 ] && pass "#78 --record without a file is exit 64" || fail "#78 --record needs a value"
(cd "$TMP" && sh "$SCRIPT" --record "$TMP/x-before" "$R2/docs/plans/q.md" "$BASE2" --repo-dir "$R2") >/dev/null 2>&1; [ $? -eq 64 ] && pass "#78 --record takes no plan or sha" || fail "#78 --record with positional arguments"
out=$(cd "$R2/src" && sh "$SCRIPT" --record "$TMP/sub-before"); rc=$?
rec=$(tr '\0' '\n' < "$TMP/sub-before" | sort)
want=$(printf '.gitignore\nmy-notes.txt\nsrc/a.sh\nsrc/b.sh\nsrc/c.sh\nsrc/extra.sh')
[ "$rc" -eq 0 ] && [ "$out" = "recorded 6" ] && [ "$rec" = "$want" ] && pass "#78 --record from a subfolder records the repository's paths" || fail "#78 --record from a subfolder (rc=$rc: $out)"

# 10. R5: a plan that names no files at all is unchecked; a bare path counts; a "::" suffix is dropped.
cat > "$R2/docs/plans/nofiles.md" <<'EOF'
### Task 1: one

Change src/a.sh somehow. Modify the thing, and create a file. No Files block here.
EOF
out=$(cd "$TMP" && sh "$SCRIPT" "$R2/docs/plans/nofiles.md" "$BASE2" --repo-dir "$R2"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unchecked the plan names no files" ] && pass "#78 a plan with no Files entries is unchecked, exit 0" || fail "#78 no entries (rc=$rc: $out)"
cat > "$R2/docs/plans/bare.md" <<'EOF'
### Task 1: one

**Files:**
- Modify: src/a.sh:1-3 (the first function)
- Create: src/extra.sh
1. Test: src/c.sh
EOF
bare() { (cd "$TMP" && sh "$SCRIPT" "$R2/docs/plans/bare.md" "$BASE2" --before "$BEFORE" --repo-dir "$R2"); }
out=$(bare); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ok" ] && pass "#78 an entry with no backticks names its first token" || fail "#78 bare paths (rc=$rc: $out)"
printf 'd\n' > "$R2/src/d.sh"
out=$(bare); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "outside src/d.sh" ] && pass "#78 a bare-path plan still flags a file it does not name" || fail "#78 bare outside (rc=$rc: $out)"
rm -f "$R2/src/d.sh"
mkdir -p "$R2/tests"
printf 't\n' > "$R2/tests/test_b.py"; printf 't\n' > "$R2/tests/test_c.py"
cat > "$R2/docs/plans/node.md" <<'EOF'
**Files:**
- Modify: `src/a.sh`
- Modify: `src/extra.sh`
- Modify: `src/c.sh`
- Test: `tests/test_b.py::test_foo`
- Test: tests/test_c.py::TestX::test_y
EOF
out=$(cd "$TMP" && sh "$SCRIPT" "$R2/docs/plans/node.md" "$BASE2" --before "$BEFORE" --repo-dir "$R2"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ok" ] && pass "#78 a ::<node id> suffix is dropped, backticked or bare" || fail "#78 :: suffix (rc=$rc: $out)"

# lane e: #106 a base merged in mid-build is not the executor's work; what the branch did itself still counts
R3="$TMP/repo3"
k() { git -C "$R3" "$@"; }
mkdir -p "$R3/src" "$R3/docs/plans"
git -c init.defaultBranch=main init -q "$R3"
k config user.email t@example.com; k config user.name t; k config commit.gpgsign false
for f in a b c d e early; do printf '%s\n' "$f" > "$R3/src/$f.sh"; done
cat > "$R3/docs/plans/m.md" <<'EOF'
### Task 1: one

**Files:**
- Modify: `src/a.sh`
EOF
k add -A; k commit -qm base
k switch -q -c feat
# An earlier fix round's commit, made before this plan's base was recorded: never this plan's to check.
printf 'early2\n' > "$R3/src/early.sh"; k commit -qam "earlier fix round"
BASE3=$(k rev-parse HEAD)
check3() { (cd "$TMP" && sh "$SCRIPT" "$R3/docs/plans/m.md" "$BASE3" --repo-dir "$R3"); }
# 11. No merge in the range: the output is today's, so a change one commit made and a later one put
#     back is not listed (on a throwaway branch, so feat stays clean).
k switch -q -c undo
printf 'c2\n' > "$R3/src/c.sh"; k commit -qam "c changed"
printf 'c\n' > "$R3/src/c.sh"; k commit -qam "c put back"
out=$(check3); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ok" ] && pass "#106 no merge in the range: a change put back is not listed, as today" || fail "#106 no merge, put back (rc=$rc: $out)"
k switch -q feat
# 12. A branch commit, then the base moves and is merged in: the files only the base changed are not listed.
printf 'a2\n' > "$R3/src/a.sh"; k commit -qam "task 1"
k switch -q main
printf 'b-main\n' > "$R3/src/b.sh"; printf 'd-main\n' > "$R3/src/d.sh"; printf 'm\n' > "$R3/src/m.sh"
k add -A; k commit -qm "the base moves"
k switch -q feat; k merge -q --no-ff --no-edit main
out=$(check3); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ok" ] && pass "#106 a branch commit, then the base merged in: ok" || fail "#106 base merged in (rc=$rc: $out)"
# 13. What the branch did itself still counts (Review Focus 4): an unnamed commit and a rename (both
#     names, as today), made between two base merges. The earlier round's src/early.sh is not listed.
printf 'c2\n' > "$R3/src/c.sh"; k commit -qam "widened"
k mv src/e.sh src/e2.sh; k commit -qm "renamed"
k switch -q main; printf 'n\n' > "$R3/src/n.sh"; k add -A; k commit -qm "the base moves again"
k switch -q feat; k merge -q --no-ff --no-edit main
out=$(check3); rc=$?
want=$(printf 'outside src/c.sh\noutside src/e.sh\noutside src/e2.sh')
[ "$rc" -eq 1 ] && [ "$out" = "$want" ] && pass "#106 the branch's own commits still count across base merges; an earlier round's do not" || fail "#106 own commits across merges (rc=$rc: $out)"

# lane e: #106 a file the executor changed that a base merge also changed prints outside-merged
# 14. A committed and an uncommitted change to files a merge also changed print outside-merged, sorted
#     by path among the outside lines; src/m.sh and src/n.sh, which only the merges changed, stay unlisted.
printf 'b-mine\n' > "$R3/src/b.sh"; k commit -qam "b touched"
printf 'd-mine\n' > "$R3/src/d.sh"
out=$(check3); rc=$?
want=$(printf 'outside-merged src/b.sh\noutside src/c.sh\noutside-merged src/d.sh\noutside src/e.sh\noutside src/e2.sh')
[ "$rc" -eq 1 ] && [ "$out" = "$want" ] && pass "#106 a change to a file a merge also changed prints outside-merged" || fail "#106 outside-merged (rc=$rc: $out)"
# 15. outside-merged lines alone still exit 1, like outside.
cat > "$R3/docs/plans/m2.md" <<'EOF'
**Files:**
- Modify: `src/a.sh`, `src/c.sh`
- Delete: `src/e.sh`
- Create: `src/e2.sh`
EOF
out=$(cd "$TMP" && sh "$SCRIPT" "$R3/docs/plans/m2.md" "$BASE3" --repo-dir "$R3"); rc=$?
want=$(printf 'outside-merged src/b.sh\noutside-merged src/d.sh')
[ "$rc" -eq 1 ] && [ "$out" = "$want" ] && pass "#106 outside-merged lines alone exit 1" || fail "#106 outside-merged alone (rc=$rc: $out)"

# #134: nested bullets, a parenthetical label, a range, and --print
R4="$TMP/repo4"; mkdir -p "$R4/src" "$R4/docs/decisions" "$R4/docs/plans"
h() { git -C "$R4" "$@"; }
git -c init.defaultBranch=main init -q "$R4"; h config user.email t@example.com; h config user.name t; h config commit.gpgsign false
for f in a b c x; do printf '%s\n' "$f" > "$R4/src/$f.sh"; done
for n in 1 2 3 4 5 6 7; do printf 'd%s\n' "$n" > "$R4/docs/decisions/D-$n.md"; done
h add -A; h commit -qm base; BASE4=$(h rev-parse HEAD)
cat > "$R4/docs/plans/n.md" <<'EOF'
### Task 1: nested

**Files:**
- Modify:
  - `src/a.sh`
  - `src/b.sh`, `src/c.sh`
- Modify (restore whole file to abc1234): `src/x.sh`
- Create: `docs/decisions/D-1.md` through `-6.md`

Prose naming `docs/decisions/D-7.md` names nothing.
EOF
for f in a b c x; do printf '%s2\n' "$f" > "$R4/src/$f.sh"; done
for n in 1 2 3 4 5 6; do printf 'e%s\n' "$n" > "$R4/docs/decisions/D-$n.md"; done
out=$(cd "$TMP" && sh "$SCRIPT" "$R4/docs/plans/n.md" "$BASE4" --repo-dir "$R4"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ok" ] && pass "#134 nested bullets, several paths on a line, a parenthetical label and a range are all in scope" || fail "#134 nested scope (rc=$rc: $out)"
printf 'e7\n' > "$R4/docs/decisions/D-7.md"
out=$(cd "$TMP" && sh "$SCRIPT" "$R4/docs/plans/n.md" "$BASE4" --repo-dir "$R4"); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "outside docs/decisions/D-7.md" ] && pass "#134 a member past the range's end is still outside" || fail "#134 range end (rc=$rc: $out)"
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R4/docs/plans/n.md" --repo-dir "$R4"); rc=$?
want=$(printf 'scope docs/decisions/D-1.md\nscope docs/decisions/D-2.md\nscope docs/decisions/D-3.md\nscope docs/decisions/D-4.md\nscope docs/decisions/D-5.md\nscope docs/decisions/D-6.md\nscope src/a.sh\nscope src/b.sh\nscope src/c.sh\nscope src/x.sh')
[ "$rc" -eq 0 ] && [ "$out" = "$want" ] && pass "#134 --print lists the parsed scope, one scope line each, exit 0" || fail "#134 --print (rc=$rc: $out)"
cat > "$R4/docs/plans/m.md" <<'EOF'
**Files:**
- Modify:
  - `src/a.sh`
A prose line ends the block: `src/c.sh` is not in scope.
- Create: `docs/decisions/D-1.md` to `-3.md`
  - `src/b.sh` sits under a label that names its own path, so it is not read.
- Test:

  - `tests/`
EOF
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R4/docs/plans/m.md" --repo-dir "$R4"); rc=$?
want=$(printf 'scope docs/decisions/D-1.md\nscope docs/decisions/D-2.md\nscope docs/decisions/D-3.md\nscope src/a.sh\nscope tests/')
[ "$rc" -eq 0 ] && [ "$out" = "$want" ] && pass "#134 a line at the label's indent ends a nested block, a to range, a blank line inside a block" || fail "#134 block end (rc=$rc: $out)"

# review fixes for #134
cat > "$R4/docs/plans/r.md" <<'EOF'
**Files:**
- Modify: each of these
  - `src/a.sh`
- Modify (rename `run()` to `start()`): `src/c.sh`
- Create: `docs/decisions/D-08.md` through `-11.md`
- Create: `docs/decisions/E-3.md` through `-1.md`
- Create: `docs/decisions/F-1.md` through `docs/decisions/F-3.md`
  Explains why, and names nothing.
EOF
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R4/docs/plans/r.md" --repo-dir "$R4"); rc=$?
want=$(printf 'scope docs/decisions/D-08.md\nscope docs/decisions/D-09.md\nscope docs/decisions/D-10.md\nscope docs/decisions/D-11.md\nscope docs/decisions/E-1.md\nscope docs/decisions/E-2.md\nscope docs/decisions/E-3.md\nscope docs/decisions/F-1.md\nscope docs/decisions/F-2.md\nscope docs/decisions/F-3.md\nscope src/a.sh\nscope src/c.sh')
[ "$rc" -eq 0 ] && [ "$out" = "$want" ] && pass "#134 prose labels read their nested bullets, nested parentheses, zero-padded, reversed and full-name ranges" || fail "#134 review forms (rc=$rc: $out)"
printf '**Files:**\n\t- Modify:\n\t\t- `src/b.sh`\n' > "$R4/docs/plans/t.md"
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R4/docs/plans/t.md" --repo-dir "$R4"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "scope src/b.sh" ] && pass "#134 a tab-indented label reads its tab-indented bullets" || fail "#134 tabs (rc=$rc: $out)"
printf '**Files:**\n- Modify:\n' > "$R4/docs/plans/e.md"
out=$(cd "$TMP" && sh "$SCRIPT" "$R4/docs/plans/e.md" "$BASE4" --repo-dir "$R4"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unchecked the plan names no files" ] && pass "#134 a label that names nothing is no entry, so nothing is reverted" || fail "#134 empty label (rc=$rc: $out)"
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R4/docs/plans/e.md" --repo-dir "$R4"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "#134 --print on a plan that names nothing prints nothing" || fail "#134 empty --print (rc=$rc: $out)"

# gate r1 (#134): a label more indented than the block's label stays inside the block
cat > "$R4/docs/plans/g.md" <<'EOF'
**Files:**
- Modify: these files
  - Create: `src/a.sh`
  - `src/b.sh`
- Test: `tests/`
EOF
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R4/docs/plans/g.md" --repo-dir "$R4"); rc=$?
want=$(printf 'scope src/a.sh\nscope src/b.sh\nscope tests/')
[ "$rc" -eq 0 ] && [ "$out" = "$want" ] && pass "#134 a deeper label inside a nested block keeps the block open" || fail "#134 deeper label (rc=$rc: $out)"

# lane a: #155, several line ranges after one path
R5="$TMP/repo155"; mkdir -p "$R5/src" "$R5/docs/plans"
h5() { git -C "$R5" "$@"; }
git -c init.defaultBranch=main init -q "$R5"; h5 config user.email t@example.com; h5 config user.name t; h5 config commit.gpgsign false
printf 'x\n' > "$R5/src/x.js"; printf 'y\n' > "$R5/src/y.js"
h5 add -A; h5 commit -qm base; BASE5=$(h5 rev-parse HEAD)
printf '**Files:**\n- Modify: `src/x.js:20-35, 90-105`\n' > "$R5/docs/plans/a.md"
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R5/docs/plans/a.md" --repo-dir "$R5"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "scope src/x.js" ] && pass "#155a several ranges with spaces after the commas, backticked" || fail "#155a (rc=$rc: $out)"
printf '**Files:**\n- Modify: `src/x.js:20-35 , 90-105 ,120`\n' > "$R5/docs/plans/b.md"
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R5/docs/plans/b.md" --repo-dir "$R5"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "scope src/x.js" ] && pass "#155b spaces around the commas" || fail "#155b (rc=$rc: $out)"
printf '**Files:**\n- Modify:\n  - src/x.js:20-35, 90-105\n  - src/y.js\n' > "$R5/docs/plans/c.md"
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R5/docs/plans/c.md" --repo-dir "$R5"); rc=$?
want=$(printf 'scope src/x.js\nscope src/y.js')
[ "$rc" -eq 0 ] && [ "$out" = "$want" ] && pass "#155c a bare list item with several ranges" || fail "#155c (rc=$rc: $out)"
printf '**Files:**\n- Modify: src/x.js:20-35, 90-105\n' > "$R5/docs/plans/d.md"
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R5/docs/plans/d.md" --repo-dir "$R5"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "scope src/x.js" ] && pass "#155d a bare label remainder with several ranges" || fail "#155d (rc=$rc: $out)"
printf '**Files:**\n- Modify: `src/x.js:20-35, 90-105`, `src/y.js:3`\n' > "$R5/docs/plans/e.md"
out=$(cd "$TMP" && sh "$SCRIPT" --print "$R5/docs/plans/e.md" --repo-dir "$R5"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "$want" ] && pass "#155e two backticked paths, the first with several ranges" || fail "#155e (rc=$rc: $out)"
printf 'changed\n' > "$R5/src/x.js"
out=$(cd "$TMP" && sh "$SCRIPT" "$R5/docs/plans/a.md" "$BASE5" --repo-dir "$R5"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ok" ] && pass "#155f a changed file named with several ranges is in scope" || fail "#155f (rc=$rc: $out)"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
