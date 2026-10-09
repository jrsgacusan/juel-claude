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
H=$(sh "$S/star-home.sh" --cwd "$APP" init)
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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
