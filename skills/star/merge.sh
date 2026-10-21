#!/bin/sh
# STAR's merge, the only place a PR is merged: on the exact head, once the merge gate has passed.
#   merge.sh <pr url> --head <sha> [--home <dir> --item <item>] [--dry-run]
# Prints one line and exits 0:
#   MERGED <merge commit sha>
#   DRY-RUN <method> <sha>   with --dry-run: everything checked, nothing posted or merged
#   PENDING check <name> not reported
#                            GitHub refused the merge with an error that has "required status
#                            check" and "expected" in it (any case): a required check has not
#                            reported on the head, and the PR is not merged: nothing is wrong, ask
#                            again later (#167). <name> is the first double-quoted name in the
#                            error, else "required checks". It is printed even when the PR state
#                            cannot be read afterwards, since GitHub refused the merge
#   FAIL <what>              live worker <dispatch>, ledger: …, merge methods: …, owner branch <base>,
#                            comment: …, head moved, or merge: …
# There is no grant: the merge gate (pr-verify.sh --merge-gate) is what lets STAR merge.
# The home is --home, else $JUEL_STAR_HOME, else star-home.sh path. From its star.json it reads
# mergeMethod, ownerBranches and hostedReviewer; a missing or unreadable star.json means all three
# are absent.
# With --home and --item (STAR passes both), before anything else it reads the item's ledger row
# (#80). A row in a worker stage (briefing, building, babysitting, posting) is
# "FAIL live worker <dispatch>": its worker may still push to the PR. The dispatch cell alone
# decides nothing, since a verifying row still names its last babysit dispatch. An item with no
# row is "FAIL ledger: <why>".
# The method is mergeMethod when it is set: the repository must allow it, else
# "FAIL merge methods: <method> not allowed" (nothing posted, nothing merged). With mergeMethod
# null it is the first of squash, merge and rebase the repository allows. A PR whose base branch is
# in ownerBranches is "FAIL owner branch <base>", before any comment or merge.
# Before merging it posts, once per head, "Merging head <sha>: codex PASS, required checks green."
# (", <hostedReviewer.login> passed." in place of the full stop when a hosted reviewer is set and
# not paused; sent with --body-file), then runs gh pr merge --<method> --match-head-commit <sha>,
# so GitHub itself refuses when the head moved. The comment is skipped when the PR's author
# already has one starting "Merging head <sha>:".
# After the merge call, whatever it said, it reads the PR's state once. MERGED when GitHub says
# merged, even if the call errored (gh can fail after the merge went through). A call that errored
# on a PR that is not merged is the FAIL it names, or PENDING when GitHub waits for a required check, state read or not. A call that worked, followed by a state that
# cannot be read, prints nothing and exits 69: the merge may or may not have happened, and the
# next run of the merge gate says which.
# Exit 64 on bad usage: a head that is not 40 hex characters, a URL that is not a PR, an unknown
# argument (a grant file is no longer one), or missing arguments.
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
WORKER_STATES = ("briefing", "building", "babysitting", "posting")  # worker-probe.sh's worker stages


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


args, pr, head, dry, home, item = sys.argv[1:], None, None, False, None, None
while args:
    arg = args.pop(0)
    if arg in ("--head", "--home", "--item"):
        if not args:
            die(f"{arg} needs a value")
        value = args.pop(0)
        if arg == "--head":
            head = value.strip().lower()
        elif arg == "--home":
            home = value
        else:
            item = value
    elif arg == "--dry-run":
        dry = True
    elif arg.startswith("-"):
        die(f"unknown argument: {arg}")
    elif pr is None:
        pr = arg
    else:
        die(f"unexpected argument: {arg}")
if not pr or not head:
    die("usage: merge.sh <pr url> --head <sha> [--home <dir> --item <item>] [--dry-run]")
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
use_star_token(home)


def star_config():
    """mergeMethod, ownerBranches and hostedReviewer from the home's star.json; absent when it cannot be read."""
    cfg = home or os.environ.get("JUEL_STAR_HOME")
    if not cfg:
        script = os.path.join(os.environ["JUEL_SKILLS_DIR"], "star", "star-home.sh")
        try:
            proc = subprocess.run(["sh", script, "path"], capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
            cfg = (proc.stdout or "").splitlines()[0].strip() if proc.returncode == 0 else ""
        except (OSError, subprocess.TimeoutExpired, IndexError):
            cfg = ""
    try:
        data = json.load(open(os.path.join(cfg, "star.json"), encoding="utf-8")) if cfg else {}
    except (OSError, ValueError):
        data = {}
    data = data if isinstance(data, dict) else {}
    method = data.get("mergeMethod") if isinstance(data.get("mergeMethod"), str) and data.get("mergeMethod") else None
    owners = [b for b in data.get("ownerBranches") or [] if isinstance(b, str)] if isinstance(data.get("ownerBranches"), list) else []
    hosted = data.get("hostedReviewer") if isinstance(data.get("hostedReviewer"), dict) else None
    return method, owners, hosted


want, owner_branches, hosted = star_config()
r = run(["gh", "repo", "view", url.group(1), "--json", ",".join(k for k, _ in METHODS)], 60)
allowed = as_json(r)
if allowed is None:
    out("FAIL merge methods: " + (first(r) if r.returncode else "unreadable output"))
if want:
    if allowed.get(dict((n, k) for k, n in METHODS).get(want, "")) is not True:
        out(f"FAIL merge methods: {want} not allowed")
    method = want
else:
    method = next((name for key, name in METHODS if allowed.get(key) is True), None)
    if not method:
        out("FAIL merge methods: the repository allows no merge method")
v = run(["gh", "pr", "view", pr, "--json", "author,comments,baseRefName"], 60)
d = as_json(v)
if d is None:
    out("FAIL comment: " + (first(v) if v.returncode else "unreadable output"))
base = d.get("baseRefName") if isinstance(d.get("baseRefName"), str) else ""
if base and base in owner_branches:
    out(f"FAIL owner branch {base}")
if dry:
    out(f"DRY-RUN {method} {head}")
author = (d.get("author") or {}).get("login") or ""
prefix = f"Merging head {head}:"
if not any(isinstance(c, dict) and (c.get("author") or {}).get("login") == author
           and str(c.get("body") or "").startswith(prefix) for c in d.get("comments") or []):
    reviewer = hosted.get("login") if hosted and not hosted.get("paused") and isinstance(hosted.get("login"), str) and hosted.get("login") else None
    text = f"{prefix} codex PASS, required checks green" + (f", {reviewer} passed." if reviewer else ".")
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
        f.write(text + "\n")
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
    said = (mg.stderr or "") + (mg.stdout or "")
    if re.search(r"required status check", said, re.I) and re.search(r"expected", said, re.I):
        quoted = re.search(r'"([^"]+)"', said)
        out(f"PENDING check {quoted.group(1) if quoted else 'required checks'} not reported")
    if re.search(r"head (branch|commit|ref)|match-head-commit|was modified", (mg.stderr or "") + (mg.stdout or ""), re.I):
        out("FAIL head moved")
    out("FAIL merge: " + first(mg))
if not state:
    unknown("the merge call worked but GitHub does not say what became of the PR")
out(f"FAIL merge: GitHub says {state} after the merge call")
PY
