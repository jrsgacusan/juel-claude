#!/bin/sh
# One worker at a time drives this Mac's screen: a machine-wide lock for unattended workers that
# launch an app, drive a GUI, or ask the user to act at the screen.
#   screen-lock.sh acquire --holder <item> [--pid <pid>] [--wait-max <seconds>]
#   screen-lock.sh renew --holder <item>        -> renewed <iso> | free
#   screen-lock.sh release --holder <item>
#   screen-lock.sh status                       -> free | held by <item> since <iso> renewed <iso>
# acquire takes a kernel lock (flock) on JUEL_SCREEN_LOCK, else /tmp/juel.screen.<uid>.lock, and
# hands it to a small detached keeper that holds it until "release", or until the watched process
# exits: --pid, else the nearest claude or codex process above this one. A worker that crashes or
# is stopped by Orca frees the screen by itself, and the lock file is never deleted by hand. The
# keeper lets go of stdin, stdout and stderr, so the Bash tool call that ran acquire returns at once.
# The holder renews the lock at least every 10 minutes while it uses the screen (#39). A lock
# whose holder has not renewed it for JUEL_SCREEN_LOCK_STALE minutes (default 30) is stale: the
# next acquire by another holder stops its keeper, takes it, and says so on stderr.
# acquire by the holder that already has it says so and succeeds. Otherwise it waits at most
# --wait-max seconds (default 540, under the Bash tool's 600 s cap), polling every
# JUEL_SCREEN_LOCK_POLL seconds (default 2), then exits 75 with "busy, held by <item> since <iso> …".
# Exit: 0 ok; 64 usage (no --holder, a --pid that is not running, or no claude or codex process to
# watch and no --pid); 65 a release or renew by a holder that does not have the lock; 71 the lock
# file cannot be opened or locked; 75 busy.
exec python3 - "$@" <<'PY'
import errno
import fcntl
import os
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone

lock = os.path.abspath(os.environ.get("JUEL_SCREEN_LOCK") or f"/tmp/juel.screen.{os.getuid()}.lock")
info = lock + ".holder"
FMT = "%Y-%m-%dT%H:%M:%SZ"


def die(code, msg):
    print(f"screen-lock.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def number(name, text, default):
    try:
        value = float(text if text is not None else default)
    except ValueError:
        value = -1
    if value < 0 or value != value:
        die(64, f"{name} must be a number")
    return value


argv = sys.argv[1:]
if not argv or argv[0] not in ("acquire", "renew", "release", "status"):
    die(64, "usage: screen-lock.sh acquire --holder <item> [--pid <pid>] [--wait-max <s>] | renew --holder <item> | release --holder <item> | status")
cmd, argv, holder, pid, wait_max = argv[0], argv[1:], None, None, None
while argv:
    arg = argv.pop(0)
    if arg not in ("--holder", "--pid", "--wait-max") or not argv:
        die(64, f"unknown or empty argument: {arg}")
    value = argv.pop(0)
    if arg == "--holder":
        holder = "_".join(value.split())
    elif arg == "--pid":
        if not value.isdigit():
            die(64, "--pid takes a process id")
        pid = int(value)
    else:
        wait_max = value
wait_max = number("--wait-max", wait_max, 540)
poll = number("JUEL_SCREEN_LOCK_POLL", os.environ.get("JUEL_SCREEN_LOCK_POLL"), 2) or 0.05
stale_after = number("JUEL_SCREEN_LOCK_STALE", os.environ.get("JUEL_SCREEN_LOCK_STALE"), 30)
if cmd != "status" and not holder:
    die(64, f"{cmd} needs --holder <item>")


def now():
    return datetime.now(timezone.utc).strftime(FMT)


def open_lock():
    try:
        return os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o644)
    except OSError as e:
        die(71, f"cannot open {lock}: {e.strerror}")


def try_lock(fd):
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError as e:
        if e.errno in (errno.EWOULDBLOCK, errno.EAGAIN):
            return False
        die(71, f"cannot lock {lock}: {e.strerror}")


def is_free():
    fd = open_lock()
    try:
        if try_lock(fd):
            fcntl.flock(fd, fcntl.LOCK_UN)
            return True
        return False
    finally:
        os.close(fd)


def holder_line():
    try:
        return open(info, encoding="utf-8").read().strip()
    except OSError:
        return ""


def field(text, key):
    return next((p.split("=", 1)[1] for p in text.split()[1:] if p.startswith(key + "=")), "")


def describe(text):
    since = field(text, "since") or "?"
    return (f"held by {text.split()[0] if text else 'another worker'} since {since} "
            f"renewed {field(text, 'renewed') or since}")


def stale(text):
    stamp = field(text, "renewed") or field(text, "since")
    try:
        then = datetime.strptime(stamp, FMT).replace(tzinfo=timezone.utc)
    except ValueError:
        return False
    return (datetime.now(timezone.utc) - then).total_seconds() > stale_after * 60


def alive(p):
    """Running, and not a zombie waiting to be reaped (a zombie still answers kill 0)."""
    try:
        os.kill(p, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    try:
        stat = subprocess.run(["ps", "-o", "stat=", "-p", str(p)], capture_output=True, text=True,
                              timeout=5).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return True
    return bool(stat) and not stat.startswith("Z")


def agent_above():
    """The nearest claude or codex process above this one."""
    current = os.getppid()
    for _ in range(40):
        if current <= 1:
            return None
        try:
            line = subprocess.run(["ps", "-o", "ppid=,args=", "-p", str(current)], capture_output=True,
                                  text=True, timeout=5).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            return None
        parts = line.split()
        if len(parts) < 2 or not parts[0].isdigit():
            return None
        if any(os.path.basename(w) in ("claude", "codex") for w in parts[1:3]):
            return current
        current = int(parts[0])
    return None


def rewrite(text):
    tmp = f"{info}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text + "\n")
    os.replace(tmp, info)


if cmd == "status":
    print("free" if is_free() else describe(holder_line()))
    sys.exit(0)

if cmd in ("release", "renew"):
    if is_free():
        print("free")
        sys.exit(0)
    text = holder_line()
    if not text or text.split()[0] != holder:
        die(65, f"refused: {describe(text)}")
    if cmd == "renew":
        stamp = now()
        rewrite(" ".join([p for p in text.split() if not p.startswith("renewed=")] + [f"renewed={stamp}"]))
        print(f"renewed {stamp}")
        sys.exit(0)
    keeper = field(text, "keeper")
    if keeper.isdigit():
        try:
            os.kill(int(keeper), signal.SIGTERM)
        except ProcessLookupError:
            pass
    end = time.monotonic() + 5
    while time.monotonic() < end and not is_free():
        time.sleep(0.05)
    print("released" if is_free() else describe(holder_line()))
    sys.exit(0)

# acquire
watch = pid if pid is not None else agent_above()
if watch is None:
    die(64, "no claude or codex process above this one: pass --pid")
if not alive(watch):
    die(64, f"process {watch} is not running")
if not is_free() and holder_line().split()[:1] == [holder]:
    print(f"held by {holder} since {field(holder_line(), 'since') or '?'}")
    sys.exit(0)
fd, start, taken_from = open_lock(), time.monotonic(), None
while not try_lock(fd):
    text = holder_line()
    if taken_from is None and text and text.split()[0] != holder and stale(text):
        keeper = field(text, "keeper")
        if keeper.isdigit():
            try:
                os.kill(int(keeper), signal.SIGTERM)
                taken_from = text
            except OSError:
                pass
    left = wait_max - (time.monotonic() - start)
    if left <= 0:
        print(f"busy, {describe(holder_line())}")
        sys.exit(75)
    time.sleep(min(poll, left))
if taken_from:
    print(f"screen-lock.sh: took over a stale lock from {taken_from.split()[0]} "
          f"(last renewed {field(taken_from, 'renewed') or field(taken_from, 'since')})", file=sys.stderr)
since = now()
ready_r, ready_w = os.pipe()
child = os.fork()
if child == 0:
    os.setsid()
    if os.fork() != 0:
        os._exit(0)
    null = os.open(os.devnull, os.O_RDWR)
    for stream in (0, 1, 2):
        os.dup2(null, stream)
    os.close(ready_r)
    rewrite(f"{holder} since={since} keeper={os.getpid()} watch={watch} renewed={since}")
    os.write(ready_w, b"ok")
    os.close(ready_w)
    stopping = []
    signal.signal(signal.SIGTERM, lambda *_: stopping.append(1))
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    while not stopping and alive(watch):
        time.sleep(poll)
    if field(holder_line(), "keeper") == str(os.getpid()):
        try:
            os.remove(info)
        except OSError:
            pass
    os._exit(0)  # closing the descriptor frees the lock
os.waitpid(child, 0)  # the middle process exits at once; the keeper lives on
os.close(ready_w)
ok = os.read(ready_r, 2)
os.close(ready_r)
os.close(fd)
if ok != b"ok":
    die(71, "the lock keeper did not start")
print(f"held by {holder} since {since}")
PY
