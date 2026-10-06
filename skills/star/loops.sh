#!/bin/sh
# Edits STAR's open-loops.md without losing anything the user typed. Every command re-reads
# the file, changes only what it names, and replaces the file atomically.
#   loops.sh [--file <path>] add --kind K --project P --item I --title T [--body TEXT]   -> N-<n>
#   loops.sh [--file <path>] answers | list | set-answer <id> <text> | close <id>
#   loops.sh [--file <path>] resume [--state S] [--run R] [--pools P] [--next N] | waiting <text>
# An answer is the text after "Answer:" plus the lines right under it, up to the first blank
# line. Anything the user writes after that blank line is their own note and is never touched.
# Exit: 0 ok, 2 file or section missing, 3 git conflict markers, 4 unknown id, 64 usage.
exec python3 - "$@" <<'PY'
import argparse
import fcntl
import os
import re
import sys
from datetime import datetime, timezone

ITEM_RE = re.compile(r"^### (N-(\d+)) · (.*?) · (.*?) · (.*)$")
SECTIONS = ("## Resume", "## Needs you", "## Waiting on others")


def die(code, msg):
    print(f"loops.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def load(path):
    try:
        lines = open(path, encoding="utf-8").read().split("\n")
    except FileNotFoundError:
        die(2, f"{path} not found")
    if any(l.startswith("<<<<<<< ") or l.startswith(">>>>>>> ") for l in lines):
        die(3, "unresolved git conflict markers; resolve them first")
    return lines


def save(path, lines):
    tmp = f"{path}.tmp.{os.getpid()}"
    if lines and lines[-1] != "":
        lines = lines + [""]
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    os.replace(tmp, path)


def section(lines, title):
    start = next((i for i, l in enumerate(lines) if l.strip() == f"## {title}"), None)
    if start is None:
        die(2, f"no '## {title}' section; not a STAR open-loops file")
    # Only STAR's own headings end a section: a "## ..." line the user pasted into an answer does not.
    end = next((i for i in range(start + 1, len(lines)) if lines[i].strip() in SECTIONS), len(lines))
    return start, end


def items(lines):
    start, end = section(lines, "Needs you")
    found, i = [], start + 1
    while i < end:
        m = ITEM_RE.match(lines[i])
        if not m:
            i += 1
            continue
        stop = next((k for k in range(i + 1, end) if ITEM_RE.match(lines[k])), end)
        found.append({"id": m.group(1), "project": m.group(3), "item": m.group(4),
                      "title": m.group(5), "start": i, "end": stop})
        i = stop
    return found


def field_line(lines, it, name):
    return next((k for k in range(it["start"] + 1, it["end"]) if lines[k].startswith(name + ":")), None)


def tight_end(lines, it):
    """Where the item itself ends: after its answer lines, before any note the user left below."""
    k = field_line(lines, it, "Answer")
    if k is None:
        return it["end"]
    j = k + 1
    while j < it["end"] and lines[j].strip():
        j += 1
    return j


def answer_of(lines, it):
    k = field_line(lines, it, "Answer")
    if k is None:
        return ""
    parts = [lines[k][len("Answer:"):]] + lines[k + 1:tight_end(lines, it)]
    return " ".join(p.strip() for p in parts if p.strip())


def kind_of(lines, it):
    k = field_line(lines, it, "kind")
    return lines[k][len("kind:"):].strip() if k is not None else ""


def find(lines, item_id):
    it = next((x for x in items(lines) if x["id"] == item_id), None)
    if it is None:
        die(4, f"no open item {item_id}")
    return it


def next_id(lines, archive):
    nums = [int(m.group(2)) for l in lines for m in [ITEM_RE.match(l)] if m]
    if os.path.exists(archive):
        nums += [int(m.group(2)) for l in open(archive, encoding="utf-8") for m in [ITEM_RE.match(l.rstrip("\n"))] if m]
    return max(nums, default=0) + 1


def main():
    p = argparse.ArgumentParser(prog="loops.sh")
    home = os.environ.get("JUEL_STAR_HOME") or os.path.expanduser("~/juel-star")
    p.add_argument("--file", default=os.path.join(home, "open-loops.md"))
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add")
    for flag in ("--kind", "--project", "--item", "--title"):
        a.add_argument(flag, required=True)
    a.add_argument("--body", default="")
    sub.add_parser("answers")
    sub.add_parser("list")
    s = sub.add_parser("set-answer"); s.add_argument("id"); s.add_argument("text")
    c = sub.add_parser("close"); c.add_argument("id")
    r = sub.add_parser("resume")
    for flag in ("--state", "--run", "--pools", "--next"):
        r.add_argument(flag)
    w = sub.add_parser("waiting"); w.add_argument("text")
    argv = sys.argv[1:]
    if "set-answer" in argv:
        k = argv.index("set-answer")
        if len(argv) > k + 2 and argv[k + 2] != "--":
            argv.insert(k + 2, "--")  # the answer may start with a dash
    try:
        args = p.parse_args(argv)
    except SystemExit as e:
        sys.exit(64 if e.code not in (0, None) else 0)

    path = args.file
    archive = os.path.join(os.path.dirname(os.path.abspath(path)), "open-loops-archive.md")
    if not os.path.exists(path):
        die(2, f"{path} not found")
    lock = open(path + ".lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    lines = load(path)

    if args.cmd == "answers":
        for it in items(lines):
            ans = answer_of(lines, it)
            if ans:
                print("\t".join([it["id"], kind_of(lines, it), it["project"], it["item"], ans]))
    elif args.cmd == "list":
        for it in items(lines):
            state = "answered" if answer_of(lines, it) else "open"
            print("\t".join([it["id"], kind_of(lines, it), it["project"], it["item"], state, it["title"]]))
    elif args.cmd == "add":
        new_id = f"N-{next_id(lines, archive)}"
        start, end = section(lines, "Needs you")
        while end - 1 > start and not lines[end - 1].strip():
            end -= 1
        block = ["", f"### {new_id} · {args.project} · {args.item} · {args.title}", f"kind: {args.kind}"]
        block += [l for l in args.body.replace("\\n", "\n").split("\n") if l.strip()]
        block += ["Answer:"]
        lines[end:end] = block
        save(path, lines)
        print(new_id)
    elif args.cmd == "set-answer":
        it = find(lines, args.id)
        if answer_of(lines, it):
            print("kept")
        else:
            k = field_line(lines, it, "Answer")
            if k is None:
                lines.insert(it["end"], f"Answer: {args.text}")
            else:
                lines[k] = f"Answer: {args.text}"
            save(path, lines)
            print("set")
    elif args.cmd == "close":
        it = find(lines, args.id)
        stop = tight_end(lines, it)
        block = lines[it["start"]:stop]
        if stop < len(lines) and not lines[stop].strip():
            stop += 1
        del lines[it["start"]:stop]
        save(path, lines)
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        old = open(archive, encoding="utf-8").read().split("\n") if os.path.exists(archive) else ["# Closed loops"]
        rest = old[1:]
        while rest and not rest[0].strip():
            rest.pop(0)
        save(archive, [old[0], ""] + block + [f"closed: {stamp}", ""] + rest)
        print("closed")
    elif args.cmd == "resume":
        start, end = section(lines, "Resume")
        cur = {}
        for l in lines[start + 1:end]:
            if ":" in l:
                key, val = l.split(":", 1)
                cur[key.strip()] = val.strip()
        for key, val in (("state", args.state), ("run", args.run), ("pools", args.pools), ("next", args.next)):
            if val is not None:
                cur[key] = val
        cur["last tick"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        body = [f"{k}: {cur.get(k, '-')}" for k in ("state", "run", "last tick", "pools", "next")] + [""]
        lines[start + 1:end] = body
        save(path, lines)
    elif args.cmd == "waiting":
        start, end = section(lines, "Waiting on others")
        lines[start + 1:end] = [l for l in args.text.split("\n") if l.strip()] + [""]
        save(path, lines)


main()
PY
