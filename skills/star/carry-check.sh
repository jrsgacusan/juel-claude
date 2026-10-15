#!/bin/sh
# Proves that a head is the gated head plus merges of the base that brought no change to a file the
# branch changes, so the gated head's SAFE verdict carries to it and no codex round is spent on such
# a merge (#75, #110).
#   carry-check.sh --from <G> --head <M> [--base <ref>] [--repo-dir <dir>]
# Prints one line:
#   OK carried from <G full sha>: merge of <ref> brings no change to a file this branch changes   exit 0
#   NO <why>                                                                                       exit 1
# Exit 64 on bad usage: a missing or unknown flag, or a commit git does not know.
# <G> must be on <M>'s first-parent line, and every commit on that line after <G> must be a merge
# of two parents, P1 (the line from <G>) and P2. For each, "git merge-tree --write-tree P1 P2" is
# the merge git makes by itself, and the merge commit must be exactly that outside the merge's
# conflicts: a file where it differs is a hand edit, file mode included. Then the merge must bring
# no change to a file this branch changes (#110): "own" is every path that differs between
# git merge-base P1 P2 and P1, "incoming" every path that differs between P1 and the merge commit.
# A path in both, or any path the merge conflicted on (both sides changed it, however it was
# resolved), is NO, the first in byte order named:
#   NO <c7> brings base changes to <path>, a file this branch changes: the gate reviews the merge
# A commit of its own is NO. With --base, every P2 must be on <ref> (git merge-base
# --is-ancestor), so only the base branch is ever carried in.
# <ref> is the newest merge's P2 named by "git name-rev --refs=refs/remotes/*" (not the
# refs/remotes/<remote>/HEAD alias, which a clone adds) without "remotes/" or a ~n/^n suffix
# ("origin/main"), else its 7-character sha.
exec python3 - "$@" <<'PY'
import os
import re
import subprocess
import sys


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


def git(*cmd, raw=False):
    r = subprocess.run(["git", "-C", REPO] + list(cmd), capture_output=True, stdin=subprocess.DEVNULL)
    text = r.stdout if raw else r.stdout.decode("utf-8", "surrogateescape")
    return r.returncode, text, r.stderr.decode("utf-8", "replace")


def commit(rev, flag):
    rc, sha, _ = git("rev-parse", "--verify", "--quiet", rev + "^{commit}")
    if rc != 0 or not sha.strip():
        die(f"--{flag}: git knows no commit {rev}")
    return sha.strip()


def paths(*cmd):
    """The NUL-separated paths one git diff command prints."""
    _, out, _ = git(*cmd)
    return {p for p in out.split("\0") if p}


G, M = commit(o["from"], "from"), commit(o["head"], "head")
BASE = commit(o["base"], "base") if o.get("base") else None
if G == M:
    no(f"{M[:7]} is the gated head itself: there is nothing to carry")
_, line, _ = git("rev-list", "--first-parent", M)
if G not in line.split():
    no(f"{G[:7]} is not on {M[:7]}'s first-parent line")
c, newest = M, None
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
    tree, conflicted = fields[0].decode().strip(), set()
    for field in fields[1:]:
        if not field:
            break
        conflicted.add(field.decode("utf-8", "surrogateescape").partition("\t")[2])
    for path in sorted(paths("diff-tree", "-r", "-z", "--name-only", "--no-renames", tree, c + "^{tree}")):
        if path not in conflicted:
            no(f"{c[:7]} changes {path} beyond the merge git makes: a hand edit is a code change")
    _, fork, _ = git("merge-base", p1, p2)
    own = paths("diff", "-z", "--name-only", "--no-renames", fork.strip(), p1)
    incoming = paths("diff-tree", "-r", "-z", "--name-only", "--no-renames", p1, c)
    both = sorted((own & incoming) | conflicted)
    if both:
        no(f"{c[:7]} brings base changes to {both[0]}, a file this branch changes: the gate reviews the merge")
    c = p1
_, named, _ = git("name-rev", "--name-only", "--refs=refs/remotes/*", "--exclude=refs/remotes/*/HEAD", newest)
ref = re.sub(r"[~^].*$", "", named.strip())
ref = ref[len("remotes/"):] if ref.startswith("remotes/") else ref
if not ref or ref == "undefined":
    ref = newest[:7]
print(f"OK carried from {G}: merge of {ref} brings no change to a file this branch changes")
PY
