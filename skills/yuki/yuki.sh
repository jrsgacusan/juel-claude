#!/bin/sh
# juel:yuki's state and checks. One folder per repository, <git common dir>/yuki: inside .git, so
# it is never committed, and every worktree of the repository (Orca's included) finds the same one.
#   yuki.sh [--home H] path                      the folder (exit 1 outside a git repository)
#   yuki.sh [--home H] init                      create it, and yuki.json when missing; print the folder
#   yuki.sh [--home H] config [<key> [<json>]]   print yuki.json, one key's value, or set one key
#   yuki.sh [--home H] add <item> [k=v ...]      a new running row; ref, path, branch, terminal, title
#   yuki.sh [--home H] set <item> k=v ...        change a row (state, pr, note, ...)
#   yuki.sh [--home H] list [--state <s>]        "<item>\t<state>\t<path>\t<branch>\t<pr>\t<note>" per row
#   yuki.sh [--home H] known                     every item ever added, one per line: the tick skips them
#   yuki.sh [--home H] free                      maxParallel minus the running rows, never below 0
#   yuki.sh [--home H] sweep                     check every running row and apply what it finds:
#       done <item> <pr> removed <path>          merged, and its worktree removed
#       merged <item> <pr> kept <path>: <why>    merged, the worktree left in place (the slot is free)
#       parked <item> <reason>                   the worker parked it, its PR closed unmerged, or its
#                                                worktree is gone: the worktree is kept, the slot is free
#       quiet <item> <age> <step>                no progress line for quietHours and no PR yet; printed
#                                                once, later sweeps print the running line ending " quiet"
#       running <item> <step> <age>[ quiet]
#   yuki.sh [--home H] host                      "ok <x.x> GB" or "low <x.x> GB": free plus inactive memory
#                                                against minFreeGB (exit 0 either way)
#   yuki.sh [--home H] beat <token>              record the coordinator's heartbeat
#   yuki.sh [--home H] owner                     "<token> <minutes since its beat>", or "none"
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
# sweep reads: "pr <url>", "parked <reason>" and "merged <url> <sha>". GitHub decides a merge, not
# the log: a row is done only when gh says its PR is MERGED.
# A worktree is removed with `orca worktree rm --worktree path:<path> --json`, never --force, and
# only when `git status --porcelain` in it prints nothing.
# Every gh call carries GH_TOKEN from yuki.json's tokenCmd when GH_TOKEN is not set already: a
# script's gh is the binary, never the owner's shell function, so it sees only gh's active account.
# The plugin's SessionStart hook gives every session in the repository the same token.
# Test seams: ORCA_CLI_COMMAND, YUKI_NOW (epoch seconds), YUKI_FREE_GB.
# Exit: 0; 1 not in a git repository (path, init) or a bot lookup GitHub refused; 2 the folder or a
# file in it cannot be read; 64 usage.
exec python3 - "$@" <<'PY'
import calendar
import fcntl
import functools
import json
import os
import re
import shutil
import subprocess
import sys
import time

USAGE = ("usage: yuki.sh [--home H] path | init | config [<key> [<json>]] | add <item> [k=v ...]"
         " | set <item> k=v ... | list [--state <s>] | known | free | sweep | host | beat <token>"
         " | owner | deps set|unchecked|external|gate|list ... | access | gh ... | git ... | bot")
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
    "repo": None,
    "owner": None,
    "cron": None,
    "tokenCmd": None,
}
FIELDS = ("ref", "path", "branch", "terminal", "title", "pr", "note", "state")
STATES = ("running", "done", "merged", "parked", "dropped")
NOT_REVIEWERS = {"github-actions[bot]", "dependabot[bot]", "renovate[bot]", "linear[bot]",
                 "vercel[bot]", "netlify[bot]", "codecov[bot]", "sonarcloud[bot]",
                 "changeset-bot[bot]", "socket-security[bot]"}


def die(code, msg):
    print(f"yuki.sh: {msg}", file=sys.stderr)
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
    return os.path.join(common, "yuki") if common else None


argv = sys.argv[1:]
home = None
if argv[:1] == ["--home"]:
    if len(argv) < 2:
        die(64, "--home needs a folder")
    home, argv = argv[1], argv[2:]
if not argv:
    die(64, USAGE)
cmd, rest = argv[0], argv[1:]
if home is None:
    home = git_home()
    if home is None and cmd in ("path", "init"):
        die(1, "not inside a git repository")
    if home is None:
        die(2, "no yuki folder: not inside a git repository")
cfg_path = os.path.join(home, "yuki.json")
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
            die(2, f"no yuki folder at {home}: run yuki.sh init")
        self.f = open(os.path.join(home, ".lock"), "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


def config():
    data = read_json(cfg_path, None)
    if data is None:
        die(2, f"no yuki.json in {home}: run yuki.sh init")
    return {**DEFAULTS, **data}


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
        if k == "state" and v not in STATES:
            die(64, f"state must be one of {', '.join(STATES)}")
        out[k] = v
    return out


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


def last_progress(item):
    path = os.path.join(home, "progress", f"{item}.log")
    try:
        with open(path) as f:
            lines = [l.rstrip("\n") for l in f if l.strip()]
    except OSError:
        lines = []
    if not lines:
        return None, None, None, []
    stamp, _, tail = lines[-1].partition(" ")
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
    row.update(state="parked", note=reason, updated=iso())
    return f"parked {row['item']} {reason}"


def sweep():
    cfg = config()
    with Locked():
        data = items()
        out = []
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
            since = stamp if stamp is not None else parse_iso(row.get("added") or "") or now()
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
            write_json(cfg_path, {**DEFAULTS, "repo": repo})
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
elif cmd == "free":
    cfg = config()
    running = sum(1 for r in items()["items"] if r.get("state") == "running")
    print(max(0, int(cfg["maxParallel"]) - running))
elif cmd == "sweep":
    sweep()
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
