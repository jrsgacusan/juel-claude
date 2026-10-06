#!/bin/sh
# Runs the gates of a gate manifest, each in its own directory, exactly as they are written.
#   run-gates.sh <manifest.json> [--root <repo root>] [test|lint|typecheck|build ...]
# The manifest is what ship-ticket writes: {"test": {"cmd": "...", "cwd": "..."} | null, "lint": ...,
# "typecheck": ..., "build": ...}. No command is ever pasted into a quoted shell string, so quotes,
# "&&", "VAR=value" and spaces in a path all survive. cwd is relative to --root (default: the git
# top level, else the current directory) whatever directory the caller is in.
# With no gate names, every gate that is not null runs, in the order above. The first red gate
# stops the run.
# Exit: 0 all green (or nothing to run); the failing gate's own code, with "<gate> failed (exit N)"
# on stderr; 71 when a gate could not be run at all (manifest missing or unreadable, a cwd that
# does not exist or leaves the root); 64 bad usage. A gate whose own code is 64, 71, 75 or 124
# comes out as 1 (its real code stays in the message): those four belong to this script and to
# gate-lock.sh, and a red gate must never read as "busy" or "could not run".
# Use it inside the gate lock:  sh gate-lock.sh --holder <item> -- sh run-gates.sh <manifest> --root <root>
exec python3 - "$@" <<'PY'
import json
import os
import subprocess
import sys

ORDER = ("test", "lint", "typecheck", "build")


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
    die(64, "usage: run-gates.sh <manifest.json> [--root <dir>] [test|lint|typecheck|build ...]")
for n in names:
    if n not in ORDER:
        die(64, f"unknown gate: {n} (known: {', '.join(ORDER)})")
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

ran = 0
for key in (names or ORDER):
    gate = gates.get(key)
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
    print(f"run-gates.sh: {key}: {gate['cmd']}  (in {cwd})", file=sys.stderr, flush=True)
    rc = subprocess.run(["sh", "-c", gate["cmd"]], cwd=cwd).returncode
    ran += 1
    if rc != 0:
        rc = rc if rc > 0 else 128 - rc
        print(f"run-gates.sh: {key} failed (exit {rc})", file=sys.stderr)
        sys.exit(1 if rc in (64, 71, 75, 124) else rc)
if not ran:
    print("run-gates.sh: no gates to run", file=sys.stderr)
PY
