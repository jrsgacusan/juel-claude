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
count=$(pgrep -f "$R/dashboard/server/main.ts" 2>/dev/null | wc -l | tr -d ' ')
[ "$count" = 1 ] && pass "one server process" || { [ "$count" = 0 ] && kill -0 "$pid" 2>/dev/null && pass "one server process (process listing unavailable)" || fail "server processes: $count"; }

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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
