#!/bin/sh
# Runs skills/ship-ticket/executor-check.sh against fake plugin roots and a fake CODEX_HOME (#164).
# Usage: sh tests/ship-ticket/executor-check.test.sh   (exit 0 = all cases pass)
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/ship-ticket/executor-check.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL executor-check.sh missing"; exit 1; }

# mkroot <name> <version|-> <skill text>: a fake plugin root; version "-" writes no plugin.json
mkroot() {
  d="$TMP/$1"; mkdir -p "$d/assets/codex-skills/claude-plan-executor"
  printf '%s\n' "$3" > "$d/assets/codex-skills/claude-plan-executor/SKILL.md"
  if [ "$2" != "-" ]; then mkdir -p "$d/.claude-plugin"; printf '{"version": "%s"}\n' "$2" > "$d/.claude-plugin/plugin.json"; fi
}
# link <root name>: point CODEX_HOME's skill link at that root's executor folder
link() {
  mkdir -p "$TMP/codex/skills"; rm -f "$TMP/codex/skills/claude-plan-executor"
  ln -s "$TMP/$1/assets/codex-skills/claude-plan-executor" "$TMP/codex/skills/claude-plan-executor"
}
run() { CODEX_HOME="$TMP/codex" sh "$SCRIPT" "$TMP/$1"; }
expect() { # expect <label> <want> <root name>
  got=$(run "$3"); if [ "$got" = "$2" ]; then pass "$1"; else fail "$1 (got '$got', want '$2')"; fi
}

mkroot run1 2.11.1 "running copy"
link run1;  expect "link into the running root is ok" "ok" run1
mkroot new 2.12.0 "newer copy"
link new;   expect "link into a newer root is ok" "ok" run1
mkroot old 2.10.0 "older copy"
link old;   expect "link into an older root is older" "older 2.10.0 2.11.1" run1
mkroot old9 2.9.0 "older nine"
link old9;  expect "versions compare as integers (2.9.0 < 2.11.1)" "older 2.9.0 2.11.1" run1
mkroot r9 2.11.9 "running nine"
mkroot n10 2.11.10 "newer ten"
link n10;   expect "2.11.10 is newer than 2.11.9" "ok" r9
mkroot nover - "no manifest copy"
link nover; expect "different copy with no plugin.json is different" "different" run1
rm -f "$TMP/codex/skills/claude-plan-executor"
expect "no link is missing" "missing" run1
ln -s "$TMP/nowhere" "$TMP/codex/skills/claude-plan-executor"
expect "broken link is missing" "missing" run1

# CODEX_HOME unset falls back to $HOME/.codex
mkdir -p "$TMP/home/.codex/skills"
ln -s "$TMP/run1/assets/codex-skills/claude-plan-executor" "$TMP/home/.codex/skills/claude-plan-executor"
got=$(env -u CODEX_HOME HOME="$TMP/home" sh "$SCRIPT" "$TMP/run1")
[ "$got" = "ok" ] && pass "CODEX_HOME unset uses HOME/.codex" || fail "CODEX_HOME unset (got '$got')"

sh "$SCRIPT" >/dev/null 2>&1; [ $? -eq 64 ] && pass "no argument exits 64" || fail "no argument exit"
sh "$SCRIPT" a b >/dev/null 2>&1; [ $? -eq 64 ] && pass "two arguments exit 64" || fail "two arguments exit"
sh "$SCRIPT" "$TMP/nowhere" >/dev/null 2>&1; [ $? -eq 64 ] && pass "root without the skill exits 64" || fail "bad root exit"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
