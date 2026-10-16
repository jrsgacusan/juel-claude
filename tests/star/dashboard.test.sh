#!/bin/sh
# skills/star/dashboard.sh on a copy of the repo with a temp HOME and fakes on PATH (open, orca,
# claude, npm): no real browser opens, no real STAR is woken, no real web build runs.
set -u
unset JUEL_DIR  # an inherited one would point the runs below at someone's real dashboard
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
cleanup() {
  for f in "$TMP"/home/.juel/dashboard.json "$TMP"/juel-*/dashboard.json; do
    [ -f "$f" ] && kill "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "$f")" 2>/dev/null
  done
  rm -rf "$TMP"
}
trap cleanup EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

R="$TMP/repo"
mkdir -p "$R/dashboard" "$R/skills"
cp -R "$ROOT/dashboard/server" "$R/dashboard/server"
cp -R "$ROOT/hooks" "$ROOT/types" "$R/"
cp -R "$ROOT/skills/star" "$R/skills/star"
rm -rf "$R/dashboard/web"
mkdir -p "$TMP/bin" "$TMP/home"
cat > "$TMP/bin/open" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/opened"
EOF
cat > "$TMP/bin/orca" <<'EOF'
#!/bin/sh
echo '{"result":{"terminals":[]}}'
EOF
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/claude"
printf '#!/bin/sh\nexit 127\n' > "$TMP/bin/cswap"  # the accounts module must never read the real cswap
cat > "$TMP/bin/npm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/npm.log"
if [ "\$1 \$2" = "run build" ]; then mkdir -p dist && echo '<!doctype html><title>built</title>' > dist/index.html; fi
exit 0
EOF
cat > "$TMP/bin/tailscale" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/tailscale.log"
if [ -f "$TMP/ts.fail" ]; then echo 'failed to connect to local Tailscale daemon' >&2; exit 1; fi
cat "$TMP/ts.json" 2>/dev/null || echo '{}'
EOF
chmod +x "$TMP/bin/open" "$TMP/bin/orca" "$TMP/bin/claude" "$TMP/bin/cswap" "$TMP/bin/tailscale" "$TMP/bin/npm"
D() { HOME="$TMP/home" PATH="$TMP/bin:$PATH" sh "$R/skills/star/dashboard.sh" "$@"; }
conf() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[sys.argv[2]])' "$TMP/home/.juel/dashboard.json" "$1"; }

# no dashboard/web: no build, the server starts once, the URL is printed and opened
out=$(D 2>&1); rc=$?
url=$(printf '%s\n' "$out" | sed -n 's/^STAR dashboard: //p')
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'no dashboard/web yet' && [ -n "$url" ] && pass "with no dashboard/web it starts the server and prints the URL" || fail "first run (rc=$rc): $out"
printf '%s\n' "$out" | grep -q 'No such file or directory' && fail "the first run printed a shell error: $out" || pass "the first run prints no shell error"
[ "$(printf '%s\n' "$out" | grep -vc -e '^STAR dashboard: ' -e '^dashboard.sh: ')" = 0 ] && pass "every first-run line is the URL or a dashboard.sh line" || fail "unexpected first-run lines: $out"
[ "$(cat "$TMP/opened" 2>/dev/null)" = "$url" ] && pass "it opens the URL" || fail "opened: $(cat "$TMP/opened" 2>/dev/null)"
pid=$(conf pid); port=$(conf port); token=$(conf token)
[ "$url" = "http://127.0.0.1:$port/?t=$token" ] && kill -0 "$pid" 2>/dev/null && pass "dashboard.json names the live server and its token" || fail "dashboard.json: pid=$pid port=$port"
curl -s "http://127.0.0.1:$port/" | grep -q 'Build the web app first' && pass "the page says to build the web app first" || fail "page"
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/api/projects")" = 401 ] && pass "the API refuses a request without the token" || fail "no 401"
[ ! -e "$TMP/npm.log" ] && pass "nothing was built" || fail "npm ran: $(cat "$TMP/npm.log")"

# run again: the same server, the URL opened again, nothing started
out2=$(D 2>&1)
[ "$(conf pid)" = "$pid" ] && [ "$(grep -c . "$TMP/opened")" = 2 ] && printf '%s\n' "$out2" | grep -qF "STAR dashboard: $url" && pass "a second run only opens the URL" || fail "second run: $out2"
if command -v pgrep >/dev/null 2>&1 && pgrep -f "$R/dashboard/server/main.ts" >/dev/null 2>&1; then
  count=$(pgrep -f "$R/dashboard/server/main.ts" 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" = 1 ] && pass "one server process" || fail "server processes: $count"
else
  kill -0 "$pid" 2>/dev/null && pass "one server process (process listing unavailable)" || fail "server process is gone"
fi

# a web app: built when dist/ is missing, not when it is fresh, again when a source is newer
W="$R/dashboard/web"; mkdir -p "$W/src"
echo '{"name":"web","private":true}' > "$W/package.json"; echo '{}' > "$W/package-lock.json"; echo 'x' > "$W/src/main.tsx"
out=$(STAR_FREE_GB=8 D 2>&1)
[ -f "$W/dist/index.html" ] && grep -qx 'ci' "$TMP/npm.log" && grep -qx 'run build' "$TMP/npm.log" && pass "a missing dist/ is built with npm ci and npm run build" || fail "build: $out / $(cat "$TMP/npm.log" 2>/dev/null)"
: > "$TMP/npm.log"
out=$(STAR_FREE_GB=8 D 2>&1)
[ ! -s "$TMP/npm.log" ] && pass "a fresh dist/ is not built again" || fail "rebuilt a fresh dist: $(cat "$TMP/npm.log")"
touch -t 202001010000 "$W/dist/index.html"
out=$(STAR_FREE_GB=8 D 2>&1)
grep -qx 'run build' "$TMP/npm.log" && pass "a source newer than dist/ rebuilds it" || fail "stale dist not rebuilt: $out"
: > "$TMP/npm.log"; touch -t 202001010000 "$W/dist/index.html"
out=$(STAR_FREE_GB=1 D 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -s "$TMP/npm.log" ] && printf '%s\n' "$out" | grep -q 'serving the web app built before' && pass "low memory serves the stale build and builds nothing" || fail "low memory with a stale dist (rc=$rc): $out"
rm -rf "$W/dist"
out=$(STAR_FREE_GB=1 D 2>&1); rc=$?
[ "$rc" = 1 ] && [ ! -s "$TMP/npm.log" ] && printf '%s\n' "$out" | grep -q 'GB free' && pass "low memory with no dist/ refuses to build and exits 1" || fail "low memory with no dist (rc=$rc): $out"

# the real memory reading: a fake vm_stat with little free memory holds the build
cat > "$TMP/bin/vm_stat" <<'EOF'
#!/bin/sh
echo 'Mach Virtual Memory Statistics: (page size of 16384 bytes)'
echo 'Pages free:                               1000.'
echo 'Pages inactive:                           1000.'
EOF
chmod +x "$TMP/bin/vm_stat"
: > "$TMP/npm.log"; mkdir -p "$W/dist"; echo old > "$W/dist/index.html"; touch -t 202001010000 "$W/dist/index.html"
out=$(env -u STAR_FREE_GB HOME="$TMP/home" PATH="$TMP/bin:$PATH" sh "$R/skills/star/dashboard.sh" 2>&1)
printf '%s\n' "$out" | grep -q 'only 0 GB free' && [ ! -s "$TMP/npm.log" ] && pass "vm_stat's free + inactive pages are read" || fail "vm_stat reading: $out"
printf '#!/bin/sh\necho "Pages free: x"\n' > "$TMP/bin/vm_stat"
out=$(env -u STAR_FREE_GB HOME="$TMP/home" PATH="$TMP/bin:$PATH" sh "$R/skills/star/dashboard.sh" 2>&1)
printf '%s\n' "$out" | grep -q 'could not read free memory' && pass "an unreadable memory reading is said" || fail "no memory line: $out"
rm -f "$TMP/bin/vm_stat"

# a pid that is alive but not a dashboard (reused after a reboot): a new server starts
pid=$(conf pid); kill "$pid"; n=0; while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 40 ]; do sleep 0.25; n=$((n + 1)); done
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["pid"]=int(sys.argv[2]); json.dump(d,open(p,"w"))' "$TMP/home/.juel/dashboard.json" "$$"
out=$(STAR_FREE_GB=8 D 2>&1)
np=$(conf pid)
[ "$np" != "$$" ] && kill -0 "$np" 2>/dev/null && pass "a reused pid starts a new server" || fail "reused pid: $out"

# a server another checkout started is replaced by this checkout's, on the same port and token
R2="$TMP/repo2"; cp -R "$R" "$R2"
oldpid=$(conf pid); oldport=$(conf port)
out=$(HOME="$TMP/home" PATH="$TMP/bin:$PATH" STAR_FREE_GB=8 sh "$R2/skills/star/dashboard.sh" 2>&1)
newpid=$(conf pid)
newcommand=$(ps -p "$newpid" -o command= 2>/dev/null || true)
if [ -n "$newcommand" ]; then
  ! kill -0 "$oldpid" 2>/dev/null && [ "$newpid" != "$oldpid" ] && printf '%s\n' "$newcommand" | grep -qF "$R2/dashboard/server/main.ts" && [ "$(conf port)" = "$oldport" ] \
    && pass "another checkout's server is replaced by this one's" || fail "other checkout: $out"
else
  [ "$newpid" = "$oldpid" ] && kill -0 "$newpid" 2>/dev/null && [ "$(conf port)" = "$oldport" ] \
    && pass "another checkout's server identity is checked by its live endpoint (process listing unavailable)" || fail "other checkout: $out"
fi

# a server that cannot start: said at once, with its error, not the node version line
R3="$TMP/repo3"; cp -R "$R" "$R3"; printf "throw new Error('boom at start')\n" > "$R3/dashboard/server/main.ts"
mkdir -p "$TMP/home3"
start=$(date +%s)
out=$(HOME="$TMP/home3" PATH="$TMP/bin:$PATH" sh "$R3/skills/star/dashboard.sh" 2>&1); rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'boom at start' && [ $(( $(date +%s) - start )) -lt 10 ] && pass "a server that cannot start is said at once, with its error" || fail "failed start (rc=$rc): $out"

# a server started by hand from the repo root, with the relative path the docs give, is this checkout's: it is opened, never replaced
kill "$(conf pid)" 2>/dev/null; n=0; while [ -n "$(lsof -nP -iTCP:"$(conf port)" -sTCP:LISTEN 2>/dev/null)" ] && [ "$n" -lt 40 ]; do sleep 0.25; n=$((n + 1)); done
(cd "$R2" && HOME="$TMP/home" PATH="$TMP/bin:$PATH" node dashboard/server/main.ts > /dev/null 2>&1 &)
n=0; until [ -f "$TMP/home/.juel/dashboard.json" ] && kill -0 "$(conf pid)" 2>/dev/null && ps -p "$(conf pid)" -o command= | grep -q 'node dashboard/server/main.ts'; do sleep 0.25; n=$((n + 1)); [ "$n" -gt 60 ] && break; done
relpid=$(conf pid)
out=$(HOME="$TMP/home" PATH="$TMP/bin:$PATH" STAR_FREE_GB=8 sh "$R2/skills/star/dashboard.sh" 2>&1)
[ "$(conf pid)" = "$relpid" ] && kill -0 "$relpid" 2>/dev/null && ! printf '%s\n' "$out" | grep -q 'stopping the dashboard' \
  && pass "a server started with the relative path is opened, not replaced" || fail "relative start (pid $relpid → $(conf pid)): $out"

# lane f: JUEL_DIR, the fixed port and the tailnet URL
D2() { HOME="$TMP/home" PATH="$TMP/bin:$PATH" STAR_FREE_GB=8 sh "$R2/skills/star/dashboard.sh" "$@"; }
confin() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[sys.argv[2]])' "$1/dashboard.json" "$2"; }
livepid=$(conf pid); liveport=$(conf port); livetoken=$(conf token)

J="$TMP/juel-alt"
out=$(JUEL_DIR="$J" D2 2>&1); rc=$?
altpid=$(confin "$J" pid 2>/dev/null); altport=$(confin "$J" port 2>/dev/null)
[ "$rc" = 0 ] && kill -0 "$altpid" 2>/dev/null && [ -s "$J/dashboard.log" ] && printf '%s\n' "$out" | grep -qF "STAR dashboard: http://127.0.0.1:$altport/?t=" \
  && pass "JUEL_DIR holds a second dashboard's config and log" || fail "JUEL_DIR start (rc=$rc): $out"
[ "$(conf pid) $(conf port) $(conf token)" = "$livepid $liveport $livetoken" ] && kill -0 "$livepid" 2>/dev/null && [ "$altport" != "$liveport" ] \
  && pass "the dashboard under HOME/.juel keeps its pid, port and token" || fail "the HOME dashboard changed: $(cat "$TMP/home/.juel/dashboard.json")"
out=$(JUEL_DIR= D2 2>&1)
printf '%s\n' "$out" | grep -qxF "STAR dashboard: http://127.0.0.1:$liveport/?t=$livetoken" && [ "$(conf pid)" = "$livepid" ] \
  && pass "an empty JUEL_DIR is ~/.juel" || fail "empty JUEL_DIR: $out"

python3 -c 'import socket, time
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(1)
print(s.getsockname()[1], flush=True); time.sleep(60)' > "$TMP/blocker.port" &
BLOCKER=$!
n=0; until [ -s "$TMP/blocker.port" ] || [ "$n" -gt 40 ]; do sleep 0.25; n=$((n + 1)); done
P=$(cat "$TMP/blocker.port"); mkdir -p "$TMP/juel-busy"
printf '{"port": %s, "token": "abcdefabcdefabcdefabcdefabcdef12", "pid": 999999}\n' "$P" > "$TMP/juel-busy/dashboard.json"
out=$(JUEL_DIR="$TMP/juel-busy" D2 2>&1); rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -qF "dashboard.sh: the server did not start: port $P is busy: the dashboard keeps its port so tailscale serve keeps reaching it." \
  && [ "$(confin "$TMP/juel-busy" port)" = "$P" ] \
  && pass "a busy recorded port stops the start, says so, and stays recorded" || fail "busy port (rc=$rc): $out"
kill "$BLOCKER" 2>/dev/null

serve_json() {  # <host:port> <proxy>: one HTTPS mapping of / in tailscale serve status --json
  python3 -c 'import json, sys
host, proxy = sys.argv[1], sys.argv[2]
print(json.dumps({"TCP": {host.rsplit(":", 1)[1]: {"HTTPS": True}}, "Web": {host: {"Handlers": {"/": {"Proxy": proxy}}}}}))' "$1" "$2" > "$TMP/ts.json"
}
serve_json "mac.tail1234.ts.net:443" "http://127.0.0.1:$liveport"
out=$(D2 2>&1)
[ "$(printf '%s\n' "$out" | grep -A1 '^STAR dashboard: ' | sed -n 2p)" = "STAR dashboard on your tailnet: https://mac.tail1234.ts.net/?t=$livetoken" ] \
  && pass "tailscale serve on the port prints the tailnet URL after the local one" || fail "tailnet line: $out"
serve_json "mac.tail1234.ts.net:8443" "http://localhost:$liveport/"
out=$(D2 2>&1)
printf '%s\n' "$out" | grep -qxF "STAR dashboard on your tailnet: https://mac.tail1234.ts.net:8443/?t=$livetoken" \
  && pass "a localhost proxy on 8443 names the port" || fail "8443: $out"
serve_json "mac.tail1234.ts.net:443" "http://127.0.0.1:$((liveport + 1))"
out=$(D2 2>&1)
! printf '%s\n' "$out" | grep -q 'on your tailnet' && pass "tailscale serve for another port prints no tailnet line" || fail "other port: $out"
touch "$TMP/ts.fail"; out=$(D2 2>&1); rm -f "$TMP/ts.fail"
! printf '%s\n' "$out" | grep -q -e 'on your tailnet' -e 'Tailscale daemon' && pass "a tailscale that fails adds nothing" || fail "failing tailscale: $out"
mkdir -p "$TMP/bin-nots"
for f in "$TMP"/bin/*; do [ "$(basename "$f")" = tailscale ] || cp "$f" "$TMP/bin-nots/"; done
ln -s "$(command -v node)" "$(command -v python3)" "$TMP/bin-nots/"
NOTS="$TMP/bin-nots:/usr/bin:/bin:/usr/sbin:/sbin"
if [ -n "$(PATH="$NOTS"; command -v tailscale)" ]; then
  fail "a tailscale outside the test's bin is on $NOTS"
else
  out=$(HOME="$TMP/home" PATH="$NOTS" STAR_FREE_GB=8 sh "$R2/skills/star/dashboard.sh" 2>&1); rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qxF "STAR dashboard: http://127.0.0.1:$liveport/?t=$livetoken" && ! printf '%s\n' "$out" | grep -q 'tailnet' \
    && pass "without tailscale nothing more is printed" || fail "no tailscale (rc=$rc): $out"
fi
[ "$(sort -u "$TMP/tailscale.log")" = "serve status --json" ] && pass "tailscale is only asked serve status --json" || fail "tailscale calls: $(sort -u "$TMP/tailscale.log")"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
