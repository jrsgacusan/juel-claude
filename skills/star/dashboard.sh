#!/bin/sh
# Opens the STAR dashboard: one local server on this Mac for every project's STAR folder.
#   sh skills/star/dashboard.sh
# Builds dashboard/web (npm ci, npm run build) when its package.json exists and dist/ is missing or
# older than web/src, web/package.json or web/package-lock.json, and free + inactive memory is at
# least 3 GB (STAR_FREE_GB overrides the reading); with less, an earlier build is served as it is.
# Starts node dashboard/server/main.ts from this checkout, in its own session (output to
# ~/.juel/dashboard.log), unless the pid in ~/.juel/dashboard.json is this checkout's live server;
# a server another checkout or plugin version started is stopped first and replaced on the same
# port and token. Then prints "STAR dashboard: <url>" and runs `open <url>`. Other lines start
# "dashboard.sh: ".
# Exit: 0 ok (also when `open` fails); 1 no node 24 or later, too little memory and no earlier
# build, the build failed, or the server did not start (with its error).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WEB="$ROOT/dashboard/web"
SERVER="$ROOT/dashboard/server/main.ts"
JUEL="$HOME/.juel"
CONF="$JUEL/dashboard.json"
LOG="$JUEL/dashboard.log"
MIN_GB=3
OTHER=

say() { echo "dashboard.sh: $*"; }

command -v node >/dev/null 2>&1 && node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)' \
  || { say "the dashboard needs node 24 or later on PATH"; exit 1; }

free_gb() {
  if [ -n "${STAR_FREE_GB:-}" ]; then
    echo "$STAR_FREE_GB"
    return
  fi
  if command -v vm_stat >/dev/null 2>&1; then
    vm_stat | awk '/page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") ps = $(i + 1) }
      /^Pages free:/ { gsub(/\./, "", $3); f = $3 } /^Pages inactive:/ { gsub(/\./, "", $3); n = $3 }
      END { if (ps && f != "" && n != "") printf "%d\n", (f + n) * ps / 1073741824 }'
    return
  fi
  if command -v free >/dev/null 2>&1; then
    free -g | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "available") c = i + 1 } NR == 2 && c { print $c }'
  fi
}

stale() {
  [ -f "$WEB/dist/index.html" ] || return 0
  [ -n "$(find "$WEB/src" "$WEB/package.json" "$WEB/package-lock.json" -type f -newer "$WEB/dist/index.html" 2>/dev/null | head -n 1)" ]
}

if [ ! -f "$WEB/package.json" ]; then
  say "no dashboard/web yet: the page says to build the web app first"
elif stale; then
  gb=$(free_gb)
  case "$gb" in
    ''|*[!0-9]*)
      say "could not read free memory: building anyway"
      low=0
      ;;
    *)
      [ "$gb" -lt "$MIN_GB" ] && low=1 || low=0
      ;;
  esac
  if [ "$low" = 1 ] && [ -f "$WEB/dist/index.html" ]; then
    say "only ${gb} GB free (needs ${MIN_GB}): serving the web app built before; run this again later to rebuild it"
  elif [ "$low" = 1 ]; then
    say "only ${gb} GB free (needs ${MIN_GB}) to build the web app: close something, then run this again"
    exit 1
  else
    say "building dashboard/web (npm ci, then npm run build)"
    (cd "$WEB" && npm ci && npm run build) || {
      say "the web app did not build"
      exit 1
    }
  fi
fi

conf() {
  python3 - "$CONF" 2>/dev/null <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    print(int(d["pid"]), int(d["port"]), str(d["token"]))
except Exception:
    pass
PY
}

running() {
  OTHER=
  set -- $(conf)
  [ "$#" -eq 3 ] || return 1
  pid=$1
  port=$2
  token=$3
  kill -0 "$pid" 2>/dev/null || return 1
  command=$(ps -p "$pid" -o command= 2>/dev/null || true)
  if [ -n "$command" ]; then
    case "$command" in
      *"$SERVER"*)
        PORT=$port
        TOKEN=$token
        return 0
        ;;
      *dashboard/server/main.ts*)
        OTHER=$pid
        return 1
        ;;
      *)
        return 1
        ;;
    esac
  fi
  curl -fsS -H "x-star-token: $token" "http://127.0.0.1:$port/api/projects" >/dev/null 2>&1 || return 1
  PORT=$port
  TOKEN=$token
}

if ! running; then
  if [ -n "$OTHER" ]; then
    say "stopping the dashboard another checkout started (pid $OTHER)"
    kill "$OTHER" 2>/dev/null || true
    n=0
    while kill -0 "$OTHER" 2>/dev/null && [ "$n" -lt 20 ]; do
      sleep 0.25
      n=$((n + 1))
    done
  fi
  mkdir -p "$JUEL"
  start=0
  [ -f "$LOG" ] && start=$(wc -c < "$LOG" | tr -d ' ')
  CHILD=$(python3 - "$SERVER" "$LOG" <<'PY'
import subprocess, sys
with open(sys.argv[2], "ab") as log:
    p = subprocess.Popen(["node", sys.argv[1]], stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True, close_fds=True)
print(p.pid)
PY
  ) || {
    say "could not start node"
    exit 1
  }
  n=0
  while [ "$n" -lt 60 ]; do
    if running; then
      break
    fi
    if ! kill -0 "$CHILD" 2>/dev/null; then
      if running; then
        break
      fi
      detail=$(tail -c +$((start + 1)) "$LOG" 2>/dev/null | grep -m 3 -E 'Error|error' || true)
      [ -n "$detail" ] || detail=$(tail -n 5 "$LOG" 2>/dev/null || true)
      say "the server did not start: $detail"
      exit 1
    fi
    n=$((n + 1))
    sleep 0.25
  done
  if ! running; then
    detail=$(tail -c +$((start + 1)) "$LOG" 2>/dev/null | grep -m 3 -E 'Error|error' || true)
    [ -n "$detail" ] || detail=$(tail -n 5 "$LOG" 2>/dev/null || true)
    say "the server did not start: $detail"
    exit 1
  fi
fi
URL="http://127.0.0.1:$PORT/?t=$TOKEN"
echo "STAR dashboard: $URL"
open "$URL" >/dev/null 2>&1 || say "could not open a browser: open the URL above"
