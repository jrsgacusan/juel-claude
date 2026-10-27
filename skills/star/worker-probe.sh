#!/bin/sh
# Tells STAR whether a worker is stuck at a screen it will never leave by itself, stalled on a
# model that is at capacity or on an API error, or making no progress, without putting the
# worker's screen into STAR's context.
#   worker-probe.sh <dispatch> [--item <item> --home <H> [--worktree <path>] [--deadline <minutes>]]
#     ->   ok | quiet <m> <terminal> | stale <m> <terminal> | settled <state> [<reason>]
#          | stuck: <label>[: <line>] | prompt bounded <terminal> <path>...
#          | stalled: model at capacity | stalled: usage-limit until <time> | stalled: api error
#          | gate-gone r<k> | gone | unknown <why>
#     ok, quiet and stale end with " holds-screen <m>" when --item holds the screen lock (#39): the holder
#     is "<project>/<item>" (project from star.json's project.name) or the bare item (#207).
# "gate-gone r<k>" (with --item and --home, for a worker that is not settled) means the newest gate
# round's <H>/reviews/<project>/<item>-r<k>.run names a pid (and gate pid) that is not alive while
# no verdict file <item>-r<k>.md exists: the codex gate died. The project is star.json's
# project.name, else every folder under reviews.
# <reason> follows only a failed settlement, when Orca gives one (agent_prompt_stalled: the agent
# never took its prompt, most often because Claude Code's trust dialog was on screen).
# "stuck" labels: usage limit, login (see below), trust dialog, model switch, confirmation dialog, waiting for
# input (a "press enter", a y/n or a password prompt). "stalled: model at capacity" is a capacity,
# overload or rate-limit error on screen: recoverable without the user (#41). The error type names
# overloaded_error and rate_limit_error count only on a line that also has "api error", an
# "error:" prefix or a 4xx/5xx status, so code or docs that name them are not a stall.
# "stalled: usage-limit until <time>" (#187) is a row that matches the usage-limit phrases and also says
# "continuing automatically at <time>" (Claude Code resumes by itself): <time> is the text after "at", up
# to a "·" or the end, trimmed, 40 characters at most. It is read after the capacity check and before the
# stuck phrases; a usage limit without "continuing automatically" stays "stuck: usage limit".
# "stuck: login" is followed by the worker's own login state (#206): the user's shell (STAR_LOGIN_SHELL,
# else $SHELL, else /bin/sh) runs `claude auth status` with -ic, stdin from /dev/null and a 30 s timeout, in
# the --worktree, else the terminal's worktreePath (orca terminal list), else the current folder, with
# CLAUDE_CONFIG_DIR removed from its environment so the folder and shell startup pick the profile. It
# prints "stuck: login: <config dir> logged out" (non-zero) or "stuck: login: <config dir> signed in"
# (zero), the dir being the shell's CLAUDE_CONFIG_DIR, else $HOME/.claude. A check that cannot run (no STAR_CFG= line,
# a timeout, no such shell) leaves the plain "stuck: login".
# "stalled: api error" (#123) is a worker that Claude Code left at an empty prompt under its own
# "API Error: <message>" row (a connection lost or a server error mid-response, the row starting
# with Claude Code's "⎿", "⏺" or "●"): read only on the rendered screen, after the capacity check
# and the phrase screens above (usage limit, login, trust dialog, model switch, a "No, exit" dialog,
# waiting for input), and before the numbered dialogs, the y/n prompt and any progress or quiet
# result, so a worker whose timer still writes progress lines is not "ok" while its screen can be
# read. The newest rows above the prompt must be that row and only its wrapped rows, with no
# "Retrying" in them and no "esc to interrupt" in the footer; a recap Claude Code printed under it
# while the worker sat idle ("※ recap: ...") is passed over first. An error above further output,
# code or docs that mention an API error inside a row, a retrying turn and a prompt someone is
# typing in are not a stall.
# A question with numbered options is "stuck: confirmation dialog: <line>", the line being the
# rm/rmdir safety line of the last dialog when it has one, else the last question, 120 characters at
# most; "stuck: confirmation dialog" alone is a "No, exit" screen. One such dialog STAR answers itself
# (#114), printed "prompt bounded <terminal> <operands>", only when all of these hold:
#   - the lines are the rendered screen of a worker with a terminal, never worker-read's text;
#   - the last question is "Do you want to proceed?" with a "1. Yes" option in the 3 lines after it;
#   - its safety line, "Dangerous rm|rmdir operation on possibly-empty variable path: <operand>", is
#     the last one in the 12 lines above it, with no other question, option or "Bash command"
#     header between the two;
#   - between the last "Bash command" header in those 12 lines and the safety line there are exactly
#     two rows, the command and its description, and the description holds no /, $ or ; (a command
#     wrapped onto a second row, a description posing as the header, or a missing description is
#     not bounded). The command holds <operand>. Nothing else on the screen is read for
#     assignments: Claude Code keeps no shell variables between Bash calls, so a previous call's
#     line says nothing about this one;
#   - the command is plain: NAME=<value> assignments (each NAME once, each used by an operand, no
#     value holding $, a backtick, "..", "~", a space or a glob or brace character), then one rm or
#     rmdir with options and operands, and nothing else (no &&, ||, |, &, $(, redirect or statement
#     after the removal);
#   - every operand, with the values put in, is an absolute path with no glob, brace or ".." and is
#     strictly below --worktree or a Claude Code session scratchpad,
#     (/private)/tmp/claude-<uid>/<project>/<session>/scratchpad/<something>, by its text and by its
#     realpath. The worktree or scratchpad root itself is not bounded.
# <operands> are those paths, normalized and space-separated. A check that fails is the stuck line.
# "stuck: account: <kind>" (#208) is a StopFailure only the owner can fix: account_on_hold, billing_error,
# verification_required, cloud_credential_error or model_not_found.
# The hook state (#208): hooks/worker-state.sh writes <H>/workers/<terminal>.json (H is --home, else the
# folder star-home.sh prints from the current directory) on every StopFailure and Notification, and clears it
# on SessionStart, UserPromptSubmit and Stop. A StopFailure names the stall (authentication_failed and
# oauth_org_not_allowed: stuck: login; account kinds: stuck: account: <kind>; overloaded: stalled: model at
# capacity; server_error, unknown, invalid_request, max_output_tokens: stalled: api error; rate_limit: the
# usage-limit lines when the screen has its phrases, else stalled: model at capacity), read before the screen
# phrases. quota_auto_resume_stale and _disabled are "stuck: usage limit". The input-wanting notifications
# (permission and elicitation prompts, idle_prompt, agent_needs_input) are only a hint: when the terminal printed
# nothing since the notification (2 s of slack) and the screen cannot be read as a dialog (a stream or
# screen-unavailable read), they are "stuck: confirmation dialog: <message>" (waiting for input: <message>
# for idle_prompt and agent_needs_input); otherwise the screen decides. No file, an unreadable one and
# every other state leave the screen to decide.
# The terminal is worker.agentTerminalHandle (Orca 1.4.230), else
# worker.agent_terminal_handle, else dispatch.assigneeHandle (#187, #191).
# With --item and --home, progress decides: the newest of <H>/progress/<item>.log, the worktree's
# last commit and the files the worktree has changed. With no --worktree (a brief or post worker changes
# nothing in a worktree), or a --worktree that is a main checkout (its git-dir is its git-common-dir; a
# build's own worktree is always a linked one), the newest of the log, the dispatch's lastHeartbeatAt
# (ISO or epoch milliseconds) and the terminal's lastOutputAt (orca terminal list; skipped when the
# terminal is not listed, and used only next to a log or a heartbeat: alone, the terminal rule below
# decides) (#191). No progress for --deadline minutes (default 30) is "stale <m> <terminal>". Without them, or with no progress source at all, the terminal
# decides: no output for STAR_QUIET_MINUTES (default 15) is "quiet <m> <terminal>".
# "gone" means Orca said dispatch_not_found (after an Orca restart) and nothing else: empty,
# shapeless or failing output is "unknown" and says nothing about the worker, so it never
# justifies starting a second one.
# The patterns are whole phrases from the agents' own blocking screens, looked for only where
# such a screen sits: the last lines of the rendered screen (orca terminal read --screen, when the
# worker has a terminal; #114: Orca 1.4.198's worker-read returns the hook transcript, which never
# shows a prompt), else worker-read's terminal tail and its newest transcript message when it is
# short (a top-level messages list, or transcript.messages[-1].blocks[*].text). A screen that cannot
# be read falls back to worker-read. A read whose source is "stream" or "screen-unavailable" (the
# accumulated output) is checked for the capacity, usage-limit and stuck phrases first (#187), then
# worker-read is read as well; the rules that need a rendered screen (the API error stall, the
# bounded prompt, the dialogs) never use it. Ordinary work
# that mentions "login", "rate limit" or "switch to main" does not match.
# STAR_NOW (ISO UTC) overrides the clock, for tests.
# Exit: 0, or 64 on bad usage.
STAR_SKILLS_DIR=$(cd "$(dirname "$0")/.." && pwd)
export STAR_SKILLS_DIR
exec python3 - "$@" <<'PY'
import json
import math
import os
import re
import subprocess
import sys
import time
from datetime import datetime

# Phrases from the blocking screens of Claude Code and Codex, as their own binaries print them.
PATTERNS = [
    ("usage limit", r"usage limit reached|hit your usage limit|limit will reset|out of extra usage"
                    r"|^\W*credit balance too low|^\W*you've reached your [\w .-]+ limit\b"
                    r"|^\W*your workspace is out of credits"),
    ("login", r"please run /login|^\W*not logged in\b|sign in (again )?to continue|^\W*invalid api key"
              r"|^\W*authentication required\b|^\W*invalid auth token\b|^\W*sign-in required"),
    ("trust dialog", r"do you trust the files in this folder|trust this folder"),
    ("model switch", r"would you like to switch (to|models?)\b|^\W*(\d+\.\s+)?switch to [\w .-]+ and continue\b"
                     r"|^\W*switch to [\w .-]+ for lower credit usage\?"),
    ("confirmation dialog", r"^\s*(❯\s*)?\d+\.\s+no, exit\b"),
    # Screens that wait for a key or a typed answer: a check-in line plus Enter would answer them.
    ("waiting for input", r"^\W*press (enter|return|any key)\b|^\W*(password|passphrase)( for [^:]*)?:\s*$"),
]
# A model at capacity, overloaded or rate limited: the agent waits, and a retry nudge restarts it (#41).
STALLED = (r"selected model is at capacity|\bmodel is at capacity\b"
           r"|\bapi error:?\s*(429|503|529)\b|^\W*(error:?\s*)?too many requests\b")
# The API's error type names count only on a line that also carries an API error: code or docs that
# merely name them are the worker reading, not the model failing.
STALLED_TYPE = r"overloaded_error|rate_limit_error"
API_ERROR = r"\bapi error\b|^\W*error:|\b[45]\d\d\b"
# #123: a model call that failed mid-turn leaves Claude Code at an empty prompt under its own
# "API Error: <message>" row (Claude Code 2.1.301: "API Error: Connection lost mid-response. ...",
# "API Error: Server error mid-response. ..."), after its "⎿", "⏺" or "●". Read only on the
# rendered screen; keep these shapes in step with stage-start.sh. The prompt is a rule row, the
# prompt row ("❯" or ">", inside a "│" frame on a boxed prompt, alone when empty, a no-break space
# included) and another rule row, with the footer below ("esc to interrupt" in it while a turn
# runs). The recap Claude Code prints on an idle terminal is a "※ recap: <text>" row. Matched as
# Claude Code writes it, case and all.
RULE = r"^\s*[╭╰]?─{3,}[╮╯]?\s*$"
PROMPT_ROW = r"^\s*│?\s*[❯>](\s|$)"
EMPTY_PROMPT = r"^\s*│?\s*[❯>]\s*│?\s*$"
API_ERROR_ROW = r"^\s*[⎿⏺●]\s*API Error:"
RECAP = r"^\s*※\s*recap:"
CONTINUED = r"^\s+[^\s⎿⏺●✽✻✶✳✢·*]"  # a wrapped row: indented, and no turn's glyph
# A y/n prompt counts only on the last line of the screen: mid-screen it is the worker talking about one.
YES_NO = r"[\[(](y/n|yes/no)[\])]\s*:?\s*$"
# A question counts as a dialog only with a numbered yes/no option on screen: prose asks
# questions too. Every permission prompt ("Do you want to make this edit to X?", "Do you want to
# create X?", "Would you like to run the following command?") has that shape, so none of them is
# ever reported as merely quiet: STAR's check-in ends with Enter, which would answer the prompt.
QUESTION = r"\b(do you want to|would you like to)\b.*\?\s*$"
OPTION = r"^\s*(❯\s*)?\d+\.\s+(yes|no)\b"
# #114: Claude Code's safety prompt for an rm or rmdir whose path holds a variable. STAR answers it
# only when the operand is bounded: see bounded_prompt().
SAFETY = r"dangerous (rm|rmdir) operation on possibly-empty variable path:\s*(\S+)"
PROCEED = r"\bdo you want to proceed\?"
YES_ONE = r"^\s*(❯\s*)?1\.\s+yes\b"
HEADER = r"^bash command$"
VAR = r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))"
ASSIGN = r"([A-Za-z_][A-Za-z0-9_]*)=(?:\"([^\"]*)\"|'([^']*)'|([^\s\"']*))"
# A value or path is plain when it holds only characters no shell treats specially: no $, backtick,
# quote, backslash, space, glob, brace or ~.
PLAIN = r"[\w./+@%:=,-]*"
# Names the shell itself reads: a plain assignment to one changes how the removal runs.
SHELL_NAMES = {"PATH", "IFS", "HOME", "CDPATH", "ENV", "BASH_ENV", "SHELLOPTS", "GLOBIGNORE", "PWD", "OLDPWD"}
SCRATCHPAD = r"^(/private)?/tmp/claude-[0-9]+/[^/]+/[^/]+/scratchpad/."
BOX = "│┃|║╭╮╰╯─━═ \t"  # a TUI frame around a line is not part of the line
USAGE = "usage: worker-probe.sh <dispatch> [--item <item> --home <H> [--worktree <path>] [--deadline <minutes>]]"


def out(line):
    print(line)
    sys.exit(0)


args, opts, dispatch = sys.argv[1:], {}, None
while args:
    arg = args.pop(0)
    if arg in ("--item", "--home", "--worktree", "--deadline"):
        if not args or not args[0].strip():
            print(USAGE, file=sys.stderr)
            sys.exit(64)
        opts[arg[2:]] = args.pop(0)
    elif arg.startswith("-") or dispatch is not None:
        print(USAGE, file=sys.stderr)
        sys.exit(64)
    else:
        dispatch = arg
if dispatch is None or ("item" in opts) != ("home" in opts):
    print(USAGE, file=sys.stderr)
    sys.exit(64)
orca = os.environ.get("ORCA_CLI_COMMAND") or "orca"
NOW = (datetime.fromisoformat(os.environ["STAR_NOW"].replace("Z", "+00:00")).timestamp()
       if os.environ.get("STAR_NOW") else time.time())


def call(*args):
    try:
        proc = subprocess.run([orca, "orchestration", *args, "--dispatch", dispatch, "--json"],
                              capture_output=True, text=True, timeout=30)
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        out(f"unknown {type(e).__name__}")
    try:
        data = json.loads(proc.stdout)
    except ValueError:
        data = None
    if proc.returncode != 0 or (isinstance(data, dict) and data.get("ok") is False):
        error = data.get("error") if isinstance(data, dict) else None
        codes = [error] if isinstance(error, str) else []
        if isinstance(error, dict):
            inner = error.get("data")
            codes = [error.get("code"), inner.get("code") if isinstance(inner, dict) else None]
        codes = [c for c in codes if isinstance(c, str) and c]
        first_err = ((proc.stderr or "").strip().splitlines() or [""])[0]
        if any(c.lower() == "dispatch_not_found" for c in codes) or "dispatch_not_found" in first_err.lower():
            out("gone")
        out("unknown " + (codes[0] if codes else first_err[:100] or "orca failed"))
    if not isinstance(data, dict) or not isinstance(data.get("result"), dict):
        out("unknown unreadable orca output")
    return data["result"]


TERMINAL = {"failed", "succeeded", "stopped", "cancelled", "canceled", "abandoned", "outcome_unknown"}
shown = call("worker-show")
worker = shown.get("worker") or {}
dispatch_record = shown.get("dispatch") or {}
if not isinstance(worker, dict) or not isinstance(dispatch_record, dict):
    out("unknown unreadable orca output")
if not worker and not dispatch_record:
    out("unknown no worker record")


def reason(state):
    """Orca's reason for a failed dispatch (agent_prompt_stalled), when it gives one."""
    if state != "failed":
        return ""
    for record in (dispatch_record, worker):
        for key in ("last_failure", "lastFailure"):
            value = record.get(key)
            if isinstance(value, dict):
                value = value.get("code") or value.get("reason")
            if isinstance(value, str) and re.fullmatch(r"[a-z][a-z0-9_]{0,60}", value):
                return " " + value
    return ""


if worker.get("stage") == "settled" or worker.get("state") in TERMINAL:
    state = worker.get("state") or "unknown"
    out("settled " + state + reason(state))
if dispatch_record.get("status") in ("completed", "failed"):
    out("settled " + dispatch_record["status"] + reason(dispatch_record["status"]))


def alive(pid):
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # it exists; it belongs to someone else
    except OSError:
        return False
    return True


def gate_gone():
    """With --item and --home: "gate-gone r<k>" when the newest gate round's run file names a process
    that is not alive and the round has no verdict file (I-9); None otherwise."""
    if "item" not in opts:
        return None
    base = os.path.join(opts["home"], "reviews")
    try:
        name = json.load(open(os.path.join(opts["home"], "star.json"), encoding="utf-8"))["project"]["name"]
        folders = [os.path.join(base, name)]
    except (OSError, ValueError, KeyError, TypeError):
        try:
            folders = [os.path.join(base, d) for d in sorted(os.listdir(base))]
        except OSError:
            return None
    runs = []
    for folder in folders:
        try:
            for entry in os.listdir(folder):
                m = re.fullmatch(re.escape(opts["item"]) + r"-r(\d+)\.run", entry)
                if m:
                    runs.append((int(m.group(1)), folder))
        except OSError:
            continue
    if not runs:
        return None
    k, folder = max(runs)
    try:
        run = json.load(open(os.path.join(folder, f"{opts['item']}-r{k}.run"), encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(run, dict) or alive(run.get("pid")) or alive(run.get("gate")):
        return None
    if os.path.exists(os.path.join(folder, f"{opts['item']}-r{k}.md")):
        return None
    return f"gate-gone r{k}"


_gone = gate_gone()
if _gone:
    out(_gone)


def screen_tail(handle):
    """(lines, source) of the terminal read: source is "screen" (the rendered screen, #114), "stream" or
    "screen-unavailable" (the accumulated output, #187); (None, None) when nothing could be read."""
    try:
        proc = subprocess.run([orca, "terminal", "read", "--terminal", handle, "--screen", "--json"],
                              capture_output=True, text=True, timeout=30)
        data = json.loads(proc.stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None, None
    result = data.get("result") if isinstance(data, dict) and data.get("ok") is not False else None
    term = result.get("terminal") if isinstance(result, dict) else None
    tail = term.get("tail") if isinstance(term, dict) else None
    if proc.returncode != 0 or not isinstance(tail, list) or not tail:
        return None, None
    source = term.get("source", "screen")
    if source not in ("screen", "stream", "screen-unavailable"):
        return None, None
    return [str(l) for l in tail], source


def newest_message(read):
    """The newest transcript message's text: a top-level messages list, or Orca 1.4.198's
    transcript.messages[-1].blocks[*].text."""
    messages = read.get("messages")
    transcript = read.get("transcript")
    if not isinstance(messages, list) and isinstance(transcript, dict):
        messages = transcript.get("messages")
    if not isinstance(messages, list) or not messages or not isinstance(messages[-1], dict):
        return ""
    newest = messages[-1]
    blocks = newest.get("blocks")
    if isinstance(blocks, list):
        return "\n".join(str(b.get("text")) for b in blocks if isinstance(b, dict) and b.get("text"))
    return str(newest.get("text") or newest.get("content") or "")


def first_of(*values):
    return next((v for v in values if isinstance(v, str) and v), None)


# #187, #191: Orca 1.4.230 names it agentTerminalHandle; the dispatch record's assigneeHandle is the same
handle = first_of(worker.get("agentTerminalHandle"), worker.get("agent_terminal_handle"),
                  dispatch_record.get("assigneeHandle"))
lines, source = screen_tail(handle) if handle else (None, None)
on_screen = source == "screen"
screen = lines if on_screen else []  # the whole rendered screen, frames and rules kept, for the API error rule only (#123)
stream = lines if lines is not None and not on_screen else None  # accumulated output: phrase checks only (#187)


def clean(raw):
    rows = [l.strip(BOX) for l in raw]
    return rows, [l for l in rows if len(l) <= 200]


def at_capacity(line):
    if re.search(STALLED, line, re.IGNORECASE):
        return True
    return bool(re.search(STALLED_TYPE, line, re.IGNORECASE) and re.search(API_ERROR, line, re.IGNORECASE))


def worker_folder():
    """Where the worker's terminal runs: --worktree, else the terminal's worktreePath, else here."""
    if opts.get("worktree") and os.path.isdir(opts["worktree"]):
        return opts["worktree"]
    try:
        proc = subprocess.run([orca, "terminal", "list", "--limit", "500", "--json"],
                              capture_output=True, text=True, timeout=30)
        for t in json.loads(proc.stdout)["result"]["terminals"]:
            if isinstance(t, dict) and t.get("handle") == handle and isinstance(t.get("worktreePath"), str) \
                    and os.path.isdir(t["worktreePath"]):
                return t["worktreePath"]
    except Exception:
        pass
    return None


def login_line():
    """#206: "stuck: login: <config dir> logged out|signed in", from `claude auth status` run the way the
    worker's terminal runs it (the user's shell, interactive, in the worker's folder); the plain line
    when the check cannot run."""
    shell = os.environ.get("STAR_LOGIN_SHELL") or os.environ.get("SHELL") or "/bin/sh"
    check = "printf 'STAR_CFG=%s\\n' \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"; claude auth status >/dev/null 2>&1"
    # Without our CLAUDE_CONFIG_DIR: the worker's folder and shell startup decide the profile (#206).
    env = {k: v for k, v in os.environ.items() if k != "CLAUDE_CONFIG_DIR"}
    try:
        proc = subprocess.run([shell, "-ic", check], stdin=subprocess.DEVNULL, capture_output=True, text=True,
                              timeout=30, cwd=worker_folder(), env=env)
    except (OSError, subprocess.TimeoutExpired):
        return "stuck: login"
    config = next((l[len("STAR_CFG="):].strip() for l in proc.stdout.splitlines() if l.startswith("STAR_CFG=")), "")
    if not config:
        return "stuck: login"
    return f"stuck: login: {config} " + ("signed in" if proc.returncode == 0 else "logged out")


def phrase_stop(lines):
    """The capacity check, the usage-limit stall and the blocking phrases (#41, #187): the result line, or None."""
    if any(at_capacity(l) for l in lines):
        return "stalled: model at capacity"
    for l in lines:  # a usage limit that resumes by itself: STAR keeps the worker
        if re.search(PATTERNS[0][1], l, re.IGNORECASE):
            m = re.search(r"continuing automatically at\s+([^·]*)", l, re.IGNORECASE)
            if m and m.group(1).strip():
                return "stalled: usage-limit until " + m.group(1).strip()[:40].strip()
    for label, pattern in PATTERNS:
        if any(re.search(pattern, l, re.IGNORECASE) for l in lines):
            return login_line() if label == "login" else "stuck: " + label
    return None


def epoch_seconds(value):
    """Seconds since the epoch for an ISO string or epoch milliseconds (#191); None when unreadable."""
    if isinstance(value, bool):
        return None
    if isinstance(value, str) and re.fullmatch(r"\d+(\.\d+)?", value.strip()):
        value = float(value)
    if isinstance(value, (int, float)):
        return value / 1000 if value > 1e11 else value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return None
    return None


def terminal_output_time():
    """The terminal's lastOutputAt in seconds, or None when the list or the terminal cannot be read."""
    try:
        proc = subprocess.run([orca, "terminal", "list", "--limit", "500", "--json"],
                              capture_output=True, text=True, timeout=30)
        terminals = json.loads(proc.stdout)["result"]["terminals"]
        last = next((t.get("lastOutputAt") for t in terminals if isinstance(t, dict) and t.get("handle") == handle), None)
    except Exception:
        return None
    return epoch_seconds(last) if isinstance(last, (int, float)) else None


def hook_state():
    """#208: (event, kind, message, at in seconds) from <H>/workers/<terminal>.json, or None."""
    if not handle or not re.fullmatch(r"[A-Za-z0-9_.-]+", handle):
        return None
    home = opts.get("home")
    if not home:
        try:
            script = os.path.join(os.environ["STAR_SKILLS_DIR"], "star", "star-home.sh")
            home = subprocess.run(["sh", script, "path"], capture_output=True, text=True, timeout=30).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            return None
    try:
        data = json.load(open(os.path.join(home, "workers", handle + ".json"), encoding="utf-8"))
        if not isinstance(data, dict) or data.get("handle") not in (None, handle):
            return None
        at = epoch_seconds(data.get("at"))
        text = " ".join(str(data.get("message") or "").split())[:120]
        return str(data.get("event") or ""), str(data.get("kind") or ""), text, at
    except (OSError, ValueError):
        return None


STATE = hook_state()
STATE_LINES = {}
for _kinds, _line in ((("overloaded",), "stalled: model at capacity"),
                      (("server_error", "unknown", "invalid_request", "max_output_tokens"), "stalled: api error"),
                      (("authentication_failed", "oauth_org_not_allowed"), None)):
    for _kind in _kinds:
        STATE_LINES[("StopFailure", _kind)] = _line
for _kind in ("account_on_hold", "billing_error", "verification_required", "cloud_credential_error", "model_not_found"):
    STATE_LINES[("StopFailure", _kind)] = "stuck: account: " + _kind
for _kind in ("quota_auto_resume_stale", "quota_auto_resume_disabled"):
    STATE_LINES[("Notification", _kind)] = "stuck: usage limit"
if STATE and (STATE[0], STATE[1]) in STATE_LINES:
    out(STATE_LINES[(STATE[0], STATE[1])] or login_line())

if stream is not None:  # the stream's phrases first, then worker-read's below (#187)
    hit = phrase_stop(clean(stream[-25:])[1])
    if hit:
        out(hit)
if on_screen:
    lines = lines[-25:]
else:
    read = call("worker-read", "--limit", "40")
    terminal = read.get("terminal")
    lines = [str(l) for l in (terminal.get("tail") or [])][-25:] if isinstance(terminal, dict) else []
    newest = newest_message(read)
    if len(newest) <= 400:  # a blocking notice is short; a long message is the worker talking
        lines += newest.splitlines()
rows, lines = clean(lines)
hit = phrase_stop(lines)
if hit:
    out(hit)
if STATE and STATE[:2] == ("StopFailure", "rate_limit"):
    out("stalled: model at capacity")  # no usage-limit phrase on screen: the API said it is rate limited
HINTS = {"permission_prompt": "confirmation dialog", "worker_permission_prompt": "confirmation dialog",
         "elicitation_dialog": "confirmation dialog", "elicitation_url_dialog": "confirmation dialog",
         "agent_needs_input": "waiting for input", "idle_prompt": "waiting for input"}
if STATE and STATE[0] == "Notification" and STATE[1] in HINTS and STATE[3] is not None \
        and source in ("stream", "screen-unavailable"):
    printed = terminal_output_time()
    if printed is not None and printed <= STATE[3] + 2:
        out("stuck: " + HINTS[STATE[1]] + ": " + STATE[2])


def api_error_stall(screen):
    """#123: True when the newest rows above the rendered screen's empty prompt are one Claude Code
    "API Error:" block (its row, then only wrapped rows) that is not retrying, with no turn running.
    A recap Claude Code printed under the error while the worker sat idle is passed over however many
    rows it wraps onto."""
    prompt = next((i for i in range(len(screen) - 2, 0, -1)
                   if re.match(PROMPT_ROW, screen[i]) and re.match(RULE, screen[i - 1]) and re.match(RULE, screen[i + 1])), None)
    if prompt is None or not re.match(EMPTY_PROMPT, screen[prompt]) \
            or any("esc to interrupt" in r for r in screen[prompt + 2:]):
        return False
    above = [r for r in screen[:prompt - 1] if r.strip()]
    recap = next((j for j in range(len(above) - 1, -1, -1) if re.match(RECAP, above[j])), None)
    if recap is not None and all(re.match(CONTINUED, r) for r in above[recap + 1:]):
        above = above[:recap]  # the idle terminal's recap, under the error
    head = next((j for j in range(len(above) - 1, -1, -1) if re.match(API_ERROR_ROW, above[j])), None)
    if head is None:
        return False
    block = above[head:]
    return all(re.match(CONTINUED, r) for r in block[1:]) \
        and not re.search(r"\bretrying\b", " ".join(block), re.IGNORECASE)


# after the capacity check and the phrase screens, so their labels win; before the numbered dialogs,
# the y/n prompt, progress and quiet (#123). screen is empty unless the rendered screen was read
if api_error_stall(screen):
    out("stalled: api error")


def inside(path, root):
    """Strictly below root: the root itself is not."""
    return path.startswith(root.rstrip("/") + "/")


def last_dialog(rows):
    """(the last question's index, the index of its rm/rmdir safety line or None): the nearest safety
    line in the 12 lines above the question, unless another question, option or Bash command header
    sits between them, which makes it another dialog's."""
    ask = next((i for i in range(len(rows) - 1, -1, -1) if re.search(QUESTION, rows[i], re.IGNORECASE)), None)
    if ask is None:
        return None, None
    for i in range(ask - 1, max(ask - 13, -1), -1):
        if re.search(SAFETY, rows[i], re.IGNORECASE):
            return ask, i
        if any(re.search(p, rows[i], re.IGNORECASE) for p in (QUESTION, OPTION, HEADER)):
            break
    return ask, None


def plain_command(command):
    """(values, operands) of `NAME=value; ...; rm|rmdir [-options] operands`, else None."""
    if re.search(r"[|&`<>\\\r\n]|\$\(", command):
        return None
    *before, removal = [part.strip() for part in command.split(";")]
    values = {}
    for part in before:
        m = re.fullmatch(ASSIGN, part)
        if not m:
            return None
        name, value = m.group(1), next(g for g in m.groups()[1:] if g is not None)
        if name in values or name in SHELL_NAMES or ".." in value or not re.fullmatch(PLAIN, value):
            return None
        values[name] = value
    words = removal.split()
    if not words or words[0] not in ("rm", "rmdir"):
        return None
    operands = words[1:]
    while operands and operands[0].startswith("-"):
        operands.pop(0)
    return (values, operands) if operands else None


def bounded_prompt(rows, on_screen):
    """#114 (design 3.5): the operands of Claude Code's variable-path rm/rmdir safety prompt, values
    put in and normalized and space-separated, when the last dialog on the rendered screen is that
    prompt, its own command is plain, and every operand is strictly below the row's worktree or a
    Claude Code session scratchpad; else None."""
    if not on_screen:
        return None
    ask, at = last_dialog(rows)
    if at is None or not re.search(PROCEED, rows[ask], re.IGNORECASE) \
            or not any(re.search(YES_ONE, l, re.IGNORECASE) for l in rows[ask + 1:ask + 4]):
        return None
    named = re.search(SAFETY, rows[at], re.IGNORECASE).group(2)
    header = next((i for i in range(at - 1, max(ask - 13, -1), -1) if re.search(HEADER, rows[i], re.IGNORECASE)), None)
    if header is None:
        return None
    shown = [l for l in rows[header + 1:at] if l]
    if len(shown) != 2 or re.search(r"[/$;]", shown[1]):  # the command and its plain description
        return None
    command = shown[0]
    parsed = plain_command(command) if named in command else None
    if not parsed:
        return None
    values, operands = parsed
    if {m.group(1) or m.group(2) for o in operands for m in re.finditer(VAR, o)} != set(values):
        return None
    wt = opts.get("worktree")
    resolved = []
    for operand in operands:
        path = re.sub(VAR, lambda m: values[m.group(1) or m.group(2)], operand)
        if not re.fullmatch("/" + PLAIN, path) or ".." in path.split("/"):
            return None
        path = os.path.normpath(path)
        real = os.path.realpath(path)
        in_worktree = wt and any(inside(path, r) for r in (os.path.normpath(wt), os.path.realpath(wt))) \
            and inside(real, os.path.realpath(wt))
        if not in_worktree and not (re.match(SCRATCHPAD, path) and re.match(SCRATCHPAD, real)):
            return None
        resolved.append(path)
    return " ".join(resolved)


if any(re.search(QUESTION, l, re.IGNORECASE) for l in lines) and any(re.search(OPTION, l, re.IGNORECASE) for l in lines):
    bounded = bounded_prompt(rows, on_screen)
    if bounded:
        out(f"prompt bounded {handle} {bounded}")
    ask, at = last_dialog(lines)
    out("stuck: confirmation dialog: " + lines[ask if at is None else at].strip()[:120])
last_line = next((l for l in reversed(lines) if l.strip()), "")
if re.search(YES_NO, last_line, re.IGNORECASE) and not last_line.lstrip().startswith(("⏺", "●", "-", "*")):
    out("stuck: waiting for input")


def screen_suffix():
    """" holds-screen <m>" when --item holds the machine's screen lock (#39): its holder label is
    "<project>/<item>" (project from star.json's project.name) or the bare item (#207)."""
    if "item" not in opts:
        return ""
    script = os.path.join(os.environ["STAR_SKILLS_DIR"], "ship-ticket", "screen-lock.sh")
    try:
        status = subprocess.run(["sh", script, "status"], capture_output=True, text=True, timeout=30).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""
    m = re.match(r"held by (\S+) since (\S+)", status)
    label = "_".join(opts["item"].split())
    try:
        project = json.load(open(os.path.join(opts["home"], "star.json"), encoding="utf-8"))["project"]["name"]
    except (OSError, ValueError, KeyError, TypeError):
        project = None
    mine = {label} | ({"_".join(project.split()) + "/" + label} if isinstance(project, str) and project else set())
    if not m or m.group(1) not in mine:
        return ""
    try:
        since = datetime.fromisoformat(m.group(2).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return ""
    return f" holds-screen {max(int((NOW - since) // 60), 0)}"


def git_dir(wt, flag):
    r = subprocess.run(["git", "-C", wt, "rev-parse", flag], capture_output=True, text=True, timeout=30)
    return os.path.realpath(os.path.join(wt, r.stdout.strip())) if r.returncode == 0 and r.stdout.strip() else None


def linked_worktree(wt):
    """#191: the folder when it is a linked worktree (or not a git folder at all); None when it is a main
    checkout, whose own worktree is never the build's."""
    if not wt or not os.path.isdir(wt):
        return None
    try:
        git, common = git_dir(wt, "--git-dir"), git_dir(wt, "--git-common-dir")
    except (OSError, subprocess.TimeoutExpired):
        return wt
    return None if git and git == common else wt


def progress_minutes():
    """Whole minutes since the item last made progress; None when there is nothing to read."""
    times = []
    log = os.path.join(opts["home"], "progress", f"{opts['item']}.log")
    if os.path.isfile(log):
        times.append(os.path.getmtime(log))
    wt = linked_worktree(opts.get("worktree"))
    if wt is None:
        # a brief or post worker changes nothing in a worktree, but it keeps a heartbeat and a streaming terminal (#191)
        beat = epoch_seconds(dispatch_record.get("lastHeartbeatAt"))
        if beat is not None:
            times.append(beat)
        if times:  # with nothing else to go on the terminal rule below decides, on its own threshold
            output = terminal_output_time()
            if output is not None:
                times.append(output)
    else:
        try:
            r = subprocess.run(["git", "-C", wt, "log", "-1", "--format=%ct"], capture_output=True, text=True, timeout=30)
            if r.returncode == 0 and r.stdout.strip().isdigit():
                times.append(int(r.stdout.strip()))
            r = subprocess.run(["git", "-C", wt, "status", "--porcelain", "-z", "--untracked-files=all"],
                               capture_output=True, text=True, timeout=30)
            for entry in (r.stdout.split("\0") if r.returncode == 0 else [])[:500]:
                if len(entry) < 4:  # "XY <path>" is 4 or more: the trailing empty entry would name the root
                    continue
                try:
                    times.append(os.path.getmtime(os.path.join(wt, entry[3:])))
                except (OSError, ValueError):
                    pass
        except (OSError, subprocess.TimeoutExpired):
            pass
    return max(int((NOW - max(times)) // 60), 0) if times else None


def quiet_minutes(handle):
    """Whole minutes since the worker's terminal last printed; None when the list cannot be read.
    A running worker whose terminal is not in a readable list, or whose last output is dated in
    the future, is "unknown": saying "ok" would hide a worker nobody can see."""
    try:
        proc = subprocess.run([orca, "terminal", "list", "--limit", "500", "--json"],
                              capture_output=True, text=True, timeout=30)
        terminals = json.loads(proc.stdout)["result"]["terminals"]
    except Exception:
        return None
    last = next((t.get("lastOutputAt") for t in terminals if isinstance(t, dict) and t.get("handle") == handle), None)
    if not isinstance(last, (int, float)):
        out("unknown terminal not listed")
    minutes = int((NOW * 1000 - float(last)) // 60000)
    if minutes < -1:
        out("unknown clock skew")
    return max(minutes, 0)


if "item" in opts:
    try:
        deadline = float(opts.get("deadline", "30"))
    except ValueError:
        deadline = 30.0
    if not math.isfinite(deadline) or deadline <= 0:
        deadline = 30.0
    progress = progress_minutes()
    if progress is not None:
        if progress >= deadline:
            out(f"stale {progress} {handle or '-'}" + screen_suffix())
        out("ok" + screen_suffix())
try:
    threshold = float(os.environ.get("STAR_QUIET_MINUTES", "15"))
except ValueError:
    threshold = 15.0
if not math.isfinite(threshold) or threshold <= 0:
    threshold = 15.0
minutes = quiet_minutes(handle) if handle else None
if minutes is not None and minutes >= threshold:
    out(f"quiet {minutes} {handle}" + screen_suffix())
out("ok" + screen_suffix())
PY
