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

# lane d: --evidence-report and --evidence-prune
rm -rf "$H/evidence"; mkdir -p "$H/evidence/A/run/node_modules" "$H/evidence/A/run/deep" "$H/evidence/B/obj"
printf '0123456789' > "$H/evidence/A/run/node_modules/x"; echo report > "$H/evidence/A/run/report.md"; printf '12345' > "$H/evidence/B/obj/a.o"
mkdir -p "$H/evidence/A/run/deep/node_modules/a/node_modules"; : > "$H/evidence/A/run/deep/node_modules/a/node_modules/y"
want=$(printf 'A\trun/deep/node_modules\t0\nA\trun/node_modules\t10\nB\tobj/a.o\t5\ntotal 3 gb=0.0\n')
out=$(WC --evidence-report)
[ "$out" = "$want" ] && [ -f "$H/evidence/A/run/node_modules/x" ] && pass "--evidence-report lists skip-listed paths once at the outer folder and removes nothing" || fail "report ($out)"
rm -rf "$H/evidence/A/run/deep"
out=$(WC --evidence-report)
[ "$out" = "$(printf 'A\trun/node_modules\t10\nB\tobj/a.o\t5\ntotal 2 gb=0.0\n')" ] && pass "the report sorts by item then path" || fail "report 2 ($out)"
out=$(WC --evidence-prune)
[ "$out" = "pruned 2 gb=0.0" ] && [ ! -e "$H/evidence/A/run/node_modules" ] && [ ! -e "$H/evidence/B/obj/a.o" ] && [ -f "$H/evidence/A/run/report.md" ] && [ "$(tail -1 "$H/evidence/A/skipped.txt")" = "$(printf 'run/node_modules\t10')" ] && pass "--evidence-prune removes them and records them in skipped.txt" || fail "prune ($out)"
rm -rf "$H/evidence"
[ "$(WC --evidence-report)" = "total 0 gb=0.0" ] && pass "a home with none prints total 0" || fail "empty report"
WC --evidence-report X >/dev/null 2>&1; [ $? -eq 64 ] && pass "--evidence-report with an item is 64" || fail "report usage"

# audit lane f: the new skip classes
FC=$(wt FC); git -C "$FC" push -q origin feat/FC; row FC done "$FC"
E="$FC/docs/superpowers/evidence/run"
mkdir -p "$E/tmp" "$E/build.app" "$E/x.mlmodelc"
for f in app.dmg pack-1.pack lib.a model.gguf w.safetensors data.parquet blob.bin; do printf 'abcde' > "$E/$f"; done
printf 't' > "$E/tmp/t"; printf 'b' > "$E/build.app/b"; printf 'm' > "$E/x.mlmodelc/m"
python3 -c "f=open('$E/take.wav','wb'); f.truncate(12*1024*1024)"; printf '1234567890' > "$E/beep.wav"
echo report > "$E/report.md"; echo png > "$E/shot.png"; echo webm > "$E/recording.webm"
WC FC >/dev/null
D="$H/evidence/FC/run"
[ "$(ls "$D" | sort | tr '\n' ' ')" = "beep.wav recording.webm report.md shot.png " ] && pass "only proof is copied: packages, models, build output, bundles and large audio stay out" || fail "copied set ($(ls "$D" | tr '\n' ' '))"
want=$(printf 'run/app.dmg\t5\nrun/blob.bin\t5\nrun/build.app\t1\nrun/data.parquet\t5\nrun/lib.a\t5\nrun/model.gguf\t5\nrun/pack-1.pack\t5\nrun/take.wav\t12582912\nrun/tmp\t1\nrun/w.safetensors\t5\nrun/x.mlmodelc\t1\n')
[ "$(sort "$H/evidence/FC/skipped.txt")" = "$(printf '%s' "$want" | sort)" ] && pass "skipped.txt lists each new class with its bytes" || fail "skipped.txt for new classes ($(sort "$H/evidence/FC/skipped.txt"))"
# report and prune on a folder already under <H>/evidence/
rm -rf "$H/evidence"; mkdir -p "$H/evidence/Q/run/tmp"
Q="$H/evidence/Q/run"
printf 'abcde' > "$Q/blob.bin"; printf 'x' > "$Q/tmp/t"; python3 -c "f=open('$Q/take.wav','wb'); f.truncate(12*1024*1024)"
printf '1234567890' > "$Q/beep.wav"; echo png > "$Q/shot.png"; echo webm > "$Q/recording.webm"
out=$(WC --evidence-report)
[ "$(printf '%s\n' "$out" | grep -c '^Q')" = 3 ] && printf '%s\n' "$out" | grep -q "^Q.run/take.wav.12582912$" && printf '%s\n' "$out" | grep -q "^Q.run/blob.bin.5$" && printf '%s\n' "$out" | grep -q "^Q.run/tmp.1$" && pass "--evidence-report lists the new classes" || fail "report new classes ($out)"
out=$(WC --evidence-prune)
[ "$out" = "pruned 3 gb=0.0" ] && [ -f "$Q/beep.wav" ] && [ -f "$Q/shot.png" ] && [ -f "$Q/recording.webm" ] && [ ! -e "$Q/take.wav" ] && [ ! -e "$Q/blob.bin" ] && [ ! -e "$Q/tmp" ] && pass "--evidence-prune removes exactly those and never proof" || fail "prune new classes ($out)"
# evidence-size counts only what was copied
FZ=$(wt FZ); git -C "$FZ" push -q origin feat/FZ; row FZ done "$FZ"
mkdir -p "$FZ/docs/superpowers/evidence/run"; python3 -c "f=open('$FZ/docs/superpowers/evidence/run/take.wav','wb'); f.truncate(12*1024*1024)"; echo r > "$FZ/docs/superpowers/evidence/run/report.md"
out=$(JUEL_EVIDENCE_GB_LIMIT=0.005 WC FZ)
case "$out" in *evidence-size*) fail "evidence-size counted a skipped file ($out)" ;; *) pass "the evidence-size line counts only what was copied" ;; esac

# audit lane f: duplicates are hardlinked, older runs keep only text
FD=$(wt FD); git -C "$FD" push -q origin feat/FD; row FD done "$FD"
E="$FD/docs/superpowers/evidence"
mkdir -p "$E/a" "$E/b"; head -c 2048 /dev/zero > "$E/a/fake-mic.wav"; head -c 2048 /dev/zero > "$E/b/fake-mic.wav"
WC FD >/dev/null
ia=$(python3 -c "import os;print(os.stat('$H/evidence/FD/a/fake-mic.wav').st_ino)"); ib=$(python3 -c "import os;print(os.stat('$H/evidence/FD/b/fake-mic.wav').st_ino)")
[ -f "$H/evidence/FD/a/fake-mic.wav" ] && [ "$ia" = "$ib" ] && pass "the same file at two paths is hardlinked" || fail "hardlink ($ia $ib)"
FV=$(wt FV); git -C "$FV" push -q origin feat/FV; row FV done "$FV"
E="$FV/docs/superpowers/evidence"
for d in 2026-10-12-x 2026-10-12-x-v2; do mkdir -p "$E/$d"; echo "r $d" > "$E/$d/report.md"; echo "p $d" > "$E/$d/shot.png"; echo "{\"$d\":1}" > "$E/$d/ledger.json"; done
WC FV >/dev/null
V="$H/evidence/FV"
[ -f "$V/2026-10-12-x-v2/report.md" ] && [ -f "$V/2026-10-12-x-v2/shot.png" ] && [ -f "$V/2026-10-12-x-v2/ledger.json" ] && [ -f "$V/2026-10-12-x/report.md" ] && [ -f "$V/2026-10-12-x/ledger.json" ] && [ ! -e "$V/2026-10-12-x/shot.png" ] && pass "the newest run keeps everything, the older one only its text files" || fail "older runs ($(find "$V" -type f | sort | tr '\n' ' '))"
FW=$(wt FW); git -C "$FW" push -q origin feat/FW; row FW done "$FW"
E="$FW/docs/superpowers/evidence"
for d in 2026-10-12-x 2026-10-12-x-v2; do mkdir -p "$E/$d"; echo "p $d" > "$E/$d/shot.png"; done
echo r > "$E/2026-10-12-x/report.md"; echo j > "$E/2026-10-12-x-v2/ledger.json"
WC FW >/dev/null
[ -f "$H/evidence/FW/2026-10-12-x/shot.png" ] && [ -f "$H/evidence/FW/2026-10-12-x-v2/shot.png" ] && pass "with no report.md in the newest run, every run is copied whole" || fail "unfinished newest ($(find "$H/evidence/FW" -type f | sort | tr '\n' ' '))"
mkdir -p "$H/evidence/FP/2026-10-12-x" "$H/evidence/FP/2026-10-12-x-v2"
echo r > "$H/evidence/FP/2026-10-12-x/report.md"; echo png > "$H/evidence/FP/2026-10-12-x/shot.png"; echo r > "$H/evidence/FP/2026-10-12-x-v2/report.md"
out=$(WC --evidence-prune)
case "$out" in "pruned 0 "*) [ -f "$H/evidence/FP/2026-10-12-x/shot.png" ] && pass "--evidence-prune never applies the older-run rule" || fail "prune removed a screenshot" ;; *) fail "prune on a pair ($out)" ;; esac

# audit lane f: a finished item's codex transcripts are gzipped
RV="$H/reviews/app"; mkdir -p "$RV"
mk_reviews() { for f in GZ-r1.log GZ-r2.log GZ-r2-error-1.log GZ-r1.md GZ-r1.raw.md GZ-r1-fix.md GZ-hosted.log GZ-gate.log other-r1.log; do echo "$f body" > "$RV/$f"; done; }
mk_reviews
GZ=$(wt GZ); git -C "$GZ" push -q origin feat/GZ; row GZ done "$GZ"
out=$(WC GZ)
[ "$(printf '%s\n' "$out" | head -1)" = "reviews-gzipped GZ 3" ] && [ "$(printf '%s\n' "$out" | tail -1)" = "removed $GZ" ] && pass "reviews-gzipped is printed before the final line" || fail "gzipped line ($out)"
ok=1; for f in GZ-r1.log GZ-r2.log GZ-r2-error-1.log; do { [ -f "$RV/$f.gz" ] && [ ! -e "$RV/$f" ] && gzip -t "$RV/$f.gz"; } || ok=0; done
for f in GZ-r1.md GZ-r1.raw.md GZ-r1-fix.md GZ-hosted.log GZ-gate.log other-r1.log; do [ "$(cat "$RV/$f")" = "$f body" ] || ok=0; done
[ "$ok" = 1 ] && [ "$(gzip -dc "$RV/GZ-r1.log.gz")" = "GZ-r1.log body" ] && pass "the three transcripts are gzipped, every other file is untouched" || fail "gzip result"
out=$(WC GZ)
case "$out" in *reviews-gzipped*) fail "a second run printed reviews-gzipped ($out)" ;; *) pass "a second run prints no reviews-gzipped line" ;; esac
row GN done "$TMP/no-such-folder"; echo x > "$RV/GN-r1.log"
out=$(WC GN)
[ "$out" = "reviews-gzipped GN 1
none" ] && [ -f "$RV/GN-r1.log.gz" ] && pass "a folder that is already gone still gzips the transcripts" || fail "gone folder ($out)"
row GB building "$TMP/no-such-folder"; echo x > "$RV/GB-r1.log"
WC GB >/dev/null; [ -f "$RV/GB-r1.log" ] && [ ! -e "$RV/GB-r1.log.gz" ] && pass "a building row's transcripts are untouched" || fail "building row gzipped"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
