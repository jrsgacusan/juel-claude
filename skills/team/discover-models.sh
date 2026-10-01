#!/bin/sh
# Lists the models Codex and Claude Code can launch right now, one JSON object per line:
#   {"provider","id","name","description","efforts","default_effort","resolves_to","flags"}
# A provider that cannot be listed prints {"provider":"<p>","unavailable":"<reason>"} instead.
# Always exits 0. Diagnostics go to stderr. Per-provider timeout: TEAM_DISCOVER_TIMEOUT (default 30s).
exec python3 - "$@" <<'PY'
import json
import os
import subprocess
import sys

TIMEOUT = float(os.environ.get("TEAM_DISCOVER_TIMEOUT", "30"))
LEGACY_WORDS = ("older", "previous", "legacy")
CLAUDE_REQUEST = json.dumps({
    "type": "control_request",
    "request_id": "team",
    "request": {"subtype": "list_models"},
}) + "\n"


class Unavailable(Exception):
    pass


def run(argv, stdin=None):
    try:
        proc = subprocess.run(argv, input=stdin, capture_output=True, text=True, timeout=TIMEOUT)
    except FileNotFoundError:
        raise Unavailable(f"{argv[0]} not found on PATH")
    except subprocess.TimeoutExpired:
        raise Unavailable(f"{argv[0]} timed out after {TIMEOUT:g}s")
    if proc.returncode != 0:
        raise Unavailable(f"{argv[0]} exited {proc.returncode}: {proc.stderr.strip()[:200]}")
    return proc.stdout


def codex_models():
    catalog = json.loads(run(["codex", "debug", "models"]))
    listed = [m for m in catalog["models"] if m.get("visibility") == "list"]
    out = []
    for m in sorted(listed, key=lambda m: m.get("priority", 999)):
        description = m.get("description") or ""
        flags = []
        if (m.get("upgrade") or {}).get("retirement_at"):
            flags.append("retiring")
        if any(word in description.lower() for word in LEGACY_WORDS):
            flags.append("legacy")
        out.append({
            "provider": "codex",
            "id": m["slug"],
            "name": m.get("display_name") or m["slug"],
            "description": description,
            "efforts": [lvl["effort"] if isinstance(lvl, dict) else lvl
                        for lvl in m.get("supported_reasoning_levels") or []],
            "default_effort": m.get("default_reasoning_level"),
            "resolves_to": None,
            "flags": flags,
        })
    return out


def claude_models():
    stdout = run(
        ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"],
        stdin=CLAUDE_REQUEST,
    )
    for line in stdout.splitlines():
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if not isinstance(msg, dict) or msg.get("type") != "control_response":
            continue
        out = []
        for m in msg["response"]["response"]["models"]:
            if m.get("value") == "default" or m.get("disabled"):
                continue
            model_id = m["value"]
            out.append({
                "provider": "claude",
                "id": model_id,
                "name": m.get("displayName") or model_id,
                "description": m.get("description") or "",
                "efforts": m.get("supportedEffortLevels") or [],
                "default_effort": None,
                "resolves_to": m.get("resolvedModel"),
                "flags": [] if any(ch.isdigit() for ch in model_id) else ["alias"],
            })
        return out
    raise Unavailable("no control_response in claude output")


def emit(obj):
    print(json.dumps(obj, separators=(",", ":")))


for provider, lister in (("codex", codex_models), ("claude", claude_models)):
    try:
        models = lister()
        if not models:
            raise Unavailable("no models listed")
        for model in models:
            emit(model)
    except Unavailable as e:
        reason = str(e)
    except KeyError as e:
        reason = f"unexpected output shape: missing key {e}"
    except (ValueError, TypeError) as e:
        reason = f"unexpected output shape: {e}"
    else:
        continue
    emit({"provider": provider, "unavailable": reason})
    print(f"discover-models: {provider}: {reason}", file=sys.stderr)

sys.exit(0)
PY
