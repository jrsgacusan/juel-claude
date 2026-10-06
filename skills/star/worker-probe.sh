#!/bin/sh
# Tells STAR whether a worker is stuck at a screen it will never leave by itself, without
# putting the worker's screen into STAR's context.
#   worker-probe.sh <dispatch>   ->   ok | settled <state> | stuck: <label> | gone | unknown <why>
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

PATTERNS = [
    ("usage limit", r"usage limit reached|hit your usage limit|limit will reset|out of extra usage"),
    ("login", r"please run /login|^\W*not logged in\b|sign in to continue|^\W*invalid api key"),
    ("trust dialog", r"do you trust the files in this folder|trust this folder"),
    ("model switch", r"would you like to switch (to|models?)\b"),
    ("confirmation dialog", r"^\s*(❯\s*)?\d+\.\s+no, exit\b"),
]
QUESTION = r"do you want to proceed\?"
OPTION = r"^\s*(❯\s*)?\d+\.\s+(yes|no)\b"


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
        code = ((data or {}).get("error") or {}).get("code") if isinstance(data, dict) else None
        if code == "dispatch_not_found":
            out("gone")
        out("unknown " + (code or ((proc.stderr or "").strip().splitlines() or ["orca failed"])[0][:100]))
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
lines = [str(l) for l in ((terminal or {}).get("tail") or [])][-15:] if isinstance(terminal, dict) else []
if isinstance(messages, list) and messages and isinstance(messages[-1], dict):
    newest = str(messages[-1].get("text") or messages[-1].get("content") or "")
    if len(newest) <= 400:  # a blocking notice is short; a long message is the worker talking
        lines += newest.splitlines()
lines = [l for l in lines if len(l) <= 200]
for label, pattern in PATTERNS:
    if any(re.search(pattern, l, re.IGNORECASE) for l in lines):
        out("stuck: " + label)
if any(re.search(QUESTION, l, re.IGNORECASE) for l in lines) and any(re.search(OPTION, l, re.IGNORECASE) for l in lines):
    out("stuck: confirmation dialog")
out("ok")
PY
