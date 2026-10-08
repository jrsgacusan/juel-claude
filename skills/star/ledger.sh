#!/bin/sh
# The one writer of STAR's ledger.md. Every command re-reads the file under a lock and replaces it
# atomically, so two writers never lose a row and a reader never sees half a file.
#   ledger.sh [--home H] name <ref>        -> the item name the ref gets, or "open <item>" when the
#                                             ref already has a row that is not done or dropped
#   ledger.sh [--home H] add <item> ref=<ref> project=<p> [<col>=<value> ...]   -> added <item>
#   ledger.sh [--home H] set <item> <col>=<value> ... [counters.<key>=<n>|+1|-] [counters=-|keep:<k>,...]
#                                          -> set <item>   (the changes apply in the order given)
#   ledger.sh [--home H] get <item> [<col>|counters.<key>]   -> one value ("-" when absent), or
#                                             the whole row as col=value lines
#   ledger.sh [--home H] list [--state <s>[,<s>...]]
#                                          -> item, state, stage, round, worktree, dispatch, pr,
#                                             updated: one row per line, tab-separated
#   ledger.sh [--home H] counts            -> "<state> <n>" for each state that has rows
# Each field is its own argument: nothing is split on spaces, so one value can never become two
# rows. A value is cleaned on the way in: "|" and line breaks become "/ ", an empty value is "-".
# "updated" is stamped by every write (UTC, or STAR_NOW when set) and cannot be set by hand.
# The naming rule: a tracker ref as written; "#<n>" becomes issue-<n>; a spec path the kebab-case
# of its file name; only A-Za-z0-9._- kept, no leading . or -, at most 60 characters; a name
# already in the ledger gets -2, -3.
# Without --home the folder is $JUEL_STAR_HOME, else the one star-home.sh names for this directory.
# Exit: 0 ok, 2 the ledger is missing or broken, 4 unknown item, 64 usage, 65 refused (the item, or
# an open row for the ref, already exists).
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
export STAR_HOME_DEFAULT
exec python3 - "$@" <<'PY'
import fcntl
import os
import re
import sys
from datetime import datetime, timezone

COLS = ["item", "ref", "project", "worktree", "state", "stage", "round", "task", "dispatch",
        "restarts", "pr", "head", "cursor", "verify", "counters", "updated"]
STATES = ["inbox", "briefing", "brief-ready", "queued", "building", "pr-draft", "reviewing",
          "fix-queued", "fixing", "screen-queued", "screening", "babysit-queued", "babysitting",
          "verifying", "ready", "reported", "post-queued", "posting", "done", "escalated", "failed",
          "dropped"]
STAGES = ["brief", "build", "review", "fix", "screen", "babysit", "post"]
COUNTS = ["miss", "silent", "unknown", "hold", "moved", "pending", "nudge", "reask", "screen", "start",
          "kept", "busy"]
WORDS = ["last", "tracker", "live"]
DEFAULTS = {"worktree": "-", "state": "inbox", "stage": "brief", "round": "0", "task": "-",
            "dispatch": "-", "restarts": "0", "pr": "-", "head": "-", "cursor": "-", "verify": "-",
            "counters": "-"}
CLOSED = ("done", "dropped")
NAME_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,59}")


def die(code, msg):
    print(f"ledger.sh: {msg}", file=sys.stderr)
    sys.exit(code)


argv, home = sys.argv[1:], os.environ.get("STAR_HOME_DEFAULT") or ""
if argv[:1] == ["--home"]:
    if len(argv) < 2:
        die(64, "--home needs a folder")
    home, argv = argv[1], argv[2:]
if not argv:
    die(64, "usage: ledger.sh [--home H] name|add|set|get|list|counts ...")
if not home:
    die(2, "no STAR folder: pass --home, or run inside a project")
path = os.path.join(home, "ledger.md")


def now():
    return os.environ.get("STAR_NOW") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def clean(value):
    value = re.sub(r"\s*(\r\n|\r|\n|\|)\s*", "/ ", value).strip()
    return value or "-"


def load():
    try:
        lines = open(path, encoding="utf-8").read().split("\n")
    except FileNotFoundError:
        die(2, f"{path} not found")
    except OSError as e:
        die(2, f"{path}: {e.strerror}")
    head = next((i for i, l in enumerate(lines) if l.strip().startswith("| item |")), None)
    if head is None or head + 1 >= len(lines) or not lines[head + 1].strip().startswith("|---"):
        die(2, f"{path} has no ledger table")
    if [c.strip() for c in lines[head].strip().strip("|").split("|")] != COLS:
        die(2, f"{path}: the header is not STAR's ledger header")
    rows, end = [], head + 2
    # rows run to the first line that is neither a row nor blank: a blank line a person left
    # between two rows does not hide the rows below it
    while end < len(lines) and (lines[end].strip().startswith("|") or not lines[end].strip()):
        line = lines[end].strip()
        end += 1
        if not line:
            continue
        cells = [c.strip() for c in line[1:-1].split("|")] if line.endswith("|") else []
        if len(cells) != len(COLS):
            die(2, f"{path}:{end}: a row has {len(cells)} cells, not {len(COLS)}")
        rows.append(dict(zip(COLS, cells)))
    names = [r["item"] for r in rows]
    twice = next((n for n in names if names.count(n) > 1), None)
    if twice:
        die(2, f"{path}: item {twice} has two rows; keep one")
    after = lines[end:]
    return lines[:head], rows, after


def save(before, rows, after):
    out = before + ["| " + " | ".join(COLS) + " |", "|" + "---|" * len(COLS)]
    out += ["| " + " | ".join(r[c] for c in COLS) + " |" for r in rows]
    text = "\n".join(out + [""] + [l for l in after if l.strip()])
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text.rstrip("\n") + "\n")
    os.replace(tmp, path)


def counters(cell):
    found = {}
    for pair in ([] if cell in ("", "-") else cell.split()):
        key, _, value = pair.partition("=")
        found[key] = value
    return found


def counters_cell(found):
    return " ".join(f"{k}={v}" for k, v in found.items()) or "-"


def base_name(ref):
    raw = ref.strip()
    if re.fullmatch(r"#\d+", raw):
        name = "issue-" + raw[1:]
    elif "/" in raw or raw.lower().endswith(".md"):
        stem = os.path.splitext(os.path.basename(raw))[0]
        name = re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")
    else:
        name = raw
    return re.sub(r"[^A-Za-z0-9._-]", "-", name).lstrip(".-")[:60] or "item"


def find(rows, item):
    return next((r for r in rows if r["item"] == item), None)


def pairs(args):
    found = []
    for arg in args:
        key, eq, value = arg.partition("=")
        if not eq or not key:
            die(64, f"'{arg}' is not <column>=<value>")
        found.append((key, value))
    return found


def apply(row, key, value):
    if key == "counters":
        if value.strip() == "-":
            row["counters"] = "-"
            return
        if not value.startswith("keep:"):
            die(64, "counters takes - or keep:<key>,<key>")
        keep = [k for k in value[5:].split(",") if k]
        row["counters"] = counters_cell({k: v for k, v in counters(row["counters"]).items() if k in keep})
        return
    if key.startswith("counters."):
        name, found = key[len("counters."):], counters(row["counters"])
        if name not in COUNTS + WORDS:
            die(64, f"unknown counter {name}")
        value = value.strip()
        if value == "-":
            found.pop(name, None)
        elif name in WORDS:
            if not re.fullmatch(r"\S+", value) or value == "+1":
                die(64, f"{name} takes one word")
            found[name] = value
        elif value == "+1":
            found[name] = str(int(found.get(name, "0") or 0) + 1)
        elif value.isdigit():
            found[name] = value
        else:
            die(64, f"{name} takes a number, +1 or -")
        row["counters"] = counters_cell(found)
        return
    if key not in COLS or key in ("item", "updated", "counters"):
        die(64, f"{key} cannot be set")
    value = clean(value)
    if key == "state" and value not in STATES:
        die(64, f"unknown state {value}")
    if key == "stage" and value not in STAGES:
        die(64, f"unknown stage {value}")
    if key in ("round", "restarts") and not value.isdigit():
        die(64, f"{key} takes a number")
    row[key] = value


cmd, rest = argv[0], argv[1:]
lock = open(os.path.join(home, "ledger.md.lock"), "a")
fcntl.flock(lock, fcntl.LOCK_EX)
before, rows, after = load()

if cmd == "name":
    if len(rest) != 1:
        die(64, "usage: ledger.sh name <ref>")
    open_row = next((r for r in rows if r["ref"] == rest[0].strip() and r["state"] not in CLOSED), None)
    if open_row:
        print(f"open {open_row['item']}")
        sys.exit(0)
    base, taken, n = base_name(rest[0]), {r["item"] for r in rows}, 1
    name = base
    while name in taken:
        n += 1
        suffix = f"-{n}"
        name = base[:60 - len(suffix)] + suffix
    print(name)
elif cmd == "add":
    if not rest:
        die(64, "usage: ledger.sh add <item> ref=<ref> project=<p> [<col>=<value> ...]")
    item, given = rest[0], pairs(rest[1:])
    if not NAME_RE.fullmatch(item):
        die(64, f"'{item}' is not an item name (A-Za-z0-9._-, at most 60, no leading . or -)")
    fields = dict(given)
    if "ref" not in fields or "project" not in fields:
        die(64, "add needs ref= and project=")
    if find(rows, item):
        die(65, f"item {item} already has a row")
    ref = clean(fields["ref"])
    open_row = next((r for r in rows if r["ref"] == ref and r["state"] not in CLOSED), None)
    if open_row:
        die(65, f"ref {ref} already has an open row: {open_row['item']}")
    row = {"item": item, "ref": ref, "project": clean(fields["project"]), **DEFAULTS, "updated": now()}
    for key, value in given:
        if key not in ("ref", "project"):
            apply(row, key, value)
    rows.append(row)
    save(before, rows, after)
    print(f"added {item}")
elif cmd == "set":
    if len(rest) < 2:
        die(64, "usage: ledger.sh set <item> <col>=<value> ...")
    row = find(rows, rest[0])
    if not row:
        die(4, f"no row for {rest[0]}")
    for key, value in pairs(rest[1:]):
        apply(row, key, value)
    row["updated"] = now()
    save(before, rows, after)
    print(f"set {rest[0]}")
elif cmd == "get":
    if len(rest) not in (1, 2):
        die(64, "usage: ledger.sh get <item> [<col>|counters.<key>]")
    row = find(rows, rest[0])
    if not row:
        die(4, f"no row for {rest[0]}")
    if len(rest) == 1:
        for c in COLS:
            print(f"{c}={row[c]}")
    elif rest[1].startswith("counters."):
        print(counters(row["counters"]).get(rest[1][len("counters."):], "-"))
    elif rest[1] in COLS:
        print(row[rest[1]])
    else:
        die(64, f"unknown column {rest[1]}")
elif cmd == "list":
    wanted = None
    if rest[:1] == ["--state"]:
        if len(rest) != 2:
            die(64, "usage: ledger.sh list [--state <s>[,<s>...]]")
        wanted = [s for s in rest[1].split(",") if s]
        bad = [s for s in wanted if s not in STATES]
        if bad:
            die(64, f"unknown state {bad[0]}")
    elif rest:
        die(64, "usage: ledger.sh list [--state <s>[,<s>...]]")
    for r in rows:
        if wanted is None or r["state"] in wanted:
            print("\t".join(r[c] for c in ("item", "state", "stage", "round", "worktree", "dispatch", "pr", "updated")))
elif cmd == "counts":
    for state in STATES:
        n = sum(1 for r in rows if r["state"] == state)
        if n:
            print(f"{state} {n}")
else:
    die(64, f"unknown command {cmd}")
PY
