#!/bin/sh
# SessionStart hook, for every session whose folder belongs to a project with a STAR folder (found
# by star-home.sh from the session's cwd; a linked worktree and a subfolder give the same folder).
# The GitHub token (#91, #92, #137): when star.json's "tokenCmd" is a one-line command, GH_TOKEN is
# unset or empty, and Claude Code gave this session a CLAUDE_ENV_FILE, it appends
# export GH_TOKEN="$(<tokenCmd>)" to that file, once. Claude Code runs that file before every Bash
# command, so every command, and every gh a script starts as a subprocess, has the token: Orca
# workers inherit no shell of the owner's. The command is written, never run here, so no token is
# ever written to disk. With tokenCmd null or absent, a valid "ghLogin" uses gh auth token --user
# <ghLogin>; a set but malformed tokenCmd is left alone. A repository with no STAR folder, or one whose
# star.json names no token, takes juel:yuki's: "tokenCmd" in <git common dir>/yuki/yuki.json, the
# same way, so yuki's workers in Orca worktrees outside the owner's folders have the token too.
# The coordinator: it tells the one session that owns STAR for this project that it is the
# coordinator, and how to pick up. It speaks only when star.json's "terminal" is this session's
# ORCA_TERMINAL_HANDLE. Every other session, in this repo or anywhere, hears nothing.
# It carries the standing rules, because the folder has no CLAUDE.md of its own, and the notes every
# worker reads: the always set, from notes.sh list --always (at most 20, each title cut to 60 characters),
# so the coordinator hears it again after every compaction. A notes.sh failure adds nothing.
# Never fails a session: always exit 0.
command -v python3 >/dev/null 2>&1 || exit 0
STAR_HOOK_INPUT=$(cat) STAR_HOME_SH="$(cd "$(dirname "$0")" && pwd)/../skills/star/star-home.sh" STAR_NOTES_SH="$(cd "$(dirname "$0")" && pwd)/../skills/star/notes.sh" python3 - <<'PY' 2>/dev/null
import json
import os
import subprocess
import re

handle = os.environ.get("ORCA_TERMINAL_HANDLE") or ""
home, star = "", {}
try:
    cwd = json.loads(os.environ.get("STAR_HOOK_INPUT") or "{}").get("cwd") or os.getcwd()
except Exception:
    raise SystemExit(0)
try:
    home = subprocess.run(["sh", os.environ["STAR_HOME_SH"], "--cwd", cwd, "path"],
                          capture_output=True, text=True, timeout=10).stdout.strip()
    star = json.load(open(os.path.join(home, "star.json"), encoding="utf-8"))
except Exception:
    star = {}
if not isinstance(star, dict):
    star = {}
command, env_file = star.get("tokenCmd"), os.environ.get("CLAUDE_ENV_FILE") or ""
if command is None:
    login = star.get("ghLogin")
    command = f"gh auth token --user {login}" if isinstance(login, str) and re.fullmatch(r"[A-Za-z0-9-]+", login) else None
if command is None:
    try:
        common = subprocess.run(["git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, timeout=10).stdout.strip()
        yuki = json.load(open(os.path.join(common, "yuki", "yuki.json"), encoding="utf-8")) if common else {}
        command = yuki.get("tokenCmd") if isinstance(yuki, dict) else None
    except Exception:
        command = None
if (isinstance(command, str) and command.strip() and "\n" not in command and "\r" not in command
        and env_file and not os.environ.get("GH_TOKEN")):
    line = 'export GH_TOKEN="$(' + command.strip() + ')"'
    try:
        have = open(env_file, encoding="utf-8", errors="replace").read() if os.path.exists(env_file) else ""
        if line not in have.splitlines():
            with open(env_file, "a", encoding="utf-8") as f:
                f.write(("" if not have or have.endswith("\n") else "\n") + line + "\n")
    except OSError:
        pass
if handle and home and star.get("terminal") == handle:
    text = ("You are STAR, the coordinator for this project. Its state is in " + home + ". "
            "If you are not already in a tick, run /juel:star now: it reads the Resume block at the top of "
            "open-loops.md and the ledger, reconciles the workers and continues. Do not wait to be asked. "
            "You coordinate; you do not build: never write product code, and never read review, evidence or log "
            "files into this session. Merge only through merge.sh, when pr-verify.sh --merge-gate passes on the "
            "exact head. Everything that matters is in those files, never "
            "only in chat: write the row before you act.")
    project = star.get("project")
    name = project.get("name") if isinstance(project, dict) else None
    try:
        listed = subprocess.run(["sh", os.environ["STAR_NOTES_SH"], "--home", home, "--shelf", "memory",
                                 "--project", name, "list", "--always"],
                                capture_output=True, text=True, timeout=10)
        rows = [l.split("\t") for l in listed.stdout.splitlines() if l.strip()] if listed.returncode == 0 else []
        shown = [r[0] + " " + r[-1][:60] for r in rows if len(r) >= 5][:20]
        if shown:
            text += " Notes every worker reads (" + str(len(rows)) + "): " + "; ".join(shown) + "."
    except Exception:
        pass
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}))
PY
exit 0
