#!/bin/sh
# Reports what changed on a PR since a cursor, as one JSON object on stdout:
#   {"state","decision","head","author","url","new_feedback":[...],"reviewers","cursor"}
# Feedback = review bodies, inline comments and conversation comments from humans other than
# the PR author. Bots ([bot] logins or type Bot) are ignored. Failures print {"error": "..."}.
# Always exits 0. Per gh call timeout: BABYSIT_GH_TIMEOUT seconds (default 60).
exec python3 - "$@" <<'PY'
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime

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


def emit(obj):
    print(json.dumps(obj, separators=(",", ":")))


def main(argv):
    p = argparse.ArgumentParser(prog="pr-state.sh")
    p.add_argument("pr")
    p.add_argument("--since")
    p.add_argument("--repo")
    a = p.parse_args(argv)
    try:
        emit(snapshot(a.pr, a.since, a.repo))
    except GhError as e:
        emit({"error": str(e)})
    except Exception as e:  # output drift from gh; never a traceback
        emit({"error": f"unexpected gh output: {type(e).__name__}: {e}"})


main(sys.argv[1:])
sys.exit(0)
PY
