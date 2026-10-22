#!/bin/sh
# Checks a PR on the exact head a worker reported: for the human's merge, or, with --merge-gate,
# for STAR's own merge.
#   pr-verify.sh <pr> --head <sha> [--repo <owner/name>] [--merge-gate [--hosted [<login>]]
#                [--home <dir>] [--brief <path>]]
# Prints exactly one line and exits 0 (64, with nothing on stdout, only for bad usage):
#   PASS [<note>] | PENDING <what> | MOVED <head> | MERGED <merge sha> | FAIL <what>
# "PASS approval is on an earlier commit" is still a pass: the repo's review rule is satisfied,
# but the approval was given before the newest commits; the note is for the person who merges.
# Green means every check that reported is green AND GitHub's merge state is not BLOCKED, and not
# BEHIND when the base requires up-to-date branches (a strict rule, or one that cannot be read),
# so a required check that has not started yet is PENDING, not a pass.
# PENDING means "ask again later" (checks running, mergeable not computed, gh unreachable or
# its output unreadable). GitHub can show a PR's previous head for a few seconds after a push: when
# the PR's head is not --head but its branch's tip (gh api .../git/ref/heads/<branch>) already is,
# the PR is read again every 5 seconds for up to 90 (times PR_VERIFY_SLEEP), and a lag that
# outlasts that is "PENDING head: the PR still shows <old> while its branch is at <tip>", never
# MOVED (#62). Where the repo has no review rule (empty reviewDecision), an approval
# counts only when it was given on the current head commit: dates are not compared, because a
# commit made earlier and pushed later carries an older date than the approval. Where the base
# branch's rules explicitly require 0 approving reviews (review-rule.sh prints "required 0"), no
# approval is needed: "PASS no approval required" (changes requested still fail). An unreadable
# rule with no approval on the head is PENDING ("PENDING review rule: <why>"), never a pass.
# Where the repo has a review rule, GitHub's own reviewDecision is trusted as it stands (it
# follows the repo's "dismiss stale approvals" setting). gh signed in to an account that cannot
# see the repository prints "PENDING gh cannot see <repo>: export GH_TOKEN for this repository".
# --home <dir> selects the STAR folder whose star.json supplies the gh token account; it is valid only with
# --merge-gate (otherwise 64; an empty value is 64), defaults to $JUEL_STAR_HOME, then star-home.sh path.
# --merge-gate is STAR's merge gate. A receipt by another login is named when the author has no
# receipt (#137). It also needs: a comment by the PR's author that starts
# "Codex gate: PASS (head <the PR's head>"; a reply from the PR's author on every unresolved
# review thread someone else opened (a hosted reviewer's included); and either an APPROVED review
# on the head by someone other than the PR's author whose authorAssociation is OWNER, MEMBER or
# COLLABORATOR (write access) ("PASS approved", "PASS hosted" with --hosted), or a base branch whose
# review rule asks for no approval (review-rule.sh prints none or required 0): "PASS no approval
# required" ("PASS hosted" with --hosted). Any rule that requires approvals and no such approval
# on the head is "PENDING approval: …", with or without --hosted (R-5). An unreadable rule is
# "PENDING review rule: <why>" or "PENDING gh cannot see …".
# --brief <path> (valid only with --merge-gate, otherwise 64) is the item's brief. A check that
# failed and that the base branch's rules do not require passes only on a proof line in the
# brief's "## Decisions" section:
#   - <date> red-check-proof check=<name> head=<40-hex sha> cause=base|infra base=<40-hex sha> url=<url>
# (a <name> with a space or = is in double quotes: check="test (ubuntu-latest)") for that check on
# this exact head, which the script confirms itself with gh: cause=base needs base= to equal the
# PR's current base head (baseRefOid; a base that moved needs a fresh line) and a run of that name
# on base= that concluded failure; cause=infra needs the head's own run of that name to
# have concluded cancelled, startup_failure, timed_out or stale. A confirmed check is set aside and
# the PASS note ends " (proven not the PR's: <name> <cause>[, …])". A required check, a rule that
# cannot be read, or a proof that does not hold leaves the check failed: "FAIL checks: …". A brief
# that cannot be read is "PENDING brief: <why>".
# The review threads are never guessed: a gh call that exits non-zero, or an answer whose threads
# are not a list, is "PENDING gh: review threads unreadable", not "no findings".
# --merge-gate also prints "PENDING check <context> not reported on <head7>" when the base branch's
# review-rule.sh lists a required check the head has no entry for (#167); the hosted reviewer's
# "PENDING hosted-status ..." line comes first. Unreadable rules add no such line.
# --hosted says the project has a hosted reviewer (Greptile): its review text is never read here
# (the babysit worker judges it from guidelines and reports READY only on a head it judged clean),
# and it does not stand in for a required human approval (R-5). Logins are compared without a "[bot]" suffix.
# Its PASS notes are "hosted" and "approved". --hosted <login> (star.json's hostedReviewer.login)
# also finds the hosted reviewer's own status: a check the base branch's rules require whose
# name holds the first word of that login (greptile-apps[bot] -> greptile, any case). When the
# head has no entry of that name at all, no check failed or conflicts, and none is still running,
# the line is "PENDING hosted-status <check> missing on <head7>" (#59): the hosted reviewer does
# not run by itself on a new head, so STAR sends the row back to babysit to refresh it. Rules
# that cannot be read, and a bare --hosted, never print it.
# When GH_TOKEN is unset, gh runs with the token of the account star.json configures (gh-token.sh, #137).
JUEL_SKILLS_DIR=$(cd "$(dirname "$0")/.." && pwd)
export JUEL_SKILLS_DIR
exec python3 - "$@" <<'PY'
import argparse
import json
import os
import re
import subprocess
import sys
import time
from urllib.parse import quote

PASSING = {"SUCCESS", "NEUTRAL", "SKIPPED"}
WAITING = {"", "PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}
WRITERS = {"OWNER", "MEMBER", "COLLABORATOR"}  # an approval the merge gate counts: someone with write access
THREADS_QUERY = ("query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){"
                 "pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved "
                 "comments(first:50){nodes{author{login} body}}}}}}}")


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


def bare(login):
    login = login if isinstance(login, str) else ""
    return login[:-5] if login.endswith("[bot]") else login


p = argparse.ArgumentParser(prog="pr-verify.sh")
p.add_argument("pr")
p.add_argument("--head", required=True)
p.add_argument("--repo")
p.add_argument("--merge-gate", action="store_true")
p.add_argument("--home")
p.add_argument("--brief")
p.add_argument("--hosted", nargs="?", const=True, default=False)
try:
    a = p.parse_args()
except SystemExit as e:
    sys.exit(64 if e.code not in (0, None) else 0)
if a.hosted and not a.merge_gate:
    print("pr-verify.sh: --hosted needs --merge-gate", file=sys.stderr)
    sys.exit(64)
if a.brief is not None and not a.merge_gate:
    print("pr-verify.sh: --brief needs --merge-gate", file=sys.stderr)
    sys.exit(64)
if a.home is not None and not str(a.home).strip():
    print("pr-verify.sh: --home needs a folder", file=sys.stderr)
    sys.exit(64)
if a.home is not None and not a.merge_gate:
    print("pr-verify.sh: --home needs --merge-gate", file=sys.stderr)
    sys.exit(64)

try:
    LIMIT = float(os.environ.get("STAR_GH_TIMEOUT", "60"))
except ValueError:
    LIMIT = 60.0
try:
    PAUSE = float(os.environ.get("PR_VERIFY_SLEEP", "1"))
except ValueError:
    PAUSE = 1.0


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


def repo_of(url):
    parts = url.split("/") if isinstance(url, str) else []
    return "/".join(parts[3:5]) if len(parts) >= 5 and parts[0] in ("https:", "http:") else ""


RULE = {}


def rule_lines(d):
    """Every line review-rule.sh prints for this PR's base branch, read once; ["unknown"] when it cannot run."""
    if "lines" not in RULE:
        RULE["lines"] = ["unknown"]
        repo = a.repo or repo_of(d.get("url")) or repo_of(a.pr)
        base = d.get("baseRefName") if isinstance(d.get("baseRefName"), str) else ""
        script = os.path.join(os.environ.get("JUEL_SKILLS_DIR") or "", "babysit-pr", "review-rule.sh")
        if repo and base and os.path.isfile(script):
            try:
                proc = subprocess.run(["sh", script, repo, base], capture_output=True, text=True,
                                      timeout=2 * LIMIT + 5)
                RULE["lines"] = [l.strip() for l in (proc.stdout or "").splitlines() if l.strip()] or ["unknown"]
            except (OSError, subprocess.TimeoutExpired):
                pass
    return RULE["lines"]


def base_requires_up_to_date(d):
    """True when the base needs branches up to date (a strict rule), or when that cannot be read."""
    lines = rule_lines(d)
    return lines[:1] == ["unknown"] or "strict" in lines


def review_rule(d):
    """The first line review-rule.sh prints for this PR's base branch; "unknown" when it cannot run."""
    return rule_lines(d)[0]


def proofs_of(path):
    """The red-check-proof lines of the brief's ## Decisions section as dicts; raises OSError when unreadable."""
    text = open(path, encoding="utf-8").read()
    found, inside = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            inside = line[3:].strip().lower() == "decisions"
            continue
        m = re.match(r"\s*-\s+\S+\s+red-check-proof\s+(.*)$", line) if inside else None
        if m:
            found.append({k: v[1:-1] if v.startswith('"') else v
                          for k, v in re.findall(r'(\w+)=("[^"]*"|\S+)', m.group(1))})
    return found


def gh_json(path):
    try:
        proc = subprocess.run(["gh", "api", path], capture_output=True, text=True, timeout=LIMIT)
        value = json.loads(proc.stdout) if proc.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    return value if isinstance(value, dict) else None


def run_conclusion(repo, sha, name):
    """The conclusion of the check run called name on sha, "" when it cannot be read."""
    data = gh_json(f"repos/{repo}/commits/{sha}/check-runs?per_page=100")
    for run in (data or {}).get("check_runs") or []:
        if isinstance(run, dict) and run.get("name") == name:
            return str(run.get("conclusion") or "").lower()
    return ""


def proven_cause(d, head, name, proofs):
    """"base" or "infra" when a proof line for this check on this head holds up against gh, else None."""
    repo = a.repo or repo_of(d.get("url")) or repo_of(a.pr)
    if not repo:
        return None
    for proof in proofs:
        if proof.get("check") != name or str(proof.get("head", "")).lower() != head:
            continue
        cause = proof.get("cause")
        if cause == "infra" and run_conclusion(repo, head, name) in ("cancelled", "startup_failure", "timed_out", "stale"):
            return "infra"
        base, tip = str(proof.get("base", "")).lower(), str(d.get("baseRefOid") or "").lower()
        if cause == "base" and re.fullmatch(r"[0-9a-f]{40}", base) and base == tip \
                and run_conclusion(repo, base, name) == "failure":
            return "base"
    return None


def hosted_missing(d, checks):
    """The hosted reviewer's required check when the head has no entry for it at all, else None (#59)."""
    login = bare(a.hosted).lower() if isinstance(a.hosted, str) else ""
    word = re.split(r"[-_\[\s]", login)[0] if login else ""
    lines = rule_lines(d)
    if not word or lines[0].startswith("unknown"):
        return None
    reported = {c.get("name") or c.get("context") for c in checks}
    required = [l[len("check "):] for l in lines[1:] if l.startswith("check ")]
    return next((c for c in required if word in c.lower() and c not in reported), None)


def threads(d):
    """Unresolved review threads as lists of (login, body), or None when they cannot be read."""
    repo = (a.repo or repo_of(d.get("url")) or repo_of(a.pr)).split("/")
    number = re.search(r"(\d+)\s*$", a.pr)
    if len(repo) != 2 or not number:
        return None
    try:
        # -f sends a string as it is; -F would turn an owner or a name such as 123 or true into a number or a boolean
        proc = subprocess.run(["gh", "api", "graphql", "-f", f"query={THREADS_QUERY}", "-f", f"owner={repo[0]}",
                               "-f", f"name={repo[1]}", "-F", f"number={number.group(1)}"],
                              capture_output=True, text=True, timeout=LIMIT)
        nodes = json.loads(proc.stdout)["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError):
        return None
    if proc.returncode != 0 or not isinstance(nodes, list):  # a partial answer (errors beside the data) is no answer
        return None
    found = []
    for t in nodes:
        if isinstance(t, dict) and not t.get("isResolved"):
            comments = ((t.get("comments") or {}).get("nodes")) or []
            found.append([(bare((c.get("author") or {}).get("login")), str(c.get("body") or ""))
                          for c in comments if isinstance(c, dict)])
    return found


def fetch():
    """(d, reviews, checks, comments, state) for the PR; anything unreadable is a PENDING line."""
    fields = ("state,isDraft,reviewDecision,reviews,headRefOid,headRefName,headRepository,headRepositoryOwner,"
              "mergeable,mergeStateStatus,statusCheckRollup,mergeCommit,url,baseRefName")
    if a.merge_gate:
        fields += ",baseRefOid,author,comments"
    cmd = ["gh", "pr", "view", a.pr, "--json", fields]
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
    comments = records(d, "comments") if a.merge_gate else []
    if reviews is None or checks is None or comments is None:
        out("PENDING gh: unreadable output")
    state = d.get("state").upper() if isinstance(d.get("state"), str) else None
    if state not in ("OPEN", "MERGED", "CLOSED") or not isinstance(d.get("reviewDecision") or "", str):
        out("PENDING gh: unreadable output")
    return d, reviews, checks, comments, state


def branch_tip(d):
    """The sha GitHub's git API gives for the PR's head branch, "" when it cannot be read. It moves
    on a push before the PR's headRefOid does (#62)."""
    owner = d.get("headRepositoryOwner") if isinstance(d.get("headRepositoryOwner"), dict) else {}
    named = d.get("headRepository") if isinstance(d.get("headRepository"), dict) else {}
    repo = (f"{owner.get('login')}/{named.get('name')}" if owner.get("login") and named.get("name")
            else a.repo or repo_of(d.get("url")) or repo_of(a.pr))
    branch = d.get("headRefName")
    if not repo or not isinstance(branch, str) or not branch:
        return ""
    try:
        proc = subprocess.run(["gh", "api", f"repos/{repo}/git/ref/heads/{quote(branch, safe='/')}"],
                              capture_output=True, text=True, timeout=LIMIT)
        sha = json.loads(proc.stdout)["object"]["sha"] if proc.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError):
        return ""
    return sha.lower() if isinstance(sha, str) else ""


def main():
    a.head = a.head.strip().lower()
    use_star_token(a.home)
    d, reviews, checks, comments, state = fetch()
    head = (d.get("headRefOid") or "").lower()
    if state == "OPEN" and len(a.head) >= 7 and head and not head.startswith(a.head):
        tip = branch_tip(d)
        if tip.startswith(a.head):
            for _ in range(18):  # GitHub can show the previous head for a few seconds after a push (#62)
                time.sleep(5 * PAUSE)
                d, reviews, checks, comments, state = fetch()
                head = (d.get("headRefOid") or "").lower()
                if state != "OPEN" or not head or head.startswith(a.head):
                    break
            else:
                out(f"PENDING head: the PR still shows {head[:7]} while its branch is at {tip[:7]}")

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
    author = bare((d.get("author") or {}).get("login")) if a.merge_gate else ""
    proofs = []
    if a.merge_gate:
        prefix = f"Codex gate: PASS (head {head}"
        receipts = []
        for comment in comments:
            login = (comment.get("author") or {}).get("login") or ""
            if login and str(comment.get("body") or "").startswith(prefix) and bare(login) not in receipts:
                receipts.append(bare(login))
        if not author or author.lower() not in {login.lower() for login in receipts}:
            if receipts:
                out(f"FAIL no codex PASS for {head[:7]} (posted by {', '.join(receipts)}, not the PR's author)")
            out(f"FAIL no codex PASS for {head[:7]}")
        if a.brief is not None:
            try:
                proofs = proofs_of(a.brief)
            except (OSError, ValueError) as e:
                out("PENDING brief: " + (e.strerror or str(e)).splitlines()[0][:120])

    latest = {}
    for n, r in enumerate(sorted(reviews, key=lambda r: r.get("submittedAt") or "")):
        if r.get("state") in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
            # a deleted account has no login: each of its reviews is its own reviewer
            who = (r.get("author") or {}).get("login")
            latest[who or ("", r.get("id") or n)] = r
    blockers = sorted({who if isinstance(who, str) else "a deleted account"
                       for who, r in latest.items() if r.get("state") == "CHANGES_REQUESTED"})
    decision = d.get("reviewDecision") or None
    zero, note = False, ""
    if a.merge_gate:
        if blockers:
            out("FAIL approval: changes requested by " + names(blockers))
        approved = any(r.get("state") == "APPROVED" and ((r.get("commit") or {}).get("oid") or "").lower() == head
                       and bare((r.get("author") or {}).get("login")) != author
                       and str(r.get("authorAssociation") or "").upper() in WRITERS for r in latest.values())
        if approved:
            note = "hosted" if a.hosted else "approved"
        else:
            rule = review_rule(d)
            if rule == "unknown" or rule.startswith("unknown "):
                why = rule[len("unknown"):].strip() or "unreadable"
                out("PENDING " + why if why.startswith("gh cannot see ") else "PENDING review rule: " + why)
            if rule not in ("none", "required 0"):
                out(f"PENDING approval: none on the current head from someone other than {author or 'the author'}")
            note = "hosted" if a.hosted else "no approval required"
    elif decision is None:
        if blockers:
            out("FAIL approval: changes requested by " + names(blockers))
        if not any(r.get("state") == "APPROVED" and ((r.get("commit") or {}).get("oid") or "").lower() == head
                   for r in latest.values()):
            rule = review_rule(d)
            if rule == "unknown" or rule.startswith("unknown "):
                why = rule[len("unknown"):].strip() or "unreadable"
                out("PENDING " + why if why.startswith("gh cannot see ") else "PENDING review rule: " + why)
            zero = rule == "required 0"
            if not zero:
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
    proven = []
    if failed and a.merge_gate and proofs:
        lines = rule_lines(d)
        if not lines[0].startswith("unknown"):  # whether a check is required is unknown otherwise
            required = {l[len("check "):] for l in lines[1:] if l.startswith("check ")}
            for name in list(failed):
                cause = None if name in required else proven_cause(d, head, name, proofs)
                if cause:
                    failed.remove(name)
                    proven.append(f"{name} {cause}")
    if failed:
        out("FAIL checks: " + names(failed))
    if d.get("mergeable") == "CONFLICTING":
        out("FAIL conflicts")
    if waiting:
        out("PENDING checks: " + names(waiting))
    if a.merge_gate and a.hosted:
        missing = hosted_missing(d, checks)
        if missing:
            out(f"PENDING hosted-status {missing} missing on {head[:7]}")
    if a.merge_gate:
        lines = rule_lines(d)
        if not lines[0].startswith("unknown"):
            reported = {c.get("name") or c.get("context") for c in checks}
            absent = next((l[len("check "):] for l in lines[1:] if l.startswith("check ") and l[len("check "):] not in reported), None)
            if absent:
                out(f"PENDING check {absent} not reported on {head[:7]}")
    if d.get("mergeable") != "MERGEABLE":
        out("PENDING mergeable")
    merge_state = str(d.get("mergeStateStatus") or "").upper()
    if merge_state == "BLOCKED":
        out("PENDING merge state: blocked (a required check or review has not reported)")
    if merge_state == "BEHIND" and base_requires_up_to_date(d):
        out("PENDING merge state: behind the base branch")
    if a.merge_gate:
        open_threads = threads(d)
        if open_threads is None:
            out("PENDING gh: review threads unreadable")
        unanswered = sum(1 for t in open_threads if t and t[0][0] != author
                         and not any(who == author for who, _ in t[1:]))
        if unanswered:
            out(f"FAIL {unanswered} finding" + ("s" if unanswered > 1 else "") + " without a reply from the author")
        out("PASS " + note + (f" (proven not the PR's: {', '.join(proven)})" if proven else ""))
    if on_head:
        out("PASS")
    if zero:
        out("PASS no approval required")
    out("PASS approval is on an earlier commit")


try:
    main()
except Exception:  # an output shape nobody planned for is "ask again later", never a crash or a pass
    out("PENDING gh: unreadable output")
PY
