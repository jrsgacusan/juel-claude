#!/bin/sh
# Says whether STAR already raised a Slack message (drafted a reply and queued it, or sent one), so a
# message the dashboard's watcher hands over again is not raised twice.
#   slack-handled.sh [--home HOME_DIR] <id>
# <id> is the slack: block's id (<channelId>-<ts>): a letter or digit, then letters, digits, dots and
# hyphens. A draft is for <id> when its name ends in exactly "-slack-<id>.md"
# (drafts/<YYYY-MM-DD>-<project>-slack-<id>.md), whatever its date and project.
# Prints the first line that holds, in this order, and exits 0:
#   handled sent <draft name>     sent.log has a "slack reply <draft name>" line for <id>, whether or
#                                 not the draft is still in drafts/
#   handled drafted <draft name>  a draft for <id> is in drafts/ and a slack-reply item, open in
#                                 open-loops.md or closed in open-loops-archive.md, names it on a
#                                 "draft:" line above its Answer line (an item of another kind, or
#                                 what the owner typed under Answer, does not count)
#   queue <absolute draft path>   a draft for <id> is in drafts/ and no slack-reply item names it
#   new                           otherwise; an item that names a draft no longer in drafts/ does not count
# When several drafts match, the greatest name (the newest date) is printed.
# The archive is the one loops.sh writes: beside open-loops.md, or beside the file it links to.
# A missing sent.log, open-loops-archive.md or drafts/ reads as empty. A missing open-loops.md, any of
# them that cannot be read, a link to nothing, or git conflict markers in either queue file is exit 2
# with nothing on stdout: every file is read before the decision, so a broken folder never reads as new.
# Without --home the folder is $JUEL_STAR_HOME, else the one star-home.sh names for the current
# directory. Exit 64 on bad usage: a missing or invalid <id>, an unknown flag, or no folder.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
export STAR_HOME_DEFAULT
exec python3 - "$@" <<'PY'
import os
import re
import sys

ITEM_RE = re.compile(r"^### (N-(\d+)) · (.*?) · (.*?) · (.*)$")
ANSWER_RE = re.compile(
    r"^\s{0,3}(?:[-*+]\s+)?(?:\[[ xX]\]\s*)?[*_]{0,2}answer\s*[:：][*_]{0,2}",
    re.IGNORECASE,
)
CONFLICT_RE = re.compile(r"^(<<<<<<<|>>>>>>>|=======|\|\|\|\|\|\|\|)( .*)?$")
ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]*")


def die(code, message):
    print(f"slack-handled.sh: {message}", file=sys.stderr)
    raise SystemExit(code)


def read_text(path, required=False):
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as stream:
            return stream.read()
    except FileNotFoundError:
        if os.path.lexists(path):
            die(2, f"{path} is a link to nothing")
        if required:
            die(2, f"cannot read {path}: not found")
        return ""
    except OSError as exc:
        die(2, f"cannot read {path}: {exc.strerror or exc}")


def drafts_in(home, suffix):
    path = os.path.join(home, "drafts")
    try:
        names = os.listdir(path)
    except FileNotFoundError:
        if os.path.lexists(path):
            die(2, f"{path} is a link to nothing")
        return []
    except OSError as exc:
        die(2, f"cannot read {path}: {exc.strerror or exc}")
    return [name for name in names if name.endswith(suffix)]


def lines_of(text):
    return [line.rstrip("\r") for line in text.split("\n")]


def sent_names(text, suffix):
    found = []
    for line in lines_of(text):
        fields = line.split("\t")
        if len(fields) < 4 or fields[2] != "slack" or not fields[3].startswith("slack reply "):
            continue
        name = os.path.basename(fields[3][len("slack reply "):].strip())
        if name.endswith(suffix):
            found.append(name)
    return found


def item_bodies(texts):
    for text in texts:
        lines = lines_of(text)
        i = 0
        while i < len(lines):
            if not ITEM_RE.match(lines[i]):
                i += 1
                continue
            end = i + 1
            while end < len(lines) and not ITEM_RE.match(lines[end]) \
                    and not lines[end].startswith("# ") \
                    and not lines[end].startswith("## "):
                end += 1
            yield lines[i + 1:end]
            i = end


def kind_of(body):
    for line in body:
        if line.startswith("kind:"):
            return (line[len("kind:"):].split() or [""])[0]
    return ""


def named_drafts(texts, suffix):
    named = set()
    for body in item_bodies(texts):
        if kind_of(body) != "slack-reply":
            continue
        answer = next((i for i, line in enumerate(body) if ANSWER_RE.match(line)), len(body))
        for line in body[:answer]:
            stripped = line.strip()
            if not stripped.startswith("draft:"):
                continue
            value = stripped[len("draft:"):].strip().strip("`'\"")
            name = os.path.basename(value)
            if name.endswith(suffix):
                named.add(name)
    return named


home = os.environ.get("STAR_HOME_DEFAULT") or ""
args = sys.argv[1:]
message_id = None
while args:
    arg = args.pop(0)
    if arg == "--home":
        if not args:
            die(64, "--home needs a value")
        home = args.pop(0)
    elif arg.startswith("-"):
        die(64, f"unknown argument: {arg}")
    elif message_id is None:
        message_id = arg
    else:
        die(64, "unexpected argument")
if not home or message_id is None or not ID_RE.fullmatch(message_id):
    die(64, "usage: slack-handled.sh [--home HOME_DIR] <id>")

suffix = f"-slack-{message_id}.md"
queue_path = os.path.join(home, "open-loops.md")
archive_path = os.path.join(os.path.dirname(os.path.realpath(queue_path)), "open-loops-archive.md")
# Read all STAR files before deciding, so a broken folder always fails closed.
sent = read_text(os.path.join(home, "sent.log"))
drafts = drafts_in(home, suffix)
queue = read_text(queue_path, required=True)
archive = read_text(archive_path)
for path, text in ((queue_path, queue), (archive_path, archive)):
    if any(CONFLICT_RE.match(line) for line in lines_of(text)):
        die(2, f"{path} has git conflict markers")

sent_matches = sent_names(sent, suffix)
drafted = named_drafts([queue, archive], suffix).intersection(drafts)
if sent_matches:
    print(f"handled sent {max(sent_matches)}")
elif drafted:
    print(f"handled drafted {max(drafted)}")
elif drafts:
    print(f"queue {os.path.join(os.path.abspath(home), 'drafts', max(drafts))}")
else:
    print("new")
PY
