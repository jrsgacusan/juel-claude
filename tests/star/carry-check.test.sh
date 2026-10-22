#!/bin/sh
# Runs skills/star/carry-check.sh against a scratch repo.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/carry-check.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL carry-check.sh missing"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$TMP/app"; mkdir -p "$R"
g() { git -C "$R" "$@"; }
s7() { printf '%.7s' "$1"; }
C() { sh "$SCRIPT" --repo-dir "$R" "$@"; }
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
t "a clean merge of the base carries the gated head's SAFE" "OK carried from $GATED: merge of origin/main brings no change to a file this branch changes" "$(C --from "$GATED" --head "$M1")"
C --from "$GATED" --head "$M1" >/dev/null; [ $? -eq 0 ] && pass "OK exits 0" || fail "OK exit"
t "a short --from is named by its full sha" "OK carried from $GATED: merge of origin/main brings no change to a file this branch changes" "$(C --from "$(s7 "$GATED")" --head "$M1")"

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
t "a chain of base merges carries from the gated head" "OK carried from $GATED: merge of origin/main brings no change to a file this branch changes" "$(C --from "$GATED" --head "$M2")"
t "a head not on the line from the gated head is refused" "NO $(s7 "$EXTRA") is not on $(s7 "$M2")'s first-parent line" "$(C --from "$EXTRA" --head "$M2")"
t "the gated head itself has nothing to carry" "NO $(s7 "$M2") is the gated head itself: there is nothing to carry" "$(C --from "$M2" --head "$M2")"

# --base: only the base branch is ever carried in
g checkout -q -b other "$GATED~1"; printf 'side\n' > "$R/h"; g add h; g commit -qm "another feature"; OTHER=$(g rev-parse HEAD)
g checkout -q -b withside "$GATED"; g merge -q --no-edit other; WS=$(g rev-parse HEAD)
t "without --base, any clean merge carries" "OK carried from $GATED: merge of $(s7 "$OTHER") brings no change to a file this branch changes" "$(C --from "$GATED" --head "$WS")"
out=$(C --from "$GATED" --head "$WS" --base origin/main); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "NO $(s7 "$WS") merges $(s7 "$OTHER"), which is not on origin/main" ] && pass "--base: a merge of another branch never carries" || fail "base other ($rc $out)"
t "--base: a merge of the base carries" "OK carried from $GATED: merge of origin/main brings no change to a file this branch changes" "$(C --from "$GATED" --head "$M2" --base origin/main)"

# #110: a conflict means both sides changed the file, so the merge brings the base into a file this
# branch changes. It never carries, however it was resolved.
g checkout -q main; printf 'a\nb\nmain-line\n' > "$R/list.txt"; g commit -qam "main lists"; g update-ref refs/remotes/origin/main main
g checkout -q -b conflicted "$GATED"; printf 'a\nb\nfeat-line\n' > "$R/list.txt"; g commit -qam "feat lists"; G2=$(g rev-parse HEAD)
g merge -q --no-edit origin/main >/dev/null 2>&1
printf 'a\nb\nmain-line\nfeat-line\n' > "$R/list.txt"; g add list.txt; g commit -qm "Merge origin/main; mechanical conflicts resolved in list.txt"
MC=$(g rev-parse HEAD)
out=$(C --from "$G2" --head "$MC"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "OK carried from $G2: the merge brings no change to a file this branch changes, except lines both sides only added (list.txt)" ] && pass "#110 a test-list conflict where both sides only appended, resolved by union, carries" || fail "#110 union-resolved conflict ($rc $out)"

# #110: a merge=union file git merged by itself, changed on both sides, never carries either
g checkout -q main; printf 'start\nmain entry\n' > "$R/CHANGELOG.md"; g commit -qam "main changelog"; g update-ref refs/remotes/origin/main main
g checkout -q -b unionside "$GATED"; printf 'start\nfeat entry\n' > "$R/CHANGELOG.md"; g commit -qam "feat changelog"; G3=$(g rev-parse HEAD)
g merge -q --no-edit origin/main; MU=$(g rev-parse HEAD)
out=$(C --from "$G3" --head "$MU"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "OK carried from $G3: the merge brings no change to a file this branch changes, except lines both sides only added (CHANGELOG.md)" ] && pass "#110 a merge=union file both sides only appended to carries" || fail "#110 union attribute ($rc $out)"

# usage
C --from "$GATED" >/dev/null 2>&1; [ $? -eq 64 ] && pass "no --head is 64" || fail "usage head"
C --from nope --head "$M1" >/dev/null 2>&1; [ $? -eq 64 ] && pass "a commit git does not know is 64" || fail "usage commit"
C --from "$GATED" --head "$M1" --what x >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown flag is 64" || fail "usage flag"
# review fixes: the base is named origin/main, not origin/HEAD (#75), and a mode change in the merge never carries (#75)
g symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
t "a clone's origin/HEAD does not name the base" "OK carried from $GATED: merge of origin/main brings no change to a file this branch changes" "$(C --from "$GATED" --head "$M1")"
g symbolic-ref --delete refs/remotes/origin/HEAD

# a mode change hidden in a merge commit is a hand edit (#75)
g checkout -q main; printf 'a\nb\n' > "$R/tool.sh"; g add tool.sh; g commit -qm "add tool"; g update-ref refs/remotes/origin/main main
g checkout -q -b modeside "$GATED"; g merge -q --no-commit --no-ff origin/main >/dev/null 2>&1
chmod +x "$R/tool.sh"; g add tool.sh; g commit -qm "Merge origin/main"; MX=$(g rev-parse HEAD)
out=$(C --from "$GATED" --head "$MX"); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "NO $(s7 "$MX") changes tool.sh beyond the merge git makes: a hand edit is a code change" ] && pass "a chmod +x hidden in a merge commit never carries" || fail "chmod in the merge ($rc $out)"

# lane a: #110 a merge carries only when the base changed none of the files the branch changes
# Review Focus 1: git merges this cleanly, but the base side changed a file the branch changed too.
g checkout -q main; printf '1\n2\n3\n4\n5\n6\n7\n' > "$R/app.txt"; g add app.txt; g commit -qm "add app"; g update-ref refs/remotes/origin/main main
g checkout -q -b samefile main; printf '1 feat\n2\n3\n4\n5\n6\n7\n' > "$R/app.txt"; g commit -qam "feat app"; G6=$(g rev-parse HEAD)
g checkout -q main; printf '1\n2\n3\n4\n5\n6\n7 main\n' > "$R/app.txt"; g commit -qam "main app"; g update-ref refs/remotes/origin/main main
g checkout -q samefile; g merge -q --no-edit origin/main && MS=$(g rev-parse HEAD)
[ "$(g show "$MS:app.txt")" = "$(printf '1 feat\n2\n3\n4\n5\n6\n7 main')" ] && pass "#110 control: git merged app.txt by itself" || fail "#110 control: the merge of app.txt was not clean"
out=$(C --from "$G6" --head "$MS" --base origin/main); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "NO $(s7 "$MS") brings base changes to app.txt, a file this branch changes: the gate reviews the merge" ] && pass "#110 a clean merge that changes a file the branch changes never carries" || fail "#110 clean same-file merge ($rc $out)"
# Review Focus 1: base changes only to files the branch never touched carry.
g checkout -q -b disjoint main; printf 'mine\n' > "$R/mine.txt"; g add mine.txt; g commit -qm "feat mine"; G7=$(g rev-parse HEAD)
g checkout -q main; printf 'theirs\n' > "$R/theirs.txt"; g add theirs.txt; g commit -qm "main theirs"; g update-ref refs/remotes/origin/main main
g checkout -q disjoint; g merge -q --no-edit origin/main; MJ=$(g rev-parse HEAD)
t "#110 a merge of base changes to files the branch never touched carries" "OK carried from $G7: merge of origin/main brings no change to a file this branch changes" "$(C --from "$G7" --head "$MJ" --base origin/main)"
# A later merge into a branch file stops the carry, though the earlier merge alone carries.
g checkout -q main; printf 'mine, from main\n' > "$R/mine.txt"; g add mine.txt; g commit -qm "main adds mine too"; g update-ref refs/remotes/origin/main main
g checkout -q disjoint; g merge -q --no-edit origin/main >/dev/null 2>&1; g checkout -q --theirs mine.txt; g add mine.txt; g commit -qm "Merge origin/main"; MJ2=$(g rev-parse HEAD)
out=$(C --from "$G7" --head "$MJ2" --base origin/main); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "NO $(s7 "$MJ2") brings base changes to mine.txt, a file this branch changes: the gate reviews the merge" ] && pass "#110 a later merge into a branch file stops the carry" || fail "#110 chain ($rc $out)"
# A conflict settled as the branch's own side still brought the base into that file.
g checkout -q -b ours "$G2"; g merge -q --no-edit origin/main >/dev/null 2>&1; g checkout -q --ours list.txt; g add list.txt; g commit -qm "Merge origin/main"; MO=$(g rev-parse HEAD)
[ "$(g show "$MO:list.txt")" = "$(g show "$G2:list.txt")" ] && pass "#110 control: the conflict was settled as the branch's side" || fail "#110 control: ours"
out=$(C --from "$G2" --head "$MO"); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "NO $(s7 "$MO") brings base changes to list.txt, a file this branch changes: the gate reviews the merge" ] && pass "#110 a conflict settled as the branch's side never carries" || fail "#110 ours ($rc $out)"

# audit lane C: lines both sides only added carry; any other change to a shared file does not
NO7() { printf 'NO %s brings base changes to %s, a file this branch changes: the gate reviews the merge' "$(s7 "$1")" "$2"; }
# two shared paths, both only appended to: the reason lists both, in path order
g checkout -q main; printf 'p\nq\n' > "$R/reg1.txt"; printf 'p\nq\n' > "$R/reg2.txt"; g add reg1.txt reg2.txt; g commit -qm "registries"; g update-ref refs/remotes/origin/main main
g checkout -q -b two main; printf 'p\nq\nfeat\n' > "$R/reg2.txt"; printf 'p\nq\nfeat\n' > "$R/reg1.txt"; g commit -qam "feat registries"; GT=$(g rev-parse HEAD)
g checkout -q main; printf 'p\nq\nmain\n' > "$R/reg1.txt"; printf 'p\nq\nmain\n' > "$R/reg2.txt"; g commit -qam "main registries"; g update-ref refs/remotes/origin/main main
g checkout -q two; g merge -q --no-edit origin/main >/dev/null 2>&1
printf 'p\nq\nmain\nfeat\n' > "$R/reg1.txt"; printf 'p\nq\nmain\nfeat\n' > "$R/reg2.txt"; g add reg1.txt reg2.txt; g commit -qm "Merge origin/main"; MT=$(g rev-parse HEAD)
t "lane C: two appended-to paths are listed in path order" "OK carried from $GT: the merge brings no change to a file this branch changes, except lines both sides only added (reg1.txt, reg2.txt)" "$(C --from "$GT" --head "$MT" --base origin/main)"
# a clean merge where both sides appended far apart in the same file
g checkout -q main; printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n' > "$R/far.txt"; g add far.txt; g commit -qm "far"; g update-ref refs/remotes/origin/main main
g checkout -q -b far main; printf 'top\n1\n2\n3\n4\n5\n6\n7\n8\n9\n' > "$R/far.txt"; g commit -qam "feat far"; GF1=$(g rev-parse HEAD)
g checkout -q main; printf '1\n2\n3\n4\n5\n6\n7\n8\n9\nbottom\n' > "$R/far.txt"; g commit -qam "main far"; g update-ref refs/remotes/origin/main main
g checkout -q far; g merge -q --no-edit origin/main; MF=$(g rev-parse HEAD)
t "lane C: a clean merge of two far-apart appends carries" "OK carried from $GF1: the merge brings no change to a file this branch changes, except lines both sides only added (far.txt)" "$(C --from "$GF1" --head "$MF" --base origin/main)"
# one side changes a line: refused as before
g checkout -q main; printf 'k1\nk2\nk3\nk4\nk5\nk6\nk7\n' > "$R/chg.txt"; g add chg.txt; g commit -qm "chg"; g update-ref refs/remotes/origin/main main
g checkout -q -b chg main; printf 'k1\nk2\nk3\nk4\nk5\nk6\nk7\nfeat\n' > "$R/chg.txt"; g commit -qam "feat chg"; GC1=$(g rev-parse HEAD)
g checkout -q main; printf 'K1\nk2\nk3\nk4\nk5\nk6\nk7\n' > "$R/chg.txt"; g commit -qam "main chg"; g update-ref refs/remotes/origin/main main
g checkout -q chg; g merge -q --no-edit origin/main; MCH=$(g rev-parse HEAD)
t "lane C: a changed line on one side is refused" "$(NO7 "$MCH" chg.txt)" "$(C --from "$GC1" --head "$MCH" --base origin/main)"
# a binary file changed on both sides
g checkout -q main; printf '\0a\0' > "$R/b.bin"; g add b.bin; g commit -qm "bin"; g update-ref refs/remotes/origin/main main
g checkout -q -b bin main; printf '\0a\0feat\0' > "$R/b.bin"; g commit -qam "feat bin"; GB1=$(g rev-parse HEAD)
g checkout -q main; printf '\0a\0main\0' > "$R/b.bin"; g commit -qam "main bin"; g update-ref refs/remotes/origin/main main
g checkout -q bin; g merge -q --no-edit origin/main >/dev/null 2>&1; printf '\0a\0main\0feat\0' > "$R/b.bin"; g add b.bin; g commit -qm "Merge origin/main"; MB=$(g rev-parse HEAD)
t "lane C: a binary file in both is refused" "$(NO7 "$MB" b.bin)" "$(C --from "$GB1" --head "$MB" --base origin/main)"
# a path one side renamed and the other side appended to
g checkout -q main; printf 'r1\nr2\nr3\nr4\nr5\nr6\n' > "$R/old.txt"; g add old.txt; g commit -qm "old"; g update-ref refs/remotes/origin/main main
g checkout -q -b ren main; g mv old.txt new.txt; g commit -qm "rename"; GR1=$(g rev-parse HEAD)
g checkout -q main; printf 'r1\nr2\nr3\nr4\nr5\nr6\nmain\n' > "$R/old.txt"; g commit -qam "main append"; g update-ref refs/remotes/origin/main main
g checkout -q ren; g merge -q --no-edit origin/main; MR=$(g rev-parse HEAD)
out=$(C --from "$GR1" --head "$MR" --base origin/main); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "$(NO7 "$MR" new.txt)" ] && pass "lane C: a renamed path with an append on the other side is refused" || fail "lane C rename ($rc $out)"

# audit lane C: a hand resolution carries only when it keeps every line both sides added
g checkout -q main; printf 'a\nb\n' > "$R/hand1.txt"; printf 'a\nb\n' > "$R/hand2.txt"; g add hand1.txt hand2.txt; g commit -qm "hand files"; g update-ref refs/remotes/origin/main main
g checkout -q -b handres main; printf 'a\nb\nX\n' > "$R/hand1.txt"; printf 'a\nb\nX1\nX2\n' > "$R/hand2.txt"; g commit -qam "feat hand"; GH=$(g rev-parse HEAD)
g checkout -q main; printf 'a\nb\nY\n' > "$R/hand1.txt"; printf 'a\nb\nY\n' > "$R/hand2.txt"; g commit -qam "main hand"; g update-ref refs/remotes/origin/main main
g checkout -q handres; g merge -q --no-edit origin/main >/dev/null 2>&1
printf 'a\nb\nZ\nY\n' > "$R/hand1.txt"; printf 'a\nb\nY\nX1\nX2\n' > "$R/hand2.txt"; g add hand1.txt hand2.txt; g commit -qm "Merge origin/main"; MH=$(g rev-parse HEAD)
t "audit lane C: a resolution that replaces the branch's line is refused" "$(NO7 "$MH" hand1.txt)" "$(C --from "$GH" --head "$MH" --base origin/main)"
g checkout -q -b handord "$GH"; g merge -q --no-edit origin/main >/dev/null 2>&1
printf 'a\nb\nX\nY\n' > "$R/hand1.txt"; printf 'a\nb\nX2\nX1\nY\n' > "$R/hand2.txt"; g add hand1.txt hand2.txt; g commit -qm "Merge origin/main"; MHO=$(g rev-parse HEAD)
t "audit lane C: a resolution that reorders the branch's appended lines is refused" "$(NO7 "$MHO" hand2.txt)" "$(C --from "$GH" --head "$MHO" --base origin/main)"
g checkout -q -b handok "$GH"; g merge -q --no-edit origin/main >/dev/null 2>&1
printf 'a\nb\nX\nY\n' > "$R/hand1.txt"; printf 'a\nb\nX1\nX2\nY\n' > "$R/hand2.txt"; g add hand1.txt hand2.txt; g commit -qm "Merge origin/main"; MHK=$(g rev-parse HEAD)
t "audit lane C: a resolution that keeps every added line carries" "OK carried from $GH: the merge brings no change to a file this branch changes, except lines both sides only added (hand1.txt, hand2.txt)" "$(C --from "$GH" --head "$MHK" --base origin/main)"

# #183: a twin of the gated merge (same tree, same parents, any order) carries; other parents never do
TWIN=$(g commit-tree "$M1^{tree}" -p "$M1^1" -p "$M1^2" -m "Merge branch 'main' into feat")
t "#183 a merge with the gated merge's tree and parents carries" "OK carried from $M1: $(s7 "$TWIN") has the same tree and parents as $(s7 "$M1")" "$(C --from "$M1" --head "$TWIN")"
TWINR=$(g commit-tree "$M1^{tree}" -p "$M1^2" -p "$M1^1" -m "Merge branch 'main' into feat")
t "#183 the same parents in the other order carry too" "OK carried from $M1: $(s7 "$TWINR") has the same tree and parents as $(s7 "$M1")" "$(C --from "$M1" --head "$TWINR")"
ONEP=$(g commit-tree "$M1^{tree}" -p "$M1^1" -m "not a merge")
out=$(C --from "$M1" --head "$ONEP"); rc=$?
[ "$rc" -eq 1 ] && case "$out" in "NO "*) true ;; *) false ;; esac && pass "#183 the same tree with different parents is refused" || fail "#183 different parents ($rc $out)"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
