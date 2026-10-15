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
# A chain theirs also reordered resolves when no side holds a command twice, neither side dropped a
# base command, and ours kept the base's commands in order and only added (commands are compared
# with outer spaces trimmed): theirs' chain, with each command only ours added right after the base
# command before it in ours, or, with none before it, right before the earliest command of theirs'
# chain that comes after it in ours (#103).
# Insertions at different points of a file are separate hunks, each resolved as above, so a file
# where both sides only added lines resolves to the union of both, at every point (#92).
# A hunk of one line on each side, each line <prefix>{ <names> }<suffix> with the same prefix and
# suffix (module.exports = { a, b };), where <names> is a comma-separated list of [A-Za-z_$][\w$]*
# with an optional trailing comma, resolves when no side repeats a name and each side kept the
# base's names in order and only added: the base's names in order with each side's added names at
# the point it added them, theirs before ours at one point, a name both sides added once, with
# theirs' spacing inside the braces and theirs' trailing comma (#103). The names are joined by the
# separator all three sides use between their names: "," or ", ". A list of one name has no
# separator and agrees with either; ", " when every side has one name. Sides that differ, or any
# other spacing (two spaces, a tab, a space before the comma), stay a conflict, since a brace glob
# or a shell brace expansion ({a,b}) changes meaning with a space (#103).
# An edit next to an insertion (#120): one side inserted a block of whole lines at a point of the
# hunk's base and changed nothing else, and the other side rewrote, line for line, only base lines
# before that point, the last of them the one directly before it. The hunk resolves to the edited
# lines, then the inserted block, then the base after the point. It stays a conflict when the
# block's last line is the base line before the point (the inserted lines then also read as an
# insertion before the edited line), and when the block repeats an edited line. Lines are split at
# newlines only, as git splits them.
# Never mechanical: any other hunk shape (edited on both sides: both sides editing the same line, an
# edit that does not end right before the other side's insertion or that runs past it, an insertion
# before the edited line, an edit that adds or drops lines), a file with no base version (added on
# both sides), a delete or rename conflict, a mode change, a binary file, a lockfile, a file whose
# last line has no newline.
# Hunks are found with
# `git merge-file --diff3 --marker-size=31`, so a file's own 7-character marker-like lines are
# never mistaken for a hunk, and with `--diff-algorithm=histogram`, the one `git merge` uses.
# --resolve merges one file from three files with the same rules and needs no repository or merge
# in progress: it prints the merged text exactly and exits 0, or prints
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
NAME = r"[A-Za-z_$][\w$]*"
# one line holding a list of names in braces, as module.exports = { a, b }; does
NAMES = re.compile(r"^(.*?)\{(\s*)(" + NAME + r"(?:\s*,\s*" + NAME + r")*)(\s*,)?(\s*)\}(.*)$")


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


def chain_reorder(base, ours, theirs):
    """Theirs' chain, which reordered the base's commands, with the commands only ours added put in;
    None unless no side repeats a command, both sides kept every base command and ours only added."""
    b, o, t = ([command.strip() for command in side] for side in (base, ours, theirs))
    if any(len(set(side)) != len(side) for side in (b, o, t)):
        return None
    if not set(b) <= set(t) or [command for command in o if command in b] != b:
        return None
    before, after, anchor = {}, {}, None
    for i, command in enumerate(o):
        if command in b:
            anchor = command
        elif command in t:
            continue  # both sides added it: it stays where theirs put it
        elif anchor is not None:
            after.setdefault(anchor, []).append(command)
        else:  # no base command before it in ours
            first = min(t.index(c) for c in o[i + 1:] if c in t)
            before.setdefault(t[first], []).append(command)
    out = []
    for command in t:
        out += before.get(command, []) + [command] + after.get(command, [])
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
        chains = [m.group(4).split(AND) for m in found]
        chain = chain_union(*chains)
        if chain is None:
            chain = chain_reorder(*chains)
        if chain is None:
            return None
        m = found[0]
        out.append(f'{m.group(1)}"{m.group(2)}"{m.group(3)}"{AND.join(chain)}"{m.group(5)}\n')
    return "".join(out)


def resolve_names(base, ours, theirs):
    """A hunk of one line on each side, a { a, b } list both sides only added names to, resolved;
    else None."""
    if any(text.count("\n") != 1 for text in (base, ours, theirs)):
        return None
    found = [NAMES.match(text.rstrip("\n")) for text in (base, ours, theirs)]
    if not all(found) or len({(m.group(1), m.group(6)) for m in found}) != 1:
        return None
    b, o, t = ([name.strip() for name in m.group(3).split(",")] for m in found)
    if any(len(set(side)) != len(side) for side in (b, o, t)):
        return None
    if any([name for name in side if name in b] != b for side in (o, t)):
        return None
    # both sides only added: chain_union puts each side's names where it added them, theirs first
    names = chain_union(b, o, t)
    if names is None:
        return None
    # the separator is one of "," and ", ", the same on all three sides (a lone name has none)
    seps = {sep for m in found for sep in re.findall(r"\s*,\s*", m.group(3))}
    if len(seps) > 1 or not seps <= {",", ", "}:
        return None
    m = found[2]
    inside = m.group(2) + (seps.pop() if seps else ", ").join(names) + (m.group(4) or "") + m.group(5)
    return m.group(1) + "{" + inside + "}" + m.group(6) + "\n"


def hunk_lines(text):
    """text split into lines at newlines only, as git counts lines: a carriage return, a form feed or
    a U+2028 inside a line stays inside it."""
    return re.findall(r"[^\n]*\n|[^\n]+\Z", text)


def resolve_adjacent(base, ours, theirs):
    """#120: one side inserted a block of whole lines at a point and changed nothing else, and the
    other side changed, line for line, only base lines before that point, the last of them the one
    directly before it: the edited lines, then the block, then the base after the point. None for any
    other shape; when the block's last line is the base line before the point (the inserted lines
    then also read as an insertion before the edited line); and when the block repeats an edited
    line (the union would hold it twice)."""
    b = hunk_lines(base)
    for edit, added in ((ours, theirs), (theirs, ours)):
        e, found = hunk_lines(edit), insertion(b, hunk_lines(added))
        if found is None or not found[1] or found[0] < 1 or len(e) != len(b):
            continue
        point, block = found
        edited = [e[i] for i in range(point) if e[i] != b[i]]
        if e[point - 1] != b[point - 1] and e[point:] == b[point:] and block[-1] != b[point - 1] \
                and not any(line in block for line in edited):
            return "".join(e[:point] + block + b[point:])
    return None


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
                done = resolve_names(*hunk)
            if done is None:
                done = resolve_adjacent(*hunk)
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
