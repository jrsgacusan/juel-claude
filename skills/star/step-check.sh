#!/bin/sh
# Says what one STAR worker is doing and what STAR should do about it, from the evidence on disk,
# so STAR never reads a progress log, a review or a gate transcript into its own context.
#   step-check.sh --item <item> --home H --state <row state> [--worktree W] [--pr <url>]
#                 [--deadline <minutes>] [--asked <iso>] [--hosted <login>]
#     ->   ok <step> | note <step> <diagnosis> | act <step> <diagnosis> -- <instruction>
#          | restart <step> <diagnosis> | unknown <why>
# <state> is the row's state: briefing, building, babysitting or posting. <step> is the token of
# the newest line of H/progress/<item>.log, "<iso> <token> <text>" (phase<N>, executor,
# live-check, regression-gate, gate-r<k>, post-pass, ready, wait-hosted, wait-ci, sync, report;
# any other token is a step with no instruction of its own), or gate-r<k> while a gate round's run
# file exists. In a babysitting row, phase2, wait-hosted and wait-ci are its waits: for feedback,
# for the hosted review and for CI. First match wins:
#   no progress log, or no dated line in it           unknown no-progress-source
#   <reviews>/<item>-r<k>.run (the newest k) whose pid or gate pid is alive:
#     its log changed in the last 20 min               ok gate-r<k>
#     its log silent 20 min or more                    act gate-r<k> log silent <m> min -- stop it, rerun round <k>
#   a run file whose pids are both gone, no verdict of round <k> newer than the run, and nothing
#     written (its log, a progress line) for 10 min    restart gate-r<k> gate process gone
#   step gate-r<k>, <reviews>/<item>-r<k>.md newer than the step's line and 15 min old:
#     --asked 15 min or more ago                       restart gate-r<k> verdict unread after an instruction
#     otherwise                                        act gate-r<k> verdict unread -- read its first line
#   with --pr, one pr-state.sh snapshot of the PR (no --wait), only once no gate row applied:
#     babysitting, step phase2, wait-hosted or wait-ci, --hosted's status success on the head, checks
#     green, the step's line 15 min old:
#       --asked 15 min or more ago                     restart <step> hosted review passed on <sha7>, worker still waiting after an instruction
#       otherwise                                      act <step> hosted review passed on <sha7> -- judge it and report READY
#   the newest activity older than --deadline (30)     act <step> no progress <m> min -- <the step's instruction>
#   a ready PR, checks green, --hosted with no status on the head, outside star.json's quietHours
#                                                      note <step> checks green, no hosted run on <sha7>
#   babysitting, and the PR conflicts with its base    note <step> PR conflicts with its base
#   otherwise                                          ok <step>
# A PR that cannot be read adds nothing; a quiet window that cannot be judged counts as inside.
# Activity is the progress line, the worktree's last commit and changed files (with --worktree),
# and, at a gate-r<k> step, that round's verdict, log and error logs. An act whose instruction STAR
# sent less than 15 minutes ago (--asked) prints "note <step> instructed <m> min ago: <diagnosis>"
# instead, so the worker has time to answer; an --asked older than the newest progress line is
# ignored, since the worker has moved. --pr and --hosted name the PR and its hosted reviewer.
# <reviews> is H/reviews/<star.json's project.name>.
# STAR_NOW (ISO UTC) overrides the clock, STEP_CHECK_PR_STATE the path of pr-state.sh; QUIET_NOW reaches
# quiet-hours.sh. For tests.
# Exit: 0 with one line; 64 on bad usage.
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
export STAR_SKILL_DIR
exec python3 - "$@" <<'PY'
import json
import math
import os
import re
import subprocess
import sys
import time
from datetime import datetime

S = os.environ["STAR_SKILL_DIR"]
STATES = ("briefing", "building", "babysitting", "posting")
OPTIONS = ("--item", "--home", "--state", "--worktree", "--pr", "--deadline", "--asked", "--hosted")
LOG_SILENT, GONE, ANSWER = 20, 10, 15  # minutes: a silent gate log, a dead gate's grace, time to answer
USAGE = ("usage: step-check.sh --item <item> --home H --state <row state> [--worktree W] [--pr <url>] "
         "[--deadline <minutes>] [--asked <iso>] [--hosted <login>]")
GENERIC = ("STAR checking in on {item}: say in one line where you are. Waiting on a background command: "
           "keep waiting. Blocked or unsure: ask me with orca orchestration ask. Finished: send your "
           "worker_done report now.")


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(64)


def out(line):
    print(line)
    sys.exit(0)


def when(value):
    """Seconds since the epoch for an ISO time, or None."""
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


args, opts = sys.argv[1:], {}
while args:
    arg = args.pop(0)
    if arg not in OPTIONS or not args or not args[0].strip():
        usage()
    opts[arg[2:]] = args.pop(0).strip()
if not all(k in opts for k in ("item", "home", "state")) or opts["state"] not in STATES:
    usage()
item, home, state = opts["item"], opts["home"], opts["state"]
try:
    deadline = float(opts.get("deadline", "30"))
except ValueError:
    usage()
if not math.isfinite(deadline) or deadline <= 0:
    usage()
asked = when(opts["asked"]) if "asked" in opts else None
if "asked" in opts and asked is None:
    usage()
NOW = when(os.environ.get("STAR_NOW") or "") or time.time()


def minutes(t):
    return max(int((NOW - t) // 60), 0)


def mtime(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return None


try:
    star = json.load(open(os.path.join(home, "star.json"), encoding="utf-8"))
except (OSError, ValueError):
    star = {}
star = star if isinstance(star, dict) else {}
project = star.get("project") if isinstance(star.get("project"), dict) else {}
reviews = os.path.join(home, "reviews", str(project.get("name") or "-"))

log = os.path.join(home, "progress", f"{item}.log")
try:
    lines = [l.strip() for l in open(log, encoding="utf-8", errors="replace") if l.strip()]
except OSError:
    lines = []
said_at, token = None, None
for l in reversed(lines):
    m = re.match(r"(\S+)\s+(\S+)", l)
    if m and when(m.group(1)) is not None:
        said_at, token = when(m.group(1)), re.sub(r"[^\w.:#-]", "?", m.group(2))[:40]
        break
if said_at is None:
    out("unknown no-progress-source")
if asked is not None and said_at > asked:
    asked = None  # the worker has written a progress line since the instruction


def act(step, diagnosis, instruction):
    if asked is not None and NOW - asked < ANSWER * 60:
        out(f"note {step} instructed {minutes(asked)} min ago: {diagnosis}")
    out(f"act {step} {diagnosis} -- {instruction}")


def alive(pid):
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # it exists; it belongs to someone else
    except OSError:
        return False
    return True


# A gate round that is running, or whose process died without cleaning up its run file
runs = []
try:
    for name in os.listdir(reviews):
        m = re.fullmatch(re.escape(item) + r"-r(\d+)\.run", name)
        if m:
            runs.append((int(m.group(1)), os.path.join(reviews, name)))
except OSError:
    pass
if runs:
    k, path = max(runs)
    step = f"gate-r{k}"
    try:
        run = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        run = None
    if isinstance(run, dict):
        log_path = run["log"] if isinstance(run.get("log"), str) else os.path.join(reviews, f"{item}-r{k}.log")
        changed = mtime(log_path) or mtime(path) or NOW
        pids = "/".join(str(run[key]) for key in ("pid", "gate") if isinstance(run.get(key), int))
        if alive(run.get("pid")) or alive(run.get("gate")):
            if NOW - changed < LOG_SILENT * 60:
                out(f"ok {step}")
            act(step, f"log silent {minutes(changed)} min",
                f"STAR: gate round {k} has printed nothing for {minutes(changed)} min (pid {pids or '?'}). "
                f"Stop it and run round {k} again; it falls back to Claude by itself.")
        verdict = mtime(os.path.join(reviews, f"{item}-r{k}.md"))
        started = when(run.get("started")) or mtime(path) or 0
        if verdict is None or verdict < started:
            if NOW - max(changed, said_at) >= GONE * 60:
                out(f"restart {step} gate process gone")
            out(f"ok {step}")

# A verdict the worker has not read
gate = re.fullmatch(r"gate-r(\d+)", token)
if gate:
    path = os.path.join(reviews, f"{item}-r{gate.group(1)}.md")
    verdict = mtime(path)
    if verdict is not None and verdict > said_at and NOW - verdict >= ANSWER * 60:
        if asked is not None and NOW - asked >= ANSWER * 60:
            out(f"restart {token} verdict unread after an instruction")
        act(token, "verdict unread",
            f"STAR: round {gate.group(1)}'s verdict is at {path}. Read its first line and continue.")


def activity():
    """The newest of the progress line, the gate round's files, and the worktree's last commit and
    changed files."""
    times = [said_at, mtime(log) or said_at]
    if gate:
        names = [f"{item}-r{gate.group(1)}.md", f"{item}-r{gate.group(1)}.log"]
        try:
            names += [n for n in os.listdir(reviews)
                      if re.fullmatch(re.escape(item) + rf"-r{gate.group(1)}-error-\d+\.log", n)]
        except OSError:
            pass
        times += [t for t in (mtime(os.path.join(reviews, n)) for n in names) if t is not None]
    wt = opts.get("worktree")
    if wt and os.path.isdir(wt):
        try:
            r = subprocess.run(["git", "-C", wt, "log", "-1", "--format=%ct"], capture_output=True, text=True, timeout=30)
            if r.returncode == 0 and r.stdout.strip().isdigit():
                times.append(int(r.stdout.strip()))
            r = subprocess.run(["git", "-C", wt, "status", "--porcelain", "-z", "--untracked-files=all"],
                               capture_output=True, text=True, timeout=30)
            for entry in (r.stdout.split("\0") if r.returncode == 0 else [])[:500]:
                if len(entry) >= 4:  # "XY <path>"; the trailing empty entry would name the root
                    t = mtime(os.path.join(wt, entry[3:]))
                    if t is not None:
                        times.append(t)
        except (OSError, subprocess.TimeoutExpired):
            pass
    return max(times)


def instruction(step, m):
    if state == "babysitting" and step == "phase2":
        return (f"STAR: no wake for {m} min while you wait for feedback in Phase 2. Run pr-state.sh on the PR "
                "once now and act on what it reports.")
    phase = re.fullmatch(r"phase(\d+)", step)
    if phase:
        return (f"STAR: {item} has written no progress line for {m} min in phase {phase.group(1)}. If a command "
                f"is still running, append a progress line naming it; if nothing runs, continue phase "
                f"{phase.group(1)} now.")
    if gate:
        return (f"STAR: gate round {gate.group(1)} shows no run and no verdict after {m} min. Run codex-gate.sh "
                f"for round {gate.group(1)} now; an ERROR keeps the round number, so rerun the same round.")
    return {
        "executor": f"STAR: the executor has changed nothing for {m} min. If codex exec still runs, keep waiting "
                    "and append a progress line; if it exited, read its exit status and continue.",
        "live-check": f"STAR: no live check has finished for {m} min. Append a progress line naming the check "
                      "that runs; if none runs, go on with the next unchecked criterion.",
        "regression-gate": f"STAR: the regression gate shows no progress for {m} min. If it still runs, keep "
                           "waiting and append a progress line; if it ended, read its result and continue.",
        "post-pass": f"STAR: the PASS comment is not posted after {m} min. Run codex-gate.sh post-pass again; "
                     "it waits out GitHub's head lag.",
        "ready": f"STAR: marking the PR ready shows no progress for {m} min. Run gh pr ready unless quiet hours "
                 "hold it, then report.",
        "wait-hosted": f"STAR: no wake for {m} min while you wait for the hosted review. Read the PR's hosted "
                       "status on its head now; when it reviewed the head, judge it and go on.",
        "wait-ci": f"STAR: no wake for {m} min while you wait for CI. Run gh pr checks on the PR now and act on "
                   "what it says.",
        "sync": f"STAR: the base sync shows no progress for {m} min. Finish the merge, run the gates and push, "
                "or escalate the conflict.",
        "report": f"STAR: you have been at the report for {m} min. Send your worker_done report now, as the "
                  "report lines your skill names.",
    }.get(step, GENERIC.format(item=item))


PR_STATE = os.environ.get("STEP_CHECK_PR_STATE") or os.path.join(os.path.dirname(S), "babysit-pr", "pr-state.sh")


def pr_snapshot():
    """One pr-state.sh snapshot of --pr, or None when there is none or it cannot be read."""
    if "pr" not in opts:
        return None
    cmd = ["sh", PR_STATE, opts["pr"]] + (["--hosted", opts["hosted"]] if opts.get("hosted") else [])
    try:
        snap = json.loads(subprocess.run(cmd, capture_output=True, text=True, timeout=300).stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    return snap if isinstance(snap, dict) and "error" not in snap else None


def quiet():
    """True inside star.json's quiet window, and whenever the window cannot be judged."""
    q = star.get("quietHours")
    if not q:
        return False
    try:
        window = f"{q['start']}-{q['end']}@{q['tz']}"
        proc = subprocess.run(["sh", os.path.join(os.path.dirname(S), "ship-ticket", "quiet-hours.sh"), window],
                              capture_output=True, text=True, timeout=30)
    except (KeyError, TypeError, OSError, subprocess.TimeoutExpired):
        return True
    return not (proc.returncode == 0 and proc.stdout.strip() == "outside")


snap = pr_snapshot()
sha = str((snap or {}).get("head") or "")[:7]
if (snap and state == "babysitting" and token in ("phase2", "wait-hosted", "wait-ci") and snap.get("hosted") == "success"
        and snap.get("checks") == "green" and NOW - said_at >= ANSWER * 60):
    if asked is not None and NOW - asked >= ANSWER * 60:
        out(f"restart {token} hosted review passed on {sha}, worker still waiting after an instruction")
    act(token, f"hosted review passed on {sha}",
        f"STAR: the hosted review passed on {sha} and checks are green. Judge the review and report READY.")
newest = activity()
if NOW - newest >= deadline * 60:
    m = minutes(newest)
    act(token, f"no progress {m} min", instruction(token, m))
if (snap and sha and not snap.get("draft") and snap.get("checks") == "green" and opts.get("hosted")
        and snap.get("hosted") == "none" and not quiet()):
    out(f"note {token} checks green, no hosted run on {sha}")
if snap and state == "babysitting" and snap.get("merge") == "dirty":
    out(f"note {token} PR conflicts with its base")
out(f"ok {token}")
PY
