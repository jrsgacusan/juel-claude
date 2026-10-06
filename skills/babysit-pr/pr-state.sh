#!/bin/sh
# Reports what changed on a PR since a cursor, as one JSON object on stdout:
#   {"state","decision","head","draft","base","author","url","new_feedback":[...],"reviewers","cursor"}
# Feedback = review bodies, inline comments and conversation comments from humans other than
# the PR author. Bots ([bot] logins or type Bot) are ignored. Failures print {"error": "..."}
# (a --wait that never got one good snapshot prints only "error" and "wake").
# "cursor" is an opaque string to pass back as --since: a time, then "#" and the ids already
# reported in that second, so an item that shares a second with the cursor is never lost and
# never reported twice. A bare time (no "#": the PR's createdAt, or a cursor from before ids
# existed) is strict: only later items count. An inline comment is timed by the later of its own time and its review's
# submit time: a comment written in a pending review counts from when the review was submitted.
# Always exits 0. Per gh call timeout: BABYSIT_GH_TIMEOUT seconds (default 60); under
# --wait --max-seconds no call may run past the budget (with a floor of 1 s per call).
# --wait polls every --interval seconds and prints the snapshot plus "wake" when something
# happens: feedback | approved | draft (approved while a draft: turned back into one, or never
# marked ready) | closed | errors (3 in a row) | silence | timeout.
# --hold-approval turns the approved and draft wakes off: use it while this run still holds
# deferred replies or a deferred "gh pr ready", so an approved PR waits out the quiet window
# instead of waking at once on every call.
exec python3 - "$@" <<'PY'
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

TIMEOUT = float(os.environ.get("BABYSIT_GH_TIMEOUT", "60"))
DEADLINE = None  # time.monotonic() value set by --wait --max-seconds


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
        raise GhError(f"gh exited {proc.returncode}: {proc.stderr.strip()[:200]}")
    return proc.stdout


def gh_list(path):
    out = gh(["api", "--paginate", path, "--jq", ".[]"])
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


def snapshot(pr, since, repo):
    view_args = ["pr", "view", pr, "--json", "state,reviewDecision,headRefOid,isDraft,baseRefName,author,url"]
    if repo:
        view_args += ["-R", repo]
    view = json.loads(gh(view_args))
    url = view["url"]
    repo = repo or "/".join(url.split("/")[3:5])
    author = view["author"]["login"]
    base = f"repos/{repo}"

    def human(user):
        return bool(user) and not is_bot(user) and user.get("login") != author

    items, reviewers, submitted = [], set(), {}
    for r in gh_list(f"{base}/pulls/{pr}/reviews"):
        if r.get("submitted_at"):
            submitted[r.get("id")] = r["submitted_at"]
        user = r.get("user")
        if not human(user) or not r.get("submitted_at") or r.get("state") in ("PENDING", "DISMISSED"):
            continue
        reviewers.add(user["login"])
        body = (r.get("body") or "").strip()
        if not body and r.get("state") in ("APPROVED", "COMMENTED"):
            continue
        items.append({"kind": "review", "id": r["id"], "author": user["login"], "at": r["submitted_at"],
                      "url": r.get("html_url"), "body": body, "review_state": r.get("state"),
                      "path": None, "line": None, "in_reply_to": None})
    for c in gh_list(f"{base}/pulls/{pr}/comments"):
        user = c.get("user")
        if not human(user):
            continue
        reviewers.add(user["login"])
        at = max([c["created_at"], submitted.get(c.get("pull_request_review_id")) or c["created_at"]], key=ts)
        items.append({"kind": "inline", "id": c["id"], "author": user["login"], "at": at,
                      "url": c.get("html_url"), "body": c.get("body") or "", "review_state": None,
                      "path": c.get("path"), "line": c.get("line") or c.get("original_line"),
                      "in_reply_to": c.get("in_reply_to_id")})
    for c in gh_list(f"{base}/issues/{pr}/comments"):
        user = c.get("user")
        if not human(user):
            continue
        reviewers.add(user["login"])
        items.append({"kind": "comment", "id": c["id"], "author": user["login"], "at": c["created_at"],
                      "url": c.get("html_url"), "body": c.get("body") or "", "review_state": None,
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
    return {"state": view["state"], "decision": view.get("reviewDecision") or None,
            "head": view.get("headRefOid"), "draft": bool(view.get("isDraft")),
            "base": view.get("baseRefName"), "author": author, "url": url,
            "new_feedback": items, "reviewers": sorted(reviewers), "cursor": cursor}


def wake_reason(snap, hold_approval=False):
    if snap["state"] in ("CLOSED", "MERGED"):
        return "closed"
    if snap["new_feedback"]:
        return "feedback"
    if snap["decision"] == "APPROVED" and not hold_approval:
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
            snap = snapshot(a.pr, a.since, a.repo)
        except Exception as e:
            errors += 1
            last_error = str(e) if isinstance(e, GhError) else f"unexpected gh output: {type(e).__name__}: {e}"
            if errors >= 3:
                return {**(last_good or {}), "error": last_error, "wake": "errors"}
        else:
            errors, last_good = 0, snap
            reason = wake_reason(snap, a.hold_approval)
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
    a = p.parse_args(argv)
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
        emit(snapshot(a.pr, a.since, a.repo))
    except GhError as e:
        emit({"error": str(e)})
    except Exception as e:  # output drift from gh; never a traceback
        emit({"error": f"unexpected gh output: {type(e).__name__}: {e}"})

main(sys.argv[1:])
sys.exit(0)
PY
