#!/bin/sh
# Proves that a head is the gated head plus merges that added no change of their own, so the gated
# head's SAFE verdict carries to it and no codex round is spent on a merge of the base (#75).
#   carry-check.sh --from <G> --head <M> [--base <ref>] [--repo-dir <dir>]
# Prints one line:
#   OK carried from <G full sha>: merge of <ref> with no conflicts                          exit 0
#   OK carried from <G full sha>: merge of <ref>, mechanical conflicts resolved in <a>, <b>  exit 0
#   NO <why>                                                                                 exit 1
# Exit 64 on bad usage: a missing or unknown flag, or a commit git does not know.
# <G> must be on <M>'s first-parent line, and every commit on that line after <G> must be a merge
# of two parents, P1 (the line from <G>) and P2. For each, "git merge-tree --write-tree P1 P2" is
# the merge git makes by itself, and the merge commit must be exactly that: a file where it differs
# from that merge is a hand edit, unless the file is one of the merge's conflicts; and every
# conflicted file must hold what merge-union.sh --resolve makes of its three stages, or, for a path
# whose merge attribute is union in the merge commit's tree, what git merge-file --union makes.
# The file mode counts too: the three stages must have one mode, and the merge commit's mode for
# the path (git ls-tree) must be that mode, so a resolved conflict plus "chmod +x" is NO.
# A commit of its own, a conflict left in or settled another way, or a side that deleted or
# renamed a conflicted file is NO. merge-tree reads attributes from the working tree, so the union
# check covers a merge made where the attribute was in force. With --base, every P2 must be on
# <ref> (git merge-base --is-ancestor), so only the base branch is ever carried in.
# <ref> is the newest merge's P2 named by "git name-rev --refs=refs/remotes/*" (not the
# refs/remotes/<remote>/HEAD alias, which a clone adds) without "remotes/" or a ~n/^n suffix
# ("origin/main"), else its 7-character sha. merge-union.sh is
# $CARRY_MERGE_UNION when set (the test seam), else ../babysit-pr/merge-union.sh.
CARRY_DIR=$(cd "$(dirname "$0")" && pwd)
export CARRY_DIR
exec python3 - "$@" <<'PY'
import os
import re
import subprocess
import sys
import tempfile


def die(msg):
    print(f"carry-check.sh: {msg}", file=sys.stderr)
    sys.exit(64)


def no(why):
    print(f"NO {why}")
    sys.exit(1)


o, args = {}, sys.argv[1:]
while args:
    arg = args.pop(0)
    if arg not in ("--from", "--head", "--base", "--repo-dir") or not args or not args[0].strip():
        die(f"unknown or empty argument: {arg}")
    o[arg[2:]] = args.pop(0).strip()
if "from" not in o or "head" not in o:
    die("usage: carry-check.sh --from <G> --head <M> [--base <ref>] [--repo-dir <dir>]")
REPO = o.get("repo-dir") or os.getcwd()
UNION = os.environ.get("CARRY_MERGE_UNION") or os.path.join(
    os.path.dirname(os.environ["CARRY_DIR"]), "babysit-pr", "merge-union.sh")


def git(*cmd, raw=False):
    r = subprocess.run(["git", "-C", REPO] + list(cmd), capture_output=True, stdin=subprocess.DEVNULL)
    text = r.stdout if raw else r.stdout.decode("utf-8", "surrogateescape")
    return r.returncode, text, r.stderr.decode("utf-8", "replace")


def commit(rev, flag):
    rc, sha, _ = git("rev-parse", "--verify", "--quiet", rev + "^{commit}")
    if rc != 0 or not sha.strip():
        die(f"--{flag}: git knows no commit {rev}")
    return sha.strip()


def blob(rev):
    rc, data, _ = git("cat-file", "blob", rev, raw=True)
    return data if rc == 0 else None


def mode_in(rev, path):
    """The file mode <rev> has for <path> (git ls-tree), or "-" when it has none."""
    rc, out, _ = git("--literal-pathspecs", "ls-tree", "-z", "--full-tree", rev, "--", path)
    return out.split(" ", 1)[0] if rc == 0 and out else "-"


def mechanical(merge, path, stages, have):
    """True when the merge commit's file is what merge-union.sh --resolve makes of the conflict's
    three stages, or, for a merge=union path, what git merge-file --union makes."""
    parts = [blob(stages[n]) for n in (1, 2, 3)]
    if any(part is None for part in parts):
        return False
    with tempfile.TemporaryDirectory() as tmp:
        files = []
        for name, data in zip(("base", "ours", "theirs"), parts):
            files.append(os.path.join(tmp, name))
            with open(files[-1], "wb") as f:
                f.write(data)
        r = subprocess.run(["sh", UNION, "--resolve", "--path", path] + files, capture_output=True,
                           stdin=subprocess.DEVNULL)
        if r.returncode == 0 and r.stdout == have:
            return True
        _, attr, _ = git("check-attr", "--source=" + merge, "merge", "--", path)
        if attr.strip().endswith(": merge: union"):
            r = subprocess.run(["git", "merge-file", "-p", "--union", files[1], files[0], files[2]],
                               capture_output=True, stdin=subprocess.DEVNULL)
            return r.returncode == 0 and r.stdout == have
    return False


G, M = commit(o["from"], "from"), commit(o["head"], "head")
BASE = commit(o["base"], "base") if o.get("base") else None
if G == M:
    no(f"{M[:7]} is the gated head itself: there is nothing to carry")
_, line, _ = git("rev-list", "--first-parent", M)
if G not in line.split():
    no(f"{G[:7]} is not on {M[:7]}'s first-parent line")
resolved, c, newest = set(), M, None
while c != G:
    _, parents, _ = git("rev-list", "--parents", "-n", "1", c)
    parents = parents.split()[1:]
    if len(parents) == 1:
        no(f"{c[:7]} is not a merge: a commit of its own is a code change")
    if len(parents) != 2:
        no(f"{c[:7]} merges {len(parents)} parents: only a merge of two carries")
    p1, p2 = parents
    newest = newest or p2
    if BASE and git("merge-base", "--is-ancestor", p2, BASE)[0] != 0:
        no(f"{c[:7]} merges {p2[:7]}, which is not on {o['base']}")
    rc, out, err = git("merge-tree", "--write-tree", "-z", "--no-messages", p1, p2, raw=True)
    if rc not in (0, 1):
        no(f"git merge-tree could not redo {c[:7]}: " + ((err.strip().splitlines() or ["failed"])[-1])[:120])
    fields = out.split(b"\0")
    tree, stages, modes = fields[0].decode().strip(), {}, {}
    for field in fields[1:]:
        if not field:
            break
        meta, _, path = field.decode("utf-8", "surrogateescape").partition("\t")
        mode, oid, stage = meta.split()
        stages.setdefault(path, {})[int(stage)] = oid
        modes.setdefault(path, {})[int(stage)] = mode
    _, changed, _ = git("diff-tree", "-r", "-z", "--name-only", "--no-renames", tree, c + "^{tree}")
    for path in (p for p in changed.split("\0") if p):
        if path not in stages:
            no(f"{c[:7]} changes {path} beyond the merge git makes: a hand edit is a code change")
    for path in sorted(stages):
        if sorted(stages[path]) != [1, 2, 3]:
            no(f"{c[:7]}: {path} is a conflict no mechanical rule settles (a side deleted or renamed it)")
        sides = [modes[path][n] for n in (1, 2, 3)]
        if len(set(sides)) != 1:
            no(f"{c[:7]}: {path} is a conflict whose sides differ in file mode ({', '.join(sides)}): no mechanical rule settles it")
        kept = mode_in(c, path)
        if kept != sides[0]:
            no(f"{c[:7]}: {path} has mode {kept} in the merge but {sides[0]} in its conflict: a mode change is a code change")
        have = blob(c + ":" + path)
        if have is None or not mechanical(c, path, stages[path], have):
            no(f"{c[:7]}: {path} is not the mechanical resolution of its conflict")
        resolved.add(path)
    c = p1
_, named, _ = git("name-rev", "--name-only", "--refs=refs/remotes/*", "--exclude=refs/remotes/*/HEAD", newest)
ref = re.sub(r"[~^].*$", "", named.strip())
ref = ref[len("remotes/"):] if ref.startswith("remotes/") else ref
if not ref or ref == "undefined":
    ref = newest[:7]
files = ", ".join(sorted(resolved))
print(f"OK carried from {G}: merge of {ref}" + (f", mechanical conflicts resolved in {files}" if files else " with no conflicts"))
PY
