#!/bin/sh
# The one place that knows where a project's STAR folder is, and brings an old one up to date.
#   star-home.sh [--cwd <dir>] path      print the folder for the repo containing <dir> (default: here)
#   star-home.sh [--cwd <dir>] init      create it from the template when missing, make git ignore it,
#                                        print it. Safe to repeat; never overwrites a file.
#   star-home.sh [--cwd <dir>] migrate   bring a v1 folder to star.json schema 2 (STAR's closed loop):
#                                        prints "current", or "migrated rows=<n>" and then one
#                                        "stop <dispatch>" per worker of a removed stage
# The folder is <main checkout>/<docsRoot>/context/star. The main checkout is the first worktree
# git lists, so a linked worktree and a subfolder give the same answer. docsRoot follows the
# plugin's rule: "docsRoot" in .claude/workflow.local.json, else .claude/workflow.json; else
# docs/.superpowers when that folder exists and is not empty; else docs/superpowers.
# Ignoring never edits .gitignore: one line goes into <git common dir>/info/exclude, and only when
# git does not already ignore the folder.
# In a submodule or a --separate-git-dir repo git lists the git directory first; the checkout is
# found through core.worktree or the current directory. star.json's "project" keeps its name and
# everything STAR learned when the project folder is moved; only "repo" follows.
# migrate copies star.json and ledger.md to *.v1.bak (never over a backup), drops the review, fix
# and screen stages, "reviewer" and every stage's "executor", adds the schema 2 keys it lacks,
# moves rows out of the seven v1-only states and out of v1's verifying (pr-draft, reviewing,
# fix-queued, fixing to queued; screen-queued, screening, ready, verifying to brief-ready) with a
# decision record in each brief, and closes open approve-brief, prep and merge-pr queue items.
# The stop lines go to migrate-stops.txt in the folder before the first row moves, are printed
# after "migrated rows=<n>", and the file is then deleted; a run that finds the file (an earlier
# migrate stopped half way) prints its lines too, after "current" or "migrated rows=<n>".
# Exit: 0 ok, 1 not inside a usable git checkout, or a STAR folder migrate cannot read, or
# ledger.sh or loops.sh failing during migrate (the message names it), 64 usage.
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd) exec python3 - "$@" <<'PY'
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

SUBDIRS = ("inbox", "briefs", "reviews", "gates", "releases", "drafts", "memory", "specs", "reports",
           "items", "grants", "progress")
FILES = ("open-loops.md", "ledger.md", "star.json")
V2_DEFAULTS = {
    "executor": {"model": "latest-luna", "effort": "xhigh", "fallback": "latest-sol"},
    "gate": {"model": "gpt-6-astra", "effort": "xhigh", "fallback": "latest-sol", "maxRounds": 3},
    "hostedReviewer": None,
    "hostGate": {"minFreeGB": 3, "maxAgents": 40, "maxSwapGB": 11, "minDiskGB": 25},
    "progressDeadlineMin": 30,
}
MOVES = {"pr-draft": ("queued", "build", "resume"), "reviewing": ("queued", "build", "resume"),
         "fix-queued": ("queued", "build", "resume"), "fixing": ("queued", "build", "resume"),
         "screen-queued": ("brief-ready", "build", "screen"), "screening": ("brief-ready", "build", "screen"),
         "ready": ("brief-ready", "build", "merge"), "verifying": ("brief-ready", "build", "merge")}
RUNNING_V1 = ("reviewing", "fixing", "screening")
RECORDS = {
    "resume": ("Resume under the closed loop",
               "STAR moved to the closed loop (juel v2.0.0) while this item was {old}.",
               "Run the build again on the item's existing branch and draft PR: verify it, then the codex gate loop.",
               "No separate review or fix stage runs for it; the build worker gates its own PR."),
    "screen": ("Screen checks become person-only steps",
               "STAR moved to the closed loop (juel v2.0.0) while this item was {old}: checks waited for a person at the screen.",
               "Ask the checks listed in {pending} as person-only steps in the next batch summary; after go, the build resumes on the existing PR.",
               "No check waits for a person after go."),
    "merge": ("Merge under a go",
              "STAR moved to the closed loop (juel v2.0.0) while this item was {old}: its PR waited for the owner's merge.",
              "A v1 item: once you say go, the build resumes the gate loop on its existing PR, and STAR merges it under that go.",
              "The owner no longer presses merge for this PR: the go in the next batch summary is its grant."),
}


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
    elif arg in ("path", "init", "migrate") and cmd is None:
        cmd = arg
    else:
        die(64, f"unknown argument: {arg}")
if cmd is None:
    die(64, "usage: star-home.sh [--cwd <dir>] path|init|migrate")

listing = git(cwd, "worktree", "list", "--porcelain")
if listing.returncode != 0:
    die(1, f"{cwd} is not inside a git repository")
first = listing.stdout.split("\n\n")[0].splitlines()
main = next((l[len("worktree "):] for l in first if l.startswith("worktree ")), "")


def is_checkout(path):
    return os.path.isdir(path) and git(path, "rev-parse", "--is-inside-work-tree").stdout.strip() == "true"


def rev_parse(*args):
    return git(cwd, "rev-parse", *args).stdout.strip()


if main and "bare" not in first and not is_checkout(main):
    # A submodule or a --separate-git-dir repo: git lists the git directory, not the checkout.
    # core.worktree names the checkout when set (submodules); otherwise the directory we were
    # started in is the main checkout exactly when its git dir is the common one.
    worktree = git(main, "config", "core.worktree").stdout.strip()
    if worktree:
        main = os.path.normpath(os.path.join(main, worktree))
    elif os.path.realpath(rev_parse("--absolute-git-dir")) == os.path.realpath(
            os.path.join(cwd, rev_parse("--git-common-dir"))):
        main = rev_parse("--show-toplevel")
if not main or "bare" in first or not is_checkout(main):
    die(1, "STAR needs a project checkout (this is a bare repository, or its main checkout cannot be found)")
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


def write_json(path, data):
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def record(project, item, old, kind):
    """Append a decision record to the item's brief, inside ## Decisions (made when missing)."""
    path = os.path.join(home, "briefs", project, f"{item}.md")
    if not os.path.isfile(path):
        return
    text = open(path, encoding="utf-8").read()
    title, context, decision, consequences = RECORDS[kind]
    n = len(re.findall(r"^### D\d+ ", text, re.M)) + 1
    pending = os.path.join(home, "gates", project, f"{item}-screen.md")
    block = (f"### D{n} {title} ({datetime.now(timezone.utc).strftime('%Y-%m-%d')}, decided by STAR)\n"
             f"Context: {context.format(old=old)}\n"
             f"Decision: {decision.format(pending=pending)}\n"
             f"Consequences: {consequences}\n"
             f"Source: star-home.sh migrate\n")
    heading = re.search(r"^## Decisions[ \t]*$", text, re.M)
    if not heading:
        text = text.rstrip("\n") + "\n\n## Decisions\n" + block
    else:
        later = re.search(r"^## ", text[heading.end():], re.M)
        cut = heading.end() + later.start() if later else len(text)
        text = text[:cut].rstrip("\n") + "\n" + block + ("\n" + text[cut:] if later else "")
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def finish(stops, path):
    """Print the stop lines, then forget them: STAR stops those workers now."""
    for line in stops:
        print(line)
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def migrate():
    star_path = os.path.join(home, "star.json")
    stops_path = os.path.join(home, "migrate-stops.txt")
    try:
        data = json.load(open(star_path, encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(1, f"cannot read {star_path} ({e})")
    if not isinstance(data, dict):
        die(1, f"{star_path} is not a JSON object")
    try:
        stops = [l.strip() for l in open(stops_path, encoding="utf-8") if l.strip()]
    except OSError:
        stops = []
    if data.get("schema") == 2:
        print("current")
        finish(stops, stops_path)
        return
    for name in ("star.json", "ledger.md"):
        src = os.path.join(home, name)
        if os.path.exists(src) and not os.path.exists(src + ".v1.bak"):
            shutil.copyfile(src, src + ".v1.bak")
    stages = data.get("stages") if isinstance(data.get("stages"), dict) else {}
    for gone in ("review", "fix", "screen"):
        stages.pop(gone, None)
    for entry in stages.values():
        if isinstance(entry, dict):
            entry.pop("executor", None)
    data["stages"] = stages
    data.pop("reviewer", None)
    for key, value in V2_DEFAULTS.items():
        data.setdefault(key, value)
    project = (data.get("project") or {}).get("name") or ""
    skill = os.environ["STAR_SKILL_DIR"]
    rows = subprocess.run(["sh", os.path.join(skill, "ledger.sh"), "--home", home, "list"],
                          capture_output=True, text=True)
    if rows.returncode != 0:
        die(1, "ledger.sh list: " + (rows.stderr.strip() or f"exit {rows.returncode}"))
    moving = []
    for line in rows.stdout.splitlines():
        cells = line.split("\t")
        if len(cells) < 6 or cells[1] not in MOVES:
            continue
        moving.append((cells[0], cells[1]))
        if cells[1] in RUNNING_V1 and cells[5] not in ("", "-") and f"stop {cells[5]}" not in stops:
            stops.append(f"stop {cells[5]}")
    if stops:  # on disk before any row moves, so a run that stops half way can still name them
        tmp = f"{stops_path}.tmp.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(stops) + "\n")
        os.replace(tmp, stops_path)
    for item, old in moving:
        new, stage, kind = MOVES[old]
        done = subprocess.run(["sh", os.path.join(skill, "ledger.sh"), "--home", home, "set", item,
                               f"state={new}", f"stage={stage}", "task=-", "dispatch=-"], capture_output=True, text=True)
        if done.returncode != 0:
            die(1, f"ledger.sh set {item}: " + (done.stderr.strip() or f"exit {done.returncode}"))
        record(project, item, old, kind)
    queue, loops = os.path.join(home, "open-loops.md"), os.path.join(skill, "loops.sh")
    items = subprocess.run(["sh", loops, "--file", queue, "list"], capture_output=True, text=True)
    if items.returncode != 0:
        die(1, "loops.sh list: " + (items.stderr.strip() or f"exit {items.returncode}"))
    for line in items.stdout.splitlines():
        cells = line.split("\t")
        if len(cells) >= 2 and cells[1] in ("approve-brief", "prep", "merge-pr"):
            closed = subprocess.run(["sh", loops, "--file", queue, "close", cells[0]], capture_output=True, text=True)
            if closed.returncode not in (0, 4):  # 4: already closed
                die(1, f"loops.sh close {cells[0]}: " + (closed.stderr.strip() or f"exit {closed.returncode}"))
    data["schema"] = 2
    write_json(star_path, data)
    print(f"migrated rows={len(moving)}")
    finish(stops, stops_path)


os.makedirs(home, exist_ok=True)
lock = open(os.path.join(home, "init.lock"), "w")
fcntl.flock(lock, fcntl.LOCK_EX)
for d in SUBDIRS:
    os.makedirs(os.path.join(home, d), exist_ok=True)
if cmd == "migrate":
    migrate()
    sys.exit(0)
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
project = data.get("project") if isinstance(data, dict) else None
if isinstance(data, dict) and not (isinstance(project, dict) and project.get("repo") == main):
    # a first run, or a project folder that was moved: the name stays, the path follows
    kept = project if isinstance(project, dict) else {}
    data["project"] = {**kept, "name": kept.get("name") or os.path.basename(main), "repo": main}
    write_json(star, data)

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
