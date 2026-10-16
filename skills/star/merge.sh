#!/bin/sh
# STAR's merge, the only place a PR is merged: under the owner's go, on the exact head.
#   merge.sh <pr url> --head <sha> --grant <file> [--quiet-hours <window>] [--home <dir> --item <item>] [--dry-run]
# Prints one line and exits 0:
#   MERGED <merge commit sha>
#   HELD quiet hours         inside the window, or a window quiet-hours.sh cannot judge
#   DRY-RUN <method> <sha>   with --dry-run: everything checked, nothing posted or merged
#   FAIL <what>              live worker <dispatch>, ledger: …, grant: …, merge methods: …,
#                            comment: …, head moved, or merge: …
# With --home and --item (STAR passes both), before anything else it reads the item's ledger row
# (#80). A row in a worker stage (briefing, building, babysitting, posting) is
# "FAIL live worker <dispatch>": its worker may still push to the PR. The dispatch cell alone
# decides nothing, since a verifying row still names its last babysit dispatch. An item with no
# row is "FAIL ledger: <why>".
# The grant file has a frontmatter block with date:, then the owner's words. The method is the
# first of squash, merge and rebase the repository allows. Before merging it posts, once per head,
# "Merging head <sha> under your go of <date>: "<words>"" (the words on one line, cut at 500
# characters, sent with --body-file), then runs gh pr merge --<method> --match-head-commit <sha>,
# so GitHub itself refuses when the head moved.
# The optional ownerApproval sentence is added only when no hosted reviewer exists, the owner grant
# matches the author's login without case, the rule is none or required 0, and no latest head approval
# by another writer remains. Anything unreadable leaves the sentence off and the merge goes ahead.
# After the merge call, whatever it said, it reads the PR's state once. MERGED when GitHub says
# merged, even if the call errored (gh can fail after the merge went through). A call that errored
# on a PR that is not merged is the FAIL it names. A call that worked, followed by a state that
# cannot be read, prints nothing and exits 69: the merge may or may not have happened, and the
# next run of the merge gate says which.
# Exit 64 on bad usage: a head that is not 40 hex characters, a URL that is not a PR, or missing
# arguments.
# When GH_TOKEN is unset, gh runs with the token of the account star.json configures (gh-token.sh, #137).
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
WORKER_STATES = ("briefing", "building", "babysitting", "posting")  # step-check.sh's STATES


def out(line):
    print(line)
    sys.exit(0)


def die(msg):
    print(f"merge.sh: {msg}", file=sys.stderr)
    sys.exit(64)


def unknown(msg):
    """No line on stdout: the merge may or may not have happened."""
    print(f"merge.sh: {msg}", file=sys.stderr)
    sys.exit(69)


def run(cmd, timeout=120):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 1, "", f"{cmd[0]}: {e}")


def use_star_token(home):
    """GH_TOKEN for the account star.json configures (#137), when this process has none."""
    if os.environ.get("GH_TOKEN"):
        return
    cmd = ["sh", os.path.join(os.environ["JUEL_SKILLS_DIR"], "star", "gh-token.sh")]
    if home:
        cmd += ["--home", home]
    try:
        proc = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=40)
        if proc.returncode == 0:
            token = proc.stdout.strip()
            if token and "\n" not in token and "\r" not in token:
                os.environ["GH_TOKEN"] = token
    except (OSError, subprocess.TimeoutExpired):
        pass


def first(proc):
    return ((proc.stderr or proc.stdout or "").strip().splitlines() or ["failed"])[0][:160]


def as_json(proc):
    try:
        value = json.loads(proc.stdout) if proc.returncode == 0 else None
    except ValueError:
        value = None
    return value if isinstance(value, dict) else None


def live_worker(home, item):
    """The row's dispatch while the row is in a worker stage, whose worker may still push (#80), else None."""
    r = run(["sh", os.path.join(os.environ["JUEL_SKILLS_DIR"], "star", "ledger.sh"), "--home", home, "get", item], 30)
    if r.returncode != 0:
        out("FAIL ledger: " + first(r))
    row = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
    return (row.get("dispatch") or "-") if row.get("state") in WORKER_STATES else None


args, pr, head, grant, window, dry, home, item = sys.argv[1:], None, None, None, None, False, None, None
while args:
    arg = args.pop(0)
    if arg in ("--head", "--grant", "--quiet-hours", "--home", "--item"):
        if not args:
            die(f"{arg} needs a value")
        value = args.pop(0)
        if arg == "--head":
            head = value.strip().lower()
        elif arg == "--grant":
            grant = value
        elif arg == "--home":
            home = value
        elif arg == "--item":
            item = value
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
    die("usage: merge.sh <pr url> --head <sha> --grant <file> [--quiet-hours <window>] [--home <dir> --item <item>] [--dry-run]")
if (home is None) != (item is None):
    die("--home and --item go together")
if not re.fullmatch(r"[0-9a-f]{40}", head):
    die("--head takes the full 40-character commit")
url = re.match(r"https?://[^/]+/([^/]+/[^/]+)/pull/\d+", pr)
if not url:
    die("the PR must be a pull request URL")
if home:
    live = live_worker(home, item)
    if live:
        out(f"FAIL live worker {live}")
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
use_star_token(home)
r = run(["gh", "repo", "view", url.group(1), "--json", ",".join(k for k, _ in METHODS)], 60)
allowed = as_json(r)
if allowed is None:
    out("FAIL merge methods: " + (first(r) if r.returncode else "unreadable output"))
method = next((name for key, name in METHODS if allowed.get(key) is True), None)
if not method:
    out("FAIL merge methods: the repository allows no merge method")
if dry:
    out(f"DRY-RUN {method} {head}")
v = run(["gh", "pr", "view", pr, "--json", "author,comments,reviews,baseRefName"], 60)
d = as_json(v)
if d is None:
    out("FAIL comment: " + (first(v) if v.returncode else "unreadable output"))
def bare(login):
    return login[:-5] if isinstance(login, str) and login.endswith("[bot]") else (login if isinstance(login, str) else "")


def owner_self_approval(data):
    if not home or not isinstance(data, dict):
        return False
    try:
        star = json.load(open(os.path.join(home, "star.json"), encoding="utf-8"))
        grant = star.get("ownerApproval") if isinstance(star, dict) else None
        if not isinstance(grant, dict) or bare(grant.get("login")).lower() != bare(author).lower() or not bare(author):
            return False
        if star.get("hostedReviewer") not in (None,):
            return False
        repo = url.group(1)
        base = data.get("baseRefName") if isinstance(data.get("baseRefName"), str) else ""
        script = os.path.join(os.environ["JUEL_SKILLS_DIR"], "babysit-pr", "review-rule.sh")
        rr = run(["sh", script, repo, base], 125)
        rule = (rr.stdout or "").splitlines()[0].strip() if rr.returncode == 0 and (rr.stdout or "").splitlines() else ""
        if rule not in ("none", "required 0"):
            return False
        latest = {}
        for index, review in enumerate(data.get("reviews") or []):
            login = bare((review.get("author") or {}).get("login"))
            if not login or review.get("state") not in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
                continue
            key = login.lower()
            prior = latest.get(key)
            stamp = str(review.get("submittedAt") or "")
            if prior is None or (stamp, index) >= prior[0]:
                latest[key] = ((stamp, index), review)
        for login, (_, review) in latest.items():
            if (review.get("state") == "APPROVED" and str((review.get("commit") or {}).get("oid") or "").lower() == head
                    and login != bare(author).lower()
                    and str(review.get("authorAssociation") or "").upper() in {"OWNER", "MEMBER", "COLLABORATOR"}):
                return False
        return True
    except (OSError, ValueError, TypeError, AttributeError, IndexError):
        return False


author = (d.get("author") or {}).get("login") or ""
prefix = f"Merging head {head} under your go"
if not any(isinstance(c, dict) and (c.get("author") or {}).get("login") == author
           and str(c.get("body") or "").startswith(prefix) for c in d.get("comments") or []):
    suffix = " Self-approved under the owner's grant: this repository has no second reviewer." if owner_self_approval(d) else ""
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
        f.write(f'{prefix} of {date.group(1)}: "{words}"{suffix}\n')
        body = f.name
    try:
        c = run(["gh", "pr", "comment", pr, "--body-file", body], 60)
    finally:
        os.unlink(body)
    if c.returncode != 0:
        out("FAIL comment: " + first(c))
mg = run(["gh", "pr", "merge", pr, f"--{method}", "--match-head-commit", head], 300)
# One read of the PR after the call, whatever the call said: gh can fail after GitHub has merged.
s = as_json(run(["gh", "pr", "view", pr, "--json", "state,mergeCommit"], 60)) or {}
state = str(s.get("state") or "").upper()
if state == "MERGED":
    out("MERGED " + ((s.get("mergeCommit") or {}).get("oid") or "unknown"))
if mg.returncode != 0:
    if re.search(r"head (branch|commit|ref)|match-head-commit|was modified", (mg.stderr or "") + (mg.stdout or ""), re.I):
        out("FAIL head moved")
    out("FAIL merge: " + first(mg))
if not state:
    unknown("the merge call worked but GitHub does not say what became of the PR")
out(f"FAIL merge: GitHub says {state} after the merge call")
PY
