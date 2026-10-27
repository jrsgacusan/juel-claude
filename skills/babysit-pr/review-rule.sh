#!/bin/sh
# Says how many approving reviews a base branch's rules require, and which status checks they
# require, so babysit-pr and STAR know whether to wait for an approval at all (#27).
#   review-rule.sh [--workflows] <owner/repo> <base>
# Prints, first:
#   required <n>     a rule asks for n approving reviews (n may be 0: an explicit zero)
#   none             no ruleset, and no readable classic protection, asks for reviews
#   unknown <why>    the rulesets or classic protection could not be read (the only line);
#                    callers keep today's approval rule (pr-verify.sh answers PENDING, never a pass)
# then one line per status check the rules require:
#   check <context>
# then, once each and in this order, when they apply:
#   queue            a ruleset that applies to the branch has a rule of type merge_queue; STAR's
#                    merge.sh reads it to merge through the queue (#212), babysit-pr Phase 4 to
#                    leave its sync triggers, pr-verify.sh to stop asking for an up-to-date head
#   no-merge-group   only with queue and --workflows: no workflow file at the base declares a
#                    merge_group trigger (a key, a list item, or in the value of an on: line;
#                    comments and `if:` conditions do not count), so required checks never report
#                    in the queue (#212). Only merge.sh passes --workflows: the others do not need
#                    the line and keep their timeouts. Nothing is printed when the workflows cannot
#                    be read, or not all within 20 seconds in total: unknown is not a warning
#   strict           a rule requires branches to be up to date before merging
# Sources: the rulesets that apply to the branch (repos/<repo>/rules/branches/<base>, readable
# with read access) and classic branch protection (repos/<repo>/branches/<base>/protection,
# often admin-only: a 403 or 404 there means no classic rule; any other error there, such as a
# 502 or a timeout, is unknown). The strict line comes from a ruleset's required_status_checks
# with strict_required_status_checks_policy true, or classic required_status_checks.strict true.
# The higher count wins. A review rule whose count is missing or
# malformed is read as 1: bad data never relaxes a check.
# A 404 or "Could not resolve to a Repository" on the rulesets (gh signed in to an account that
# cannot see a private repo) prints "unknown gh cannot see <repo>: export GH_TOKEN for this
# repository". Per-call timeout: BABYSIT_GH_TIMEOUT, else STAR_GH_TIMEOUT, seconds (default 60;
# a value that is not a number falls back to 60).
# Exit: 0, or 64 on bad usage.
exec python3 - "$@" <<'PY'
import base64
import json
import os
import re
import subprocess
import sys
import time
from urllib.parse import quote

args = sys.argv[1:]
want_workflows = "--workflows" in args
args = [a for a in args if a != "--workflows"]
if len(args) != 2 or args[0].count("/") != 1 or not all(args[0].split("/")) or not args[1]:
    print("usage: review-rule.sh [--workflows] <owner/repo> <base>", file=sys.stderr)
    sys.exit(64)
repo, base = args
BRANCH = quote(base, safe="/")
try:
    LIMIT = float(os.environ.get("BABYSIT_GH_TIMEOUT") or os.environ.get("STAR_GH_TIMEOUT") or "60")
except ValueError:
    LIMIT = 60.0


def api(path, timeout=LIMIT):
    """(data, None) on success; (None, the first line of the error) otherwise."""
    try:
        proc = subprocess.run(["gh", "api", path], capture_output=True, text=True, timeout=timeout)
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

counts, checks, strict, queue = [], [], False, False
for rule in rules:
    if not isinstance(rule, dict):
        continue
    params = rule.get("parameters") if isinstance(rule.get("parameters"), dict) else {}
    if rule.get("type") == "pull_request":
        counts.append(count(params.get("required_approving_review_count")))
    elif rule.get("type") == "merge_queue":
        queue = True
    elif rule.get("type") == "required_status_checks":
        if params.get("strict_required_status_checks_policy") is True:
            strict = True
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
        if status.get("strict") is True:
            strict = True
        checks += [c for c in status.get("contexts") or [] if isinstance(c, str)]
        checks += [c["context"] for c in status.get("checks") or []
                   if isinstance(c, dict) and isinstance(c.get("context"), str)]

print(f"required {max(counts)}" if counts else "none")
for c in dict.fromkeys(checks):
    print(f"check {c}")


MERGE_GROUP_TRIGGER = re.compile(r"^\s*merge_group\s*:|^\s*-\s*merge_group\b|^\s*on\s*:.*\bmerge_group\b")


def has_merge_group_workflow():
    """True or False when the base's workflow files can all be read within the deadline, None when
    any cannot. merge_group counts only as a trigger, not in a comment or an if: condition."""
    deadline = time.monotonic() + float(os.environ.get("REVIEW_RULE_WORKFLOWS_DEADLINE") or 20)

    def read(path):
        left = deadline - time.monotonic()
        return api(path, min(LIMIT, left)) if left > 0 else (None, "deadline")

    listing, err = read(f"repos/{repo}/contents/.github/workflows?ref={BRANCH}")
    if err or not isinstance(listing, list):
        return None
    for entry in listing:
        name = entry.get("name") if isinstance(entry, dict) else None
        if not isinstance(name, str) or not name.endswith((".yml", ".yaml")):
            continue
        item, err = read(f"repos/{repo}/contents/.github/workflows/{quote(name)}?ref={BRANCH}")
        if err or not isinstance(item, dict) or not isinstance(item.get("content"), str):
            return None
        try:
            text = base64.b64decode(item["content"]).decode("utf-8", "replace")
        except ValueError:
            return None
        if any(MERGE_GROUP_TRIGGER.search(re.sub(r"(^|\s)#.*$", "", l)) for l in text.splitlines()):
            return True
    return False


if queue:
    print("queue")
    if want_workflows and has_merge_group_workflow() is False:
        print("no-merge-group")
if strict:
    print("strict")
PY
