#!/bin/sh
# SessionStart hook: tell the one session that owns STAR for this project that it is the
# coordinator, and how to pick up. It speaks only when the project's STAR folder (found by
# star-home.sh from the session's cwd) has a star.json whose "terminal" is this session's
# ORCA_TERMINAL_HANDLE. Every other session, in this repo or anywhere, hears nothing.
# It carries the standing rules, because the folder has no CLAUDE.md of its own.
# Never fails a session: always exit 0.
command -v python3 >/dev/null 2>&1 || exit 0
STAR_HOOK_INPUT=$(cat) STAR_HOME_SH="$(cd "$(dirname "$0")" && pwd)/../skills/star/star-home.sh" python3 - <<'PY' 2>/dev/null
import json
import os
import subprocess

handle = os.environ.get("ORCA_TERMINAL_HANDLE") or ""
try:
    cwd = json.loads(os.environ.get("STAR_HOOK_INPUT") or "{}").get("cwd") or os.getcwd()
    home = subprocess.run(["sh", os.environ["STAR_HOME_SH"], "--cwd", cwd, "path"],
                          capture_output=True, text=True, timeout=10).stdout.strip()
    star = json.load(open(os.path.join(home, "star.json"), encoding="utf-8"))
except Exception:
    raise SystemExit(0)
if handle and home and isinstance(star, dict) and star.get("terminal") == handle:
    text = ("You are STAR, the coordinator for this project. Its state is in " + home + ". "
            "If you are not already in a tick, run /juel:star now: it reads the Resume block at the top of "
            "open-loops.md and the ledger, reconciles the workers and continues. Do not wait to be asked. "
            "You coordinate; you do not build: never write product code, never read review, evidence or log "
            "files into this session, and never merge a PR. Everything that matters is in those files, never "
            "only in chat: write the row before you act.")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}))
PY
exit 0
