#!/bin/sh
# Runs skills/star/worktree-clean.sh against a scratch repo with a bare remote, a real ledger and a
# stub orca whose `worktree rm` really removes the git worktree.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
S="$ROOT/skills/star"
SCRIPT="$S/worktree-clean.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL worktree-clean.sh missing"; exit 1; }

git init -q --bare "$TMP/remote.git"
APP="$TMP/app"; mkdir -p "$APP"
(cd "$APP" && git init -q -b main . && git commit -q --allow-empty -m init && git remote add origin "$TMP/remote.git" && git push -q origin main)
APP=$(cd "$APP" && pwd -P)
H=$(HOME="$TMP/home" sh "$S/star-home.sh" --cwd "$APP" init)
L() { sh "$S/ledger.sh" --home "$H" "$@"; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/orca" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/calls"
case "$*" in
  "worktree rm --worktree path:"*)
    p=${4#path:}
    case "$p" in *"${STUB_REFUSE:-no-such-path}"*) echo '{"ok":false,"error":{"message":"worktree is locked"}}'; exit 1 ;; esac
    common=$(git -C "$p" rev-parse --path-format=absolute --git-common-dir)
    git --git-dir="$common" worktree remove "$p" && echo '{"ok":true,"result":{"removed":true}}' ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$TMP/bin/orca"
WC() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" ORCA_CLI_COMMAND=orca sh "$SCRIPT" --home "$H" "$@"; }
# wt <item>: a worktree on feat/<item> cut from origin/main
wt() { git -C "$APP" worktree add -q -b "feat/$1" "$APP/.worktrees/app/$1" origin/main 2>/dev/null; echo "$APP/.worktrees/app/$1"; }
commit() { (cd "$1" && echo "$2" > "$2.txt" && git add "$2.txt" && git commit -q -m "$2"); }
row() { L add "$1" "ref=$1" project=app "state=$2" "worktree=$3" "head=${4:--}" >/dev/null; }

# done, pushed: removed, cell cleared, logged
A=$(wt A); commit "$A" a; git -C "$A" push -q origin feat/A; row A done "$A"
[ "$(WC A)" = "removed $A" ] && pass "a done row whose work is pushed is removed" || fail "pushed ($(WC A))"
[ ! -d "$A" ] && [ "$(L get A worktree)" = "-" ] && pass "the folder is gone and the cell cleared" || fail "cell or folder left"
grep -q "STAR.A.removed worktree $A" "$H/sent.log" && pass "sent.log records the removal" || fail "sent.log line"
grep -q -- '--force' "$TMP/calls" && fail "removal used --force" || pass "never --force"

# dropped, with a commit that exists nowhere else: kept
B=$(wt B); commit "$B" b; row B dropped "$B"
[ "$(WC B)" = "kept $B: unpushed commits" ] && [ -d "$B" ] && pass "unpushed work is kept" || fail "unpushed ($(WC B))"

# done, uncommitted changes: kept
C=$(wt C); git -C "$C" push -q origin feat/C; echo x > "$C/scratch.txt"; row C done "$C"
[ "$(WC C)" = "kept $C: uncommitted changes" ] && pass "uncommitted changes are kept" || fail "dirty ($(WC C))"

# done, squash-merged and the remote branch deleted: HEAD is the recorded merged head, removed
D=$(wt D); commit "$D" d; row D done "$D" "$(git -C "$D" rev-parse --short HEAD)"
[ "$(WC D)" = "removed $D" ] && pass "a done row on its merged head is removed" || fail "merged head ($(WC D))"

# dropped with no commits of its own: contained in origin/main, removed
E=$(wt E); row E dropped "$E"
[ "$(WC E)" = "removed $E" ] && pass "a worktree with nothing of its own is removed" || fail "no own commits ($(WC E))"

# a row still in progress, the main checkout, a worktree another open row uses
F=$(wt F); row F queued "$F"
[ "$(WC F)" = "kept $F: row is queued" ] && pass "an open row keeps its worktree" || fail "queued ($(WC F))"
row M done "$APP"
[ "$(WC M)" = "kept $APP: the main checkout" ] && pass "the main checkout is never removed" || fail "main checkout ($(WC M))"
G=$(wt G); git -C "$G" push -q origin feat/G; row G done "$G"; row G2 babysit-queued "$G"
[ "$(WC G)" = "kept $G: in use by G2" ] && pass "a worktree another open row names is kept" || fail "in use ($(WC G))"

# already gone: pruned, cell cleared, none
N=$(wt N); row N done "$N"; rm -rf "$N"
[ "$(WC N)" = "none" ] && [ "$(L get N worktree)" = "-" ] && ! git -C "$APP" worktree list | grep -q "/N " && pass "a vanished folder is pruned and cleared" || fail "vanished ($(WC N))"
row Z done -
[ "$(WC Z)" = "none" ] && pass "a row with no worktree is none" || fail "no worktree"

# orca refusing: kept with its message, the cell untouched
O=$(wt O); git -C "$O" push -q origin feat/O; row O done "$O"
out=$(STUB_REFUSE=/O WC O)
[ "$out" = "kept $O: orca: worktree is locked" ] && [ "$(L get O worktree)" = "$O" ] && pass "an Orca refusal keeps it and says why" || fail "orca refusal ($out)"

WC nope >/dev/null 2>&1; [ $? -eq 4 ] && pass "an unknown item is 4" || fail "unknown item"
WC >/dev/null 2>&1; [ $? -eq 64 ] && pass "no item is 64" || fail "usage"

# evidence outlives the worktree (#73). docs/ is ignored, as it is in the projects STAR runs, so
# git status never counts the evidence as work that would be lost.
printf 'docs/\n' >> "$APP/.git/info/exclude"
EV=$(wt EV); git -C "$EV" push -q origin feat/EV; row EV done "$EV"
mkdir -p "$EV/docs/superpowers/evidence/2026-10-12-ev/shots"
echo report > "$EV/docs/superpowers/evidence/2026-10-12-ev/report.md"
echo png > "$EV/docs/superpowers/evidence/2026-10-12-ev/shots/a.png"
out=$(WC EV)
[ "$out" = "kept-evidence $H/evidence/EV/
removed $EV" ] && pass "evidence is copied into the STAR home before the worktree goes" || fail "evidence copy ($out)"
[ -f "$H/evidence/EV/2026-10-12-ev/report.md" ] && [ -f "$H/evidence/EV/2026-10-12-ev/shots/a.png" ] && [ ! -d "$EV" ] && pass "every evidence file is in the STAR home" || fail "evidence files missing"
EW=$(wt EW); git -C "$EW" push -q origin feat/EW; row EW done "$EW"
mkdir -p "$EW/docs/.superpowers/evidence/run"; echo r > "$EW/docs/.superpowers/evidence/run/report.md"
out=$(WC EW)
[ "$(printf '%s\n' "$out" | head -1)" = "kept-evidence $H/evidence/EW/" ] && [ -f "$H/evidence/EW/run/report.md" ] && pass "evidence under the dotted docsRoot is copied too" || fail "dotted docsRoot ($out)"
ER=$(wt ER); git -C "$ER" push -q origin feat/ER; row ER done "$ER"
mkdir -p "$ER/docs/superpowers/evidence/run" "$H/evidence/ER/run"
echo new > "$ER/docs/superpowers/evidence/run/report.md"; echo old > "$H/evidence/ER/run/report.md"
out=$(WC ER)
[ "$(printf '%s\n' "$out" | tail -1)" = "removed $ER" ] && [ "$(cat "$H/evidence/ER/run/report.md")" = new ] && pass "a copy into a folder an earlier attempt left (an Orca refusal) succeeds and refreshes it" || fail "copy over an earlier one ($out)"
EF=$(wt EF); git -C "$EF" push -q origin feat/EF; row EF done "$EF"
mkdir -p "$EF/docs/superpowers/evidence/run"; echo r > "$EF/docs/superpowers/evidence/run/report.md"
chmod 555 "$H/evidence"; out=$(WC EF); chmod 755 "$H/evidence"
case "$out" in
  "kept $EF: evidence copy failed: "*) [ -d "$EF" ] && [ "$(L get EF worktree)" = "$EF" ] && pass "a failed copy keeps the worktree and says why" || fail "a failed copy removed the worktree" ;;
  *) fail "failed copy ($out)" ;;
esac

# lane d: specs and plans are kept, dependency folders are skipped and listed, a big folder says its size
BD=$(wt BD); git -C "$BD" push -q origin feat/BD; row BD done "$BD"
mkdir -p "$BD/docs/superpowers/specs" "$BD/docs/superpowers/plans" "$BD/docs/superpowers/evidence/run"
echo s > "$BD/docs/superpowers/specs/2026-10-20-x.md"; echo p > "$BD/docs/superpowers/plans/2026-10-20-x.md"; echo rp > "$BD/docs/superpowers/plans/review-plan.md"
echo r > "$BD/docs/superpowers/evidence/run/report.md"
out=$(WC BD)
[ "$out" = "kept-builds $H/builds/BD/
kept-evidence $H/evidence/BD/
removed $BD" ] && pass "specs and plans are kept before the evidence line" || fail "builds + evidence ($out)"
[ -f "$H/builds/BD/specs/2026-10-20-x.md" ] && [ -f "$H/builds/BD/plans/2026-10-20-x.md" ] && [ -f "$H/builds/BD/plans/review-plan.md" ] && pass "the spec, plan and review plan are in the STAR home" || fail "build files missing"
BN=$(wt BN); git -C "$BN" push -q origin feat/BN; row BN done "$BN"
mkdir -p "$BN/docs/superpowers/specs"; echo s > "$BN/docs/superpowers/specs/a.md"
out=$(WC BN)
[ "$out" = "kept-builds $H/builds/BN/
removed $BN" ] && pass "specs without evidence print kept-builds then removed" || fail "builds only ($out)"
SK=$(wt SK); git -C "$SK" push -q origin feat/SK; row SK done "$SK"
E="$SK/docs/superpowers/evidence/run"
mkdir -p "$E/tools/node_modules/pkg" "$E/tools/.build" "$E/obj"
echo report > "$E/report.md"; printf 'abcd' > "$E/tools/node_modules/pkg/index.js"; printf 'xyz' > "$E/tools/.build/x"; printf 'ob' > "$E/obj/a.o"
WC SK >/dev/null
D="$H/evidence/SK/run"
[ -f "$D/report.md" ] && [ ! -e "$D/tools/node_modules" ] && [ ! -e "$D/tools/.build" ] && [ ! -e "$D/obj/a.o" ] && pass "dependency folders and object files stay out of evidence" || fail "skip-listed paths were copied"
[ "$(sort "$H/evidence/SK/skipped.txt")" = "$(printf 'run/obj/a.o\t2\nrun/tools/.build\t3\nrun/tools/node_modules\t4\n')" ] && pass "skipped.txt lists each skipped path with its bytes" || fail "skipped.txt ($(cat "$H/evidence/SK/skipped.txt"))"
NK=$(wt NK); git -C "$NK" push -q origin feat/NK; row NK done "$NK"
[ "$(WC NK)" = "removed $NK" ] && pass "a worktree with nothing to keep prints removed alone" || fail "nothing to keep"
SZ=$(wt SZ); git -C "$SZ" push -q origin feat/SZ; row SZ done "$SZ"
mkdir -p "$SZ/docs/superpowers/evidence/run"; echo r > "$SZ/docs/superpowers/evidence/run/report.md"
out=$(JUEL_EVIDENCE_GB_LIMIT=0 WC SZ)
[ "$out" = "kept-evidence $H/evidence/SZ/
evidence-size SZ 0.0 GB
removed $SZ" ] && pass "evidence over the limit prints its size" || fail "size line ($out)"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
