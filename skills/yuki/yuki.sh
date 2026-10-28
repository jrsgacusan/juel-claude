#!/bin/sh
# juel:yuki's state and checks. One folder per repository, <git common dir>/yuki: inside .git, so
# it is never committed, and every worktree of the repository (Orca's included) finds the same one.
# --kind yuna (first option, before --home; skills/yuna/yuna.sh passes it) is juel:yuna's: the folder is
# <git common dir>/yuna, the config yuna.json, errors start "yuna.sh:", and the lines marked "yuna" below
# change. Everything not marked behaves the same for both. In this header Y is yuki.sh [--kind K] [--home H].
#   yuki.sh [--home H] path                      the folder (exit 1 outside a git repository)
#   yuki.sh [--home H] init                      create it, and yuki.json when missing; print the folder
#                                                (yuna: yuna.json, with reviewer and silenceHours 72, no bot or
#                                                mergeMethod)
#   yuki.sh [--home H] config [<key> [<json>]]   print yuki.json, one key's value, or set one key
#   yuki.sh [--home H] add <item> [k=v ...]      a new running row; ref, path, branch, terminal, title, pr,
#                                                throwaway (the branch Orca made for a review worktree), rounds
#                                                (yuna: a done row is reopened instead: running, the new values,
#                                                rounds + 1, a "reopened round <n>" progress line; any other
#                                                existing row is refused)
#   yuki.sh [--home H] skip <item> <reason>      remember why a PR or ticket was passed over (items.json "skips",
#                                                keyed by item: reason and at): prints "new" the first time a
#                                                reason is recorded for the item, "seen" after. add clears it.
#   yuki.sh [--home H] skip <item> --clear       drop the item's skip
#   yuki.sh [--home H] set <item> k=v ...        change a row (state, pr, note, ...)
#   yuki.sh [--home H] list [--state <s>]        "<item>\t<state>\t<path>\t<branch>\t<pr>\t<note>" per row
#   yuki.sh [--home H] whoami                    yuna only: gh api user --jq .login; prints the login and stores
#                                                it as reviewer. Exit 1, "yuna.sh: gh: <error>" on stderr
#   yuki.sh [--home H] fresh <pr> ...            yuna only: one line per PR number, in the order given
#       fresh <n>                                review it
#       skip <n> <why>                           <why> is "row <state>" (a running, parked, ended or dropped row
#                                                for review-<n>; a done row never skips), "mine" (reviewer wrote
#                                                it), "draft", "not open", "reviewed <sha7>" (reviewer's newest
#                                                submitted review is on the current head and no review request
#                                                names reviewer directly: a team's never counts), "checked out at <path>"
#                                                (its head branch is checked out in a worktree of this
#                                                repository) or "gh: <error>"
#   yuki.sh [--home H] known                     every item ever added, one per line: the tick skips them
#   yuki.sh [--home H] free                      maxParallel minus the running rows, never below 0
#   yuki.sh [--home H] sweep                     check every running row and apply what it finds:
#       unparked <item> <step>                   the parked worker has a newer real progress line
#       done <item> <pr> removed <path>          merged, and its worktree removed
#       merged <item> <pr> kept <path>: <why>    merged, the worktree left in place (the slot is free)
#       parked <item> <reason>                   the worker parked it, its PR closed unmerged, or its
#                                                worktree is gone: the worktree is kept, the slot is free
#       quiet <item> <age> <step>                no progress line for quietHours and no PR yet; printed
#                                                once, later sweeps print the running line ending " quiet"
#       running <item> <step> <age>[ quiet]
#   yuki.sh [--home H] queue                     follow-ups of merged rows that are not known yet, one per line
#   yuki.sh [--home H] nudge [<item> ...]        read each running row's terminal (default: every one with a
#                                                terminal) and look at the last dialog on its rendered screen;
#                                                at most one line per item, nothing when there is no dialog:
#       nudged <item> permission: <command>      a Bash permission prompt whose command is one screen row, not
#                                                reaching the box's right edge, and read-only (the allowlist in
#                                                read_only(): plain words only, no path outside the worktree, no
#                                                jq or awk, git with no option but --no-pager): the screen is
#                                                read again and, only when the same dialog is still last, Enter
#                                                is sent once (a failing re-read: "unknown <item> <why>")
#       nudged <item> trust|bypass dialog        Claude Code's folder-trust or bypass-permissions dialog on its
#                                                "No, exit" default: Down, then Enter, once
#       prompt <item> new <kind>: <text>         any other dialog, the first tick: kind is permission (a command
#                                                that is not read-only), edit, mcp or dialog; its fingerprint is
#                                                kept in the row's prompt field; nothing is sent
#       prompt <item> <kind>: <text>             the same dialog on a later tick
#       unknown <item> <why>                     the terminal cannot be read (nothing is sent)
#     <text> is one line, 120 characters at most. A nudge appends "<iso> nudged ..." to the progress log;
#     the sweep skips those lines, so a nudge neither changes a row's step nor resets its quiet clock.
#   yuki.sh [--home H] readonly <command>        "yes" (exit 0) or "no: <why>" (exit 1): the allowlist nudge uses
#   yuki.sh [--home H] host                      "ok <x.x> GB" or "low <x.x> GB": free plus inactive memory
#                                                against minFreeGB (exit 0 either way)
#   yuki.sh [--home H] beat <token>              record the coordinator's heartbeat
#   yuki.sh [--home H] owner                     "<token> <minutes since its beat>", or "none"
#   yuki.sh [--home H] sweep (yuna)              the same row-by-row check, with yuna's rules; for each running
#                                                row the first that holds:
#       parked <item> <reason>                   1. the last progress step is "parked" (worktree kept)
#       done <item> <pr> removed <path> merged|closed
#                                                2. the PR merged or closed: worktree removed
#       done <item> <pr> removed <path> approved 3. reviewer's newest submitted review (not PENDING) is
#                                                APPROVED, from this round, and the last step is "approved" or
#                                                the review is 15 minutes old or more
#       done <item> <pr> removed <path> released 4. the last step is "released" (the worker let the PR go)
#       ended <item> <pr> kept <path>: <why>     a removal in 2 to 4 that failed (state "ended": the slot is
#                                                free, the folder kept)
#       parked <item> worktree gone              5.
#       quiet <item> <age> <step>                6. no progress for quietHours and the step is not "wait"
#       running <item> <step> <age>[ quiet]      7.
#   yuki.sh [--home H] deps set <item> [<blocker> ...] --why <text>
#                                                record what <item> needs merged first ([] is none)
#   yuki.sh [--home H] deps unchecked <item> ... the items with no record yet: their blockers are unknown
#   yuki.sh [--home H] deps external <item> ...  the blockers of these items that are not yuki rows, one
#                                                per line: the tick asks the tracker whether each is done
#   yuki.sh [--home H] deps gate <item> ... [--done <ref>[,<ref> ...]]
#       ready <item>                             every blocker is cleared
#       wait <item> on <blocker>[,<blocker>]     the blockers still open, in recorded order
#       cycle <item> <a> <b> ... <item>          its blockers lead back to it: it never starts by itself
#       wait <item> on unchecked                 no record for <item> yet: find its blockers first
#     A blocker is cleared when its row is done or merged, or when --done names it (the tracker says
#     done or canceled). A running, parked or dropped row, an unknown name and an unchecked item are open.
#   yuki.sh [--home H] deps list                 "<item>\t<blocker,...|->\t<why>" per record
#   yuki.sh [--home H] access                    can gh see this repository?
#       ok                                       yes, as things are (GH_TOKEN, tokenCmd or gh's active account)
#       token <login>                            only as <login>: tokenCmd is set to gh auth token --user
#                                                <login> (CLAUDE_ENV_FILE, when set, gets the export line)
#       none <why>                               no logged-in account can (exit 1)
#   yuki.sh [--home H] gh <args...>              gh, and git, with the token tokenCmd prints: the coordinator
#   yuki.sh [--home H] git <args...>             reaches GitHub through these, and never handles the token
#   yuki.sh [--home H] bot                       the bot reviewer's login, or "none": config.reviewBots in
#                                                .claude/workflow.local.json or .claude/workflow.json, else
#                                                the first [bot] login that reviewed one of the last 20
#                                                merged PRs (CI, dependency and deploy bots excluded), or
#                                                greptile-apps[bot] commenting on one; "unknown <why>" exit 1
# A worker writes <home>/progress/<item>.log, one "<iso> <step> <text>" line per step. The steps
# sweep reads: "pr <url>", "parked <reason> plan=<path>", "followup <ref>" and "merged <url> <sha>".
# Yuki's "resumed …" and "nudged …" lines never count as progress. GitHub decides a merge, not
# the log: a row is done only when gh says its PR is MERGED.
# A worktree is removed with `orca worktree rm --worktree path:<path> --json`, never --force, and
# only when `git status --porcelain` in it prints nothing. Under yuna, a row with no throwaway is never
# removed ("no throwaway branch"); one with throwaway first runs
# `git -C <path> checkout <throwaway>` (a failure keeps it: "cannot leave the PR branch: <line>"),
# because orca worktree rm deletes the branch the worktree has checked out and the PR's head branch may
# be one the owner keeps. yuna's progress steps: review <round>, posted <verdict> <url>, wait author,
# approved <url> <sha>, released <reason>, parked <reason>.
# Every gh call carries GH_TOKEN from yuki.json's tokenCmd when GH_TOKEN is not set already: a
# script's gh is the binary, never the owner's shell function, so it sees only gh's active account.
# The plugin's SessionStart hook gives every session in the repository the same token.
# Test seams: ORCA_CLI_COMMAND, YUKI_NOW (epoch seconds), YUKI_FREE_GB.
# Exit: 0; 1 not in a git repository (path, init), a bot lookup GitHub refused or whoami failing;
# 2 the folder or a file in it cannot be read; 64 usage (bot and deps under yuna: "yuna.sh: <sub> is a
# yuki command"; whoami and fresh under yuki likewise).
exec python3 - "$@" <<'PY'
import calendar
import fcntl
import functools
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

KIND, NAME = "yuki", "yuki"
USAGE = ("usage: yuki.sh [--kind yuki|yuna] [--home H] path | init | config [<key> [<json>]]"
         " | add <item> [k=v ...] | set <item> k=v ... | skip <item> <reason>|--clear | list [--state <s>] | known | free | sweep"
         " | nudge [<item> ...] | queue | host | beat <token> | owner | access | gh ... | git ..."
         " | yuki: deps set|unchecked|external|gate|list ... | bot"
         " | yuna: whoami | fresh <pr> ...")
NAME_RE = r"[A-Za-z0-9_#][A-Za-z0-9._#/-]{0,79}"
DEFAULTS = {
    "schema": 1,
    "maxParallel": 5,
    "intervalMinutes": 10,
    "sources": [],
    "bot": None,
    "mergeMethod": None,
    "minFreeGB": 3,
    "quietHours": 2,
    "idleMinutes": 30,
    "unblock": None,
    "repo": None,
    "owner": None,
    "cron": None,
    "tokenCmd": None,
}
YUNA_DEFAULTS = {
    "schema": 1,
    "maxParallel": 5,
    "intervalMinutes": 10,
    "sources": [],
    "minFreeGB": 3,
    "quietHours": 2,
    "repo": None,
    "owner": None,
    "cron": None,
    "tokenCmd": None,
    "reviewer": None,
    "silenceHours": 72,
}
FIELDS = ("ref", "path", "branch", "terminal", "title", "pr", "note", "state", "throwaway", "rounds")
STATES = ("running", "done", "merged", "parked", "dropped")
YUNA_STATES = ("running", "done", "ended", "parked", "dropped")
NOT_REVIEWERS = {"github-actions[bot]", "dependabot[bot]", "renovate[bot]", "linear[bot]",
                 "vercel[bot]", "netlify[bot]", "codecov[bot]", "sonarcloud[bot]",
                 "changeset-bot[bot]", "socket-security[bot]"}


def die(code, msg):
    print(f"{NAME}.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def now():
    return int(os.environ.get("YUKI_NOW") or time.time())


def iso(t=None):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now() if t is None else t))


def parse_iso(text):
    try:
        return calendar.timegm(time.strptime(text, "%Y-%m-%dT%H:%M:%SZ"))
    except (ValueError, OverflowError):
        return None


def age(seconds):
    seconds = max(0, seconds)
    if seconds < 3600:
        return f"{seconds // 60}m"
    if seconds < 86400:
        return f"{seconds // 3600}h{seconds % 3600 // 60:02d}m"
    return f"{seconds // 86400}d{seconds % 86400 // 3600}h"


def git_home():
    try:
        common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    return os.path.join(common, KIND) if common else None


argv = sys.argv[1:]
home = None
while argv[:1] in (["--kind"], ["--home"]):
    if len(argv) < 2:
        die(64, f"{argv[0]} needs a value")
    if argv[0] == "--home":
        home = argv[1]
    elif argv[1] in ("yuki", "yuna"):
        KIND = NAME = argv[1]
    else:
        die(64, "--kind is yuki or yuna")
    argv = argv[2:]
if not argv:
    die(64, USAGE)
cmd, rest = argv[0], argv[1:]
YUNA = KIND == "yuna"
if YUNA and cmd in ("bot", "deps", "unblock", "queue"):
    die(64, f"{cmd} is a yuki command")
if not YUNA and cmd in ("whoami", "fresh"):
    die(64, f"{cmd} is a yuna command")
if home is None:
    home = git_home()
    if home is None and cmd in ("path", "init"):
        die(1, "not inside a git repository")
    if home is None:
        die(2, f"no {NAME} folder: not inside a git repository")
cfg_path = os.path.join(home, f"{NAME}.json")
items_path = os.path.join(home, "items.json")


def read_json(path, default):
    if not os.path.exists(path):
        return default
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        die(2, f"cannot read {path}: {e}")


def write_json(path, data):
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


class Locked:
    def __enter__(self):
        if not os.path.isdir(home):
            die(2, f"no {NAME} folder at {home}: run {NAME}.sh init")
        self.f = open(os.path.join(home, ".lock"), "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


def config():
    data = read_json(cfg_path, None)
    if data is None:
        die(2, f"no {NAME}.json in {home}: run {NAME}.sh init")
    return {**(YUNA_DEFAULTS if YUNA else DEFAULTS), **data}


def items():
    data = read_json(items_path, {"items": []})
    if not isinstance(data.get("items"), list):
        die(2, f"{items_path}: items is not a list")
    return data


def find(data, item):
    for row in data["items"]:
        if row.get("item") == item:
            return row
    return None


def pairs(args):
    out = {}
    for a in args:
        k, sep, v = a.partition("=")
        if not sep or k not in FIELDS:
            die(64, f"expected key=value with a key in {', '.join(FIELDS)}, got {a!r}")
        if k == "state" and v not in (YUNA_STATES if YUNA else STATES):
            die(64, f"state must be one of {', '.join(YUNA_STATES if YUNA else STATES)}")
        if k == "rounds" and not re.fullmatch(r"[0-9]+", v):
            die(64, f"rounds must be digits, got {v!r}")
        out[k] = v
    return out


def rounds_of(row):
    """The row's rounds as a number: 1 when absent or not digits."""
    value = str(row.get("rounds") or "")
    return int(value) if re.fullmatch(r"[0-9]+", value) and int(value) else 1


def repo_dir(cfg):
    repo = cfg.get("repo")
    if repo and os.path.isdir(repo):
        return repo
    return os.path.dirname(os.path.dirname(home.rstrip("/")))


@functools.lru_cache(maxsize=None)
def token_from(command):
    p = subprocess.run(["sh", "-c", command], capture_output=True, text=True, timeout=30)
    return p.stdout.strip() if p.returncode == 0 else None


def without_token():
    return {k: v for k, v in os.environ.items() if k != "GH_TOKEN"}


def gh_env():
    env = dict(os.environ)
    command = config().get("tokenCmd")
    if not env.get("GH_TOKEN") and isinstance(command, str) and command.strip():
        token = token_from(command)
        if token:
            env["GH_TOKEN"] = token
    return env


def gh(args, cwd, env=None):
    try:
        p = subprocess.run(["gh", *args], capture_output=True, text=True, cwd=cwd, timeout=60,
                           env=env or gh_env())
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, str(e)
    if p.returncode != 0:
        return None, (p.stderr.strip().splitlines() or ["gh failed"])[-1]
    return p.stdout, None


def orca_bin():
    env = os.environ.get("ORCA_CLI_COMMAND")
    if env:
        return env
    found = shutil.which("orca")
    if found:
        return found
    for c in ("/Applications/Orca.app/Contents/Resources/bin/orca",
              os.path.expanduser("~/.local/bin/orca"), "/opt/homebrew/bin/orca"):
        if os.access(c, os.X_OK):
            return c
    return None


PROGRESS_SKIP = ("nudged", "resumed")


def real_lines(lines):
    return [line for line in lines if line.partition(" ")[2].partition(" ")[0] not in PROGRESS_SKIP]


def split_plan(text):
    match = re.search(r"^(.*) plan=(\S+)$", text)
    return (match.group(1), match.group(2)) if match else (text, None)


def max_phase(lines):
    phases = [int(match[1]) for line in real_lines(lines)
              if (match := re.match(r"^\S+ phase(\d+)\b", line))]
    return max(phases, default=0)


def last_progress(item):
    path = os.path.join(home, "progress", f"{item}.log")
    try:
        with open(path) as f:
            lines = [l.rstrip("\n") for l in f if l.strip()]
    except OSError:
        lines = []
    steps = real_lines(lines)
    if not steps:
        return None, None, None, lines
    stamp, _, tail = steps[-1].partition(" ")
    step, _, text = tail.partition(" ")
    return parse_iso(stamp) or int(os.path.getmtime(path)), step, text, lines


def pr_of(row, lines, cfg):
    if row.get("pr"):
        return row["pr"], None
    for line in reversed(lines):
        parts = line.split(" ")
        if len(parts) >= 3 and parts[1] == "pr" and parts[2].startswith("http"):
            return parts[2], None
    branch = row.get("branch")
    if not branch:
        return None, None
    out, err = gh(["pr", "list", "--head", branch, "--state", "all", "--json", "url",
                   "--limit", "1"], repo_dir(cfg))
    if err:
        return None, err
    try:
        found = json.loads(out or "[]")
    except ValueError:
        return None, "gh printed no JSON"
    return (found[0]["url"] if found else None), None


def remove(row):
    path = row.get("path") or ""
    if not path or not os.path.isdir(path):
        return True, "already gone"
    status = subprocess.run(["git", "-C", path, "status", "--porcelain"], capture_output=True, text=True)
    if status.returncode != 0:
        return False, "git status failed"
    if status.stdout.strip():
        return False, "uncommitted changes"
    if YUNA:
        # orca worktree rm deletes the branch the worktree has checked out: leave the PR's head branch first,
        # and keep the folder when there is no throwaway branch to leave for
        if not row.get("throwaway"):
            return False, "no throwaway branch"
        left = subprocess.run(["git", "-C", path, "checkout", row["throwaway"]], capture_output=True, text=True)
        if left.returncode != 0:
            first = (left.stderr.strip().splitlines() or ["git checkout failed"])[0]
            return False, f"cannot leave the PR branch: {first}"
    orca = orca_bin()
    if not orca:
        return False, "orca not found"
    p = subprocess.run([orca, "worktree", "rm", "--worktree", f"path:{path}", "--json"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        why = "orca worktree rm failed"
        try:
            why = json.loads(p.stdout).get("error", {}).get("message") or why
        except (ValueError, AttributeError):
            pass
        return False, why
    return True, "removed"


def park(row, reason):
    note, plan = split_plan(reason)
    row.update(state="parked", note=note, parkedAt=iso(), updated=iso())
    if plan:
        row["plan"] = plan
    else:
        row.pop("plan", None)
    return f"parked {row['item']} {note}"


def sweep():
    cfg = config()
    if YUNA:
        return yuna_sweep(cfg)
    with Locked():
        data = items()
        out = []
        for row in data["items"]:
            item = row["item"]
            stamp, step, text, lines = last_progress(item)
            if row.get("state") == "parked":
                parked_at = parse_iso(row.get("parkedAt") or row.get("updated") or "")
                if step and step != "parked" and stamp and parked_at and stamp > parked_at:
                    row.update(state="running", note="", updated=iso())
                    out.append(f"unparked {item} {step}")
                continue
            if row.get("state") != "running":
                continue
            followups = [line.partition(" ")[2].partition(" ")[2].strip()
                         for line in lines if line.partition(" ")[2].partition(" ")[0] == "followup"]
            if followups and followups[-1]:
                row["followup"] = followups[-1]
            resumed = parse_iso(row.get("resumed") or "")
            if step == "parked" and (resumed is None or (stamp is not None and stamp > resumed)):
                out.append(park(row, text or "parked by the worker"))
                continue
            pr, err = pr_of(row, lines, cfg)
            if pr:
                row["pr"] = pr
                view, err = gh(["pr", "view", pr, "--json", "state"], repo_dir(cfg))
                state = None
                if view:
                    try:
                        state = json.loads(view).get("state")
                    except ValueError:
                        err = "gh printed no JSON"
                if state == "MERGED":
                    ok, why = remove(row)
                    if ok:
                        row.update(state="done", note=why, updated=iso())
                        out.append(f"done {item} {pr} removed {row.get('path') or '-'}")
                    else:
                        row.update(state="merged", note=f"kept: {why}", updated=iso())
                        out.append(f"merged {item} {pr} kept {row.get('path') or '-'}: {why}")
                    continue
                if state == "CLOSED":
                    out.append(park(row, "PR closed without a merge"))
                    continue
            if row.get("path") and not os.path.isdir(row["path"]):
                out.append(park(row, "worktree gone"))
                continue
            work_since = stamp if stamp is not None else parse_iso(row.get("added") or "") or now()
            since = max(work_since, resumed) if resumed is not None else work_since
            label = step or "spawned"
            if err:
                label = f"{label} (gh: {err})"
            quiet = not pr and now() - since >= float(cfg.get("quietHours") or 2) * 3600
            if quiet and row.get("note") != "quiet":
                row.update(note="quiet", updated=iso())
                out.append(f"quiet {item} {age(now() - since)} {label}")
                continue
            if not quiet and row.get("note") == "quiet":
                row.update(note="", updated=iso())
            out.append(f"running {item} {label} {age(now() - since)}{' quiet' if quiet else ''}")
        write_json(items_path, data)
    for line in out:
        print(line)


def pr_number(row, pr):
    tail = (pr or "").rstrip("/").rsplit("/", 1)[-1]
    return tail if tail.isdigit() else str(row.get("ref") or "")


def queue():
    rows = items()["items"]
    known = {row.get("item") for row in rows}
    known.update(row.get("ref") for row in rows if row.get("ref"))
    seen = set()
    for row in rows:
        ref = row.get("followup")
        if row.get("state") in ("done", "merged") and ref and ref not in known and ref not in seen:
            print(ref)
            seen.add(ref)


def submitted_reviews(number, cfg):
    """(the reviews of the PR as dicts, error): gh prints one JSON object per line."""
    out, err = gh(["api", f"repos/{{owner}}/{{repo}}/pulls/{number}/reviews", "--paginate", "--jq", ".[]"],
                  repo_dir(cfg))
    if err:
        return None, err
    found = []
    for line in (out or "").splitlines():
        try:
            review = json.loads(line)
        except ValueError:
            continue
        if isinstance(review, dict):
            found.append(review)
    return found, None


def newest_review(reviews, login):
    """The login's newest submitted review (any state but PENDING), or None."""
    mine = [r for r in reviews if str((r.get("user") or {}).get("login") or "").lower() == str(login or "").lower()
            and r.get("state") != "PENDING" and r.get("submitted_at")]
    return max(mine, key=lambda r: r["submitted_at"]) if mine else None


def yuna_sweep(cfg):
    reviewer = cfg.get("reviewer")
    with Locked():
        data = items()
        out = []

        def finish(row, pr, why):
            ok, note = remove(row)
            if ok:
                row.update(state="done", note=note, updated=iso())
                out.append(f"done {row['item']} {pr} removed {row.get('path') or '-'} {why}")
            else:
                row.update(state="ended", note=f"kept: {note}", updated=iso())
                out.append(f"ended {row['item']} {pr} kept {row.get('path') or '-'}: {note}")

        for row in data["items"]:
            if row.get("state") != "running":
                continue
            item = row["item"]
            stamp, step, text, lines = last_progress(item)
            if step == "parked":
                out.append(park(row, text or "parked by the worker"))
                continue
            pr, err = pr_of(row, lines, cfg)
            if pr:
                row["pr"] = pr
                view, err = gh(["pr", "view", pr, "--json", "state"], repo_dir(cfg))
                state = None
                if view:
                    try:
                        state = json.loads(view).get("state")
                    except ValueError:
                        err = "gh printed no JSON"
                if state in ("MERGED", "CLOSED"):
                    finish(row, pr, state.lower())
                    continue
                if reviewer:
                    reviews, rerr = submitted_reviews(pr_number(row, pr), cfg)
                    err = err or rerr
                    newest = newest_review(reviews or [], reviewer)
                    if newest and newest.get("state") == "APPROVED":
                        # an approval older than this round (a reopened row) is not this round's
                        started = parse_iso(row.get("started") or row.get("added") or "") or 0
                        at = parse_iso(newest["submitted_at"]) or 0
                        if at >= started - 60 and (step == "approved" or now() - at >= 15 * 60):
                            finish(row, pr, "approved")
                            continue
            if step == "released":
                finish(row, pr or "-", "released")
                continue
            if row.get("path") and not os.path.isdir(row["path"]):
                out.append(park(row, "worktree gone"))
                continue
            since = stamp if stamp is not None else parse_iso(row.get("added") or "") or now()
            label = step or "spawned"
            if err:
                label = f"{label} (gh: {err})"
            quiet = step != "wait" and now() - since >= float(cfg.get("quietHours") or 2) * 3600
            if quiet and row.get("note") != "quiet":
                row.update(note="quiet", updated=iso())
                out.append(f"quiet {item} {age(now() - since)} {label}")
                continue
            if not quiet and row.get("note") == "quiet":
                row.update(note="", updated=iso())
            out.append(f"running {item} {label} {age(now() - since)}{' quiet' if quiet else ''}")
        write_json(items_path, data)
    for line in out:
        print(line)


def whoami():
    cfg = config()
    out, err = gh(["api", "user", "--jq", ".login"], repo_dir(cfg))
    login = (out or "").strip()
    if err or not login:
        die(1, f"gh: {err or 'no login'}")
    with Locked():
        data = read_json(cfg_path, {})
        data["reviewer"] = login
        write_json(cfg_path, data)
    print(login)


def worktree_branches(cfg):
    """{branch: path} of every branch checked out in a worktree of this repository."""
    p = subprocess.run(["git", "-C", repo_dir(cfg), "worktree", "list", "--porcelain"],
                       capture_output=True, text=True)
    found, path = {}, None
    for line in p.stdout.splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):]
        elif line.startswith("branch refs/heads/"):
            found[line[len("branch refs/heads/"):]] = path
    return found


def fresh(numbers):
    cfg = config()
    reviewer = cfg.get("reviewer")
    if not reviewer:
        die(2, "no reviewer in yuna.json: run yuna.sh whoami")
    rows = {r["item"]: r for r in items()["items"]}
    checked_out = None
    for n in numbers:
        if not re.fullmatch(r"[0-9]+", n):
            die(64, f"fresh needs PR numbers, got {n!r}")
        row = rows.get(f"review-{n}")
        if row and row.get("state") != "done":
            print(f"skip {n} row {row.get('state')}")
            continue
        view, err = gh(["pr", "view", n, "--json", "state,isDraft,author,headRefOid,headRefName,reviewRequests"], repo_dir(cfg))
        try:
            pr = json.loads(view) if view else None
        except ValueError:
            pr, err = None, "gh printed no JSON"
        if not isinstance(pr, dict):
            print(f"skip {n} gh: {err or 'gh printed no JSON'}")
            continue
        if str((pr.get("author") or {}).get("login") or "").lower() == reviewer.lower():
            print(f"skip {n} mine")
        elif pr.get("isDraft"):
            print(f"skip {n} draft")
        elif pr.get("state") != "OPEN":
            print(f"skip {n} not open")
        else:
            reviews, err = submitted_reviews(n, cfg)
            if err:
                print(f"skip {n} gh: {err}")
                continue
            newest = newest_review(reviews, reviewer)
            head = pr.get("headRefOid") or ""
            asked = any(str(q.get("login") or "").lower() == reviewer.lower()
                        for q in pr.get("reviewRequests") or [] if isinstance(q, dict))
            if newest and head and newest.get("commit_id") == head and not asked:
                print(f"skip {n} reviewed {head[:7]}")
                continue
            if checked_out is None:
                checked_out = worktree_branches(cfg)
            where = checked_out.get(pr.get("headRefName") or "")
            if where:
                print(f"skip {n} checked out at {where}")
                continue
            print(f"fresh {n}")


# --- nudge (#214): answer what a person need not answer, report the rest ---
READ_ONLY = {"ls", "cat", "head", "tail", "wc", "grep", "egrep", "fgrep", "rg", "find", "sed", "sort",
             "uniq", "cut", "tr", "file", "stat", "du", "df", "pwd", "echo", "printf", "which", "type",
             "command", "test", "realpath", "readlink", "dirname", "basename", "date", "tree",
             "diff", "cmp", "git"}
GIT_READ_ONLY = {"status", "log", "diff", "show", "rev-parse", "ls-files", "ls-tree", "blame", "grep", "cat-file",
                 "branch", "describe", "merge-base"}
GIT_BRANCH_FLAGS = {"-a", "-r", "-v", "-vv", "--all", "--remotes", "--verbose", "--show-current", "--list"}


SAFE_CHARS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:@%+,=*?~-")


def shell_parts(command):
    """The simple commands of a line split on | & and ;, or None when it holds anything the shell could read
    as more than plain words: outside single quotes only SAFE_CHARS, spaces and the separators; inside
    double quotes SAFE_CHARS, spaces and a single quote (so never $, a backslash or a backtick); an open
    quote. Single-quoted text is literal, so it may hold anything."""
    parts, cur, quote = [], [], None
    for c in command:
        if quote == "'":
            quote = None if c == "'" else quote
        elif quote == '"':
            if c == '"':
                quote = None
            elif c not in SAFE_CHARS and c not in " '":
                return None
        elif c in "'\"":
            quote = c
        elif c in "|&;":
            parts.append("".join(cur))
            cur = []
            continue
        elif c not in SAFE_CHARS and c != " ":
            return None
        cur.append(c)
    if quote:
        return None
    parts.append("".join(cur))
    return [p.strip() for p in parts if p.strip()]


def reaches_outside(word):
    """A word that names a path outside the worktree: absolute, home-relative or holding .. . An option's
    name is stripped first, so -f/x and --file=/x count."""
    m = re.match(r"--?[A-Za-z][A-Za-z0-9-]*=?", word)
    return (word[m.end():] if m else word).startswith(("/", "~")) or ".." in word


def sed_script_ok(script):
    """Only commands that print, delete, quit or substitute without w or e flags."""
    i, n = 0, len(script)
    while i < n:
        while i < n and script[i] in " \t\n;{}":
            i += 1
        if i >= n:
            break
        while True:  # addresses: N, $, /re/, \cREc, first~step, addr,addr
            if i >= n:
                return False
            if script[i].isdigit() or script[i] == "$":
                i += 1
                while i < n and (script[i].isdigit() or script[i] in "~"):
                    i += 1
            elif script[i] in "/\\":
                d = script[i + 1] if script[i] == "\\" and i + 1 < n else script[i]
                i += 2 if script[i] == "\\" else 1
                while i < n and script[i] != d:
                    i += 2 if script[i] == "\\" else 1
                i += 1
                while i < n and script[i] in "IM":
                    i += 1
            else:
                break
            if i < n and script[i] == ",":
                i += 1
                continue
            break
        while i < n and script[i] in " !":
            i += 1
        if i >= n:
            return False
        c = script[i]
        i += 1
        if c in "pdPDnNqQ=lgGhHxz":
            while i < n and script[i].isdigit():
                i += 1
        elif c in "sy":
            if i >= n:
                return False
            d = script[i]
            i += 1
            for _ in range(2):
                while i < n and script[i] != d:
                    i += 2 if script[i] == "\\" else 1
                i += 1
            flags = ""
            while i < n and script[i] not in " \t\n;}":
                flags += script[i]
                i += 1
            if c == "y" and flags or re.search(r"[weWE]", flags):
                return False
        elif c in "aic":
            while i < n and script[i] != "\n":
                i += 1
        else:
            return False
    return True


def sed_ok(args):
    scripts, script_given, expect = [], False, False
    for a in args:
        if expect:
            scripts.append(a)
            expect, script_given = False, True
            continue
        if a.startswith("--"):
            if a.startswith("--expression="):
                scripts.append(a.split("=", 1)[1])
                script_given = True
            elif a == "--expression":
                expect = True
            elif a not in ("--quiet", "--silent", "--regexp-extended", "--separate", "--null-data", "--posix",
                           "--unbuffered", "--sandbox", "--debug", "--"):
                return False
        elif a.startswith("-") and len(a) > 1:
            cluster = a[1:]
            if any(ch not in "nErsuze" for ch in cluster):
                return False
            if cluster.endswith("e"):
                expect = True
        elif not script_given:
            scripts.append(a)
            script_given = True
    return not expect and bool(scripts) and all(sed_script_ok(sc) for sc in scripts)


def read_only(command):
    """(True, "") when every part of the command is on the allowlist, else (False, why). A deterministic
    rule, never a judgement over screen text."""
    parts = shell_parts(command or "")
    if not parts:
        return False, "empty or unparseable"
    for part in parts:
        try:
            words = shlex.split(part)
        except ValueError:
            return False, "unparseable"
        if not words:
            return False, "empty part"
        prog, args = words[0], words[1:]
        if "sudo" in words:
            return False, "sudo"
        if any(reaches_outside(w) for w in args):
            return False, "a path outside the worktree"
        if prog not in READ_ONLY:
            return False, f"{prog} is not on the list"
        if prog == "git":
            if args[:1] == ["--no-pager"]:
                args = args[1:]
            if not args or args[0] not in GIT_READ_ONLY:
                return False, "git subcommand"
            sub, args = args[0], args[1:]
            if any(re.match(r"--output|--ext-diff|--textconv|-O|--open-files-in-pager", a) for a in args):
                return False, "git option"
            if sub == "branch" and args and (
                    any(a.startswith("-") and a not in GIT_BRANCH_FLAGS for a in args)
                    or (any(not a.startswith("-") for a in args) and "--list" not in args)):
                return False, "git branch"
        elif prog == "find":
            if any(a in ("-exec", "-execdir", "-delete", "-ok", "-okdir", "-fls") or a.startswith("-fprint")
                   for a in args):
                return False, "find action"
        elif prog == "sed":
            if not sed_ok(args):
                return False, "sed"
        elif prog == "sort":
            if any(re.match(r"-[A-Za-z]*o|--output|--compress-program", a) for a in args):
                return False, "sort output"
        elif prog == "uniq":
            if len([a for a in args if not a.startswith("-") and not a.isdigit()]) > 1:
                return False, "uniq output file"
        elif prog == "tree":
            if any(re.match(r"-[A-Za-z]*o\b|--output", a) for a in args):
                return False, "tree output"
        elif prog == "date":
            if any(re.match(r"-[A-Za-z]*s|--set", a) for a in args):
                return False, "date -s"
        elif prog == "file":
            if any(re.match(r"-[A-Za-z]*C", a) for a in args):
                return False, "file -C"
        elif prog == "rg":
            if any(a.startswith(("--pre", "--hostname-bin")) for a in args):
                return False, "rg runs a program"
        elif prog == "command":
            if args[:1] not in (["-v"], ["-V"]):
                return False, "command"
    return True, ""


BOXCHARS = "│┃|║╭╮╰╯─━═ \t"
Q_ROW = r"\b(do you want to|would you like to)\b.*\?\s*$"
OPT_ROW = r"^(❯\s*)?(\d+)\.\s+(\S.*)$"
MAX_BELOW = 8  # a live dialog is at the bottom of the screen: footer rows only below its options


SHELL_WORDS = {"cd", "eval", "exec", "export", "source", ".", "alias", "set", "unset", "trap", "builtin",
               "command", "if", "for", "while", "case", "function"}


def is_description(row):
    """Prose, not a second row of the command: two words or more, a capital first, no shell syntax, and a
    first word that runs nothing (which() sees through a case-insensitive disk: Npm runs npm)."""
    words = row.split()
    return (len(words) >= 2 and row[0].isupper() and not re.search(r"[|&;<>$`\\{}]", row)
            and not shutil.which(words[0]) and words[0].lower() not in SHELL_WORDS)


class Rows(list):
    """The rendered rows with the box borders stripped; raw keeps them, for the width of the dialog's box."""
    raw = ()


# a command row this close to the box's right edge may be one row of a wrapped command: the renderer breaks
# at the last space that fits, so the next word can be as long as this
WRAP_SLACK = 20


def command_row_fits(rows, header, row):
    """True when the command row stops well short of the dialog's right edge, so it is not a wrapped row. The
    edge is the text width of the box whose top border is above the Bash command header, or, with no border,
    the longest row of the dialog."""
    border = next((r.strip() for r in reversed(rows.raw[:header]) if re.fullmatch(r"[╭┌]─+[╮┐]", r.strip())), None)
    width = len(border) - 4 if border else max(len(r) for r in rows[header:])
    return len(row) <= width - WRAP_SLACK


def clean_text(text, limit):
    return " ".join(text.split())[:limit]


def read_screen(handle):
    """(rows, None) of the rendered screen, or (None, why)."""
    orca = orca_bin()
    if not orca:
        return None, "orca not found"
    try:
        p = subprocess.run([orca, "terminal", "read", "--terminal", handle, "--screen", "--json"],
                           capture_output=True, text=True, timeout=30)
        data = json.loads(p.stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None, "terminal cannot be read"
    result = data.get("result") if isinstance(data, dict) and data.get("ok") is not False else None
    term = result.get("terminal") if isinstance(result, dict) else None
    tail = term.get("tail") if isinstance(term, dict) else None
    if p.returncode != 0 or not isinstance(tail, list) or not tail:
        return None, "terminal cannot be read"
    if term.get("source", "screen") != "screen":
        return None, "no rendered screen"
    rows = Rows(str(l).strip(BOXCHARS) for l in tail)
    rows.raw = [str(l) for l in tail]
    return rows, None


def find_dialog(rows):
    """The last dialog on the rendered screen: None, or a dict with kind (permission, trust, bypass, edit,
    mcp, dialog), text and auto (the nudge it earns: "enter", "down-enter" or None)."""
    sel = next((i for i in range(len(rows) - 1, -1, -1) if re.match(r"^❯\s*\d+\.\s", rows[i])), None)
    if sel is None:
        return None
    num = int(re.match(OPT_ROW, rows[sel]).group(2))
    first = sel
    while num > 1:  # walk up to option 1, allowing one wrapped row between options
        prev = next((k for k in range(first - 1, max(first - 3, -1), -1)
                     if (m := re.match(OPT_ROW, rows[k])) and int(m.group(2)) == num - 1), None)
        if prev is None:
            return None
        first, num = prev, num - 1
    last, number = sel, int(re.match(OPT_ROW, rows[sel]).group(2))
    while True:
        nxt = next((k for k in range(last + 1, min(last + 4, len(rows)))
                    if (m := re.match(OPT_ROW, rows[k])) and int(m.group(2)) == number + 1), None)
        if nxt is None:
            break
        last, number = nxt, number + 1
    if number < 2 or sum(1 for r in rows[last + 1:] if r) > MAX_BELOW + 2:
        return None
    ask = next((k for k in range(first - 1, -1, -1) if rows[k]), None)
    if ask is None or first - ask > 3:
        return None
    question = rows[ask]
    selected = re.match(OPT_ROW, rows[sel]).group(3)
    if re.match(r"no, exit\b", selected, re.IGNORECASE):
        yes_below = any(re.match(OPT_ROW, rows[k]) and re.match(r"yes\b", re.match(OPT_ROW, rows[k]).group(3), re.IGNORECASE)
                        for k in range(sel + 1, last + 1))
        marks = {}
        for kind, pattern in (("trust", r"trust (this|the files in this) folder|do you trust"),
                              ("bypass", r"bypass permissions")):
            at = [k for k, r in enumerate(rows) if re.search(pattern, r, re.IGNORECASE)]
            if at:
                marks[kind] = at[-1]
        if marks and yes_below:
            kind = max(marks, key=marks.get)
            return {"kind": kind, "text": f"{kind} dialog", "auto": "down-enter"}
        return {"kind": "dialog", "text": clean_text(question, 400), "auto": None}
    if re.search(r"\bdo you want to proceed\?", question, re.IGNORECASE) and sel == first \
            and re.match(r"yes\b", re.match(OPT_ROW, rows[first]).group(3), re.IGNORECASE):
        header = next((k for k in range(ask - 1, max(ask - 13, -1), -1)
                       if re.fullmatch(r"bash command", rows[k], re.IGNORECASE)), None)
        if header is not None and not any(re.search(Q_ROW, rows[k], re.IGNORECASE) or re.match(OPT_ROW, rows[k])
                                          for k in range(header + 1, ask)):
            shown = [r for r in rows[header + 1:ask] if r]
            if len(shown) == 2:
                # one command row and its description. A command on more rows is told to a person, whole:
                # its second row could be anything that looks like a description
                command, description = shown
                if is_description(description) and command_row_fits(rows, header, command):
                    ok = read_only(command)[0]
                    return {"kind": "permission", "text": clean_text(command, 2000), "auto": "enter" if ok else None}
            if shown:
                return {"kind": "permission", "text": clean_text(" ".join(shown), 2000), "auto": None}
        return {"kind": "dialog", "text": clean_text(question, 400), "auto": None}
    if re.search(r"do you want to (make this edit|create|overwrite|write)", question, re.IGNORECASE):
        return {"kind": "edit", "text": clean_text(question, 400), "auto": None}
    context = " ".join(rows[max(ask - 3, 0):last + 1])
    if re.search(r"\bmcp\b", context, re.IGNORECASE):
        return {"kind": "mcp", "text": clean_text(question, 400), "auto": None}
    return {"kind": "dialog", "text": clean_text(question, 400), "auto": None}


def send_keys(handle, *keys):
    orca = orca_bin()
    for key in keys:
        extra = ["--enter"] if key == "enter" else ["--text", "\x1b[B"]
        p = subprocess.run([orca, "terminal", "send", "--terminal", handle, *extra],
                           capture_output=True, text=True, timeout=30)
        if p.returncode != 0:
            return False
    return True


def nudge(names):
    cfg = config()
    snapshot = [dict(r) for r in items()["items"]]
    byname = {r["item"]: r for r in snapshot}
    for name in names:
        if name not in byname:
            print(f"unknown {name} no such row")
    todo = ([byname[n] for n in names if n in byname] if names else
            [r for r in snapshot if r.get("state") == "running" and r.get("terminal")])
    out, changes = [], {}
    for row in todo:
        item, handle = row["item"], row.get("terminal")
        if row.get("state") != "running" or not handle:
            out.append(f"unknown {item} {'not running' if row.get('state') != 'running' else 'no terminal'}")
            continue
        rows, why = read_screen(handle)
        if rows is None:
            out.append(f"unknown {item} {why}")
            continue
        dialog = find_dialog(rows)
        if dialog is None:
            changes[item] = None
            continue
        log = None
        if dialog["auto"] == "enter":
            again, why = read_screen(handle)
            if again is None:
                out.append(f"unknown {item} {why}")
                continue
            same = find_dialog(again)
            if not (same and same["kind"] == dialog["kind"] and same["text"] == dialog["text"] and same["auto"]):
                continue
            if not send_keys(handle, "enter"):
                out.append(f"unknown {item} send failed")
                continue
            out.append(f"nudged {item} permission: {dialog['text'][:120]}")
            log = f"nudged permission: {dialog['text'][:80]}"
        elif dialog["auto"] == "down-enter":
            if not send_keys(handle, "down", "enter"):
                out.append(f"unknown {item} send failed")
                continue
            out.append(f"nudged {item} {dialog['text']}")
            log = f"nudged {dialog['text']}"
        else:
            fingerprint = hashlib.sha1(f"{dialog['kind']}\0{dialog['text']}".encode()).hexdigest()[:12]
            seen = row.get("prompt") == fingerprint
            out.append(f"prompt {item} {'' if seen else 'new '}{dialog['kind']}: {dialog['text'][:120]}")
            changes[item] = fingerprint
            continue
        changes[item] = None
        if log:
            os.makedirs(os.path.join(home, "progress"), exist_ok=True)
            with open(os.path.join(home, "progress", f"{item}.log"), "a") as f:
                f.write(f"{iso()} {log}\n")
    if changes:
        with Locked():
            data = items()
            for row in data["items"]:
                if row["item"] in changes:
                    if changes[row["item"]] is None:
                        row.pop("prompt", None)
                    else:
                        row["prompt"] = changes[row["item"]]
            write_json(items_path, data)
    for line in out:
        print(line)


def host():
    cfg = config()
    forced = os.environ.get("YUKI_FREE_GB")
    if forced:
        gb = float(forced)
    elif sys.platform == "darwin":
        text = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
        m = re.search(r"page size of (\d+)", text)
        size = int(m[1]) if m else 4096
        pages = sum(int(m) for m in re.findall(r"Pages (?:free|inactive|speculative):\s+(\d+)", text))
        gb = pages * size / 1024 ** 3
    else:
        gb = 0.0
        try:
            with open("/proc/meminfo") as f:
                m = re.search(r"MemAvailable:\s+(\d+) kB", f.read())
            gb = int(m[1]) / 1024 ** 2 if m else 0.0
        except OSError:
            pass
    print(f"{'ok' if gb >= float(cfg['minFreeGB']) else 'low'} {gb:.1f} GB")


def take(args, flag, need):
    # (the value after <flag>, the args without both), or (None, args) when the flag is absent
    if flag not in args:
        return None, args
    i = args.index(flag)
    if i + 1 >= len(args):
        die(64, need)
    return args[i + 1], args[:i] + args[i + 2:]


def deps(args):
    if not args:
        die(64, USAGE)
    sub, args = args[0], args[1:]
    config()
    if sub == "set":
        why, args = take(args, "--why", "--why needs a reason")
        if not args or not why:
            die(64, "deps set <item> [<blocker> ...] --why <text>")
        item, on = args[0], list(dict.fromkeys(args[1:]))
        for name in [item, *on]:
            if not re.fullmatch(NAME_RE, name):
                die(64, f"not an item name: {name!r}")
        if item in on:
            die(64, f"{item} cannot block itself")
        with Locked():
            data = items()
            data.setdefault("deps", {})[item] = {"on": on, "why": why, "checked": iso()}
            write_json(items_path, data)
        return
    data = items()
    recs = data.get("deps") or {}
    rows = {}
    for row in data["items"]:
        rows[row["item"]] = row
        if row.get("ref"):
            rows.setdefault(row["ref"], row)
    if sub == "list":
        for item, rec in recs.items():
            print(f"{item}\t{','.join(rec.get('on') or []) or '-'}\t{rec.get('why') or '-'}")
    elif sub == "unchecked":
        for item in args:
            if item not in recs:
                print(item)
    elif sub == "external":
        seen = []
        for item in args:
            for b in (recs.get(item) or {}).get("on") or []:
                if b not in rows and b not in seen:
                    seen.append(b)
        for b in seen:
            print(b)
    elif sub == "gate":
        done, args = take(args, "--done", "--done needs a comma-separated list")
        done = {d for d in (done or "").split(",") if d}

        def cleared(b):
            return b in done or (rows.get(b) or {}).get("state") in ("done", "merged")

        def cycle(start):
            stack = [(start, [start])]
            while stack:
                node, path = stack.pop()
                for b in (recs.get(node) or {}).get("on") or []:
                    if cleared(b):
                        continue
                    if b == start:
                        return path + [start]
                    if b not in path:
                        stack.append((b, path + [b]))
            return None

        for item in args:
            if item not in recs:
                print(f"wait {item} on unchecked")
                continue
            loop = cycle(item)
            if loop:
                print(f"cycle {' '.join(loop)}")
                continue
            open_ = [b for b in recs[item].get("on") or [] if not cleared(b)]
            print(f"wait {item} on {','.join(open_)}" if open_ else f"ready {item}")
    else:
        die(64, USAGE)


def access():
    cfg = config()
    cwd = repo_dir(cfg)
    probe = ["api", "repos/{owner}/{repo}", "--jq", ".full_name"]
    out, err = gh(probe, cwd)
    if out and out.strip():
        print("ok")
        return
    status = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True, timeout=30,
                            env=without_token())
    logins = re.findall(r"Logged in to github\.com account ([A-Za-z0-9-]+)", status.stdout + status.stderr)
    for login in dict.fromkeys(logins):
        tok = subprocess.run(["gh", "auth", "token", "--user", login], capture_output=True, text=True,
                             timeout=30, env=without_token())
        if tok.returncode != 0 or not tok.stdout.strip():
            continue
        out, _ = gh(probe, cwd, env={**os.environ, "GH_TOKEN": tok.stdout.strip()})
        if out and out.strip():
            command = f"gh auth token --user {login}"
            with Locked():
                data = read_json(cfg_path, {})
                data["tokenCmd"] = command
                write_json(cfg_path, data)
            env_file = os.environ.get("CLAUDE_ENV_FILE")
            if env_file and not os.environ.get("GH_TOKEN"):
                line = f'export GH_TOKEN="$({command})"'
                try:
                    have = open(env_file).read() if os.path.exists(env_file) else ""
                    if line not in have.splitlines():
                        with open(env_file, "a") as f:
                            f.write(("" if not have or have.endswith("\n") else "\n") + line + "\n")
                except OSError:
                    pass
            print(f"token {login}")
            return
    print(f"none {err or 'gh cannot see this repository'}; tried {', '.join(logins) or 'no logged-in account'}")
    sys.exit(1)


def bot():
    cfg = config()
    cwd = repo_dir(cfg)
    for name in ("workflow.local.json", "workflow.json"):
        path = os.path.join(cwd, ".claude", name)
        if os.path.exists(path):
            try:
                bots = (json.load(open(path)).get("config") or {}).get("reviewBots") or []
            except (OSError, ValueError):
                bots = []
            if bots:
                print(bots[0])
                return
    out, err = gh(["pr", "list", "--state", "merged", "--limit", "20", "--json", "number",
                   "--jq", ".[].number"], cwd)
    if err:
        print(f"unknown {err}")
        sys.exit(1)
    for n in (out or "").split():
        logins, err = gh(["api", f"repos/{{owner}}/{{repo}}/pulls/{n}/reviews", "--paginate",
                          "--jq", ".[].user.login"], cwd)
        if err:
            print(f"unknown {err}")
            sys.exit(1)
        for login in (logins or "").split():
            if login.endswith("[bot]") and login not in NOT_REVIEWERS:
                print(login)
                return
        comments, err = gh(["api", f"repos/{{owner}}/{{repo}}/issues/{n}/comments", "--paginate",
                            "--jq", ".[].user.login"], cwd)
        if err:
            print(f"unknown {err}")
            sys.exit(1)
        if "greptile-apps[bot]" in (comments or "").split():
            print("greptile-apps[bot]")
            return
    print("none")


if cmd == "path":
    print(home)
elif cmd == "init":
    os.makedirs(os.path.join(home, "progress"), exist_ok=True)
    with Locked():
        if not os.path.exists(cfg_path):
            repo = os.path.dirname(os.path.dirname(home.rstrip("/")))
            write_json(cfg_path, {**(YUNA_DEFAULTS if YUNA else DEFAULTS), "repo": repo})
        if not os.path.exists(items_path):
            write_json(items_path, {"items": []})
    print(home)
elif cmd == "config":
    cfg = config()
    if not rest:
        print(json.dumps(cfg, indent=2))
    elif len(rest) == 1:
        v = cfg.get(rest[0])
        print(v if isinstance(v, str) else json.dumps(v))
    elif len(rest) == 2:
        try:
            value = json.loads(rest[1])
        except ValueError:
            die(64, f"{rest[1]!r} is not JSON (quote a string: '\"squash\"')")
        if rest[0] == "maxParallel" and not (isinstance(value, int) and 1 <= value <= 20):
            die(64, "maxParallel must be a whole number from 1 to 20")
        if rest[0] == "idleMinutes" and not (type(value) is int and 5 <= value <= 1440):
            die(64, "idleMinutes must be a whole number from 5 to 1440")
        if rest[0] == "unblock" and value not in (None, "merge"):
            die(64, 'unblock is null or "merge"')
        with Locked():
            data = read_json(cfg_path, {})
            data[rest[0]] = value
            write_json(cfg_path, data)
    else:
        die(64, USAGE)
elif cmd in ("add", "set"):
    if not rest or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,79}", rest[0]):
        die(64, f"{cmd} needs an item name (letters, digits, . _ -)")
    item, values = rest[0], pairs(rest[1:])
    config()
    with Locked():
        data = items()
        row = find(data, item)
        if cmd == "add":
            data.get("skips", {}).pop(item, None)
            if row and YUNA and row.get("state") == "done":
                # a PR approved and then pushed again comes back: a new round on the same row
                ref = values.pop("ref", None)
                for stale in ("note", "prompt"):
                    row.pop(stale, None)
                rounds = rounds_of(row) + 1
                row.update(values, state="running", rounds=rounds, started=iso(), updated=iso())
                if ref:
                    row["ref"] = ref
                os.makedirs(os.path.join(home, "progress"), exist_ok=True)
                with open(os.path.join(home, "progress", f"{item}.log"), "a") as f:
                    f.write(f"{iso()} reopened round {rounds}\n")
                write_json(items_path, data)
                sys.exit(0)
            if row:
                die(64, f"{item} is already a row ({row.get('state')})")
            data["items"].append({"item": item, "ref": values.pop("ref", item), "state": "running",
                                  **values, "added": iso(), "updated": iso()})
        else:
            if not row:
                die(64, f"no row {item}")
            if not values:
                die(64, "set needs at least one key=value")
            row.update(values, updated=iso())
        write_json(items_path, data)
elif cmd == "skip":
    if not rest or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,79}", rest[0]) or len(rest) != 2 or not rest[1]:
        die(64, "skip needs <item> and a reason, or <item> --clear")
    item, reason = rest
    config()
    with Locked():
        data = items()
        skips = data.setdefault("skips", {})
        if reason == "--clear":
            skips.pop(item, None)
        elif item in skips:
            print("seen")
            sys.exit(0)
        else:
            skips[item] = {"reason": reason, "at": iso()}
            print("new")
        write_json(items_path, data)
elif cmd == "list":
    state = None
    if rest[:1] == ["--state"] and len(rest) == 2:
        state = rest[1]
    elif rest:
        die(64, USAGE)
    for row in items()["items"]:
        if state and row.get("state") != state:
            continue
        print("\t".join(row.get(k) or "-" for k in ("item", "state", "path", "branch", "pr", "note")))
elif cmd == "known":
    for row in items()["items"]:
        print(row["item"])
        if row.get("ref") and row["ref"] != row["item"]:
            print(row["ref"])
elif cmd == "queue":
    queue()
elif cmd == "free":
    cfg = config()
    running = sum(1 for r in items()["items"] if r.get("state") == "running")
    print(max(0, int(cfg["maxParallel"]) - running))
elif cmd == "sweep":
    sweep()
elif cmd == "nudge":
    nudge(rest)
elif cmd == "whoami":
    whoami()
elif cmd == "fresh":
    fresh(rest)
elif cmd == "readonly":
    ok, why = read_only(" ".join(rest))
    print("yes" if ok else f"no: {why}")
    sys.exit(0 if ok else 1)
elif cmd == "host":
    host()
elif cmd == "beat":
    if len(rest) != 1:
        die(64, "beat needs the coordinator's token")
    with Locked():
        data = read_json(cfg_path, {})
        data["owner"] = {"token": rest[0], "beat": iso()}
        write_json(cfg_path, data)
elif cmd == "owner":
    owner = config().get("owner") or {}
    beat = parse_iso(owner.get("beat") or "")
    print(f"{owner['token']} {(now() - beat) // 60}" if owner.get("token") and beat else "none")
elif cmd == "deps":
    deps(rest)
elif cmd == "access":
    access()
elif cmd in ("gh", "git"):
    try:
        os.execvpe(cmd, [cmd, *rest], gh_env())
    except OSError as e:
        die(2, f"cannot run {cmd}: {e}")
elif cmd == "bot":
    bot()
else:
    die(64, USAGE)
PY
