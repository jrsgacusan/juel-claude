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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
