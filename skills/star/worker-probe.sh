#!/bin/sh
# Tells STAR whether a worker is stuck at a screen it will never leave by itself, without
# putting the worker's screen into STAR's context.
#   worker-probe.sh <dispatch>
#     ->   ok | quiet <minutes> <terminal> | settled <state> | stuck: <label> | gone | unknown <why>
# "quiet" means the worker is running but its terminal has printed nothing for STAR_QUIET_MINUTES
# (default 15): it may have ended its turn without reporting, or be waiting on a long command.
# STAR checks in on it through that terminal; it is never a reason to stop the worker.
# "gone" means Orca said dispatch_not_found (after an Orca restart) and nothing else: empty,
# shapeless or failing output is "unknown" and says nothing about the worker, so it never
# justifies starting a second one.
# The patterns are whole phrases from the agents' own blocking screens, looked for only where
# such a screen sits: the last lines of the terminal, or the newest transcript message when it
# is short. Ordinary work that mentions "login" or "switch to main" does not match.
exec python3 - "$@" <<'PY'
import json
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
                     r"|^\W*switch to [\w .-]+ for lower credit usage\?|^\W*(\d+\.\s+)?(no, )?keep (my )?current model\b"),
    ("confirmation dialog", r"^\s*(❯\s*)?\d+\.\s+no, exit\b"),
]
# A question counts as a dialog only with a numbered yes/no option on screen: prose asks
# questions too. Every permission prompt ("Do you want to make this edit to X?", "Do you want to
# create X?", "Would you like to run the following command?") has that shape, so none of them is
# ever reported as merely quiet: STAR's check-in ends with Enter, which would answer the prompt.
QUESTION = r"\b(do you want to|would you like to)\b.*\?\s*$"
OPTION = r"^\s*(❯\s*)?\d+\.\s+(yes|no)\b"
BOX = "│┃|║╭╮╰╯─━═ \t"  # a TUI frame around a line is not part of the line


def out(line):
    print(line)
    sys.exit(0)


if len(sys.argv) != 2:
    print("usage: worker-probe.sh <dispatch>", file=sys.stderr)
    sys.exit(64)
orca = os.environ.get("ORCA_CLI_COMMAND") or "orca"


def call(*args):
    try:
        proc = subprocess.run([orca, "orchestration", *args, "--dispatch", sys.argv[1], "--json"],
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
dispatch = shown.get("dispatch") or {}
if not isinstance(worker, dict) or not isinstance(dispatch, dict):
    out("unknown unreadable orca output")
if not worker and not dispatch:
    out("unknown no worker record")
if worker.get("stage") == "settled" or worker.get("state") in TERMINAL:
    out("settled " + (worker.get("state") or "unknown"))
if dispatch.get("status") in ("completed", "failed"):
    out("settled " + dispatch["status"])
read = call("worker-read", "--limit", "40")
terminal, messages = read.get("terminal"), read.get("messages")
lines = [str(l) for l in ((terminal or {}).get("tail") or [])][-25:] if isinstance(terminal, dict) else []
if isinstance(messages, list) and messages and isinstance(messages[-1], dict):
    newest = str(messages[-1].get("text") or messages[-1].get("content") or "")
    if len(newest) <= 400:  # a blocking notice is short; a long message is the worker talking
        lines += newest.splitlines()
lines = [l for l in (l.strip(BOX) for l in lines) if len(l) <= 200]
for label, pattern in PATTERNS:
    if any(re.search(pattern, l, re.IGNORECASE) for l in lines):
        out("stuck: " + label)
if any(re.search(QUESTION, l, re.IGNORECASE) for l in lines) and any(re.search(OPTION, l, re.IGNORECASE) for l in lines):
    out("stuck: confirmation dialog")


def quiet_minutes(handle):
    """Whole minutes since the worker's terminal last printed, or None when that cannot be told."""
    try:
        proc = subprocess.run([orca, "terminal", "list", "--limit", "500", "--json"],
                              capture_output=True, text=True, timeout=30)
        terminals = json.loads(proc.stdout)["result"]["terminals"]
        last = next(t["lastOutputAt"] for t in terminals if t.get("handle") == handle)
        now = (datetime.fromisoformat(os.environ["STAR_NOW"].replace("Z", "+00:00")).timestamp()
               if os.environ.get("STAR_NOW") else time.time())
        return int((now * 1000 - float(last)) // 60000)
    except Exception:
        return None


handle = worker.get("agent_terminal_handle")
try:
    threshold = float(os.environ.get("STAR_QUIET_MINUTES", "15"))
except ValueError:
    threshold = 15.0
minutes = quiet_minutes(handle) if handle else None
if minutes is not None and minutes >= threshold:
    out(f"quiet {minutes} {handle}")
out("ok")
PY
