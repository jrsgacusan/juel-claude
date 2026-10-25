#!/bin/sh
# STAR's merge, the only place a PR is merged: on the exact head, once the merge gate has passed.
#   merge.sh <pr url> --head <sha> [--home <dir> --item <item>] [--hosted <login>] [--dry-run]
# Prints one line and exits 0:
#   MERGED <merge commit sha>
#   DRY-RUN <method> <sha>   with --dry-run: everything checked, nothing posted or merged
#   PENDING check <name> not reported
#                            GitHub refused the merge with an error that has "required status
#                            check" and "expected" in it (any case): a required check has not
#                            reported on the head, and the PR is not merged: nothing is wrong, ask
#                            again later (#167). <name> is the first double-quoted name in the
#                            error message (stderr, or the message field of the JSON body gh api
#                            prints), never a JSON key, else "required checks". It is printed even when the PR state
#                            cannot be read afterwards, since GitHub refused the merge
#   PENDING merge state: behind the base branch
#                            the merge was refused, the head is the one given and the PR is BEHIND
#                            a base that wants an up-to-date head: sync the base in, then ask again
#   FAIL <what>              live worker <dispatch>, ledger: …, merge methods: …, owner branch <base>,
#                            comment: … (before the merge only), settings: …, head moved,
#                            merge: conflicts with the base, or merge: …
# There is no grant: the merge gate (pr-verify.sh --merge-gate) is what lets STAR merge.
# The home is --home, else $JUEL_STAR_HOME, else star-home.sh path. From its star.json it reads
# mergeMethod and ownerBranches; a missing star.json means both are absent. A star.json that exists
# but cannot be parsed (or is not a JSON object) is "FAIL settings: <why>": nothing posted, nothing
# merged, exit 0.
# With --home and --item (STAR passes both), before anything else it reads the item's ledger row
# (#80). A row in a worker stage (briefing, building, babysitting, posting) is
# "FAIL live worker <dispatch>": its worker may still push to the PR. The dispatch cell alone
# decides nothing, since a verifying row still names its last babysit dispatch. An item with no
# row is "FAIL ledger: <why>".
# The method is mergeMethod when it is set: the repository must allow it, else
# "FAIL merge methods: <method> not allowed" (nothing posted, nothing merged). With mergeMethod
# null it is the first of squash, merge and rebase the repository allows. A PR whose base branch is
# in ownerBranches is "FAIL owner branch <base>", before any comment or merge.
# After the merge it posts, once per head, "Merging head <sha>: codex PASS, required checks green."
# (", <login> passed." in place of the full stop only when --hosted <login> is given, which STAR
# does exactly when it passed --hosted to the merge gate; star.json's hostedReviewer is not read
# here; sent with --body-file). It is skipped when the PR's author already has a comment starting
# "Merging head <sha>:", and a refused merge never leaves one (#193). A comment that fails after the
# merge prints MERGED all the same, with "merge.sh: comment failed: <why>" on stderr.
# The merge is gh pr merge --<method> --match-head-commit <sha>, so GitHub itself refuses when the
# head moved. One exception: a PR whose mergeStateStatus is BEHIND, on a base for which
# review-rule.sh (babysit-pr) prints none of strict, unknown and queue, is merged through
# gh api -X PUT repos/<repo>/pulls/<n>/merge -f sha=<head> -f merge_method=<method>, since gh pr
# merge refuses BEHIND before it asks GitHub. GitHub still refuses a moved head there (409).
# After the merge call, whatever it said, it reads the PR once (state, merge commit, head,
# merge state). MERGED when GitHub says merged, even if the call errored (gh can fail after the
# merge went through). A call that errored on a PR that is not merged is classified from that read:
# PENDING check <name> not reported (above); FAIL head moved only when the head read differs from
# --head (when the read failed, from the error text: "was modified", "HTTP 409" or
# "match-head-commit", never gh's "head branch is not up to date", the BEHIND refusal); on the REST
# path, a 422, 403 or 429 or any "rate limit" text is FAIL merge: <first line>, decided before the
# BEHIND rule, since a refusal that is not about the PR's state is never "behind"; PENDING merge state: behind the base branch
# when the state is BEHIND; FAIL merge: conflicts with the base when it is DIRTY or the error says
# so; else FAIL merge: <first line>. A call that worked, followed by a state that
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


args, pr, head, dry, home, item, hosted = sys.argv[1:], None, None, False, None, None, None
while args:
    arg = args.pop(0)
    if arg in ("--head", "--home", "--item", "--hosted"):
        if not args:
            die(f"{arg} needs a value")
        value = args.pop(0)
        if arg == "--head":
            head = value.strip().lower()
        elif arg == "--home":
            home = value
        elif arg == "--hosted":
            hosted = value.strip() or None
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
    die("usage: merge.sh <pr url> --head <sha> [--home <dir> --item <item>] [--hosted <login>] [--dry-run]")
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
    """mergeMethod and ownerBranches from the home's star.json; absent when there is no star.json,
    "FAIL settings" when there is one that cannot be parsed."""
    cfg = home or os.environ.get("JUEL_STAR_HOME")
    if not cfg:
        script = os.path.join(os.environ["JUEL_SKILLS_DIR"], "star", "star-home.sh")
        try:
            proc = subprocess.run(["sh", script, "path"], capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
            cfg = (proc.stdout or "").splitlines()[0].strip() if proc.returncode == 0 else ""
        except (OSError, subprocess.TimeoutExpired, IndexError):
            cfg = ""
    path = os.path.join(cfg, "star.json") if cfg else ""
    data = {}
    if path and os.path.exists(path):
        try:
            data = json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError) as e:
            out("FAIL settings: " + (str(e).splitlines() or ["unreadable"])[0][:120])
        if not isinstance(data, dict):
            out("FAIL settings: star.json is not a JSON object")
    method = data.get("mergeMethod") if isinstance(data.get("mergeMethod"), str) and data.get("mergeMethod") else None
    owners = [b for b in data.get("ownerBranches") or [] if isinstance(b, str)] if isinstance(data.get("ownerBranches"), list) else []
    return method, owners


want, owner_branches = star_config()
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
number = re.search(r"/pull/(\d+)", pr).group(1)


def post_comment():
    """The merge comment, once per head, after the merge: a refused merge never leaves one (#193).
    A failure here is a note on stderr, since the PR is already merged."""
    if any(isinstance(c, dict) and (c.get("author") or {}).get("login") == author
           and str(c.get("body") or "").startswith(prefix) for c in d.get("comments") or []):
        return
    text = f"{prefix} codex PASS, required checks green" + (f", {hosted} passed." if hosted else ".")
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
        f.write(text + "\n")
        body = f.name
    try:
        c = run(["gh", "pr", "comment", pr, "--body-file", body], 60)
    finally:
        os.unlink(body)
    if c.returncode != 0:
        print("merge.sh: comment failed: " + first(c), file=sys.stderr)


def rest_merge_allowed():
    """True for a BEHIND PR on a base whose rules do not ask for an up-to-date head: gh pr merge
    refuses BEHIND before it asks GitHub, the REST merge does not (#193)."""
    pre = as_json(run(["gh", "pr", "view", pr, "--json", "headRefOid,mergeStateStatus"], 60)) or {}
    if str(pre.get("mergeStateStatus") or "").upper() != "BEHIND":
        return False
    rule = run(["sh", os.path.join(os.environ["JUEL_SKILLS_DIR"], "babysit-pr", "review-rule.sh"), url.group(1), base], 120)
    words = {l.split()[0] for l in (rule.stdout or "").splitlines() if l.split()}
    return rule.returncode == 0 and not words & {"strict", "queue", "unknown"}


def error_text(proc):
    """What the call said: stderr, plus the message field of the JSON body gh api prints on stdout
    (its other keys are not text), else stdout as it is."""
    out_text = proc.stdout or ""
    try:
        body = json.loads(out_text)
    except ValueError:
        body = None
    if isinstance(body, dict):
        out_text = body["message"] if isinstance(body.get("message"), str) else ""
    return (proc.stderr or "") + out_text


via_rest = rest_merge_allowed()
if via_rest:
    mg = run(["gh", "api", "-X", "PUT", f"repos/{url.group(1)}/pulls/{number}/merge", "-f", f"sha={head}", "-f", f"merge_method={method}"], 300)
else:
    mg = run(["gh", "pr", "merge", pr, f"--{method}", "--match-head-commit", head], 300)
# One read of the PR after the call, whatever the call said: gh can fail after GitHub has merged.
s = as_json(run(["gh", "pr", "view", pr, "--json", "state,mergeCommit,headRefOid,mergeStateStatus"], 60)) or {}
state = str(s.get("state") or "").upper()
if state == "MERGED":
    post_comment()
    out("MERGED " + ((s.get("mergeCommit") or {}).get("oid") or "unknown"))
if mg.returncode != 0:
    said = error_text(mg)
    if re.search(r"required status check", said, re.I) and re.search(r"expected", said, re.I):
        quoted = re.search(r'"([^"]+)"', said)
        out(f"PENDING check {quoted.group(1) if quoted else 'required checks'} not reported")
    now_head = str(s.get("headRefOid") or "").lower()
    merge_state = str(s.get("mergeStateStatus") or "").upper()
    if now_head:
        # The PR was read again: only a different head is a moved head.
        if now_head != head:
            out("FAIL head moved")
    elif re.search(r"match-head-commit|was modified|HTTP 409", said, re.I):
        out("FAIL head moved")
    if via_rest and re.search(r"HTTP (422|403|429)|rate limit", said, re.I):
        out("FAIL merge: " + first(mg))
    if merge_state == "BEHIND":
        out("PENDING merge state: behind the base branch")
    if merge_state == "DIRTY" or re.search(r"merge conflict|conflicts? with", said, re.I):
        out("FAIL merge: conflicts with the base")
    out("FAIL merge: " + first(mg))
if not state:
    unknown("the merge call worked but GitHub does not say what became of the PR")
out(f"FAIL merge: GitHub says {state} after the merge call")
PY
