#!/bin/sh
# Asks the dashboard's Slack drafter for a new draft, the way the owner asked: STAR runs it for a
# "rewrite: <how>" answer on a slack-reply item, since STAR never writes reply text itself.
#   slack-redraft.sh [--home HOME_DIR] --draft <path> --loop <id> --how <text>
# Writes HOME_DIR/slack/redraft/<UTC YYYYMMDDTHHMMSSZ>-<4 lowercase hex>.md, three lines:
#   draft: <the draft's absolute path>
#   loop: <id>
#   how: <text>
# <id> is the slack-reply item's id (N-<n>). <text> is made one line: each run of whitespace, line
# breaks included, becomes one space. The request is written under a temp name that does not end in
# .md, then hard-linked to its name, so the dashboard never reads half of one and no request is ever
# overwritten. slack/redraft/ is created when missing.
# Prints "requested <file name>" and exits 0. Exit 65 with "no draft <absolute path>", writing
# nothing, when the draft is not a file.
# Without --home the folder is $JUEL_STAR_HOME, else the one star-home.sh names for the current
# directory. Exit 64 on bad usage: a missing or unknown flag, a flag without its value, a stray
# argument, an <id> that is not N-<n>, a <text> that is only whitespace, a <path> with a line break,
# or no folder. Exit 2 when the request cannot be written.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
export STAR_HOME_DEFAULT
exec python3 - "$@" <<'PY'
import os
import re
import secrets
import sys
from datetime import datetime, timezone

USAGE = "usage: slack-redraft.sh [--home HOME_DIR] --draft <path> --loop <id> --how <text>"


def die(code, msg):
    print(f"slack-redraft.sh: {msg}", file=sys.stderr)
    sys.exit(code)


opts = {"--home": os.environ.get("STAR_HOME_DEFAULT") or ""}
args = sys.argv[1:]
while args:
    arg = args.pop(0)
    if arg in ("--home", "--draft", "--loop", "--how"):
        if not args:
            die(64, f"{arg} needs a value")
        opts[arg] = args.pop(0)
    else:
        die(64, f"unknown argument: {arg}")
if not all(k in opts for k in ("--draft", "--loop", "--how")):
    die(64, USAGE)
home, draft, loop = opts["--home"], opts["--draft"], opts["--loop"]
how = " ".join(opts["--how"].split())
if not re.fullmatch(r"N-[0-9]+", loop):
    die(64, f"not a queue item id: {loop}")
if not how:
    die(64, "--how is empty")
if "\n" in draft or "\r" in draft:
    die(64, "the draft path has a line break")
if not home or not os.path.isdir(home):
    die(64, f"no STAR folder at {home}")
path = os.path.abspath(draft)
if not os.path.isfile(path):
    print(f"no draft {path}")
    sys.exit(65)
folder = os.path.join(home, "slack", "redraft")
tmp = os.path.join(folder, f".redraft-{secrets.token_hex(4)}.tmp.{os.getpid()}")
try:
    os.makedirs(folder, exist_ok=True)
    with open(tmp, "x", encoding="utf-8") as f:
        f.write(f"draft: {path}\nloop: {loop}\nhow: {how}\n")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    for _ in range(20):
        name = f"{stamp}-{secrets.token_hex(2)}.md"
        try:
            os.link(tmp, os.path.join(folder, name))
        except FileExistsError:
            continue
        print(f"requested {name}")
        break
    else:
        die(2, "no free request name after 20 tries")
except OSError as e:
    die(2, f"cannot write {folder}: {e.strerror}")
finally:
    try:
        os.remove(tmp)
    except OSError:
        pass
