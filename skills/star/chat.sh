#!/bin/sh
# STAR's side of the dashboard's chat thread: writes STAR's replies and posts, and names the owner's
# messages that still wait for a reply (after a stop or a compaction, say).
#   chat.sh [--home HOME_DIR] reply <message id> --body-file <file>
#   chat.sh [--home HOME_DIR] post --body-file <file>
#   chat.sh [--home HOME_DIR] pending
# The thread is HOME_DIR/chat/, one file per message, never rewritten:
# <UTC YYYYMMDDTHHMMSSZ>-<who>-<4 lowercase hex>.md, who "me" (the owner, written by the dashboard) or
# "star" (written here). A message's id is its file name without .md. A file is the lines
# "id: <id>", "who: me|star", "at: <ISO 8601 UTC, seconds, Z>", "replyTo: <message id, or ->" and
# "---", then the text. A file that does not parse is skipped, never an error for the thread.
# A message is written under a temp name that does not end in .md, then hard-linked to its name, so
# no reader sees half of it and no file is ever overwritten. chat/ is created when missing. The body
# file is copied byte for byte.
# Prints one line and exits 0:
#   replied <reply id>      reply: a star message whose replyTo is <message id>
#   posted <id>             post: a star message whose replyTo is -
#   <message id>            pending: one line per owner message no star message replies to, oldest
#                           first; nothing when none waits
# Refusals print one line, write nothing and exit:
#   no message <id>         65: no owner message has that id
#   already replied <id>    66: a star message already replies to it
# Without --home the folder is $JUEL_STAR_HOME, else the one star-home.sh names for the current
# directory. Exit 64 on bad usage: a missing or unknown command or flag, an id that is not a message
# id, a body file that is missing, unreadable or only whitespace, or no folder. Exit 2 when chat/
# cannot be listed or written.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
export STAR_HOME_DEFAULT
exec python3 - "$@" <<'PY'
import os
import re
import secrets
import sys
from datetime import datetime, timezone

ID_RE = re.compile(r"[0-9]{8}T[0-9]{6}Z-(me|star)-[0-9a-f]{4}")
USAGE = "usage: chat.sh [--home HOME_DIR] reply <message id> --body-file <file> | post --body-file <file> | pending"


def die(code, msg):
    print(f"chat.sh: {msg}", file=sys.stderr)
    sys.exit(code)


home, body_file, words, args = os.environ.get("STAR_HOME_DEFAULT") or "", None, [], sys.argv[1:]
while args:
    arg = args.pop(0)
    if arg in ("--home", "--body-file"):
        if not args:
            die(64, f"{arg} needs a value")
        if arg == "--home":
            home = args.pop(0)
        else:
            body_file = args.pop(0)
    elif arg.startswith("-"):
        die(64, f"unknown argument: {arg}")
    else:
        words.append(arg)
command = words[0] if words else None
if len(words) > 2 or command not in ("reply", "post", "pending"):
    die(64, USAGE)
if command == "reply" and (len(words) != 2 or body_file is None):
    die(64, USAGE)
if command == "post" and (len(words) != 1 or body_file is None):
    die(64, USAGE)
if command == "pending" and (len(words) != 1 or body_file is not None):
    die(64, USAGE)
target = words[1] if command == "reply" else None
if target is not None and not ID_RE.fullmatch(target):
    die(64, f"not a message id: {target}")
if not home or not os.path.isdir(home):
    die(64, f"no STAR folder at {home}")
body = b""
if command != "pending":
    try:
        with open(body_file, "rb") as f:
            body = f.read()
    except OSError:
        die(64, f"cannot read {body_file}")
    if not body.strip():
        die(64, "the body is empty")
folder = os.path.join(home, "chat")


def parse(name):
    stem = name[:-3]
    if not name.endswith(".md") or not ID_RE.fullmatch(stem):
        return None
    try:
        with open(os.path.join(folder, name), "rb") as f:
            head = f.read(4096).split(b"\n")[:5]
    except OSError:
        return None
    lines = [l.decode("utf-8", errors="replace") for l in head]
    if len(lines) < 5:
        return None
    who = stem.split("-")[1]
    reply = lines[3][len("replyTo: "):] if lines[3].startswith("replyTo: ") else None
    if (lines[0] != f"id: {stem}" or lines[1] != f"who: {who}" or not lines[2].startswith("at: ")
            or not lines[2][4:].strip() or reply is None or lines[4] != "---"
            or not (reply == "-" or ID_RE.fullmatch(reply))):
        return None
    return {"id": stem, "who": who, "replyTo": None if reply == "-" else reply}


def thread():
    try:
        names = sorted(os.listdir(folder))
    except FileNotFoundError:
        return []
    except OSError as e:
        die(2, f"cannot read {folder}: {e.strerror}")
    return [m for m in (parse(n) for n in names) if m]


def write(who, reply_to):
    try:
        os.makedirs(folder, exist_ok=True)
    except OSError as e:
        die(2, f"cannot write {folder}: {e.strerror}")
    now = datetime.now(timezone.utc)
    stamp, at = now.strftime("%Y%m%dT%H%M%SZ"), now.strftime("%Y-%m-%dT%H:%M:%SZ")
    for _ in range(20):
        mid = f"{stamp}-{who}-{secrets.token_hex(2)}"
        tmp = os.path.join(folder, f".chat-{secrets.token_hex(4)}.tmp.{os.getpid()}")
        text = f"id: {mid}\nwho: {who}\nat: {at}\nreplyTo: {reply_to or '-'}\n---\n".encode() + body
        try:
            with open(tmp, "xb") as f:
                f.write(text)
            os.link(tmp, os.path.join(folder, mid + ".md"))
            return mid
        except FileExistsError:
            continue
        except OSError as e:
            die(2, f"cannot write {folder}: {e.strerror}")
        finally:
            try:
                os.remove(tmp)
            except OSError:
                pass
    die(2, "no free message name after 20 tries")


messages = thread()
answered = {m["replyTo"] for m in messages if m["who"] == "star" and m["replyTo"]}
if command == "pending":
    for m in messages:
        if m["who"] == "me" and m["id"] not in answered:
            print(m["id"])
elif command == "reply":
    if not any(m["who"] == "me" and m["id"] == target for m in messages):
        print(f"no message {target}")
        sys.exit(65)
    if target in answered:
        print(f"already replied {target}")
        sys.exit(66)
    print(f"replied {write('star', target)}")
else:
    print(f"posted {write('star', None)}")
