#!/bin/sh
# STAR's merge, the only place a PR is merged: under the owner's go, on the exact head.
#   merge.sh <pr url> --head <sha> --grant <file> [--quiet-hours <window>] [--dry-run]
# Prints one line and exits 0:
#   MERGED <merge commit sha>
#   HELD quiet hours         inside the window, or a window quiet-hours.sh cannot judge
#   DRY-RUN <method> <sha>   with --dry-run: everything checked, nothing posted or merged
#   FAIL <what>              grant: …, merge methods: …, comment: …, head moved, or merge: …
# The grant file has a frontmatter block with date:, then the owner's words. The method is the
# first of squash, merge and rebase the repository allows. Before merging it posts, once per head,
# "Merging head <sha> under your go of <date>: "<words>"" (the words on one line, cut at 500
# characters, sent with --body-file), then runs gh pr merge --<method> --match-head-commit <sha>,
# so GitHub itself refuses when the head moved.
# Exit 64 on bad usage.
JUEL_SKILLS_DIR=$(cd "$(dirname "$0")/.." && pwd)
export JUEL_SKILLS_DIR
exec python3 - "$@" <<'PY'
import json
import os
import re
import subprocess
import sys
import tempfile

METHODS = (("squashMergeAllowed", "squash"), ("mergeCommitAllowed", "merge"), ("rebaseMergeAllowed", "rebase"))


def out(line):
    print(line)
    sys.exit(0)


def die(msg):
    print(f"merge.sh: {msg}", file=sys.stderr)
    sys.exit(64)


def run(cmd, timeout=120):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 1, "", f"{cmd[0]}: {e}")


def first(proc):
    return ((proc.stderr or proc.stdout or "").strip().splitlines() or ["failed"])[0][:160]


def as_json(proc):
    try:
        value = json.loads(proc.stdout) if proc.returncode == 0 else None
    except ValueError:
        value = None
    return value if isinstance(value, dict) else None


args, pr, head, grant, window, dry = sys.argv[1:], None, None, None, None, False
while args:
    arg = args.pop(0)
    if arg in ("--head", "--grant", "--quiet-hours"):
        if not args:
            die(f"{arg} needs a value")
        value = args.pop(0)
        if arg == "--head":
            head = value.strip().lower()
        elif arg == "--grant":
            grant = value
        else:
            window = value
    elif arg == "--dry-run":
        dry = True
    elif arg.startswith("-"):
        die(f"unknown argument: {arg}")
    elif pr is None:
        pr = arg
    else:
        die(f"unexpected argument: {arg}")
if not pr or not head or not grant:
    die("usage: merge.sh <pr url> --head <sha> --grant <file> [--quiet-hours <window>] [--dry-run]")
if not re.fullmatch(r"[0-9a-f]{40}", head):
    die("--head takes the full 40-character commit")
url = re.match(r"https?://[^/]+/([^/]+/[^/]+)/pull/\d+", pr)
if not url:
    die("the PR must be a pull request URL")
if window:
    q = run(["sh", os.path.join(os.environ["JUEL_SKILLS_DIR"], "ship-ticket", "quiet-hours.sh"), window], 30)
    if q.returncode != 0 or q.stdout.strip() != "outside":
        out("HELD quiet hours")
try:
    text = open(grant, encoding="utf-8").read()
except OSError as e:
    out(f"FAIL grant: {e.strerror}: {grant}")
fm = re.match(r"﻿?---\r?\n(.*?)\r?\n---\r?\n?(.*)", text, re.S)
date = re.search(r"^date:\s*(\S.*?)\s*$", fm.group(1), re.M) if fm else None
words = " ".join((fm.group(2) if fm else "").split())
if not date or not words:
    out(f"FAIL grant: no date or no words in {grant}")
words = words if len(words) <= 500 else words[:497] + "..."
r = run(["gh", "repo", "view", url.group(1), "--json", ",".join(k for k, _ in METHODS)], 60)
allowed = as_json(r)
if allowed is None:
    out("FAIL merge methods: " + (first(r) if r.returncode else "unreadable output"))
method = next((name for key, name in METHODS if allowed.get(key) is True), None)
if not method:
    out("FAIL merge methods: the repository allows no merge method")
if dry:
    out(f"DRY-RUN {method} {head}")
v = run(["gh", "pr", "view", pr, "--json", "author,comments"], 60)
d = as_json(v)
if d is None:
    out("FAIL comment: " + (first(v) if v.returncode else "unreadable output"))
author = (d.get("author") or {}).get("login") or ""
prefix = f"Merging head {head} under your go"
if not any(isinstance(c, dict) and (c.get("author") or {}).get("login") == author
           and str(c.get("body") or "").startswith(prefix) for c in d.get("comments") or []):
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
        f.write(f'{prefix} of {date.group(1)}: "{words}"\n')
        body = f.name
    try:
        c = run(["gh", "pr", "comment", pr, "--body-file", body], 60)
    finally:
        os.unlink(body)
    if c.returncode != 0:
        out("FAIL comment: " + first(c))
mg = run(["gh", "pr", "merge", pr, f"--{method}", "--match-head-commit", head], 300)
if mg.returncode != 0:
    if re.search(r"head (branch|commit|ref)|match-head-commit|was modified", (mg.stderr or "") + (mg.stdout or ""), re.I):
        out("FAIL head moved")
    out("FAIL merge: " + first(mg))
s = as_json(run(["gh", "pr", "view", pr, "--json", "state,mergeCommit"], 60)) or {}
if str(s.get("state") or "").upper() == "MERGED":
    out("MERGED " + ((s.get("mergeCommit") or {}).get("oid") or "unknown"))
out(f"FAIL merge: GitHub says {s.get('state') or 'unknown'} after the merge call")
PY
