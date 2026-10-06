#!/bin/sh
# STAR's handoff file: what needs the user before they leave, and a summary every few hours
# while they are away. It only reads STAR's own small files (queue, ledger, sent.log, star.json).
#   handoff.sh [--home <dir>] start      write handoff.md, mark away in star.json, print its path
#   handoff.sh [--home <dir>] due [--hours N]   -> due | not-due | not-away   (default 4 hours)
#   handoff.sh [--home <dir>] summary    add a dated summary at the top of handoff.md
#   handoff.sh [--home <dir>] latest     print the newest summary
#   handoff.sh [--home <dir>] end        clear away, stamp the file, print the newest summary
# Answers are never collected here: the queue (open-loops.md) is the one place to answer.
# Exit: 0 ok, 1 not possible (summary while not away, files missing), 64 usage.
# STAR_NOW (ISO UTC) and STAR_MEM_GB override the clock and the memory reading, for tests.
exec python3 - "$@" <<'PY'
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

ITEM_RE = re.compile(r"^### (N-\d+) · (.*?) · (.*?) · (.*)$")
BLOCKING = {"approve-brief", "question", "escalation", "restart-or-drop"}
OVERNIGHT = {
    "inbox": "a worker drafts its brief, then it waits for your approval",
    "briefing": "its brief is being drafted, then it waits for your approval",
    "brief-ready": "waits for your approval; nothing runs",
    "queued": "builds when a slot frees, up to a draft PR and second-model review; goes to reviewers when you're back",
    "building": "building, up to a draft PR and second-model review; goes to reviewers when you're back",
    "pr-draft": "second-model review and fixes (up to 3 rounds); goes to reviewers when you're back",
    "reviewing": "second-model review and fixes (up to 3 rounds); goes to reviewers when you're back",
    "fixing": "fixing review findings, then the next review round; goes to reviewers when you're back",
    "babysit-queued": "reviewed and safe; it is marked ready and sent to reviewers when you're back",
    "babysitting": "already with reviewers: keeps answering them and pushing fixes, outside your quiet hours",
    "verifying": "final check on the exact head, then it waits for your merge",
    "ready": "waits for your merge",
    "escalated": "stopped; waits for your answer",
    "failed": "stopped; waits for your answer",
}
FMT = "%Y-%m-%dT%H:%M:%SZ"


def die(code, msg):
    print(f"handoff.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def now():
    return os.environ.get("STAR_NOW") or datetime.now(timezone.utc).strftime(FMT)


def parse(ts):
    try:
        return datetime.strptime(ts[:20], FMT).replace(tzinfo=timezone.utc)
    except (ValueError, TypeError):
        return None


def read(path):
    try:
        return open(path, encoding="utf-8").read().split("\n")
    except FileNotFoundError:
        return []


def write(path, lines):
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines).rstrip("\n") + "\n")
    os.replace(tmp, path)


def queue(home):
    lines, out = read(os.path.join(home, "open-loops.md")), []
    for k, line in enumerate(lines):
        m = ITEM_RE.match(line)
        if m:
            kind = lines[k + 1][5:].strip() if k + 1 < len(lines) and lines[k + 1].startswith("kind:") else ""
            out.append({"id": m.group(1), "project": m.group(2), "item": m.group(3), "title": m.group(4), "kind": kind})
    return out


def ledger(home):
    rows, header = [], None
    for line in read(os.path.join(home, "ledger.md")):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if header is None and "item" in cells and "state" in cells:
            header = cells
        elif header and len(cells) == len(header) and not set(line.strip()) <= set("|-: "):
            rows.append(dict(zip(header, cells)))
    return rows


def star(home):
    try:
        return json.load(open(os.path.join(home, "star.json"), encoding="utf-8"))
    except (FileNotFoundError, ValueError):
        die(1, "star.json missing or unreadable; is this a STAR home?")


def save_star(home, data):
    path = os.path.join(home, "star.json")
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def label(q):
    return f"{q['id']} · {q['project']} · {q['item']} · {q['title']}"


def summaries(lines):
    """[(start, end, timestamp)] of '### <iso>' blocks inside '## Summaries', in file order."""
    try:
        s = next(i for i, l in enumerate(lines) if l.strip() == "## Summaries")
    except StopIteration:
        return None, []
    e = next((i for i in range(s + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    heads = [i for i in range(s + 1, e) if lines[i].startswith("### ") and parse(lines[i][4:])]
    return s, [(h, (heads[n + 1] if n + 1 < len(heads) else e), lines[h][4:].strip()) for n, h in enumerate(heads)]


def mem_gb():
    if os.environ.get("STAR_MEM_GB"):
        return os.environ["STAR_MEM_GB"]
    try:
        out = subprocess.run(["vm_stat"], capture_output=True, text=True, timeout=10).stdout
        page = int(re.search(r"page size of (\d+) bytes", out).group(1))
        free = int(re.search(r"Pages free:\s+(\d+)", out).group(1))
        inactive = int(re.search(r"Pages inactive:\s+(\d+)", out).group(1))
        return str((free + inactive) * page // 1073741824)
    except Exception:
        return "?"


p = argparse.ArgumentParser(prog="handoff.sh")
p.add_argument("--home", default=os.environ.get("JUEL_STAR_HOME") or os.path.expanduser("~/juel-star"))
sub = p.add_subparsers(dest="cmd", required=True)
sub.add_parser("start")
d = sub.add_parser("due"); d.add_argument("--hours", type=float, default=4)
sub.add_parser("summary")
sub.add_parser("latest")
sub.add_parser("end")
try:
    a = p.parse_args()
except SystemExit as e:
    sys.exit(64 if e.code not in (0, None) else 0)

home = a.home
path = os.path.join(home, "handoff.md")
cfg = star(home)

if a.cmd == "start":
    stamp = now()
    q = queue(home)
    part_a = [f"- {label(x)}" for x in q if x["kind"] in BLOCKING] or ["- Nothing."]
    part_b = [f"- {label(x)}" for x in q if x["kind"] not in BLOCKING] or ["- Nothing."]
    part_c = [f"- {r.get('project')} · {r.get('item')} · {r.get('state')}: {OVERNIGHT[r.get('state')]}"
              for r in ledger(home) if r.get("state") in OVERNIGHT] or ["- Nothing is in progress."]
    write(path, [
        f"# Handoff — away since {stamp}",
        "",
        "Answer in `open-loops.md` (each item's `Answer:` line) or tell STAR. This file only lists.",
        "",
        "## Summaries",
        "",
        "## Before you go",
        "",
        "### A. Needs you now (work is blocked on these)",
        *part_a,
        "",
        "### B. Waits for you (nothing is blocked)",
        *part_b,
        "",
        "### C. What runs while you're away",
        *part_c,
        "",
        "While you're away: building, second-model review and fixes continue. No new PR is marked ready or",
        "sent to human reviewers until you're back; babysitting that had already started carries on.",
        "Status changes are held. Nothing is merged.",
    ])
    cfg["away"] = stamp
    save_star(home, cfg)
    print(path)
    sys.exit(0)

away = cfg.get("away")
lines = read(path)
start, blocks = summaries(lines)
last = blocks[0][2] if blocks else away

if a.cmd == "due":
    if not away:
        print("not-away")
    else:
        t_last, t_now = parse(last), parse(now())
        print("due" if t_last and t_now and t_now - t_last >= timedelta(hours=a.hours) else "not-due")
elif a.cmd == "latest":
    print("\n".join(lines[blocks[0][0]:blocks[0][1]]).rstrip() if blocks else "No summaries yet.")
elif a.cmd == "summary":
    if not away or start is None:
        die(1, "not away: run 'handoff.sh start' first")
    since = parse(last)
    rows = ledger(home)
    counts = {}
    for r in rows:
        if r.get("state") not in ("done", "dropped"):
            counts[r.get("state")] = counts.get(r.get("state"), 0) + 1

    def changed(r):
        t = parse(r.get("updated", ""))
        return bool(t and since and t > since)

    ready = [f"{r.get('project')} {r.get('item')} {r.get('pr')}" for r in rows if r.get("state") == "ready"]
    merged = [f"{r.get('project')} {r.get('item')}" for r in rows if r.get("state") == "done" and changed(r)]
    stopped = [f"{r.get('project')} {r.get('item')} ({r.get('state')})" for r in rows if r.get("state") in ("escalated", "failed")]
    sent = []
    for line in read(os.path.join(home, "sent.log")):
        cells = line.split("\t")
        t = parse(cells[0]) if cells and cells[0] else None
        if t and since and t > since and len(cells) >= 4:
            sent.append(f"{cells[1]} {cells[2]}: {cells[3]}")
    running = sum(counts.get(s, 0) for s in ("briefing", "building", "reviewing", "fixing", "babysitting"))
    block = [
        f"### {now()}",
        "- Items: " + (" · ".join(f"{k} {v}" for k, v in sorted(counts.items())) or "none open"),
        "- PRs ready for your merge: " + ("; ".join(ready) or "none"),
        "- Merged since the last summary: " + ("; ".join(merged) or "none"),
        "- Stopped, waiting for your answer: " + ("; ".join(stopped) or "none"),
        "- Sent since the last summary: " + ("; ".join(sent) or "nothing"),
        f"- Host: {mem_gb()} GB free + inactive; workers running: {running}",
        "- Needs you: " + ("; ".join(label(x) for x in queue(home)) or "nothing"),
        "",
    ]
    at = blocks[0][0] if blocks else start + 1
    if not blocks and at < len(lines) and not lines[at].strip():
        at += 1
    lines[at:at] = block
    write(path, lines)
elif a.cmd == "end":
    cfg["away"] = None
    save_star(home, cfg)
    if lines:
        lines[1:1] = [f"back: {now()}"]
        write(path, lines)
    print("\n".join(lines[blocks[0][0] + 1:blocks[0][1] + 1]).rstrip() if blocks else "No summaries were written.")
PY
