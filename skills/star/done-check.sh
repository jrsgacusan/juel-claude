#!/bin/sh
# Checks a build worker's DONE report against STAR's files and GitHub, so STAR never opens a review.
#   done-check.sh [--home H] <item> --pr <url> --head <sha>
# Prints one line and exits 0:
#   OK                 the PR's head starts with <sha>, the item's newest review is SAFE for that
#                      full head (review-proof.sh), or the newest round has the owner's carried
#                      PASS for that head (<item>-r<k>-carried.md, #82), or the newest review is
#                      SAFE for an earlier head that carry-check.sh carries to the PR's head (#110),
#                      and the PR carries "Codex gate: PASS (head <PR head>" in a comment by the
#                      PR's author
#   MISMATCH <what>    review: <why>, head: <why> or pass: <why>
#   PENDING <why>      gh could not be read: ask again later
# The carry (#110): when the newest <item>-r<k>.md is SAFE but for another head, and star.json names
# the project's repository ("project": {"repo": ...}), it runs
#   carry-check.sh --from <the review's head> --head <PR head> --base <remote>/<PR base> --repo-dir <repo>
# with <remote> origin when <repo> has origin/<PR base>, else the one remote that has it, the way
# codex-gate.sh post-pass picks it. Anything but "OK carried from ..." prints
# "MISMATCH review: not carried: <why>". With no repo in star.json, review-proof.sh's line stands.
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
    star = json.load(open(os.path.join(home, "star.json"), encoding="utf-8"))
    project, repo = star["project"]["name"], star["project"].get("repo")
except (OSError, ValueError, KeyError, TypeError, AttributeError):
    die(f"cannot read the project name from {home}/star.json")
reviews = os.path.join(home, "reviews", project)
rounds = [int(m.group(1)) for m in (re.fullmatch(re.escape(item) + r"-r(\d+)\.md", n)
                                     for n in (os.listdir(reviews) if os.path.isdir(reviews) else [])) if m]
if not rounds:
    out(f"MISMATCH review: no review for {item} in {reviews}")
newest = os.path.join(reviews, f"{item}-r{max(rounds)}.md")
carried = os.path.join(reviews, f"{item}-r{max(rounds)}-carried.md")
if os.path.isfile(carried):  # the owner shipped the newest round's head with its findings deferred (#82)
    newest = carried
try:
    view = subprocess.run(["gh", "pr", "view", pr, "--json", "author,baseRefName,comments,headRefOid"],
                          capture_output=True, text=True, timeout=60)
except (OSError, subprocess.TimeoutExpired) as e:
    out(f"PENDING gh: {type(e).__name__}")
if view.returncode != 0:
    out("PENDING gh: " + ((view.stderr or view.stdout or "").strip().splitlines() or ["failed"])[0][:120])
try:
    d = json.loads(view.stdout)
    author = (d.get("author") or {}).get("login") or ""
    pr_head = str(d.get("headRefOid") or "").lower()
    base = str(d.get("baseRefName") or "")
    comments = [c for c in (d.get("comments") or []) if isinstance(c, dict)]
except (ValueError, AttributeError):
    out("PENDING gh: unreadable output")
if not pr_head.startswith(head):
    out(f"MISMATCH head: the PR's head is {pr_head[:7] or '?'}, the report says {head[:7]}")


def last(text):
    return (text.strip().splitlines() or [""])[-1]


def not_carried(gated):
    """None when carry-check.sh carries the SAFE review of gated to the PR's head (#110), else why not."""
    if not base:
        return "the PR's base branch is unknown"
    refs = subprocess.run(["git", "-C", repo, "for-each-ref", "--format=%(refname:short)",
                           f"refs/remotes/*/{base}"], capture_output=True, text=True).stdout.split()
    ref = f"origin/{base}" if f"origin/{base}" in refs else (refs[0] if len(refs) == 1 else "")
    if not ref:
        return f"no single remote-tracking branch for the base {base} (found: {', '.join(refs) or 'none'})"
    r = subprocess.run(["sh", os.path.join(os.environ["JUEL_SKILLS_DIR"], "star", "carry-check.sh"),
                        "--from", gated, "--head", pr_head, "--base", ref, "--repo-dir", repo],
                       capture_output=True, text=True)
    said = last(r.stdout)
    if r.returncode == 0 and said.startswith("OK carried from "):
        return None
    if said.startswith("NO "):
        return said[3:]
    return "carry-check failed: " + (last(r.stderr) or said or f"exit {r.returncode}")


# review-proof.sh needs the full commit: the report may give a short one
proof = subprocess.run(["sh", os.path.join(os.environ["JUEL_SKILLS_DIR"], "babysit-pr", "review-proof.sh"),
                        newest, "--item", item, "--head", pr_head], capture_output=True, text=True)
line = (proof.stdout.strip().splitlines() or [""])[0]
if not line.startswith("OK "):
    why = line[3:] if line.startswith("NO ") else line or "review-proof.sh could not run"
    reviewed = None
    if newest != carried and line.startswith("NO head: ") and isinstance(repo, str) and repo:
        # review-proof.sh checks the verdict before the head, so this review is SAFE for another head
        first = open(newest, encoding="utf-8", errors="replace").readline()
        m = re.match(r"VERDICT item=\S+ round=\d+ SAFE findings=\d+ head=([0-9a-fA-F]{7,40})\s*$", first)
        reviewed = m and m.group(1)
    if not reviewed:
        out("MISMATCH review: " + why)
    why = not_carried(reviewed)
    if why:
        out("MISMATCH review: not carried: " + why)
prefix = f"Codex gate: PASS (head {pr_head}"
if not any((c.get("author") or {}).get("login") == author and str(c.get("body") or "").startswith(prefix)
           for c in comments):
    out(f"MISMATCH pass: no codex PASS on the PR for {pr_head[:7]}")
out("OK")
PY
