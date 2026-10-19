#!/bin/sh
# Reports what changed on a PR since a cursor, as one JSON object on stdout:
#   {"state","decision","head","draft","base","author","url","approval","required","checks","merge",
#    "hosted","changes_requested","new_feedback":[...],"reviewers","cursor"}
#   plus "requested","head_seen" under --as-reviewer (below).
# "merge" is clean, dirty (the PR conflicts with its base: mergeStateStatus DIRTY, or mergeable
# CONFLICTING, which is all a draft shows, since GitHub reports DRAFT for it), behind, blocked, or
# unknown (GitHub is still computing it). UNSTABLE and HAS_HOOKS still merge: clean.
# Feedback = review bodies, inline comments and conversation comments from humans other than
# the PR author, plus two kinds of bot: the app behind a status check the base branch's rules
# require (a code-review app whose status is required; never github-actions[bot], which is CI),
# and any login given in --review-bots (github-actions[bot] counts only when listed there).
# Every other bot ([bot] logins or type Bot) is ignored, and no bot is ever in "reviewers".
# "approval"/"required" come from review-rule.sh: required <n>, none or unknown. "checks" is
# green (every check on the head finished passing and every required one reported), pending or
# failing. Failures print {"error": "..."}; a repository gh cannot see is
# "gh cannot see <repo>: export GH_TOKEN for this repository".
# (a --wait that never got one good snapshot prints only "error" and "wake").
# "cursor" is an opaque string to pass back as --since: a time, then "#" and the ids already
# reported in that second, so an item that shares a second with the cursor is never lost and
# never reported twice. A bare time (no "#": the PR's createdAt, or a cursor from before ids
# existed) is strict: only later items count. An inline comment is timed by the later of its own time and its review's
# submit time: a comment written in a pending review counts from when the review was submitted.
# --hosted <login> names the hosted reviewer (greptile-apps[bot]). It is kept like a --review-bots
# login, and "hosted" says how its status on the head stands: none, pending, success, failure, or
# unknown when GitHub could not be read (null without --hosted). Its status is a check run of the
# app <login without [bot]>, or a commit status <login> created. Its summary comment, which it edits
# in place on every re-review, is the item {"kind": "hosted-pass", "head": <the full head>, ...}
# while its "Last reviewed commit" names the PR's head: the item's id is <comment id>@<updated_at>
# and its time is updated_at, so each edit that names the head is new feedback once. An edit that
# names an older head stays a plain comment, timed by its creation: not new. A hosted-skip item is
# a review or summary edit by the hosted login that reviewed nothing, by skip_reason's rule; it has
# head and reason, and a summary edit is new once per edit.
# --hosted <login> --hosted-passes prints, in place of the snapshot, the hosted reviewer's past
# passes in the <item>-hosted.log form (#96), one line per distinct head, oldest first:
#   <time> pass <n> head=<full sha>
#   <time> skipped head=<sha> <reason>
# A pass is a review by <login> (compared without case, as --hosted matches it) that is not
# PENDING, read from pulls/<n>/reviews and timed by submitted_at, or a conversation comment by
# <login> whose "Last reviewed commit" footer names a commit (#116), read from issues/<n>/comments
# and timed by updated_at (the summary is edited in place, so it holds only its newest pass). A
# hosted review with a skip reason and no confidence score is a skipped run, not a pass; the
# reason is the first matching line, with Markdown marks removed and whitespace folded. A footer sha shorter than 40 is expanded by prefix from the review heads and the PR's head, else
# from pulls/<n>/commits (read only then); one nothing expands is printed as given. A head named
# more than once keeps its earliest time. Every list is read paginated. No pass prints nothing
# (exit 0). GitHub that cannot be read prints one line, "error <why>" (exit 1). No --hosted, or
# --wait or --as-reviewer with it, is a usage error (exit 64).
# <pr> is a number, a PR URL (STAR's ledger holds one), a branch name or #<n>; the REST paths use its number.
# Exits 0, except a usage error in --hosted-passes (above) or the reviewer flags (below), which is
# 64, and a --hosted-passes "error" line, which is 1. Per gh call timeout:
# BABYSIT_GH_TIMEOUT seconds (default 60); under
# --wait --max-seconds no call may run past the budget (with a floor of 1 s per call).
# --wait polls every --interval seconds and prints the snapshot plus "wake" when something
# happens: feedback | conflict ("merge" is dirty; it wakes even under --hold-approval) |
# approved (reviewDecision APPROVED; or, where the rules require 0
# approving reviews, no reviewer's latest review is CHANGES_REQUESTED and "checks" is green) |
# draft (approved while a draft: turned back into one, or never
# marked ready) | closed | errors (3 in a row) | silence | timeout.
# --hold-approval turns the approved and draft wakes off: use it while this run must not end
# on an approval yet
# instead of waking at once on every call.
# --as-reviewer <login> --reviewed-head <sha> [--settle-minutes <n>] [--head-seen <sha>@<iso>]
# watch a PR that <login> reviewed and someone else authored (babysit-pr's reviewer mode).
# --settle-minutes defaults to 30. The other three flags without --as-reviewer, an empty
# --as-reviewer, --as-reviewer without a --reviewed-head of 7 to 40 hex, a negative or non-finite
# (nan, inf) --settle-minutes, or a --head-seen that is not <sha>@<iso> print the reason on stderr
# and exit 64, before any gh call.
# In that mode "new_feedback" holds only the PR author's items, "reviewers" is empty, and the
# snapshot adds "requested" (the time of the newest review_requested timeline event that names
# <login> itself, compared without case, never a team, after the cursor's second; else null: a
# request at or before the cursor never counts) and "head_seen" ("<head>@<iso>": when this script
# first saw that head; --head-seen carries the time into a new call while its sha still starts the
# head). The timeline is read, paginated, only in this mode; a timeline that cannot be read is an
# error, like any other gh failure.
# --wait then wakes only: closed | rerequested ("requested" is not null) | settled (the head does
# not start with --reviewed-head, and "head_seen" is at least --settle-minutes old; a force-pushed
# head is a new head like any other) | errors | silence | timeout. Never feedback, conflict,
# approved or draft: those are the author's to act on. One --wait call keeps "head_seen" across
# its polls; the foreground form passes the last snapshot's "head_seen" back as --head-seen.
BABYSIT_DIR=$(cd "$(dirname "$0")" && pwd)
export BABYSIT_DIR
exec python3 - "$@" <<'PY'
import argparse
import json
import math
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

TIMEOUT = float(os.environ.get("BABYSIT_GH_TIMEOUT", "60"))
DEADLINE = None  # time.monotonic() value set by --wait --max-seconds
PASSING = {"SUCCESS", "NEUTRAL", "SKIPPED"}
WAITING = {"", "PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}
RULES = {}  # (repo, base) -> (first line, required check contexts); a --wait reads a known rule once


def explain(message):
    if "Could not resolve to a Repository" in message:
        named = re.search(r"name '([^']+)'", message)
        return f"gh cannot see {named.group(1) if named else 'this repository'}: export GH_TOKEN for this repository"
    return message


class GhError(Exception):
    pass


def gh(args):
    limit = TIMEOUT if DEADLINE is None else max(1.0, min(TIMEOUT, DEADLINE - time.monotonic()))
    try:
        proc = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=limit)
    except FileNotFoundError:
        raise GhError("gh not found on PATH")
    except subprocess.TimeoutExpired:
        raise GhError(f"gh timed out after {limit:g}s")
    if proc.returncode != 0:
        raise GhError(explain(f"gh exited {proc.returncode}: {proc.stderr.strip()[:200]}"))
    return proc.stdout


def gh_list(path, jq=".[]"):
    out = gh(["api", "--paginate", path, "--jq", jq])
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def ts(value):
    t = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def split_cursor(value):
    """'<iso>#<id>,<id>' -> (iso, {ids already reported in that second}); a bare time has no ids."""
    if not value:
        return None, set()
    iso, _, ids = value.partition("#")
    return iso, {i for i in ids.split(",") if i}


def is_bot(user):
    return user.get("type") == "Bot" or (user.get("login") or "").endswith("[bot]")


def review_rule(repo, base):
    """(first line of review-rule.sh, [required check contexts]); an unknown rule is never cached."""
    if (repo, base) in RULES:
        return RULES[(repo, base)]
    script = os.path.join(os.environ.get("BABYSIT_DIR") or "", "review-rule.sh")
    first, checks = "unknown", []
    if repo and base and os.path.isfile(script):
        limit = 2 * TIMEOUT + 5
        if DEADLINE is not None:
            limit = max(1.0, min(limit, DEADLINE - time.monotonic()))
        try:
            proc = subprocess.run(["sh", script, repo, base], capture_output=True, text=True, timeout=limit)
            lines = (proc.stdout or "").splitlines()
            first = (lines or ["unknown"])[0].strip()
            checks = [l[len("check "):] for l in lines[1:] if l.startswith("check ")]
        except (OSError, subprocess.TimeoutExpired):
            pass
    if first == "none" or first.startswith("required "):
        RULES[(repo, base)] = (first, checks)
    return first, checks


def checks_state(rollup, required):
    if not isinstance(rollup, list):
        return "pending"
    seen, pending = set(), False
    for c in rollup:
        if not isinstance(c, dict):
            continue
        seen.add(c.get("name") or c.get("context") or "")
        if c.get("__typename") == "CheckRun" and (c.get("status") or "COMPLETED") != "COMPLETED":
            pending = True
            continue
        value = (c.get("conclusion") or c.get("state") or "").upper()
        if value in PASSING:
            continue
        if value in WAITING:
            pending = True
            continue
        return "failing"
    return "pending" if pending or any(r not in seen for r in required) else "green"


def merge_state(view):
    """clean | dirty | behind | blocked | unknown, from GitHub's two merge fields."""
    status = str(view.get("mergeStateStatus") or "").upper()
    mergeable = str(view.get("mergeable") or "").upper()
    if status == "DIRTY" or mergeable == "CONFLICTING":
        return "dirty"
    if status == "BEHIND":
        return "behind"
    if status == "BLOCKED":
        return "blocked"
    if status in ("CLEAN", "HAS_HOOKS", "UNSTABLE") or (status == "DRAFT" and mergeable == "MERGEABLE"):
        return "clean"
    return "unknown"


LAST_REVIEWED = re.compile(r"/commit/([0-9a-fA-F]{7,40})|last reviewed commit\W*([0-9a-fA-F]{7,40})\b", re.I)
SCORE = re.compile(r"confidence[^\n]{0,40}?\b[0-5](?:\.\d+)?\s*(?:/|out of)\s*5\b", re.I)
SKIP = re.compile(
    r"\breviews?\s+(?:was|were|has been|have been|is)?\s*skipped\b|"
    r"\bskipp(?:ed|ing)\s+(?:this\s+|the\s+)?review\b|"
    r"\b(?:exceed\w*|reach\w*|hit)\b[^\n]{0,60}?\busage limit\b|"
    r"\busage limit\b[^\n]{0,30}?\b(?:reached|exceeded|hit)\b", re.I
)


def last_reviewed(body):
    """The commit a hosted reviewer's summary says it last reviewed, lowercase, or None."""
    for line in body.splitlines():
        lower = line.lower()
        if "last reviewed commit" in lower:
            m = LAST_REVIEWED.search(line[lower.index("last reviewed commit"):])
            if m:
                return (m.group(1) or m.group(2)).lower()
    return None


def skip_reason(body):
    """The first hosted-review skip notice, with Markdown marks removed, or None."""
    searchable = re.sub(r"[*_`]", "", body)
    if SCORE.search(searchable):
        return None
    for line in body.splitlines():
        cleaned = re.sub(r"[*_>#]", "", line)
        cleaned = " ".join(cleaned.split())
        if cleaned and SKIP.search(cleaned):
            return cleaned[:160]
    return None


def hosted_status(runs, statuses, login):
    """none | pending | success | failure: the hosted reviewer's status on the head; unknown unread."""
    if runs is None or statuses is None:
        return "unknown"
    login = login.lower()
    slug = login[:-len("[bot]")] if login.endswith("[bot]") else login
    seen = []
    for r in runs:
        if ((r.get("app") or {}).get("slug") or "").lower() == slug:
            if (r.get("status") or "completed").lower() != "completed":
                seen.append("pending")
            elif (r.get("conclusion") or "").lower() in ("success", "neutral", "skipped"):
                seen.append("success")
            else:
                seen.append("failure")
    for s in statuses:
        if ((s.get("creator") or {}).get("login") or "").lower() == login:
            value = (s.get("state") or "").lower()
            seen.append(value if value in ("success", "pending") else "failure")
    for verdict in ("failure", "pending", "success"):
        if verdict in seen:
            return verdict
    return "none"


def pr_number(pr, view):
    """The number the REST paths need: <pr> itself when it is one, else the number in a /pull/<n> URL, else the
    one gh returned for a branch name or #<n> in the same `gh pr view`."""
    if pr.isdigit():
        return pr
    in_url = re.search(r"/pull/(\d+)", pr)
    return in_url.group(1) if in_url else str(view["number"])


def hosted_passes(pr, repo, login):
    """The hosted reviewer's past passes and skipped runs as <item>-hosted.log lines."""
    view_args = ["pr", "view", pr, "--json", "url,number,headRefOid"]
    if repo:
        view_args += ["-R", repo]
    view = json.loads(gh(view_args))
    repo = repo or "/".join(view["url"].split("/")[3:5])
    number = pr_number(pr, view)

    def by_login(item):
        return ((item.get("user") or {}).get("login") or "").lower() == login.lower()

    reviews = gh_list(f"repos/{repo}/pulls/{number}/reviews")
    comments = gh_list(f"repos/{repo}/issues/{number}/comments")
    known = [str(r.get("commit_id") or "").lower() for r in reviews if r.get("commit_id")]
    known.append(str(view.get("headRefOid") or "").lower())
    commits = None

    def full(sha):
        nonlocal commits
        sha = (sha or "").lower()
        if len(sha) >= 40:
            return sha
        matches = {k for k in known if k and k.startswith(sha)}
        if not matches:
            if commits is None:
                commits = [str(x.get("sha") or "").lower()
                           for x in gh_list(f"repos/{repo}/pulls/{number}/commits")]
            matches = {k for k in commits if k.startswith(sha)}
        return matches.pop() if len(matches) == 1 else sha

    passes = []
    skipped = []
    for review in reviews:
        if not by_login(review) or review.get("state") == "PENDING":
            continue
        when = review.get("submitted_at")
        sha = str(review.get("commit_id") or "").lower()
        if not when or not sha:
            continue
        reason = skip_reason(str(review.get("body") or ""))
        if reason:
            skipped.append((when, sha, reason))
        else:
            passes.append((when, sha))
    for comment in comments:
        if not by_login(comment):
            continue
        body = str(comment.get("body") or "")
        reason = skip_reason(body)
        sha = last_reviewed(body)
        when = comment.get("updated_at") or comment.get("created_at")
        if not when or (not reason and not sha):
            continue
        sha = full(sha) if sha else str(view.get("headRefOid") or "").lower()
        if reason:
            skipped.append((when, sha, reason))
        else:
            passes.append((when, sha))

    earliest = {}
    for when, sha in passes:
        if sha not in earliest or ts(when) < ts(earliest[sha]):
            earliest[sha] = when
    numbered = [(when, f"{when} pass {n} head={sha}")
                for n, (sha, when) in enumerate(sorted(earliest.items(), key=lambda kv: ts(kv[1])), 1)]
    lines = numbered + [(when, f"{when} skipped head={sha} {reason}") for when, sha, reason in skipped]
    return [line for _, line in sorted(lines, key=lambda pair: (ts(pair[0]), 0 if " pass " in pair[1] else 1))]


def snapshot(pr, since, repo, bots=(), hosted="", reviewer=None):
    view_args = ["pr", "view", pr, "--json",
                 "state,reviewDecision,headRefOid,isDraft,baseRefName,author,url,statusCheckRollup,"
                 "mergeStateStatus,mergeable,number"]
    if repo:
        view_args += ["-R", repo]
    view = json.loads(gh(view_args))
    url = view["url"]
    repo = repo or "/".join(url.split("/")[3:5])
    author = view["author"]["login"]
    base = f"repos/{repo}"
    number = pr_number(pr, view)
    rule, required_checks = review_rule(repo, view.get("baseRefName"))
    head = view.get("headRefOid")
    kept = {b.lower() for b in bots} | ({hosted.lower()} if hosted else set())
    runs = None
    if head and (required_checks or hosted):
        try:
            runs = gh_list(f"{base}/commits/{head}/check-runs", ".check_runs[]")
        except (GhError, ValueError):
            runs = None  # no required-check bots this time; humans and listed bots still count
    for run in runs or []:
        slug = (run.get("app") or {}).get("slug")
        # GitHub Actions is CI, not a reviewer: only --review-bots can keep its bot
        if slug and slug != "github-actions" and run.get("name") in required_checks:
            kept.add(f"{slug}[bot]".lower())
    hosted_state = None
    if hosted:
        statuses = None
        if head:
            try:
                statuses = gh_list(f"{base}/commits/{head}/status", ".statuses[]")
            except (GhError, ValueError):
                statuses = None
        hosted_state = hosted_status(runs, statuses, hosted)

    def wanted(user):
        if reviewer:
            # a reviewer waits on the author: only the author's own words are news
            return bool(user) and user.get("login") == author
        if not user or user.get("login") == author:
            return False
        return not is_bot(user) or (user.get("login") or "").lower() in kept

    def note_reviewer(user):
        if not reviewer and not is_bot(user):
            reviewers.add(user["login"])

    items, reviewers, submitted, latest = [], set(), {}, {}
    raw_reviews = gh_list(f"{base}/pulls/{number}/reviews")
    for r in sorted(raw_reviews, key=lambda r: r.get("submitted_at") or ""):
        if r.get("state") in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
            latest[(r.get("user") or {}).get("login") or f"#{r.get('id')}"] = r.get("state")
    for r in raw_reviews:
        if r.get("submitted_at"):
            submitted[r.get("id")] = r["submitted_at"]
        user = r.get("user")
        if not wanted(user) or not r.get("submitted_at") or r.get("state") in ("PENDING", "DISMISSED"):
            continue
        note_reviewer(user)
        body = (r.get("body") or "").strip()
        if not body and r.get("state") in ("APPROVED", "COMMENTED"):
            continue
        reason = skip_reason(body) if hosted and (user.get("login") or "").lower() == hosted.lower() else None
        if reason:
            items.append({"kind": "hosted-skip", "id": r["id"], "author": user["login"], "at": r["submitted_at"],
                          "url": r.get("html_url"), "body": body, "review_state": r.get("state"),
                          "path": None, "line": None, "in_reply_to": None,
                          "head": str(r.get("commit_id") or "").lower(), "reason": reason})
        else:
            items.append({"kind": "review", "id": r["id"], "author": user["login"], "at": r["submitted_at"],
                          "url": r.get("html_url"), "body": body, "review_state": r.get("state"),
                          "path": None, "line": None, "in_reply_to": None})
    for c in gh_list(f"{base}/pulls/{number}/comments"):
        user = c.get("user")
        if not wanted(user):
            continue
        note_reviewer(user)
        at = max([c["created_at"], submitted.get(c.get("pull_request_review_id")) or c["created_at"]], key=ts)
        items.append({"kind": "inline", "id": c["id"], "author": user["login"], "at": at,
                      "url": c.get("html_url"), "body": c.get("body") or "", "review_state": None,
                      "path": c.get("path"), "line": c.get("line") or c.get("original_line"),
                      "in_reply_to": c.get("in_reply_to_id")})
    for c in gh_list(f"{base}/issues/{number}/comments"):
        user = c.get("user")
        if not wanted(user):
            continue
        note_reviewer(user)
        body = c.get("body") or ""
        mine = bool(hosted) and (user.get("login") or "").lower() == hosted.lower()
        reviewed = last_reviewed(body) if mine else None
        reason = skip_reason(body) if mine else None
        if reason:
            at = c.get("updated_at") or c["created_at"]
            skip_head = head if not reviewed or (head and head.lower().startswith(reviewed)) else reviewed
            items.append({"kind": "hosted-skip", "id": f"{c['id']}@{at}", "author": user["login"], "at": at,
                          "url": c.get("html_url"), "body": body, "review_state": None,
                          "path": None, "line": None, "in_reply_to": None,
                          "head": skip_head, "reason": reason})
            continue
        if reviewed and head and head.lower().startswith(reviewed):
            # the hosted reviewer's summary, edited in place: each edit that names the head is new once
            at = c.get("updated_at") or c["created_at"]
            items.append({"kind": "hosted-pass", "id": f"{c['id']}@{at}", "author": user["login"], "at": at,
                          "url": c.get("html_url"), "body": body, "review_state": None,
                          "path": None, "line": None, "in_reply_to": None, "head": head})
            continue
        items.append({"kind": "comment", "id": c["id"], "author": user["login"], "at": c["created_at"],
                      "url": c.get("html_url"), "body": body, "review_state": None,
                      "path": None, "line": None, "in_reply_to": None})

    since_at, seen = split_cursor(since)
    everything = items
    if since_at:
        edge = ts(since_at)
        # a bare time is strict, as it always was; with ids, its own second is open to ids not yet seen
        items = [i for i in items if ts(i["at"]) > edge or (seen and ts(i["at"]) == edge and str(i["id"]) not in seen)]
    items.sort(key=lambda i: ts(i["at"]))
    cursor = since
    if items:
        newest = ts(items[-1]["at"])
        at_newest = sorted({str(i["id"]) for i in everything if ts(i["at"]) == newest}, key=lambda x: (len(x), x))
        cursor = items[-1]["at"] + "#" + ",".join(at_newest)
    extra = {}
    if reviewer:
        # a re-request counts only after the cursor's second, so a request already handled never wakes again
        edge = ts(since_at) if since_at else None
        asked = []
        for e in gh_list(f"{base}/issues/{number}/timeline"):
            who = ((e.get("requested_reviewer") or {}).get("login") or "").lower()
            if e.get("event") != "review_requested" or who != reviewer["login"].lower() or not e.get("created_at"):
                continue  # a team request names requested_team, not requested_reviewer
            if edge is None or ts(e["created_at"]) > edge:
                asked.append(e["created_at"])
        seen_sha, _, seen_at = (reviewer.get("head_seen") or "").partition("@")
        if not (head and seen_sha and head.lower().startswith(seen_sha.lower())):
            seen_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        extra = {"requested": max(asked, key=ts) if asked else None, "head_seen": f"{head or ''}@{seen_at}"}
    approval, required = "unknown", None
    if rule == "none":
        approval = "none"
    elif rule.startswith("required ") and rule.split()[1].isdigit():
        approval, required = "required", int(rule.split()[1])
    return {"state": view["state"], "decision": view.get("reviewDecision") or None,
            "head": head, "draft": bool(view.get("isDraft")),
            "base": view.get("baseRefName"), "author": author, "url": url,
            "approval": approval, "required": required,
            "checks": checks_state(view.get("statusCheckRollup"), required_checks),
            "merge": merge_state(view), "hosted": hosted_state,
            "changes_requested": sorted(w for w, s in latest.items() if s == "CHANGES_REQUESTED"),
            "new_feedback": items, "reviewers": sorted(reviewers), "cursor": cursor, **extra}


def settled(snap, reviewer):
    """The head moved off the one the reviewer last reviewed and has stayed put for --settle-minutes."""
    head = (snap.get("head") or "").lower()
    if not head or head.startswith(reviewer["reviewed_head"]):
        return False
    at = (snap.get("head_seen") or "").partition("@")[2]
    return bool(at) and (datetime.now(timezone.utc) - ts(at)).total_seconds() >= reviewer["settle"] * 60


def wake_reason(snap, hold_approval=False, reviewer=None):
    if snap["state"] in ("CLOSED", "MERGED"):
        return "closed"
    if reviewer:
        # the author's comments, a conflict, an approval or a draft are the author's to act on: only a
        # re-request, or a head that stopped moving, asks the reviewer to look again
        if snap.get("requested"):
            return "rerequested"
        return "settled" if settled(snap, reviewer) else None
    if snap["new_feedback"]:
        return "feedback"
    if snap.get("merge") == "dirty":
        return "conflict"
    if hold_approval:
        return None
    approved = snap["decision"] == "APPROVED" or (
        snap["decision"] is None and snap.get("required") == 0
        and not snap.get("changes_requested") and snap.get("checks") == "green")
    if approved:
        return "draft" if snap["draft"] else "approved"
    return None


def wait(a):
    global DEADLINE
    started = time.monotonic()
    if a.max_seconds is not None:
        DEADLINE = started + a.max_seconds
    quiet_since = ts(a.quiet_since) if a.quiet_since else datetime.now(timezone.utc)
    errors, last_error, last_good = 0, None, None
    snap_cost = 0.0  # how long the slowest snapshot took; never start one the budget cannot finish
    while True:
        t_snap = time.monotonic()
        try:
            snap = snapshot(a.pr, a.since, a.repo, a.bots, a.hosted, a.reviewer)
        except Exception as e:
            errors += 1
            last_error = str(e) if isinstance(e, GhError) else f"unexpected gh output: {type(e).__name__}: {e}"
            if errors >= 3:
                return {**(last_good or {}), "error": last_error, "wake": "errors"}
        else:
            errors, last_good = 0, snap
            if a.reviewer:
                a.reviewer["head_seen"] = snap["head_seen"]  # the next poll keeps when this head was first seen
            reason = wake_reason(snap, a.hold_approval, a.reviewer)
            if reason:
                return {**snap, "wake": reason}
            quiet_for = (datetime.now(timezone.utc) - quiet_since).total_seconds()
            if a.silence_hours and quiet_for >= a.silence_hours * 3600:
                return {**snap, "wake": "silence"}
        snap_cost = max(snap_cost, time.monotonic() - t_snap)
        nap = a.interval
        if a.max_seconds is not None:
            # Sleep at most what is left of the budget after reserving one more snapshot, so an
            # interval longer than the budget (600 s polling inside a foreground call) still waits
            # instead of busy-looping, and a slow gh never pushes the call past --max-seconds.
            left = a.max_seconds - (time.monotonic() - started) - snap_cost
            if left <= 0:
                return {**(last_good or {}), "wake": "timeout", **({"error": last_error} if last_good is None else {})}
            nap = min(nap, left)
        time.sleep(nap)


def emit(obj):
    print(json.dumps(obj, separators=(",", ":")))


SHA = re.compile(r"[0-9a-fA-F]{7,40}")


def usage(msg):
    print(f"pr-state.sh: {msg}", file=sys.stderr)
    sys.exit(64)


def reviewer_args(a):
    """None without --as-reviewer; else {login, reviewed_head, settle (minutes), head_seen}. Half given: exit 64."""
    if a.as_reviewer is None:
        for flag, value in (("--reviewed-head", a.reviewed_head), ("--settle-minutes", a.settle_minutes),
                            ("--head-seen", a.head_seen)):
            if value is not None:
                usage(f"{flag} needs --as-reviewer")
        return None
    login = a.as_reviewer.strip()
    if not login:
        usage("--as-reviewer needs a login")
    if not a.reviewed_head or not SHA.fullmatch(a.reviewed_head):
        usage("--as-reviewer needs --reviewed-head <sha> (7 to 40 hex)")
    settle = 30.0 if a.settle_minutes is None else a.settle_minutes
    if not math.isfinite(settle) or settle < 0:
        usage("--settle-minutes must be 0 or more")
    if a.head_seen is not None:
        sha, _, at = a.head_seen.partition("@")
        try:
            ok = bool(SHA.fullmatch(sha)) and bool(at) and ts(at) is not None
        except ValueError:
            ok = False
        if not ok:
            usage("--head-seen must be <sha>@<iso time>")
    return {"login": login, "reviewed_head": a.reviewed_head.lower(), "settle": settle, "head_seen": a.head_seen}


def main(argv):
    p = argparse.ArgumentParser(prog="pr-state.sh")
    p.add_argument("pr")
    p.add_argument("--since")
    p.add_argument("--repo")
    p.add_argument("--wait", action="store_true")
    p.add_argument("--interval", type=float, default=600)
    p.add_argument("--max-seconds", type=float, default=None)
    p.add_argument("--silence-hours", type=float, default=0)
    p.add_argument("--quiet-since")
    p.add_argument("--hold-approval", action="store_true")
    p.add_argument("--review-bots", default="")
    p.add_argument("--hosted", default="")
    p.add_argument("--as-reviewer")
    p.add_argument("--reviewed-head")
    p.add_argument("--settle-minutes", type=float)
    p.add_argument("--head-seen")
    p.add_argument("--hosted-passes", action="store_true")
    a = p.parse_args(argv)
    a.bots = [b.strip() for b in a.review_bots.split(",") if b.strip()]
    a.hosted = a.hosted.strip()
    if a.hosted_passes:
        if not a.hosted:
            usage("--hosted-passes needs --hosted <login>")
        if a.wait or a.as_reviewer is not None:
            usage("--hosted-passes takes no --wait or --as-reviewer")
        try:
            lines = hosted_passes(a.pr, a.repo, a.hosted)
        except Exception as e:  # GitHub could not be read, or gh's output drifted; never a traceback
            why = str(e) if isinstance(e, GhError) else f"unexpected gh output: {type(e).__name__}: {e}"
            print("error " + " ".join(why.split()))
            sys.exit(1)
        for line in lines:
            print(line)
        return
    a.reviewer = reviewer_args(a)
    for flag, value in (("--since", split_cursor(a.since)[0]), ("--quiet-since", a.quiet_since)):
        try:
            if value:
                ts(value)
        except ValueError:
            emit({"error": f"bad {flag}: {value!r} is not an ISO time (2026-10-01T09:00:00Z)"})
            return
    if a.wait:
        emit(wait(a))
        return
    try:
        emit(snapshot(a.pr, a.since, a.repo, a.bots, a.hosted, a.reviewer))
    except GhError as e:
        emit({"error": str(e)})
    except Exception as e:  # output drift from gh; never a traceback
        emit({"error": f"unexpected gh output: {type(e).__name__}: {e}"})

main(sys.argv[1:])
sys.exit(0)
PY
