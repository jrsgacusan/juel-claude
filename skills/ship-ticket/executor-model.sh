#!/bin/sh
# Resolves the model and effort a codex plan run uses, from what Codex can launch right now.
#   executor-model.sh [--model <id|latest-<family>>] [--effort <level>]
# Prints one line and exits 0:
#   <model> <effort>   pass the model as -m and the effort as -c model_reasoning_effort="<effort>"
#   default <why>      codex cannot list its models, or nothing matches: pass neither flag
# latest-<family> is the first model `codex debug models` lists (lowest priority number, visibility
# "list") whose slug contains "-<family>", whose description does not call it older, previous or
# legacy, and that is not retiring (the rule skills/team/discover-models.sh applies). A plain id is
# used as given when Codex lists it. The effort is the one asked for when the model supports it,
# else the highest it supports below that; a model that lists no efforts gets the one asked for.
# Defaults: --model latest-luna, --effort xhigh. EXECUTOR_MODEL_TIMEOUT: seconds (default 30).
# Exit: 0, or 64 on bad usage.
exec python3 - "$@" <<'PY'
import json
import os
import subprocess
import sys

ORDER = ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
LEGACY_WORDS = ("older", "previous", "legacy")


def die(msg):
    print(f"executor-model.sh: {msg}", file=sys.stderr)
    sys.exit(64)


def out(line):
    print(line)
    sys.exit(0)


model, effort, args = "latest-luna", "xhigh", sys.argv[1:]
while args:
    arg = args.pop(0)
    if arg not in ("--model", "--effort") or not args or not args[0].strip():
        die(f"unknown or empty argument: {arg}")
    value = args.pop(0).strip()
    if arg == "--model":
        model = value
    else:
        effort = value
if effort not in ORDER:
    die(f"--effort must be one of {', '.join(ORDER)}")
try:
    limit = float(os.environ.get("EXECUTOR_MODEL_TIMEOUT", "30"))
except ValueError:
    limit = 30.0
try:
    proc = subprocess.run(["codex", "debug", "models"], capture_output=True, text=True, timeout=limit,
                          stdin=subprocess.DEVNULL)
except FileNotFoundError:
    out("default codex not found on PATH")
except subprocess.TimeoutExpired:
    out(f"default codex debug models timed out after {limit:g}s")
if proc.returncode != 0:
    out(f"default codex debug models exited {proc.returncode}")
try:
    listed = [m for m in json.loads(proc.stdout)["models"]
              if isinstance(m, dict) and m.get("visibility") == "list" and m.get("slug")]
except (ValueError, KeyError, TypeError):
    out("default codex debug models printed something unreadable")
listed.sort(key=lambda m: m.get("priority", 999))


def current(m):
    description = str(m.get("description") or "").lower()
    upgrade = m.get("upgrade") if isinstance(m.get("upgrade"), dict) else {}
    return not upgrade.get("retirement_at") and not any(w in description for w in LEGACY_WORDS)


if model.startswith("latest-"):
    family = model[len("latest-"):]
    chosen = next((m for m in listed if f"-{family}" in str(m["slug"]) and current(m)), None)
    if chosen is None:
        out(f"default no current {family} model is listed")
else:
    chosen = next((m for m in listed if m["slug"] == model), None)
    if chosen is None:
        out(f"default {model} is not listed")
levels = [l.get("effort") if isinstance(l, dict) else l for l in chosen.get("supported_reasoning_levels") or []]
levels = [l for l in levels if l in ORDER]
if levels and effort not in levels:
    below = [l for l in levels if ORDER.index(l) < ORDER.index(effort)]
    effort = max(below, key=ORDER.index) if below else min(levels, key=ORDER.index)
out(f"{chosen['slug']} {effort}")
PY
