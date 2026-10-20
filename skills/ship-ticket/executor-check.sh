#!/bin/sh
# Checks that the linked claude-plan-executor skill is the running plugin's copy or a newer one (#164).
# Usage: sh executor-check.sh <plugin root>
# Reads ${CODEX_HOME:-$HOME/.codex}/skills/claude-plan-executor/SKILL.md and prints one line:
#   ok                          byte-equal to <plugin root>/assets/codex-skills/claude-plan-executor/SKILL.md,
#                               or it resolves into a plugin whose version is the running one or newer
#   older <linked> <running>    it resolves into an older plugin
#   different                   not byte-equal and either version cannot be read
#   missing                     no such file (a missing or broken link)
# Newer passes: the executor's plan contract only grows (#118's ledger before a capacity stop), and
# since #158 the dispatch line itself carries the session-task stop. An older copy lacks those fixes.
# Exit 0 for every line above; 64 on bad usage (not exactly one argument, or a root without the skill).
[ $# -eq 1 ] || { echo "usage: executor-check.sh <plugin root>" >&2; exit 64; }
[ -f "$1/assets/codex-skills/claude-plan-executor/SKILL.md" ] || { echo "no executor skill under $1" >&2; exit 64; }
python3 - "$1" <<'PY'
import json, os, re, sys
root = sys.argv[1]
mine = os.path.join(root, "assets/codex-skills/claude-plan-executor/SKILL.md")
linked = os.path.join(os.environ.get("CODEX_HOME") or os.path.join(os.path.expanduser("~"), ".codex"),
                      "skills/claude-plan-executor/SKILL.md")
if not os.path.isfile(linked):
    print("missing"); sys.exit(0)
def read(p):
    with open(p, "rb") as f:
        return f.read()
if read(linked) == read(mine):
    print("ok"); sys.exit(0)
def version(r):
    try:
        with open(os.path.join(r, ".claude-plugin", "plugin.json")) as f:
            v = json.load(f)["version"]
        if not re.fullmatch(r"\d+(\.\d+)*", v):
            return None
        return v
    except Exception:
        return None
real = os.path.realpath(linked)
lroot = real
for _ in range(4):
    lroot = os.path.dirname(lroot)
lv, rv = version(lroot), version(root)
if lv is None or rv is None:
    print("different"); sys.exit(0)
key = lambda v: tuple(int(x) for x in v.split("."))
print("ok" if key(lv) >= key(rv) else "older %s %s" % (lv, rv))
PY
