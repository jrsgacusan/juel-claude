#!/bin/sh
# Reports what changed on a PR since a cursor, as one JSON object on stdout:
#   {"state","decision","head","author","url","new_feedback":[...],"reviewers","cursor"}
# Feedback = review bodies, inline comments and conversation comments from humans other than
# the PR author. Bots ([bot] logins or type Bot) are ignored. Failures print {"error": "..."}.
# Always exits 0. Per gh call timeout: BABYSIT_GH_TIMEOUT seconds (default 60).
# --wait polls every --interval seconds and prints the snapshot plus "wake" when something
# happens: feedback | approved | closed | errors (3 in a row) | silence | timeout.
exec python3 - "$@" <<'PY'
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

TIMEOUT = float(os.environ.get("BABYSIT_GH_TIMEOUT", "60"))


class GhError(Exception):
    pass


def gh(args):
    try:
        proc = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=TIMEOUT)
    except FileNotFoundError:
        raise GhError("gh not found on PATH")
    except subprocess.TimeoutExpired:
        raise GhError(f"gh timed out after {TIMEOUT:g}s")
    if proc.returncode != 0:
        raise GhError(f"gh exited {proc.returncode}: {proc.stderr.strip()[:200]}")
    return proc.stdout


def gh_list(path):
    out = gh(["api", "--paginate", path, "--jq", ".[]"])
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def ts(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def is_bot(user):
    return user.get("type") == "Bot" or (user.get("login") or "").endswith("[bot]")


def snapshot(pr, since, repo):
    view_args = ["pr", "view", pr, "--json", "state,reviewDecision,headRefOid,author,url"]
    if repo:
        view_args += ["-R", repo]
    view = json.loads(gh(view_args))
    url = view["url"]
    repo = repo or "/".join(url.split("/")[3:5])
    author = view["author"]["login"]
    base = f"repos/{repo}"

    def human(user):
        return bool(user) and not is_bot(user) and user.get("login") != author

    items, reviewers = [], set()
    for r in gh_list(f"{base}/pulls/{pr}/reviews"):
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
        items.append({"kind": "inline", "id": c["id"], "author": user["login"], "at": c["created_at"],
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

    if since:
        items = [i for i in items if ts(i["at"]) > ts(since)]
    items.sort(key=lambda i: ts(i["at"]))
    cursor = items[-1]["at"] if items else since
    return {"state": view["state"], "decision": view.get("reviewDecision") or None,
            "head": view.get("headRefOid"), "author": author, "url": url,
            "new_feedback": items, "reviewers": sorted(reviewers), "cursor": cursor}


def wake_reason(snap):
    if snap["state"] in ("CLOSED", "MERGED"):
        return "closed"
    if snap["new_feedback"]:
        return "feedback"
    if snap["decision"] == "APPROVED":
        return "approved"
    return None


def wait(a):
    started = time.monotonic()
    quiet_since = ts(a.quiet_since) if a.quiet_since else datetime.now(timezone.utc)
    errors, last_error, last_good = 0, None, None
    while True:
        try:
            snap = snapshot(a.pr, a.since, a.repo)
        except Exception as e:
            errors += 1
            last_error = str(e) if isinstance(e, GhError) else f"unexpected gh output: {type(e).__name__}: {e}"
            if errors >= 3:
                return {**(last_good or {}), "error": last_error, "wake": "errors"}
        else:
            errors, last_good = 0, snap
            reason = wake_reason(snap)
            if reason:
                return {**snap, "wake": reason}
            quiet_for = (datetime.now(timezone.utc) - quiet_since).total_seconds()
            if a.silence_hours and quiet_for >= a.silence_hours * 3600:
                return {**snap, "wake": "silence"}
        nap = a.interval
        if a.max_seconds is not None:
            # Sleep at most what is left of the budget, so an interval longer than the budget
            # (600 s polling inside 540 s foreground calls) still waits instead of busy-looping.
            left = a.max_seconds - (time.monotonic() - started)
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
    a = p.parse_args(argv)
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
