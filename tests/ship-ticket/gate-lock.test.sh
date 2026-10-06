#!/bin/sh
# Runs skills/ship-ticket/gate-lock.sh against a scratch lock path.
# Usage: sh tests/ship-ticket/gate-lock.test.sh   (exit 0 = all cases pass)
set -u
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
# (the default lock is the real machine-wide one: never wait for it here; busy means a real gate runs)
d=$(cd "$TMP" && mkdir -p nogit2 && cd nogit2 && env -u JUEL_GATE_LOCK sh "$SCRIPT" --holder loc-probe --wait-max 0 -- sh -c "cut -d' ' -f1 /tmp/juel.gate.$(id -u).lock" 2>/dev/null); rc=$?
case "$rc:$d" in 0:loc-probe) pass "the default lock is one file per user under /tmp, in or out of a git repo" ;; 75:*) pass "default lock path (skipped: a real gate is running)" ;; *) fail "default lock path (rc=$rc $d)" ;; esac
now() { python3 -c 'import time; print(time.time())'; }
# A holds the lock; B waits on that file; the file is deleted; C then locks the new file. When A
# ends, B gets the old file's lock, must notice the path no longer names it, and wait for C.
sh "$SCRIPT" --holder A -- sleep 1.5 &
pa=$!; sleep 0.4
sh "$SCRIPT" --holder B --wait-max 20 -- sh -c "python3 -c 'import time; print(time.time())' > '$TMP/b.start2'" &
pb=$!; sleep 0.4
rm -f "$LOCK"
sh "$SCRIPT" --holder C --wait-max 20 -- sh -c "sleep 2.5; python3 -c 'import time; print(time.time())' > '$TMP/c.end2'" &
pc=$!
wait "$pa" "$pb" "$pc"
python3 -c 'import sys; b, c = (float(open(p).read()) for p in sys.argv[1:]); sys.exit(0 if b >= c else 1)' "$TMP/b.start2" "$TMP/c.end2" && pass "a waiter on a deleted lock file moves to the new one and waits its turn" || fail "waiter ran on the deleted lock file while another gate held the new one"
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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
