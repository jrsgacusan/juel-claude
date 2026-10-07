#!/bin/sh
# STAR's way to report a problem with STAR itself to the plugin's own GitHub repository, without
# ever posting a project's details there: that repository is public.
#   star-issue.sh [--home H] find "<words>"     -> up to 5 "#<n>\t<title>" lines, or none
#   star-issue.sh [--home H] file --fingerprint <fp> --title "star: ..." --label bug|enhancement --body-file <f>
#   star-issue.sh [--home H] comment <n> --fingerprint <fp> --body-file <f>
#     -> filed <url> | commented <url> | already <url> | failed <why>
# The repository is "repository" in the plugin's .claude-plugin/plugin.json (JUEL_ISSUE_REPO
# overrides it; JUEL_GH names the gh binary). A fingerprint (3 to 60 of a-z, 0-9 and -) names one
# finding: once it is in <home>/issues.log, file and comment print "already <url>" and post
# nothing. The body gets a hidden "star-fingerprint" marker.
# Before anything is posted, the title and body are refused (exit 65, "refused <kind>: <term>",
# nothing posted) when they still contain the project's name, an item name or ref from the
# ledger or a ref's prefix (SPH in SPH-13, matched as written), the repository's path, its remote
# URL, owner or name, the user's login name, git user.name or user.email, or a path under $HOME.
# Matching ignores case (except for a ref prefix) and needs a whole word; the placeholders
# <project>, <repo>, <app>, <item> and ITEM-<n> are what STAR writes instead, and never count.
# Exit: 0 (a gh failure is the "failed" line), 2 the STAR folder or the repository cannot be
# read, 64 usage, 65 refused.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
export STAR_HOME_DEFAULT STAR_SKILL_DIR
exec python3 - "$@" <<'PY'
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

S = os.environ["STAR_SKILL_DIR"]
gh = os.environ.get("JUEL_GH") or "gh"
PLACEHOLDERS = re.compile(r"<(?:project|repo|app|item)>|\bITEM-\d+\b", re.I)


def die(code, msg):
    print(f"star-issue.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def out(line, code=0):
    print(line)
    sys.exit(code)


args, home = sys.argv[1:], os.environ.get("STAR_HOME_DEFAULT") or ""
if args[:1] == ["--home"]:
    if len(args) < 2:
        die(64, "--home needs a folder")
    home, args = args[1], args[2:]
if not args or args[0] not in ("find", "file", "comment"):
    die(64, "usage: star-issue.sh [--home H] find <words> | file ... | comment <n> ...")
cmd, args = args[0], args[1:]


def slug():
    if os.environ.get("JUEL_ISSUE_REPO"):
        return os.environ["JUEL_ISSUE_REPO"]
    try:
        url = json.load(open(os.path.join(S, "..", "..", ".claude-plugin", "plugin.json"))).get("repository") or ""
    except (OSError, ValueError):
        url = ""
    m = re.search(r"github\.com[/:]([^/\s]+/[^/\s]+?)(?:\.git)?/?$", url)
    if not m:
        die(2, "the plugin's plugin.json names no GitHub repository")
    return m.group(1)


def gh_run(*a):
    try:
        p = subprocess.run([gh, *a], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        out(f"failed cannot run gh: {e}")
    if p.returncode != 0:
        out("failed " + (((p.stderr or p.stdout).strip().splitlines() or ["gh failed"])[0])[:150])
    return p.stdout


repo = slug()
if cmd == "find":
    if len(args) != 1 or not args[0].strip():
        die(64, "usage: star-issue.sh find <words>")
    listed = gh_run("issue", "list", "--repo", repo, "--state", "open", "--search", args[0], "--limit", "5",
                    "--json", "number,title")
    try:
        issues = json.loads(listed)
    except ValueError:
        out("failed gh printed no JSON")
    for issue in issues[:5]:
        print(f"#{issue.get('number')}\t{issue.get('title')}")
    if not issues:
        print("none")
    sys.exit(0)

number = None
if cmd == "comment":
    if not args or not args[0].isdigit():
        die(64, "usage: star-issue.sh comment <n> --fingerprint <fp> --body-file <f>")
    number, args = args[0], args[1:]
opts = {}
while args:
    arg = args.pop(0)
    if arg not in ("--fingerprint", "--title", "--label", "--body-file") or not args:
        die(64, f"unknown or empty argument: {arg}")
    opts[arg[2:]] = args.pop(0)
fp = opts.get("fingerprint", "")
if not re.fullmatch(r"[a-z0-9][a-z0-9-]{2,59}", fp):
    die(64, "--fingerprint takes 3 to 60 of a-z, 0-9 and -")
if cmd == "file":
    if not opts.get("title", "").strip():
        die(64, "file needs --title")
    if opts.get("label") not in ("bug", "enhancement"):
        die(64, "--label is bug or enhancement")
try:
    body = open(opts.get("body-file") or "", encoding="utf-8").read()
except OSError:
    die(64, "--body-file must name a readable file")

log = os.path.join(home, "issues.log")
try:
    for line in open(log, encoding="utf-8", errors="replace"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 3 and parts[1] == fp:
            out(f"already {parts[2]}")
except OSError:
    pass


def terms():
    try:
        star = json.load(open(os.path.join(home, "star.json"), encoding="utf-8"))
    except (OSError, ValueError):
        die(2, f"cannot read {home}/star.json")
    project = star.get("project") if isinstance(star.get("project"), dict) else {}
    found, exact = [], []
    if project.get("name"):
        found.append(("project name", project["name"]))
    if project.get("repo"):
        found.append(("repository path", project["repo"]))
        remote = project.get("remote") or "origin"
        git = lambda *a: subprocess.run(["git", "-C", project["repo"], *a], capture_output=True,
                                        text=True).stdout.strip()
        url = git("remote", "get-url", remote)
        if url:
            found.append(("remote URL", url))
            m = re.search(r"[:/]([^/:]+)/([^/]+?)(?:\.git)?$", url)
            if m:
                found += [("repository name", f"{m.group(1)}/{m.group(2)}"), ("repository name", m.group(2)),
                          ("remote owner", m.group(1))]
        for key, kind in (("user.name", "git user name"), ("user.email", "git user email")):
            value = git("config", key)
            if value:
                found.append((kind, value))
    try:
        for line in open(os.path.join(home, "ledger.md"), encoding="utf-8"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if line.startswith("| ") and len(cells) >= 2 and cells[0] not in ("item", ""):
                found += [("item", cells[0])] + ([("ref", cells[1])] if cells[1] not in ("-", cells[0]) else [])
                prefix = re.match(r"([A-Z][A-Z0-9]+)-\d+$", cells[1])
                if prefix:
                    exact.append(("ref prefix", prefix.group(1)))
    except OSError:
        pass
    login = os.path.basename(os.path.expanduser("~").rstrip("/"))
    if len(login) >= 3:
        found.append(("user name", login))
    return [(k, t, False) for k, t in found] + [(k, t, True) for k, t in exact]


def hit(text, term, case_sensitive=False):
    return re.search(r"(?<![A-Za-z0-9])" + re.escape(term) + r"(?![A-Za-z0-9])", text,
                     0 if case_sensitive else re.I) is not None


checked = PLACEHOLDERS.sub(" ", opts.get("title", "") + "\n" + body)
# longest first, so a repository path is named as one even though it ends in the project name
home_dir = os.path.expanduser("~").rstrip("/")
if home_dir and re.search(re.escape(home_dir) + r"(?![A-Za-z0-9_-])", checked):
    out(f"refused home path: {home_dir}", 65)
for kind, term, case_sensitive in sorted(terms(), key=lambda t: -len(t[1])):
    if term and hit(checked, term, case_sensitive):
        out(f"refused {kind}: {term}", 65)

with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
    f.write(body.rstrip("\n") + f"\n\n<!-- star-fingerprint: {fp} -->\n")
    body_file = f.name
try:
    if cmd == "file":
        printed = gh_run("issue", "create", "--repo", repo, "--title", opts["title"], "--label", opts["label"],
                         "--body-file", body_file)
        verb = "filed"
    else:
        printed = gh_run("issue", "comment", number, "--repo", repo, "--body-file", body_file)
        verb = "commented"
finally:
    os.unlink(body_file)
url = next((l for l in reversed(printed.split()) if l.startswith("https://")), "")
if not url:
    out("failed gh printed no URL")
with open(log, "a", encoding="utf-8") as f:
    f.write(f"{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\t{fp}\t{url}\n")
out(f"{verb} {url}")
PY
