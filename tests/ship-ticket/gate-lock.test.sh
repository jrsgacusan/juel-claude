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

# 16. Outside a git repo with no JUEL_GATE_LOCK and no STAR home: refuse, create nothing.
(cd "$TMP" && mkdir -p nogit && cd nogit && env -u JUEL_GATE_LOCK JUEL_STAR_HOME="$TMP/nohome" sh "$SCRIPT" -- true 2>/dev/null); rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$TMP/nogit/juel" ] && pass "refuses outside a git repo" || fail "ran outside a git repo (rc=$rc)"

# 17. With a STAR home on this machine the lock is shared by every project.
mkdir -p "$TMP/starhome" "$TMP/proj" && : > "$TMP/starhome/star.json" && (cd "$TMP/proj" && git init -q .)
(cd "$TMP/proj" && env -u JUEL_GATE_LOCK JUEL_STAR_HOME="$TMP/starhome" sh "$SCRIPT" --holder m -- sh -c "test -f '$TMP/starhome/gate.lock'"); rc=$?
[ "$rc" -eq 0 ] && pass "machine-wide lock under STAR's home" || fail "lock not under STAR's home ($rc)"
(cd "$TMP/proj" && env -u JUEL_GATE_LOCK JUEL_STAR_HOME="$TMP/nohome" sh "$SCRIPT" --holder m -- sh -c "test -f .git/juel/gate.lock"); rc=$?
[ "$rc" -eq 0 ] && pass "per-repo lock without a STAR home" || fail "per-repo fallback ($rc)"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
