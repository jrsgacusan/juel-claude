#!/bin/sh
# Reads STAR's Orca inbox and prints only what STAR acts on, so heartbeats, replays and Orca's
# JSON quirks never reach STAR's context.
#   messages.sh [--home H] [--ack <delivery>] [--wait] [--timeout-ms <n>]
# Runs `orca orchestration check [--ack D] [--wait] --types worker_done,escalation,question
# [--timeout-ms N] --json`. Keeps worker_done, escalation and question messages. Drops heartbeats
# (Orca returns them whatever --types says), "Rejected heartbeat" notices, every other type, and
# any message whose id is already in <home>/processed.log. A batch with nothing left is
# acknowledged here and the wait goes on for the rest of the timeout, so STAR is never woken for
# nothing; after 50 such rounds it gives up with "none".
# Output:
#   delivery <id> <n>        then for each of the n messages:
#   msg <id> <type> <dispatch or -> <sent>[ deadline=<iso>]
#     <body line>            at most 12, each indented two spaces
#   cut <n>                  the body had n more lines
#   none                     nothing to act on before the timeout (a timed-out wait included)
#   waiter-exists <pids>     Orca refused the wait: an earlier `orca orchestration check --wait`
#                            still holds this run's waiter; <pids> are the orphaned waits (parent
#                            pid 1: the messages.sh that started them died), comma-separated, or
#                            "-". A wait with a live parent, such as another project's STAR, is
#                            never listed (#38)
#   unknown <code>: <msg>    Orca answered with an error code
#   unknown <why>            Orca could not be read; it says nothing about the workers
# A literal \n (backslash, n) in a body's first line is read as a line break.
# A question's deadline is its sent time plus the minutes of a trailing "deadline=<minutes>"
# (1 to 240; default 30; more than 240 is 240), so a replay computes the same deadline.
# Orca's JSON is read leniently: a raw line break inside a string does not make it unreadable.
# orca runs in its own process group: TERM, INT or HUP to this script ends it too, and a wait
# whose parent session is gone ends itself, so no waiter outlives the STAR command that made it.
# Exit: 0, or 64 on bad usage.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
export STAR_HOME_DEFAULT
exec python3 - "$@" <<'PY'
import json
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

KEEP = ("worker_done", "escalation", "question")
ROUNDS = 50
orca = os.environ.get("ORCA_CLI_COMMAND") or "orca"
child = None


def die(code, msg):
    print(f"messages.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def out(line):
    print(line)
    sys.exit(0)


def stop(signum, _frame):
    """End the orca wait with this script, so it never holds the run's waiter on its own (#38)."""
    if child is not None and child.poll() is None:
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except OSError:
            pass
    sys.exit(128 + signum)


for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(sig, stop)

home, ack, wait, timeout, args = os.environ.get("STAR_HOME_DEFAULT") or "", None, False, None, sys.argv[1:]
while args:
    arg = args.pop(0)
    if arg in ("--home", "--ack", "--timeout-ms"):
        if not args:
            die(64, f"{arg} needs a value")
        value = args.pop(0)
        if arg == "--home":
            home = value
        elif arg == "--ack":
            ack = value
        elif not value.isdigit():
            die(64, "--timeout-ms takes a number of milliseconds")
        else:
            timeout = int(value)
    elif arg == "--wait":
        wait = True
    else:
        die(64, f"unknown argument: {arg}")

processed = set()
try:
    with open(os.path.join(home, "processed.log"), encoding="utf-8", errors="replace") as f:
        processed = {line.split()[0] for line in f if line.split()}
except OSError:
    pass


def stale_waiters():
    try:
        found = subprocess.run(["pgrep", "-P", "1", "-f", "orchestration check.*--wait"], capture_output=True, text=True,
                               timeout=10).stdout.split()
    except (OSError, subprocess.TimeoutExpired):
        return "-"
    return ",".join(p for p in found if p.isdigit() and int(p) != os.getpid()) or "-"


def check(ack_id, wait_ms):
    global child
    cmd = [orca, "orchestration", "check"]
    if ack_id:
        cmd += ["--ack", ack_id]
    if wait_ms is not None:
        cmd += ["--wait"]
    cmd += ["--types", ",".join(KEEP)]
    if wait_ms is not None:
        cmd += ["--timeout-ms", str(wait_ms)]
    cmd += ["--json"]
    deadline = time.monotonic() + (wait_ms or 0) / 1000 + 60
    try:
        child = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                 start_new_session=True)
    except OSError as e:
        out(f"unknown {type(e).__name__}")
    while True:
        try:
            stdout, stderr = child.communicate(timeout=5)
            break
        except subprocess.TimeoutExpired:
            orphaned = os.getppid() == 1
            if orphaned or time.monotonic() > deadline:
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                except OSError:
                    pass
                child.communicate()
                out("unknown " + ("orphaned: the session that started this wait is gone" if orphaned else "TimeoutExpired"))
    returncode, child = child.returncode, None
    try:
        data = json.loads(stdout, strict=False)
    except ValueError:
        data = None
    error = data.get("error") if isinstance(data, dict) else None
    code = (error.get("code") if isinstance(error, dict) else error) or ""
    if isinstance(code, str) and "timeout" in code.lower():
        return {}
    if returncode != 0 or not isinstance(data, dict) or data.get("ok") is False:
        if isinstance(error, dict) and isinstance(code, str) and code:
            if code.lower() == "waiter_exists":
                out("waiter-exists " + stale_waiters())
            message = (str(error.get("message") or "").strip().splitlines() or ["-"])[0][:100]
            out(f"unknown {code}: {message}")
        first = ((stderr or stdout or "").strip().splitlines() or [""])[0][:100]
        out("unknown " + (first or "unreadable orca output"))
    return data.get("result") if isinstance(data.get("result"), dict) else {}


def payload(m):
    p = m.get("payload")
    if isinstance(p, str):
        try:
            p = json.loads(p, strict=False)
        except ValueError:
            p = {}
    return p if isinstance(p, dict) else {}


def wanted(m):
    if not isinstance(m, dict) or m.get("type") not in KEEP:
        return False
    if f"{m.get('subject') or ''} {m.get('body') or ''}".strip().lower().startswith("rejected heartbeat"):
        return False
    return str(m.get("id")) not in processed


def deadline_for(body, sent):
    found = re.search(r"\bdeadline=(\d{1,6})\s*$", body.strip())
    minutes = int(found.group(1)) if found else 30
    minutes = 30 if minutes < 1 else min(minutes, 240)
    try:
        start = datetime.fromisoformat(sent.replace("Z", "+00:00"))
    except ValueError:
        start = datetime.now(timezone.utc)
    return (start + timedelta(minutes=minutes)).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def show(m):
    p, body, sent = payload(m), str(m.get("body") or ""), str(m.get("created_at") or "-")
    first, sep, rest = body.partition("\n")
    # A report typed with an escaped "\n" inside a quoted --body arrives with a literal backslash-n
    # on its first line; split it there so one bad report cannot glue its fields together (#22).
    # Later lines keep theirs: a NOTE may quote "\n" on purpose.
    body = first.replace("\\n", "\n") + sep + rest
    line = f"msg {m.get('id')} {m.get('type')} {p.get('dispatchId') or p.get('dispatch_id') or '-'} {sent}"
    if m.get("type") == "question":
        line += " deadline=" + deadline_for(body, sent)
    print(line)
    lines = body.splitlines()
    for l in lines[:12]:
        print("  " + l)
    if len(lines) > 12:
        print(f"cut {len(lines) - 12}")


end = time.monotonic() + (timeout or 0) / 1000
pending = ack
for _ in range(ROUNDS):
    left = max(0, int((end - time.monotonic()) * 1000)) if wait else None
    result = check(pending, left)
    pending = None
    delivery = result.get("deliveryId") or result.get("delivery_id")
    keep = [m for m in (result.get("messages") or []) if wanted(m)]
    if keep:
        print(f"delivery {delivery or '-'} {len(keep)}")
        for m in keep:
            show(m)
        sys.exit(0)
    if not delivery:
        break
    pending = delivery  # a batch of heartbeats and replays only: acknowledge it with the next call
    if not wait or time.monotonic() >= end:
        break
if pending:
    check(pending, None)
out("none")
PY
