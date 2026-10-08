#!/bin/sh
# Says how many approving reviews a base branch's rules require, and which status checks they
# require, so babysit-pr and STAR know whether to wait for an approval at all (#27).
#   review-rule.sh <owner/repo> <base>
# Prints, first:
#   required <n>     a rule asks for n approving reviews (n may be 0: an explicit zero)
#   none             no ruleset, and no readable classic protection, asks for reviews
#   unknown <why>    the rulesets or classic protection could not be read (the only line);
#                    every caller treats it like none
# then one line per status check the rules require:
#   check <context>
# Sources: the rulesets that apply to the branch (repos/<repo>/rules/branches/<base>, readable
# with read access) and classic branch protection (repos/<repo>/branches/<base>/protection,
# often admin-only: a 403 or 404 there means no classic rule; any other error there, such as a
# 502 or a timeout, is unknown). The higher count wins. A review rule whose count is missing or
# malformed is read as 1: bad data never relaxes a check.
# A 404 or "Could not resolve to a Repository" on the rulesets (gh signed in to an account that
# cannot see a private repo) prints "unknown gh cannot see <repo>: export GH_TOKEN for this
# repository". Per-call timeout: BABYSIT_GH_TIMEOUT, else STAR_GH_TIMEOUT, seconds (default 60;
# a value that is not a number falls back to 60).
# Exit: 0, or 64 on bad usage.
exec python3 - "$@" <<'PY'
import json
import os
import subprocess
import sys
from urllib.parse import quote

args = sys.argv[1:]
if len(args) != 2 or args[0].count("/") != 1 or not all(args[0].split("/")) or not args[1]:
    print("usage: review-rule.sh <owner/repo> <base>", file=sys.stderr)
    sys.exit(64)
repo, base = args
BRANCH = quote(base, safe="/")
try:
    LIMIT = float(os.environ.get("BABYSIT_GH_TIMEOUT") or os.environ.get("STAR_GH_TIMEOUT") or "60")
except ValueError:
    LIMIT = 60.0


def api(path):
    """(data, None) on success; (None, the first line of the error) otherwise."""
    try:
        proc = subprocess.run(["gh", "api", path], capture_output=True, text=True, timeout=LIMIT)
    except FileNotFoundError:
        return None, "gh not found on PATH"
    except subprocess.TimeoutExpired:
        return None, "gh timed out"
    if proc.returncode != 0:
        lines = (proc.stderr or proc.stdout or "").strip().splitlines()
        return None, (lines[0][:160] if lines else f"gh exited {proc.returncode}")
    try:
        return json.loads(proc.stdout), None
    except ValueError:
        return None, "unreadable output"


def count(value):
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else 1


rules, err = api(f"repos/{repo}/rules/branches/{BRANCH}")
if err:
    if "HTTP 404" in err or "Could not resolve to a Repository" in err:
        print(f"unknown gh cannot see {repo}: export GH_TOKEN for this repository")
    else:
        print(f"unknown {err}")
    sys.exit(0)
if not isinstance(rules, list):
    print("unknown unreadable rules")
    sys.exit(0)

counts, checks = [], []
for rule in rules:
    if not isinstance(rule, dict):
        continue
    params = rule.get("parameters") if isinstance(rule.get("parameters"), dict) else {}
    if rule.get("type") == "pull_request":
        counts.append(count(params.get("required_approving_review_count")))
    elif rule.get("type") == "required_status_checks":
        for c in params.get("required_status_checks") or []:
            if isinstance(c, dict) and isinstance(c.get("context"), str):
                checks.append(c["context"])

classic, err = api(f"repos/{repo}/branches/{BRANCH}/protection")
if err and "HTTP 403" not in err and "HTTP 404" not in err:
    print(f"unknown {err}")
    sys.exit(0)
if isinstance(classic, dict):
    reviews = classic.get("required_pull_request_reviews")
    if isinstance(reviews, dict):
        counts.append(count(reviews.get("required_approving_review_count")))
    status = classic.get("required_status_checks")
    if isinstance(status, dict):
        checks += [c for c in status.get("contexts") or [] if isinstance(c, str)]
        checks += [c["context"] for c in status.get("checks") or []
                   if isinstance(c, dict) and isinstance(c.get("context"), str)]

print(f"required {max(counts)}" if counts else "none")
for c in dict.fromkeys(checks):
    print(f"check {c}")
PY
