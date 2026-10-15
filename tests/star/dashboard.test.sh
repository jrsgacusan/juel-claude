#!/bin/sh
# skills/star/dashboard.sh on a copy of the repo with a temp HOME and fakes on PATH (open, orca,
# claude, npm): no real browser opens, no real STAR is woken, no real web build runs.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
cleanup() {
  for f in "$TMP"/home/.juel/dashboard.json; do
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
cat > "$TMP/bin/npm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/npm.log"
if [ "\$1 \$2" = "run build" ]; then mkdir -p dist && echo '<!doctype html><title>built</title>' > dist/index.html; fi
exit 0
EOF
chmod +x "$TMP/bin/open" "$TMP/bin/orca" "$TMP/bin/claude" "$TMP/bin/npm"
D() { HOME="$TMP/home" PATH="$TMP/bin:$PATH" sh "$R/skills/star/dashboard.sh" "$@"; }
conf() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[sys.argv[2]])' "$TMP/home/.juel/dashboard.json" "$1"; }

# no dashboard/web: no build, the server starts once, the URL is printed and opened
out=$(D 2>&1); rc=$?
url=$(printf '%s\n' "$out" | sed -n 's/^STAR dashboard: //p')
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'no dashboard/web yet' && [ -n "$url" ] && pass "with no dashboard/web it starts the server and prints the URL" || fail "first run (rc=$rc): $out"
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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
