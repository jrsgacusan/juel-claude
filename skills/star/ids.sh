#!/bin/sh
# Hands out ids from a sequence that several branches append to (a decision register, an ADR
# index, numbered migrations), so parallel workers never pick the same next number (#26).
#   ids.sh [--home H] reserve <sequence> --item <item> --count <n> --floor <highest id seen>
#     -> one id per line
#   ids.sh [--home H] list [--item <item>]
#     -> "<sequence> <item> <id>" per line, by sequence, then in the order they were handed out
# <sequence> is the register's path in the repository (docs/decisions.md). Ids are integers; the
# caller formats them (D-041). reserve hands out n ids (1 to 100) starting at
# max(next, floor + 1) and records them against the item. HOME_DIR/ids.json is written
# atomically under an fcntl lock, so workers in parallel never share an id.
# Exit: 0; 2 the STAR folder or ids.json cannot be read (a damaged ids.json is never rewritten);
# 64 usage.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
export STAR_HOME_DEFAULT
exec python3 - "$@" <<'PY'
import fcntl
import json
import os
import re
import sys

NAME_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,59}")
USAGE = ("usage: ids.sh [--home H] reserve <sequence> --item <item> --count <n> --floor <n>"
         " | list [--item <item>]")


def die(code, msg):
    print(f"ids.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def options(rest, names):
    found, i = {}, 0
    while i < len(rest):
        if rest[i] in names and i + 1 < len(rest):
            found[rest[i]] = rest[i + 1]
            i += 2
        else:
            die(64, f"unexpected argument {rest[i]!r}; {USAGE}")
    return found


def number(text, low, high, flag):
    if not re.fullmatch(r"\d+", text or "") or not low <= int(text) <= high:
        die(64, f"{flag} must be a whole number from {low} to {high}")
    return int(text)


argv, home = sys.argv[1:], os.environ.get("STAR_HOME_DEFAULT") or ""
if argv[:1] == ["--home"]:
    if len(argv) < 2:
        die(64, "--home needs a folder")
    home, argv = argv[1], argv[2:]
if not argv or argv[0] not in ("reserve", "list"):
    die(64, USAGE)
if not home or not os.path.isdir(home):
    die(2, f"no STAR folder at {home or '(unset)'}")
path = os.path.join(home, "ids.json")


def load():
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return {"sequences": {}}
    except (OSError, ValueError):
        die(2, f"{path} is not valid JSON: fix or remove it")
    if not isinstance(data, dict) or not isinstance(data.get("sequences"), dict) or not all(
            map(well_formed, data["sequences"].values())):
        die(2, f"{path} is not an ids ledger: fix or remove it")
    return data


def whole(value):
    return isinstance(value, int) and not isinstance(value, bool)


def well_formed(entry):
    return (isinstance(entry, dict) and whole(entry.get("next")) and entry["next"] >= 1
            and isinstance(entry.get("reserved"), list)
            and all(isinstance(r, dict) and isinstance(r.get("item"), str) and whole(r.get("id"))
                    for r in entry["reserved"]))


if argv[0] == "list":
    want = options(argv[1:], {"--item"}).get("--item")
    for seq, entry in sorted(load()["sequences"].items()):
        for r in entry.get("reserved") or []:
            if want is None or r.get("item") == want:
                print(f"{seq} {r.get('item')} {r.get('id')}")
    sys.exit(0)

if len(argv) < 2 or argv[1].startswith("--") or not argv[1].strip() or any(c.isspace() for c in argv[1]):
    die(64, USAGE)
seq = argv[1]
o = options(argv[2:], {"--item", "--count", "--floor"})
if set(o) != {"--item", "--count", "--floor"}:
    die(64, USAGE)
if not NAME_RE.fullmatch(o["--item"]):
    die(64, f"bad item name {o['--item']!r}")
count = number(o["--count"], 1, 100, "--count")
floor = number(o["--floor"], 0, 10**9, "--floor")

with open(path + ".lock", "a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    data = load()
    entry = data["sequences"].setdefault(seq, {"next": 1, "reserved": []})
    start = max(entry["next"], floor + 1)
    ids = list(range(start, start + count))
    entry["next"] = start + count
    entry["reserved"].extend({"item": o["--item"], "id": n} for n in ids)
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
for n in ids:
    print(n)
PY
