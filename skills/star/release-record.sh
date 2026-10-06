#!/bin/sh
# Writes the record for one merged PR into a STAR home and prints the record's path.
#   release-record.sh --home <dir> --project <p> --item <i> --pr <n-or-url> [--repo <owner/name>]
# Exit 1 with "error: ..." when the PR is not merged or gh fails; 64 on bad usage, which
# includes a project or item that is not a plain name (a slash, "..", a control character).
# One record per PR: asked again for the same PR it prints the existing record's path, so a
# replayed "merged" message is harmless. Another PR for the same item gets -v2, -v3; nothing
# is ever overwritten.
exec python3 - "$@" <<'PY'
import argparse
import fcntl
import glob
import json
import os
import re
import subprocess
import sys


def err(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


p = argparse.ArgumentParser(prog="release-record.sh")
for flag in ("--home", "--project", "--item", "--pr"):
    p.add_argument(flag, required=True)
p.add_argument("--repo")
try:
    a = p.parse_args()
except SystemExit as e:
    sys.exit(64 if e.code not in (0, None) else 0)

for flag, value in (("--project", a.project), ("--item", a.item)):
    if not value.strip() or re.search(r"[\x00-\x1f\x7f/\\]", value) or value.startswith(".") or ".." in value:
        print(f"release-record.sh: {flag} must be a plain name (got {value!r})", file=sys.stderr)
        sys.exit(64)

cmd = ["gh", "pr", "view", a.pr, "--json",
       "number,title,url,state,mergeCommit,mergedAt,mergedBy,reviews,statusCheckRollup,baseRefName,headRefName"]
if a.repo:
    cmd += ["-R", a.repo]
try:
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
except (FileNotFoundError, subprocess.TimeoutExpired) as e:
    err(f"gh: {type(e).__name__}")
if proc.returncode != 0:
    err("gh: " + ((proc.stderr or "").strip().splitlines() or ["failed"])[0])
try:
    d = json.loads(proc.stdout)
except ValueError:
    err("gh: unreadable output")
if not isinstance(d, dict):
    err("gh: unreadable output")
for key in ("reviews", "statusCheckRollup"):
    value = d.get(key) or []
    if not isinstance(value, list) or not all(isinstance(e, dict) for e in value):
        err("gh: unreadable output")
if d.get("state") != "MERGED":
    err(f"PR is {d.get('state')}, not merged")

rounds, worktree = "-", "-"
ledger = os.path.join(a.home, "ledger.md")
if os.path.exists(ledger):
    header = None
    for line in open(ledger, encoding="utf-8", errors="replace"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if header is None and "item" in cells and "project" in cells:
            header = cells
        elif header and len(cells) == len(header):
            row = dict(zip(header, cells))
            if row.get("item") == a.item and row.get("project") == a.project:
                rounds = row.get("round") or "-"
                worktree = row.get("worktree") or "-"

approvers = sorted({(r.get("author") or {}).get("login") for r in d.get("reviews") or []
                    if r.get("state") == "APPROVED" and (r.get("author") or {}).get("login")})
bad = []
for c in d.get("statusCheckRollup") or []:
    value = (c.get("conclusion") or c.get("state") or "").upper()
    if value not in ("SUCCESS", "NEUTRAL", "SKIPPED"):
        bad.append(f"{c.get('name') or c.get('context') or 'check'}: {value or 'pending'}")
reviews = sorted(os.path.relpath(f, a.home) for f in glob.glob(os.path.join(a.home, "reviews", a.project, glob.escape(a.item) + "-r*.md")))
follow = []
loops = os.path.join(a.home, "open-loops.md")
if os.path.exists(loops):
    text = open(loops, encoding="utf-8", errors="replace").read().split("\n")
    for k, line in enumerate(text):
        m = re.match(r"^### (N-\d+) · (.*?) · (.*?) · (.*)$", line)
        # the item's own "merge PR" entry is what this record closes, not a follow-up
        own = k + 1 < len(text) and text[k + 1].strip() == "kind: merge-pr"
        if m and m.group(2) == a.project and m.group(3) == a.item and not own:
            follow.append(f"{m.group(1)}: {m.group(4)}")

date = (d.get("mergedAt") or "")[:10] or "undated"
slug = re.sub(r"[^a-z0-9]+", "-", a.item.lower()).strip("-") or "item"
os.makedirs(os.path.join(a.home, "releases"), exist_ok=True)
base = os.path.join(a.home, "releases", f"{date}-{a.project}-{slug}")
pr_line = f"- PR: {d.get('url')} (#{d.get('number')}), "
lock = open(os.path.join(a.home, "releases.lock"), "w")
fcntl.flock(lock, fcntl.LOCK_EX)
path, n = base + ".md", 1
while os.path.exists(path):
    if any(l.startswith(pr_line) for l in open(path, encoding="utf-8", errors="replace")):
        print(path)  # this PR already has its record
        sys.exit(0)
    n += 1
    path = f"{base}-v{n}.md"

brief = os.path.join("briefs", a.project, a.item + ".md")
body = [
    f"# {a.project} · {a.item} · {d.get('title') or ''}",
    "",
    f"{pr_line}{d.get('headRefName')} → {d.get('baseRefName')}",
    f"- Merged: {d.get('mergedAt')} by {(d.get('mergedBy') or {}).get('login') or 'unknown'}, merge commit {(d.get('mergeCommit') or {}).get('oid') or 'unknown'}",
    f"- Approved by: {', '.join(approvers) if approvers else 'nobody on record'}",
    f"- Checks on the PR head at merge: {'all passed' if not bad else '; '.join(bad)}",
    f"- Second-model review rounds: {rounds}",
    f"- Brief: {brief if os.path.exists(os.path.join(a.home, brief)) else 'none on file'}",
    "- Reviews: " + (", ".join(reviews) if reviews else "none on file"),
    f"- Worktree: {worktree} (verification evidence is under its docs root)",
    "- Open follow-ups: " + ("; ".join(follow) if follow else "none"),
    "",
]
with open(path, "x", encoding="utf-8") as f:
    f.write("\n".join(body))
print(path)
PY
