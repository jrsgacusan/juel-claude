#!/bin/sh
# Runs the gates of a gate manifest, each in its own directory, exactly as they are written.
#   run-gates.sh <manifest.json> [--root <repo root>] [test|lint|typecheck|build|sweep ...]
# The manifest is what ship-ticket writes: {"test": {"cmd": "...", "cwd": "..."} | null, "lint": ...,
# "typecheck": ..., "build": ..., "sweep": ...}. No command is ever pasted into a quoted shell
# string, so quotes, "&&", "VAR=value" and spaces in a path all survive. cwd is relative to --root
# (default: the git top level, else the current directory) whatever directory the caller is in.
# With no gate names, every gate that is not null runs, in the order test, lint, typecheck, build.
# sweep (each test file once, no E2E) runs only when named; a null or missing sweep runs the test
# entry in its place (#102). The first red gate stops the run.
# Every gate about to run is checked before any runs (#105). The check applies to a gate only when
# all three hold. Its command runs a JS tool: the first word, after any NAME=value words, has the
# basename npm, npx, pnpm, pnpx, yarn, bun, bunx, node or corepack (a command that does not split
# into words counts as JS). Its cwd has a package.json that declares dependencies: a non-empty
# dependencies, devDependencies, optionalDependencies or peerDependencies object, or a workspaces
# key (a package.json that does not parse counts as declaring). And no node_modules folder, no
# .pnp.cjs file and no .pnp.js file exists in that cwd or any folder above it up to the root. Such
# a gate stops the run with exit 71 and this line on stderr (<cwd> is the manifest's own cwd):
#   run-gates.sh: <gate>: dependencies are not installed (no node_modules for <cwd>/package.json)
# Exit: 0 all green (or nothing to run); the failing gate's own code, with "<gate> failed (exit N)"
# on stderr; 71 when a gate could not be run at all (manifest missing or unreadable, a cwd that
# does not exist or leaves the root, dependencies not installed); 64 bad usage. A gate whose own
# code is 64, 71, 75, 124 or 125 comes out as 1 (its real code stays in the message): those five
# belong to this script and to gate-lock.sh, and a red gate must never read as "busy", "could not
# run", "ran past" or "stalled".
# Use it inside the gate lock:  sh gate-lock.sh --holder <item> -- sh run-gates.sh <manifest> --root <root>
exec python3 - "$@" <<'PY'
import json
import os
import re
import shlex
import subprocess
import sys

ORDER = ("test", "lint", "typecheck", "build")
KNOWN = ORDER + ("sweep",)  # sweep runs only when named


def die(code, msg):
    print(f"run-gates.sh: {msg}", file=sys.stderr)
    sys.exit(code)


argv, root, names, manifest = sys.argv[1:], None, [], None
while argv:
    arg = argv.pop(0)
    if arg == "--root":
        if not argv:
            die(64, "--root needs a value")
        root = argv.pop(0)
    elif arg.startswith("-"):
        die(64, f"unknown argument: {arg}")
    elif manifest is None:
        manifest = arg
    else:
        names.append(arg)
if manifest is None:
    die(64, "usage: run-gates.sh <manifest.json> [--root <dir>] [test|lint|typecheck|build|sweep ...]")
for n in names:
    if n not in KNOWN:
        die(64, f"unknown gate: {n} (known: {', '.join(KNOWN)})")
if root is None:
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    root = top.stdout.strip() if top.returncode == 0 and top.stdout.strip() else os.getcwd()
root = os.path.realpath(root)
try:
    gates = json.load(open(manifest, encoding="utf-8"))
except (OSError, ValueError) as e:
    die(71, f"cannot read the gate manifest {manifest}: {e}")
if not isinstance(gates, dict):
    die(71, f"the gate manifest {manifest} is not an object")


JS_TOOLS = ("npm", "npx", "pnpm", "pnpx", "yarn", "bun", "bunx", "node", "corepack")
DEP_KEYS = ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies")


def runs_js_tool(cmd):
    """True when the first word of cmd, after any NAME=value words, is a JS tool. A cmd that does
    not split keeps the check."""
    try:
        words = shlex.split(cmd)
    except ValueError:
        return True
    while words and re.match(r"[A-Za-z_][A-Za-z0-9_]*=", words[0]):
        words.pop(0)
    return bool(words) and os.path.basename(words[0]) in JS_TOOLS


def declares_deps(path):
    """True when the package.json at path is an object with a non-empty dependency object or a
    workspaces key. One that does not parse counts as declaring."""
    try:
        with open(path, encoding="utf-8") as f:
            pkg = json.load(f)
    except (OSError, ValueError, RecursionError):
        return True
    return isinstance(pkg, dict) and ("workspaces" in pkg or any(isinstance(pkg.get(k), dict) and pkg[k] for k in DEP_KEYS))


def deps_missing(cwd, cmd):
    """True when cmd runs a JS tool, cwd has a package.json that declares dependencies, and no
    node_modules folder, .pnp.cjs file or .pnp.js file exists in cwd or in any folder above it, up
    to and including the root (npm workspaces install at the root)."""
    pkg = os.path.join(cwd, "package.json")
    if not os.path.isfile(pkg) or not runs_js_tool(cmd) or not declares_deps(pkg):
        return False
    d = cwd
    while True:
        if os.path.isdir(os.path.join(d, "node_modules")) or any(os.path.isfile(os.path.join(d, f)) for f in (".pnp.cjs", ".pnp.js")):
            return False
        if d == root or os.path.dirname(d) == d:
            return True
        d = os.path.dirname(d)


plan = []  # every gate is checked before any of them runs
for key in (names or ORDER):
    gate = gates.get(key)
    if gate is None and key == "sweep":
        gate = gates.get("test")  # a null or missing sweep runs the test entry in its place
    if gate is None:
        continue
    if not isinstance(gate, dict) or not isinstance(gate.get("cmd"), str) or not gate["cmd"].strip():
        die(71, f"gate {key} has no cmd")
    if not isinstance(gate.get("cwd") or ".", str):
        die(71, f"gate {key}: cwd is not text")
    cwd = os.path.realpath(os.path.join(root, gate.get("cwd") or "."))
    if cwd != root and not cwd.startswith(root + os.sep):
        die(71, f"gate {key}: cwd {gate.get('cwd')!r} leaves the root {root}")
    if not os.path.isdir(cwd):
        die(71, f"gate {key}: cwd {cwd} does not exist")
    if deps_missing(cwd, gate["cmd"]):
        die(71, f"{key}: dependencies are not installed (no node_modules for {gate.get('cwd') or '.'}/package.json)")
    plan.append((key, gate["cmd"], cwd))
for key, cmd, cwd in plan:
    print(f"run-gates.sh: {key}: {cmd}  (in {cwd})", file=sys.stderr, flush=True)
    rc = subprocess.run(["sh", "-c", cmd], cwd=cwd).returncode
    if rc != 0:
        rc = rc if rc > 0 else 128 - rc
        print(f"run-gates.sh: {key} failed (exit {rc})", file=sys.stderr)
        sys.exit(1 if rc in (64, 71, 75, 124, 125) else rc)
if not plan:
    print("run-gates.sh: no gates to run", file=sys.stderr)
PY
