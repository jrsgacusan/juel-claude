#!/bin/sh
# Runs one command while holding the machine-wide heavy-gate lock, so unattended workers never
# run full test suites or builds at the same time.
#
# Usage: sh gate-lock.sh [--holder <label>] [--progress <file>] [--wait-max <seconds>] [--max-seconds <seconds>] [--idle-max <seconds>] -- <command> [args...]
#        sh gate-lock.sh --slots <n>
#
# What follows "--" is one command with its arguments, run as it is: no shell reads it. A line
# with "&&", "cd", "VAR=value" or a redirect needs a shell of its own: put the commands in a file
# and pass "sh <file>" (or use run-gates.sh, next to this file, with a gate manifest).
#
# Run it with the Bash tool's run_in_background: true and wait for the completion notification
# (like codex exec): waiting for the lock plus running the gate can take longer than the tool's
# 600 s foreground cap. The command's stdin is /dev/null.
#
# The lock is a kernel lock (flock) on one file, <lock>: JUEL_GATE_LOCK when set (give an absolute path),
# else /tmp/juel.gate.<uid>.lock, one file per user for every project on the machine.
# JUEL_GATE_TEST_DIR, test-only, replaces /tmp in that default path (#132); never set it outside a
# test.
# The default is under /tmp on purpose: every worker and every sandboxed executor can write there,
# no worker needs to know where STAR's home is, and no "git clean" in a repo can delete it. The file
# stays on disk;
# what it contains ("<label> pid=<wrapper> pgid=<command group>") is only there for the busy
# message and decides nothing. After taking the lock the wrapper checks that the path still names
# the file it locked, and starts over when the file was replaced meanwhile. Never delete the file
# while gates run: a gate started after that would not see the one still running.
#
# Queue (#97): a gate that cannot start at once takes a ticket, a file in <lock>.q/ named by its
# arrival time on the monotonic clock (nanoseconds, 20 digits, system-wide on macOS and Linux, so
# a wall clock stepped back cannot sort a newcomer ahead of earlier waiters). With one slot (the
# default) the waiters start in strict arrival order, whatever their poll interval. With more
# slots the first <slots> waiters in the queue race for a freed slot, so those start in no fixed
# order. A newcomer that finds anyone queued takes a ticket behind them, even at an instant the
# lock is free. A waiter holds its ticket's lock from before the ticket appears until after it
# deletes it, so a ticket whose lock can be taken has no live waiter (one killed with kill -9
# holds nothing): the next poll deletes it, and it blocks no one. A waiter keeps the lock file it
# opened while it waits, so a file replaced meanwhile never lets it run beside the gate that
# holds the old one.
#
# Slots (#97): <lock> is slot 1. "sh gate-lock.sh --slots <n>" (n is 1 to 4, with nothing else)
# writes n to <lock>.slots through a temp file and a rename, and prints "slots <n>". Up to n
# gates then run at once, in <lock>, <lock>.2, <lock>.3 and <lock>.4, each file holding its own
# gate's holder line, and the first n tickets in the queue race for a slot that frees. A missing,
# unreadable or out-of-range <lock>.slots reads as 1. --slots exits 64 on bad usage and 71 when
# it cannot write the file. Heavy gates side by side can take the machine down: raise the count
# only when free memory allows.
#
# The command runs in its own process group and inherits the lock. The kernel drops the lock when
# the last process holding it exits, so there is nothing stale to detect and a recycled pid can
# never keep it busy: if this wrapper is SIGKILLed, the lock stays held exactly as long as the
# command or anything it started is alive. A TERM, INT or HUP to the wrapper stops the whole
# group and frees the lock. When the command exits normally the wrapper waits for its group to
# empty, stops what is still there after JUEL_GATE_LOCK_DRAIN_SECONDS (default 60), and frees
# the lock. A child that detached into its own session (a daemon) is not part of the gate.
# A gate started from inside a gate on the same lock (a wrapped script calling a wrapped step)
# runs at once: the outer gate already holds the lock. The proof is a token: the command gets it
# in JUEL_GATE_LOCK_HELD and its slot's file holds it for as long as that gate runs, so a value a
# process kept after its gate ended, or carried into another lock, proves nothing and is ignored.
#
# Waiting: polls every JUEL_GATE_LOCK_POLL seconds (default 5), and gives up when the queue ahead
# has not moved for --wait-max seconds (default 3600). Moving means a ticket ahead left the queue
# or a slot's holder line changed, so a long queue that keeps moving never times out (#97).
# Running: a command still going after --max-seconds (default 7200; 0 = no limit) is stopped
# like a TERM, so one hung test runner cannot hold every project's gate for good.
# Idle (#143): a command that prints nothing, on stdout or stderr, for --idle-max seconds (default
# 900; 0 = no limit) is stopped the same way, so a test stuck on a server it started frees the
# lock in minutes. To see that, the wrapper reads the command's stdout and stderr through pipes and
# copies every byte to its own stdout and stderr as it arrives, unchanged (only when both go to one
# file can the two interleave differently than a direct write would). With --idle-max 0 the
# command writes straight to the wrapper's stdout and stderr, as before. The wrapper never waits
# for the pipes to close, since a detached daemon may hold them. A gate inside a gate is not
# watched again: the outer gate sees its output.
#
# With --progress <file>, a gate that has to wait appends one line to <file> when the wait starts,
# and again every JUEL_GATE_LOCK_PROGRESS_SECONDS (default 600) while it waits:
#   <UTC time, as 2026-10-13T09:00:00Z> regression-gate gate-lock waiting, held by <holder label>
# which is the line a STAR worker's progress log takes, so STAR's progress check reads a gate
# queued behind other workers as alive (#89). A lock that is free at once writes nothing. A file
# that cannot be written is skipped: the progress line never stops a gate.
#
# Exit status: the command's own (128+n when a signal ended it, 127 when it could not start).
# The wrapper's own codes never mean "the gate is red": 75 with "gate-lock.sh: busy, held by
# <slot 1's holder>" when the queue ahead did not move for --wait-max seconds; 124 with "ran past"
# when --max-seconds ended the command; 125 with "gate-lock.sh: stalled, the command printed
# nothing for <n> s and was stopped" when --idle-max ended it; 71 when the gate could not run at
# all (a lock file or the queue cannot be opened or locked); 64 on bad usage; 77 with
# "gate-lock.sh: <holder> holds the screen lock: release it first (the order is gate, then screen,
# #207)" when --holder names a worker that holds the screen lock (screen-lock.sh, next to this
# file; the label is matched whole, never by its part after the last "/", since two projects may
# each have an issue-12): nothing runs and no gate lock is taken, so a worker never holds the screen while it waits
# in the gate queue. Release the screen, run the gate again. A nested gate is never refused.
GATE_LOCK_DIR=$(cd "$(dirname "$0")" && pwd) exec python3 - "$@" <<'PY'
import fcntl
import re
import select
import errno
import os
import secrets
import signal
import stat
import subprocess
import sys
import time


def die(code, msg):
    print(f"gate-lock.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def number(name, text, default):
    try:
        value = float(text if text is not None else default)
    except ValueError:
        value = -1
    if value < 0 or value != value:
        die(64, f"{name} must be a number of seconds, 0 or more (got {text!r})")
    return value


lock = os.path.abspath(os.environ.get("JUEL_GATE_LOCK") or f"{os.environ.get('JUEL_GATE_TEST_DIR') or '/tmp'}/juel.gate.{os.getuid()}.lock")

if sys.argv[1:2] == ["--slots"]:  # sh gate-lock.sh --slots <n>: how many gates may run at once
    if len(sys.argv) != 3 or sys.argv[2] not in ("1", "2", "3", "4"):
        die(64, "usage: gate-lock.sh --slots <n>, with n from 1 to 4 and nothing else")
    tmp = f"{lock}.slots.tmp-{secrets.token_hex(4)}"
    try:
        os.makedirs(os.path.dirname(lock), exist_ok=True)
        f = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
        os.write(f, f"{sys.argv[2]}\n".encode())
        os.close(f)
        os.replace(tmp, f"{lock}.slots")  # a reader sees the old count or the new one, never half a file
    except OSError as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        die(71, f"cannot write {lock}.slots: {e.strerror}")
    print(f"slots {sys.argv[2]}")
    sys.exit(0)

holder, wait_max, max_seconds, idle_max, progress, argv = "gate", None, None, None, None, sys.argv[1:]
holder_given = False
while argv:
    arg = argv.pop(0)
    if arg == "--":
        break
    if arg not in ("--holder", "--wait-max", "--max-seconds", "--idle-max", "--progress"):
        die(64, f"unknown argument: {arg}")
    if not argv or argv[0] == "--":
        die(64, f"{arg} needs a value")
    if arg == "--holder":
        holder, holder_given = argv.pop(0), True
    elif arg == "--wait-max":
        wait_max = argv.pop(0)
    elif arg == "--progress":
        progress = argv.pop(0) or None
    elif arg == "--idle-max":
        idle_max = argv.pop(0)
    else:
        max_seconds = argv.pop(0)
else:
    die(64, "no command given after --")
if not argv:
    die(64, "no command given after --")
wait_max = number("--wait-max", wait_max, 3600)
max_seconds = number("--max-seconds", max_seconds, 7200)
idle_max = number("--idle-max", idle_max, 900)
poll = number("JUEL_GATE_LOCK_POLL", os.environ.get("JUEL_GATE_LOCK_POLL"), 5) or 0.01
drain = number("JUEL_GATE_LOCK_DRAIN_SECONDS", os.environ.get("JUEL_GATE_LOCK_DRAIN_SECONDS"), 60)
every = number("JUEL_GATE_LOCK_PROGRESS_SECONDS", os.environ.get("JUEL_GATE_LOCK_PROGRESS_SECONDS"), 600)
holder = "_".join(holder.split()) or "gate"


def code(rc):
    return rc if rc >= 0 else 128 - rc


QUEUE = f"{lock}.q"  # one ticket per waiter, named "<monotonic_ns, 20 digits>-<pid>"
TICKET = re.compile(r"[0-9]{20}-[0-9]+")
SLOT_MAX = 4  # slots live in <lock>, <lock>.2, <lock>.3 and <lock>.4


def slot_path(i):
    """Slot 1 is the lock file itself, so a gate-lock.sh from before the queue still excludes on it."""
    return lock if i == 1 else f"{lock}.{i}"


def slot_count():
    """How many gates may run at once: <lock>.slots, read as 1 when missing, unreadable or not 1 to 4."""
    text = head(f"{lock}.slots").strip()
    return int(text) if text in ("1", "2", "3", "4") else 1


def head(path):
    """The start of a small file as text; "" when it is missing or unreadable. Never blocks."""
    try:
        f = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return ""
    try:
        return os.read(f, 400).decode("utf-8", "replace")
    except OSError:
        return ""
    finally:
        os.close(f)


def held_by_our_gate():
    """True when the gate that started us is still running in one of this lock's slots."""
    token = os.environ.get("JUEL_GATE_LOCK_HELD") or ""
    if not re.fullmatch(r"[0-9a-f]{16}", token):
        return False
    return any(f"token={token}" in head(slot_path(i)).split() for i in range(1, SLOT_MAX + 1))


if held_by_our_gate():
    # waiting for the lock would be waiting for ourselves
    try:
        sys.exit(code(subprocess.run(argv, stdin=subprocess.DEVNULL).returncode))
    except OSError as e:
        die(127 if isinstance(e, FileNotFoundError) else 126, f"cannot run {argv[0]}: {e.strerror}")


def holds_screen():
    """True when --holder names the worker that holds the screen lock (#207): the order is gate, then
    screen. screen-lock.sh stores the label with spaces turned to "_"; it is matched whole, never by its
    part after the last "/", since two projects may each have an "issue-12"."""
    if not holder_given:
        return False
    try:
        out = subprocess.run(["sh", os.path.join(os.environ.get("GATE_LOCK_DIR") or ".", "screen-lock.sh"), "status"],
                             stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return False  # cannot tell: the gate is not refused over it
    return out[:2] == ["held", "by"] and len(out) > 2 and out[2] == holder


if holds_screen():
    die(77, f"{holder} holds the screen lock: release it first (the order is gate, then screen, #207)")


def open_lock(path):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        new = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o644)
    except OSError as e:
        die(71, f"cannot open the lock file {path}: {e.strerror}")
    if not stat.S_ISREG(os.fstat(new).st_mode):
        die(71, f"the lock path {path} is not a regular file")
    return new


def still_the_file(fd, path):
    """True when the path still names the file this descriptor has locked."""
    try:
        there, mine = os.stat(path, follow_symlinks=False), os.fstat(fd)
    except OSError:
        return False
    return (there.st_dev, there.st_ino) == (mine.st_dev, mine.st_ino)


def waiting_note():
    """One line for a STAR worker's progress log: this gate waits, and for whom (#89)."""
    if not progress:
        return
    try:
        held = head(slot_path(1)).split()
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        with open(progress, "a", encoding="utf-8") as f:
            f.write(f"{stamp} regression-gate gate-lock waiting, held by {held[0] if held else 'another gate'}\n")
    except OSError:
        pass  # the progress line never stops a gate


fds = {}  # slot number -> descriptor of its lock file, kept open from one poll to the next


def try_slots(n):
    """Lock the first free slot of 1..n without blocking: its number, or None when all are busy.
    A descriptor stays open between polls, so a waiter that opened a slot's file before someone
    replaced it waits for that file's holder and never runs beside it."""
    for i in range(1, n + 1):
        while True:
            if i not in fds:
                fds[i] = open_lock(slot_path(i))
            try:
                fcntl.flock(fds[i], fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as e:
                if e.errno not in (errno.EWOULDBLOCK, errno.EAGAIN):
                    die(71, f"cannot lock {slot_path(i)}: {e.strerror}")
                break  # busy: try the next slot
            if still_the_file(fds[i], slot_path(i)):
                return i
            os.close(fds.pop(i))  # the file was deleted or replaced while we waited: lock the one there now
    return None


def reap(path):
    """True when no live waiter holds the queue file at path, which is then deleted. A waiter
    locks its ticket before the ticket appears and deletes it before letting go of the lock, so a
    lock we can take means its waiter is dead (kill -9 included) or has just left the queue."""
    try:
        f = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return True  # its waiter left the queue
    except OSError:
        return False  # cannot tell: count it as live
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return False  # its waiter holds it (or another poll is deleting it: gone by the next poll)
    else:
        try:
            os.unlink(path)  # names are never reused: this is the file just locked, or nothing
        except OSError:
            pass
        return True
    finally:
        os.close(f)


def scan(mine):
    """The number of live tickets ahead of ours (of all tickets, when we hold none yet). Dead
    tickets ahead are deleted on the way, and so is a .tmp- file left unlocked for over 60 s."""
    try:
        names = sorted(os.listdir(QUEUE))
    except OSError:
        return 0  # no queue folder yet: no one waits
    ahead = 0
    for name in names:  # ".tmp-" sorts before the digits; the tickets follow in arrival order
        path = os.path.join(QUEUE, name)
        if name.startswith(".tmp-"):
            try:
                stale = time.time() - os.lstat(path).st_mtime > 60
            except OSError:
                continue
            if stale:
                reap(path)  # its waiter died between creating it and renaming it
        elif mine is not None and name >= mine:
            break  # our own ticket, then the ones behind it
        elif TICKET.fullmatch(name) and not reap(path):
            ahead += 1
    return ahead


def take_ticket():
    """Join the queue: our ticket's descriptor and name. The ticket is locked under a temporary
    name and only then renamed into place, so no poll ever sees a ticket its waiter does not hold."""
    try:
        os.makedirs(QUEUE, exist_ok=True)
        tmp = os.path.join(QUEUE, f".tmp-{os.getpid()}-{secrets.token_hex(4)}")
        f = os.open(tmp, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
        fcntl.flock(f, fcntl.LOCK_EX)  # never contended: no poll opens a .tmp- file younger than 60 s
        name = f"{time.monotonic_ns():020d}-{os.getpid()}"
        os.rename(tmp, os.path.join(QUEUE, name))
    except OSError as e:
        die(71, f"cannot join the queue in {QUEUE}: {e.strerror}")
    return f, name


def leave_queue(ticket):
    """Delete our ticket, then let go of its lock: a poll in between finds it gone, never unlocked."""
    f, name = ticket
    try:
        os.unlink(os.path.join(QUEUE, name))
    except OSError:
        pass
    os.close(f)


start = time.monotonic()
slot = None
if scan(None) == 0:  # no one queued: a free slot is ours at once, and nothing is written
    slot = try_slots(slot_count())
if slot is None:
    ticket = take_ticket()  # anyone already queued goes first, even when a slot is free right now
    next_note = None  # when the next progress line is due: None until the gate first has to wait
    moved, last = start, None  # when the queue ahead last moved, and what the previous poll saw
    while True:
        n = slot_count()
        ahead = scan(ticket[1])
        if ahead < n:  # with n slots, the first n tickets in the queue may try
            slot = try_slots(n)
            if slot is not None:
                break
        now = time.monotonic()
        holders = [head(slot_path(i)) for i in range(1, SLOT_MAX + 1)]
        if last is not None and (ahead < last[0] or holders != last[1]):
            moved = now  # a ticket ahead left, or a slot changed hands: the queue is moving
        last = (ahead, holders)
        left = wait_max - (now - moved)
        if left <= 0:
            leave_queue(ticket)
            die(75, f"busy, held by {head(slot_path(1)).strip() or 'another gate'}")
        if next_note is None or now >= next_note:
            waiting_note()
            next_note = now + every
        time.sleep(min(poll, left))
    leave_queue(ticket)
fd = fds.pop(slot)
for other in fds.values():
    os.close(other)  # never locked: closing them frees nothing


def note(text):
    """Write first, then cut to length: a reader never sees the file empty while the gate runs."""
    data = text.encode()
    os.pwrite(fd, data, 0)
    os.ftruncate(fd, len(data))


def group_alive(pgid):
    try:
        os.waitpid(pgid, os.WNOHANG)  # reap the command itself so it does not count as alive
    except ChildProcessError:
        pass
    try:
        os.killpg(pgid, 0)
    except (ProcessLookupError, PermissionError):
        return False  # macOS answers EPERM for a group that holds only exited processes
    return True


def stop_group(pgid, grace):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        if not group_alive(pgid):
            return
        try:
            os.killpg(pgid, sig)
        except (ProcessLookupError, PermissionError):
            return
        end = time.monotonic() + grace
        while time.monotonic() < end and group_alive(pgid):
            time.sleep(0.05)


def release():
    note("")
    fcntl.flock(fd, fcntl.LOCK_UN)


child, starting, early = None, False, []


def on_signal(signum, _frame):
    if starting:  # the command is being started: act once its pid is known, never before
        early.append(signum)
        return
    if child is not None:
        stop_group(child.pid, 5)
    release()
    sys.exit(128 + signum)


for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(s, on_signal)

token = secrets.token_hex(8)
note(f"{holder} pid={os.getpid()} token={token}\n")
starting = True
try:
    # its own process group, with the lock's descriptor inherited
    out = subprocess.PIPE if idle_max else None  # 0: no idle limit, the output goes straight through
    child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=out, pass_fds=[fd],
                             preexec_fn=os.setpgrp, env={**os.environ, "JUEL_GATE_LOCK_HELD": token})
except OSError as e:
    release()
    die(127 if isinstance(e, FileNotFoundError) else 126, f"cannot run {argv[0]}: {e.strerror}")
starting = False
if early:
    on_signal(early[0], None)
note(f"{holder} pid={os.getpid()} pgid={child.pid} token={token}\n")
pipes = {}  # read end -> the wrapper's own fd it is copied to
if idle_max:
    for r, to in ((child.stdout, 1), (child.stderr, 2)):
        os.set_blocking(r.fileno(), False)
        pipes[r.fileno()] = to
dropped = set()  # the wrapper's own fds that failed a write: later output on them is discarded


def copy(r):
    """Copy what one pipe holds to its fd; returns the bytes read (0: nothing waiting, or the end)."""
    try:
        data = os.read(r, 65536)
    except BlockingIOError:
        return 0
    except OSError:
        data = b""
    if not data:
        pipes.pop(r, None)
        return 0
    to = pipes[r]
    if to not in dropped:
        try:
            view = memoryview(data)
            while view:
                view = view[os.write(to, view):]
        except OSError:
            dropped.add(to)
    return len(data)


def pump(timeout):
    """Copy what is ready for up to timeout seconds; True when any bytes arrived."""
    if not pipes:
        time.sleep(timeout)
        return False
    got = False
    try:
        ready = select.select(list(pipes), [], [], timeout)[0]
    except (OSError, ValueError):
        return False
    for r in ready:
        if copy(r):
            got = True
    return got


begun = last = time.monotonic()
while True:
    rc = child.poll()
    if rc is not None:
        break
    now = time.monotonic()
    if max_seconds and now - begun >= max_seconds:
        print(f"gate-lock.sh: the command ran past {max_seconds:g} s and was stopped", file=sys.stderr)
        stop_group(child.pid, 5)
        release()
        sys.exit(124)
    if idle_max and now - last >= idle_max:
        print(f"gate-lock.sh: stalled, the command printed nothing for {idle_max:g} s and was stopped", file=sys.stderr)
        stop_group(child.pid, 5)
        release()
        sys.exit(125)
    if pump(0.1):
        last = time.monotonic()
# the group may still hold children of the command: give them the drain time, then stop them
end = time.monotonic() + drain
while group_alive(child.pid) and time.monotonic() < end:
    pump(0.1)
if group_alive(child.pid):
    print(f"gate-lock.sh: stopping processes the command left running in group {child.pid}", file=sys.stderr)
    stop_group(child.pid, 2)
for r in list(pipes):  # what is still buffered; never wait for an end a detached daemon may hold off
    while r in pipes and copy(r):
        pass
release()
sys.exit(code(rc))
PY
