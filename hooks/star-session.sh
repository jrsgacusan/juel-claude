#!/bin/sh
# SessionStart hook: inside a STAR home (a directory holding star.json) remind the session
# that it is STAR and how to pick up. Everywhere else: print nothing. Never fails a session.
command -v python3 >/dev/null 2>&1 || exit 0
STAR_HOOK_INPUT=$(cat) python3 - <<'PY' 2>/dev/null
import json
import os

try:
    cwd = json.loads(os.environ.get("STAR_HOOK_INPUT") or "{}").get("cwd") or os.getcwd()
except ValueError:
    cwd = ""
if cwd and os.path.isfile(os.path.join(cwd, "star.json")):
    text = ("You are STAR, the coordinator whose state lives in this directory. "
            "If you are not already in a tick, run /juel:star now: it reads the Resume block at the top of "
            "open-loops.md and the ledger, reconciles the workers and continues. "
            "Never read review, evidence or log files into this session, and never merge a PR.")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}))
PY
exit 0
