#!/bin/sh
# Checks that a PR is ready for the human's merge, on the exact head a worker reported.
#   pr-verify.sh <pr> --head <sha> [--repo <owner/name>]
# Prints exactly one line and exits 0 (64, with nothing on stdout, only for bad usage):
#   PASS [<note>] | PENDING <what> | MOVED <head> | MERGED <merge sha> | FAIL <what>
# "PASS approval is on an earlier commit" is still a pass: the repo's review rule is satisfied,
# but the approval was given before the newest commits; the note is for the person who merges.
# Green means every check that reported is green AND GitHub's merge state is not BLOCKED or
# BEHIND, so a required check that has not started yet is PENDING, not a pass.
# PENDING means "ask again later" (checks running, mergeable not computed, gh unreachable or
# its output unreadable). Where the repo has no review rule (empty reviewDecision), an approval
# counts only when it was given on the current head commit: dates are not compared, because a
# commit made earlier and pushed later carries an older date than the approval. Where the base
# branch's rules explicitly require 0 approving reviews (review-rule.sh prints "required 0"), no
# approval is needed: "PASS no approval required" (changes requested still fail). Where the repo
# has a review rule, GitHub's own reviewDecision is trusted as it stands (it follows the repo's
# "dismiss stale approvals" setting). gh signed in to an account that cannot see the repository
# prints "PENDING gh cannot see <repo>: export GH_TOKEN for this repository".
JUEL_SKILLS_DIR=$(cd "$(dirname "$0")/.." && pwd)
export JUEL_SKILLS_DIR
exec python3 - "$@" <<'PY'
import argparse
import json
import os
import re
import subprocess
import sys

PASSING = {"SUCCESS", "NEUTRAL", "SKIPPED"}
WAITING = {"", "PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}


def out(line):
    print(line)
    sys.exit(0)


def records(d, key):
    """The list of objects under key, [] when absent, None when gh printed some other shape."""
    value = [] if d.get(key) is None else d[key]
    if isinstance(value, list) and all(isinstance(e, dict) for e in value):
        return value
    return None


def names(items):
    return ", ".join(items[:5]) + (f" (+{len(items) - 5} more)" if len(items) > 5 else "")


p = argparse.ArgumentParser(prog="pr-verify.sh")
p.add_argument("pr")
p.add_argument("--head", required=True)
p.add_argument("--repo")
try:
    a = p.parse_args()
except SystemExit as e:
    sys.exit(64 if e.code not in (0, None) else 0)

try:
    LIMIT = float(os.environ.get("STAR_GH_TIMEOUT", "60"))
except ValueError:
    LIMIT = 60.0


def repo_of(url):
    parts = url.split("/") if isinstance(url, str) else []
    return "/".join(parts[3:5]) if len(parts) >= 5 and parts[0] in ("https:", "http:") else ""


def review_rule(d):
    """The first line review-rule.sh prints for this PR's base branch; "unknown" when it cannot run."""
    repo = a.repo or repo_of(d.get("url")) or repo_of(a.pr)
    base = d.get("baseRefName") if isinstance(d.get("baseRefName"), str) else ""
    script = os.path.join(os.environ.get("JUEL_SKILLS_DIR") or "", "babysit-pr", "review-rule.sh")
    if not repo or not base or not os.path.isfile(script):
        return "unknown"
    try:
        proc = subprocess.run(["sh", script, repo, base], capture_output=True, text=True, timeout=2 * LIMIT + 5)
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    return ((proc.stdout or "").splitlines() or ["unknown"])[0].strip()


def main():
    cmd = ["gh", "pr", "view", a.pr, "--json",
           "state,isDraft,reviewDecision,reviews,headRefOid,mergeable,mergeStateStatus,statusCheckRollup,mergeCommit,url,baseRefName"]
    if a.repo:
        cmd += ["-R", a.repo]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=LIMIT)
    except FileNotFoundError:
        out("PENDING gh: not found on PATH")
    except subprocess.TimeoutExpired:
        out("PENDING gh: timed out")
    if proc.returncode != 0:
        first = ((proc.stderr or "").strip().splitlines() or ["failed"])[0]
        if "Could not resolve to a Repository" in first:
            named = re.search(r"name '([^']+)'", first)
            repo = a.repo or (named.group(1) if named else "") or repo_of(a.pr) or "this repository"
            out(f"PENDING gh cannot see {repo}: export GH_TOKEN for this repository")
        out("PENDING gh: " + first[:120])
    try:
        d = json.loads(proc.stdout)
    except ValueError:
        out("PENDING gh: unreadable output")
    if not isinstance(d, dict):
        out("PENDING gh: unreadable output")
    reviews, checks = records(d, "reviews"), records(d, "statusCheckRollup")
    if reviews is None or checks is None:
        out("PENDING gh: unreadable output")
    a.head = a.head.strip().lower()
    state = d.get("state").upper() if isinstance(d.get("state"), str) else None
    if state not in ("OPEN", "MERGED", "CLOSED") or not isinstance(d.get("reviewDecision") or "", str):
        out("PENDING gh: unreadable output")

    if state == "MERGED":
        out("MERGED " + ((d.get("mergeCommit") or {}).get("oid") or "unknown"))
    if state == "CLOSED":
        out("FAIL closed")
    head = (d.get("headRefOid") or "").lower()
    if len(a.head) < 7:
        out("FAIL bad head: " + a.head)
    if not head:
        out("PENDING gh: no head")
    if not head.startswith(a.head):
        out("MOVED " + head)
    if d.get("isDraft"):
        out("FAIL draft")

    decision = d.get("reviewDecision") or None
    zero = False
    if decision is None:
        latest = {}
        for n, r in enumerate(sorted(reviews, key=lambda r: r.get("submittedAt") or "")):
            if r.get("state") in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
                # a deleted account has no login: each of its reviews is its own reviewer
                who = (r.get("author") or {}).get("login")
                latest[who or ("", r.get("id") or n)] = r
        blockers = sorted({who if isinstance(who, str) else "a deleted account"
                           for who, r in latest.items() if r.get("state") == "CHANGES_REQUESTED"})
        if blockers:
            out("FAIL approval: changes requested by " + names(blockers))
        zero = review_rule(d) == "required 0"
        if not zero and not any(r.get("state") == "APPROVED" and ((r.get("commit") or {}).get("oid") or "").lower() == head
                                for r in latest.values()):
            out("FAIL approval: none on the current head")
    elif decision != "APPROVED":
        out("FAIL approval: " + decision)
    on_head = any(r.get("state") == "APPROVED" and ((r.get("commit") or {}).get("oid") or "").lower() == head
                  for r in reviews)

    failed, waiting = [], []
    for c in checks:
        name = c.get("name") or c.get("context") or "check"
        if c.get("__typename") == "CheckRun" and (c.get("status") or "COMPLETED") != "COMPLETED":
            waiting.append(name)
            continue
        value = (c.get("conclusion") or c.get("state") or "").upper()
        if value in PASSING:
            continue
        (waiting if value in WAITING else failed).append(name)
    if failed:
        out("FAIL checks: " + names(failed))
    if d.get("mergeable") == "CONFLICTING":
        out("FAIL conflicts")
    if waiting:
        out("PENDING checks: " + names(waiting))
    if d.get("mergeable") != "MERGEABLE":
        out("PENDING mergeable")
    merge_state = str(d.get("mergeStateStatus") or "").upper()
    if merge_state == "BLOCKED":
        out("PENDING merge state: blocked (a required check or review has not reported)")
    if merge_state == "BEHIND":
        out("PENDING merge state: behind the base branch")
    out("PASS" if on_head else "PASS no approval required" if zero else "PASS approval is on an earlier commit")


try:
    main()
except Exception:  # an output shape nobody planned for is "ask again later", never a crash or a pass
    out("PENDING gh: unreadable output")
PY
