#!/bin/sh
# Checks whether STAR has already raised a Slack message.
#   slack-handled.sh [--home HOME_DIR] <id>
# Prints one line and exits 0, in D2 order:
#   handled sent <draft name>     a sent Slack reply names this message id
#   handled drafted <draft name>  a slack-reply queue item names a draft for this message id
#   queue <absolute draft path>   a matching draft has no named slack-reply item yet
#   new                           no matching sent reply, queue item or draft exists
# Exit 2 when a STAR folder file cannot be read; exit 64 on usage errors.
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
ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]*")


def die(code, message):
    print(f"slack-handled.sh: {message}", file=sys.stderr)
    raise SystemExit(code)


def read_text(path, required=False):
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as stream:
            return stream.read()
    except FileNotFoundError:
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
        return []
    except OSError as exc:
        die(2, f"cannot read {path}: {exc.strerror or exc}")
    return [name for name in names if name.endswith(suffix)]


def sent_names(text, suffix):
    found = []
    for line in text.splitlines():
        fields = line.split("\t")
        if len(fields) < 4 or fields[2] != "slack" or not fields[3].startswith("slack reply "):
            continue
        name = os.path.basename(fields[3][len("slack reply "):].strip())
        if name.endswith(suffix):
            found.append(name)
    return found


def named_drafts(texts, suffix):
    named = set()
    for text in texts:
        lines = text.splitlines()
        i = 0
        while i < len(lines):
            match = ITEM_RE.match(lines[i])
            if not match:
                i += 1
                continue
            end = i + 1
            while end < len(lines):
                if ITEM_RE.match(lines[end]) or lines[end].startswith("## ") or lines[end].startswith("# "):
                    break
                end += 1
            item = lines[i:end]
            kind = ""
            for line in item[1:]:
                if line.startswith("kind:"):
                    kind = line[len("kind:"):].split()[:1]
                    kind = kind[0] if kind else ""
                    break
            if kind == "slack-reply":
                body_end = next((n for n, line in enumerate(item[1:], 1) if ANSWER_RE.match(line)), len(item))
                for line in item[1:body_end]:
                    if line.startswith("draft: "):
                        name = os.path.basename(line[len("draft: "):].strip())
                        if name.endswith(suffix):
                            named.add(name)
            i = end
    return named


home = os.environ.get("STAR_HOME_DEFAULT") or ""
args = list(sys.argv[1:])
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
# Read all STAR files before deciding, so a broken folder always fails closed.
sent = read_text(os.path.join(home, "sent.log"))
drafts = drafts_in(home, suffix)
queue = read_text(os.path.join(home, "open-loops.md"), required=True)
archive = read_text(os.path.join(home, "open-loops-archive.md"))

sent_matches = sent_names(sent, suffix)
named = named_drafts([queue, archive], suffix)
if sent_matches:
    print(f"handled sent {max(sent_matches)}")
elif set(drafts) & named:
    print(f"handled drafted {max(set(drafts) & named)}")
elif drafts:
    print(f"queue {os.path.join(os.path.abspath(home), 'drafts', max(drafts))}")
else:
    print("new")
PY
