#!/bin/sh
# Runs skills/star/star-issue.sh against a stub gh and a scratch STAR folder.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
S="$ROOT/skills/star"
SCRIPT="$S/star-issue.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL star-issue.sh missing"; exit 1; }
APP="$TMP/app"; mkdir -p "$APP"
(cd "$APP" && git init -q -b main . && git commit -q --allow-empty -m init && git remote add origin git@github.com:acme/sphere-browser.git)
APP=$(cd "$APP" && pwd -P)
H=$(sh "$S/star-home.sh" --cwd "$APP" init)
sh "$S/ledger.sh" --home "$H" add SPH-13 ref=SPH-13 project=app >/dev/null
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/calls"
[ -f "$STUB_DIR/gh-fail" ] && { echo "HTTP 403: Resource not accessible" >&2; exit 1; }
case "$1 $2" in
  "issue list") echo '[{"number":8,"title":"star: orchestration check --types still returns heartbeat messages"}]' ;;
  "issue create") cp "$(printf '%s' "$*" | sed -n 's/.*--body-file \([^ ]*\).*/\1/p')" "$STUB_DIR/posted"; echo "https://github.com/jrsgacusan/juel-claude/issues/19" ;;
  "issue comment") echo "https://github.com/jrsgacusan/juel-claude/issues/8#issuecomment-1" ;;
esac
EOF
chmod +x "$TMP/bin/gh"
I() { PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" JUEL_GH=gh sh "$SCRIPT" --home "$H" "$@"; }
body() { printf '%s\n' "$1" > "$TMP/body.md"; }

# find
[ "$(I find heartbeat)" = "$(printf '#8\tstar: orchestration check --types still returns heartbeat messages')" ] && pass "find lists open matches" || fail "find ($(I find heartbeat))"
grep -q -- 'issue list --repo jrsgacusan/juel-claude --state open --search heartbeat --limit 5' "$TMP/calls" && pass "the repo comes from plugin.json" || fail "repo ($(cat "$TMP/calls"))"

# file, then the same fingerprint again
body "## What happened
<project>'s ITEM-1 waited 25 minutes for a build slot while <app> was idle."
out=$(I file --fingerprint pool-starves-builds --title "star: builds wait for every brief" --label enhancement --body-file "$TMP/body.md")
[ "$out" = "filed https://github.com/jrsgacusan/juel-claude/issues/19" ] && pass "file" || fail "file ($out)"
grep -q 'star-fingerprint: pool-starves-builds' "$TMP/posted" && pass "the fingerprint travels in the body" || fail "fingerprint marker"
grep -q "pool-starves-builds.https://github.com/jrsgacusan/juel-claude/issues/19" "$H/issues.log" && pass "issues.log records it" || fail "log"
n=$(wc -l < "$TMP/calls")
[ "$(I file --fingerprint pool-starves-builds --title "star: again" --label bug --body-file "$TMP/body.md")" = "already https://github.com/jrsgacusan/juel-claude/issues/19" ] && [ "$(wc -l < "$TMP/calls")" -eq "$n" ] && pass "a known fingerprint posts nothing" || fail "already"

# comment
out=$(I comment 8 --fingerprint heartbeats-again --body-file "$TMP/body.md")
[ "$out" = "commented https://github.com/jrsgacusan/juel-claude/issues/8#issuecomment-1" ] && pass "comment" || fail "comment ($out)"

# redaction: each of these is refused and nothing is posted
n=$(wc -l < "$TMP/calls")
refused() { body "$2"; out=$(I file --fingerprint "r-$1" --title "star: x" --label bug --body-file "$TMP/body.md"); rc=$?
  [ $rc -eq 65 ] && case "$out" in "refused $3"*) true ;; *) false ;; esac && pass "refused: $1" || fail "refused $1 ($rc $out)"; }
refused name "The App window stayed blank" "project name"
refused ref "SPH-13 never got a slot" "item"
refused path "it failed in $APP/src" "repository path"
refused remote "pushed to git@github.com:acme/sphere-browser.git" "remote URL"
refused reponame "see acme/sphere-browser for the run" "repository name"
refused home "the log is at $HOME/notes.txt" "home path"
git -C "$APP" config user.name "Pat Example"; git -C "$APP" config user.email "pat@example.com"
refused owner "the acme team runs it" "remote owner"
refused barerepo "the sphere-browser checkout" "repository name"
refused username "ask $(basename "$HOME") about it" "user name"
refused gitname "Pat Example saw it first" "git user name"
refused gitmail "mail pat@example.com" "git user email"
refused homeend "it lives in $HOME." "home path"
refused prefix "every SPH ticket stalls" "ref prefix"
body "x"; out=$(I file --fingerprint r-title --title "star: SPH-13 stalls" --label bug --body-file "$TMP/body.md"); [ $? -eq 65 ] && pass "the title is checked too" || fail "title ($out)"
[ "$(wc -l < "$TMP/calls")" -eq "$n" ] && pass "nothing refused reached gh" || fail "a refused body was posted"
body "it is fine: the IT item and the sph word in lower case"
out=$(I file --fingerprint prefix-case-ok --title "star: prefix case" --label bug --body-file "$TMP/body.md")
case "$out" in "filed "*) pass "a ref prefix only counts as written (upper case)" ;; *) fail "prefix false refusal ($out)" ;; esac
# Review Focus 3: the placeholders themselves pass
body "<app> showed <project>'s ITEM-2 in <repo>; ~/notes is fine"
out=$(I file --fingerprint placeholders-ok --title "star: placeholders" --label bug --body-file "$TMP/body.md")
case "$out" in "filed "*) pass "placeholders are not project details" ;; *) fail "placeholders ($out)" ;; esac

# gh failing
touch "$TMP/gh-fail"; body "fine"
case "$(I file --fingerprint gh-down --title "star: y" --label bug --body-file "$TMP/body.md")" in "failed HTTP 403"*) pass "a gh failure is one failed line" ;; *) fail "gh failure" ;; esac
rm -f "$TMP/gh-fail"

# usage
I file --fingerprint Bad_FP --title "star: z" --label bug --body-file "$TMP/body.md" >/dev/null 2>&1; [ $? -eq 64 ] && pass "a bad fingerprint is 64" || fail "fingerprint usage"
I file --fingerprint ok-fp --title "star: z" --label question --body-file "$TMP/body.md" >/dev/null 2>&1; [ $? -eq 64 ] && pass "a label other than bug or enhancement is 64" || fail "label usage"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
