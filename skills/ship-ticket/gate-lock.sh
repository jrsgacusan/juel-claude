#!/bin/sh
# Runs one command while holding the machine-wide heavy-gate lock, so unattended workers never
# run full test suites or builds at the same time.
#
# Usage: sh gate-lock.sh [--holder <label>] [--wait-max <seconds>] -- <command> [args...]
#
# Run it with the Bash tool's run_in_background: true and wait for the completion notification
# (like codex exec): waiting for the lock plus running the gate can take longer than the tool's
# 600 s foreground cap. The command's stdin is /dev/null.
#
# The lock is a kernel lock (flock) on one file. Where the file lives: JUEL_GATE_LOCK when set;
# else <STAR home>/gate.lock when STAR has a home on this machine ($JUEL_STAR_HOME or ~/juel-star
# with a star.json), so workers in different projects share one lock; else
# <git-common-dir>/juel/gate.lock. The file stays on disk; what it contains ("<label> pid=<wrapper>
# pgid=<command group>") is only there for the busy message and decides nothing.
#
# The command runs in its own process group and inherits the lock. The kernel drops the lock when
# the last process holding it exits, so there is nothing stale to detect and a recycled pid can
# never keep it busy: if this wrapper is SIGKILLed, the lock stays held exactly as long as the
# command or anything it started is alive. A TERM, INT or HUP to the wrapper stops the whole
# group and frees the lock. When the command exits normally the wrapper waits for its group to
# empty, stops what is still there after JUEL_GATE_LOCK_DRAIN_SECONDS (default 60), and frees
# the lock. A child that detached into its own session (a daemon) is not part of the gate.
#
# Waiting: polls every JUEL_GATE_LOCK_POLL seconds (default 5) for at most --wait-max seconds
# (default 3600).
#
# Exit status: the command's own (128+n when a signal ended it, 127 when it could not start);
# 75 with "gate-lock.sh: busy, held by ..." on stderr when the lock stayed busy; 64 on bad
# usage; 1 when there is nowhere to put the lock (not in a git repo, no JUEL_GATE_LOCK, no STAR
# home).
exec python3 - "$@" <<'PY'
import fcntl
import os
import signal
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


holder, wait_max, argv = "gate", None, sys.argv[1:]
while argv:
    arg = argv.pop(0)
    if arg == "--":
        break
    if arg not in ("--holder", "--wait-max"):
        die(64, f"unknown argument: {arg}")
    if not argv or argv[0] == "--":
        die(64, f"{arg} needs a value")
    if arg == "--holder":
        holder = argv.pop(0)
    else:
        wait_max = argv.pop(0)
else:
    die(64, "no command given after --")
if not argv:
    die(64, "no command given after --")
wait_max = number("--wait-max", wait_max, 3600)
poll = number("JUEL_GATE_LOCK_POLL", os.environ.get("JUEL_GATE_LOCK_POLL"), 5) or 0.01
drain = number("JUEL_GATE_LOCK_DRAIN_SECONDS", os.environ.get("JUEL_GATE_LOCK_DRAIN_SECONDS"), 60)
holder = "_".join(holder.split()) or "gate"

star_home = os.environ.get("JUEL_STAR_HOME") or os.path.expanduser("~/juel-star")
if os.environ.get("JUEL_GATE_LOCK"):
    lock = os.environ["JUEL_GATE_LOCK"]
elif os.path.isfile(os.path.join(star_home, "star.json")):
    lock = os.path.join(star_home, "gate.lock")
else:
    try:
        git = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True, text=True)
    except FileNotFoundError:
        die(1, "git not found and no JUEL_GATE_LOCK")
    if git.returncode != 0:
        die(1, "not in a git repo")
    lock = os.path.join(os.path.realpath(git.stdout.strip()), "juel", "gate.lock")
try:
    os.makedirs(os.path.dirname(os.path.abspath(lock)), exist_ok=True)
    fd = os.open(lock, os.O_RDWR | os.O_CREAT, 0o644)
except OSError as e:
    die(1, f"cannot open the lock file {lock}: {e.strerror}")

start = time.monotonic()
while True:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except OSError:
        left = wait_max - (time.monotonic() - start)
        if left <= 0:
            who = os.pread(fd, 200, 0).decode("utf-8", "replace").strip() or "another gate"
            die(75, f"busy, held by {who}")
        time.sleep(min(poll, left))


def note(text):
    os.ftruncate(fd, 0)
    os.pwrite(fd, text.encode(), 0)


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

note(f"{holder} pid={os.getpid()}\n")
starting = True
try:
    # its own process group, with the lock's descriptor inherited
    child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, pass_fds=[fd], preexec_fn=os.setpgrp)
except OSError as e:
    release()
    die(127 if isinstance(e, FileNotFoundError) else 126, f"cannot run {argv[0]}: {e.strerror}")
starting = False
if early:
    on_signal(early[0], None)
note(f"{holder} pid={os.getpid()} pgid={child.pid}\n")
rc = child.wait()
# the group may still hold children of the command: give them the drain time, then stop them
end = time.monotonic() + drain
while group_alive(child.pid) and time.monotonic() < end:
    time.sleep(0.1)
if group_alive(child.pid):
    print(f"gate-lock.sh: stopping processes the command left running in group {child.pid}", file=sys.stderr)
    stop_group(child.pid, 2)
release()
sys.exit(rc if rc >= 0 else 128 - rc)
PY
