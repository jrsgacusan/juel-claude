#!/bin/sh
# gh-token.sh [--home <dir>] prints the token for the account star.json configures, or nothing.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
export SCRIPT_DIR
exec python3 - "$@" <<'PY'
import json
import os
import re
import subprocess
import sys


def usage():
    print("gh-token.sh: usage: gh-token.sh [--home <dir>]", file=sys.stderr)
    sys.exit(64)


args = sys.argv[1:]
home = None
if args:
    if args[0] != "--home" or len(args) != 2 or not args[1]:
        usage()
    home = args[1]
if home is None:
    home = os.environ.get("JUEL_STAR_HOME") or ""
if not home:
    try:
        script_dir = os.environ.get("SCRIPT_DIR") or os.path.dirname(os.path.abspath(sys.argv[0]))
        path = subprocess.run(["sh", os.path.join(script_dir, "star-home.sh"), "path"],
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        if path.returncode == 0:
            lines = path.stdout.splitlines()
            home = lines[0].strip() if lines else ""
    except (OSError, subprocess.TimeoutExpired):
        home = ""

try:
    with open(os.path.join(home, "star.json"), encoding="utf-8") as f:
        star = json.load(f)
    if not isinstance(star, dict):
        raise ValueError
    command = star.get("tokenCmd")
    if command is None:
        login = star.get("ghLogin")
        command = None
        if isinstance(login, str) and re.fullmatch(r"[A-Za-z0-9-]+", login):
            proc = subprocess.run(["gh", "auth", "token", "--user", login],
                                  stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        else:
            proc = None
    elif isinstance(command, str) and command.strip() and "\n" not in command and "\r" not in command:
        proc = subprocess.run(["sh", "-c", command], stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=30)
    else:
        proc = None
    if proc is not None and proc.returncode == 0:
        token = proc.stdout.strip()
        if token and "\n" not in token and "\r" not in token:
            print(token)
except (OSError, ValueError, TypeError, AttributeError, subprocess.TimeoutExpired):
    pass
PY
