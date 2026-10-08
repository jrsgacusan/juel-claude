#!/bin/sh
# Resolves the merge conflicts that are mechanical: in a conflicted file, both sides inserted text
# at the same point of the base and changed nothing else (two rows appended to one table, two
# entries added to one list) (#28). Run it in a worktree whose `git merge` stopped with conflicts.
#   merge-union.sh [--repo-dir <path>]
# Prints one line per unmerged path:
#   resolved <path>          exit 0, only when every unmerged path was mechanical: all written
#                            and staged, ready for `git commit`
#   conflict <path> <why>    exit 1: nothing was written or staged, so `git merge --abort` is clean
# A hunk resolves to the base before the insertion point, then theirs (stage 3: the branch being
# merged in, which is the base branch for babysit-pr and receive-review-and-execute), then ours
# (stage 2), then the base after the point; an insertion identical on both sides is kept once.
# An insertion that would join two word characters (\w), as 1 to 10 does, is not mechanical.
# Where two different insertions meet, theirs must end or ours start with whitespace or , ; |.
# Never mechanical: any other hunk shape (edited on both sides), a file with no base version
# (added on both sides), a delete or rename conflict, a mode change, a binary file, a lockfile,
# a file whose last line has no newline. Hunks are found with
# `git merge-file --diff3 --marker-size=31`, so a file's own 7-character marker-like lines are
# never mistaken for a hunk, and with `--diff-algorithm=histogram`, the one `git merge` uses.
# Exit: 0 all resolved; 1 something is not mechanical; 2 no merge with conflicts in progress;
# 64 usage.
exec python3 - "$@" <<'PY'
import os
import re
import subprocess
import sys
import tempfile

MARK = 31
SEPARATORS = " \t\n,;|"
LOCKFILES = {"package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", "go.sum"}


def usage():
    print("usage: merge-union.sh [--repo-dir <path>]", file=sys.stderr)
    sys.exit(64)


def stop(msg):
    print(f"merge-union.sh: {msg}", file=sys.stderr)
    sys.exit(2)


argv = sys.argv[1:]
where = None
if argv[:1] == ["--repo-dir"]:
    if len(argv) != 2:
        usage()
    where = argv[1]
elif argv:
    usage()
if where is not None and not os.path.isdir(where):
    stop(f"no such directory: {where}")


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd or where, capture_output=True)


top = git("rev-parse", "--show-toplevel")
if top.returncode != 0:
    stop("not inside a git repository")
top = top.stdout.decode().strip()
if git("rev-parse", "-q", "--verify", "MERGE_HEAD", cwd=top).returncode != 0:
    stop("no merge in progress")

stages = {}
for rec in git("ls-files", "-u", "-z", cwd=top).stdout.split(b"\0"):
    if not rec:
        continue
    meta, _, path = rec.partition(b"\t")
    mode, sha, stage = meta.decode().split()
    stages.setdefault(path.decode("utf-8", "surrogateescape"), {})[int(stage)] = (mode, sha)
if not stages:
    stop("the merge has no conflicts left")


def insertion(base, side):
    """(point, text) when side is base with one piece of text inserted at point; else None."""
    if len(side) < len(base):
        return None
    p = 0
    while p < len(base) and base[p] == side[p]:
        p += 1
    s = 0
    while s < len(base) - p and base[len(base) - 1 - s] == side[len(side) - 1 - s]:
        s += 1
    if p + s != len(base):
        return None
    return p, side[p:len(side) - s]


def joins(left, right):
    """True when left ends and right starts with a word character: put together, they splice a word."""
    return bool(left and right and re.match(r"\w", left[-1]) and re.match(r"\w", right[0]))


def resolve_hunk(base, ours, theirs):
    o, t = insertion(base, ours), insertion(base, theirs)
    if o is None or t is None or o[0] != t[0]:
        return None
    before, after = base[:o[0]], base[o[0]:]
    if any(joins(before, text) or joins(text, after) for text in (o[1], t[1])):
        return None
    if t[1] == o[1]:
        return before + t[1] + after
    if t[1] and o[1] and t[1][-1] not in SEPARATORS and o[1][0] not in SEPARATORS:
        return None
    return before + t[1] + o[1] + after


def marker(line, ch):
    body = line.rstrip("\r\n")
    return body.startswith(ch * MARK) and (len(body) == MARK or body[MARK] == " ")


def merged(texts):
    """(the file with every hunk resolved, None), or (None, why)."""
    with tempfile.TemporaryDirectory() as tmp:
        names = []
        for label in ("ours", "base", "theirs"):
            name = os.path.join(tmp, label)
            with open(name, "w", encoding="utf-8", newline="") as f:
                f.write(texts[label])
            names.append(name)
        proc = subprocess.run(["git", "merge-file", "-p", "--diff3", f"--marker-size={MARK}",
                               "--diff-algorithm=histogram", *names], capture_output=True)
    if proc.returncode > 127:
        return None, "git merge-file failed"
    out, state, part = [], "text", None
    for line in proc.stdout.decode("utf-8").splitlines(keepends=True):
        if state == "text":
            if marker(line, "<"):
                state, part = "ours", {"ours": [], "base": [], "theirs": []}
            else:
                out.append(line)
        elif state == "ours":
            if marker(line, "|"):
                state = "base"
            elif marker(line, "="):
                return None, "unreadable merge"
            else:
                part["ours"].append(line)
        elif state == "base":
            if marker(line, "="):
                state = "theirs"
            else:
                part["base"].append(line)
        elif marker(line, ">"):
            done = resolve_hunk("".join(part["base"]), "".join(part["ours"]), "".join(part["theirs"]))
            if done is None:
                return None, "edited on both sides"
            out.append(done)
            state = "text"
        else:
            part["theirs"].append(line)
    if state != "text":
        return None, "unreadable merge"
    return "".join(out), None


def resolve_file(path, entry):
    """(the merged file, None), or (None, why) when the conflict in path is not mechanical."""
    name = os.path.basename(path)
    if name in LOCKFILES or name.endswith(".lock"):
        return None, "lockfile"
    if 1 not in entry:
        return None, "added on both sides"
    if 2 not in entry or 3 not in entry:
        return None, "deleted on one side"
    modes = {entry[k][0] for k in (1, 2, 3)}
    if len(modes) != 1 or modes.pop() not in ("100644", "100755"):
        return None, "mode or file type changed"
    raw = {label: git("cat-file", "blob", entry[k][1], cwd=top).stdout
           for label, k in (("base", 1), ("ours", 2), ("theirs", 3))}
    if any(b"\0" in v for v in raw.values()):
        return None, "binary"
    try:
        texts = {k: v.decode("utf-8") for k, v in raw.items()}
    except UnicodeDecodeError:
        return None, "binary"
    if any(v and not v.endswith("\n") for v in texts.values()):
        return None, "no newline at the end of the file"
    return merged(texts)


results, problems = {}, []
for path in sorted(stages):
    text, why = resolve_file(path, stages[path])
    if text is None:
        problems.append((path, why))
    else:
        results[path] = text

if problems:
    for path, why in problems:
        print(f"conflict {path} {why}")
    sys.exit(1)
for path, text in results.items():
    with open(os.path.join(top, path), "w", encoding="utf-8", newline="") as f:
        f.write(text)
added = git("add", "--", *results, cwd=top)
if added.returncode != 0:
    stop("git add failed: " + added.stderr.decode().strip()[:160])
for path in results:
    print(f"resolved {path}")
PY
