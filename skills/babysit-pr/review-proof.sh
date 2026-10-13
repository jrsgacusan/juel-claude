#!/bin/sh
# Checks that a second-model review file is proof for one exact commit, so no worker has to read
# a verdict line by eye (where "NOT-SAFE" contains "SAFE").
#   review-proof.sh <review file> --item <item> --head <commit sha> [--verdict SAFE|NOT-SAFE]
# Prints one line and exits 0:  OK round=<k>  |  OK carried round=<k>  |  NO <why>
# OK means all of: the file's FIRST line is exactly
#   VERDICT item=<item> round=<k> <verdict> findings=<n> head=<7 to 40 hex characters>
# for this item and the verdict asked for (default SAFE); <k> is the round in the file's name
# (<item>-r<k>.md); the reviewed head is the start of --head; and no later round's review
# (<item>-r<k+1>.md) lies beside it, because a later round replaces an earlier verdict.
# OK carried means the file is <item>-r<k>-carried.md, the owner's decision to ship round k's head
# with its findings deferred (#82), and all of: its FIRST line is exactly
#   CARRIED item=<item> round=<k> head=<40 hex characters> from=<item>-r<k>.md decision=<id>
# for this item and the round in its name; that head starts with --head; <item>-r<k>.md lies
# beside it; and no <item>-r<j>.md with j greater than k does. A carried file never answers
# --verdict NOT-SAFE.
# Exit 64 on bad usage, which includes a --head shorter than 7 characters.
#
#   review-proof.sh carry --reviews <dir> --item <item> --round <k> --head <40 hex> --decision <id> --note <text>
# Writes <dir>/<item>-r<k>-carried.md in three lines: the CARRIED line, the note flattened to one
# line, and "Deferred: the findings in <item>-r<k>.md" (the findings are named, never copied).
# Prints "wrote <path>" and exits 0, or "ERROR <why>" and exits 1: no <item>-r<k>.md in <dir>, a
# later round's review in <dir>, a --head that is not 40 hex characters, or the file exists already
# (a carried PASS is never overwritten). Exit 64 on bad usage: a missing flag, a round that is not
# a number from 1, an item or decision that is not one word, or an empty note.
exec python3 - "$@" <<'PY'
import argparse
import os
import re
import sys


def parse(parser, argv):
    try:
        return parser.parse_args(argv)
    except SystemExit as e:
        sys.exit(64 if e.code not in (0, None) else 0)


def newer(folder, item, k):
    """Rounds after k whose review lies in folder: a later round replaces an earlier verdict."""
    pattern = re.compile(re.escape(item) + r"-r(\d+)\.md")
    names = os.listdir(folder) if os.path.isdir(folder) else []
    return sorted(int(m.group(1)) for m in map(pattern.fullmatch, names) if m and int(m.group(1)) > k)


if sys.argv[1:2] == ["carry"]:
    p = argparse.ArgumentParser(prog="review-proof.sh carry")
    for flag in ("--reviews", "--item", "--round", "--head", "--decision", "--note"):
        p.add_argument(flag, required=True)
    a = parse(p, sys.argv[2:])
    item, decision = a.item.strip(), a.decision.strip()
    if (not a.round.isdigit() or int(a.round) < 1 or not item or any(c.isspace() for c in item)
            or not decision or any(c.isspace() for c in decision) or not a.note.strip()):
        print("review-proof.sh carry: --round takes a number from 1, --item and --decision one word each, "
              "and --note some text", file=sys.stderr)
        sys.exit(64)
    k, head = int(a.round), a.head.strip().lower()

    def error(why):
        print(f"ERROR {why}")
        sys.exit(1)

    if not re.fullmatch(r"[0-9a-f]{40}", head):
        error(f"--head must be the full 40-character commit (got {a.head!r})")
    source = f"{item}-r{k}.md"
    if not os.path.isfile(os.path.join(a.reviews, source)):
        error(f"no {source} in {a.reviews}")
    later = newer(a.reviews, item, k)
    if later:
        error(f"round {later[0]} is newer than round {k}")
    path = os.path.join(a.reviews, f"{item}-r{k}-carried.md")
    note = " ".join(a.note.split())
    try:
        with open(path, "x", encoding="utf-8") as f:
            f.write(f"CARRIED item={item} round={k} head={head} from={source} decision={decision}\n"
                    f"{note}\nDeferred: the findings in {source}\n")
    except FileExistsError:
        error(f"{path} exists: a carried PASS is never overwritten")
    except OSError as e:
        error(f"cannot write {path}: {e.strerror}")
    print(f"wrote {path}")
    sys.exit(0)

p = argparse.ArgumentParser(prog="review-proof.sh")
p.add_argument("file")
p.add_argument("--item", required=True)
p.add_argument("--head", required=True)
p.add_argument("--verdict", default="SAFE", choices=("SAFE", "NOT-SAFE"))
a = parse(p, sys.argv[1:])
head = a.head.strip().lower()
if not re.fullmatch(r"[0-9a-f]{7,40}", head):
    print(f"review-proof.sh: --head must be 7 to 40 hex characters (got {a.head!r})", file=sys.stderr)
    sys.exit(64)


def no(why):
    print(f"NO {why}")
    sys.exit(0)


try:
    first = open(a.file, encoding="utf-8", errors="replace").readline().rstrip("\r\n")
except OSError as e:
    no(f"file: {a.file}: {e.strerror}")
carried = re.fullmatch(re.escape(a.item) + r"-r(\d+)-carried\.md", os.path.basename(a.file))
if carried:
    k = int(carried.group(1))
    m = re.fullmatch(r"CARRIED item=(\S+) round=(\d+) head=([0-9a-f]{40}) from=(\S+) decision=(\S+)", first)
    if not m:
        no(f"first line is not a full CARRIED line: {first[:120]!r}")
    item, rnd, carried_head, source, _ = m.groups()
    if item != a.item:
        no(f"item: the carried PASS is for {item}, not {a.item}")
    if a.verdict != "SAFE":
        no("verdict: a carried PASS is never a NOT-SAFE review")
    if int(rnd) != k:
        no(f"round: the file is round {k} but its CARRIED line says round {rnd}")
    if source != f"{a.item}-r{k}.md":
        no(f"from: the CARRIED line names {source}, not {a.item}-r{k}.md")
    if not carried_head.startswith(head):
        no(f"head: the carried PASS is for {carried_head[:7]}, the commit now is {head}")
    folder = os.path.dirname(os.path.abspath(a.file))
    if not os.path.isfile(os.path.join(folder, source)):
        no(f"from: {source} is not beside it")
    later = newer(folder, a.item, k)
    if later:
        replaced = os.path.join(folder, f"{a.item}-r{later[0]}.md")
        no(f"newer: round {later[0]} has its own review at {replaced}")
    print(f"OK carried round={k}")
    sys.exit(0)
m = re.fullmatch(r"VERDICT item=(\S+) round=(\d+) (SAFE|NOT-SAFE) findings=(\d+) head=([0-9a-fA-F]{7,40})", first)
if not m:
    no(f"first line is not a full VERDICT line: {first[:120]!r}")
item, rnd, verdict, _, reviewed = m.groups()
if item != a.item:
    no(f"item: the review is for {item}, not {a.item}")
if verdict != a.verdict:
    no(f"verdict: the review says {verdict}, not {a.verdict}")
name = re.fullmatch(re.escape(a.item) + r"-r(\d+)\.md", os.path.basename(a.file))
if not name:
    no(f"name: {os.path.basename(a.file)} is not {a.item}-r<round>.md")
if int(name.group(1)) != int(rnd):
    no(f"round: the file is round {name.group(1)} but its verdict line says round {rnd}")
if not head.startswith(reviewed.lower()):
    no(f"head: the review is of {reviewed}, the commit now is {head}")
later = os.path.join(os.path.dirname(os.path.abspath(a.file)), f"{a.item}-r{int(rnd) + 1}.md")
if os.path.exists(later):
    no(f"newer: round {int(rnd) + 1} has its own review at {later}")
print(f"OK round={rnd}")
PY
