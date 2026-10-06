#!/bin/sh
# Tells STAR whether a worker is stuck at a screen it will never leave by itself, without
# putting the worker's screen into STAR's context.
#   worker-probe.sh <dispatch>   ->   ok | settled <state> | stuck: <label> | unknown <why>
# The patterns are whole phrases from the agents' own blocking screens, so ordinary work
# that merely mentions "login" does not match.
exec python3 - "$@" <<'PY'
import json
import os
import re
import subprocess
import sys

PATTERNS = [
    ("usage limit", r"usage limit reached|hit your usage limit|limit will reset|out of extra usage"),
    ("login", r"please run /login|not logged in|sign in to continue|invalid api key"),
    ("trust dialog", r"do you trust the files in this folder|trust this folder"),
    ("model switch", r"would you like to switch|switch to .* to continue"),
    ("confirmation dialog", r"^\s*(❯\s*)?\d+\.\s+no, exit\b|do you want to proceed\?"),
]


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
    if proc.returncode != 0:
        out("unknown " + ((proc.stderr or "").strip().splitlines() or ["orca failed"])[0][:100])
    try:
        return json.loads(proc.stdout).get("result") or {}
    except ValueError:
        out("unknown unreadable orca output")


worker = call("worker-show").get("worker") or {}
if worker.get("stage") == "settled":
    out("settled " + (worker.get("state") or "unknown"))
read = call("worker-read", "--limit", "40")
lines = list((read.get("terminal") or {}).get("tail") or [])
for m in read.get("messages") or []:
    lines += str(m.get("text") or m.get("content") or "").splitlines()
for label, pattern in PATTERNS:
    if any(re.search(pattern, l, re.IGNORECASE) for l in lines[-40:]):
        out("stuck: " + label)
out("ok")
PY
