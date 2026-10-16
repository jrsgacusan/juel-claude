#!/bin/sh
# Lists the files a plan's executor changed that no task of the plan names (#78).
#   scope-check.sh <plan file> <base sha> [--before <file>] [--repo-dir <dir>]
#   scope-check.sh --print <plan file> [--repo-dir <dir>]
#   scope-check.sh --record <file> [--repo-dir <dir>]
# Prints, sorted, one line per changed file that no task's **Files:** block names, then exits 1:
#   outside <path>
#   outside-merged <path>    in its place when a merge commit in <base sha>..HEAD also changed it
# or, when every changed file is named, one line and exit 0:
#   ok
# or, when no line of the plan is a **Files:** entry at all, one line and exit 0, so the caller
# reverts nothing:
#   unchecked the plan names no files
# "Changed" is every path that differs between <base sha> and the working tree, committed or not,
# deletions included (git diff --no-renames --name-only <base>), plus untracked files git does not
# ignore. When a merge commit sits on HEAD's first-parent line since <base sha> (the base branch
# merged in mid-build), "changed" is only what the branch did itself (#106): the paths its own
# non-merge commits touched (git log --first-parent --no-merges --no-renames --name-only
# <base>..HEAD), every path that differs from HEAD, and the untracked files; a path only a merge
# changed is never listed.
# A **Files:** entry starts with Create:, Modify:, Test: or Delete: (after an optional list marker),
# with an optional parenthetical. Its paths are the backticked ones; a prose label opens an indented
# block, whose list items may name a bare first token and whose other lines name only backticked
# paths. The block closes at the first non-blank line no deeper than its label. Ranges use through
# or to, a short or full second end, keep zero padding and allow reversed ends; ranges over 1000
# members name only their ends. A label counts only when it names a path. A ":<lines>" suffix is
# dropped, and so is a "::<anything>" suffix (a pytest node id such as tests/test_b.py::test_foo).
# A path ending in "/" names everything under it. Never outside: paths under .superpowers/ (the
# executor's ledger), and the plan's own folder when the plan sits in the repository (only the plan
# file itself when that folder is the repository's top). Only files are checked, never line ranges:
# ranges drift as earlier tasks edit a file, and the review reads the hunks.
# --record writes to <file> every path that differs from HEAD right now (git diff --no-renames
# --name-only -z HEAD, plus the untracked files git does not ignore), NUL-separated, prints
# "recorded <n>" and exits 0. The caller records right before it dispatches the executor.
# --before <file> (the file --record wrote) excuses every path in it: it already differed before
# the executor ran, so it is the user's or the skill's own work, and the caller must not restore
# or delete it. A --before file that cannot be read is exit 64.
# The caller restores each outside file from <base sha>, or deletes it when it is new, and says so.
# It never restores an outside-merged file: restoring it from <base sha> would drop the base's change.
# Paths are relative to the repository's top level, whatever --repo-dir (default: here) points at.
# --print lists the parsed scope as sorted "scope <path>" lines and needs no base sha or --before;
# a plan that names nothing prints nothing and exits 0. A base sha or --before with --print is 64.
# Exit: 0 ok, unchecked, printed or recorded; 1 outside or outside-merged lines; 64 bad usage, a plan or
# --before file that cannot be read, a --record file that cannot be written, a <base sha> that is
# not a commit, or a --repo-dir that is not in a git repository.
exec python3 - "$@" <<'PY'
import os
import re
import subprocess
import sys

LABEL = re.compile(r"^(\s*)(?:[-*+]\s+|\d+[.)]\s+)?(?:Create|Modify|Test|Delete)(?:\s*\((?:[^()\n]|\([^()\n]*\))*\))?:(.*)$")
RANGE = re.compile(r"`?([^`\s]+?)-(\d+)((?:\.[A-Za-z0-9]+)*)`?\s+(?:through|to)\s+`?(?:(?:\1)?)-(\d+)((?:\.[A-Za-z0-9]+)*)`?")
TICKED = re.compile(r"`([^`\n]+)`")
LINES = re.compile(r":\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$")


def die(code, msg):
    print(f"scope-check.sh: {msg}", file=sys.stderr)
    sys.exit(code)


argv, repo_dir, args, record, before_file, print_plan = sys.argv[1:], ".", [], None, None, None
while argv:
    arg = argv.pop(0)
    if arg in ("--repo-dir", "--record", "--before", "--print"):
        if not argv:
            die(64, f"{arg} needs a value")
        value = argv.pop(0)
        if arg == "--repo-dir":
            repo_dir = value
        elif arg == "--record":
            record = value
        elif arg == "--before":
            before_file = value
        else:
            print_plan = value
    elif arg.startswith("-"):
        die(64, f"unknown argument: {arg}")
    else:
        args.append(arg)
if record is not None:
    if args or before_file is not None or print_plan is not None:
        die(64, "--record takes no plan, base sha, --before or --print")
elif print_plan is not None:
    if args or before_file is not None:
        die(64, "--print takes a plan and --repo-dir only")
    plan, base = print_plan, None
elif len(args) != 2:
    die(64, "usage: scope-check.sh <plan file> <base sha> [--before <file>] [--repo-dir <dir>]"
            " | scope-check.sh --print <plan file> [--repo-dir <dir>]"
            " | scope-check.sh --record <file> [--repo-dir <dir>]")
else:
    plan, base = args


def git(cwd, *cmd):
    try:
        proc = subprocess.run(["git", "-C", cwd, *cmd], capture_output=True, text=True)
    except OSError as e:
        die(64, f"cannot run git: {e.strerror}")
    return proc.returncode, proc.stdout


if record is None:
    try:
        with open(plan, encoding="utf-8") as f:
            text = f.read()
    except (OSError, UnicodeDecodeError) as e:
        die(64, f"cannot read the plan {plan}: {e}")
    before = set()
    if before_file is not None:
        try:
            with open(before_file, encoding="utf-8") as f:
                before = {p for p in f.read().split("\0") if p}
        except (OSError, UnicodeDecodeError) as e:
            die(64, f"cannot read the --before file {before_file}: {e}")
rc, top = git(repo_dir, "rev-parse", "--show-toplevel")
if rc != 0 or not top.strip():
    die(64, f"{repo_dir} is not in a git repository")
top = os.path.realpath(top.strip())
if record is None and base is not None and git(top, "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}")[0] != 0:
    die(64, f"{base} is not a commit")


def listed(*cmd):
    """The NUL-separated paths one git command prints."""
    rc, out = git(top, *cmd)
    if rc != 0:
        die(64, f"git {cmd[0]} failed in {top}")
    return {p for p in out.split("\0") if p}


def changed_since(rev):
    """Every path that differs from <rev> in the working tree, plus the untracked files git does not ignore."""
    return (listed("diff", "--no-renames", "--name-only", "-z", rev)
            | listed("ls-files", "--others", "--exclude-standard", "-z"))


if record is not None:
    paths = changed_since("HEAD")
    try:
        with open(record, "w", encoding="utf-8") as f:
            f.write("".join(p + "\0" for p in sorted(paths)))
    except OSError as e:
        die(64, f"cannot write {record}: {e.strerror}")
    print(f"recorded {len(paths)}")
    sys.exit(0)


def inside(full):
    """A real absolute path, relative to the repository's top ("" for the top); None outside it."""
    if full == top:
        return ""
    if full.startswith(top + os.sep):
        return os.path.relpath(full, top)
    return None


def plan_path(raw):
    """A **Files:** entry as a repository path, a trailing "/" kept; None when it names nothing here."""
    raw = LINES.sub("", raw.split("::", 1)[0].strip())
    folder = raw.endswith("/")
    path = inside(os.path.realpath(raw)) if os.path.isabs(raw) else os.path.normpath(raw)
    if not path or path in (".", "..") or path.startswith(".." + os.sep):
        return None
    return path + "/" if folder else path


def names(raw, bare=False):
    """Paths from a label's remainder, including ranges and optionally a bare first token."""
    found = []
    remainder = raw
    ranges = list(RANGE.finditer(raw))
    for match in reversed(ranges):
        stem, first, ext1, last, ext2 = match.groups()
        a, b = int(first), int(last)
        width = max(len(first), len(last)) if first.startswith("0") or last.startswith("0") else 1
        ext = ext2 or ext1
        start, end = min(a, b), max(a, b)
        if end - start + 1 > 1000:
            found.extend((f"{stem}-{a:0{width}d}{ext}", f"{stem}-{b:0{width}d}{ext}"))
        else:
            found.extend(f"{stem}-{n:0{width}d}{ext}" for n in range(start, end + 1))
        remainder = remainder[:match.start()] + " " + remainder[match.end():]
    found.extend(TICKED.findall(remainder))
    if not found and bare:
        token = remainder.split()[:1]
        found.extend(token)
    return found


def add_paths(raws):
    for raw in raws:
        path = plan_path(raw)
        if path is None:
            continue
        if path.endswith("/"):
            folders.append(path)
        else:
            files.add(path)


files, folders, entries = set(), [], 0
lines = text.splitlines()
i = 0
while i < len(lines):
    line = lines[i]
    label = LABEL.match(line)
    if not label:
        i += 1
        continue
    indent, rest = label.groups()
    parsed = names(rest)
    if parsed:
        add_paths(parsed)
        entries += 1
        i += 1
        continue
    # A prose label opens an indented Files block. A line at its indent closes it.
    base_indent = len(indent.expandtabs(8))
    block = []
    j = i + 1
    while j < len(lines):
        nested = lines[j]
        if not nested.strip():
            j += 1
            continue
        nested_indent = len(nested[:len(nested) - len(nested.lstrip(" \t"))].expandtabs(8))
        if nested_indent <= base_indent or LABEL.match(nested):
            break
        body = nested.lstrip(" \t")
        is_item = bool(re.match(r"^(?:[-*+]\s+|\d+[.)]\s+)", body))
        body = re.sub(r"^(?:[-*+]\s+|\d+[.)]\s+)", "", body)
        block.extend(names(body, bare=is_item))
        j += 1
    if block:
        add_paths(block)
        entries += 1
    else:
        own = names(rest, bare=True)
        if own:
            add_paths(own)
            entries += 1
    i = j


if print_plan is not None:
    for path in sorted(files | set(folders)):
        print(f"scope {path}")
    sys.exit(0)

if not entries:
    print("unchecked the plan names no files")
    sys.exit(0)

skip_files, skip_folders = set(before), [".superpowers/"]
where = inside(os.path.realpath(os.path.dirname(os.path.abspath(plan))))
if where == "":
    skip_files.add(os.path.basename(plan))
elif where is not None:
    skip_folders.append(where + "/")

rc, out = git(top, "rev-list", "--first-parent", "--merges", f"{base}..HEAD")
if rc != 0:
    die(64, f"git rev-list failed in {top}")
merges = out.split()
if merges:
    # the base was merged in since <base>: count only what the branch did itself (#106)
    changed = changed_since("HEAD") | listed("log", "--first-parent", "--no-merges", "--no-renames",
                                             "--format=", "--name-only", "-z", f"{base}..HEAD")
else:
    changed = changed_since(base)
merged = set()
for m in merges:  # what each merge brought in: its changes against its first parent
    merged |= listed("diff", "--no-renames", "--name-only", "-z", f"{m}^1", m)
outside = sorted(p for p in changed
                 if p not in skip_files and not any(p.startswith(d) for d in skip_folders)
                 and p not in files and not any(p.startswith(d) for d in folders))
for p in outside:
    print(f"outside-merged {p}" if p in merged else f"outside {p}")
if outside:
    sys.exit(1)
print("ok")
PY
