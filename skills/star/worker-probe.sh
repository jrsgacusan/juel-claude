#!/bin/sh
# Tells STAR whether a worker is stuck at a screen it will never leave by itself, stalled on a
# model that is at capacity, or making no progress, without putting the worker's screen into
# STAR's context.
#   worker-probe.sh <dispatch> [--item <item> --home <H> [--worktree <path>] [--deadline <minutes>]]
#     ->   ok | quiet <m> <terminal> | stale <m> <terminal> | settled <state> [<reason>]
#          | stuck: <label> | stalled: model at capacity | gone | unknown <why>
#     ok, quiet and stale end with " holds-screen <m>" when --item holds the screen lock (#39).
# <reason> follows only a failed settlement, when Orca gives one (agent_prompt_stalled: the agent
# never took its prompt, most often because Claude Code's trust dialog was on screen).
# "stuck" labels: usage limit, login, trust dialog, model switch, confirmation dialog, waiting for
# input (a "press enter", a y/n or a password prompt). "stalled: model at capacity" is a capacity,
# overload or rate-limit error on screen: recoverable without the user (#41).
# With --item and --home, progress decides: the newest of <H>/progress/<item>.log, the worktree's
# last commit and the files the worktree has changed. No progress for --deadline minutes (default
# 30) is "stale <m> <terminal>". Without them, or with no progress source at all, the terminal
# decides: no output for STAR_QUIET_MINUTES (default 15) is "quiet <m> <terminal>".
# "gone" means Orca said dispatch_not_found (after an Orca restart) and nothing else: empty,
# shapeless or failing output is "unknown" and says nothing about the worker, so it never
# justifies starting a second one.
# The patterns are whole phrases from the agents' own blocking screens, looked for only where
# such a screen sits: the last lines of the terminal, or the newest transcript message when it
# is short. Ordinary work that mentions "login", "rate limit" or "switch to main" does not match.
# STAR_NOW (ISO UTC) overrides the clock, for tests.
# Exit: 0, or 64 on bad usage.
STAR_SKILLS_DIR=$(cd "$(dirname "$0")/.." && pwd)
export STAR_SKILLS_DIR
exec python3 - "$@" <<'PY'
import json
import math
import os
import re
import subprocess
import sys
import time
from datetime import datetime

# Phrases from the blocking screens of Claude Code and Codex, as their own binaries print them.
PATTERNS = [
    ("usage limit", r"usage limit reached|hit your usage limit|limit will reset|out of extra usage"
                    r"|^\W*credit balance too low|^\W*you've reached your [\w .-]+ limit\b"
                    r"|^\W*your workspace is out of credits"),
    ("login", r"please run /login|^\W*not logged in\b|sign in (again )?to continue|^\W*invalid api key"
              r"|^\W*authentication required\b|^\W*invalid auth token\b|^\W*sign-in required"),
    ("trust dialog", r"do you trust the files in this folder|trust this folder"),
    ("model switch", r"would you like to switch (to|models?)\b|^\W*(\d+\.\s+)?switch to [\w .-]+ and continue\b"
                     r"|^\W*switch to [\w .-]+ for lower credit usage\?"),
    ("confirmation dialog", r"^\s*(❯\s*)?\d+\.\s+no, exit\b"),
    # Screens that wait for a key or a typed answer: a check-in line plus Enter would answer them.
    ("waiting for input", r"^\W*press (enter|return|any key)\b|^\W*(password|passphrase)( for [^:]*)?:\s*$"),
]
# A model at capacity, overloaded or rate limited: the agent waits, and a retry nudge restarts it (#41).
STALLED = (r"selected model is at capacity|\bmodel is at capacity\b|overloaded_error"
           r"|\bapi error:?\s*(429|503|529)\b|rate_limit_error|^\W*(error:?\s*)?too many requests\b")
# A y/n prompt counts only on the last line of the screen: mid-screen it is the worker talking about one.
YES_NO = r"[\[(](y/n|yes/no)[\])]\s*:?\s*$"
# A question counts as a dialog only with a numbered yes/no option on screen: prose asks
# questions too. Every permission prompt ("Do you want to make this edit to X?", "Do you want to
# create X?", "Would you like to run the following command?") has that shape, so none of them is
# ever reported as merely quiet: STAR's check-in ends with Enter, which would answer the prompt.
QUESTION = r"\b(do you want to|would you like to)\b.*\?\s*$"
OPTION = r"^\s*(❯\s*)?\d+\.\s+(yes|no)\b"
BOX = "│┃|║╭╮╰╯─━═ \t"  # a TUI frame around a line is not part of the line
USAGE = "usage: worker-probe.sh <dispatch> [--item <item> --home <H> [--worktree <path>] [--deadline <minutes>]]"


def out(line):
    print(line)
    sys.exit(0)


args, opts, dispatch = sys.argv[1:], {}, None
while args:
    arg = args.pop(0)
    if arg in ("--item", "--home", "--worktree", "--deadline"):
        if not args or not args[0].strip():
            print(USAGE, file=sys.stderr)
            sys.exit(64)
        opts[arg[2:]] = args.pop(0)
    elif arg.startswith("-") or dispatch is not None:
        print(USAGE, file=sys.stderr)
        sys.exit(64)
    else:
        dispatch = arg
if dispatch is None or ("item" in opts) != ("home" in opts):
    print(USAGE, file=sys.stderr)
    sys.exit(64)
orca = os.environ.get("ORCA_CLI_COMMAND") or "orca"
NOW = (datetime.fromisoformat(os.environ["STAR_NOW"].replace("Z", "+00:00")).timestamp()
       if os.environ.get("STAR_NOW") else time.time())


def call(*args):
    try:
        proc = subprocess.run([orca, "orchestration", *args, "--dispatch", dispatch, "--json"],
                              capture_output=True, text=True, timeout=30)
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        out(f"unknown {type(e).__name__}")
    try:
        data = json.loads(proc.stdout)
    except ValueError:
        data = None
    if proc.returncode != 0 or (isinstance(data, dict) and data.get("ok") is False):
        error = data.get("error") if isinstance(data, dict) else None
        codes = [error] if isinstance(error, str) else []
        if isinstance(error, dict):
            inner = error.get("data")
            codes = [error.get("code"), inner.get("code") if isinstance(inner, dict) else None]
        codes = [c for c in codes if isinstance(c, str) and c]
        first_err = ((proc.stderr or "").strip().splitlines() or [""])[0]
        if any(c.lower() == "dispatch_not_found" for c in codes) or "dispatch_not_found" in first_err.lower():
            out("gone")
        out("unknown " + (codes[0] if codes else first_err[:100] or "orca failed"))
    if not isinstance(data, dict) or not isinstance(data.get("result"), dict):
        out("unknown unreadable orca output")
    return data["result"]


TERMINAL = {"failed", "succeeded", "stopped", "cancelled", "canceled", "abandoned", "outcome_unknown"}
shown = call("worker-show")
worker = shown.get("worker") or {}
dispatch_record = shown.get("dispatch") or {}
if not isinstance(worker, dict) or not isinstance(dispatch_record, dict):
    out("unknown unreadable orca output")
if not worker and not dispatch_record:
    out("unknown no worker record")


def reason(state):
    """Orca's reason for a failed dispatch (agent_prompt_stalled), when it gives one."""
    if state != "failed":
        return ""
    for record in (dispatch_record, worker):
        for key in ("last_failure", "lastFailure"):
            value = record.get(key)
            if isinstance(value, dict):
                value = value.get("code") or value.get("reason")
            if isinstance(value, str) and re.fullmatch(r"[a-z][a-z0-9_]{0,60}", value):
                return " " + value
    return ""


if worker.get("stage") == "settled" or worker.get("state") in TERMINAL:
    state = worker.get("state") or "unknown"
    out("settled " + state + reason(state))
if dispatch_record.get("status") in ("completed", "failed"):
    out("settled " + dispatch_record["status"] + reason(dispatch_record["status"]))
read = call("worker-read", "--limit", "40")
terminal, messages = read.get("terminal"), read.get("messages")
lines = [str(l) for l in ((terminal or {}).get("tail") or [])][-25:] if isinstance(terminal, dict) else []
if isinstance(messages, list) and messages and isinstance(messages[-1], dict):
    newest = str(messages[-1].get("text") or messages[-1].get("content") or "")
    if len(newest) <= 400:  # a blocking notice is short; a long message is the worker talking
        lines += newest.splitlines()
lines = [l for l in (l.strip(BOX) for l in lines) if len(l) <= 200]
if any(re.search(STALLED, l, re.IGNORECASE) for l in lines):
    out("stalled: model at capacity")
for label, pattern in PATTERNS:
    if any(re.search(pattern, l, re.IGNORECASE) for l in lines):
        out("stuck: " + label)
if any(re.search(QUESTION, l, re.IGNORECASE) for l in lines) and any(re.search(OPTION, l, re.IGNORECASE) for l in lines):
    out("stuck: confirmation dialog")
last_line = next((l for l in reversed(lines) if l.strip()), "")
if re.search(YES_NO, last_line, re.IGNORECASE) and not last_line.lstrip().startswith(("⏺", "●", "-", "*")):
    out("stuck: waiting for input")


def screen_suffix():
    """" holds-screen <m>" when --item holds the machine's screen lock (#39)."""
    if "item" not in opts:
        return ""
    script = os.path.join(os.environ["STAR_SKILLS_DIR"], "ship-ticket", "screen-lock.sh")
    try:
        status = subprocess.run(["sh", script, "status"], capture_output=True, text=True, timeout=30).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""
    m = re.match(r"held by (\S+) since (\S+)", status)
    if not m or m.group(1) != "_".join(opts["item"].split()):
        return ""
    try:
        since = datetime.fromisoformat(m.group(2).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return ""
    return f" holds-screen {max(int((NOW - since) // 60), 0)}"


def progress_minutes():
    """Whole minutes since the item last made progress; None when there is nothing to read."""
    times = []
    log = os.path.join(opts["home"], "progress", f"{opts['item']}.log")
    if os.path.isfile(log):
        times.append(os.path.getmtime(log))
    wt = opts.get("worktree")
    if wt and os.path.isdir(wt):
        try:
            r = subprocess.run(["git", "-C", wt, "log", "-1", "--format=%ct"], capture_output=True, text=True, timeout=30)
            if r.returncode == 0 and r.stdout.strip().isdigit():
                times.append(int(r.stdout.strip()))
            r = subprocess.run(["git", "-C", wt, "status", "--porcelain", "-z", "--untracked-files=all"],
                               capture_output=True, text=True, timeout=30)
            for entry in (r.stdout.split("\0") if r.returncode == 0 else [])[:500]:
                if len(entry) < 4:  # "XY <path>" is 4 or more: the trailing empty entry would name the root
                    continue
                try:
                    times.append(os.path.getmtime(os.path.join(wt, entry[3:])))
                except (OSError, ValueError):
                    pass
        except (OSError, subprocess.TimeoutExpired):
            pass
    return max(int((NOW - max(times)) // 60), 0) if times else None


def quiet_minutes(handle):
    """Whole minutes since the worker's terminal last printed; None when the list cannot be read.
    A running worker whose terminal is not in a readable list, or whose last output is dated in
    the future, is "unknown": saying "ok" would hide a worker nobody can see."""
    try:
        proc = subprocess.run([orca, "terminal", "list", "--limit", "500", "--json"],
                              capture_output=True, text=True, timeout=30)
        terminals = json.loads(proc.stdout)["result"]["terminals"]
    except Exception:
        return None
    last = next((t.get("lastOutputAt") for t in terminals if isinstance(t, dict) and t.get("handle") == handle), None)
    if not isinstance(last, (int, float)):
        out("unknown terminal not listed")
    minutes = int((NOW * 1000 - float(last)) // 60000)
    if minutes < -1:
        out("unknown clock skew")
    return max(minutes, 0)


handle = worker.get("agent_terminal_handle")
if "item" in opts:
    try:
        deadline = float(opts.get("deadline", "30"))
    except ValueError:
        deadline = 30.0
    if not math.isfinite(deadline) or deadline <= 0:
        deadline = 30.0
    progress = progress_minutes()
    if progress is not None:
        if progress >= deadline:
            out(f"stale {progress} {handle or '-'}" + screen_suffix())
        out("ok" + screen_suffix())
try:
    threshold = float(os.environ.get("STAR_QUIET_MINUTES", "15"))
except ValueError:
    threshold = 15.0
if not math.isfinite(threshold) or threshold <= 0:
    threshold = 15.0
minutes = quiet_minutes(handle) if handle else None
if minutes is not None and minutes >= threshold:
    out(f"quiet {minutes} {handle}" + screen_suffix())
out("ok" + screen_suffix())
PY
