#!/bin/sh
# Opens the STAR dashboard: one local server on this Mac for every project's STAR folder.
#   sh skills/star/dashboard.sh [--tailnet]
# Builds dashboard/web (npm ci, npm run build) when its package.json exists and dist/ is missing or
# older than web/src, web/package.json or web/package-lock.json, and free + inactive memory is at
# least 3 GB (STAR_FREE_GB overrides the reading); with less, an earlier build is served as it is.
# Starts node dashboard/server/main.ts from this checkout, in its own session (output to
# ~/.juel/dashboard.log; $JUEL_DIR replaces ~/.juel when it is set and not empty), unless the pid in
# ~/.juel/dashboard.json is this checkout's live server;
# a server another checkout or plugin version started is stopped first and replaced on the same
# port and token. The port recorded in dashboard.json never moves: when something else holds it the
# server does not start, and the line says so. Then prints "STAR dashboard: <url>", and "STAR dashboard
# on your tailnet: <url>" when tailscale serve maps / to this port over HTTPS, and runs `open <url>`.
# Without --tailnet the only tailscale command is `serve status --json`; when Tailscale answers and
# nothing serves / over HTTPS on 443, one line says to run this with --tailnet. With --tailnet, when
# Tailscale is running and nothing else serves / over HTTPS on 443, it runs `tailscale serve --bg <port>`
# (HTTPS inside your tailnet only) and prints the tailnet link, or one line saying why it could not.
# The commands it may run are `tailscale serve status --json`, `tailscale status --json` and
# `tailscale serve --bg <port>`, the last stopped after JUEL_TAILSCALE_TIMEOUT seconds (an integer,
# default 20). Never tailscale funnel, never tailscale serve reset. Other lines start "dashboard.sh: ".
# Exit: 0 ok (also when `open` fails or tailscale cannot map it); 1 no node 24 or later, too little memory and no earlier
# build, the build failed, or the server did not start (with its error); 64 a usage error.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WEB="$ROOT/dashboard/web"
SERVER="$ROOT/dashboard/server/main.ts"
JUEL="${JUEL_DIR:-$HOME/.juel}"
CONF="$JUEL/dashboard.json"
LOG="$JUEL/dashboard.log"
MIN_GB=3
OTHER=

say() { echo "dashboard.sh: $*"; }

TAILNET_FLAG=0
case "$#:${1:-}" in
  0:) ;;
  1:--tailnet) TAILNET_FLAG=1 ;;
  *) say "usage: dashboard.sh [--tailnet]"; exit 64 ;;
esac

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

# The real path of the main.ts a dashboard process runs: its command line minus the node binary,
# resolved against the process's own folder when it is relative (`node dashboard/server/main.ts`
# from the repo root, as the docs give it). Nothing when that folder cannot be read.
server_of() {  # <pid> <command line>
  script=${2#* }
  case "$script" in
    /*) ;;
    *)
      cwd=$(lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)
      [ -n "$cwd" ] || return 0
      script="$cwd/$script"
      ;;
  esac
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$script"
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
      *dashboard/server/main.ts*) ;;
      *) return 1 ;;  # a reused pid
    esac
    theirs=$(server_of "$pid" "$command")
    mine=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SERVER")
    # A server whose path cannot be told is left running and opened: never stop what cannot be placed.
    if [ -n "$theirs" ] && [ "$theirs" != "$mine" ]; then
      OTHER=$pid
      return 1
    fi
    PORT=$port
    TOKEN=$token
    return 0
  fi
  curl -fsS -H "x-star-token: $token" "http://127.0.0.1:$port/api/projects" >/dev/null 2>&1 || return 1
  PORT=$port
  TOKEN=$token
}

# Why the server did not start, from what the log gained since $start: its own "could not start" line, else the errors, else the tail.
startup_error() {
  new=$(tail -c +$((start + 1)) "$LOG" 2>/dev/null || true)
  detail=$(printf '%s\n' "$new" | sed -n 's/^.*star dashboard: could not start: //p' | head -n 1)
  [ -n "$detail" ] || detail=$(printf '%s\n' "$new" | grep -m 3 -E 'Error|error' || true)
  [ -n "$detail" ] || detail=$(tail -n 5 "$LOG" 2>/dev/null || true)
  say "the server did not start: $detail"
}

# What tailscale serve status --json says about this port, as one line, or nothing when tailscale is
# missing, failed, slow (5 s) or answered something that is not an object:
#   url <https url>/?t=<token>  a Web handler for / proxies to this port on an HTTPS host:port
#   taken <proxy>               some other Web handler for / is on <host>:443
#   free                        neither
tailnet_probe() {  # <port> <token>
  command -v tailscale >/dev/null 2>&1 || return 0
  python3 -c '
import json, subprocess, sys
port, token = sys.argv[1], sys.argv[2]
try:
    r = subprocess.run(["tailscale", "serve", "status", "--json"], capture_output=True, text=True, timeout=5)
    if r.returncode != 0:
        sys.exit(0)
    d = json.loads(r.stdout)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
targets = ("http://127.0.0.1:" + port, "http://localhost:" + port)
configs = [d]
fg = d.get("Foreground")
if isinstance(fg, dict):
    configs += [c for c in fg.values() if isinstance(c, dict)]
taken = None
for c in configs:
    web, tcp = c.get("Web"), c.get("TCP")
    if not isinstance(web, dict):
        continue
    for hostport, entry in web.items():
        host, _, p = hostport.rpartition(":")
        try:
            handler = entry["Handlers"]["/"]
        except Exception:
            continue
        if not isinstance(handler, dict):
            continue
        proxy = handler.get("Proxy")
        if isinstance(proxy, str) and proxy.rstrip("/") in targets and isinstance(tcp, dict):
            t = tcp.get(p)
            if isinstance(t, dict) and t.get("HTTPS") is True:
                print("url https://" + host + ("" if p == "443" else ":" + p) + "/?t=" + token)
                sys.exit(0)
        if p == "443" and taken is None:
            taken = proxy if isinstance(proxy, str) and proxy else "a path or text handler"
print("taken " + taken if taken is not None else "free")
' "$1" "$2" 2>/dev/null || true
}

# BackendState from tailscale status --json (5 s), or "unknown".
tailnet_state() {
  python3 -c '
import json, subprocess
try:
    r = subprocess.run(["tailscale", "status", "--json"], capture_output=True, text=True, timeout=5)
    s = json.loads(r.stdout).get("BackendState") if r.returncode == 0 else None
    print(s if isinstance(s, str) and s else "unknown")
except Exception:
    print("unknown")
' 2>/dev/null || echo unknown
}

# tailscale serve --bg <port>, stopped after JUEL_TAILSCALE_TIMEOUT seconds. Prints nothing when it
# exited 0, else why: its last non-empty output line, or "no answer in <n> s".
tailnet_serve() {  # <port>
  python3 -c '
import os, subprocess, sys, tempfile
port = sys.argv[1]
t = os.environ.get("JUEL_TAILSCALE_TIMEOUT", "")
n = int(t) if t.isdigit() and int(t) > 0 else 20
with tempfile.TemporaryFile("w+") as out:
    try:
        rc = subprocess.run(["tailscale", "serve", "--bg", port], stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT, timeout=n).returncode
    except subprocess.TimeoutExpired:
        rc = None
    except Exception:
        rc = 1
    out.seek(0)
    lines = [l.strip() for l in out.read().splitlines() if l.strip()]
if rc == 0:
    sys.exit(0)
print(lines[-1] if lines else "no answer in %d s" % n)
' "$1" 2>/dev/null || echo "no answer"
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
      startup_error
      exit 1
    fi
    n=$((n + 1))
    sleep 0.25
  done
  if ! running; then
    startup_error
    exit 1
  fi
fi
URL="http://127.0.0.1:$PORT/?t=$TOKEN"
echo "STAR dashboard: $URL"
PROBE=$(tailnet_probe "$PORT" "$TOKEN")
TAILNET_LINE="STAR dashboard on your tailnet: "
if [ "$TAILNET_FLAG" = 0 ]; then
  case "$PROBE" in
    "url "*) echo "${TAILNET_LINE}${PROBE#url }" ;;
    free) say "to open it from your phone, run /juel:star dashboard --tailnet (tailscale serve, inside your tailnet only)" ;;
  esac
elif ! command -v tailscale >/dev/null 2>&1; then
  say "--tailnet needs tailscale on PATH: install Tailscale and sign in, then run this again"
else
  STATE=$(tailnet_state)
  if [ "$STATE" != Running ]; then
    say "tailscale is not running ($STATE): start it and sign in, then run this again"
  else
    case "$PROBE" in
      "url "*) echo "${TAILNET_LINE}${PROBE#url }" ;;
      "taken "*) say "tailscale serve already sends https / to ${PROBE#taken }: left as it is; map the dashboard yourself with tailscale serve --bg --https=<another port> $PORT" ;;
      '') say "tailscale serve status did not answer: map the dashboard yourself with tailscale serve --bg $PORT" ;;
      *)
        WHY=$(tailnet_serve "$PORT")
        if [ -n "$WHY" ]; then
          say "tailscale serve --bg $PORT did not map the dashboard: $WHY"
        else
          PROBE=$(tailnet_probe "$PORT" "$TOKEN")
          case "$PROBE" in
            "url "*) echo "${TAILNET_LINE}${PROBE#url }" ;;
            *) say "tailscale serve ran, but no HTTPS address on your tailnet reaches port $PORT" ;;
          esac
        fi
        ;;
    esac
  fi
fi
open "$URL" >/dev/null 2>&1 || say "could not open a browser: open the URL above"
