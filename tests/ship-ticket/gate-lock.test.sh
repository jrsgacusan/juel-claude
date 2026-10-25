#!/bin/sh
# Runs skills/ship-ticket/gate-lock.sh against a scratch lock path.
# Usage: sh tests/ship-ticket/gate-lock.test.sh   (exit 0 = all cases pass)
set -u
# a gate that runs this suite inside gate-lock.sh passes its JUEL_GATE_LOCK* variables down (#132):
# this suite sets up its own, so every inherited one is dropped first
for v in $(env | sed -n 's/^\(JUEL_GATE_LOCK[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/ship-ticket/gate-lock.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL gate-lock.sh missing"; exit 1; }

LOCK="$TMP/gate.lock"
export JUEL_GATE_LOCK="$LOCK" JUEL_GATE_LOCK_POLL=0.2
free() { sh "$SCRIPT" --holder probe --wait-max 0 -- true 2>/dev/null; }

# 1. A free lock: the command runs, its exit code passes through, the lock is free after.
sh "$SCRIPT" --holder t1 -- sh -c 'exit 3'; rc=$?
[ "$rc" -eq 3 ] && pass "exit code passes through" || fail "exit code passes through ($rc)"
free && pass "lock free after the command" || fail "lock free after the command"

# 2. Held by a running gate: give up after --wait-max with exit 75 and say who holds it.
sh "$SCRIPT" --holder first -- sh -c "sleep 30; echo late > '$TMP/first.late'" &
live=$!
sleep 0.5
err=$(sh "$SCRIPT" --holder t2 --wait-max 1 -- sh -c "echo ran > '$TMP/t2.ran'" 2>&1); rc=$?
[ "$rc" -eq 75 ] && [ ! -e "$TMP/t2.ran" ] && pass "busy lock returns 75 without running the command" || fail "busy lock returns 75 ($rc)"
case "$err" in *"busy, held by first"*) pass "busy message names the holder" ;; *) fail "busy message ($err)" ;; esac
# 3. --wait-max is honoured even with a long poll interval.
t0=$(date +%s); JUEL_GATE_LOCK_POLL=30 sh "$SCRIPT" --holder p --wait-max 1 -- true 2>/dev/null; rc=$?; t1=$(date +%s)
[ "$rc" -eq 75 ] && [ $((t1 - t0)) -le 3 ] && pass "wait deadline honoured with a long poll" || fail "wait deadline overshot (rc=$rc, $((t1 - t0))s)"
# 4. Killing the wrapper stops the command and frees the lock.
kill -TERM "$live"; wait "$live" 2>/dev/null
sleep 0.3
free && pass "lock free when the holder is killed" || fail "lock free when the holder is killed"
pgrep -f "$TMP/first.late" >/dev/null && fail "TERM left the gate command running" || pass "TERM stops the gate command"
# A signal that lands while the command is being started still stops it: never a running
# command with the lock already released.
n=0; while [ $n -lt 8 ]; do n=$((n + 1))
  sh "$SCRIPT" --holder race -- sh -c "sleep 5; echo late > '$TMP/race.late'" 2>/dev/null &
  r=$!; sleep 0.0$n; kill -TERM "$r" 2>/dev/null; wait "$r" 2>/dev/null
done
sleep 0.3
pgrep -f "$TMP/race.late" >/dev/null && fail "a signal at start left a command running" || pass "a signal at start never leaves a command running"

# 5. What a dead holder left in the lock file means nothing: the kernel lock is what counts,
#    so a recycled pid or process group can never keep the lock busy.
printf 'ghost pid=%s pgid=%s\n' "$$" "$$" > "$LOCK"
sh "$SCRIPT" --holder t5 --wait-max 0 -- true 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && pass "a leftover holder line with live pids does not block" || fail "leftover holder line blocked ($rc)"

# 6. Two gates never overlap: the second starts after the first ends.
sh "$SCRIPT" --holder a -- sh -c "date +%s > '$TMP/a.start'; sleep 2; date +%s > '$TMP/a.end'" &
first=$!
sleep 0.5
sh "$SCRIPT" --holder b --wait-max 10 -- sh -c "date +%s > '$TMP/b.start'"
wait "$first"
[ "$(cat "$TMP/b.start")" -ge "$(cat "$TMP/a.end")" ] && pass "second gate waits for the first" || fail "gates overlapped"

# 7. Twenty waiters polling every 10 ms: every one runs, no two at the same time.
: > "$TMP/log"
i=0; while [ $i -lt 20 ]; do i=$((i + 1))
  JUEL_GATE_LOCK_POLL=0.01 sh "$SCRIPT" --holder "w$i" --wait-max 60 -- sh -c "echo 'start $i' >> '$TMP/log'; sleep 0.05; echo 'end $i' >> '$TMP/log'" 2>/dev/null &
done; wait
python3 - "$TMP/log" <<'PY' && pass "20 waiters at 10 ms: all ran, none overlapped" || fail "contention: overlap or a lost run"
import sys
active, starts = None, 0
for line in open(sys.argv[1]):
    kind, who = line.split()
    if kind == "start":
        assert active is None, f"{who} started while {active} ran"
        active, starts = who, starts + 1
    else:
        assert active == who, f"{who} ended but {active} was running"
        active = None
assert starts == 20 and active is None, starts
PY

# 8. kill -9 on the wrapper: the gate command keeps running, so the lock must stay held until it ends.
sh "$SCRIPT" --holder v -- sh -c "sleep 3; date +%s > '$TMP/v.end'" &
v=$!
sleep 0.5
kill -9 "$v" 2>/dev/null; wait "$v" 2>/dev/null
sh "$SCRIPT" --holder w --wait-max 10 -- sh -c "date +%s > '$TMP/w.start'"
[ -f "$TMP/v.end" ] && [ "$(cat "$TMP/w.start")" -ge "$(cat "$TMP/v.end")" ] && pass "SIGKILLed wrapper's command still holds the lock" || fail "lock taken while the killed wrapper's command ran"

# 9. SIGHUP (terminal closed) stops the whole command group and frees the lock.
sh "$SCRIPT" --holder h -- sh -c "sleep 30; echo late > '$TMP/h.late'" 2> "$TMP/h.err" &
h=$!
sleep 0.5
kill -HUP "$h"; wait "$h" 2>/dev/null; rc=$?
sleep 0.5
free && pass "SIGHUP frees the lock" || fail "SIGHUP frees the lock"
[ "$rc" -eq 129 ] && [ ! -s "$TMP/h.err" ] && pass "a signalled wrapper exits 128+n and prints nothing" || fail "signalled wrapper (rc=$rc): $(head -3 "$TMP/h.err")"
sleep 1; [ ! -f "$TMP/h.late" ] && pass "SIGHUP stops the gate command" || fail "SIGHUP left the gate command running"

# 10. Any holder label is fine: spaces and an empty label used to leak the lock.
sh "$SCRIPT" --holder 'with space' -- true && free && pass "a holder label with a space" || fail "holder label with a space leaked the lock"
sh "$SCRIPT" --holder '' -- true && free && pass "an empty holder label" || fail "empty holder label leaked the lock"

# 11. Bad usage is exit 64 and runs nothing.
for args in "--wait-max xyz" "--wait-max -1" "--holder" "--bogus 1"; do
  # shellcheck disable=SC2086
  sh "$SCRIPT" $args -- sh -c "echo ran > '$TMP/bad.ran'" 2>/dev/null; rc=$?
  [ "$rc" -eq 64 ] && [ ! -e "$TMP/bad.ran" ] && pass "bad usage ($args) is exit 64" || fail "bad usage ($args) gave $rc"
done
sh "$SCRIPT" --holder x 2>/dev/null; [ $? -eq 64 ] && pass "no command is exit 64" || fail "no command"

# 12. A command that cannot start is 127 and the lock is free.
sh "$SCRIPT" --holder n -- /no/such/gate-command 2>/dev/null; rc=$?
[ "$rc" -eq 127 ] && free && pass "a missing command is 127 and frees the lock" || fail "missing command ($rc)"

# 13. A child the command left running in its group does not hold the wrapper forever:
#     after the drain time it is stopped and the lock is freed.
t0=$(date +%s)
JUEL_GATE_LOCK_DRAIN_SECONDS=1 sh "$SCRIPT" --holder d -- sh -c "(sleep 30; echo late > '$TMP/d.late') & exit 0" 2>/dev/null; rc=$?
t1=$(date +%s)
[ "$rc" -eq 0 ] && [ $((t1 - t0)) -le 5 ] && free && pass "a leftover child is stopped after the drain time" || fail "leftover child held the wrapper (rc=$rc, $((t1 - t0))s)"
sleep 0.3; pgrep -f "$TMP/d.late" >/dev/null && fail "leftover child still running" || pass "leftover child is gone"

# 14. A child that detached into its own session is not part of the gate: the lock is free when
#     the command returns, even though the daemon inherited the lock's file descriptor.
sh "$SCRIPT" --holder s -- python3 -c "
import os, time
if os.fork(): os._exit(0)
os.setsid()
time.sleep(4)
"
free && pass "a detached daemon does not keep the lock" || fail "detached daemon kept the lock"

# 15. The script does not depend on the invoking shell's job control.
if command -v zsh >/dev/null 2>&1; then
  zsh "$SCRIPT" --holder z -- sh -c "echo ran > '$TMP/z.ran'" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] && [ -f "$TMP/z.ran" ] && pass "runs under zsh" || fail "zsh skipped the command ($rc)"
fi
bash "$SCRIPT" --holder z -- true && pass "runs under bash" || fail "bash"

# Second stress pass
# 18. The lock file is replaced while a gate holds it: a waiter that already opened the old file
#     must not run on it, and the default lock lives where git clean and a sandbox cannot break it.
sh "$SCRIPT" --holder n1 -- sh -c "sh '$SCRIPT' --holder n2 --wait-max 2 -- sh -c 'echo inner > $TMP/nest.ran'"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$TMP/nest.ran" ] && pass "a gate inside a gate on the same lock runs, it does not wait for itself" || fail "nested gate (rc=$rc)"
# (without JUEL_GATE_TEST_DIR the default lock is the real machine-wide one: never wait for it here; busy means a real gate runs.
# The probe may land in any real slot, so it looks for its own token in the default lock's slot files.)
DL="${JUEL_GATE_TEST_DIR:-/tmp}/juel.gate.$(id -u).lock"
d=$(cd "$TMP" && mkdir -p nogit2 && cd nogit2 && env -u JUEL_GATE_LOCK sh "$SCRIPT" --holder loc-probe --wait-max 0 -- sh -c 'for f in "$@"; do grep -q "^loc-probe .*token=$JUEL_GATE_LOCK_HELD" "$f" 2>/dev/null && { echo "$f"; exit 0; }; done; exit 1' sh "$DL" "$DL.2" "$DL.3" "$DL.4" 2>/dev/null); rc=$?
case "$rc:$d" in "0:$DL"|"0:$DL.2"|"0:$DL.3"|"0:$DL.4") pass "the default lock is one file per user under /tmp, in or out of a git repo" ;; 75:*) pass "default lock path (skipped: a real gate is running)" ;; *) fail "default lock path (rc=$rc $d)" ;; esac
now() { python3 -c 'import time; print(time.time())'; }
# A holds the lock; B waits on that file; the file is deleted; C arrives and queues behind B (#97).
# When A ends, B gets the old file's lock, must notice the path no longer names it, and only then
# run, on the new file: never beside A. C runs after B.
sh "$SCRIPT" --holder A -- sh -c "sleep 1.5; python3 -c 'import time; print(time.time())' > '$TMP/a.end2'" &
pa=$!; sleep 0.4
sh "$SCRIPT" --holder B --wait-max 20 -- sh -c "python3 -c 'import time; print(time.time())' > '$TMP/b.start2'" &
pb=$!; sleep 0.4
rm -f "$LOCK"
sh "$SCRIPT" --holder C --wait-max 20 -- sh -c "python3 -c 'import time; print(time.time())' > '$TMP/c.start2'" &
pc=$!
wait "$pa" "$pb" "$pc"
python3 -c 'import sys; a, b, c = (float(open(p).read()) for p in sys.argv[1:]); sys.exit(0 if a <= b <= c else 1)' "$TMP/a.end2" "$TMP/b.start2" "$TMP/c.start2" && pass "a waiter on a deleted lock file waits for the gate on the old file, then runs before the gate queued behind it" || fail "waiter ran beside the gate on the deleted lock file, or out of turn"
free && pass "the lock still works after its file was deleted" || fail "lock unusable after its file was deleted"

# Final pass
# 19. The nested shortcut is for a process inside a gate that is still running, proven by the
#     token in the lock file: a stale value inherited by a later, unrelated caller means nothing.
old=$(sh "$SCRIPT" --holder t -- sh -c 'printf %s "$JUEL_GATE_LOCK_HELD"')
sh "$SCRIPT" --holder live2 -- sleep 3 &
l2=$!; sleep 0.5
JUEL_GATE_LOCK_HELD="$old" sh "$SCRIPT" --holder stale --wait-max 0 -- sh -c "echo ran > '$TMP/stale.ran'" 2>/dev/null; rc=$?
[ "$rc" -eq 75 ] && [ ! -e "$TMP/stale.ran" ] && pass "a stale nested marker does not skip the lock" || fail "stale JUEL_GATE_LOCK_HELD ran without the lock (rc=$rc)"
JUEL_GATE_LOCK_HELD="$LOCK" sh "$SCRIPT" --holder path --wait-max 0 -- true 2>/dev/null; [ $? -eq 75 ] && pass "the lock's path alone is not a nested marker" || fail "path as marker skipped the lock"
wait "$l2"
ln -s "$TMP" "$TMP.alias"
sh "$SCRIPT" --holder outer -- sh -c "JUEL_GATE_LOCK='$TMP.alias/gate.lock' sh '$SCRIPT' --holder inner --wait-max 1 -- sh -c 'echo inner > $TMP/alias.ran'"; rc=$?
rm -f "$TMP.alias"
[ "$rc" -eq 0 ] && [ -f "$TMP/alias.ran" ] && pass "a nested gate that spells the same lock file differently still runs" || fail "nested gate on an aliased path (rc=$rc)"
# 20. A gate that never ends is stopped at --max-seconds and says so with its own exit code.
t0=$(date +%s); sh "$SCRIPT" --holder hung --max-seconds 1 -- sh -c "sleep 60; echo late > '$TMP/hung.late'" 2> "$TMP/hung.err"; rc=$?; t1=$(date +%s)
[ "$rc" -eq 124 ] && [ $((t1 - t0)) -le 10 ] && grep -q 'ran past' "$TMP/hung.err" && free && pass "a hung gate is stopped at --max-seconds with exit 124" || fail "hung gate (rc=$rc, $((t1 - t0))s)"
sleep 0.3; pgrep -f "$TMP/hung.late" >/dev/null && fail "hung gate's command still running" || pass "the hung gate's command is gone"
# 21. A gate that cannot run at all is exit 71: never the same code as a red test suite.
mkfifo "$TMP/fifo.lock"; t0=$(date +%s); JUEL_GATE_LOCK="$TMP/fifo.lock" sh "$SCRIPT" --holder f --wait-max 30 -- true 2>/dev/null; rc=$?; t1=$(date +%s)
[ "$rc" -eq 71 ] && [ $((t1 - t0)) -le 5 ] && pass "a lock path that is not a regular file is exit 71 at once" || fail "FIFO lock path (rc=$rc, $((t1 - t0))s)"
mkdir "$TMP/dir.lock"; JUEL_GATE_LOCK="$TMP/dir.lock" sh "$SCRIPT" --holder d -- true 2>/dev/null; [ $? -eq 71 ] && pass "a lock path that cannot be opened is exit 71" || fail "directory lock path"
sh "$SCRIPT" --holder m --max-seconds nope -- true 2>/dev/null; [ $? -eq 64 ] && pass "a bad --max-seconds is exit 64" || fail "bad --max-seconds"
# 22. The command's group is what holds a killed wrapper's lock: a child of the command counts.
sh "$SCRIPT" --holder g -- sh -c "(sleep 2; date +%s > '$TMP/g.end') & wait" &
g=$!; sleep 0.5; kill -9 "$g" 2>/dev/null; wait "$g" 2>/dev/null
sh "$SCRIPT" --holder g2 --wait-max 10 -- sh -c "date +%s > '$TMP/g2.start'"
[ -f "$TMP/g.end" ] && [ "$(cat "$TMP/g2.start")" -ge "$(cat "$TMP/g.end")" ] && pass "a grandchild keeps a killed wrapper's lock held" || fail "lock freed while a grandchild still ran"

sh "$SCRIPT" --holder z0 --max-seconds 0 -- sh -c "sleep 1; echo ran > '$TMP/z0.ran'"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$TMP/z0.ran" ] && pass "--max-seconds 0 means no time limit" || fail "--max-seconds 0 killed the gate (rc=$rc)"

# lane e: #89 a gate that waits for the lock says so in the worker's progress log
# 23. A free lock writes no progress line.
rm -f "$TMP/p.free"
sh "$SCRIPT" --holder pf --progress "$TMP/p.free" -- true; rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$TMP/p.free" ] && pass "#89 a free lock writes no progress line" || fail "#89 free lock wrote a progress line (rc=$rc)"
# 24. A gate that waits appends a line when the wait starts and again every interval, naming the holder.
sh "$SCRIPT" --holder holderA -- sleep 2.5 &
ha=$!; sleep 0.4
JUEL_GATE_LOCK_PROGRESS_SECONDS=1 sh "$SCRIPT" --holder waiterB --progress "$TMP/p.log" --wait-max 20 -- true; rc=$?
wait "$ha"
n=$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z regression-gate gate-lock waiting, held by holderA$' "$TMP/p.log" 2>/dev/null)
all=$(wc -l < "$TMP/p.log" 2>/dev/null | tr -d ' ')
[ "$rc" -eq 0 ] && [ "${n:-0}" -ge 2 ] && [ "${all:-0}" -eq "${n:-0}" ] && pass "#89 a waiting gate writes a progress line on entry and every interval" || fail "#89 progress lines (rc=$rc n=${n:-0} all=${all:-0}: $(cat "$TMP/p.log" 2>/dev/null))"
# 25. The line is appended: what the log already held stays.
printf 'earlier line\n' > "$TMP/p2.log"
sh "$SCRIPT" --holder holderC -- sleep 1 &
hc=$!; sleep 0.4
sh "$SCRIPT" --holder waiterD --progress "$TMP/p2.log" --wait-max 20 -- true
wait "$hc"
[ "$(head -1 "$TMP/p2.log")" = "earlier line" ] && grep -q 'regression-gate gate-lock waiting, held by holderC$' "$TMP/p2.log" && pass "#89 progress lines are appended" || fail "#89 progress log overwritten ($(cat "$TMP/p2.log"))"
# 26. A progress file that cannot be written (a missing folder, a read-only folder, a directory)
#     changes nothing: the gate waits, runs, keeps its exit status, and prints nothing about it.
mkdir -p "$TMP/ro"; chmod 555 "$TMP/ro"
for p in "$TMP/no/such/folder/p.log" "$TMP/ro/p.log" "$TMP"; do
  rm -f "$TMP/f.ran"
  sh "$SCRIPT" --holder holderE -- sleep 1 &
  he=$!; sleep 0.4
  sh "$SCRIPT" --holder waiterF --progress "$p" --wait-max 20 -- sh -c "echo ran > '$TMP/f.ran'; exit 3" 2> "$TMP/f.err"; rc=$?
  wait "$he"
  [ "$rc" -eq 3 ] && [ -f "$TMP/f.ran" ] && [ ! -s "$TMP/f.err" ] && [ ! -e "$TMP/no" ] && pass "#89 an unwritable progress path ($p) changes nothing" || fail "#89 unwritable progress path $p (rc=$rc: $(head -2 "$TMP/f.err"))"
done
chmod 755 "$TMP/ro"
# 27. --progress needs a value.
sh "$SCRIPT" --progress -- true 2>/dev/null; [ $? -eq 64 ] && pass "#89 --progress without a value is exit 64" || fail "#89 --progress usage"

# lane b: #97 waiters start in arrival order, in up to 4 slots, and --wait-max counts from the last move
# until_ok <test...>: retry a check every 50 ms for up to 5 s (a barrier, never a fixed sleep)
until_ok() { _u=0; until "$@"; do _u=$((_u + 1)); [ "$_u" -ge 100 ] && return 1; sleep 0.05; done; }
tickets() { ls "$LOCK.q" 2>/dev/null | grep -c '^[0-9]'; }
cat > "$TMP/at" <<'EOF'
python3 -c 'import sys, time; open(sys.argv[1], "w").write("%r\n" % time.time())' "$1"
EOF
# in_order <file>...: the times the files hold never go down
in_order() { python3 -c 'import sys; t = [float(open(p).read()) for p in sys.argv[1:]]; sys.exit(0 if t == sorted(t) else 1)' "$@" 2>/dev/null; }
# 28. B queues first and polls every 1.5 s; C queues second and polls every 20 ms. When A ends,
#     B still starts first. D arrives while the slot is free and B has not polled yet: it queues
#     behind B and C instead of taking the slot. (A waiter's first progress line is the barrier:
#     it is written once the waiter holds its ticket.)
sh "$SCRIPT" --holder A -- sh -c "sleep 1; sh '$TMP/at' '$TMP/q.a.end'" &
qa=$!
until_ok test -s "$LOCK"
JUEL_GATE_LOCK_POLL=1.5 sh "$SCRIPT" --holder B --progress "$TMP/q.b.wait" --wait-max 20 -- sh "$TMP/at" "$TMP/q.b.start" &
qb=$!
until_ok test -s "$TMP/q.b.wait"
JUEL_GATE_LOCK_POLL=0.02 sh "$SCRIPT" --holder C --progress "$TMP/q.c.wait" --wait-max 20 -- sh "$TMP/at" "$TMP/q.c.start" &
qc=$!
until_ok test -s "$TMP/q.c.wait"
until_ok test -s "$TMP/q.a.end"
until_ok test ! -s "$LOCK"
JUEL_GATE_LOCK_POLL=0.02 sh "$SCRIPT" --holder D --wait-max 20 -- sh "$TMP/at" "$TMP/q.d.start" &
qd=$!
wait "$qa" "$qb" "$qc" "$qd"
in_order "$TMP/q.a.end" "$TMP/q.b.start" "$TMP/q.c.start" "$TMP/q.d.start" && pass "#97 waiters start in arrival order, whatever their poll interval" || fail "#97 arrival order (A end, B, C, D: $(cat "$TMP/q.a.end" "$TMP/q.b.start" "$TMP/q.c.start" "$TMP/q.d.start" 2>/dev/null | tr '\n' ' '))"
[ "$(tickets)" -eq 0 ] && pass "#97 every ticket is gone once its waiter ran" || fail "#97 tickets left: $(ls "$LOCK.q")"
# 29. A waiter killed with kill -9 while queued blocks no one: the waiter behind it deletes its
#     ticket and starts as soon as the slot is free.
sh "$SCRIPT" --holder A -- sh -c "sleep 1; sh '$TMP/at' '$TMP/k.a.end'" &
ka=$!
until_ok test -s "$LOCK"
sh "$SCRIPT" --holder K --progress "$TMP/k.k.wait" --wait-max 20 -- sh "$TMP/at" "$TMP/k.k.start" &
kk=$!
until_ok test -s "$TMP/k.k.wait"
sh "$SCRIPT" --holder W --progress "$TMP/k.w.wait" --wait-max 20 -- sh "$TMP/at" "$TMP/k.w.start" &
kw=$!
until_ok test -s "$TMP/k.w.wait"
kill -9 "$kk"; wait "$kk" 2>/dev/null
wait "$ka"; wait "$kw"; rc=$?
python3 -c 'import sys; a, w = (float(open(p).read()) for p in sys.argv[1:]); sys.exit(0 if 0 <= w - a <= 1 else 1)' "$TMP/k.a.end" "$TMP/k.w.start" 2>/dev/null; late=$?
[ "$rc" -eq 0 ] && [ "$late" -eq 0 ] && [ ! -e "$TMP/k.k.start" ] && [ "$(tickets)" -eq 0 ] && pass "#97 a waiter killed with kill -9 blocks no one" || fail "#97 killed waiter (rc=$rc late=$late tickets=$(tickets))"
# 30. --slots 2 lets two gates run side by side, in <lock> and <lock>.2; a third waits for one of them.
sh "$SCRIPT" --slots 2 > "$TMP/s.out"; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$TMP/s.out")" = "slots 2" ] && [ "$(cat "$LOCK.slots" 2>/dev/null)" = "2" ] && pass "#97 --slots 2 writes the slot count and says so" || fail "#97 --slots 2 (rc=$rc: $(cat "$TMP/s.out"))"
sh "$SCRIPT" --holder S1 -- sh -c "sh '$TMP/at' '$TMP/s1.start'; sleep 1.5; sh '$TMP/at' '$TMP/s1.end'" &
s1=$!
sh "$SCRIPT" --holder S2 -- sh -c "sh '$TMP/at' '$TMP/s2.start'; sleep 1.5; sh '$TMP/at' '$TMP/s2.end'" &
s2=$!
until_ok test -s "$TMP/s1.start"; until_ok test -s "$TMP/s2.start"
held=$(cut -d' ' -f1 "$LOCK" "$LOCK.2" 2>/dev/null | sort | tr '\n' ' ')
sh "$SCRIPT" --holder S3 --wait-max 20 -- sh "$TMP/at" "$TMP/s3.start"; rc=$?
wait "$s1" "$s2"
[ "$held" = "S1 S2 " ] && pass "#97 two gates hold slot 1 and slot 2 at once" || fail "#97 slot holders ($held)"
python3 -c 'import sys; a, b, c, d, e = (float(open(p).read()) for p in sys.argv[1:]); sys.exit(0 if a < d and c < b and e >= min(b, d) else 1)' "$TMP/s1.start" "$TMP/s1.end" "$TMP/s2.start" "$TMP/s2.end" "$TMP/s3.start" 2>/dev/null && [ "$rc" -eq 0 ] && pass "#97 with two slots, two gates overlap and a third waits for one to end" || fail "#97 two slots (rc=$rc)"
# 31. A gate inside a gate held in slot 2 runs at once: the token is looked for in every slot.
sh "$SCRIPT" --holder N1 -- sleep 2 &
n1=$!
until_ok test -s "$LOCK"
sh "$SCRIPT" --holder outer2 --wait-max 0 -- sh -c "sh '$SCRIPT' --holder inner2 --wait-max 0 -- sh -c 'echo inner > $TMP/slot2.nest'" 2>/dev/null; rc=$?
wait "$n1"
[ "$rc" -eq 0 ] && [ -f "$TMP/slot2.nest" ] && pass "#97 a gate inside a gate held in slot 2 runs at once" || fail "#97 nested gate in slot 2 (rc=$rc)"
# 32. --slots takes one number from 1 to 4 and nothing else; a refused call leaves the count as it
#     was. A count outside 1 to 4 in the file reads as 1.
sh "$SCRIPT" --slots 1 >/dev/null
for args in "--slots 5" "--slots 0" "--slots two" "--slots" "--slots 2 -- true" "--holder x --slots 2 -- true"; do
  # shellcheck disable=SC2086
  sh "$SCRIPT" $args > "$TMP/s.bad" 2>/dev/null; rc=$?
  [ "$rc" -eq 64 ] && [ ! -s "$TMP/s.bad" ] && [ "$(cat "$LOCK.slots" 2>/dev/null)" = "1" ] && pass "#97 bad --slots usage ($args) is exit 64" || fail "#97 --slots usage ($args) gave $rc"
done
printf '9\n' > "$LOCK.slots"
sh "$SCRIPT" --holder S9 -- sleep 1 &
s9=$!
until_ok test -s "$LOCK"
sh "$SCRIPT" --holder S10 --wait-max 0 -- true 2>/dev/null; rc=$?
wait "$s9"
rm -f "$LOCK.slots"
[ "$rc" -eq 75 ] && pass "#97 a slot count outside 1 to 4 reads as 1" || fail "#97 out-of-range slot count (rc=$rc)"
# 33. --wait-max counts from the last time the queue ahead moved: W2 waits about 2.8 s behind H and
#     W1, longer than its --wait-max 2.2, but the queue moves every 1.4 s, so W2 runs.
sh "$SCRIPT" --holder H -- sleep 1.4 &
mh=$!
until_ok test -s "$LOCK"
sh "$SCRIPT" --holder W1 --progress "$TMP/m1.wait" --wait-max 20 -- sleep 1.4 &
m1=$!
until_ok test -s "$TMP/m1.wait"
JUEL_GATE_LOCK_POLL=0.05 sh "$SCRIPT" --holder W2 --wait-max 2.2 -- sh -c "echo ran > '$TMP/m2.ran'" 2>/dev/null; rc=$?
wait "$mh" "$m1"
[ "$rc" -eq 0 ] && [ -f "$TMP/m2.ran" ] && pass "#97 a waiter whose queue keeps moving outlives --wait-max" || fail "#97 a moving queue timed out (rc=$rc)"
# 34. A queue that never moves still gives up: H2 runs 3 s, W3 waits behind it, and W4, behind W3
#     with --wait-max 1, exits 75 naming H2 and leaves no ticket.
sh "$SCRIPT" --holder H2 -- sleep 3 &
mh2=$!
until_ok test -s "$LOCK"
sh "$SCRIPT" --holder W3 --progress "$TMP/m3.wait" --wait-max 20 -- true &
m3=$!
until_ok test -s "$TMP/m3.wait"
t0=$(date +%s)
sh "$SCRIPT" --holder W4 --wait-max 1 -- sh -c "echo ran > '$TMP/m4.ran'" 2> "$TMP/m4.err"; rc=$?
t1=$(date +%s)
wait "$mh2" "$m3"
[ "$rc" -eq 75 ] && [ ! -e "$TMP/m4.ran" ] && [ $((t1 - t0)) -le 3 ] && grep -q 'busy, held by H2' "$TMP/m4.err" && [ "$(tickets)" -eq 0 ] && pass "#97 a queue that never moves still gives up after --wait-max" || fail "#97 a stuck queue (rc=$rc, $((t1 - t0))s: $(cat "$TMP/m4.err"))"

# lane c: #143 a gate that prints nothing for --idle-max seconds is stopped, frees the lock and exits 125
# 35. A command that prints, then goes silent, is stopped at the idle limit with its own code and line.
t0=$(date +%s)
sh "$SCRIPT" --holder idle --idle-max 1 -- sh -c "echo started; sleep 30; echo late > '$TMP/idle.late'" > "$TMP/idle.out" 2> "$TMP/idle.err"; rc=$?
t1=$(date +%s)
[ "$rc" -eq 125 ] && [ $((t1 - t0)) -le 6 ] && [ "$(cat "$TMP/idle.out")" = "started" ] && [ "$(cat "$TMP/idle.err")" = "gate-lock.sh: stalled, the command printed nothing for 1 s and was stopped" ] && free && pass "#143 a silent gate is stopped at --idle-max with exit 125 and one stalled line, and the lock is free" || fail "#143 silent gate (rc=$rc, $((t1 - t0))s, err: $(cat "$TMP/idle.err"))"
sleep 0.3; pgrep -f "$TMP/idle.late" >/dev/null && fail "#143 the silent gate's command still running" || pass "#143 the silent gate's command is gone"
# 36. Output on stdout alone, or on stderr alone, keeps a gate going past the idle limit.
for fd in 1 2; do
  sh "$SCRIPT" --holder tick --idle-max 1 -- sh -c "i=0; while [ \$i -lt 6 ]; do i=\$((i + 1)); echo tick >&$fd; sleep 0.4; done; exit 4" > "$TMP/tick.1" 2> "$TMP/tick.2"; rc=$?
  [ "$rc" -eq 4 ] && [ "$(grep -c '^tick$' "$TMP/tick.$fd")" -eq 6 ] && ! grep -q stalled "$TMP/tick.2" && pass "#143 output on fd $fd alone keeps a gate past --idle-max" || fail "#143 a gate printing on fd $fd (rc=$rc: $(grep -v '^tick$' "$TMP/tick.2"))"
done
# 37. Output streams through as it comes, byte for byte, each on its own stream.
printf 'early\nout\nno newline' > "$TMP/st.want"
sh "$SCRIPT" --holder stream --idle-max 5 -- sh -c "printf 'early\n'; sleep 2; printf 'out\nno newline'; printf 'err1\n' >&2" > "$TMP/st.out" 2> "$TMP/st.err" &
st=$!
until_ok grep -q early "$TMP/st.out"; early=$?
kill -0 "$st" 2>/dev/null; running=$?
wait "$st"; rc=$?
[ "$early" -eq 0 ] && [ "$running" -eq 0 ] && [ "$rc" -eq 0 ] && cmp -s "$TMP/st.out" "$TMP/st.want" && [ "$(cat "$TMP/st.err")" = "err1" ] && pass "#143 output streams through as it comes, byte for byte, each on its own stream" || fail "#143 streamed output (rc=$rc early=$early running=$running)"
# 38. --idle-max 0 is no idle limit: the command writes straight to the wrapper's own stdout.
sh "$SCRIPT" --holder i0 --idle-max 0 -- sh -c "sleep 1.5; python3 -c 'import os; print(os.fstat(1).st_ino)'" > "$TMP/i0.out" 2> "$TMP/i0.err"; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$TMP/i0.out")" = "$(ls -i "$TMP/i0.out" | awk '{print $1}')" ] && pass "#143 --idle-max 0 is no idle limit, and the output goes straight through" || fail "#143 --idle-max 0 (rc=$rc)"
# 39. --idle-max takes a number of seconds, 0 or more; the header lists the flag and exit 125.
for v in nope -1; do
  sh "$SCRIPT" --holder ib --idle-max "$v" -- sh -c "echo ran > '$TMP/ib.ran'" 2>/dev/null; rc=$?
  [ "$rc" -eq 64 ] && [ ! -e "$TMP/ib.ran" ] && pass "#143 a bad --idle-max ($v) is exit 64" || fail "#143 bad --idle-max ($v) gave $rc"
done
sh "$SCRIPT" --idle-max -- true 2>/dev/null; [ $? -eq 64 ] && pass "#143 --idle-max without a value is exit 64" || fail "#143 --idle-max usage"
grep -qF -- '[--idle-max <seconds>]' "$SCRIPT" && grep -qF '125 with "gate-lock.sh: stalled, the command printed' "$SCRIPT" && pass "#143 the header lists --idle-max and exit 125" || fail "#143 header"

# 40. The order is gate, then screen (#207): a holder that has the screen lock gets exit 77 and nothing runs.
SCREEN="$ROOT/skills/ship-ticket/screen-lock.sh"
export JUEL_SCREEN_LOCK="$TMP/screen.lock" JUEL_SCREEN_LOCK_POLL=0.2
sleep 120 & sw=$!
sh "$SCREEN" acquire --holder star/item-7 --pid "$sw" --wait-max 2 >/dev/null
err=$(sh "$SCRIPT" --holder star/item-7 --wait-max 1 -- sh -c "echo ran > '$TMP/s77.ran'" 2>&1); rc=$?
[ "$rc" -eq 77 ] && [ ! -e "$TMP/s77.ran" ] && pass "#207 a holder that has the screen lock gets exit 77 and nothing runs" || fail "#207 exit 77 ($rc)"
case "$err" in *"star/item-7 holds the screen lock: release it first (the order is gate, then screen, #207)"*) pass "#207 the message names the holder and the order" ;; *) fail "#207 message ($err)" ;; esac
free && pass "#207 the refusal took no gate lock" || fail "#207 the refusal left the gate lock held"
sh "$SCREEN" release --holder star/item-7 >/dev/null 2>&1
sh "$SCREEN" acquire --holder item-7 --pid "$sw" --wait-max 2 >/dev/null
sh "$SCRIPT" --holder star/item-7 --wait-max 1 -- sh -c "echo ran > '$TMP/s77b.ran'" 2>/dev/null; rc=$?
[ "$rc" -eq 77 ] && [ ! -e "$TMP/s77b.ran" ] && pass "#207 a screen lock under the part after the last / matches too" || fail "#207 short holder ($rc)"
sh "$SCRIPT" --holder other --wait-max 1 -- sh -c "echo ran > '$TMP/s77c.ran'" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ -e "$TMP/s77c.ran" ] && pass "#207 another holder is not refused" || fail "#207 other holder ($rc)"
sh "$SCRIPT" -- sh -c "echo ran > '$TMP/s77d.ran'" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ -e "$TMP/s77d.ran" ] && pass "#207 no --holder is never refused" || fail "#207 no holder ($rc)"
# a nested gate runs at once, even under a holder that has the screen
sh "$SCRIPT" --holder star/item-8 -- sh "$SCRIPT" --holder star/item-7 -- sh -c "echo ran > '$TMP/s77e.ran'" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ -e "$TMP/s77e.ran" ] && pass "#207 a nested gate is not refused" || fail "#207 nested ($rc)"
sh "$SCREEN" release --holder item-7 >/dev/null 2>&1
sh "$SCRIPT" --holder star/item-7 --wait-max 1 -- sh -c "echo ran > '$TMP/s77f.ran'" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ -e "$TMP/s77f.ran" ] && pass "#207 after the screen is released the gate runs" || fail "#207 after release ($rc)"
kill "$sw" 2>/dev/null; wait "$sw" 2>/dev/null
grep -qF 'holds the screen lock: release it first (the order is gate, then screen,' "$SCRIPT" && pass "#207 the header lists exit 77" || fail "#207 header"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
