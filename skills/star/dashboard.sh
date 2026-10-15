#!/bin/sh
# Opens the STAR dashboard: one local server on this Mac for every project's STAR folder.
#   sh skills/star/dashboard.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WEB="$ROOT/dashboard/web"
SERVER="$ROOT/dashboard/server/main.ts"
JUEL="$HOME/.juel"
CONF="$JUEL/dashboard.json"
MIN_GB=3

say() { echo "dashboard.sh: $*"; }

command -v node >/dev/null 2>&1 && node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)' \
  || { say "the dashboard needs node 24 or later on PATH"; exit 1; }

free_gb() {
  if [ -n "${STAR_FREE_GB:-}" ]; then echo "$STAR_FREE_GB"; return; fi
  if command -v vm_stat >/dev/null 2>&1; then
    vm_stat | awk '/page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") ps = $(i + 1) }
      /^Pages free:/ { gsub(/\./, "", $3); f = $3 } /^Pages inactive:/ { gsub(/\./, "", $3); n = $3 }
      END { if (ps && f != "") printf "%d\n", (f + n) * ps / 1073741824 }'
  elif command -v free >/dev/null 2>&1; then
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
    ''|*[!0-9]*) low=0 ;;
    *) [ "$gb" -lt "$MIN_GB" ] && low=1 || low=0 ;;
  esac
  if [ "$low" = 1 ] && [ -f "$WEB/dist/index.html" ]; then
    say "only ${gb} GB free (needs ${MIN_GB}): serving the web app built before; run this again later to rebuild it"
  elif [ "$low" = 1 ]; then
    say "only ${gb} GB free (needs ${MIN_GB}) to build the web app: close something, then run this again"
    exit 1
  else
    say "building dashboard/web (npm ci, then npm run build)"
    (cd "$WEB" && npm ci && npm run build) || { say "the web app did not build"; exit 1; }
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
  set -- $(conf)
  [ "$#" -eq 3 ] || return 1
  kill -0 "$1" 2>/dev/null || return 1
  if ! ps -p "$1" -o command= 2>/dev/null | grep -qF 'dashboard/server/main.ts'; then
    curl -fsS -H "x-star-token: $3" "http://127.0.0.1:$2/api/projects" >/dev/null 2>&1 || return 1
  fi
  PORT=$2
  TOKEN=$3
}

if ! running; then
  mkdir -p "$JUEL"
  python3 - "$SERVER" "$JUEL/dashboard.log" <<'PY' || { say "could not start node"; exit 1; }
import subprocess, sys
log = open(sys.argv[2], "ab")
subprocess.Popen(["node", sys.argv[1]], stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True, close_fds=True)
PY
  n=0
  until running; do
    n=$((n + 1))
    if [ "$n" -gt 60 ]; then
      say "the server did not start: $(tail -n 1 "$JUEL/dashboard.log" 2>/dev/null)"
      exit 1
    fi
    sleep 0.25
  done
fi
URL="http://127.0.0.1:$PORT/?t=$TOKEN"
echo "STAR dashboard: $URL"
open "$URL" >/dev/null 2>&1 || say "could not open a browser: open the URL above"
