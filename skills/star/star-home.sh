#!/bin/sh
# The one place that knows where a project's STAR folder is.
#   star-home.sh [--cwd <dir>] path   print the folder for the repo containing <dir> (default: here)
#   star-home.sh [--cwd <dir>] init   create it from the template when missing, make git ignore it,
#                                     print it. Safe to repeat; never overwrites a file.
# The folder is <main checkout>/<docsRoot>/context/star. The main checkout is the first worktree
# git lists, so a linked worktree and a subfolder give the same answer. docsRoot follows the
# plugin's rule: "docsRoot" in .claude/workflow.local.json, else .claude/workflow.json; else
# docs/.superpowers when that folder exists and is not empty; else docs/superpowers.
# Ignoring never edits .gitignore: one line goes into <git common dir>/info/exclude, and only when
# git does not already ignore the folder.
# Exit: 0 ok, 1 not inside a usable git checkout, 64 usage.
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd) exec python3 - "$@" <<'PY'
import fcntl
import json
import os
import shutil
import subprocess
import sys

SUBDIRS = ("inbox", "briefs", "reviews", "gates", "releases", "drafts", "memory")
FILES = ("open-loops.md", "ledger.md", "star.json")


def die(code, msg):
    print(f"star-home.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def git(where, *args):
    return subprocess.run(["git", "-C", where, *args], capture_output=True, text=True)


argv, cwd, cmd = sys.argv[1:], os.getcwd(), None
while argv:
    arg = argv.pop(0)
    if arg == "--cwd":
        if not argv:
            die(64, "--cwd needs a directory")
        cwd = argv.pop(0)
    elif arg in ("path", "init") and cmd is None:
        cmd = arg
    else:
        die(64, f"unknown argument: {arg}")
if cmd is None:
    die(64, "usage: star-home.sh [--cwd <dir>] path|init")

listing = git(cwd, "worktree", "list", "--porcelain")
if listing.returncode != 0:
    die(1, f"{cwd} is not inside a git repository")
first = listing.stdout.split("\n\n")[0].splitlines()
main = next((l[len("worktree "):] for l in first if l.startswith("worktree ")), "")
if not main or "bare" in first or not os.path.isdir(main):
    die(1, "STAR needs a project checkout (this is a bare repository, or its main checkout is gone)")
main = os.path.realpath(main)


def docs_root():
    for name in ("workflow.local.json", "workflow.json"):
        try:
            value = json.load(open(os.path.join(main, ".claude", name), encoding="utf-8")).get("docsRoot")
        except (OSError, ValueError, AttributeError):
            continue
        if isinstance(value, str) and value.strip():
            return os.path.normpath(os.path.join(main, value.strip()))
    dotted = os.path.join(main, "docs", ".superpowers")
    if os.path.isdir(dotted) and os.listdir(dotted):
        return dotted
    return os.path.join(main, "docs", "superpowers")


home = os.path.join(docs_root(), "context", "star")
if cmd == "path":
    print(home)
    sys.exit(0)

os.makedirs(home, exist_ok=True)
lock = open(os.path.join(home, "init.lock"), "w")
fcntl.flock(lock, fcntl.LOCK_EX)
for d in SUBDIRS:
    os.makedirs(os.path.join(home, d), exist_ok=True)
template = os.path.join(os.environ["STAR_SKILL_DIR"], "template")
for name in FILES:
    target = os.path.join(home, name)
    if not os.path.exists(target):
        tmp = f"{target}.tmp.{os.getpid()}"
        shutil.copyfile(os.path.join(template, name), tmp)
        os.replace(tmp, target)

star = os.path.join(home, "star.json")
try:
    data = json.load(open(star, encoding="utf-8"))
except (OSError, ValueError):
    data = None
if isinstance(data, dict) and not data.get("project"):
    data["project"] = {"name": os.path.basename(main), "repo": main}
    tmp = f"{star}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, star)

inside = home == main or home.startswith(main + os.sep)
if inside and git(main, "check-ignore", "-q", os.path.join(home, "star.json")).returncode != 0:
    common = git(main, "rev-parse", "--git-common-dir").stdout.strip()
    exclude = os.path.join(os.path.normpath(os.path.join(main, common)), "info", "exclude")
    line = "/" + os.path.relpath(home, main).replace(os.sep, "/") + "/"
    try:
        os.makedirs(os.path.dirname(exclude), exist_ok=True)
        have = open(exclude, encoding="utf-8", errors="replace").read() if os.path.exists(exclude) else ""
        if line not in have.splitlines():
            with open(exclude, "a", encoding="utf-8") as f:
                f.write(("" if have.endswith("\n") or not have else "\n") + line + "\n")
    except OSError as e:
        print(f"star-home.sh: could not make git ignore {home} ({e.strerror}); add '{line}' to .git/info/exclude yourself",
              file=sys.stderr)
print(home)
PY
