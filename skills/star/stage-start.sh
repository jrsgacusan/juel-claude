#!/bin/sh
# Starts one STAR stage for one ledger row: everything "Fill slots" does, in one place, so no
# session hand-rolls it.
#   stage-start.sh [--home H] brief|build|babysit|post <item>
#   stage-start.sh [--home H] close|release|stop <dispatch>
#   stage-start.sh [--home H] tell <dispatch> <subject> <body>
# Prints one line:
#   started task=<id> dispatch=<id>[ fallback <model>: <why>]
#   hold memory <gb>          free + inactive memory under hostGate.minFreeGB (default 3)
#   hold agents <n>           more claude and codex processes than hostGate.maxAgents (default 40)
#   hold swap <gb>            more swap in use than hostGate.maxSwapGB (default 11)
#   hold disk <gb>            less free disk under STAR's home than hostGate.minDiskGB (default 25)
#   hold trust <path>         Claude Code's first-run dialogs for <path> could not be cleared
#   wait until <iso>          build only: the brief's notBefore is still ahead (#87). A date alone
#                             is 00:00 in the machine's local zone; a time needs an offset or Z
#   wait <item>               build and babysit: the brief's blockedBy: [<item>, ...] names an item that
#                             is still open (#189, #205), checked after notBefore and before the host
#                             gate. An item is cleared when its row is done, or dropped with every row
#                             whose counters.parent names it cleared, recursively (a SPLIT's parts, a
#                             re-scope's follow-up); a name with no row is open. Nothing is written
#   hold session <terminal> (<state>)
#                             a session may still be working (#76): the row's previous dispatch has
#                             an open terminal Orca does not prove it owns (<state> is its
#                             retainedReason, such as user_takeover or identity_unproven, or its
#                             ownershipState) that printed output in the last 10 minutes, unless
#                             its screen shows only Claude Code's recap line above an empty prompt
#                             (#119); or closing
#                             the dispatch's own terminal failed ("close failed: <why>"; never for a
#                             released dispatch, #95); or, for build and babysit, another claude or
#                             codex terminal in the worktree printed output in the last 10 minutes
#                             ("live in the worktree")
#   failed <step>: <why>      step: brief, worktree, branch, env, in-use, task-create, worker-start
# close <dispatch> (#175) prints exactly one line and starts nothing. It closes the terminal a finished
# dispatch of STAR's own left open, whatever Orca's retainedReason (user_takeover, identity_unproven):
#   closed <terminal>                  Orca reports the dispatch settled (completed, failed,
#                                      cancelled or released) and its terminal owned by that
#                                      dispatch: closed
#   kept <terminal> (<state>)          not closed: the dispatch is still running ("running"), the
#                                      terminal's owner is another dispatch or a person (<state> is its
#                                      retainedReason or ownershipState), or the close failed
#                                      ("close failed: <why>")
#   none                               the dispatch has no terminal, or Orca no longer lists it
# release <dispatch> (#197), stop <dispatch> and tell <dispatch> <subject> <body> (#198) print exactly one
# line, exit 0, and start nothing. They are the only way STAR calls worker-release, worker-stop and
# orchestration send; none of the Orca commands takes --run, and a send needs the address dispatch:<id>.
#   release: worker-release --dispatch <id> --json, then close. "<status> <dispatch>; <close line>", the
#     status being Orca's (released, retained, release_pending, already_released); or
#     "FAIL release <dispatch>: <message>" (ok: false, a non-zero exit, release_unknown)
#   stop: appends "<dispatch> stopped <iso>" to <home>/processed.log unless a line for the dispatch is
#     there, then worker-stop, then release: "stopped <dispatch>; <release line>" or "FAIL stop <dispatch>: <message>"
#   tell: the dispatch's mailbox ("sent mailbox"); when Orca refuses, the dispatch's terminal
#     (worker-show's agentTerminalHandle, else assigneeHandle) gets "<subject>: <body>" and Enter
#     ("sent terminal <t>"); "busy <t>" when Orca answers agent_prompt_blocked (try again next tick);
#     else "FAIL tell <dispatch>: <message>"
# Before that one line it may print, in this order, each on a line of its own, whatever line
# follows (#76):
#   stopped previous gate pgid=<n>    the gate lock, or one of its slot files <lock>.2 to <lock>.4
#                                     (#97; each one that exists, whatever <lock>.slots says), is held
#                                     under this item's label, <project name>/<item>
#                                     (project.name from star.json; the lock is one file per user for
#                                     every project, so a bare item id would also match another
#                                     project's item of the same id): TERM to its recorded group,
#                                     whatever the state of its terminal, but only once no "hold
#                                     session" was printed (a live session may be the one running it);
#                                     one line per slot so held, in slot order
#   ended previous session <terminal> the previous dispatch's own terminal was open: closed. A
#                                     dispatch Orca reports settled (completed, failed, cancelled, or
#                                     "released") whose terminal it owns is gone (#95, #175), whatever
#                                     the retainedReason: its terminal is closed the same way,
#                                     best-effort, and a failed close is ignored
#   kept previous session <terminal> (<state>)
#                                     an open terminal Orca does not prove is the dispatch's, quiet
#                                     for 10 minutes or more, or showing only Claude Code's recap
#                                     line above an empty prompt (#119): left open (a person's
#                                     terminal is never closed), and the start goes on
# These run only when the row's dispatch is not "-", and never on a replay, which would be its own
# dispatch. Nothing is written to the row before a hold. A previous terminal that a readable,
# untruncated `orca terminal list --limit 500` no longer lists is gone, whatever worker-show still
# reports (#119): no line, nothing closed, no hold.
# The branch step holds a per-repository lock, so parallel starts in one repository are safe; a rename
# that collides on git's `.tmp-renamed-log` is retried once (#181).
# In order: for build, the brief's notBefore (a value that is not a date is "failed brief");
# the host gate (nothing starts while one of its four checks fails); the previous dispatch's
# terminal; for build and babysit, live terminals in the worktree, once it is known; then, with no
# hold session, the previous dispatch's gate; for build, the
# worktree (reuse one already on the brief's branch, else orca worktree create, then put it on the
# brief's branch, copy the main checkout's git-ignored environment files, and add a
# .git/info/exclude line when the worktree sits inside the repository; the copy (#98) skips a
# directory entry, anything under .claude/worktrees/ and anything that is not a regular file, and a
# file it cannot copy prints "stage-start.sh: could not copy <name> (<why>)" on stderr while the
# start goes on); for babysit, a review a v1
# reviewer left inside the worktree moves into the STAR folder (#35); for a claude worker whose
# path Claude Code's config does not list as trusted, the first-run dialogs, cleared in a
# throwaway terminal the way orca-ship-tickets does (only while "No, exit" is on screen, Down then
# Enter, at most 3 rounds); the prompt; then task-create and worker-start. Both carry a
# --retry-request id, so a STAR that died between a call and recording its result gets the same
# task or dispatch back from Orca, never a second one. Orca takes only a UUID there (#163): the id is
# the UUID5 of the STAR folder and star-<item>-<stage>-r<round>-s<n> (-w<attempt> for worker-start),
# so a replay sends the same UUID and two projects never share one.
# The row is written through ledger.sh before task-create (state, stage, round, counters.start
# and counters.live), after it (task) and after worker-start (dispatch, live cleared). A row whose
# counters still hold live= for this stage is a start that died: it is replayed with the same ids.
# A brief with existingPr: <url> and no local branch yet gets its branch fetched from the
# project's remote and checked out tracking it (an open PR's head), instead of a renamed branch.
# The brief stage gets --feedback when its brief has a "## Feedback" section, or when STAR left
# feedback for it in <brief>.feedback.md while it was still drafting (#112). It gets
# --rescope <reviews>/<file> when the row's counters hold rescope=<file>; the
# babysit stage gets --reviewed <the newest round's <item>-r<k>-carried.md when the owner carried
# that round (#82), else its <item>-r<k>.md>. The executor, gate and hosted-reviewer
# settings are not in any prompt: workers read them from star.json through their brief.
# Every spec sent is one line. A failed worker-start is retried once: with --retry-of, one effort
# level lower when the effort was refused, or on "worker" when the model was refused.
# Test seams: ORCA_CLI_COMMAND, STAR_FREE_GB, STAR_AGENTS, STAR_SWAP_GB, STAR_DISK_GB,
# STAR_TRUST_POLL (seconds), CLAUDE_CONFIG_DIR, JUEL_GATE_LOCK (the gate lock's path, as gate-lock.sh).
# Exit: 0 with one of the lines above; 2 the STAR folder or star.json cannot be read; 4 no row for
# the item; 64 usage.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
export STAR_HOME_DEFAULT STAR_SKILL_DIR
exec python3 - "$@" <<'PY'
import fcntl
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone

S = os.environ["STAR_SKILL_DIR"]
RUNNING = {"brief": "briefing", "build": "building", "babysit": "babysitting", "post": "posting"}
WAITING = {"brief": "inbox", "build": "queued", "babysit": "babysit-queued", "post": "post-queued"}
EFFORTS = ["max", "xhigh", "high", "medium", "low"]
REFUSED = ("not installed", "unknown agent", "model", "access", "credit", "quota", "not available")
ENV_NAMES = (".env", ".envrc", ".npmrc", ".tool-versions")
LIVE_MS = 10 * 60 * 1000  # a terminal that printed output this recently is a working session (#76)
# Claude Code 2.1.301's screen, as `orca terminal read --screen` renders it (#119); keep these shapes
# in step with worker-probe.sh. The prompt is a rule row, the prompt row and another rule row, with
# the footer below: the prompt row is "❯" (or ">", inside a "│" frame on a boxed prompt), alone when
# empty, a no-break space or trailing spaces after it included. A footer row says "esc to interrupt"
# while a turn runs. The recap Claude Code prints on an idle terminal is a "※ recap: <text>" row,
# wrapped onto indented rows under it.
RULE = re.compile(r"^\s*[╭╰]?─{3,}[╮╯]?\s*$")
PROMPT_ROW = re.compile(r"^\s*│?\s*[❯>](\s|$)")
EMPTY_PROMPT = re.compile(r"^\s*│?\s*[❯>]\s*│?\s*$")
RECAP = re.compile(r"^\s*※\s*recap:")
CONTINUED = re.compile(r"^\s+[^\s⎿⏺●✽✻✶✳✢·*]")  # a wrapped row: indented, and no turn's glyph
NOTES = []  # extra lines (#76), printed in this order before the one result line
orca = os.environ.get("ORCA_CLI_COMMAND") or "orca"


def die(code, msg):
    print(f"stage-start.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def out(line):
    for note in NOTES:
        print(note)
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


def orca_lists(handle):
    """Whether Orca's terminal list holds this handle (#119); None unless the list proves it is whole:
    it reads, does not say ok: false, is a list, is marked truncated: false, holds totalCount entries
    when it names a count, and leaves out no host (hostScope.omittedHostIds). Then a missing handle
    proves nothing."""
    shown = run([orca, "terminal", "list", "--limit", "500", "--json"], 60)
    data = lenient(shown.stdout)
    result = data.get("result") if isinstance(data, dict) and data.get("ok") is not False else None
    terminals = result.get("terminals") if isinstance(result, dict) else None
    if shown.returncode != 0 or not isinstance(terminals, list) or result.get("truncated") is not False:
        return None
    count, scope = result.get("totalCount"), result.get("hostScope")
    if (isinstance(count, int) and count > len(terminals)) or (isinstance(scope, dict) and scope.get("omittedHostIds")):
        return None
    return any(isinstance(t, dict) and t.get("handle") == handle for t in terminals)


SETTLED_DISPATCH = ("completed", "failed", "cancelled", "canceled")


def settled_own_terminal(dispatch):
    """Orca's view of a dispatch's terminal (#175): (handle, settled_own, result). handle is None when
    Orca no longer knows the dispatch or it has no terminal. settled_own is True when Orca reports the
    dispatch settled (its own status completed, failed or cancelled, or releaseState or ownershipState
    "released") and the terminal's owner is that dispatch: its terminal is STAR's to close, whatever
    its retainedReason or exactWorker say. After worker-release, a terminal a person clicked into stays
    releaseState "retained", ownershipState "user_owned", while the dispatch says completed (#175)."""
    shown = run([orca, "orchestration", "worker-show", "--dispatch", dispatch, "--json"], 60)
    data = lenient(shown.stdout)
    result = data.get("result") if isinstance(data, dict) else None
    if shown.returncode != 0 or not isinstance(result, dict):
        return None, False, None
    terminal = result.get("terminal")
    handle = terminal.get("handle") if isinstance(terminal, dict) else None
    if not handle:
        return None, False, result
    res = result.get("terminalResource") if isinstance(result.get("terminalResource"), dict) else {}
    released = "released" in (res.get("releaseState"), res.get("ownershipState"))
    status = (result.get("dispatch") or {}).get("status") if isinstance(result.get("dispatch"), dict) else None
    settled = released or status in SETTLED_DISPATCH
    return handle, settled and res.get("ownerDispatchId") == dispatch, result


def close_line(dispatch):
    """close <dispatch> (#175): close the terminal a settled dispatch of STAR's own left open. Returns the line."""
    handle, settled_own, result = settled_own_terminal(dispatch)
    if not handle or orca_lists(handle) is False:
        return "none"
    if settled_own:
        closed = run([orca, "terminal", "close", "--terminal", handle, "--json"], 60)
        if closed.returncode == 0 or orca_lists(handle) is False:
            return f"closed {handle}"
        return f"kept {handle} (close failed: {why(closed)})"
    res = result.get("terminalResource") if isinstance(result.get("terminalResource"), dict) else {}
    if "released" in (res.get("releaseState"), res.get("ownershipState")):
        return f"kept {handle} ({res.get('retainedReason') or res.get('ownershipState') or 'unowned'})"
    return f"kept {handle} (running)"


def close_command(dispatch):
    out(close_line(dispatch))


def release_command(dispatch):
    """release <dispatch> (#197): worker-release with only --dispatch, then the close check. Returns the line."""
    released = run([orca, "orchestration", "worker-release", "--dispatch", dispatch, "--json"], 60)
    data = lenient(released.stdout)
    statuses = ("released", "retained", "release_pending", "already_released", "release_unknown")
    status = next((v for v in strings(data) if v in statuses), None)
    if released.returncode != 0 or not isinstance(data, dict) or data.get("ok") is False or status in (None, "release_unknown"):
        message = why(released)
        result = data.get("result") if isinstance(data, dict) else None
        if released.returncode == 0 and isinstance(result, dict) and (result.get("message") or result.get("reason")):
            message = str(result.get("message") or result.get("reason"))[:120]
        elif released.returncode == 0 and status is None:
            message = "Orca named no release status"
        return f"FAIL release {dispatch}: {message}"
    return f"{status} {dispatch}; {close_line(dispatch)}"


def strings(value):
    """Every string value under a decoded JSON value."""
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for v in value.values():
            yield from strings(v)
    elif isinstance(value, list):
        for v in value:
            yield from strings(v)


def stop_command(dispatch):
    """stop <dispatch> (#80, #197): note the stop in processed.log first, so a late worker_done is skipped, then
    worker-stop, then release."""
    log = os.path.join(home, "processed.log")
    try:
        known = any(line.split()[:1] == [dispatch] for line in open(log, encoding="utf-8", errors="replace"))
    except OSError:
        known = False
    if not known:
        with open(log, "a", encoding="utf-8") as f:
            f.write(f"{dispatch} stopped {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\n")
    stopped = run([orca, "orchestration", "worker-stop", "--dispatch", dispatch, "--json"], 60)
    data = lenient(stopped.stdout)
    if stopped.returncode != 0 or (isinstance(data, dict) and data.get("ok") is False):
        out(f"FAIL stop {dispatch}: {why(stopped)}")
    out(f"stopped {dispatch}; {release_command(dispatch)}")


def tell_command(dispatch, subject, body):
    """tell <dispatch> <subject> <body> (#198): the dispatch's mailbox, else its own terminal."""
    sent = run([orca, "orchestration", "send", "--to", f"dispatch:{dispatch}", "--subject", subject, "--body", body, "--json"], 60)
    data = lenient(sent.stdout)
    if sent.returncode == 0 and not (isinstance(data, dict) and data.get("ok") is False):
        out("sent mailbox")
    shown = run([orca, "orchestration", "worker-show", "--dispatch", dispatch, "--json"], 60)
    shown_data = lenient(shown.stdout)
    result = shown_data.get("result") if isinstance(shown_data, dict) else None
    result = result if isinstance(result, dict) else {}
    worker = result.get("worker") if isinstance(result.get("worker"), dict) else {}
    record = result.get("dispatch") if isinstance(result.get("dispatch"), dict) else {}
    handle = worker.get("agentTerminalHandle") or record.get("assigneeHandle")
    if not handle:
        out(f"FAIL tell {dispatch}: {why(sent)}; the dispatch has no terminal")
    typed = run([orca, "terminal", "send", "--terminal", handle, "--text", f"{subject}: {body}", "--enter", "--json"], 60)
    typed_data = lenient(typed.stdout)
    if typed.returncode == 0 and not (isinstance(typed_data, dict) and typed_data.get("ok") is False):
        out(f"sent terminal {handle}")
    if "agent_prompt_blocked" in typed.stdout + typed.stderr:
        out(f"busy {handle}")
    out(f"FAIL tell {dispatch}: {why(typed)}")


home, args, positional = os.environ.get("STAR_HOME_DEFAULT") or "", sys.argv[1:], []
while args:
    arg = args.pop(0)
    if positional[:1] == ["tell"] and len(positional) >= 2:
        positional.append(arg)  # a subject or body may start with a dash
    elif arg == "--home":
        if not args:
            die(64, "--home needs a value")
        home = args.pop(0)
    elif arg.startswith("-"):
        die(64, f"unknown argument: {arg}")
    else:
        positional.append(arg)
USAGE = ("usage: stage-start.sh [--home H] brief|build|babysit|post <item> | close|release|stop <dispatch> "
         "| tell <dispatch> <subject> <body>")
if len(positional) == 2 and positional[0] == "close":
    close_command(positional[1])
if len(positional) == 2 and positional[0] == "release":
    out(release_command(positional[1]))
if len(positional) == 2 and positional[0] == "stop":
    if not home:
        die(2, "no STAR folder: pass --home, or run inside a project")
    home = os.path.abspath(home)
    stop_command(positional[1])
if len(positional) == 4 and positional[0] == "tell":
    tell_command(*positional[1:])
if len(positional) != 2 or positional[0] not in RUNNING:
    die(64, USAGE)
stage, item = positional
if not home:
    die(2, "no STAR folder: pass --home, or run inside a project")
home = os.path.abspath(home)
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
round_ = int(row["round"]) if row["round"].isdigit() else 0
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


def not_before(value):
    """The brief's notBefore as an aware time, or None when it is not a time STAR reads (#87)."""
    try:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            day = datetime.strptime(value, "%Y-%m-%d")
            return day.astimezone()  # a naive day read as local time
        when = datetime.fromisoformat(value[:-1] + "+00:00" if value[-1:] in ("Z", "z") else value)
    except ValueError:
        return None
    return when if when.tzinfo else None


def open_blocker(name, seen=None):
    """The first item still open under this blocker (#189, #205), or None when it is cleared. A row is
    cleared when it is done, or dropped with every row whose counters.parent names it cleared,
    recursively: a SPLIT's parts and a re-scope's follow-up both carry parent=. A name with no row is
    open. A dropped row with no such rows clears (#37)."""
    seen = seen or set()
    if name in seen:
        return None
    got = run(["sh", os.path.join(S, "ledger.sh"), "--home", home, "get", name, "state"], 30)
    if got.returncode != 0:
        return name
    state = got.stdout.strip()
    if state == "done":
        return None
    if state != "dropped":
        return name
    listed = run(["sh", os.path.join(S, "ledger.sh"), "--home", home, "list"], 30)
    for line in listed.stdout.splitlines():
        part = line.split("\t")[0]
        if part and part != name and run(["sh", os.path.join(S, "ledger.sh"), "--home", home, "get", part, "counters.parent"], 30).stdout.strip() == name:
            found = open_blocker(part, seen | {name})
            if found:
                return found
    return None


def first_open_blocker(value):
    """The first open item in a brief's blockedBy: [<item>, ...] line, or None."""
    for blocker in re.split(r"[\s,]+", value.strip().strip("[]")):
        found = open_blocker(blocker) if blocker else None
        if found:
            return found
    return None


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


def measured(env, read):
    if os.environ.get(env):
        try:
            return int(float(os.environ[env]))
        except ValueError:
            return None
    try:
        return read()
    except Exception:  # a host that cannot be measured never holds a start
        return None


def agent_count():
    return sum(1 for l in run(["ps", "-Ao", "comm"], 10).stdout.splitlines()
               if os.path.basename(l.strip()) in ("claude", "codex"))


def swap_gb():
    if sys.platform == "darwin":
        used = re.search(r"used = ([\d.]+)([MG])", run(["sysctl", "-n", "vm.swapusage"], 10).stdout)
        return int(float(used.group(1)) / (1024 if used.group(2) == "M" else 1))
    swap = next(l for l in run(["free", "-g"], 10).stdout.splitlines() if l.lower().startswith("swap"))
    return int(swap.split()[2])


def disk_gb():
    return shutil.disk_usage(home).free // 1073741824


def host_gate():
    """The first check that fails, as "<what> <value>"; None when the host has room (the host gate)."""
    hg = star.get("hostGate") if isinstance(star.get("hostGate"), dict) else {}

    def limit(key, default):
        try:
            return float(hg.get(key, default))
        except (TypeError, ValueError):
            return float(default)

    gb = free_gb()
    if gb is not None and gb < limit("minFreeGB", 3):
        return f"memory {gb}"
    agents = measured("STAR_AGENTS", agent_count)
    if agents is not None and agents > limit("maxAgents", 40):
        return f"agents {agents}"
    swap = measured("STAR_SWAP_GB", swap_gb)
    if swap is not None and swap > limit("maxSwapGB", 11):
        return f"swap {swap}"
    disk = measured("STAR_DISK_GB", disk_gb)
    if disk is not None and disk < limit("minDiskGB", 25):
        return f"disk {disk}"
    return None


def setting():
    default = {"agent": "claude", "model": "default"}
    fallback = star.get("worker") if isinstance(star.get("worker"), dict) else default
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
        # git lists a nested worktree as one "<dir>/" entry (#98): only regular files are environment
        if (not f or f.endswith("/") or f.startswith(".claude/worktrees/")
                or not os.path.isfile(os.path.join(repo, f))):
            continue
        # an untracked file that is not ignored is someone's work in progress, not environment
        if os.path.exists(target) or git("check-ignore", "-q", f).returncode != 0:
            continue
        try:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(os.path.join(repo, f), target)
        except OSError as e:
            print(f"stage-start.sh: could not copy {f} ({e.strerror or e})", file=sys.stderr)
            continue
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
    # the branch step holds a per-repository lock: git renames branches through one shared temp log (#181)
    lock = git("rev-parse", "--git-common-dir")
    lock_dir = lock.stdout.strip() if lock.returncode == 0 else ""
    if lock_dir:
        lock_fd = os.open(os.path.join(os.path.realpath(os.path.join(repo, lock_dir)), "juel-stage-start.lock"),
                          os.O_RDWR | os.O_CREAT, 0o644)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
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
            if r.returncode != 0 and ".tmp-renamed-log" in r.stderr:
                # a rename that collided on git's temp log is retried once, from the HEAD as it is now
                r = git("branch", "-m", branch, cwd=wt)
            if r.returncode != 0:
                out(f"failed branch: git branch -m {branch}: {why(r)}")
    if lock_dir:
        os.close(lock_fd)
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
    """Clear Claude Code's folder-trust and bypass dialogs for path in a throwaway terminal.

    The throwaway session runs on the classic renderer: a fullscreen launch closed seconds after it
    started counts as a failed fullscreen boot, and after two of those Claude Code turns fullscreen
    off for the whole config (fullscreenAutoDisabled), so STAR's own session stops getting clicks."""
    poll = float(os.environ.get("STAR_TRUST_POLL") or 2)
    made = run([orca, "terminal", "create", "--worktree", f"path:{path}", "--title", f"STAR trust {item}",
                "--command", "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 claude --dangerously-skip-permissions", "--json"], 60)
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


def has_feedback(path):
    """The brief has a ## Feedback section, or STAR's side file for it exists (#112)."""
    if os.path.isfile(path + ".feedback.md"):
        return True
    try:
        return re.search(r"^## Feedback\s*$", open(path, encoding="utf-8").read(), re.M) is not None
    except OSError:
        return False


def newest_review():
    """The newest round's proof: its carried file when the owner carried that round (#82), else its review."""
    names = os.listdir(reviews) if os.path.isdir(reviews) else []
    rounds = [int(m.group(1)) for m in (re.fullmatch(re.escape(item) + r"-r(\d+)\.md", n) for n in names) if m]
    if not rounds:
        return None
    carried = os.path.join(reviews, f"{item}-r{max(rounds)}-carried.md")
    return carried if os.path.isfile(carried) else os.path.join(reviews, f"{item}-r{max(rounds)}.md")


def prompt():
    if stage == "brief":
        feedback = " --feedback" if has_feedback(brief) else ""
        rescope = counters.get("rescope")
        rescope = f" --rescope {os.path.join(reviews, rescope)}" if rescope and rescope != "-" else ""
        return f"/juel:star draft-brief {row['ref']} --project {name} --item {item} --out {brief}{feedback}{rescope}"
    if stage == "build":
        return f"/juel:ship-ticket --unattended --brief {brief}"
    if stage == "babysit":
        pr = re.search(r"/pull/(\d+)", row["pr"])
        if not pr:
            out("failed brief: the row has no PR to babysit")
        review = newest_review()
        if not review:
            out(f"failed brief: {item} has no review to prove its PR was gated")
        since = f" --since {row['cursor']}" if row["cursor"] not in ("", "-") else ""
        return (f"/juel:babysit-pr {pr.group(1)} --unattended --mark-ready --reviewed {review} --item {item} "
                f"--brief {brief} --gates-file {gates}/{item}.json{since}")
    return f"/juel:star post-report {row['ref']} --item {item} --report {home}/reports/{name}/{item}.md"


def lock_holder():
    """Each held gate-lock slot's holder as (label, pid, pgid), in slot order: <lock> and each of
    <lock>.2 to <lock>.4 that exists, whatever <lock>.slots says (#97). Empty when no slot is held."""
    lock = os.path.abspath(os.environ.get("JUEL_GATE_LOCK") or f"/tmp/juel.gate.{os.getuid()}.lock")
    held = []
    for path in (lock, f"{lock}.2", f"{lock}.3", f"{lock}.4"):
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        except OSError:
            continue
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
                continue  # nobody holds it: whatever the file says is stale
            except OSError:
                pass
            words = os.pread(fd, 400, 0).decode("utf-8", "replace").split()
        finally:
            os.close(fd)
        fields = dict(w.split("=", 1) for w in words[1:] if "=" in w)
        try:
            held.append((words[0], int(fields.get("pid", "0")), int(fields.get("pgid", "0"))))
        except (IndexError, ValueError):
            pass
    return held


def stop_gate():
    """A gate any lock slot says this item holds stops before a new stage of it starts, whatever its terminal (#76, #97).
    Called only once no "hold session" was printed: a live session may be the one running it."""
    # the label ship-ticket and babysit-pr give gate-lock.sh under a star: brief, whitespace folded as it folds it
    label = "_".join(f"{name}/{item}".split())
    stopped = []
    for held_label, pid, pgid in lock_holder():
        if held_label != label or pgid <= 1 or pgid == os.getpgrp():
            continue
        for kill, target in ((os.killpg, pgid), (os.kill, pid)):
            if target > 1 and target != os.getpid():
                try:
                    kill(target, signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
        stopped.append(f"stopped previous gate pgid={pgid}")
    NOTES[:0] = stopped  # first, before the session lines


def recent(last):
    """True when a terminal printed output in the last 10 minutes, or Orca does not say when."""
    return not isinstance(last, (int, float)) or time.time() * 1000 - last <= LIVE_MS


def screen_rows(handle):
    """The terminal's rendered screen rows, read with the same command and checks as worker-probe.sh's
    screen_tail() (without its 25-row cut); None when the screen cannot be read or Orca reports
    anything but "screen"."""
    read = run([orca, "terminal", "read", "--terminal", handle, "--screen", "--json"], 60)
    data = lenient(read.stdout)
    result = data.get("result") if isinstance(data, dict) and data.get("ok") is not False else None
    term = result.get("terminal") if isinstance(result, dict) else None
    tail = term.get("tail") if isinstance(term, dict) else None
    if read.returncode != 0 or not isinstance(tail, list) or not tail or term.get("source", "screen") != "screen":
        return None
    return [str(row) for row in tail]


def recap_only(rows):
    """True when the newest rows above the screen's empty prompt are Claude Code's recap (#119): its
    newest "※ recap:" row, then only its wrapped rows, however many, with no turn running.
    Any other screen, an unreadable one included, is False."""
    rows = rows or []
    prompt = next((i for i in range(len(rows) - 2, 0, -1)
                   if PROMPT_ROW.match(rows[i]) and RULE.match(rows[i - 1]) and RULE.match(rows[i + 1])), None)
    if prompt is None or not EMPTY_PROMPT.match(rows[prompt]) \
            or any("esc to interrupt" in r for r in rows[prompt + 2:]):
        return False
    above = [r for r in rows[:prompt - 1] if r.strip()]  # the recap row and however many wrapped rows
    head = next((j for j in range(len(above) - 1, -1, -1) if RECAP.match(above[j])), None)
    return head is not None and all(CONTINUED.match(r) for r in above[head + 1:])


def checks_previous():
    """The previous dispatch is checked when the row names one, and never on a replay of itself."""
    return not replay and (row.get("dispatch") or "-") != "-"


def previous_session():
    """The row's previous dispatch's terminal (#76): close its own, or a released one's (#95), keep a
    quiet one it cannot prove is its own, and hold on a working one. A terminal Orca's whole list no
    longer holds is gone, and the terminal Orca kept after it released the dispatch is quiet when its
    newest rows above an empty prompt are Claude Code's recap, with no turn running (#119). Returns
    that terminal's handle, or None when there is none left."""
    if not checks_previous():
        return None
    prev = row["dispatch"]
    handle, settled_own, result = settled_own_terminal(prev)
    if not handle:
        return None  # Orca no longer knows the dispatch, or its terminal is closed: nothing of it is left to end
    terminal = result.get("terminal")
    res = result.get("terminalResource") if isinstance(result.get("terminalResource"), dict) else {}
    seen = result.get("observation") if isinstance(result.get("observation"), dict) else {}
    reason, state = res.get("retainedReason") or "", None
    released = "released" in (res.get("releaseState"), res.get("ownershipState"))
    if settled_own or (not reason and released):
        # Orca released the dispatch, so it is gone (#95): close its terminal best-effort and ignore
        # the result, since Orca or the coordinator may have closed it already. Its own terminal is
        # closed whatever the retainedReason (#175).
        run([orca, "terminal", "close", "--terminal", handle, "--json"], 60)
        NOTES.append(f"ended previous session {handle}")
        return handle
    if res.get("ownershipState") != "owned" or res.get("ownerDispatchId") != prev:
        state = reason or res.get("ownershipState") or "unowned"
    elif reason or seen.get("exactWorker") is not True:
        state = reason or "identity_unproven"
    if state:
        if orca_lists(handle) is False:
            return None  # Orca's whole list holds no such terminal: it is gone, whatever worker-show says (#119)
        # a recap on the terminal Orca kept after it released the dispatch is not a session at work
        # (#119); an active dispatch's terminal is never judged by its recap, and only a recent one is read
        released = res.get("releaseState") in ("retained", "released")
        if recent(terminal.get("lastOutputAt")) and not (released and recap_only(screen_rows(handle))):
            out(f"hold session {handle} ({state})")
        NOTES.append(f"kept previous session {handle} ({state})")  # never close a terminal a person may own
        return handle
    closed = run([orca, "terminal", "close", "--terminal", handle, "--json"], 60)
    if closed.returncode != 0:
        if orca_lists(handle) is False:
            return None  # the close failed because the terminal is gone: nothing of it is left (#119)
        out(f"hold session {handle} (close failed: {why(closed)})")
    NOTES.append(f"ended previous session {handle}")
    return handle


def worktree_sessions(path, previous):
    """Any other claude or codex terminal that printed output in this worktree in the last 10 minutes holds the start (#76)."""
    listed = run([orca, "terminal", "list", "--worktree", f"path:{path}", "--json"], 60)
    data = lenient(listed.stdout)
    result = data.get("result") if isinstance(data, dict) else None
    terminals = result.get("terminals") if isinstance(result, dict) else None
    if listed.returncode != 0 or not isinstance(terminals, list):
        return  # Orca cannot list them: the previous dispatch was already checked
    now, real = time.time() * 1000, os.path.realpath(path)
    for t in terminals:
        if not isinstance(t, dict) or not t.get("handle") or t.get("handle") == previous:
            continue
        if t.get("agentIdentity") not in ("claude", "codex"):
            continue
        where = t.get("worktreePath")
        if where and os.path.realpath(where) != real:
            continue
        last = t.get("lastOutputAt")
        if isinstance(last, (int, float)) and now - last <= LIVE_MS:
            out(f"hold session {t['handle']} (live in the worktree)")


fm = {}
if stage != "brief":
    fm = frontmatter(brief)
    if fm is None:
        out(f"failed brief: no brief at {brief}")
if stage == "build" and fm.get("notBefore"):
    when = not_before(fm["notBefore"])
    if when is None:
        out(f"failed brief: notBefore {fm['notBefore']} is not a date (YYYY-MM-DD, or an ISO time with an offset)")
    if datetime.now(timezone.utc) < when:
        out(f"wait until {when.isoformat()}")
if stage in ("build", "babysit") and fm.get("blockedBy"):
    blocker = first_open_blocker(fm["blockedBy"])
    if blocker:
        out(f"wait {blocker}")
held = host_gate()
if held:
    out(f"hold {held}")
previous = previous_session()
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
    # a review a v1 reviewer wrote inside the worktree instead of the STAR folder (#35)
    rel = os.path.relpath(reviews, repo)
    stray_dir = os.path.join(place, rel)
    if not rel.startswith("..") and os.path.isdir(stray_dir):
        for n in sorted(os.listdir(stray_dir)):
            target = os.path.join(reviews, n)
            if re.fullmatch(re.escape(item) + r"-r\d+\.md", n) and not os.path.exists(target):
                os.makedirs(reviews, exist_ok=True)
                shutil.move(os.path.join(stray_dir, n), target)
                print(f"stage-start.sh: moved {os.path.join(stray_dir, n)} to {target}", file=sys.stderr)
if stage in ("build", "babysit"):
    worktree_sessions(place, previous)
if checks_previous():
    stop_gate()  # only now, with no hold session: a live session may be the one running it


def ensure_trust(setting_):
    if (setting_.get("agent") or "claude") == "claude" and not trusted_in_config(place) and not clear_trust(place):
        if started_row:
            # the row is already written (a fallback agent needed the dialogs): put it back to wait,
            # and keep live= so the next start replays this one instead of making a second task
            ledger("set", item, f"state={WAITING[stage]}")
        out(f"hold trust {place}")


def same_launch(a, b):
    """Two settings launch the same thing when agent, model and effort match."""
    return all((a.get(k) or None) == (b.get(k) or None) for k in ("agent", "model", "effort"))


ensure_trust(entry)
spec = prompt()
n = int(live) if replay and str(live).isdigit() else int(counters.get("start", "0") or 0) + 1
rid = f"star-{item}-{stage}-r{round_}-s{n}"


def request_id(key):
    """Orca takes only a UUID as --retry-request (#163); the same folder and key give the same one."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"juel-star:{home}#{key}"))


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
                f"{item} {stage} r{round_}", "--retry-request", request_id(rid), "--json"], 60)
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
    return run(cmd + ["--retry-request", request_id(f"{rid}-w{attempt}"), "--json"], 540)


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
