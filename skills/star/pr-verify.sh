#!/bin/sh
# Checks that a PR is ready for the human's merge, on the exact head a worker reported.
#   pr-verify.sh <pr> --head <sha> [--repo <owner/name>]
# Prints exactly one line and exits 0:
#   PASS | PENDING <what> | MOVED <head> | MERGED <merge sha> | FAIL <what>
# PENDING means "ask again later" (checks running, mergeable not computed, gh unreachable or
# its output unreadable). Where the repo has no review rule (empty reviewDecision), an approval
# counts only when it was given on the current head commit: dates are not compared, because a
# commit made earlier and pushed later carries an older date than the approval.
exec python3 - "$@" <<'PY'
import argparse
import json
import os
import subprocess
import sys

PASSING = {"SUCCESS", "NEUTRAL", "SKIPPED"}
WAITING = {"", "PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}


def out(line):
    print(line)
    sys.exit(0)


def records(d, key):
    """The list of objects under key, [] when absent, None when gh printed some other shape."""
    value = d.get(key) or []
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

cmd = ["gh", "pr", "view", a.pr, "--json",
       "state,isDraft,reviewDecision,reviews,headRefOid,mergeable,statusCheckRollup,mergeCommit"]
if a.repo:
    cmd += ["-R", a.repo]
try:
    limit = float(os.environ.get("STAR_GH_TIMEOUT", "60"))
except ValueError:
    limit = 60.0
try:
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=limit)
except FileNotFoundError:
    out("PENDING gh: not found on PATH")
except subprocess.TimeoutExpired:
    out("PENDING gh: timed out")
if proc.returncode != 0:
    out("PENDING gh: " + ((proc.stderr or "").strip().splitlines() or ["failed"])[0][:120])
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

if d.get("state") == "MERGED":
    out("MERGED " + ((d.get("mergeCommit") or {}).get("oid") or "unknown"))
if d.get("state") == "CLOSED":
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
    if not any(r.get("state") == "APPROVED" and ((r.get("commit") or {}).get("oid") or "").lower() == head
               for r in latest.values()):
        out("FAIL approval: none on the current head")
elif decision != "APPROVED":
    out("FAIL approval: " + decision)

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
out("PASS")
PY
