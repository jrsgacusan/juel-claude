#!/bin/sh
# Starts one STAR stage for one ledger row: everything "Fill slots" does, in one place, so no
# session hand-rolls it.
#   stage-start.sh [--home H] [--round <k>] brief|build|review|fix|screen|babysit|post <item>
# Prints one line:
#   started task=<id> dispatch=<id>[ fallback <model>: <why>]
#   hold memory <gb>          under 3 GB free + inactive: nothing was started
#   hold trust <path>         Claude Code's first-run dialogs for <path> could not be cleared
#   failed <step>: <why>      step: brief, worktree, branch, env, in-use, task-create, worker-start
# In order: the memory check; for build, the worktree (reuse one already on the brief's branch,
# else orca worktree create, then put it on the brief's branch, copy the main checkout's
# git-ignored environment files, and add a .git/info/exclude line when the worktree sits inside
# the repository); for a claude worker whose path Claude Code's config does not list as trusted,
# the first-run dialogs, cleared in a throwaway terminal the way orca-ship-tickets does (only
# while "No, exit" is on screen, Down then Enter, at most 3 rounds); the prompt; then task-create
# and worker-start. Both carry a --retry-request id, so a STAR that died between a call and
# recording its result gets the same task or dispatch back from Orca, never a second one.
# The row is written through ledger.sh before task-create (state, stage, round, counters.start
# and counters.live), after it (task) and after worker-start (dispatch, live cleared). A row whose
# counters still hold live= for this stage is a start that died: it is replayed with the same ids.
# --round defaults to the row's round, plus one for a review that is not a replay.
# A brief with existingPr: <url> and no local branch yet gets its branch fetched from the
# project's remote and checked out tracking it (an open PR's head), instead of a renamed branch.
# Every spec sent is one line: the reviewer's instructions go to specs/<project>/ and the spec
# points at them. A failed worker-start is retried once: with --retry-of, one effort level lower
# when the effort was refused, or on "worker" ("reviewer" for review) when the model was refused.
# Test seams: ORCA_CLI_COMMAND, STAR_FREE_GB, STAR_TRUST_POLL (seconds), CLAUDE_CONFIG_DIR.
# Exit: 0 with one of the lines above; 2 the STAR folder or star.json cannot be read; 4 no row for
# the item; 64 usage.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
export STAR_HOME_DEFAULT STAR_SKILL_DIR
exec python3 - "$@" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
import time

S = os.environ["STAR_SKILL_DIR"]
RUNNING = {"brief": "briefing", "build": "building", "review": "reviewing", "fix": "fixing",
           "screen": "screening", "babysit": "babysitting", "post": "posting"}
WAITING = {"brief": "inbox", "build": "queued", "review": "pr-draft", "fix": "fix-queued",
           "screen": "screen-queued", "babysit": "babysit-queued", "post": "post-queued"}
EFFORTS = ["max", "xhigh", "high", "medium", "low"]
REFUSED = ("not installed", "unknown agent", "model", "access", "credit", "quota", "not available")
ENV_NAMES = (".env", ".envrc", ".npmrc", ".tool-versions")
orca = os.environ.get("ORCA_CLI_COMMAND") or "orca"


def die(code, msg):
    print(f"stage-start.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def out(line):
    print(line)
    sys.exit(0)


class Ran:
    def __init__(self, returncode, stdout, stderr):
        self.returncode, self.stdout, self.stderr = returncode, stdout, stderr


def run(cmd, timeout=60, cwd=None):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd)
        return Ran(p.returncode, p.stdout or "", p.stderr or "")
    except subprocess.TimeoutExpired:
        return Ran(124, "", f"{cmd[0]} ran past {timeout} s")
    except OSError as e:
        return Ran(127, "", f"cannot run {cmd[0]}: {e.strerror}")


def lenient(text):
    try:
        return json.loads(text, strict=False)
    except ValueError:
        return None


def why(proc):
    data = lenient(proc.stdout)
    if isinstance(data, dict):
        error = data.get("error")
        if isinstance(error, dict) and (error.get("message") or error.get("code")):
            return str(error.get("message") or error.get("code"))[:120]
        if isinstance(error, str) and error:
            return error[:120]
    lines = (proc.stderr.strip() or proc.stdout.strip()).splitlines()
    return (lines[0] if lines else f"exit {proc.returncode}")[:120]


def ids(text, prefix):
    """The first id with this prefix under an id, taskId or dispatchId key."""
    found = []

    def walk(value):
        if isinstance(value, dict):
            for key, v in value.items():
                if key in ("id", "taskId", "dispatchId") and isinstance(v, str) and v.startswith(prefix):
                    found.append(v)
                walk(v)
        elif isinstance(value, list):
            for v in value:
                walk(v)

    walk(lenient(text))
    if not found:
        found = re.findall(r'"(?:id|taskId|dispatchId)"\s*:\s*"(' + re.escape(prefix) + r'[A-Za-z0-9_-]+)"', text)
    return found[0] if found else None


home, round_arg, args, positional = os.environ.get("STAR_HOME_DEFAULT") or "", None, sys.argv[1:], []
while args:
    arg = args.pop(0)
    if arg in ("--home", "--round"):
        if not args:
            die(64, f"{arg} needs a value")
        value = args.pop(0)
        if arg == "--home":
            home = value
        elif not value.isdigit():
            die(64, "--round takes a number")
        else:
            round_arg = int(value)
    elif arg.startswith("-"):
        die(64, f"unknown argument: {arg}")
    else:
        positional.append(arg)
if len(positional) != 2 or positional[0] not in RUNNING:
    die(64, "usage: stage-start.sh [--home H] [--round <k>] brief|build|review|fix|screen|babysit|post <item>")
stage, item = positional
if not home:
    die(2, "no STAR folder: pass --home, or run inside a project")
try:
    star = json.load(open(os.path.join(home, "star.json"), encoding="utf-8"))
except (OSError, ValueError) as e:
    die(2, f"cannot read star.json ({e})")
project = star.get("project") if isinstance(star.get("project"), dict) else {}
repo, name = project.get("repo"), project.get("name")
if not repo or not name:
    die(2, "star.json has no project: run star-home.sh init")


def ledger(*a):
    proc = run(["sh", os.path.join(S, "ledger.sh"), "--home", home, *a], 30)
    if proc.returncode == 4:
        die(4, f"no ledger row for {item}")
    if proc.returncode != 0:
        die(2, "ledger.sh: " + (proc.stderr.strip() or f"exit {proc.returncode}"))
    return proc.stdout


row = dict(l.split("=", 1) for l in ledger("get", item).splitlines() if "=" in l)
counters = {} if row["counters"] == "-" else dict(p.split("=", 1) for p in row["counters"].split() if "=" in p)
live = counters.get("live")
replay = live is not None and row["stage"] == stage
if round_arg is not None:
    round_ = round_arg
elif stage == "review" and not replay:
    round_ = int(row["round"]) + 1
else:
    round_ = int(row["round"])
replay = replay and str(round_) == row["round"]
brief = os.path.join(home, "briefs", name, f"{item}.md")
reviews = os.path.join(home, "reviews", name)
gates = os.path.join(home, "gates", name)
started_row = False


def finish(line):
    if started_row:
        ledger("set", item, "counters.live=-")
    out(line)


def frontmatter(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return None
    m = re.match(r"﻿?---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
    found = {}
    for line in (m.group(1).splitlines() if m else []):
        k = re.match(r"([A-Za-z_]+):\s*(.*?)\s*(?:#.*)?$", line)
        if k and not line[:1].isspace():
            found[k.group(1)] = k.group(2).strip().strip("\"'")
    return found


def free_gb():
    if os.environ.get("STAR_FREE_GB"):
        return int(os.environ["STAR_FREE_GB"])
    try:
        if sys.platform == "darwin":
            text = run(["vm_stat"], 10).stdout
            page = int(re.search(r"page size of (\d+) bytes", text).group(1))
            pages = sum(int(re.search(rf"^Pages {k}:\s+(\d+)\.", text, re.M).group(1)) for k in ("free", "inactive"))
            return pages * page // 1073741824
        lines = run(["free", "-g"], 10).stdout.splitlines()
        return int(lines[1].split()[lines[0].split().index("available") + 1])
    except (AttributeError, IndexError, ValueError):
        return None


def setting():
    default = {"agent": "claude", "model": "default"}
    fallback = star.get("reviewer" if stage == "review" else "worker")
    fallback = fallback if isinstance(fallback, dict) else default
    stages = star.get("stages") if isinstance(star.get("stages"), dict) else {}
    entry = stages.get(stage)
    return (entry if isinstance(entry, dict) else fallback), fallback


def git(*a, cwd=None):
    return run(["git", "-C", cwd or repo, *a], 120)


def other_row_using(path):
    real = os.path.realpath(path)
    for line in ledger("list").splitlines():
        cells = line.split("\t")
        if (len(cells) >= 5 and cells[0] != item and cells[1] not in ("done", "dropped")
                and cells[4] not in ("", "-") and os.path.realpath(cells[4]) == real):
            return cells[0]
    return None


def exclude_if_inside(wt):
    root, real = os.path.realpath(repo), os.path.realpath(wt)
    if not real.startswith(root + os.sep):
        return
    first = os.path.relpath(real, root).split(os.sep)[0]
    if git("check-ignore", "-q", first + "/").returncode == 0:
        return
    common = git("rev-parse", "--git-common-dir").stdout.strip()
    exclude = os.path.join(os.path.normpath(os.path.join(repo, common)), "info", "exclude")
    line = f"/{first}/"
    try:
        os.makedirs(os.path.dirname(exclude), exist_ok=True)
        have = open(exclude, encoding="utf-8", errors="replace").read() if os.path.exists(exclude) else ""
        if line not in have.splitlines():
            with open(exclude, "a", encoding="utf-8") as f:
                f.write(("" if have.endswith("\n") or not have else "\n") + line + "\n")
    except OSError as e:
        print(f"stage-start.sh: could not add {line} to {exclude} ({e.strerror})", file=sys.stderr)


def copy_env(wt):
    names = [f for f in sorted(os.listdir(repo)) if os.path.isfile(os.path.join(repo, f))
             and (f in ENV_NAMES or f.startswith(".env.") or f.endswith(".local"))]
    names += git("ls-files", "--others", "--ignored", "--exclude-standard", ".claude").stdout.splitlines()
    copied = []
    for f in names:
        target = os.path.join(wt, f)
        # an untracked file that is not ignored is someone's work in progress, not environment
        if not f or os.path.exists(target) or git("check-ignore", "-q", f).returncode != 0:
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(repo, f), target)
        copied.append(target)
    if git("status", "--porcelain", cwd=wt).stdout.strip():
        for t in copied:
            try:
                os.remove(t)
            except OSError:
                pass
        out("failed env: the worktree is not clean after copying environment files")


def build_worktree(fm):
    branch, base = fm.get("branch"), fm.get("baseBranch")
    if not branch or not base:
        out("failed brief: the brief has no branch or baseBranch")
    for block in git("worktree", "list", "--porcelain").stdout.split("\n\n"):
        lines = block.splitlines()
        wt = next((l[len("worktree "):] for l in lines if l.startswith("worktree ")), None)
        # the main checkout is the user's own: a build never runs there, even on the brief's branch
        if wt and os.path.realpath(wt) != os.path.realpath(repo) and f"branch refs/heads/{branch}" in lines:
            other = other_row_using(wt)
            if other:
                out(f"failed in-use: branch {branch} is already being built as {other}")
            ledger("set", item, f"worktree={wt}")
            exclude_if_inside(wt)
            return wt
    repo_id, remote = project.get("orcaRepo"), project.get("remote") or "origin"
    if not repo_id:
        out("failed worktree: star.json has no project.orcaRepo (register the repo: orca repo add)")
    proc = run([orca, "worktree", "create", "--repo", f"id:{repo_id}", "--name", item, "--base-branch",
                f"{remote}/{base}", "--no-parent", "--setup", "run", "--json"], 540)
    data = lenient(proc.stdout)
    result = data.get("result") if isinstance(data, dict) else None
    worktree = result.get("worktree") if isinstance(result, dict) else None
    wt = worktree.get("path") if isinstance(worktree, dict) else None
    if not wt:
        m = re.search(r'"path"\s*:\s*"([^"]+)"', proc.stdout)
        wt = m.group(1) if m else None
    if proc.returncode != 0 or not wt or not os.path.isdir(wt):
        out("failed worktree: " + why(proc))
    ledger("set", item, f"worktree={wt}")
    current = git("rev-parse", "--abbrev-ref", "HEAD", cwd=wt).stdout.strip()
    if current != branch:
        if git("show-ref", "--verify", "--quiet", f"refs/heads/{branch}").returncode == 0:
            r = git("switch", branch, cwd=wt)
            if r.returncode != 0:
                out(f"failed branch: git switch {branch}: {why(r)}")
            if current and current != "HEAD":
                git("branch", "-D", current)
        elif fm.get("existingPr"):
            # an open PR's head branch: build on it, never on a fresh branch of the same name (#33)
            r = git("fetch", remote, branch, cwd=wt)
            if r.returncode != 0:
                out(f"failed branch: git fetch {remote} {branch}: {why(r)}")
            r = git("switch", "-c", branch, "--track", f"{remote}/{branch}", cwd=wt)
            if r.returncode != 0:
                out(f"failed branch: git switch --track {remote}/{branch}: {why(r)}")
            if current and current != "HEAD":
                git("branch", "-D", current)
        else:
            r = git("branch", "-m", branch, cwd=wt)
            if r.returncode != 0:
                out(f"failed branch: git branch -m {branch}: {why(r)}")
    exclude_if_inside(wt)
    copy_env(wt)
    return wt


def trusted_in_config(path):
    base = os.environ.get("CLAUDE_CONFIG_DIR")
    config = os.path.join(base, ".claude.json") if base else os.path.expanduser("~/.claude.json")
    try:
        projects = json.load(open(config, encoding="utf-8")).get("projects") or {}
    except (OSError, ValueError, AttributeError):
        return False
    for p in {path, os.path.realpath(path)}:
        entry = projects.get(p) if isinstance(projects, dict) else None
        if isinstance(entry, dict) and entry.get("hasTrustDialogAccepted") is True:
            return True
    return False


def clear_trust(path):
    """Clear Claude Code's folder-trust and bypass dialogs for path in a throwaway terminal."""
    poll = float(os.environ.get("STAR_TRUST_POLL") or 2)
    made = run([orca, "terminal", "create", "--worktree", f"path:{path}", "--title", f"STAR trust {item}",
                "--command", "claude --dangerously-skip-permissions", "--json"], 60)
    handle = re.search(r"term_[A-Za-z0-9-]+", made.stdout)
    if made.returncode != 0 or not handle:
        return False
    handle, rounds, clean = handle.group(0), 0, 0
    try:
        for poll_no in range(15):
            time.sleep(poll)
            screen = run([orca, "terminal", "read", "--terminal", handle, "--screen", "--json"], 30)
            if screen.returncode != 0:
                return False
            if "No, exit" in screen.stdout:
                if rounds == 3:
                    return False
                # both dialogs default to "No, exit": move the selection first, never a blind Enter
                run([orca, "terminal", "send", "--terminal", handle, "--text", "\x1b[B"], 30)
                run([orca, "terminal", "send", "--terminal", handle, "--enter"], 30)
                rounds, clean = rounds + 1, 0
                continue
            clean += 1
            if clean >= 3 and (rounds or poll_no >= 4):
                return True
        return False
    finally:
        run([orca, "terminal", "close", "--terminal", handle, "--json"], 30)


def window():
    if star.get("away"):
        return "always"
    q = star.get("quietHours")
    if isinstance(q, dict) and q.get("start") and q.get("end") and q.get("tz"):
        return f"{q['start']}-{q['end']}@{q['tz']}"
    return None


def has_feedback(path):
    try:
        return re.search(r"^## Feedback\s*$", open(path, encoding="utf-8").read(), re.M) is not None
    except OSError:
        return False


def reviewer_spec(fm):
    template = open(os.path.join(S, "template", "reviewer-prompt.md"), encoding="utf-8").read()
    review = os.path.join(reviews, f"{item}-r{round_}.md")
    if round_ >= 2:
        previous = (f"Previous round: {os.path.join(reviews, f'{item}-r{round_ - 1}.md')} and its -fix.md "
                    "beside it. Judge each rejection on its merits; a prior rejection is evidence, not a verdict.")
    else:
        previous = "This is round 1: there is no previous review."
    values = {"brief": brief, "notes": os.path.join(home, "memory", f"{name}.md"), "previous": previous,
              "remote": project.get("remote") or "origin", "base": fm.get("baseBranch") or "main",
              "review": review, "item": item, "round": str(round_)}
    text = re.sub(r"\{\{(\w+)\}\}", lambda m: values.get(m.group(1), m.group(0)), template)
    folder = os.path.join(home, "specs", name)
    os.makedirs(folder, exist_ok=True)
    target = os.path.join(folder, f"{item}-review-r{round_}.md")
    tmp = f"{target}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, target)
    return f"You are STAR's second-model reviewer for {item}. Read {target} and do exactly what it says."


def prompt(entry, fm):
    executor = " --executor session" if entry.get("executor") == "session" else ""
    quiet_window = window()
    quiet = f" --quiet-hours {quiet_window}" if quiet_window else ""
    if stage == "brief":
        feedback = " --feedback" if has_feedback(brief) else ""
        return f"/juel:star draft-brief {row['ref']} --project {name} --item {item} --out {brief}{feedback}"
    if stage == "build":
        return f"/juel:ship-ticket --unattended --brief {brief}{executor}{quiet}"
    if stage == "fix":
        return (f"/juel:ship-ticket --unattended --brief {brief} --fix-review "
                f"{reviews}/{item}-r{round_}.md{executor}{quiet}")
    if stage == "screen":
        return (f"/juel:ship-ticket --unattended --brief {brief} --screen-checks "
                f"{gates}/{item}-screen.md{executor}{quiet}")
    if stage == "babysit":
        pr = re.search(r"/pull/(\d+)", row["pr"])
        if not pr:
            out("failed brief: the row has no PR to babysit")
        since = f" --since {row['cursor']}" if row["cursor"] not in ("", "-") else ""
        return (f"/juel:babysit-pr {pr.group(1)} --unattended --mark-ready --reviewed {reviews}/{item}-r{round_}.md "
                f"--item {item} --brief {brief} --gates-file {gates}/{item}.json{executor}{since}{quiet}")
    if stage == "post":
        return f"/juel:star post-report {row['ref']} --item {item} --report {home}/reports/{name}/{item}.md"
    return reviewer_spec(fm)


fm = {}
if stage != "brief":
    fm = frontmatter(brief)
    if fm is None:
        out(f"failed brief: no brief at {brief}")
gb = free_gb()
if gb is not None and gb < 3:
    out(f"hold memory {gb}")
entry, fallback = setting()
if stage in ("brief", "post"):
    place = repo
elif stage == "build":
    place = build_worktree(fm)
else:
    place = row["worktree"]
    if place in ("", "-") or not os.path.isdir(place):
        out(f"failed worktree: {item} has no worktree")
    other = other_row_using(place)
    if other:
        out(f"failed in-use: {place} is already in use by {other}")


def ensure_trust(setting_):
    if (setting_.get("agent") or "claude") == "claude" and not trusted_in_config(place) and not clear_trust(place):
        if started_row:
            # the row is already written (a fallback agent needed the dialogs): put it back to wait,
            # and keep live= so the next start replays this one instead of making a second task
            ledger("set", item, f"state={WAITING[stage]}")
        out(f"hold trust {place}")


def same_launch(a, b):
    """Two settings launch the same thing when agent, model and effort match; executor is not part of a launch."""
    return all((a.get(k) or None) == (b.get(k) or None) for k in ("agent", "model", "effort"))


ensure_trust(entry)
spec = prompt(entry, fm)
n = int(live) if replay and str(live).isdigit() else int(counters.get("start", "0") or 0) + 1
rid = f"star-{item}-{stage}-r{round_}-s{n}"
task = dispatch = None
if replay:
    ledger("set", item, f"state={RUNNING[stage]}")
    task = None if row["task"] == "-" else row["task"]
    dispatch = None if row["dispatch"] == "-" else row["dispatch"]
else:
    ledger("set", item, f"state={RUNNING[stage]}", f"stage={stage}", f"round={round_}", "task=-",
           "dispatch=-", f"counters.start={n}", f"counters.live={n}")
started_row = True
if task and dispatch:
    finish(f"started task={task} dispatch={dispatch}")
if not task:
    made = run([orca, "orchestration", "task-create", "--spec", spec, "--task-title",
                f"{item} {stage} r{round_}", "--retry-request", rid, "--json"], 60)
    task = ids(made.stdout, "task_")
    if made.returncode != 0 or not task:
        finish("failed task-create: " + why(made))
    ledger("set", item, f"task={task}")


def worker_start(setting_, attempt, effort=None, retry_of=None):
    cmd = [orca, "orchestration", "worker-start", "--task", task, "--worktree", f"path:{place}",
           "--agent", setting_.get("agent") or "claude"]
    model = setting_.get("model")
    if model and model != "default":
        cmd += ["--model", model]
        level = effort or setting_.get("effort")
        if level:
            cmd += ["--effort", level]
    if retry_of:
        cmd += ["--retry-of", retry_of]
    return run(cmd + ["--retry-request", f"{rid}-w{attempt}", "--json"], 540)


first, note = worker_start(entry, 1), ""
dispatch = ids(first.stdout, "ctx_")
if first.returncode != 0 or not dispatch:
    reason, level = why(first), entry.get("effort")
    if "effort" in reason.lower() and level in EFFORTS[:-1]:
        second = worker_start(entry, 2, effort=EFFORTS[EFFORTS.index(level) + 1])
    elif not same_launch(entry, fallback) and any(w in reason.lower() for w in REFUSED):
        ensure_trust(fallback)
        second = worker_start(fallback, 2)
        note = f" fallback {fallback.get('model') or 'default'}: {reason}"
    else:
        second = worker_start(entry, 2, retry_of=dispatch)
    dispatch = ids(second.stdout, "ctx_")
    if second.returncode != 0 or not dispatch:
        finish("failed worker-start: " + why(second))
ledger("set", item, f"dispatch={dispatch}", "counters.live=-")
started_row = False
out(f"started task={task} dispatch={dispatch}{note}")
PY
