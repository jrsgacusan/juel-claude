#!/bin/sh
# Removes the Orca worktree of a finished STAR row when nothing in it would be lost.
#   worktree-clean.sh [--home H] <item>
#     -> removed <path> | kept <path>: <why> | none
#        with "kept-evidence <H>/evidence/<item>/" on its own line first when evidence was copied
# It removes the worktree only when all of these hold: the row is done or dropped; the path is not
# the project's main checkout and no other open row names it; `git status --porcelain` is empty;
# and the work is safe elsewhere: after a fetch from the project's remote, HEAD is contained in a
# remote branch, or, for a done row, HEAD is still the head the ledger recorded (the one that
# merged, also after a squash merge deleted the remote branch).
# Then `orca worktree rm --worktree path:<path> --json`, never with --force (Orca keeps any branch
# it cannot prove merged), the row's worktree cell becomes -, and sent.log gets
# "<iso>\tSTAR\t<item>\tremoved worktree <path>".
# A folder that is already gone: `git worktree prune`, the cell becomes -, and it prints none,
# as for a row with no worktree.
# Evidence outlives the worktree (#73): before the removal, every <docsRoot>/evidence/ folder the
# worktree holds is copied into <H>/evidence/<item>/ (merged into what an earlier attempt left), and
# every file is checked to have arrived at its size. The docsRoots looked at are the one STAR's home
# sits in (<main checkout>/<docsRoot>/context/star) and the plugin's defaults, docs/superpowers and
# docs/.superpowers, since a build resolves docsRoot inside its own worktree. Evidence is
# git-ignored, so git status never counts it: without this copy it would be removed with the folder.
# <why>: row is <state> | the main checkout | in use by <item> | not a git checkout |
#        uncommitted changes | unpushed commits | evidence copy failed: <why> | orca: <message>
# Test seam: ORCA_CLI_COMMAND.
# Exit: 0 with one of the lines above; 2 the STAR folder or star.json cannot be read; 4 no row for
# the item; 64 usage.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
export STAR_HOME_DEFAULT STAR_SKILL_DIR
exec python3 - "$@" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

S = os.environ["STAR_SKILL_DIR"]
orca = os.environ.get("ORCA_CLI_COMMAND") or "orca"
FINISHED = ("done", "dropped")


def die(code, msg):
    print(f"worktree-clean.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def out(line):
    print(line)
    sys.exit(0)


def run(cmd, timeout=120):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout or "", p.stderr or ""
    except subprocess.TimeoutExpired:
        return 124, "", f"{cmd[0]} ran past {timeout} s"
    except OSError as e:
        return 127, "", f"cannot run {cmd[0]}: {e.strerror}"


args, home = sys.argv[1:], os.environ.get("STAR_HOME_DEFAULT") or ""
if args[:1] == ["--home"]:
    if len(args) < 2:
        die(64, "--home needs a folder")
    home, args = args[1], args[2:]
if len(args) != 1 or args[0].startswith("-"):
    die(64, "usage: worktree-clean.sh [--home H] <item>")
item = args[0]
if not home:
    die(2, "no STAR folder: pass --home, or run inside a project")
try:
    project = json.load(open(os.path.join(home, "star.json"), encoding="utf-8")).get("project") or {}
except (OSError, ValueError, AttributeError) as e:
    die(2, f"cannot read star.json ({e})")
repo, remote = project.get("repo"), project.get("remote") or "origin"
if not repo:
    die(2, "star.json has no project: run star-home.sh init")


def ledger(*a):
    rc, stdout, stderr = run(["sh", os.path.join(S, "ledger.sh"), "--home", home, *a], 30)
    if rc == 4:
        die(4, f"no ledger row for {item}")
    if rc != 0:
        die(2, "ledger.sh: " + (stderr.strip() or f"exit {rc}"))
    return stdout


def git(where, *a):
    return run(["git", "-C", where, *a])


def git_out(where, *a):
    """git's stdout, stripped; empty when the command failed."""
    rc, stdout, _ = git(where, *a)
    return stdout.strip() if rc == 0 else ""


def evidence_dirs(worktree):
    """Each <docsRoot>/evidence/ folder the worktree holds: under the docsRoot STAR's home sits in,
    and under the plugin's two default docsRoots."""
    roots = ["docs/superpowers", "docs/.superpowers"]
    real_home, main = os.path.realpath(home), os.path.realpath(repo)
    docs = os.path.dirname(os.path.dirname(real_home))
    if (os.path.basename(real_home) == "star" and os.path.basename(os.path.dirname(real_home)) == "context"
            and (docs == main or docs.startswith(main + os.sep))):
        roots.insert(0, os.path.relpath(docs, main))
    found, seen = [], set()
    for rel in roots:
        folder = os.path.join(worktree, rel, "evidence")
        if os.path.isdir(folder) and os.path.realpath(folder) not in seen:
            seen.add(os.path.realpath(folder))
            found.append(folder)
    return found


def keep_evidence(worktree):
    """(<H>/evidence/<item>/, None) after a full copy; (None, None) when there is nothing to keep;
    (None, why) when the copy failed or left a file out."""
    sources = evidence_dirs(worktree)
    if not sources:
        return None, None
    if re.search(r"[\x00-\x1f\x7f/\\]", item) or item.startswith("."):
        return None, f"{item} is not a plain folder name"
    dest = os.path.join(home, "evidence", item)
    missing = total = 0
    try:
        for src in sources:
            shutil.copytree(src, dest, symlinks=True, dirs_exist_ok=True)
        for src in sources:
            for top, dirs, files in os.walk(src):
                for name in files + [d for d in dirs if os.path.islink(os.path.join(top, d))]:
                    total += 1
                    orig = os.path.join(top, name)
                    copy = os.path.join(dest, os.path.relpath(orig, src))
                    plain = os.path.isfile(orig) and not os.path.islink(orig)
                    if not os.path.lexists(copy) or (plain and os.path.getsize(copy) != os.path.getsize(orig)):
                        missing += 1
    except OSError as e:
        return None, str(getattr(e, "strerror", None) or e)[:120]
    if missing:
        return None, f"{missing} of {total} files missing after the copy"
    return dest + "/", None


row = dict(l.split("=", 1) for l in ledger("get", item).splitlines() if "=" in l)
path, state = row["worktree"], row["state"]
if path in ("", "-"):
    out("none")
if state not in FINISHED:
    out(f"kept {path}: row is {state}")
if os.path.realpath(path) == os.path.realpath(repo):
    out(f"kept {path}: the main checkout")
for line in ledger("list").splitlines():
    cells = line.split("\t")
    if (len(cells) >= 5 and cells[0] != item and cells[1] not in FINISHED
            and cells[4] not in ("", "-") and os.path.realpath(cells[4]) == os.path.realpath(path)):
        out(f"kept {path}: in use by {cells[0]}")
if not os.path.isdir(path):
    git(repo, "worktree", "prune")
    ledger("set", item, "worktree=-")
    out("none")
if git_out(path, "rev-parse", "--is-inside-work-tree") != "true":
    out(f"kept {path}: not a git checkout")
if git_out(path, "status", "--porcelain"):
    out(f"kept {path}: uncommitted changes")
git(path, "fetch", "--quiet", remote)  # offline: stale refs can only make it keep more
head = git_out(path, "rev-parse", "HEAD").lower()
recorded = row["head"].strip().lower()
on_remote = bool(git_out(path, "branch", "-r", "--contains", "HEAD"))
merged_head = state == "done" and len(recorded) >= 7 and head.startswith(recorded)
if not (on_remote or merged_head):
    out(f"kept {path}: unpushed commits")
kept_at, why = keep_evidence(path)
if why:
    out(f"kept {path}: evidence copy failed: {why}")
if kept_at:
    print(f"kept-evidence {kept_at}")
rc, stdout, stderr = run([orca, "worktree", "rm", "--worktree", f"path:{path}", "--json"])
try:
    data = json.loads(stdout, strict=False)
except ValueError:
    data = None
if rc != 0 or (isinstance(data, dict) and data.get("ok") is False):
    error = data.get("error") if isinstance(data, dict) else None
    message = error.get("message") if isinstance(error, dict) else error
    lines = (stderr.strip() or stdout.strip()).splitlines()
    out(f"kept {path}: orca: " + str(message or (lines[0] if lines else f"exit {rc}"))[:120])
ledger("set", item, "worktree=-")
with open(os.path.join(home, "sent.log"), "a", encoding="utf-8") as f:
    f.write(f"{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\tSTAR\t{item}\tremoved worktree {path}\n")
out(f"removed {path}")
PY
