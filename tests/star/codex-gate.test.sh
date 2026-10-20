#!/bin/sh
# Runs skills/star/codex-gate.sh in a scratch repo against stub codex and gh binaries.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/codex-gate.sh"
PROOF="$ROOT/skills/babysit-pr/review-proof.sh"
FIX="$ROOT/tests/star/fixtures/codex-review"
MODELS="$ROOT/tests/ship-ticket/fixtures/codex-models-2026-10.json"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL codex-gate.sh missing"; exit 1; }

APP="$TMP/app"; mkdir -p "$APP" "$TMP/fix"
(cd "$APP" && git init -q -b main . && printf 'a\n' > f && git add f && git -c user.email=t@t -c user.name=t commit -qm init && git checkout -qb feat/item-1 && printf 'b\n' > f && git -c user.email=t@t -c user.name=t commit -qam change)
H="$TMP/home"; mkdir -p "$H/memory" "$H/gates/app"
printf '{"project": {"name": "app"}, "gate": {"model": "latest-sol", "effort": "xhigh", "fallback": {"agent": "claude", "model": "opus", "effort": "xhigh"}}}\n' > "$H/star.json"
BRIEF="$H/briefs/app/ITEM-1.md"; mkdir -p "$(dirname "$BRIEF")"
cat > "$BRIEF" <<EOF
---
juel_brief: 1
item:
  name: ITEM-1
branch: feat/item-1
baseBranch: main
star:
  home: $H
  project: app
  notes: [$H/memory/app.md]
  reviews: $H/reviews/app
  gates: $H/gates/app/ITEM-1.json
  reports: $H/reports/app
---
## Acceptance criteria
- [ ] add() returns the sum
EOF

mkdir -p "$TMP/bin"
cat > "$TMP/bin/codex" <<'EOF'
#!/bin/sh
if [ "$1 $2" = "debug models" ]; then cat "$STUB_MODELS"; exit 0; fi
n=$(cat "$STUB_DIR/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_DIR/n"
printf '%s\n' "$*" >> "$STUB_DIR/calls"
line=$(sed -n "${n}p" "$STUB_DIR/plan")
rc=${line%% *}; rest=${line#* }; fixture=${rest%% *}; err=${rest#"$fixture"}
if [ "$fixture" = move-head ]; then git -c user.email=t@t -c user.name=t commit -q --allow-empty -m moved; fixture=safe; fi
if [ "$fixture" = peek ]; then cp "$STUB_RUN" "$STUB_DIR/run-seen" 2>/dev/null; echo $$ > "$STUB_DIR/stub-pid"; fixture=safe; fi
if [ "$fixture" = sleep ]; then echo $$ > "$STUB_DIR/stub-pid"; printf 'reviewing\n' >&2; sleep 30; fixture=safe; fi
[ "$fixture" != "-" ] && cat "$STUB_FIX/$fixture.txt"
[ -n "$err" ] && printf '%s\n' "$err" >&2
exit "$rc"
EOF
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/gh-calls"
printf '%s %s %s\n' "${GH_TOKEN:-none}" "$1" "$2" >> "$STUB_DIR/tokens"
[ -f "$STUB_DIR/gh-fail" ] && { echo "HTTP 502" >&2; exit 1; }
case "$1 $2" in
  "pr view") n=$(($(cat "$STUB_DIR/pr-n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$STUB_DIR/pr-n"
             if [ -f "$STUB_DIR/pr-$n.json" ]; then cat "$STUB_DIR/pr-$n.json"; else cat "$STUB_DIR/pr.json"; fi ;;
  "pr comment") shift 2; while [ $# -gt 0 ]; do [ "$1" = --body ] && printf '%s' "$2" > "$STUB_DIR/body"; shift; done
                echo "https://github.com/o/r/pull/5#issuecomment-1" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$TMP/bin/codex" "$TMP/bin/gh"
cat > "$TMP/bin/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/claude-calls"
# the plan's line n serves the n-th call since reset; past its end, its last line serves again
n=$(($(cat "$STUB_DIR/claude-n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$STUB_DIR/claude-n"
line=$(sed -n "${n}p" "$STUB_DIR/claude-plan" 2>/dev/null)
[ -n "$line" ] || line=$(sed -n '$p' "$STUB_DIR/claude-plan" 2>/dev/null)
[ -n "$line" ] || { echo "no claude plan" >&2; exit 9; }
rc=${line%% *}; rest=${line#* }; fixture=${rest%% *}; err=${rest#"$fixture"}
# claude -p --output-format json prints one JSON object; a <name>.txt fixture is wrapped as a clean result,
# <name>.json is printed as written, and raw-<name> prints <name>.txt unwrapped (prose, though JSON was asked for)
case "$fixture" in
  -) ;;
  *.json) cat "$STUB_FIX/$fixture" ;;
  raw-*) cat "$STUB_FIX/${fixture#raw-}.txt" ;;
  *) case "$*" in
       *"--output-format json"*) python3 -c 'import json, sys; print(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": sys.stdin.read(), "permission_denials": []}))' < "$STUB_FIX/$fixture.txt" ;;
       *) cat "$STUB_FIX/$fixture.txt" ;;
     esac ;;
esac
[ -n "$err" ] && printf '%s\n' "$err" >&2
exit "$rc"
EOF
chmod +x "$TMP/bin/claude"
reset() { rm -f "$TMP/n" "$TMP/calls" "$TMP/tokens" "$TMP/gh-calls" "$TMP/gh-fail" "$TMP/plan" "$TMP/claude-calls" "$TMP/claude-plan" "$TMP/claude-n" "$TMP/run-seen" "$TMP/stub-pid" "$TMP/pr-n" "$TMP/pr-1.json" "$TMP/pr-2.json" "$TMP/body"; rm -rf "$H/reviews" "$H/specs"; }
plan() { printf '%s\n' "$@" > "$TMP/plan"; }
cplan() { printf '%s\n' "$@" > "$TMP/claude-plan"; }
G() { (cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_FIX="$FIX" STUB_MODELS="$MODELS" CODEX_GATE_SLEEP=0 sh "$SCRIPT" "$@"); }
# GF reads the fixtures a test writes into $TMP/fix instead of the shared ones
GF() { (cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_FIX="$TMP/fix" STUB_MODELS="$MODELS" CODEX_GATE_SLEEP=0 sh "$SCRIPT" "$@"); }
HEAD=$(git -C "$APP" rev-parse HEAD)
APPREAL=$(cd "$APP" && pwd -P)
R1="$H/reviews/app/ITEM-1-r1.md"

# SAFE, with the files in STAR's home and the flags the owner chose
reset; plan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && pass "a clean review is SAFE" || fail "safe ($rc $out)"
[ "$(head -n 1 "$R1")" = "VERDICT item=ITEM-1 round=1 SAFE findings=0 head=$HEAD" ] && pass "the review's first line is the v1 verdict line" || fail "verdict line ($(head -n 1 "$R1"))"
[ "$(sh "$PROOF" "$R1" --item ITEM-1 --head "$HEAD")" = "OK round=1" ] && pass "review-proof.sh accepts it" || fail "review-proof"
[ -s "$H/reviews/app/ITEM-1-r1.raw.md" ] && [ -f "$H/reviews/app/ITEM-1-r1.log" ] && [ -z "$(git -C "$APP" status --porcelain)" ] && pass "raw and log land in STAR's home, nothing in the worktree (#35)" || fail "file places"
grep -q 'review You are STAR' "$TMP/calls" && grep -q -- '--strict-config' "$TMP/calls" && grep -q 'model="gpt-6.1-sol"' "$TMP/calls" && grep -q 'model_reasoning_effort="xhigh"' "$TMP/calls" && grep -q 'sandbox_mode="read-only"' "$TMP/calls" && grep -q 'mcp_servers={}' "$TMP/calls" && pass "codex review runs read-only, with no MCP servers, on the gate settings" || fail "codex flags ($(cat "$TMP/calls"))"
P1="$H/specs/app/ITEM-1-gate-r1.md"
grep -qF "git diff $(git -C "$APP" rev-parse main)...HEAD" "$P1" && grep -q "$BRIEF" "$P1" && grep -q 'This is round 1' "$P1" && grep -q 'No check is pending at the screen.' "$P1" && pass "the prompt is filled in and kept" || fail "prompt ($(cat "$P1"))"

# NOT-SAFE on a P1; round 2 names the previous review; pending screen checks are listed (#43)
reset; plan "0 p1"; printf '1. sign in to the app as the test account\n' > "$H/gates/app/ITEM-1-screen.md"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 2 --base main); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "NOT-SAFE round=2 findings=1 p0=0 p1=1 head=$HEAD review=$H/reviews/app/ITEM-1-r2.md" ] && pass "a P1 is NOT-SAFE" || fail "p1 ($rc $out)"
grep -q '^1\. \[P1\] Return the sum instead of the difference — /repo/calc.py:2-2$' "$H/reviews/app/ITEM-1-r2.md" && pass "the finding is numbered with its place" || fail "finding line"
P2="$H/specs/app/ITEM-1-gate-r2.md"
grep -q "ITEM-1-r1.md" "$P2" && grep -q "ITEM-1-r1-fix.md" "$P2" && pass "round 2 names the previous review and its dispositions" || fail "previous round"
grep -q 'sign in to the app as the test account' "$P2" && grep -q 'never a finding here' "$P2" && pass "a check pending at the screen is named as pending (#43)" || fail "pending checks"
rm -f "$H/gates/app/ITEM-1-screen.md"

# P2 and P3 only is SAFE
reset; plan "0 p2-p3"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
[ "$out" = "SAFE round=1 findings=2 head=$HEAD review=$R1" ] && pass "P2 and P3 findings do not block" || fail "p2-p3 ($out)"

# model and effort: the flags, else star.json's gate block (the star.json above holds the defaults, so change it)
cp "$H/star.json" "$TMP/star.json.orig"
printf '{"gate": {"model": "gpt-6-sol", "effort": "high"}}\n' > "$H/star.json"
reset; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main >/dev/null
grep -q 'model="gpt-6-sol"' "$TMP/calls" && grep -q 'model_reasoning_effort="high"' "$TMP/calls" && pass "star.json's gate block sets the model and effort" || fail "star.json gate ($(cat "$TMP/calls"))"
reset; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main --model gpt-6-luna --effort low >/dev/null
grep -q 'model="gpt-6-luna"' "$TMP/calls" && grep -q 'model_reasoning_effort="low"' "$TMP/calls" && pass "--model and --effort win over star.json" || fail "gate flags ($(cat "$TMP/calls"))"
cp "$TMP/star.json.orig" "$H/star.json"

# a bullet in the overall text of a clean review is not a finding
reset; mkdir -p "$TMP/fix"; cp "$FIX"/*.txt "$TMP/fix/"
printf 'The change is fine.\n- the export works\n- the filter works\n' > "$TMP/fix/notes.txt"; plan "0 notes"
out=$( (cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_FIX="$TMP/fix" STUB_MODELS="$MODELS" CODEX_GATE_SLEEP=0 sh "$SCRIPT" --brief "$BRIEF" --item ITEM-1 --round 1 --base main) )
[ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && pass "bullets in a clean review's notes are not findings" || fail "notes bullets ($out)"

# Review Focus 2: findings without tags are an error, never SAFE
reset; plan "0 untagged"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR unreadable review: findings without [P0]-[P3] tags" ] && pass "untagged findings are ERROR" || fail "untagged ($rc $out)"
reset; plan "0 untagged-noheader"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR unreadable review: findings without [P0]-[P3] tags" ] && pass "an untagged finding with no header is ERROR too" || fail "untagged, no header ($rc $out)"
reset; mkdir -p "$TMP/fix"; printf 'The change has a problem.\n\nReview comment:\n\nadd() now subtracts.\n' > "$TMP/fix/header-only.txt"; plan "0 header-only"
out=$( (cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_FIX="$TMP/fix" STUB_MODELS="$MODELS" CODEX_GATE_SLEEP=0 sh "$SCRIPT" --brief "$BRIEF" --item ITEM-1 --round 1 --base main) ); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR unreadable review: findings without [P0]-[P3] tags" ] && pass "a findings header with no tagged finding under it is ERROR" || fail "header only ($rc $out)"

# A-1: a finding in another bullet shape is still a finding, and a tag the gate cannot read is never SAFE
for shape in p1-star p1-numbered p1-bold; do
  reset; plan "0 $shape"
  out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "NOT-SAFE round=1 findings=1 p0=0 p1=1 head=$HEAD review=$R1" ] && grep -q '^1\. \[P1\] Return the sum instead of the difference — /repo/calc.py:2-2$' "$R1" && pass "a [P1] in the $shape bullet shape is NOT-SAFE, never SAFE" || fail "$shape ($rc $out)"
done
for shape in untagged-hyphen untagged-paren untagged-star; do
  reset; plan "0 $shape"
  out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
  [ "$rc" -eq 69 ] && [ "$out" = "ERROR unreadable review: findings without [P0]-[P3] tags" ] && pass "an untagged finding in the $shape shape is ERROR, never SAFE" || fail "$shape ($rc $out)"
done
while IFS='|' read -r label body; do
  reset; printf 'The change has a problem.\n\n%s\n' "$body" > "$TMP/fix/var.txt"; plan "0 var"
  out=$(GF --brief "$BRIEF" --item ITEM-1 --round 1 --base main < /dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "NOT-SAFE round=1 findings=1 p0=0 p1=1 head=$HEAD review=$R1" ] && pass "a [P1] is NOT-SAFE with $label" || fail "tagged variant ($label): $rc $out"
done <<'EOF'
a plus bullet|+ [P1] Return the sum instead of the difference — /repo/calc.py:2-2
a numbered bullet closed by a parenthesis|1) [P1] Return the sum instead of the difference — /repo/calc.py:2-2
an indented bullet|  - [P1] Return the sum instead of the difference — /repo/calc.py:2-2
EOF
while IFS='|' read -r label body; do
  reset; printf 'The change has a problem.\n\n%s\n' "$body" > "$TMP/fix/var.txt"; plan "0 var"
  out=$(GF --brief "$BRIEF" --item ITEM-1 --round 1 --base main < /dev/null); rc=$?
  [ "$rc" -eq 69 ] && [ "$out" = "ERROR unreadable review: findings without [P0]-[P3] tags" ] && pass "an untagged finding is ERROR with $label" || fail "untagged variant ($label): $rc $out"
done <<'EOF'
an en dash before the place|- Return the sum from add() – /repo/calc.py:2
a numbered bullet|1. Return the sum from add() — /repo/calc.py:2-2
a plus bullet|+ Return the sum from add() - /repo/calc.py:2
a line range in parentheses|- Return the sum from add() (/repo/calc.py:2-4)
EOF
while IFS='|' read -r label body; do
  reset; printf 'The change has a problem.\n\n%b\n' "$body" > "$TMP/fix/odd.txt"; plan "0 odd"
  out=$(GF --brief "$BRIEF" --item ITEM-1 --round 1 --base main < /dev/null); rc=$?
  [ "$rc" -eq 69 ] && [ "$out" = "ERROR unreadable review: a finding in a shape the gate cannot read" ] && [ ! -f "$R1" ] && pass "a tag the gate cannot read is ERROR ($label)" || fail "unreadable tag ($label): $rc $out"
done <<'EOF'
no bullet|[P1] Return the sum instead of the difference — /repo/calc.py:2-2
a colon after the tag|- [P1]: Return the sum instead of the difference — /repo/calc.py:2-2
a bold tag with no bullet|**[P1]** Return the sum instead of the difference — /repo/calc.py:2-2
a tag with no title|- [P3]
a P0 with a colon after the tag|- [P0]: Delete the table — /repo/db.py:9
the tag inside the title|- Return the sum [P2] — /repo/calc.py:2
a readable P1 beside one that cannot be read|- [P1] Return the sum — /repo/calc.py:2\n- [P2]: Rename it — /repo/calc.py:9
EOF

# A-4: a failure that codex prints on stdout while it exits 0 is not a review
for fx in error-line error-lower warning-line; do
  reset; plan "0 $fx"
  out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
  [ "$rc" -eq 69 ] && [ "$out" = "ERROR codex review failed: $(grep -m 1 . "$FIX/$fx.txt")" ] && [ "$(cat "$TMP/n")" = 1 ] && [ ! -f "$R1" ] && pass "exit 0 with $fx as the first line is ERROR, not SAFE, and not retried" || fail "$fx ($rc $out)"
done
reset; printf 'The change is fine.\nError handling in the export is covered by a test.\n' > "$TMP/fix/error-later.txt"; plan "0 error-later"
out=$(GF --brief "$BRIEF" --item ITEM-1 --round 1 --base main < /dev/null); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && pass "the word error on a later line is only text" || fail "error later ($rc $out)"

# an empty review is an error at once
reset; plan "0 -"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR empty review" ] && [ "$(cat "$TMP/n")" = 1 ] && pass "an empty review is ERROR, not retried" || fail "empty ($rc $out)"

# capacity: two retries on Sol, then the Claude fallback (#41, #64)
reset; plan "1 - Selected model is at capacity. Please try a different model." "1 - Selected model is at capacity." "1 - stream error: 503 Service Unavailable"; cplan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
[ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && [ "$(cat "$TMP/n")" = 3 ] && [ "$(grep -c 'model="gpt-6.1-sol"' "$TMP/calls")" = 3 ] && pass "capacity is retried twice on Sol, then Claude reviews" || fail "capacity ($out, $(cat "$TMP/n") calls)"
c=$(cat "$TMP/claude-calls")
case "$c" in "-p You are STAR"*) true ;; *) false ;; esac \
  && printf '%s' "$c" | grep -qF -- '--model opus --effort xhigh' \
  && printf '%s' "$c" | grep -qF -- '--append-system-prompt Write the review as plain text' \
  && printf '%s' "$c" | grep -qF -- "--add-dir $H " \
  && printf '%s' "$c" | grep -qF -- '--allowedTools Read Grep Glob Bash(git diff *) Bash(git show *) Bash(git log *) Bash(git -C '"$APPREAL"' diff) Bash(git -C '"$APPREAL"' diff *) Bash(git -C '"$APPREAL"' show) Bash(git -C '"$APPREAL"' show *) Bash(git -C '"$APPREAL"' log) Bash(git -C '"$APPREAL"' log *)' \
  && printf '%s' "$c" | grep -qF -- '--disallowedTools Edit Write NotebookEdit Bash(git * --output*)' \
  && printf '%s' "$c" | grep -qF -- '--output-format json --strict-mcp-config --no-session-persistence' \
  && pass "the fallback runs claude -p read-only, with STAR's home, no MCP server and no saved session" || fail "claude flags ($c)"
# N1: a -C rule holds the worktree's own path, never a "*": a "*" would match a whole subcommand (git -C x branch diff)
allowed=$(printf '%s' "$c" | sed -e 's/.*--allowedTools //' -e 's/ --disallowedTools.*//')
case "$allowed" in *"git -C *"*) false ;; *"git -C $APPREAL diff)"*) true ;; *) false ;; esac \
  && printf '%s' "$allowed" | grep -qE 'git -C [^* ]+ (diff|show|log)' \
  && ! printf '%s' "$allowed" | grep -qE 'git (-C|-c) \*|git \*' \
  && pass "the -C allow rules hold the worktree path, with no git -C * rule that could match another subcommand" || fail "-C rules ($allowed)"
grep -q '^Gate: claude:opus xhigh (fallback: sol at capacity) · base main' "$R1" && pass "the review names the fallback and why it ran" || fail "fallback gate line ($(grep '^Gate:' "$R1"))"
reset; plan "1 - You've hit your usage limit. Try again at Oct 18th, 2026 6:00 PM."; cplan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
[ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && [ "$(cat "$TMP/n")" = 1 ] && grep -q '^Gate: claude:opus xhigh (fallback: sol usage limit)' "$R1" && pass "a usage limit goes to Claude at once, with no retry (#64)" || fail "usage limit ($out, $(cat "$TMP/n") calls)"
reset; plan "1 - You've hit your usage limit."; cplan "0 p1"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
[ "$out" = "NOT-SAFE round=1 findings=1 p0=0 p1=1 head=$HEAD review=$R1" ] && pass "the fallback's review is read by the same rules: a P1 is NOT-SAFE" || fail "fallback p1 ($out)"
reset; plan "1 - You've hit your usage limit."; cplan "1 - API Error: 529 Overloaded"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR gate-down sol usage limit: You've hit your usage limit.; claude: API Error: 529 Overloaded" ] && [ ! -f "$R1" ] && pass "Sol and Claude both down is ERROR gate-down" || fail "gate-down ($rc $out)"
reset; plan "1 - at capacity" "1 - at capacity" "1 - at capacity"; cplan "0 -"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR gate-down sol at capacity: at capacity; claude: empty review" ] && pass "an empty fallback review is gate-down" || fail "empty fallback ($rc $out)"
reset; plan "1 - at capacity" "1 - at capacity" "1 - at capacity"; mkdir -p "$TMP/fix"; printf 'API Error: 500 Internal server error\n' > "$TMP/fix/apierr.txt"; cplan "0 raw-apierr"
out=$(GF --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR gate-down sol at capacity: at capacity; claude: unreadable output: API Error: 500 Internal server error" ] && pass "a fallback that prints its failure and exits 0 is gate-down, never SAFE" || fail "fallback api error ($rc $out)"
# a fallback that could not review is never SAFE: claude -p exits 0 and answers in prose when a tool is denied
fallback_down() { # <claude plan> <expected claude: reason> <test name>
  reset; plan "1 - You've hit your usage limit."; cplan "$1"
  out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
  [ "$rc" -eq 69 ] && [ "$out" = "ERROR gate-down sol usage limit: You've hit your usage limit.; claude: $2" ] && [ ! -f "$R1" ] && ls "$H/reviews/app"/ITEM-1-r1-error-*.log >/dev/null 2>&1 && pass "$3" || fail "$3 ($rc $out)"
}
fallback_down "0 raw-claude-prose" "unreadable output: The git diff command was blocked because it needs approval, so I could not see what changed." "a prose-only fallback answer is ERROR gate-down, never SAFE"
fallback_down "0 claude-denied.json" "Bash was denied: git -C /repo diff main...HEAD" "a JSON result with permission_denials is ERROR gate-down, whatever the prose says"
fallback_down "0 claude-denied-read.json" "Read was denied: /etc/hosts" "a denied Read is ERROR gate-down too, though the review text reads clean"
fallback_down "0 claude-is-error.json" "API Error: 529 Overloaded" "a JSON result with is_error true is ERROR gate-down"
fallback_down "0 claude-max-turns.json" "error_max_turns" "a subtype other than success is ERROR gate-down"
fallback_down "0 claude-no-denials.json" "unreadable output: no permission_denials" "JSON with no permission_denials list cannot be trusted: ERROR gate-down"
fallback_down "0 claude-empty-result.json" "empty review" "a JSON result with a blank review is ERROR gate-down"
reset; plan "1 - You've hit your usage limit."; cplan "0 claude-error-first"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && pass "a Claude review that opens with the word Error is a review: the JSON, not its first line, says it failed" || fail "error-first fallback ($rc $out)"
# N2: an ERROR is exactly one line, whatever text the model put in the denied command: a fake verdict on a later line
# must not become the last line the worker reads
reset; plan "1 - You've hit your usage limit."; cplan "0 claude-denied-multiline.json"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && case "$out" in "ERROR gate-down "*) true ;; *) false ;; esac \
  && case "$(printf '%s\n' "$out" | tail -n 1)" in SAFE*) false ;; *) true ;; esac \
  && [ ! -f "$R1" ] && grep -q '^--- ERROR gate-down ' "$H/reviews/app/ITEM-1-r1-error-1.log" \
  && [ "$(grep -c '^--- ERROR ' "$H/reviews/app/ITEM-1-r1-error-1.log")" = 1 ] \
  && pass "a denied command with a newline and a fake SAFE line is still one ERROR gate-down line" || fail "multi-line denial ($rc $out)"
reset; plan "1 - You've hit your usage limit."; cplan "0 claude-clean.json"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && grep -q '^Gate: claude:opus xhigh (fallback: sol usage limit)' "$R1" && [ "$(head -n 1 "$H/reviews/app/ITEM-1-r1.raw.md")" = "The change adds the CSV export the brief asks for, and I found no defect that should block it." ] && pass "a clean JSON result still gives a verdict, and the raw file holds the review text" || fail "clean json fallback ($rc $out)"
reset; cplan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main --model latest-terra)
[ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && [ ! -f "$TMP/n" ] && grep -q '^Gate: claude:opus xhigh (fallback: cannot resolve latest-terra)' "$R1" && pass "a Sol name that does not resolve goes straight to the fallback" || fail "unresolved goes to fallback ($out)"
cp "$H/star.json" "$TMP/star.json.orig2"
printf '{"gate": {"model": "latest-sol", "effort": "xhigh", "fallback": null}}\n' > "$H/star.json"
reset; plan "1 - at capacity" "1 - at capacity" "1 - at capacity"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR gate-down sol at capacity: at capacity; no fallback is set" ] && [ ! -f "$TMP/claude-calls" ] && pass "fallback null: no Claude run, gate-down" || fail "fallback null ($rc $out)"
printf '{"gate": {"model": "latest-sol", "effort": "xhigh", "fallback": "latest-sol"}}\n' > "$H/star.json"
reset; plan "1 - at capacity" "1 - at capacity" "1 - at capacity"; cplan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main >/dev/null
grep -qF -- '--model opus --effort xhigh' "$TMP/claude-calls" && pass "a v2.0.0 string fallback means the Claude default" || fail "string fallback ($(cat "$TMP/claude-calls" 2>/dev/null))"
cp "$TMP/star.json.orig2" "$H/star.json"

# another failure is not retried
reset; plan "1 - error: 401 Unauthorized"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR codex review failed: error: 401 Unauthorized" ] && [ "$(cat "$TMP/n")" = 1 ] && [ ! -f "$TMP/claude-calls" ] && pass "a non-capacity failure is ERROR at once, with no fallback" || fail "auth ($rc $out)"

# HEAD moving during the review is an error, never a verdict
reset; plan "0 move-head"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
case "$out" in "ERROR HEAD moved during the review"*) [ "$rc" -eq 69 ] && pass "a moved HEAD is ERROR" || fail "moved head rc" ;; *) fail "moved head ($out)" ;; esac
git -C "$APP" reset -q --hard "$HEAD"

# post-pass: once per head, by the PR's author
NEWHEAD=$(git -C "$APP" rev-parse HEAD)
reset
printf '{"author":{"login":"me"},"headRefOid":"%s","url":"https://github.com/o/r/pull/5","comments":[]}\n' "$NEWHEAD" > "$TMP/pr.json"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && grep -q "pr comment https://github.com/o/r/pull/5 --body Codex gate: PASS (head $NEWHEAD, round 2, gpt-6.1-sol xhigh)" "$TMP/gh-calls" && pass "post-pass posts the PASS" || fail "post-pass ($out / $(cat "$TMP/gh-calls"))"
[ "$(cat "$TMP/body" 2>/dev/null)" = "$(printf 'Codex gate: PASS (head %s, round 2, gpt-6.1-sol xhigh)\nVERDICT: PASS' "$NEWHEAD")" ] && pass "the receipt's second line is VERDICT: PASS, the line a project's review rule reads (#84)" || fail "receipt lines ($(cat "$TMP/body" 2>/dev/null))"
# #137: post-pass uses the token configured for STAR's account when GH_TOKEN is unset
TOKEN_HOME="$TMP/token-home"; mkdir -p "$TOKEN_HOME"
printf '{"tokenCmd":"echo tok_star", "gate":{"model":"latest-sol","effort":"xhigh","fallback":{"agent":"claude","model":"opus","effort":"xhigh"}}}\n' > "$TOKEN_HOME/star.json"
reset
printf '{"author":{"login":"me"},"headRefOid":"%s","url":"https://github.com/o/r/pull/5","comments":[]}\n' "$NEWHEAD" > "$TMP/pr.json"
out=$(cd "$APP" && env -u GH_TOKEN PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_MODELS="$MODELS" JUEL_STAR_HOME="$TOKEN_HOME" CODEX_GATE_SLEEP=0 sh "$SCRIPT" post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && [ -s "$TMP/tokens" ] && ! grep -v '^tok_star ' "$TMP/tokens" >/dev/null && pass "#137 codex-gate post-pass uses the configured token" || fail "#137 codex-gate token ($out / $(cat "$TMP/tokens" 2>/dev/null))"
reset
printf '{"author":{"login":"me"},"headRefOid":"%s","url":"u","comments":[{"author":{"login":"me"},"body":"Codex gate: PASS (head %s, round 1, gpt-6.1-sol xhigh)","url":"https://github.com/o/r/pull/5#issuecomment-9"}]}\n' "$NEWHEAD" "$NEWHEAD" > "$TMP/pr.json"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD")
[ "$out" = "already https://github.com/o/r/pull/5#issuecomment-9" ] && ! grep -q 'pr comment' "$TMP/gh-calls" && pass "a PASS already there is not posted twice" || fail "already ($out)"
reset
printf '{"author":{"login":"me"},"headRefOid":"%s","url":"u","comments":[{"author":{"login":"someone-else"},"body":"Codex gate: PASS (head %s, round 1, gpt-6.1-sol xhigh)","url":"https://github.com/o/r/pull/5#issuecomment-8"}]}\n' "$NEWHEAD" "$NEWHEAD" > "$TMP/pr.json"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && pass "a PASS comment from someone other than the PR's author does not count" || fail "other author ($out)"
reset; printf '{"author":{"login":"me"},"headRefOid":"0000000000000000000000000000000000000000","url":"u","comments":[]}\n' > "$TMP/pr.json"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD"); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR the PR's head is 0000000, not $(printf '%.7s' "$NEWHEAD"), after 90 s" ] && [ "$(cat "$TMP/pr-n")" = 19 ] && pass "post-pass refuses another head after waiting 90 s" || fail "post-pass head ($rc $out)"
reset; touch "$TMP/gh-fail"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD"); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR gh: HTTP 502" ] && pass "a gh failure is ERROR" || fail "gh failure ($rc $out)"
reset; mkdir -p "$H/reviews/app"; RV="$H/reviews/app/ITEM-1-r2.md"
printf 'VERDICT item=ITEM-1 round=2 SAFE findings=0 head=%s\n\n## Findings\nnone\n\n## Notes\n-\n\nGate: gpt-6.1-sol xhigh · base main · raw r · log l\n' "$NEWHEAD" > "$RV"
printf '{"author":{"login":"me"},"headRefOid":"%s","url":"https://github.com/o/r/pull/5","comments":[]}\n' "$NEWHEAD" > "$TMP/pr.json"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD" --review "$RV")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && grep -q "PASS (head $NEWHEAD, round 2, gpt-6.1-sol xhigh)" "$TMP/gh-calls" && pass "post-pass names the model the review ran on, a fallback included" || fail "post-pass --review ($out / $(cat "$TMP/gh-calls"))"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD" --review "$TMP/no-such-review.md"); rc=$?
[ "$rc" -eq 69 ] && case "$out" in "ERROR cannot read the review: "*) true ;; *) false ;; esac && pass "post-pass refuses a review it cannot read" || fail "unreadable review ($rc $out)"
rm -f "$TMP/gh-calls"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD" --review "$RV" --model gpt-6-luna --effort low)
grep -q "PASS (head $NEWHEAD, round 2, gpt-6-luna low)" "$TMP/gh-calls" && pass "post-pass: --model and --effort win over the review file" || fail "post-pass flags ($out / $(cat "$TMP/gh-calls"))"
# A-2: with --review, post-pass posts only a SAFE verdict of this round and this head, with no newer round beside it
review_file() { # review_file <path> <first line>
  printf '%s\n\n## Findings\nnone\n\n## Notes\n-\n\nGate: gpt-6.1-sol xhigh · base main · raw r · log l\n' "$2" > "$1"
}
refused() { # refused <label> <review file> <the start of the ERROR line>
  rm -f "$TMP/gh-calls"
  out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD" --review "$2"); rc=$?
  case "$out" in "$3"*) [ "$rc" -eq 69 ] && ! grep -q 'pr comment' "$TMP/gh-calls" 2>/dev/null && pass "post-pass refuses $1 and posts nothing" || fail "$1 (rc=$rc, $out, calls: $(cat "$TMP/gh-calls" 2>/dev/null))" ;; *) fail "$1 ($rc $out)" ;; esac
}
RV2="$H/reviews/app/ITEM-1-r2.md"; S7=$(printf '%.7s' "$NEWHEAD")
review_file "$RV2" "VERDICT item=ITEM-1 round=2 NOT-SAFE findings=1 head=$NEWHEAD"
refused "a NOT-SAFE review" "$RV2" "ERROR the review says NOT-SAFE, not SAFE"
review_file "$RV2" "VERDICT item=ITEM-1 round=2 SAFE findings=0 head=0000000000000000000000000000000000000000"
refused "a SAFE review of another head" "$RV2" "ERROR the review is of 0000000, not $S7"
review_file "$RV2" "VERDICT item=ITEM-1 round=1 SAFE findings=0 head=$NEWHEAD"
refused "a SAFE review of another round" "$RV2" "ERROR the review is of round 1, not round 2"
review_file "$RV2" "Looks good to me."
refused "a file with no VERDICT line" "$RV2" "ERROR the review's first line is not a full VERDICT line"
: > "$RV2"
refused "an empty file" "$RV2" "ERROR the review's first line is not a full VERDICT line"
review_file "$RV2" "VERDICT item=ITEM-1 round=2 SAFE findings=0 head=$(printf '%.6s' "$NEWHEAD")"
refused "a head of fewer than 7 characters" "$RV2" "ERROR the review's first line is not a full VERDICT line"
review_file "$RV2" "VERDICT item=ITEM-1 round=2 SAFE findings=0 head=$NEWHEAD and then some"
refused "a VERDICT line with words after it" "$RV2" "ERROR the review's first line is not a full VERDICT line"
review_file "$RV2" "VERDICT item=ITEM-1 round=2 SAFE findings=0 head=$NEWHEAD"; : > "$H/reviews/app/ITEM-1-r3.md"
refused "a review with a newer round beside it" "$RV2" "ERROR round 3 has its own review at $H/reviews/app/ITEM-1-r3.md"
rm -f "$H/reviews/app/ITEM-1-r3.md"; : > "$H/reviews/app/OTHER-1-r3.md"
rm -f "$TMP/gh-calls"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD" --review "$RV2")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && grep -q "PASS (head $NEWHEAD, round 2, gpt-6.1-sol xhigh)" "$TMP/gh-calls" && pass "post-pass posts a SAFE review of this round and head; another item's newer round does not matter" || fail "valid review ($out / $(cat "$TMP/gh-calls"))"
review_file "$RV2" "VERDICT item=ITEM-1 round=2 SAFE findings=0 head=$S7"; rm -f "$TMP/gh-calls"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD" --review "$RV2")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && pass "post-pass accepts a review whose head is the start of --head" || fail "head prefix ($out)"
rm -f "$H/reviews/app/OTHER-1-r3.md"
review_file "$RV2" "VERDICT item=ITEM-1 round=2 SAFE findings=0 head=$NEWHEAD"
sed -i.bak 's/^Gate: .*/Gate: claude:opus xhigh (fallback: sol at capacity) · base main · raw r · log l/' "$RV2"; rm -f "$RV2.bak" "$TMP/gh-calls"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD" --review "$RV2")
grep -q "PASS (head $NEWHEAD, round 2, claude:opus xhigh)" "$TMP/gh-calls" && pass "post-pass names the fallback that reviewed: claude:opus" || fail "post-pass fallback token ($out / $(cat "$TMP/gh-calls"))"
rm -f "$TMP/gh-calls"; mkdir -p "$TMP/phome"; printf '{"gate": {"model": "gpt-6-sol", "effort": "high"}}\n' > "$TMP/phome/star.json"
out=$( (cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" JUEL_STAR_HOME="$TMP/phome" sh "$SCRIPT" post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD") )
grep -q "PASS (head $NEWHEAD, round 2, gpt-6-sol high)" "$TMP/gh-calls" && pass "post-pass: with no flag and no review, star.json's gate block names the model" || fail "post-pass star.json ($out / $(cat "$TMP/gh-calls"))"

# #75: post-pass carries a SAFE across a merge of the base, and runs carry-check.sh itself
MAIN0=$(git -C "$APP" rev-parse main)
(cd "$APP" && git checkout -q main && printf 'other\n' > g && git add g && git -c user.email=t@t -c user.name=t commit -qm "main moves" \
  && git update-ref refs/remotes/origin/main main && git checkout -q feat/item-1 \
  && git -c user.email=t@t -c user.name=t merge -q --no-edit origin/main)
MERGED=$(git -C "$APP" rev-parse HEAD)
carried_pr() { printf '{"author":{"login":"me"},"baseRefName":"main","headRefOid":"%s","url":"https://github.com/o/r/pull/5","comments":[]}\n' "$1" > "$TMP/pr.json"; }
RG="$H/reviews/app/ITEM-1-r2.md"
reset; mkdir -p "$H/reviews/app"; review_file "$RG" "VERDICT item=ITEM-1 round=2 SAFE findings=0 head=$NEWHEAD"; carried_pr "$MERGED"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$MERGED" --review "$RG" --carried-from "$NEWHEAD" --reason "merge of origin/main with no conflicts")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && [ "$(cat "$TMP/body" 2>/dev/null)" = "$(printf 'Codex gate: PASS (head %s, round 2, gpt-6.1-sol xhigh, carried from %s: merge of origin/main with no conflicts)\nVERDICT: PASS' "$MERGED" "$NEWHEAD")" ] && pass "post-pass --carried-from posts the carried receipt on the merge head (#75)" || fail "carried-from ($out / $(cat "$TMP/body" 2>/dev/null))"
rm -f "$TMP/gh-calls" "$TMP/body" "$TMP/pr-n"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$MERGED" --review "$RG" --carried-from "$(printf '%.7s' "$NEWHEAD")" --reason "merge of origin/main with no conflicts")
grep -q "carried from $NEWHEAD: merge of origin/main with no conflicts)" "$TMP/body" 2>/dev/null && pass "a short --carried-from is named by its full sha in the receipt" || fail "short carried-from ($out)"
(cd "$APP" && printf 'sneaky\n' >> f && git -c user.email=t@t -c user.name=t commit -qam "more work")
SNEAKY=$(git -C "$APP" rev-parse HEAD)
reset; mkdir -p "$H/reviews/app"; review_file "$RG" "VERDICT item=ITEM-1 round=2 SAFE findings=0 head=$NEWHEAD"; carried_pr "$SNEAKY"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$SNEAKY" --review "$RG" --carried-from "$NEWHEAD" --reason "merge of origin/main with no conflicts"); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR not carried: $(printf '%.7s' "$SNEAKY") is not a merge: a commit of its own is a code change" ] && ! grep -q 'pr comment' "$TMP/gh-calls" && pass "post-pass never carries past a commit of its own, and posts nothing (Review Focus 1)" || fail "sneaky carry ($rc $out)"
git -C "$APP" reset -q --hard "$MERGED"
reset; mkdir -p "$H/reviews/app"; review_file "$RG" "VERDICT item=ITEM-1 round=2 SAFE findings=0 head=$MERGED"; carried_pr "$MERGED"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$MERGED" --review "$RG" --carried-from "$NEWHEAD" --reason x); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR the review is of $(printf '%.7s' "$MERGED"), not $(printf '%.7s' "$NEWHEAD")" ] && pass "with --carried-from, the review must be the gated head's" || fail "carried review head ($rc $out)"
reset; mkdir -p "$H/reviews/app"; review_file "$RG" "VERDICT item=ITEM-1 round=2 SAFE findings=0 head=$NEWHEAD"
printf '{"author":{"login":"me"},"headRefOid":"%s","url":"u","comments":[]}\n' "$MERGED" > "$TMP/pr.json"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$MERGED" --review "$RG" --carried-from "$NEWHEAD" --reason x); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR not carried: the PR's base branch is unknown" ] && pass "a PR whose base gh does not name is never carried" || fail "no base ($rc $out)"
G post-pass --pr x --round 2 --head "$MERGED" --reason x >/dev/null 2>&1; [ $? -eq 64 ] && pass "--reason without --carried-from is bad usage" || fail "usage reason"
G post-pass --pr x --round 2 --head "$MERGED" --carried-from "$NEWHEAD" --reason x >/dev/null 2>&1; [ $? -eq 64 ] && pass "--carried-from needs --review" || fail "usage carried review"
G post-pass --pr x --round 2 --head "$MERGED" --carried-from "$NEWHEAD" >/dev/null 2>&1; [ $? -eq 64 ] && pass "--carried-from without --reason is bad usage" || fail "usage carried reason"
git -C "$APP" reset -q --hard "$NEWHEAD"; git -C "$APP" update-ref refs/heads/main "$MAIN0"; git -C "$APP" update-ref -d refs/remotes/origin/main

# #82: the owner's carried PASS posts its own receipt, once review-proof.sh accepts it
RN="$H/reviews/app/ITEM-1-r3.md"; RC="$H/reviews/app/ITEM-1-r3-carried.md"
reset; mkdir -p "$H/reviews/app"; review_file "$RN" "VERDICT item=ITEM-1 round=3 NOT-SAFE findings=1 head=$NEWHEAD"
printf 'CARRIED item=ITEM-1 round=3 head=%s from=ITEM-1-r3.md decision=N-12\nship it\nDeferred: the findings in ITEM-1-r3.md\n' "$NEWHEAD" > "$RC"
carried_pr "$NEWHEAD"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 3 --head "$NEWHEAD" --review "$RC")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && [ "$(cat "$TMP/body" 2>/dev/null)" = "$(printf 'Codex gate: PASS (head %s, round 3, gpt-6.1-sol xhigh, carried by owner decision N-12: findings deferred)\nVERDICT: PASS (owner decision N-12)' "$NEWHEAD")" ] && pass "an owner's carried PASS posts its receipt, naming the decision (#82)" || fail "owner carry ($out / $(cat "$TMP/body" 2>/dev/null))"
rm -f "$TMP/gh-calls"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD" --review "$RC"); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR the carried review is of round 3, not round 2" ] && pass "a carried PASS posts only for its own round" || fail "owner carry round ($rc $out)"
printf 'CARRIED item=ITEM-1 round=3 head=%s from=ITEM-1-r3.md decision=N-12\nship it\n' 0000000000000000000000000000000000000000 > "$RC"
rm -f "$TMP/gh-calls"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 3 --head "$NEWHEAD" --review "$RC"); rc=$?
case "$out" in "ERROR the carried review is not proof for this head: head: "*) [ "$rc" -eq 69 ] && ! grep -q 'pr comment' "$TMP/gh-calls" 2>/dev/null && pass "a carried PASS of another head is refused, and nothing is posted" || fail "owner carry head rc ($rc)" ;; *) fail "owner carry head ($rc $out)" ;; esac
G post-pass --pr x --round 3 --head "$NEWHEAD" --review "$RC" --carried-from "$NEWHEAD" --reason x >/dev/null 2>&1; [ $? -eq 64 ] && pass "--carried-from does not go with a carried review" || fail "usage carried file"
reset

# #65: a latest-<family> name never reaches codex as written
reset; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main --model latest-sol >/dev/null
grep -q 'model="gpt-6.1-sol"' "$TMP/calls" && ! grep -q 'model="latest-sol"' "$TMP/calls" && pass "--model latest-sol is resolved before codex sees it (#65)" || fail "--model alias ($(cat "$TMP/calls"))"
reset; mkdir -p "$TMP/phome2"; printf '{"gate": {"model": "latest-sol", "effort": "xhigh"}}\n' > "$TMP/phome2/star.json"
printf '{"author":{"login":"me"},"headRefOid":"%s","url":"u","comments":[]}\n' "$NEWHEAD" > "$TMP/pr.json"
out=$( (cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_MODELS="$MODELS" JUEL_STAR_HOME="$TMP/phome2" sh "$SCRIPT" post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD") )
grep -q "PASS (head $NEWHEAD, round 2, gpt-6.1-sol xhigh)" "$TMP/gh-calls" && pass "post-pass names the model latest-sol resolves to, not the alias" || fail "post-pass alias ($out / $(cat "$TMP/gh-calls"))"

# #66: an ERROR keeps its round number and leaves no round files
R4="$H/reviews/app/ITEM-1-r4"
reset; plan "1 - error: 401 Unauthorized"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 4 --base main); rc=$?
[ "$rc" -eq 69 ] && [ ! -e "$R4.md" ] && [ ! -e "$R4.raw.md" ] && [ ! -e "$R4.log" ] && [ ! -e "$R4.run" ] && grep -q '401 Unauthorized' "$R4-error-1.log" && grep -q '^--- ERROR codex review failed: error: 401 Unauthorized$' "$R4-error-1.log" && pass "an ERROR run leaves only <item>-r4-error-1.log (#66)" || fail "error files ($rc $out: $(ls "$H/reviews/app"))"
rm -f "$TMP/n" "$TMP/calls"; plan "0 untagged"
G --brief "$BRIEF" --item ITEM-1 --round 4 --base main >/dev/null
[ -f "$R4-error-2.log" ] && grep -q '^--- stdout$' "$R4-error-2.log" && grep -q 'ERROR unreadable review' "$R4-error-2.log" && [ ! -e "$R4.raw.md" ] && pass "a second ERROR on the same round is error-2, with the review text kept" || fail "error-2 ($(ls "$H/reviews/app"))"
rm -f "$TMP/n" "$TMP/calls"; plan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 4 --base main)
[ "$out" = "SAFE round=4 findings=0 head=$HEAD review=$R4.md" ] && [ -f "$R4-error-1.log" ] && [ -f "$R4-error-2.log" ] && [ -s "$R4.raw.md" ] && pass "the next run of the same round gives it its verdict; the error logs stay" || fail "round 4 after errors ($out)"

# the run file names the review agent while a round runs (#70 reads it)
reset; export STUB_RUN="$H/reviews/app/ITEM-1-r1.run"; plan "0 peek"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main >/dev/null
python3 - "$TMP/run-seen" "$(cat "$TMP/stub-pid" 2>/dev/null)" "$H/reviews/app/ITEM-1-r1.log" <<'PY' && pass "the run file names the review agent, the gate, the model and the log while it runs" || fail "run file ($(cat "$TMP/run-seen" 2>/dev/null))"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["pid"] == int(sys.argv[2]) and d["gate"] != d["pid"], d
assert d["agent"] == "codex" and d["model"] == "gpt-6.1-sol" and d["attempt"] == 1 and d["log"] == sys.argv[3], d
assert d["started"].endswith("Z"), d
PY
[ ! -e "$STUB_RUN" ] && pass "the run file is gone once the round has its verdict" || fail "run file left behind"

# a signal stops the agent, keeps the round and removes the run file (Review Focus)
waitfor() { i=0; while { [ ! -s "$STUB_RUN" ] || [ ! -s "$TMP/stub-pid" ]; } && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; }
gone() { i=0; while kill -0 "$1" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; ! kill -0 "$1" 2>/dev/null; }
reset; plan "0 sleep"
(cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_FIX="$FIX" STUB_MODELS="$MODELS" CODEX_GATE_SLEEP=0 sh "$SCRIPT" --brief "$BRIEF" --item ITEM-1 --round 1 --base main > "$TMP/bg.out" 2>/dev/null) &
waitfor
gate=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["gate"])' "$STUB_RUN" 2>/dev/null)
child=$(cat "$TMP/stub-pid" 2>/dev/null)
kill -TERM "$gate" 2>/dev/null; wait
[ "$(cat "$TMP/bg.out")" = "ERROR stopped by SIGTERM" ] && [ ! -e "$STUB_RUN" ] && [ -f "$H/reviews/app/ITEM-1-r1-error-1.log" ] && gone "$child" && pass "TERM stops the review agent, removes the run file and keeps the round" || fail "signal ($(cat "$TMP/bg.out"))"
reset; plan "0 sleep"
(cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_FIX="$FIX" STUB_MODELS="$MODELS" CODEX_GATE_SLEEP=0 sh "$SCRIPT" --brief "$BRIEF" --item ITEM-1 --round 1 --base main > "$TMP/bg.out" 2>/dev/null) &
waitfor
kill -TERM -- "-$(cat "$TMP/stub-pid")" 2>/dev/null; wait
[ "$(cat "$TMP/bg.out")" = "ERROR codex review stopped by signal 15" ] && [ ! -e "$STUB_RUN" ] && [ -f "$H/reviews/app/ITEM-1-r1-error-1.log" ] && pass "an agent stopped from outside is ERROR for this round, never gate-down (Review Focus)" || fail "agent killed ($(cat "$TMP/bg.out"))"

# #71: the review streams to the terminal; the verdict is still the only stdout line, and the last line
reset; plan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main 2> "$TMP/stream")
[ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && grep -q 'The change adds the CSV export' "$TMP/stream" && grep -q '^--- codex review gpt-6.1-sol xhigh ' "$TMP/stream" && grep -q 'The change adds the CSV export' "$H/reviews/app/ITEM-1-r1.raw.md" && pass "codex's output streams on stderr and still lands in the raw file (#71)" || fail "stream ($out / $(cat "$TMP/stream"))"
reset; plan "1 - Selected model is at capacity." "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main > "$TMP/both" 2>&1
[ "$(tail -n 1 "$TMP/both")" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && grep -q 'Selected model is at capacity.' "$TMP/both" && grep -q 'Selected model is at capacity.' "$H/reviews/app/ITEM-1-r1.log" && pass "stderr streams too and still reaches the log; the verdict is the last line" || fail "combined ($(tail -n 3 "$TMP/both"))"
reset; plan "0 sleep"
(cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_FIX="$FIX" STUB_MODELS="$MODELS" CODEX_GATE_SLEEP=0 sh "$SCRIPT" --brief "$BRIEF" --item ITEM-1 --round 1 --base main > "$TMP/bg.out" 2> "$TMP/bg.err") &
i=0; while ! grep -q '^reviewing$' "$TMP/bg.err" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
[ -s "$STUB_RUN" ] && grep -q '^reviewing$' "$TMP/bg.err" && pass "a line reaches the terminal while the review still runs" || fail "not streamed live ($(cat "$TMP/bg.err"))"
kill -TERM -- "-$(cat "$TMP/stub-pid")" 2>/dev/null; wait

# #63: the prompt points at the evidence of the live checks
reset; plan "0 safe"; mkdir -p "$APP/ev"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main --evidence "$APP/ev" >/dev/null
P1="$H/specs/app/ITEM-1-gate-r1.md"
grep -q "Evidence of the live checks: $APP/ev; start at its report.md" "$P1" && grep -q 'A criterion with no change in the diff behind it is judged on this evidence' "$P1" && pass "--evidence puts the evidence folder in the prompt (#63)" || fail "evidence line ($(grep -i evidence "$P1"))"
reset; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main >/dev/null
grep -q 'No evidence folder was given.' "$P1" && pass "without --evidence the prompt says so" || fail "no evidence line"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main --evidence "$APP/no-such" >/dev/null 2>&1; [ $? -eq 64 ] && pass "an --evidence folder that does not exist is a usage error" || fail "missing evidence folder"
rmdir "$APP/ev"
# #61: an accepted residual in Decisions is not a missed criterion
grep -q 'accepts with a documented residual and a named follow-up is met, not missed' "$P1" && pass "the prompt says an accepted residual is met (#61)" || fail "accepted residual line"
grep -qF 'A finding class (the same invariant broken at several places) is one finding that names every site, never one site per round' "$P1" && pass "#131 the prompt asks for every site of a finding class in one finding" || fail "#131 finding-class line ($(grep -i 'finding class' "$P1"))"
# lane c: #147 a criterion that names a CI check is proven by that check, never a finding in the round
grep -qF 'A criterion that names a CI check (a lane, a workflow or a job that must pass on the PR'"'"'s head) is proven by that check on the head, which STAR'"'"'s merge gate requires green before it merges: while the check has not reported on the head, the criterion is pending, never a finding in this round. A check that reported red on the head, or a change this branch makes to that check'"'"'s own definition, is judged like any other finding.' "$P1" && pass "#147 the prompt leaves a CI-proven criterion to the merge gate" || fail "#147 CI criterion line"
# #67: a round with no -fix.md behind it takes the brief's later decisions as dispositions
reset; mkdir -p "$H/reviews/app"; printf 'VERDICT item=ITEM-1 round=1 NOT-SAFE findings=1 head=%s\n' "$HEAD" > "$H/reviews/app/ITEM-1-r1.md"
TZ=UTC touch -t 202610101200 "$H/reviews/app/ITEM-1-r1.md"; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 2 --base main >/dev/null
P2="$H/specs/app/ITEM-1-gate-r2.md"
grep -q 'No `-fix.md` exists for round 1. Treat the records in the brief'"'"'s `## Decisions` dated 2026-10-10 or later as the dispositions of its findings.' "$P2" && pass "a re-scope with no -fix.md: the brief's later decisions are the dispositions (#67)" || fail "decisions as dispositions ($(grep -i previous "$P2"))"
rm -f "$TMP/n" "$TMP/calls"; plan "0 safe"; printf '1. Disposition: moved to ITEM-1-followup.\n' > "$H/reviews/app/ITEM-1-r1-fix.md"
G --brief "$BRIEF" --item ITEM-1 --round 2 --base main >/dev/null
! grep -q 'No `-fix.md` exists' "$P2" && pass "with a -fix.md the prompt adds no such sentence" || fail "fix.md present"
# the fallback can read the evidence folder too
reset; plan "1 - You've hit your usage limit."; cplan "0 safe"; mkdir -p "$TMP/ev2"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main --evidence "$TMP/ev2" >/dev/null
grep -qF -- "--add-dir $H $TMP/ev2 --allowedTools" "$TMP/claude-calls" && pass "the Claude fallback gets the evidence folder as a readable directory" || fail "fallback evidence dir ($(tail -n 1 "$TMP/claude-calls"))"

# #62: GitHub can show the previous head for a few seconds after a push
reset; OLD=0000000000000000000000000000000000000000
printf '{"author":{"login":"me"},"headRefOid":"%s","url":"u","comments":[]}\n' "$OLD" > "$TMP/pr-1.json"; cp "$TMP/pr-1.json" "$TMP/pr-2.json"
printf '{"author":{"login":"me"},"headRefOid":"%s","url":"https://github.com/o/r/pull/5","comments":[]}\n' "$NEWHEAD" > "$TMP/pr.json"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 2 --head "$NEWHEAD")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && [ "$(cat "$TMP/pr-n")" = 3 ] && pass "post-pass waits out GitHub's head lag after a push (#62)" || fail "head lag ($out, $(cat "$TMP/pr-n") views)"

# #64: check says whether the gate can review at all, for STAR's gateDown
mkdir -p "$TMP/chome" "$TMP/fix"; printf 'ok\n' > "$TMP/fix/ok.txt"
printf '{"gate": {"model": "latest-sol", "effort": "xhigh", "fallback": {"agent": "claude", "model": "opus", "effort": "xhigh"}}}\n' > "$TMP/chome/star.json"
C() { (cd "$APP" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" STUB_FIX="$TMP/fix" STUB_MODELS="$MODELS" JUEL_STAR_HOME="$TMP/chome" sh "$SCRIPT" check "$@"); }
reset; plan "0 ok"
out=$(C); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "up codex:gpt-6.1-sol" ] && grep -q '^exec ' "$TMP/calls" && grep -q 'model="gpt-6.1-sol"' "$TMP/calls" && grep -q 'model_reasoning_effort="low"' "$TMP/calls" && grep -q 'Reply with the single word ok.' "$TMP/calls" && [ ! -f "$TMP/claude-calls" ] && pass "check: Sol answers, so the gate is up" || fail "check up ($rc $out / $(cat "$TMP/calls"))"
reset; plan "1 - You've hit your usage limit."; cplan "0 ok"
out=$(C); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "up claude:opus" ] && grep -qF -- '--model opus --effort low' "$TMP/claude-calls" && pass "check: Sol down, Claude up, the gate is up" || fail "check claude ($rc $out)"
reset; plan "1 - You've hit your usage limit."; cplan "1 - API Error: 529 Overloaded"
out=$(C); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "down sol: You've hit your usage limit.; claude: API Error: 529 Overloaded" ] && pass "check: both down is down, naming both" || fail "check down ($rc $out)"
reset; plan "0 safe"; cplan "0 ok"
out=$(C)
[ "$out" = "up claude:opus" ] && pass "check: an answer without ok is not up" || fail "check not ok ($out)"
printf '{"gate": {"model": "latest-sol", "fallback": null}}\n' > "$TMP/chome/star.json"
reset; plan "1 - at capacity"
out=$(C); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "down sol: at capacity; no fallback is set" ] && [ ! -f "$TMP/claude-calls" ] && pass "check: fallback null, Sol down, down" || fail "check null ($rc $out)"
C extra >/dev/null 2>&1; [ $? -eq 64 ] && pass "check takes no arguments" || fail "check usage"

# usage
G --item ITEM-1 --round 1 --base main >/dev/null 2>&1; [ $? -eq 64 ] && pass "no --brief is 64" || fail "usage brief"
G --brief "$BRIEF" --item ITEM-1 --round 0 --base main >/dev/null 2>&1; [ $? -eq 64 ] && pass "round 0 is 64" || fail "usage round"
G post-pass --pr x --round 1 --head abc >/dev/null 2>&1; [ $? -eq 64 ] && pass "post-pass needs the full head" || fail "usage head"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main --fallback latest-sol >/dev/null 2>&1; [ $? -eq 64 ] && pass "--fallback is gone: the fallback is star.json's gate.fallback" || fail "usage fallback"

# lane c: the fallback's read rules and its quoting rule (#100)
dash_c() { r=$1; shift; for s in "$@"; do printf ' Bash(git -C %s %s) Bash(git -C %s %s *)' "$r" "$s" "$r" "$s"; done; }
rules() { # rules <command>...: "git <command> *" for each, then its two -C rules for the real path and, when $PWD differs, for $PWD
  for s in "$@"; do printf ' Bash(git %s *)' "$s"; done
  dash_c "$APPREAL" "$@"
  [ "$APP" = "$APPREAL" ] || dash_c "$APP" "$@"
}
reset; plan "1 - You've hit your usage limit."; cplan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main >/dev/null
call=$(grep -F -- '--allowedTools' "$TMP/claude-calls")
allowed=$(printf '%s\n' "$call" | sed -e 's/.*--allowedTools //' -e 's/ --disallowedTools.*//')
want="Read Grep Glob$(rules diff show log)$(rules ls-tree ls-files rev-parse merge-base cat-file '--no-pager diff' '--no-pager show' '--no-pager log' '-P diff' '-P show' '-P log')"
[ "$allowed" = "$want" ] && pass "the fallback may also run git ls-tree, ls-files, rev-parse, merge-base and cat-file, and diff, show and log with the pager off, each also under -C (#100)" || fail "allow rules ($allowed)"
! printf '%s\n' "$allowed" | grep -qE 'git (-C [^ ]+ )?(-c|grep)[ )]' && pass "no git -c rule and no git grep rule (#100)" || fail "git -c or git grep allowed ($allowed)"
printf '%s\n' "$call" | grep -qF -- '--disallowedTools Edit Write NotebookEdit Bash(git * --output*) --output-format json' && pass "the --output deny rule stays (#100)" || fail "deny rule ($call)"
grep -F -- '--append-system-prompt' "$TMP/claude-calls" | grep -qF 'Single-quote any argument that holds a shell metacharacter (`& | ; < > ( ) [ ] * ? $`), and never use `$(…)`.' && pass "the fallback is told to single-quote a shell metacharacter (#100)" || fail "quoting rule ($(grep -F -- '--append-system-prompt' "$TMP/claude-calls"))"
grep -F -- '--append-system-prompt' "$TMP/claude-calls" | grep -qF 'Use only Read, Grep, Glob, git diff, git show, git log, git ls-tree, git ls-files, git rev-parse, git merge-base and git cat-file, one command per call' && pass "the fallback is told it may also use git ls-tree, ls-files, rev-parse, merge-base and cat-file (#100)" || fail "tool list ($(grep -F -- '--append-system-prompt' "$TMP/claude-calls"))"

# lane c: a denied fallback run is asked once more inside the round (#100)
reset; plan "1 - You've hit your usage limit."; cplan "0 claude-denied-two.json" "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && [ "$(cat "$TMP/claude-n")" = 2 ] && grep -q '^Gate: claude:opus xhigh (fallback: sol usage limit)' "$R1" && [ "$(head -n 1 "$H/reviews/app/ITEM-1-r1.raw.md")" = "The change adds the CSV export the brief asks for, and I found no defect that should block it." ] && pass "one denial, then a clean run in the same round, gives a verdict (#100)" || fail "denial then clean ($rc $out, $(cat "$TMP/claude-n" 2>/dev/null) claude runs)"
grep -qxF 'Your previous run was denied: git diff --word-diff=porcelain --word-diff-regex=[^[:space:]&]+ origin/main...HEAD -- package.json. Search with Grep and find files with Glob (never git grep, grep or rg), read a file with Read, and run any other git command as one plain command, single-quoting any argument that holds a shell metacharacter.' "$TMP/claude-calls" \
  && grep -qxF 'Your previous run was denied: git ls-tree --name-only origin/dev docs/decisions/. Search with Grep and find files with Glob (never git grep, grep or rg), read a file with Read, and run any other git command as one plain command, single-quoting any argument that holds a shell metacharacter.' "$TMP/claude-calls" \
  && [ "$(grep -c '^Your previous run was denied: ' "$TMP/claude-calls")" = 2 ] \
  && pass "the second run's prompt names each denied command on a line of its own, and the first run's names none (#100)" || fail "retry prompt ($(grep 'denied' "$TMP/claude-calls"))"
L1="$H/reviews/app/ITEM-1-r1.log"
[ "$(grep -c '^--- claude opus xhigh' "$L1")" = 2 ] && grep -q '^--- stdout$' "$L1" && grep -qF 'git ls-tree --name-only origin/dev docs/decisions/' "$L1" && pass "the denied run's output stays in the round's log, beside the second run's (#100)" || fail "first run's log ($(cat "$L1"))"
reset; plan "1 - You've hit your usage limit."; cplan "0 claude-denied-two.json" "0 claude-denied.json"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR gate-down sol usage limit: You've hit your usage limit.; claude: Bash was denied: git -C /repo diff main...HEAD" ] && [ "$(cat "$TMP/claude-n")" = 2 ] && [ ! -f "$R1" ] \
  && [ "$(grep -c '^--- stdout$' "$H/reviews/app/ITEM-1-r1-error-1.log")" = 2 ] && grep -qF 'origin/dev docs/decisions/' "$H/reviews/app/ITEM-1-r1-error-1.log" \
  && pass "a second denial is gate-down, read from the second run, with both runs kept in the error log (#100)" || fail "two denials ($rc $out, $(cat "$TMP/claude-n" 2>/dev/null) claude runs)"
reset; plan "1 - You've hit your usage limit."; cplan "0 claude-is-error.json" "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR gate-down sol usage limit: You've hit your usage limit.; claude: API Error: 529 Overloaded" ] && [ "$(cat "$TMP/claude-n")" = 1 ] && pass "a fallback failure that is not a denial is gate-down at once, with no second run (#100)" || fail "no retry without a denial ($rc $out)"

# lane c: a direct post-pass is already done only over a direct receipt for the same head (#104)
receipts_pr() { # receipts_pr <first line>...: a PR on $NEWHEAD whose author left one two-line receipt per argument, the n-th at #issuecomment-<n + 6>
  n=6; comments=""
  for line in "$@"; do n=$((n + 1)); comments="$comments${comments:+,}{\"author\":{\"login\":\"me\"},\"body\":\"$line\\nVERDICT: PASS\",\"url\":\"https://github.com/o/r/pull/5#issuecomment-$n\"}"; done
  printf '{"author":{"login":"me"},"baseRefName":"main","headRefOid":"%s","url":"https://github.com/o/r/pull/5","comments":[%s]}\n' "$NEWHEAD" "$comments" > "$TMP/pr.json"
}
CARRIED_LINE="Codex gate: PASS (head $NEWHEAD, round 2, gpt-6.1-sol xhigh, carried from 1111111111111111111111111111111111111111: merge of origin/main with no conflicts)"
OWNER_LINE="Codex gate: PASS (head $NEWHEAD, round 3, gpt-6.1-sol xhigh, carried by owner decision N-12: findings deferred)"
DIRECT_LINE="Codex gate: PASS (head $NEWHEAD, round 3, claude:opus xhigh)"
reset; receipts_pr "$CARRIED_LINE"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 4 --head "$NEWHEAD")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && [ "$(cat "$TMP/body" 2>/dev/null)" = "$(printf 'Codex gate: PASS (head %s, round 4, gpt-6.1-sol xhigh)\nVERDICT: PASS' "$NEWHEAD")" ] && pass "a direct post-pass posts its receipt over a carried one: a direct verdict supersedes a carry (#104)" || fail "direct over carried ($out)"
reset; receipts_pr "$OWNER_LINE"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 4 --head "$NEWHEAD")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && pass "an owner-decision carry does not stop a direct receipt on the same head (#104)" || fail "direct over owner carry ($out)"
reset; receipts_pr "$DIRECT_LINE"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 4 --head "$NEWHEAD")
[ "$out" = "already https://github.com/o/r/pull/5#issuecomment-7" ] && ! grep -q 'pr comment' "$TMP/gh-calls" && pass "a direct receipt for the head is already there, whatever its round and model (#104)" || fail "direct over direct ($out)"
reset; receipts_pr "$CARRIED_LINE" "$OWNER_LINE" "$DIRECT_LINE"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 4 --head "$NEWHEAD")
[ "$out" = "already https://github.com/o/r/pull/5#issuecomment-9" ] && ! grep -q 'pr comment' "$TMP/gh-calls" && pass "with carried and direct receipts on the head, a direct post-pass is already done, naming the direct one (Review Focus 5)" || fail "carried and direct ($out)"
reset; receipts_pr "Codex gate: PASS (head 0000000000000000000000000000000000000000, round 3, gpt-6.1-sol xhigh)" "Codex gate: PASS (head $(printf '%.7s' "$NEWHEAD"), round 3, gpt-6.1-sol xhigh)" "$CARRIED_LINE"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 4 --head "$NEWHEAD")
[ "$out" = "posted https://github.com/o/r/pull/5#issuecomment-1" ] && pass "a direct receipt on another head, or on this head's short form, does not count (Review Focus 5)" || fail "direct receipt on another head ($out)"
reset; mkdir -p "$H/reviews/app"; review_file "$RN" "VERDICT item=ITEM-1 round=3 NOT-SAFE findings=1 head=$NEWHEAD"
printf 'CARRIED item=ITEM-1 round=3 head=%s from=ITEM-1-r3.md decision=N-12\nship it\nDeferred: the findings in ITEM-1-r3.md\n' "$NEWHEAD" > "$RC"
receipts_pr "$DIRECT_LINE"
out=$(G post-pass --pr https://github.com/o/r/pull/5 --round 3 --head "$NEWHEAD" --review "$RC")
receipts_pr "$CARRIED_LINE"
out2=$(G post-pass --pr https://github.com/o/r/pull/5 --round 3 --head "$NEWHEAD" --review "$RC")
[ "$out" = "already https://github.com/o/r/pull/5#issuecomment-7" ] && [ "$out2" = "already https://github.com/o/r/pull/5#issuecomment-7" ] && ! grep -q 'pr comment' "$TMP/gh-calls" && pass "a carried post-pass keeps today's rule: any receipt on the head is already there (#104)" || fail "carried post-pass ($out / $out2)"
reset

# lane b: the round's base is pinned, and a base that moved under a file the branch changes is merged first (#113)
MAINSHA=$(git -C "$APP" rev-parse main)
reset; plan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && grep -q "^Gate: gpt-6.1-sol xhigh · base main $MAINSHA · raw " "$R1" && pass "the review's Gate line names the base and the commit the round pinned (#113)" || fail "pinned Gate line ($rc $out, $(grep '^Gate:' "$R1"))"
P1="$H/specs/app/ITEM-1-gate-r1.md"
grep -qF "git diff $MAINSHA...HEAD" "$P1" && grep -qF "git show $MAINSHA:AGENTS.md" "$P1" && ! grep -qF 'main...HEAD' "$P1" && pass "the prompt names the pinned commit in place of the ref, so a fetch during the round cannot move it (#113)" || fail "pinned prompt ($(grep -F 'git ' "$P1"))"
reset; plan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base no-such-branch); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR the base no-such-branch is not a commit here" ] && [ ! -f "$TMP/n" ] && pass "a base git cannot resolve is ERROR before any agent runs (#113)" || fail "unknown base ($rc $out)"
# the base changes f, the file the branch changes, and the branch does not have it yet
(cd "$APP" && git checkout -q main && printf 'a\nbase\n' > f && git -c user.email=t@t -c user.name=t commit -qam "base changes f" && git checkout -q feat/item-1)
MOVED=$(git -C "$APP" rev-parse main)
reset; plan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 2 --base main); rc=$?
[ "$rc" -eq 69 ] && [ "$out" = "ERROR base-moved main at $(printf '%.7s' "$MOVED") changes f, a file this branch changes: merge it in, then run round 2" ] && pass "a base that moved under a file the branch changes refuses the round (#113)" || fail "base-moved ($rc $out)"
[ ! -f "$TMP/n" ] && [ ! -f "$TMP/calls" ] && [ ! -f "$TMP/claude-calls" ] && [ -z "$(ls "$H/reviews/app" 2>/dev/null)" ] && [ ! -e "$H/specs/app/ITEM-1-gate-r2.md" ] && pass "the refusal runs no agent and leaves no round file, no error log and no prompt (Review Focus 3)" || fail "the refusal left something ($(ls "$H/reviews/app" "$H/specs/app" 2>/dev/null))"
(cd "$APP" && git -c user.email=t@t -c user.name=t merge -q --no-edit -X ours main >/dev/null)
MERGEDB=$(git -C "$APP" rev-parse HEAD)
reset; plan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 2 --base main); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "SAFE round=2 findings=0 head=$MERGEDB review=$H/reviews/app/ITEM-1-r2.md" ] && [ "$(cat "$TMP/n")" = 1 ] && pass "once the branch holds the newest base, the same round runs and keeps its number (Review Focus 3)" || fail "after the merge ($rc $out)"
# the base moves again, this time only in g, a file the branch never changes
git -C "$APP" reset -q --hard "$HEAD"; git -C "$APP" update-ref refs/heads/main "$MAINSHA"
(cd "$APP" && git checkout -q main && printf 'other\n' > g && git add g && git -c user.email=t@t -c user.name=t commit -qm "base adds g" && git checkout -q feat/item-1)
GONLY=$(git -C "$APP" rev-parse main)
reset; plan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && grep -qF "git diff $GONLY...HEAD" "$H/specs/app/ITEM-1-gate-r1.md" && grep -q "^Gate: gpt-6.1-sol xhigh · base main $GONLY · " "$R1" && pass "a base that moved only in files the branch never changes is reviewed, pinned to its new commit (Review Focus 3)" || fail "disjoint move ($rc $out)"
git -C "$APP" update-ref refs/heads/main "$MAINSHA"
reset

# lane b: the fallback searches with Grep and Glob, and a denied git grep is sent there (#117)
reset; plan "1 - You've hit your usage limit."; cplan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 1 --base main >/dev/null
grep -F -- '--append-system-prompt' "$TMP/claude-calls" | grep -qF 'any other command is refused, and a refused command fails the review. Search with Grep and find files with Glob, never git grep, grep or rg. Single-quote any argument' && pass "the fallback is told to search with Grep and Glob, never git grep, grep or rg (#117)" || fail "search rule ($(grep -F -- '--append-system-prompt' "$TMP/claude-calls"))"
reset; plan "1 - You've hit your usage limit."; cplan "0 claude-denied-grep.json" "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && [ "$(cat "$TMP/claude-n")" = 2 ] && grep -q '^Gate: claude:opus xhigh (fallback: sol usage limit)' "$R1" && pass "a usage limit whose fallback was denied git grep still ends in a verdict, not gate-down (#117)" || fail "git grep denial ($rc $out, $(cat "$TMP/claude-n" 2>/dev/null) claude runs)"
grep -qxF 'Your previous run was denied: git grep -n chain origin/main -- package.json. Search with Grep and find files with Glob (never git grep, grep or rg), read a file with Read, and run any other git command as one plain command, single-quoting any argument that holds a shell metacharacter.' "$TMP/claude-calls" && pass "the retry sends the denied git grep to Grep and Glob (#117)" || fail "git grep retry line ($(grep 'denied' "$TMP/claude-calls"))"
# lane f: a path a build marked as tooling is graded for safety only, and its blocking findings are counted (#160)
reset; plan "0 p1"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
grep -qF 'No path is tooling: grade every file in full.' "$H/specs/app/ITEM-1-gate-r1.md" && ! printf '%s' "$out" | grep -q 'tooling=' && pass "TL160a without a tooling file the prompt says no path is tooling and the line has no tooling=" || fail "TL160a ($out)"
reset; plan "0 tooling-p1"; printf 'eval/\n' > "$H/gates/app/ITEM-1-tooling.md"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
grep -qF 'Tooling, graded for safety only: eval/.' "$H/specs/app/ITEM-1-gate-r1.md" && [ "$out" = "NOT-SAFE round=1 findings=2 p0=0 p1=2 tooling=2 head=$HEAD review=$R1" ] && pass "TL160b a tooling file puts the prefixes in the prompt and tooling=2 on the line" || fail "TL160b ($out)"
grep -q '^VERDICT item=ITEM-1 round=1 NOT-SAFE findings=2 head=' "$R1" && pass "TL160b2 the review's VERDICT line is unchanged" || fail "TL160b2 ($(head -n 1 "$R1"))"
reset; plan "0 tooling-mixed"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
[ "$out" = "NOT-SAFE round=1 findings=2 p0=0 p1=2 tooling=1 head=$HEAD review=$R1" ] && pass "TL160c a finding outside the prefixes is not counted" || fail "TL160c ($out)"
reset; plan "0 p1"; printf '# nothing is tooling yet\n\n' > "$H/gates/app/ITEM-1-tooling.md"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
grep -qF 'No path is tooling' "$H/specs/app/ITEM-1-gate-r1.md" && ! printf '%s' "$out" | grep -q 'tooling=' && pass "TL160d a tooling file with only a comment counts as none" || fail "TL160d ($out)"
reset; plan "0 abs"; printf 'eval\n' > "$H/gates/app/ITEM-1-tooling.md"
printf 'x\n\nReview comment:\n\n- [P1] Runner drops failures \xe2\x80\x94 `%s/eval/run.py:3`\n  body\n' "$APPREAL" > "$TMP/fix/abs.txt"
out=$(GF --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
[ "$out" = "NOT-SAFE round=1 findings=1 p0=0 p1=1 tooling=1 head=$HEAD review=$R1" ] && pass "TL160e an absolute place under the worktree counts" || fail "TL160e ($out)"
rm -f "$H/gates/app/ITEM-1-tooling.md"

# audit lane C: {{since}} and the out-of-credits phrases
gc() { git -C "$APP" -c user.email=t@t -c user.name=t "$@"; }
vline() { printf 'VERDICT item=ITEM-1 round=1 NOT-SAFE findings=1 p0=0 p1=1 head=%s\n1. [P1] x - /repo/a.py:1-1\n' "$1" > "$H/reviews/app/ITEM-1-r1.md"; }
since_run() { reset; mkdir -p "$H/reviews/app"; plan "0 safe"; G --brief "$BRIEF" --item ITEM-1 --round "${1:-2}" --base main >/dev/null; }
SP="$H/specs/app/ITEM-1-gate-r2.md"
BASESHA=$(git -C "$APP" rev-parse main)
since_run 1
grep -qF 'Review the whole change.' "$H/specs/app/ITEM-1-gate-r1.md" && pass "since: round 1 reviews the whole change" || fail "since r1"
reset; mkdir -p "$H/reviews/app"; vline "$HEAD"; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 2 --base main >/dev/null
grep -qF 'Round 1 reviewed this same head.' "$SP" && grep -qF '"(earlier code)"' "$SP" && pass "since: the same head" || fail "since same ($(cat "$SP"))"
gc commit -q --allow-empty -m more; HEAD2=$(git -C "$APP" rev-parse HEAD)
reset; mkdir -p "$H/reviews/app"; vline "$HEAD"; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 2 --base main >/dev/null
grep -qF "Round 1 reviewed $(printf %s "$HEAD" | cut -c1-7)." "$SP" && grep -qF "git log --oneline $HEAD..HEAD" "$SP" && grep -qF "git diff $HEAD..HEAD" "$SP" && grep -qF -- "git diff $BASESHA...HEAD --name-only" "$SP" && grep -qF '"(earlier code)"' "$SP" && grep -qF 'A [P0] anywhere still blocks.' "$SP" && pass "since: an ancestor head names the commits since" || fail "since ancestor ($(cat "$SP"))"
reset; mkdir -p "$H/reviews/app"; vline "0123456789abcdef0123456789abcdef01234567"; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 2 --base main >/dev/null
grep -qF 'Review the whole change.' "$SP" && pass "since: an unknown head reviews the whole change" || fail "since unknown"
reset; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 2 --base main >/dev/null
grep -qF 'Review the whole change.' "$SP" && pass "since: no previous review reviews the whole change" || fail "since none"
# a merge of the base between the previous head and HEAD keeps the since text
gc checkout -q main; printf 'm\n' > "$APP/basework.txt"; gc add basework.txt; gc commit -qm basework; gc checkout -q feat/item-1; gc merge -q --no-ff --no-edit main
[ -n "$(gc rev-list --merges "$HEAD..HEAD")" ] && pass "since: the base merge commit exists between the previous head and HEAD" || fail "since merge commit missing"
reset; mkdir -p "$H/reviews/app"; vline "$HEAD"; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 2 --base main >/dev/null
grep -qF "git log --oneline $HEAD..HEAD" "$SP" && grep -qF -- '--name-only' "$SP" && pass "since: a base merge among the commits keeps the since text" || fail "since merge ($(cat "$SP"))"
# a head dropped by a rewritten history
vline "$HEAD2"; gc reset -q --hard "$HEAD"; gc commit -q --allow-empty -m rewritten; gc gc -q --prune=now 2>/dev/null; gc reflog expire --expire=now --all; gc gc -q --prune=now 2>/dev/null
reset; mkdir -p "$H/reviews/app"; vline "$HEAD2"; plan "0 safe"
G --brief "$BRIEF" --item ITEM-1 --round 2 --base main >/dev/null
grep -qF 'Review the whole change.' "$SP" && pass "since: a head dropped by a rewrite reviews the whole change" || fail "since rewritten ($(cat "$SP"))"
gc reset -q --hard "$HEAD"
reset; plan "1 - You are out of credits for this workspace."; cplan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
[ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && [ "$(cat "$TMP/n")" = 1 ] && grep -q '^Gate: claude:opus xhigh (fallback: sol usage limit)' "$R1" && pass "out of credits goes to Claude at once" || fail "credits ($out)"
reset; plan "1 - Your credit balance is too low"; cplan "0 safe"
out=$(G --brief "$BRIEF" --item ITEM-1 --round 1 --base main)
[ "$out" = "SAFE round=1 findings=0 head=$HEAD review=$R1" ] && [ "$(cat "$TMP/n")" = 1 ] && grep -q '^Gate: claude:opus xhigh (fallback: sol usage limit)' "$R1" && pass "credit balance goes to Claude at once" || fail "balance ($out)"

reset
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
