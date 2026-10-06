#!/bin/sh
# Checks that a PR is ready for the human's merge, on the exact head a worker reported.
#   pr-verify.sh <pr> --head <sha> [--repo <owner/name>]
# Prints exactly one line and exits 0:
#   PASS | PENDING <what> | MOVED <head> | MERGED <merge sha> | FAIL <what>
# PENDING means "ask again later" (checks running, mergeable not computed, gh unreachable).
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


p = argparse.ArgumentParser(prog="pr-verify.sh")
p.add_argument("pr")
p.add_argument("--head", required=True)
p.add_argument("--repo")
try:
    a = p.parse_args()
except SystemExit as e:
    sys.exit(64 if e.code not in (0, None) else 0)

cmd = ["gh", "pr", "view", a.pr, "--json",
       "state,isDraft,reviewDecision,reviews,commits,headRefOid,mergeable,statusCheckRollup,mergeCommit"]
if a.repo:
    cmd += ["-R", a.repo]
try:
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=float(os.environ.get("STAR_GH_TIMEOUT", "60")))
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

if d.get("state") == "MERGED":
    out("MERGED " + ((d.get("mergeCommit") or {}).get("oid") or "unknown"))
if d.get("state") == "CLOSED":
    out("FAIL closed")
head = d.get("headRefOid") or ""
if not (head.startswith(a.head) or a.head.startswith(head)) or len(a.head) < 7:
    out("MOVED " + head)
if d.get("isDraft"):
    out("FAIL draft")

decision = d.get("reviewDecision") or None
if decision is None:
    commits = d.get("commits") or []
    last = commits[-1].get("committedDate") if commits else None
    latest = {}
    for r in sorted(d.get("reviews") or [], key=lambda r: r.get("submittedAt") or ""):
        if r.get("state") in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
            latest[(r.get("author") or {}).get("login") or "?"] = r
    blockers = sorted(who for who, r in latest.items() if r.get("state") == "CHANGES_REQUESTED")
    if blockers:
        out("FAIL approval: changes requested by " + ", ".join(blockers))
    if not any(r.get("state") == "APPROVED" and (last is None or (r.get("submittedAt") or "") >= last)
               for r in latest.values()):
        out("FAIL approval: none after the last commit")
elif decision != "APPROVED":
    out("FAIL approval: " + decision)

failed, waiting = [], []
for c in d.get("statusCheckRollup") or []:
    name = c.get("name") or c.get("context") or "check"
    if c.get("__typename") == "CheckRun" and (c.get("status") or "COMPLETED") != "COMPLETED":
        waiting.append(name)
        continue
    value = (c.get("conclusion") or c.get("state") or "").upper()
    if value in PASSING:
        continue
    (waiting if value in WAITING else failed).append(name)
if failed:
    out("FAIL checks: " + ", ".join(failed))
if d.get("mergeable") == "CONFLICTING":
    out("FAIL conflicts")
if waiting:
    out("PENDING checks: " + ", ".join(waiting))
if d.get("mergeable") != "MERGEABLE":
    out("PENDING mergeable")
out("PASS")
PY
