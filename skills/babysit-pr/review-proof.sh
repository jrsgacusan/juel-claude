#!/bin/sh
# Checks that a second-model review file is proof for one exact commit, so no worker has to read
# a verdict line by eye (where "NOT-SAFE" contains "SAFE").
#   review-proof.sh <review file> --item <item> --head <commit sha> [--verdict SAFE|NOT-SAFE]
# Prints one line and exits 0:  OK round=<k>  |  NO <why>
# OK means all of: the file's FIRST line is exactly
#   VERDICT item=<item> round=<k> <verdict> findings=<n> head=<7 to 40 hex characters>
# for this item and the verdict asked for (default SAFE); <k> is the round in the file's name
# (<item>-r<k>.md); the reviewed head is the start of --head; and no later round's review
# (<item>-r<k+1>.md) lies beside it, because a later round replaces an earlier verdict.
# Exit 64 on bad usage, which includes a --head shorter than 7 characters.
exec python3 - "$@" <<'PY'
import argparse
import os
import re
import sys

p = argparse.ArgumentParser(prog="review-proof.sh")
p.add_argument("file")
p.add_argument("--item", required=True)
p.add_argument("--head", required=True)
p.add_argument("--verdict", default="SAFE", choices=("SAFE", "NOT-SAFE"))
try:
    a = p.parse_args()
except SystemExit as e:
    sys.exit(64 if e.code not in (0, None) else 0)
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
