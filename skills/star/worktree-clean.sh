#!/bin/sh
# Removes the Orca worktree of a finished STAR row when nothing in it would be lost.
#   worktree-clean.sh [--home H] <item>
#     -> removed <path> | kept <path>: <why> | none
#        with "kept-builds <H>/builds/<item>/" on its own line first when specs or plans were copied,
#        then "kept-evidence <H>/evidence/<item>/" when evidence was copied, then
#        "evidence-size <item> <x.x> GB" when that evidence is over 1 GiB
# For a done or dropped row, whether or not a worktree is left, it first gzips the item's codex
# transcripts <H>/reviews/<project>/<item>-r<k>.log and <item>-r<k>-error-<n>.log (nothing else there
# changes) and prints "reviews-gzipped <item> <n>" as its first line when <n> is 1 or more.
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
# The build's docs outlive it too: every specs/ and plans/ folder under those same docsRoots (the spec,
# the plan, the review plan) is copied the same way, with the same size check, into
# <H>/builds/<item>/specs/ and <H>/builds/<item>/plans/.
# The evidence copy leaves out, by class:
#   folders named node_modules .build DerivedData .venv venv target __pycache__ .gradle tmp .tmp .git,
#   and folders ending .app .mlmodelc .xcarchive;
#   files ending .o .dmg .pkg .ipa .pack .idx .a .so .dylib .gguf .safetensors .onnx .pt .bin .parquet .npz;
#   audio files (.wav .flac .aif .aiff .caf .mp3 .m4a .ogg) over 10 MB (10 * 1024 * 1024 bytes).
# The copy alone also hardlinks a file whose sha256 equals one already copied for the item (never to a path a later
# evidence root has since replaced), and, for
# evidence folders that share a name but for a -v<N> suffix, keeps only the text files (.md .txt .json
# .log .csv) of the older runs when the newest holds a report.md (with none, every run is copied whole).
# --evidence-report and --evidence-prune apply the skip classes alone. Each skipped path is a line
# "<path relative to the evidence folder>\t<bytes>" in <H>/evidence/<item>/skipped.txt (a folder's bytes
# are its total). The size line counts what was copied, not what was skipped.
# <why>: row is <state> | the main checkout | in use by <item> | not a git checkout |
#        uncommitted changes | unpushed commits | evidence copy failed: <why> |
#        build docs copy failed: <why> | orca: <message>
#   worktree-clean.sh [--home H] --evidence-report
#     -> one line "<item>\t<relative path>\t<bytes>" per skip-listed folder or file already under
#        <H>/evidence/ (sorted by item, then path; a folder inside another is listed once, at the
#        outer one), then "total <n> gb=<x.x>". Reads only; needs no ledger, git or orca.
#   worktree-clean.sh [--home H] --evidence-prune
#     -> removes exactly what the report lists, appends each to that item's skipped.txt, and prints
#        "pruned <n> gb=<x.x>"
#   Both modes exit 0; 2 the STAR folder cannot be read; 64 usage (an item with either mode).
# Test seams: ORCA_CLI_COMMAND; JUEL_EVIDENCE_GB_LIMIT (GiB, default 1) sets the size above which
# "evidence-size" is printed.
# Exit: 0 with one of the lines above; 2 the STAR folder or star.json cannot be read; 4 no row for
# the item; 64 usage.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
export STAR_HOME_DEFAULT STAR_SKILL_DIR
exec python3 - "$@" <<'PY'
import gzip
import hashlib
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


SKIP_DIRS = ("node_modules", ".build", "DerivedData", ".venv", "venv", "target", "__pycache__", ".gradle",
             "tmp", ".tmp", ".git")
SKIP_DIR_SUFFIXES = (".app", ".mlmodelc", ".xcarchive")
SKIP_EXTS = (".o", ".dmg", ".pkg", ".ipa", ".pack", ".idx", ".a", ".so", ".dylib", ".gguf", ".safetensors",
             ".onnx", ".pt", ".bin", ".parquet", ".npz")
AUDIO_EXTS = (".wav", ".flac", ".aif", ".aiff", ".caf", ".mp3", ".m4a", ".ogg")
AUDIO_LIMIT = 10 * 1024 * 1024
TEXT_EXTS = (".md", ".txt", ".json", ".log", ".csv")
GIB = 1024 ** 3


def skip_listed(path, is_dir):
    """True for a path the evidence copy leaves out: judged by its name, and for audio by its size."""
    name = os.path.basename(path)
    if is_dir:
        return name in SKIP_DIRS or name.endswith(SKIP_DIR_SUFFIXES)
    low = name.lower()
    if low.endswith(SKIP_EXTS):
        return True
    if low.endswith(AUDIO_EXTS):
        try:
            return os.lstat(path).st_size > AUDIO_LIMIT
        except OSError:
            return False
    return False


def version_group(name):
    """(name without a trailing -v<N>, N); N is 1 for a name with no suffix."""
    m = re.match(r"^(.*)-v(\d+)$", name)
    return (m.group(1), int(m.group(2))) if m else (name, 1)


def superseded_runs(src):
    """Names of the folders directly under src that a newer -v<N> run replaced, where that newest
    run holds a report.md (a finished run). With no report.md in the newest, none are superseded."""
    groups = {}
    for name in os.listdir(src):
        if os.path.isdir(os.path.join(src, name)) and not os.path.islink(os.path.join(src, name)):
            base, n = version_group(name)
            groups.setdefault(base, []).append((n, name))
    old = set()
    for members in groups.values():
        if len(members) < 2:
            continue
        members.sort()
        if os.path.isfile(os.path.join(src, members[-1][1], "report.md")):
            old.update(name for _, name in members[:-1])
    return old


def tree_bytes(path):
    """Total size of a file, or of every file under a folder (links count as links)."""
    if os.path.islink(path) or not os.path.isdir(path):
        return os.lstat(path).st_size
    total = 0
    for top, dirs, files in os.walk(path):
        for name in files + [d for d in dirs if os.path.islink(os.path.join(top, d))]:
            total += os.lstat(os.path.join(top, name)).st_size
    return total


def note_skipped(dest, rows):
    """Append "<path>\t<bytes>" lines to <dest>/skipped.txt, leaving out lines already there."""
    if not rows:
        return
    os.makedirs(dest, exist_ok=True)
    listing = os.path.join(dest, "skipped.txt")
    have = set()
    if os.path.exists(listing):
        have = set(open(listing, encoding="utf-8", errors="replace").read().splitlines())
    with open(listing, "a", encoding="utf-8") as f:
        for rel, size in rows:
            line = f"{rel}\t{size}"
            if line not in have:
                f.write(line + "\n")
                have.add(line)


def gb_limit():
    try:
        return float(os.environ.get("JUEL_EVIDENCE_GB_LIMIT", "1"))
    except ValueError:
        return 1.0


args, home = sys.argv[1:], os.environ.get("STAR_HOME_DEFAULT") or ""
if args[:1] == ["--home"]:
    if len(args) < 2:
        die(64, "--home needs a folder")
    home, args = args[1], args[2:]
if args[:1] in (["--evidence-report"], ["--evidence-prune"]):
    mode = args[0]
    if len(args) != 1:
        die(64, f"usage: worktree-clean.sh [--home H] {mode}")
    if not home:
        die(2, "no STAR folder: pass --home, or run inside a project")
    base = os.path.join(home, "evidence")
    found = []
    try:
        if not os.path.isdir(home):
            raise OSError(2, "no such folder", home)
        names = sorted(os.listdir(base)) if os.path.isdir(base) else []
        for name in names:
            root = os.path.join(base, name)
            if not os.path.isdir(root) or os.path.islink(root):
                continue
            for top, dirs, files in os.walk(root):
                dirs.sort()
                for d in [d for d in dirs if skip_listed(os.path.join(top, d), True)]:
                    full = os.path.join(top, d)
                    found.append((name, os.path.relpath(full, root), tree_bytes(full), full))
                dirs[:] = [d for d in dirs if not skip_listed(os.path.join(top, d), True)]
                for f in sorted(files):
                    full = os.path.join(top, f)
                    if skip_listed(full, False):
                        found.append((name, os.path.relpath(full, root), tree_bytes(full), full))
        found.sort(key=lambda r: (r[0], r[1]))
        if mode == "--evidence-prune":
            for name, rel, size, full in found:
                if os.path.islink(full) or not os.path.isdir(full):
                    os.remove(full)
                else:
                    shutil.rmtree(full)
                note_skipped(os.path.join(base, name), [(rel, size)])
    except OSError as e:
        die(2, f"cannot read or write the evidence folders ({getattr(e, 'strerror', None) or e})")
    total = sum(r[2] for r in found)
    if mode == "--evidence-report":
        for name, rel, size, _ in found:
            print(f"{name}\t{rel}\t{size}")
        print(f"total {len(found)} gb={total / GIB:.1f}")
    else:
        print(f"pruned {len(found)} gb={total / GIB:.1f}")
    sys.exit(0)
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


def doc_folders(worktree, sub):
    """Each <docsRoot>/<sub>/ folder the worktree holds: under the docsRoot STAR's home sits in,
    and under the plugin's two default docsRoots."""
    roots = ["docs/superpowers", "docs/.superpowers"]
    real_home, main = os.path.realpath(home), os.path.realpath(repo)
    docs = os.path.dirname(os.path.dirname(real_home))
    if (os.path.basename(real_home) == "star" and os.path.basename(os.path.dirname(real_home)) == "context"
            and (docs == main or docs.startswith(main + os.sep))):
        roots.insert(0, os.path.relpath(docs, main))
    found, seen = [], set()
    for rel in roots:
        folder = os.path.join(worktree, rel, sub)
        if os.path.isdir(folder) and os.path.realpath(folder) not in seen:
            seen.add(os.path.realpath(folder))
            found.append(folder)
    return found


def evidence_dirs(worktree):
    return doc_folders(worktree, "evidence")


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def copy_checked(pairs, ignore=None):
    """Copy each (src, dest) folder, then check every file arrived at its size. Returns (files
    copied, skipped rows [(path under src, bytes)], bytes copied). Raises OSError or ValueError.
    With ignore: the skip classes are left out, a file whose sha256 equals one already copied is
    hardlinked to it, and the folders of superseded -v<N> runs keep only their text files."""
    skipped, copied, size = [], 0, 0
    seen = {}  # sha256 -> the copy made first
    old = {src: superseded_runs(src) if ignore else set() for src, _ in pairs}

    def left_out(src, full, is_dir):
        if skip_listed(full, is_dir):
            return True
        rel = os.path.relpath(full, src).split(os.sep)
        return (not is_dir and rel[0] in old[src] and len(rel) > 1
                and not full.lower().endswith(TEXT_EXTS))

    def ignorer(src):
        def ignore_fn(top, names):
            drop = []
            for n in names:
                full = os.path.join(top, n)
                is_dir = os.path.isdir(full) and not os.path.islink(full)
                if ignore and left_out(src, full, is_dir):
                    drop.append(n)
                    if skip_listed(full, is_dir):
                        skipped.append((os.path.relpath(full, src), tree_bytes(full)))
            return drop
        return ignore_fn

    def copy_file(a, b):
        if ignore:
            digest = sha256_of(a)
            if os.path.lexists(b):
                os.remove(b)  # never write through a link an earlier attempt made
            # b is written anew below: no earlier copy may stand for what it held before
            for d in [d for d, v in seen.items() if v == b]:
                del seen[d]
            first = seen.get(digest)
            if first and os.path.exists(first):
                try:
                    os.link(first, b)
                    return b
                except OSError:
                    pass
            shutil.copy2(a, b)
            seen.setdefault(digest, b)
            return b
        return shutil.copy2(a, b)

    for src, dest in pairs:
        shutil.copytree(src, dest, symlinks=True, dirs_exist_ok=True, ignore=ignorer(src), copy_function=copy_file)
    missing = 0
    for src, dest in pairs:
        for top, dirs, files in os.walk(src):
            if ignore:
                dirs[:] = [d for d in dirs if not (not os.path.islink(os.path.join(top, d)) and left_out(src, os.path.join(top, d), True))]
                files = [f for f in files if not left_out(src, os.path.join(top, f), False)]
            for name in files + [d for d in dirs if os.path.islink(os.path.join(top, d))]:
                copied += 1
                orig = os.path.join(top, name)
                copy = os.path.join(dest, os.path.relpath(orig, src))
                plain = os.path.isfile(orig) and not os.path.islink(orig)
                if plain:
                    size += os.path.getsize(orig)
                if not os.path.lexists(copy) or (plain and os.path.getsize(copy) != os.path.getsize(orig)):
                    missing += 1
    if missing:
        raise ValueError(f"{missing} of {copied} files missing after the copy")
    return copied, skipped, size


def keep_builds(worktree):
    """(<H>/builds/<item>/, None) after a full copy of the specs and plans; (None, None) when there
    are none; (None, why) when the copy failed or left a file out."""
    pairs = [(f, os.path.join(home, "builds", item, sub)) for sub in ("specs", "plans") for f in doc_folders(worktree, sub)]
    if not pairs:
        return None, None
    if re.search(r"[\x00-\x1f\x7f/\\]", item) or item.startswith("."):
        return None, f"{item} is not a plain folder name"
    try:
        copied, _, _ = copy_checked(pairs)
    except (OSError, ValueError) as e:
        return None, str(getattr(e, "strerror", None) or e)[:120]
    return (os.path.join(home, "builds", item) + "/", None) if copied else (None, None)


def keep_evidence(worktree):
    """(<H>/evidence/<item>/, bytes copied) after a full copy; (None, None) when there is nothing to
    keep; (None, why) when the copy failed or left a file out."""
    sources = evidence_dirs(worktree)
    if not sources:
        return None, None
    if re.search(r"[\x00-\x1f\x7f/\\]", item) or item.startswith("."):
        return None, f"{item} is not a plain folder name"
    dest = os.path.join(home, "evidence", item)
    try:
        _, skipped, size = copy_checked([(src, dest) for src in sources], ignore=True)
        note_skipped(dest, skipped)
    except (OSError, ValueError) as e:
        return None, str(getattr(e, "strerror", None) or e)[:120]
    return dest + "/", size


def gzip_reviews(project_name):
    """Gzip the item's codex transcripts (<item>-r<k>.log, <item>-r<k>-error-<n>.log) in
    <H>/reviews/<project>/, leaving every other file and any .gz already there alone. Returns how many."""
    if not project_name or re.search(r"[\x00-\x1f\x7f/\\]", project_name) or project_name.startswith("."):
        return 0
    folder = os.path.join(home, "reviews", project_name)
    pattern = re.compile(re.escape(item) + r"-r\d+(-error-\d+)?\.log")
    done = 0
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return 0
    for name in names:
        full = os.path.join(folder, name)
        if not pattern.fullmatch(name) or os.path.islink(full) or not os.path.isfile(full):
            continue
        try:
            with open(full, "rb") as f, gzip.open(full + ".gz", "wb") as g:
                shutil.copyfileobj(f, g)
            os.remove(full)
            done += 1
        except OSError:
            try:
                os.remove(full + ".gz")
            except OSError:
                pass
    return done


row = dict(l.split("=", 1) for l in ledger("get", item).splitlines() if "=" in l)
path, state = row["worktree"], row["state"]
if state in FINISHED:
    n_gzipped = gzip_reviews(row.get("project", "").strip())
    if n_gzipped:
        print(f"reviews-gzipped {item} {n_gzipped}")
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
builds_at, why = keep_builds(path)
if why:
    out(f"kept {path}: build docs copy failed: {why}")
kept_at, result = keep_evidence(path)
if kept_at is None and result:
    out(f"kept {path}: evidence copy failed: {result}")
if builds_at:
    print(f"kept-builds {builds_at}")
if kept_at:
    print(f"kept-evidence {kept_at}")
    if result / GIB > gb_limit():
        print(f"evidence-size {item} {result / GIB:.1f} GB")
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
