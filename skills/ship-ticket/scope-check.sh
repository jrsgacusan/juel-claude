#!/bin/sh
# Lists the files a plan's executor changed that no task of the plan names (#78).
#   scope-check.sh <plan file> <base sha> [--repo-dir <dir>]
# Prints, sorted, one line per changed file that no task's **Files:** block names, then exits 1:
#   outside <path>
# or, when every changed file is named, one line and exit 0:
#   ok
# "Changed" is every path that differs between <base sha> and the working tree, committed or not,
# deletions included (git diff --no-renames --name-only <base>), plus untracked files git does not
# ignore. A **Files:** entry is a backticked path on a line that starts with Create:, Modify:,
# Test: or Delete: (after an optional list marker). A ":<lines>" suffix is dropped, and a path
# ending in "/" names everything under it. Never outside: paths under .superpowers/ (the
# executor's ledger), and the plan's own folder when the plan sits in the repository (only the plan
# file itself when that folder is the repository's top). Only files are checked, never line
# ranges: ranges drift as earlier tasks edit a file, and the review reads the hunks.
# The caller restores each outside file from <base sha>, or deletes it when it is new, and says so.
# Paths are relative to the repository's top level, whatever --repo-dir (default: here) points at.
# Exit: 0 ok; 1 outside lines; 64 bad usage, a plan that cannot be read, a <base sha> that is not
# a commit, or a --repo-dir that is not in a git repository.
exec python3 - "$@" <<'PY'
import os
import re
import subprocess
import sys

ENTRY = re.compile(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)?(?:Create|Modify|Test|Delete):")
TICKED = re.compile(r"`([^`\n]+)`")
LINES = re.compile(r":\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$")


def die(code, msg):
    print(f"scope-check.sh: {msg}", file=sys.stderr)
    sys.exit(code)


argv, repo_dir, args = sys.argv[1:], ".", []
while argv:
    arg = argv.pop(0)
    if arg == "--repo-dir":
        if not argv:
            die(64, "--repo-dir needs a value")
        repo_dir = argv.pop(0)
    elif arg.startswith("-"):
        die(64, f"unknown argument: {arg}")
    else:
        args.append(arg)
if len(args) != 2:
    die(64, "usage: scope-check.sh <plan file> <base sha> [--repo-dir <dir>]")
plan, base = args


def git(cwd, *cmd):
    try:
        proc = subprocess.run(["git", "-C", cwd, *cmd], capture_output=True, text=True)
    except OSError as e:
        die(64, f"cannot run git: {e.strerror}")
    return proc.returncode, proc.stdout


try:
    with open(plan, encoding="utf-8") as f:
        text = f.read()
except (OSError, UnicodeDecodeError) as e:
    die(64, f"cannot read the plan {plan}: {e}")
rc, top = git(repo_dir, "rev-parse", "--show-toplevel")
if rc != 0 or not top.strip():
    die(64, f"{repo_dir} is not in a git repository")
top = os.path.realpath(top.strip())
if git(top, "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}")[0] != 0:
    die(64, f"{base} is not a commit")


def inside(full):
    """A real absolute path, relative to the repository's top ("" for the top); None outside it."""
    if full == top:
        return ""
    if full.startswith(top + os.sep):
        return os.path.relpath(full, top)
    return None


def plan_path(raw):
    """A **Files:** entry as a repository path, a trailing "/" kept; None when it names nothing here."""
    raw = LINES.sub("", raw.strip())
    folder = raw.endswith("/")
    path = inside(os.path.realpath(raw)) if os.path.isabs(raw) else os.path.normpath(raw)
    if not path or path in (".", "..") or path.startswith(".." + os.sep):
        return None
    return path + "/" if folder else path


files, folders = set(), []
for line in text.splitlines():
    if ENTRY.match(line):
        for raw in TICKED.findall(line):
            path = plan_path(raw)
            if path is None:
                continue
            if path.endswith("/"):
                folders.append(path)
            else:
                files.add(path)

skip_files, skip_folders = set(), [".superpowers/"]
where = inside(os.path.realpath(os.path.dirname(os.path.abspath(plan))))
if where == "":
    skip_files.add(os.path.basename(plan))
elif where is not None:
    skip_folders.append(where + "/")

changed = set()
for cmd in (("diff", "--no-renames", "--name-only", "-z", base),
            ("ls-files", "--others", "--exclude-standard", "-z")):
    rc, out = git(top, *cmd)
    if rc != 0:
        die(64, f"git {cmd[0]} failed in {top}")
    changed.update(p for p in out.split("\0") if p)

outside = sorted(p for p in changed
                 if p not in skip_files and not any(p.startswith(d) for d in skip_folders)
                 and p not in files and not any(p.startswith(d) for d in folders))
for p in outside:
    print(f"outside {p}")
if outside:
    sys.exit(1)
print("ok")
PY
