#!/bin/sh
# Checks a build worker's DONE report against STAR's files and GitHub, so STAR never opens a review.
#   done-check.sh [--home H] <item> --pr <url> --head <sha>
# Prints one line and exits 0:
#   OK                 the PR's head starts with <sha>, the item's newest review is SAFE for that
#                      full head (review-proof.sh), and the PR carries "Codex gate: PASS (head
#                      <PR head>" in a comment by the PR's author
#   MISMATCH <what>    review: <why>, head: <why> or pass: <why>
#   PENDING <why>      gh could not be read: ask again later
# Exit 64 on bad usage.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
JUEL_SKILLS_DIR=$(cd "$(dirname "$0")/.." && pwd)
export STAR_HOME_DEFAULT JUEL_SKILLS_DIR
exec python3 - "$@" <<'PY'
import json
import os
import re
import subprocess
import sys


def out(line):
    print(line)
    sys.exit(0)


def die(msg):
    print(f"done-check.sh: {msg}", file=sys.stderr)
    sys.exit(64)


home, args, item, pr, head = os.environ.get("STAR_HOME_DEFAULT") or "", sys.argv[1:], None, None, None
while args:
    arg = args.pop(0)
    if arg in ("--home", "--pr", "--head"):
        if not args:
            die(f"{arg} needs a value")
        value = args.pop(0)
        if arg == "--home":
            home = value
        elif arg == "--pr":
            pr = value
        else:
            head = value.strip().lower()
    elif arg.startswith("-"):
        die(f"unknown argument: {arg}")
    elif item is None:
        item = arg
    else:
        die(f"unexpected argument: {arg}")
if not item or not pr or not head:
    die("usage: done-check.sh [--home H] <item> --pr <url> --head <sha>")
if not re.fullmatch(r"[0-9a-f]{7,40}", head):
    die("--head takes 7 to 40 hex characters")
try:
    project = json.load(open(os.path.join(home, "star.json"), encoding="utf-8"))["project"]["name"]
except (OSError, ValueError, KeyError, TypeError):
    die(f"cannot read the project name from {home}/star.json")
reviews = os.path.join(home, "reviews", project)
rounds = [int(m.group(1)) for m in (re.fullmatch(re.escape(item) + r"-r(\d+)\.md", n)
                                     for n in (os.listdir(reviews) if os.path.isdir(reviews) else [])) if m]
if not rounds:
    out(f"MISMATCH review: no review for {item} in {reviews}")
newest = os.path.join(reviews, f"{item}-r{max(rounds)}.md")
try:
    view = subprocess.run(["gh", "pr", "view", pr, "--json", "author,comments,headRefOid"],
                          capture_output=True, text=True, timeout=60)
except (OSError, subprocess.TimeoutExpired) as e:
    out(f"PENDING gh: {type(e).__name__}")
if view.returncode != 0:
    out("PENDING gh: " + ((view.stderr or view.stdout or "").strip().splitlines() or ["failed"])[0][:120])
try:
    d = json.loads(view.stdout)
    author = (d.get("author") or {}).get("login") or ""
    pr_head = str(d.get("headRefOid") or "").lower()
    comments = [c for c in (d.get("comments") or []) if isinstance(c, dict)]
except (ValueError, AttributeError):
    out("PENDING gh: unreadable output")
if not pr_head.startswith(head):
    out(f"MISMATCH head: the PR's head is {pr_head[:7] or '?'}, the report says {head[:7]}")
# review-proof.sh needs the full commit: the report may give a short one
proof = subprocess.run(["sh", os.path.join(os.environ["JUEL_SKILLS_DIR"], "babysit-pr", "review-proof.sh"),
                        newest, "--item", item, "--head", pr_head], capture_output=True, text=True)
line = (proof.stdout.strip().splitlines() or [""])[0]
if not line.startswith("OK "):
    out("MISMATCH review: " + (line[3:] if line.startswith("NO ") else line or "review-proof.sh could not run"))
prefix = f"Codex gate: PASS (head {pr_head}"
if not any((c.get("author") or {}).get("login") == author and str(c.get("body") or "").startswith(prefix)
           for c in comments):
    out(f"MISMATCH pass: no codex PASS on the PR for {pr_head[:7]}")
out("OK")
PY
