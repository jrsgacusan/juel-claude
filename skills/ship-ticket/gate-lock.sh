#!/bin/sh
# Runs one command while holding the machine-wide heavy-gate lock, so unattended workers never
# run full test suites or builds at the same time.
#
# Usage: sh gate-lock.sh [--holder <label>] [--wait-max <seconds>] [--max-seconds <seconds>] -- <command> [args...]
#
# What follows "--" is one command with its arguments, run as it is: no shell reads it. A line
# with "&&", "cd", "VAR=value" or a redirect needs a shell of its own: put the commands in a file
# and pass "sh <file>" (or use run-gates.sh, next to this file, with a gate manifest).
#
# Run it with the Bash tool's run_in_background: true and wait for the completion notification
# (like codex exec): waiting for the lock plus running the gate can take longer than the tool's
# 600 s foreground cap. The command's stdin is /dev/null.
#
# The lock is a kernel lock (flock) on one file: JUEL_GATE_LOCK when set (give an absolute path),
# else /tmp/juel.gate.<uid>.lock, one file per user for every project on the machine. It is under
# /tmp on purpose: every worker and every sandboxed executor can write there, no worker needs to
# know where STAR's home is, and no "git clean" in a repo can delete it. The file stays on disk;
# what it contains ("<label> pid=<wrapper> pgid=<command group>") is only there for the busy
# message and decides nothing. After taking the lock the wrapper checks that the path still names
# the file it locked, and starts over when the file was replaced meanwhile. Never delete the file
# while gates run: a gate started after that would not see the one still running.
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
# in JUEL_GATE_LOCK_HELD and the lock file holds it for as long as that gate runs, so a value a
# process kept after its gate ended, or carried into another lock, proves nothing and is ignored.
#
# Waiting: polls every JUEL_GATE_LOCK_POLL seconds (default 5) for at most --wait-max seconds
# (default 3600). Running: a command still going after --max-seconds (default 7200; 0 = no limit) is stopped
# like a TERM, so one hung test runner cannot hold every project's gate for good.
#
# Exit status: the command's own (128+n when a signal ended it, 127 when it could not start).
# The wrapper's own codes never mean "the gate is red": 75 with "gate-lock.sh: busy, held by ..."
# when the lock stayed busy; 124 with "ran past" when --max-seconds ended the command; 71 when
# the gate could not run at all (the lock file cannot be opened or locked); 64 on bad usage.
exec python3 - "$@" <<'PY'
import fcntl
import re
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


holder, wait_max, max_seconds, argv = "gate", None, None, sys.argv[1:]
while argv:
    arg = argv.pop(0)
    if arg == "--":
        break
    if arg not in ("--holder", "--wait-max", "--max-seconds"):
        die(64, f"unknown argument: {arg}")
    if not argv or argv[0] == "--":
        die(64, f"{arg} needs a value")
    if arg == "--holder":
        holder = argv.pop(0)
    elif arg == "--wait-max":
        wait_max = argv.pop(0)
    else:
        max_seconds = argv.pop(0)
else:
    die(64, "no command given after --")
if not argv:
    die(64, "no command given after --")
wait_max = number("--wait-max", wait_max, 3600)
max_seconds = number("--max-seconds", max_seconds, 7200)
poll = number("JUEL_GATE_LOCK_POLL", os.environ.get("JUEL_GATE_LOCK_POLL"), 5) or 0.01
drain = number("JUEL_GATE_LOCK_DRAIN_SECONDS", os.environ.get("JUEL_GATE_LOCK_DRAIN_SECONDS"), 60)
holder = "_".join(holder.split()) or "gate"

lock = os.path.abspath(os.environ.get("JUEL_GATE_LOCK") or f"/tmp/juel.gate.{os.getuid()}.lock")


def code(rc):
    return rc if rc >= 0 else 128 - rc


def held_by_our_gate():
    """True when the gate that started us is still running on this very lock file."""
    token = os.environ.get("JUEL_GATE_LOCK_HELD") or ""
    if not re.fullmatch(r"[0-9a-f]{16}", token):
        return False
    try:
        with open(lock, encoding="utf-8", errors="replace") as f:
            return f"token={token}" in f.read(400).split()
    except OSError:
        return False


if held_by_our_gate():
    # waiting for the lock would be waiting for ourselves
    try:
        sys.exit(code(subprocess.run(argv, stdin=subprocess.DEVNULL).returncode))
    except OSError as e:
        die(127 if isinstance(e, FileNotFoundError) else 126, f"cannot run {argv[0]}: {e.strerror}")


def open_lock():
    try:
        os.makedirs(os.path.dirname(lock), exist_ok=True)
        new = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o644)
    except OSError as e:
        die(71, f"cannot open the lock file {lock}: {e.strerror}")
    if not stat.S_ISREG(os.fstat(new).st_mode):
        die(71, f"the lock path {lock} is not a regular file")
    return new


def still_the_file(fd):
    """True when the path still names the file this descriptor has locked."""
    try:
        there, mine = os.stat(lock, follow_symlinks=False), os.fstat(fd)
    except OSError:
        return False
    return (there.st_dev, there.st_ino) == (mine.st_dev, mine.st_ino)


fd = open_lock()
start = time.monotonic()
while True:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if still_the_file(fd):
            break
        os.close(fd)  # the file was deleted or replaced while we waited: lock the one that is there now
        fd = open_lock()
        continue
    except OSError as e:
        if e.errno not in (errno.EWOULDBLOCK, errno.EAGAIN):
            die(71, f"cannot lock {lock}: {e.strerror}")
        left = wait_max - (time.monotonic() - start)
        if left <= 0:
            who = os.pread(fd, 200, 0).decode("utf-8", "replace").strip() or "another gate"
            die(75, f"busy, held by {who}")
        time.sleep(min(poll, left))


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
    child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, pass_fds=[fd], preexec_fn=os.setpgrp,
                             env={**os.environ, "JUEL_GATE_LOCK_HELD": token})
except OSError as e:
    release()
    die(127 if isinstance(e, FileNotFoundError) else 126, f"cannot run {argv[0]}: {e.strerror}")
starting = False
if early:
    on_signal(early[0], None)
note(f"{holder} pid={os.getpid()} pgid={child.pid} token={token}\n")
try:
    rc = child.wait(timeout=max_seconds or None)  # 0 means no limit
except subprocess.TimeoutExpired:
    print(f"gate-lock.sh: the command ran past {max_seconds:g} s and was stopped", file=sys.stderr)
    stop_group(child.pid, 5)
    release()
    sys.exit(124)
# the group may still hold children of the command: give them the drain time, then stop them
end = time.monotonic() + drain
while group_alive(child.pid) and time.monotonic() < end:
    time.sleep(0.1)
if group_alive(child.pid):
    print(f"gate-lock.sh: stopping processes the command left running in group {child.pid}", file=sys.stderr)
    stop_group(child.pid, 2)
release()
sys.exit(code(rc))
PY
