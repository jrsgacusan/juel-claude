#!/bin/sh
# Tells STAR whether a worker is stuck at a screen it will never leave by itself, without
# putting the worker's screen into STAR's context.
#   worker-probe.sh <dispatch>   ->   ok | settled <state> | stuck: <label> | gone | unknown <why>
# "gone" means Orca has no such worker (after an Orca restart); "unknown" is any other orca
# failure and says nothing about the worker.
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
    try:
        data = json.loads(proc.stdout or "{}")
    except ValueError:
        data = None
    if proc.returncode != 0 or (isinstance(data, dict) and data.get("ok") is False):
        code = ((data or {}).get("error") or {}).get("code") if isinstance(data, dict) else None
        if code == "dispatch_not_found":
            out("gone")
        out("unknown " + (code or ((proc.stderr or "").strip().splitlines() or ["orca failed"])[0][:100]))
    if data is None:
        out("unknown unreadable orca output")
    return data.get("result") or {}


TERMINAL = {"failed", "succeeded", "stopped", "cancelled", "canceled", "abandoned", "outcome_unknown"}
shown = call("worker-show")
worker = shown.get("worker") or {}
dispatch = shown.get("dispatch") or {}
if not worker and not dispatch:
    out("gone")
if worker.get("stage") == "settled" or worker.get("state") in TERMINAL:
    out("settled " + (worker.get("state") or "unknown"))
if dispatch.get("status") in ("completed", "failed"):
    out("settled " + dispatch["status"])
read = call("worker-read", "--limit", "40")
lines = list((read.get("terminal") or {}).get("tail") or [])
for m in read.get("messages") or []:
    lines += str(m.get("text") or m.get("content") or "").splitlines()
for label, pattern in PATTERNS:
    if any(re.search(pattern, l, re.IGNORECASE) for l in lines[-40:]):
        out("stuck: " + label)
out("ok")
PY
