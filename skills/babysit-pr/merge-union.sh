#!/bin/sh
# Resolves the merge conflicts that are mechanical: in a conflicted file, both sides inserted text
# at the same point of the base and changed nothing else (two rows appended to one table, two
# entries added to one list) (#28). Run it in a worktree whose `git merge` stopped with conflicts.
#   merge-union.sh [--repo-dir <path>]
#   merge-union.sh --resolve [--path <repo path>] <base file> <ours file> <theirs file>
# Prints one line per unmerged path:
#   resolved <path>          exit 0, only when every unmerged path was mechanical: all written
#                            and staged, ready for `git commit`
#   conflict <path> <why>    exit 1: nothing was written or staged, so `git merge --abort` is clean
# A hunk resolves to the base before the insertion point, then theirs (stage 3: the branch being
# merged in, which is the base branch for babysit-pr and receive-review-and-execute), then ours
# (stage 2), then the base after the point; an insertion identical on both sides is kept once.
# An insertion that would join two word characters (\w), as 1 to 10 does, is not mechanical.
# Where two different insertions meet, the whole lines of one may not appear as a run inside the
# other, and theirs must end or ours start with whitespace or , ; |.
# Two in-line insertions where one contains the other's text (" && node x" and " && node x && node y")
# are edited on both sides: putting both in would repeat the shorter one (#85).
# package.json: a conflicted line of its "scripts" object whose value is a chain of commands joined
# by " && ", where each side kept the base's commands in order and only added commands, at any
# points, resolves to the ordered union of the chain: the base's commands in order, and before each
# one the commands theirs added there, then those ours added there; a command already in the chain
# is not added again (#85, #92). Every other line of such a hunk must be the same on all three sides.
# Insertions at different points of a file are separate hunks, each resolved as above, so a file
# where both sides only added lines resolves to the union of both, at every point (#92).
# Never mechanical: any other hunk shape (edited on both sides), a file with no base version
# (added on both sides), a delete or rename conflict, a mode change, a binary file, a lockfile,
# a file whose last line has no newline. Hunks are found with
# `git merge-file --diff3 --marker-size=31`, so a file's own 7-character marker-like lines are
# never mistaken for a hunk, and with `--diff-algorithm=histogram`, the one `git merge` uses.
# --resolve merges one file from three files with the same rules and needs no repository or merge
# in progress (carry-check.sh uses it): it prints the merged text exactly and exits 0, or prints
# "conflict <why>" and exits 1. The lockfile and package.json rules go by the name --path gives,
# else by the name of <ours file>.
# Exit: 0 all resolved; 1 something is not mechanical; 2 no merge with conflicts in progress;
# 64 usage (in --resolve, also a file that does not exist).
exec python3 - "$@" <<'PY'
import difflib
import json
import os
import re
import subprocess
import sys
import tempfile

MARK = 31
SEPARATORS = " \t\n,;|"
LOCKFILES = {"package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", "go.sum"}
AND = " && "
# one "key": "value" line of a JSON object, its two strings still escaped as written
PAIR = re.compile(r'^(\s*)"((?:[^"\\]|\\.)*)"(\s*:\s*)"((?:[^"\\]|\\.)*)"(\s*,?\s*)$')


def usage():
    print("usage: merge-union.sh [--repo-dir <path>]\n"
          "       merge-union.sh --resolve [--path <repo path>] <base file> <ours file> <theirs file>",
          file=sys.stderr)
    sys.exit(64)


def stop(msg):
    print(f"merge-union.sh: {msg}", file=sys.stderr)
    sys.exit(2)


argv = sys.argv[1:]
where = None
resolve = None  # (name, base file, ours file, theirs file) with --resolve
if argv[:1] == ["--resolve"]:
    rest, name = argv[1:], None
    if rest[:1] == ["--path"]:
        if len(rest) < 2:
            usage()
        name, rest = os.path.basename(rest[1]), rest[2:]
    if len(rest) != 3:
        usage()
    for f in rest:
        if not os.path.isfile(f):
            print(f"merge-union.sh: no such file: {f}", file=sys.stderr)
            sys.exit(64)
    resolve = (name or os.path.basename(rest[1]), *rest)
elif argv[:1] == ["--repo-dir"]:
    if len(argv) != 2:
        usage()
    where = argv[1]
elif argv:
    usage()
if where is not None and not os.path.isdir(where):
    stop(f"no such directory: {where}")


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd or where, capture_output=True)


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
    shorter, longer = sorted((t[1].splitlines(keepends=True), o[1].splitlines(keepends=True)), key=len)
    n = len(shorter)
    if n and any(longer[i:i + n] == shorter for i in range(len(longer) - n + 1)):
        return None
    inner, outer = sorted((t[1], o[1]), key=len)
    if "\n" not in outer and inner and inner in outer:
        return None
    if t[1] and o[1] and t[1][-1] not in SEPARATORS and o[1][0] not in SEPARATORS:
        return None
    return before + t[1] + o[1] + after


def chain_union(base, ours, theirs):
    """The ordered union of two command chains that only added commands to base; None otherwise."""
    def added(side):
        at = {}
        for tag, i1, _i2, j1, j2 in difflib.SequenceMatcher(None, base, side, autojunk=False).get_opcodes():
            if tag == "insert":
                at.setdefault(i1, []).extend(side[j1:j2])
            elif tag != "equal":
                return None
        return at
    o, t = added(ours), added(theirs)
    if o is None or t is None:
        return None
    out = []
    for i in range(len(base) + 1):
        for command in t.get(i, []) + o.get(i, []):
            if command not in out and command not in base:
                out.append(command)
        if i < len(base):
            out.append(base[i])
    return out


def unescape(raw):
    return json.loads(f'"{raw}"')


def resolve_chains(base, ours, theirs, scripts):
    """A hunk whose differing lines are all package.json script chains, resolved; else None."""
    lines = {k: v.splitlines(keepends=True) for k, v in (("base", base), ("ours", ours), ("theirs", theirs))}
    if not lines["base"] or len({len(v) for v in lines.values()}) != 1:
        return None
    out = []
    for b, o, t in zip(lines["base"], lines["ours"], lines["theirs"]):
        if b == o == t:
            out.append(b)
            continue
        found = [PAIR.match(x.rstrip("\n")) for x in (b, o, t)]
        if not all(found) or len({(m.group(1), m.group(2), m.group(3), m.group(5)) for m in found}) != 1:
            return None
        try:
            key, values = unescape(found[0].group(2)), [unescape(m.group(4)) for m in found]
        except ValueError:
            return None
        if any(value != scripts[label].get(key) for value, label in zip(values, ("base", "ours", "theirs"))):
            return None
        chain = chain_union(*(m.group(4).split(AND) for m in found))
        if chain is None:
            return None
        m = found[0]
        out.append(f'{m.group(1)}"{m.group(2)}"{m.group(3)}"{AND.join(chain)}"{m.group(5)}\n')
    return "".join(out)


def marker(line, ch):
    body = line.rstrip("\r\n")
    return body.startswith(ch * MARK) and (len(body) == MARK or body[MARK] == " ")


def merged(texts, scripts=None):
    """(the file with every hunk resolved, None), or (None, why). scripts: each side's package.json
    "scripts" object, when the file is a package.json whose three versions all have one."""
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
            hunk = ("".join(part["base"]), "".join(part["ours"]), "".join(part["theirs"]))
            done = resolve_hunk(*hunk)
            if done is None and scripts:
                done = resolve_chains(*hunk, scripts)
            if done is None:
                return None, "edited on both sides"
            out.append(done)
            state = "text"
        else:
            part["theirs"].append(line)
    if state != "text":
        return None, "unreadable merge"
    return "".join(out), None


def scripts_of(texts):
    """Each side's "scripts" object when all three sides are JSON objects that have one, else None."""
    found = {}
    for label, text in texts.items():
        try:
            doc = json.loads(text)
        except ValueError:
            return None
        if not isinstance(doc, dict) or not isinstance(doc.get("scripts"), dict):
            return None
        found[label] = doc["scripts"]
    return found


def resolve_texts(name, raw):
    """(the merged file, None), or (None, why), from the three versions' bytes."""
    if any(b"\0" in v for v in raw.values()):
        return None, "binary"
    try:
        texts = {k: v.decode("utf-8") for k, v in raw.items()}
    except UnicodeDecodeError:
        return None, "binary"
    if any(v and not v.endswith("\n") for v in texts.values()):
        return None, "no newline at the end of the file"
    return merged(texts, scripts_of(texts) if name == "package.json" else None)


def lockfile(name):
    return name in LOCKFILES or name.endswith(".lock")


def resolve_file(path, entry):
    """(the merged file, None), or (None, why) when the conflict in path is not mechanical."""
    name = os.path.basename(path)
    if lockfile(name):
        return None, "lockfile"
    if 1 not in entry:
        return None, "added on both sides"
    if 2 not in entry or 3 not in entry:
        return None, "deleted on one side"
    modes = {entry[k][0] for k in (1, 2, 3)}
    if len(modes) != 1 or modes.pop() not in ("100644", "100755"):
        return None, "mode or file type changed"
    blobs = {label: git("cat-file", "blob", entry[k][1], cwd=top)
             for label, k in (("base", 1), ("ours", 2), ("theirs", 3))}
    if any(b.returncode != 0 for b in blobs.values()):
        return None, "unreadable blob"
    return resolve_texts(name, {label: b.stdout for label, b in blobs.items()})


if resolve is not None:
    name, *files = resolve
    raw = {}
    for label, f in zip(("base", "ours", "theirs"), files):
        with open(f, "rb") as fh:
            raw[label] = fh.read()
    text, why = (None, "lockfile") if lockfile(name) else resolve_texts(name, raw)
    if text is None:
        print(f"conflict {why}")
        sys.exit(1)
    sys.stdout.write(text)
    sys.exit(0)

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
added = git("--literal-pathspecs", "add", "--", *results, cwd=top)
if added.returncode != 0:
    stop("git add failed: " + added.stderr.decode().strip()[:160])
for path in results:
    print(f"resolved {path}")
PY
