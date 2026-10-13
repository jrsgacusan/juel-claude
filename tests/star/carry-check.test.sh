#!/bin/sh
# Runs skills/star/carry-check.sh against a scratch repo, with merge-union.sh stubbed through
# CARRY_MERGE_UNION (the stub records the three files it gets and answers from union-out/union-rc).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/carry-check.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL carry-check.sh missing"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$TMP/app"; mkdir -p "$R" "$TMP/bin"
g() { git -C "$R" "$@"; }
s7() { printf '%.7s' "$1"; }
cat > "$TMP/bin/merge-union" <<'EOF'
#!/bin/sh
[ "$1" = --resolve ] || { echo "stub: no --resolve" >&2; exit 64; }
shift
if [ "$1" = --path ]; then printf '%s' "$2" > "$STUB_DIR/got-path"; shift 2; fi
cp "$1" "$STUB_DIR/got-base"; cp "$2" "$STUB_DIR/got-ours"; cp "$3" "$STUB_DIR/got-theirs"
cat "$STUB_DIR/union-out"
exit "$(cat "$STUB_DIR/union-rc" 2>/dev/null || echo 0)"
EOF
chmod +x "$TMP/bin/merge-union"
printf 'unused\n' > "$TMP/union-out"; echo 0 > "$TMP/union-rc"
C() { CARRY_MERGE_UNION="$TMP/bin/merge-union" STUB_DIR="$TMP" sh "$SCRIPT" --repo-dir "$R" "$@"; }
t() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got: $3)"; fi; }

# a base, a gated feature head, and main moving on
g init -q -b main
printf 'CHANGELOG.md merge=union\n' > "$R/.gitattributes"
printf 'one\n' > "$R/f"; printf 'a\nb\n' > "$R/list.txt"; printf 'start\n' > "$R/CHANGELOG.md"; printf 'x\n' > "$R/g"
g add . && g commit -qm base
g checkout -qb feat; printf 'two\n' > "$R/f"; g commit -qam feature
GATED=$(g rev-parse HEAD)
g checkout -q main; printf 'y\n' > "$R/g"; g commit -qam "main moves"; g update-ref refs/remotes/origin/main main
g checkout -q feat

# a clean merge of the base carries
g merge -q --no-edit origin/main; M1=$(g rev-parse HEAD)
t "a clean merge of the base carries the gated head's SAFE" "OK carried from $GATED: merge of origin/main with no conflicts" "$(C --from "$GATED" --head "$M1")"
C --from "$GATED" --head "$M1" >/dev/null; [ $? -eq 0 ] && pass "OK exits 0" || fail "OK exit"
t "a short --from is named by its full sha" "OK carried from $GATED: merge of origin/main with no conflicts" "$(C --from "$(s7 "$GATED")" --head "$M1")"

# Review Focus 1: a hand edit hidden in the merge commit
g checkout -q -b hand "$GATED"; g merge -q --no-commit --no-ff origin/main; printf 'sneaky\n' >> "$R/f"; g add f; g commit -qm "Merge origin/main"
HAND=$(g rev-parse HEAD)
out=$(C --from "$GATED" --head "$HAND"); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "NO $(s7 "$HAND") changes f beyond the merge git makes: a hand edit is a code change" ] && pass "a hand edit hidden in a merge commit never carries" || fail "hand edit ($rc $out)"

# a commit of its own after the gated head
g checkout -q -b extra "$GATED"; printf 'three\n' > "$R/f"; g commit -qam "more work"; EXTRA=$(g rev-parse HEAD)
out=$(C --from "$GATED" --head "$EXTRA"); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "NO $(s7 "$EXTRA") is not a merge: a commit of its own is a code change" ] && pass "a commit that is not a merge never carries" || fail "non-merge ($rc $out)"

# a second merge carries from the same gated head
g checkout -q main; printf 'z\n' > "$R/g"; g commit -qam "main moves again"; g update-ref refs/remotes/origin/main main
g checkout -q feat; g merge -q --no-edit origin/main; M2=$(g rev-parse HEAD)
t "a chain of base merges carries from the gated head" "OK carried from $GATED: merge of origin/main with no conflicts" "$(C --from "$GATED" --head "$M2")"
t "a head not on the line from the gated head is refused" "NO $(s7 "$EXTRA") is not on $(s7 "$M2")'s first-parent line" "$(C --from "$EXTRA" --head "$M2")"
t "the gated head itself has nothing to carry" "NO $(s7 "$M2") is the gated head itself: there is nothing to carry" "$(C --from "$M2" --head "$M2")"

# --base: only the base branch is ever carried in
g checkout -q -b other "$GATED~1"; printf 'side\n' > "$R/h"; g add h; g commit -qm "another feature"; OTHER=$(g rev-parse HEAD)
g checkout -q -b withside "$GATED"; g merge -q --no-edit other; WS=$(g rev-parse HEAD)
t "without --base, any clean merge carries" "OK carried from $GATED: merge of $(s7 "$OTHER") with no conflicts" "$(C --from "$GATED" --head "$WS")"
out=$(C --from "$GATED" --head "$WS" --base origin/main); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "NO $(s7 "$WS") merges $(s7 "$OTHER"), which is not on origin/main" ] && pass "--base: a merge of another branch never carries" || fail "base other ($rc $out)"
t "--base: a merge of the base carries" "OK carried from $GATED: merge of origin/main with no conflicts" "$(C --from "$GATED" --head "$M2" --base origin/main)"

# a conflict merge-union.sh resolves, resolved the same way
g checkout -q main; printf 'a\nb\nmain-line\n' > "$R/list.txt"; g commit -qam "main lists"; g update-ref refs/remotes/origin/main main
g checkout -q -b conflicted "$GATED"; printf 'a\nb\nfeat-line\n' > "$R/list.txt"; g commit -qam "feat lists"; G2=$(g rev-parse HEAD)
g merge -q --no-edit origin/main >/dev/null 2>&1
printf 'a\nb\nmain-line\nfeat-line\n' > "$R/list.txt"; g add list.txt; g commit -qm "Merge origin/main; mechanical conflicts resolved in list.txt"
MC=$(g rev-parse HEAD)
printf 'a\nb\nmain-line\nfeat-line\n' > "$TMP/union-out"; echo 0 > "$TMP/union-rc"
t "a conflict merge-union.sh resolves the same way carries" "OK carried from $G2: merge of origin/main, mechanical conflicts resolved in list.txt" "$(C --from "$G2" --head "$MC")"
[ "$(cat "$TMP/got-base")" = "$(printf 'a\nb')" ] && [ "$(cat "$TMP/got-ours")" = "$(printf 'a\nb\nfeat-line')" ] && [ "$(cat "$TMP/got-theirs")" = "$(printf 'a\nb\nmain-line')" ] && pass "merge-union.sh --resolve gets base, ours and theirs, in that order" || fail "stub files"
[ "$(cat "$TMP/got-path" 2>/dev/null)" = "list.txt" ] && pass "merge-union.sh --resolve gets --path with the conflicted file's repo path (its package.json rule needs the name)" || fail "stub path: $(cat "$TMP/got-path" 2>/dev/null)"
printf 'a\nb\nfeat-line\nmain-line\n' > "$TMP/union-out"
out=$(C --from "$G2" --head "$MC"); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "NO $(s7 "$MC"): list.txt is not the mechanical resolution of its conflict" ] && pass "a conflict resolved another way never carries" || fail "other resolution ($rc $out)"
printf 'conflict both sides changed line 2\n' > "$TMP/union-out"; echo 1 > "$TMP/union-rc"
t "a conflict merge-union.sh cannot resolve never carries" "NO $(s7 "$MC"): list.txt is not the mechanical resolution of its conflict" "$(C --from "$G2" --head "$MC")"
printf 'unused\n' > "$TMP/union-out"; echo 0 > "$TMP/union-rc"

# a merge=union file: clean when merge-tree applies the attribute, settled by merge-file --union when not
g checkout -q main; printf 'start\nmain entry\n' > "$R/CHANGELOG.md"; g commit -qam "main changelog"; g update-ref refs/remotes/origin/main main
g checkout -q -b unionside "$GATED"; printf 'start\nfeat entry\n' > "$R/CHANGELOG.md"; g commit -qam "feat changelog"; G3=$(g rev-parse HEAD)
g merge -q --no-edit origin/main; MU=$(g rev-parse HEAD)
t "a merge=union file git merged by itself carries as no conflict" "OK carried from $G3: merge of origin/main with no conflicts" "$(C --from "$G3" --head "$MU")"
EMPTY=$(git hash-object -t tree /dev/null)
t "when merge-tree does not apply the union attribute, git merge-file --union settles it" "OK carried from $G3: merge of origin/main, mechanical conflicts resolved in CHANGELOG.md" "$(GIT_ATTR_SOURCE=$EMPTY C --from "$G3" --head "$MU")"

# usage
C --from "$GATED" >/dev/null 2>&1; [ $? -eq 64 ] && pass "no --head is 64" || fail "usage head"
C --from nope --head "$M1" >/dev/null 2>&1; [ $? -eq 64 ] && pass "a commit git does not know is 64" || fail "usage commit"
C --from "$GATED" --head "$M1" --what x >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown flag is 64" || fail "usage flag"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
