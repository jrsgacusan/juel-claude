#!/bin/sh
# STAR's second-model gate: one headless `codex review` of a branch against its base, with the
# brief as the contract, written to STAR's home and read back as one verdict line.
#   codex-gate.sh --brief <brief> --item <item> --round <k> --base <ref>
#                 [--model <id>] [--effort <level>] [--fallback <id|latest-<family>>]
#   codex-gate.sh post-pass --pr <url> --round <k> --head <sha> [--review <path>]
#                 [--model <id>] [--effort <level>]
# The gate prints one line:
#   SAFE round=<k> findings=<n> head=<sha> review=<path>
#   NOT-SAFE round=<k> findings=<n> p0=<a> p1=<b> head=<sha> review=<path>
#   ERROR <why>
# post-pass prints: posted <url> | already <url> | ERROR <why>
# Run the gate from the item's worktree. The brief's star: block gives home, project, notes,
# reviews and gates. Model, effort and fallback come from the flags, else star.json's "gate"
# block, else gpt-6-astra, xhigh and latest-sol (resolved by ../ship-ticket/executor-model.sh).
# The prompt is template/gate-prompt.md, kept as <home>/specs/<project>/<item>-gate-r<k>.md.
# codex review runs read-only with no MCP servers; its stdout goes to <reviews>/<item>-r<k>.raw.md
# and its stderr to <item>-r<k>.log. <item>-r<k>.md starts with the VERDICT line review-proof.sh
# reads. Only a [P0] or [P1] finding makes it NOT-SAFE. A capacity, overload or rate-limit failure
# is retried after 60 and 180 seconds, then run once on the fallback model (a fallback that does
# not resolve is ERROR, naming why); any other failure, an empty review, findings without [P<n>]
# tags (a "Review comment(s):" header with no tagged finding, or a bullet that ends
# " — <path>:<line>" or " — <path>:<line>-<line>" with no tag), or HEAD moving during the review
# is ERROR.
# post-pass posts "Codex gate: PASS (head <sha>, round <k>, <model> <effort>)" on the PR, once per
# head; --head must be the PR's current head, all 40 characters. The model and effort are
# --model and --effort, else the "Gate: <model> <effort>" line of the --review file (the model
# that ran, a fallback included), else the "gate" block of the project's star.json
# ($JUEL_STAR_HOME, else the folder star-home.sh names), else gpt-6-astra and xhigh. A --review
# file that cannot be read is ERROR.
# Test seams: CODEX_GATE_SLEEP multiplies the waits (default 1); CODEX_GATE_TIMEOUT, seconds per
# codex run (default 3600).
# Exit: 0 with a verdict or a post-pass result, 69 with ERROR, 64 on bad usage.
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
export STAR_SKILL_DIR
exec python3 - "$@" <<'PY'
import json
import os
import re
import subprocess
import sys
import time

S = os.environ["STAR_SKILL_DIR"]
CAPACITY = re.compile(r"at capacity|overloaded|rate.?limit|too many requests|service unavailable"
                      r"|\b(429|503|529)\b", re.I)
TAG = re.compile(r"^\s*-\s*\[P([0-3])\]\s+(.*\S)\s*$")
FINDINGS_HEADER = re.compile(r"^\s*review comments?:\s*$", re.I)
# The shape of a finding with its tag dropped: a bullet at the margin that ends " — <path>:<line>[-<line>]"
PLACED = re.compile(r"^-\s+(?!\[P[0-3]\]).*\S\s+—\s+\S.*:\d+(?:-\d+)?\s*$")


def out(line, code=0):
    print(line)
    sys.exit(code)


def error(why):
    out(f"ERROR {why}", 69)


def die(msg):
    print(f"codex-gate.sh: {msg}", file=sys.stderr)
    sys.exit(64)


def run(cmd, timeout=120):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 127, "", f"{cmd[0]}: {e}")


def last_line(text):
    lines = [l.strip() for l in (text or "").splitlines() if l.strip()]
    return lines[-1][:160] if lines else ""


def options(argv, names):
    found, args = {}, list(argv)
    while args:
        arg = args.pop(0)
        if arg not in names or not args or not args[0].strip():
            die(f"unknown or empty argument: {arg}")
        found[arg[2:]] = args.pop(0).strip()
    return found


def project_gate():
    """star.json's "gate" block, for post-pass, which has no brief: $JUEL_STAR_HOME, else star-home.sh path."""
    home = os.environ.get("JUEL_STAR_HOME") or run(["sh", os.path.join(S, "star-home.sh"), "path"], 30).stdout.strip()
    try:
        gate = json.load(open(os.path.join(home, "star.json"), encoding="utf-8")).get("gate") if home else None
    except (OSError, ValueError, AttributeError):
        gate = None
    return gate if isinstance(gate, dict) else {}


def post_pass(o):
    head = o["head"].lower()
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        die("--head takes the full 40-character commit")
    ran = None
    if o.get("review"):
        try:
            ran = re.search(r"^Gate: (\S+) (\S+)", open(o["review"], encoding="utf-8", errors="replace").read(), re.M)
        except OSError as e:
            error(f"cannot read the review: {e.strerror}")
    model, effort = o.get("model") or (ran and ran.group(1)), o.get("effort") or (ran and ran.group(2))
    if not model or not effort:
        gate = project_gate()
        model, effort = model or gate.get("model") or "gpt-6-astra", effort or gate.get("effort") or "xhigh"
    view = run(["gh", "pr", "view", o["pr"], "--json", "author,comments,headRefOid,url"], 60)
    if view.returncode != 0:
        error("gh: " + (last_line(view.stderr or view.stdout) or "failed"))
    try:
        d = json.loads(view.stdout)
        author = (d.get("author") or {}).get("login") or ""
        comments = [c for c in (d.get("comments") or []) if isinstance(c, dict)]
    except (ValueError, AttributeError):
        error("gh: unreadable output")
    pr_head = str(d.get("headRefOid") or "").lower()
    if pr_head != head:
        error(f"the PR's head is {pr_head[:7] or '?'}, not {head[:7]}")
    prefix = f"Codex gate: PASS (head {head}"
    for c in comments:
        if (c.get("author") or {}).get("login") == author and str(c.get("body") or "").startswith(prefix):
            out(f"already {c.get('url') or d.get('url')}")
    posted = run(["gh", "pr", "comment", o["pr"], "--body",
                  f"Codex gate: PASS (head {head}, round {o['round']}, {model} {effort})"], 60)
    if posted.returncode != 0:
        error("gh: " + (last_line(posted.stderr or posted.stdout) or "failed"))
    out(f"posted {last_line(posted.stdout) or d.get('url')}")


argv = sys.argv[1:]
if argv[:1] == ["post-pass"]:
    o = options(argv[1:], ("--pr", "--round", "--head", "--review", "--model", "--effort"))
    for key in ("pr", "round", "head"):
        if key not in o:
            die(f"post-pass needs --{key}")
    if not o["round"].isdigit():
        die("--round takes a number")
    post_pass(o)

o = options(argv, ("--brief", "--item", "--round", "--base", "--model", "--effort", "--fallback"))
for key in ("brief", "item", "round", "base"):
    if key not in o:
        die(f"the gate needs --{key}")
if not o["round"].isdigit() or int(o["round"]) < 1:
    die("--round takes a number from 1")
item, k, base, brief = o["item"], int(o["round"]), o["base"], os.path.abspath(o["brief"])


def star_block(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        die(f"cannot read the brief: {e.strerror}")
    m = re.match(r"﻿?---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
    found, inside = {}, False
    for line in (m.group(1).splitlines() if m else []):
        kv = re.match(r"(\s*)([A-Za-z_]+):\s*(.*?)\s*$", line)
        if not kv:
            continue
        if not kv.group(1):
            inside = kv.group(2) == "star"
        elif inside:
            found[kv.group(2)] = kv.group(3).strip("'\"")
    return found


star = star_block(brief)
home, project = star.get("home"), star.get("project")
if not home or not project:
    die("the brief has no star: block with home and project")
reviews = star.get("reviews") or os.path.join(home, "reviews", project)
notes = [n.strip().strip("'\"") for n in star.get("notes", "").strip("[]").split(",") if n.strip()]
gates_dir = os.path.dirname(star.get("gates") or os.path.join(home, "gates", project, f"{item}.json"))
try:
    gate = json.load(open(os.path.join(home, "star.json"), encoding="utf-8")).get("gate")
except (OSError, ValueError, AttributeError):
    gate = None
gate = gate if isinstance(gate, dict) else {}
model = o.get("model") or gate.get("model") or "gpt-6-astra"
effort = o.get("effort") or gate.get("effort") or "xhigh"
fallback = o.get("fallback") or gate.get("fallback") or "latest-sol"
try:
    LIMIT = float(os.environ.get("CODEX_GATE_TIMEOUT", "3600"))
except ValueError:
    LIMIT = 3600.0
try:
    PAUSE = float(os.environ.get("CODEX_GATE_SLEEP", "1"))
except ValueError:
    PAUSE = 1.0


def prompt_text():
    template = open(os.path.join(S, "template", "gate-prompt.md"), encoding="utf-8").read()
    if k >= 2:
        previous = (f"Previous round: {os.path.join(reviews, f'{item}-r{k - 1}.md')}, and the dispositions "
                    f"of the findings that were not fixed in {os.path.join(reviews, f'{item}-r{k - 1}-fix.md')} "
                    "when that file exists.")
    else:
        previous = "This is round 1: there is no previous review."
    try:
        pending = [l.strip() for l in open(os.path.join(gates_dir, f"{item}-screen.md"), encoding="utf-8") if l.strip()]
    except OSError:
        pending = []
    pending_text = ("Pending at the screen, verified separately with a person and never a finding here: "
                    + "; ".join(pending)) if pending else "No check is pending at the screen."
    values = {"item": item, "round": str(k), "base": base, "brief": brief, "notes": ", ".join(notes) or "none",
              "previous": previous, "pending": pending_text}
    return re.sub(r"\{\{(\w+)\}\}", lambda m: values.get(m.group(1), m.group(0)), template)


def head():
    r = run(["git", "rev-parse", "HEAD"], 30)
    return r.stdout.strip().lower() if r.returncode == 0 else ""


os.makedirs(reviews, exist_ok=True)
specs = os.path.join(home, "specs", project)
os.makedirs(specs, exist_ok=True)
review_path = os.path.join(reviews, f"{item}-r{k}.md")
raw_path = os.path.join(reviews, f"{item}-r{k}.raw.md")
log_path = os.path.join(reviews, f"{item}-r{k}.log")
prompt = prompt_text()
with open(os.path.join(specs, f"{item}-gate-r{k}.md"), "w", encoding="utf-8") as f:
    f.write(prompt)
before = head()
if not re.fullmatch(r"[0-9a-f]{40}", before):
    error("not inside a git checkout")


def review(model_, effort_):
    cmd = ["codex", "review", prompt, "--strict-config", "-c", f'model="{model_}"',
           "-c", f'model_reasoning_effort="{effort_}"', "-c", 'sandbox_mode="read-only"', "-c", "mcp_servers={}"]
    start = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    try:
        with open(raw_path, "w", encoding="utf-8") as so, open(log_path, "a", encoding="utf-8") as se:
            se.write(f"--- codex review {model_} {effort_} {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n")
            se.flush()
            rc = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=so, stderr=se, timeout=LIMIT).returncode
    except FileNotFoundError:
        error("codex not found on PATH")
    except subprocess.TimeoutExpired:
        rc = 124
    with open(log_path, encoding="utf-8", errors="replace") as f:
        f.seek(start)
        tail = "\n".join(f.read().splitlines()[1:])  # this attempt's stderr, without the script's own header line
    return rc, open(raw_path, encoding="utf-8", errors="replace").read(), tail


def fallback_model():
    """(model, effort) for the fallback run, or (None, why) when it cannot be resolved."""
    if not fallback.startswith("latest-"):
        return fallback, effort
    r = run(["sh", os.path.join(os.path.dirname(S), "ship-ticket", "executor-model.sh"),
             "--model", fallback, "--effort", effort], 60)
    words = r.stdout.split()
    if r.returncode == 0 and len(words) == 2 and words[0] != "default":
        return words[0], words[1]
    if r.returncode == 0 and words[:1] == ["default"]:
        return None, " ".join(words[1:]) or "executor-model.sh named no model"
    return None, last_line(r.stderr or r.stdout) or f"executor-model.sh exited {r.returncode}"


used, text, tail = None, "", ""
for m_, e_, wait in ((model, effort, 0), (model, effort, 60), (model, effort, 180), (None, None, 0)):
    if m_ is None:
        m_, e_ = fallback_model()
        if m_ is None:
            error("codex review at capacity after 3 tries; no fallback: " + e_)
    if wait:
        time.sleep(wait * PAUSE)
    rc, text, tail = review(m_, e_)
    if rc == 0 and text.strip():
        used = (m_, e_)
        break
    if rc == 0:
        error("empty review")
    if not CAPACITY.search(tail):
        error("codex review failed: " + (last_line(tail) or f"exit {rc}"))
if used is None:
    error("codex review at capacity after 3 tries and the fallback: " + (last_line(tail) or "no output"))
after = head()
if after != before:
    error(f"HEAD moved during the review ({before[:7]} to {after[:7] or '?'})")

findings, overall, current, listing, untagged = [], [], None, False, False
for line in text.splitlines():
    tag = TAG.match(line)
    if tag:
        title, _, where = tag.group(2).rpartition(" — ")
        current = {"p": int(tag.group(1)), "title": (title or tag.group(2)).strip(),
                   "where": where.strip() if title else "", "body": []}
        findings.append(current)
        listing = True
    elif PLACED.match(line):
        untagged = True
    elif current is not None and line[:1].isspace() and line.strip():
        current["body"].append(line.strip())
    elif FINDINGS_HEADER.match(line):
        listing = True
    elif not listing and line.strip():
        overall.append(line.strip())
if untagged or (listing and not findings):
    error("unreadable review: findings without [P0]-[P3] tags")
p0 = sum(1 for f in findings if f["p"] == 0)
p1 = sum(1 for f in findings if f["p"] == 1)
verdict = "NOT-SAFE" if p0 + p1 else "SAFE"
lines = [f"VERDICT item={item} round={k} {verdict} findings={len(findings)} head={after}", "", "## Findings"]
for i, f in enumerate(findings, 1):
    lines.append(f"{i}. [P{f['p']}] {f['title']}" + (f" — {f['where']}" if f["where"] else ""))
    lines += ["   " + b for b in f["body"]]
if not findings:
    lines.append("none")
lines += ["", "## Notes", " ".join(overall) or "-", "",
          f"Gate: {used[0]} {used[1]} · base {base} · raw {raw_path} · log {log_path}"]
tmp = f"{review_path}.tmp.{os.getpid()}"
with open(tmp, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
os.replace(tmp, review_path)
if verdict == "SAFE":
    out(f"SAFE round={k} findings={len(findings)} head={after} review={review_path}")
out(f"NOT-SAFE round={k} findings={len(findings)} p0={p0} p1={p1} head={after} review={review_path}")
PY
