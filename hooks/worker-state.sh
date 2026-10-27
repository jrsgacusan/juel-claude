#!/bin/sh
# Hook for SessionStart, UserPromptSubmit, Stop, StopFailure and Notification (#208). Inside an Orca
# terminal it records what the session just told Claude Code's hooks in
# <star home>/workers/<ORCA_TERMINAL_HANDLE>.json, so worker-probe.sh can name a stall from the event
# instead of guessing from the screen: {"handle", "session", "event", "kind", "message", "at"}.
# StopFailure writes kind=error, Notification kind=notification_type; SessionStart, UserPromptSubmit
# and Stop write event "clear", so a state stands only until the worker takes a new turn.
# Prints nothing (a UserPromptSubmit hook's stdout reaches the model), deletes files in workers/
# older than 7 days, and never fails a session: always exit 0.
[ -n "${ORCA_TERMINAL_HANDLE:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
STAR_HOOK_INPUT=$(cat) STAR_HOME_SH="$(cd "$(dirname "$0")" && pwd)/../skills/star/star-home.sh" python3 - <<'PY' >/dev/null 2>&1
import json
import os
import re
import subprocess
import time
from datetime import datetime, timezone

handle = os.environ.get("ORCA_TERMINAL_HANDLE") or ""
if not re.fullmatch(r"[A-Za-z0-9_.-]+", handle) or handle.startswith("."):
    raise SystemExit(0)
try:
    data = json.loads(os.environ.get("STAR_HOOK_INPUT") or "{}")
    if not isinstance(data, dict):
        raise SystemExit(0)
    event = data.get("hook_event_name")
    if event in ("SessionStart", "UserPromptSubmit", "Stop"):
        state = ("clear", "", "")
    elif event == "StopFailure":
        state = (event, str(data.get("error") or ""), str(data.get("error_details") or ""))
    elif event == "Notification":
        state = (event, str(data.get("notification_type") or ""), str(data.get("message") or ""))
    else:
        raise SystemExit(0)
    cwd = data.get("cwd") or os.getcwd()
    home = subprocess.run(["sh", os.environ["STAR_HOME_SH"], "--cwd", cwd, "path"],
                          capture_output=True, text=True, timeout=10).stdout.strip()
    if not home or not os.path.isdir(home):
        raise SystemExit(0)
    folder = os.path.join(home, "workers")
    os.makedirs(folder, exist_ok=True)
    record = {"handle": handle, "session": str(data.get("session_id") or ""), "event": state[0], "kind": state[1],
              "message": " ".join(state[2].split())[:120],
              "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    path = os.path.join(folder, handle + ".json")
    tmp = path + f".{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(record, f)
    os.replace(tmp, path)
    cutoff = time.time() - 7 * 86400
    for name in os.listdir(folder):
        p = os.path.join(folder, name)
        try:
            if os.path.isfile(p) and os.path.getmtime(p) < cutoff:
                os.remove(p)
        except OSError:
            pass
except SystemExit:
    raise
except Exception:
    pass
PY
exit 0
