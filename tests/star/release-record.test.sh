#!/bin/sh
# Runs skills/star/release-record.sh against a scratch STAR home and a stub gh.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/release-record.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL release-record.sh missing"; exit 1; }
H="$TMP/home"; mkdir -p "$H/reviews/lstn" "$H/briefs/lstn" "$TMP/bin"
cp "$ROOT/skills/star/template/ledger.md" "$H/ledger.md"; cp "$ROOT/skills/star/template/open-loops.md" "$H/open-loops.md"
printf '| #12 | #12 | lstn | /w/a | ready | - | 2 | t | d | 0 | https://github.com/o/lstn/pull/12 | abc1234 | - | - | - | now |\n| #12 | #12 | web | /w/b | ready | - | 1 | t | d | 0 | https://github.com/o/web/pull/12 | fff0000 | - | - | - | now |\n' >> "$H/ledger.md"
: > "$H/reviews/lstn/#12-r1.md"; : > "$H/reviews/lstn/#12-r2.md"; : > "$H/briefs/lstn/#12.md"
sh "$ROOT/skills/star/loops.sh" --file "$H/open-loops.md" add --kind held --project lstn --item '#12' --title "set status in_review via linear" >/dev/null
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
[ "${STUB_FAIL:-}" = 1 ] && { echo "boom" >&2; exit 1; }
cat "$STUB_JSON"
EOF
chmod +x "$TMP/bin/gh"; ln -s "$(command -v python3)" "$TMP/bin/python3"
cat > "$TMP/merged.json" <<'EOF'
{"number":12,"title":"Add retry to the webhook","url":"https://github.com/o/lstn/pull/12","state":"MERGED",
 "mergeCommit":{"oid":"9e8d7c6b5a"},"mergedAt":"2026-10-07T03:04:05Z","mergedBy":{"login":"jrsgacusan"},
 "baseRefName":"main","headRefName":"feat/issue-12-retry",
 "reviews":[{"author":{"login":"ezra"},"state":"APPROVED"},{"author":{"login":"jp"},"state":"COMMENTED"},{"author":{"login":"ezra"},"state":"APPROVED"}],
 "statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]}
EOF
run() { PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged.json" sh "$SCRIPT" --home "$H" "$@"; }
out=$(run --project lstn --item '#12' --pr 12)
exp="$H/releases/2026-10-07-lstn-12.md"
[ "$out" = "$exp" ] && [ -f "$exp" ] && pass "record written, path printed" || fail "record path ($out)"
grep -q 'Add retry to the webhook' "$exp" && grep -q '9e8d7c6b5a' "$exp" && grep -q 'jrsgacusan' "$exp" && pass "title, merge commit, merger" || fail "core fields"
grep -q 'Approved by: ezra$' "$exp" && pass "approvers deduplicated, commenters excluded" || fail "approvers"
grep -q 'Checks on the PR head at merge: all passed' "$exp" && pass "checks" || fail "checks"
grep -q 'Second-model review rounds: 2' "$exp" && pass "same item in two projects: the lstn row is used" || fail "wrong ledger row"
grep -q 'reviews/lstn/#12-r1.md' "$exp" && grep -q 'reviews/lstn/#12-r2.md' "$exp" && pass "review files listed" || fail "review files"
grep -q 'set status in_review via linear' "$exp" && pass "open follow-ups listed" || fail "follow-ups"
out2=$(run --project lstn --item '#12' --pr 12)
[ "$out2" = "$exp" ] && [ "$(ls "$H/releases" | wc -l | tr -d ' ')" = 1 ] && pass "the same PR twice gives the same record, not a second one" || fail "second record for one PR ($out2)"
sed -e 's/"number":12/"number":13/' -e 's#pull/12#pull/13#' "$TMP/merged.json" > "$TMP/merged13.json"
run13() { PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged13.json" sh "$SCRIPT" --home "$H" "$@"; }
out2=$(run13 --project lstn --item '#12' --pr 13)
[ "$out2" = "$H/releases/2026-10-07-lstn-12-v2.md" ] && ! grep -q 'pull/13' "$exp" && pass "another PR for the same item never overwrites" || fail "overwrote ($out2)"
sed 's/"state":"MERGED"/"state":"OPEN"/' "$TMP/merged.json" > "$TMP/open.json"
PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/open.json" sh "$SCRIPT" --home "$H" --project lstn --item '#12' --pr 12 >/dev/null 2>&1
[ $? -eq 1 ] && pass "an unmerged PR is refused" || fail "unmerged PR accepted"
PATH="$TMP/bin:/usr/bin:/bin" STUB_FAIL=1 STUB_JSON=/dev/null sh "$SCRIPT" --home "$H" --project lstn --item '#12' --pr 12 >/dev/null 2>&1
[ $? -eq 1 ] && pass "gh failure is an error" || fail "gh failure"

sh "$ROOT/skills/star/loops.sh" --file "$H/open-loops.md" add --kind merge-pr --project lstn --item '#12' --title "merge PR #12 — approved" >/dev/null
sed -e 's/"number":12/"number":14/' -e 's#pull/12#pull/14#' "$TMP/merged.json" > "$TMP/merged14.json"
out3=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged14.json" sh "$SCRIPT" --home "$H" --project lstn --item '#12' --pr 14)
grep -q 'set status in_review via linear' "$out3" && ! grep -q 'merge PR #12 — approved' "$out3" && pass "the item's own merge-pr entry is not a follow-up" || fail "merge-pr listed as a follow-up"
grep -q '^- Worktree: /w/a' "$out3" && pass "worktree recorded (evidence lives there)" || fail "worktree missing"
grep -q 'Checks on the PR head at merge: all passed' "$out3" && pass "checks labelled honestly" || fail "checks label"
PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged.json" sh "$SCRIPT" --bogus >/dev/null 2>&1; [ $? -eq 64 ] && pass "bad usage is exit 64" || fail "usage exit code"

for body in '[]' '502' 'null'; do
  printf '%s\n' "$body" > "$TMP/odd.json"
  err=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/odd.json" sh "$SCRIPT" --home "$H" --project lstn --item '#12' --pr 12 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$err" = "error: gh: unreadable output" ] && pass "gh printing $body is one error line" || fail "gh printing $body (rc=$rc: $err)"
done
run --project 'a/b' --item '#12' --pr 12 >/dev/null 2>&1; [ $? -eq 64 ] && pass "a project that is not a plain name is refused" || fail "project with a slash"
run --project lstn --item '../escape' --pr 12 >/dev/null 2>&1; [ $? -eq 64 ] && [ ! -e "$H/escape.md" ] && pass "an item that climbs out of its folder is refused" || fail "item with dot-dot"
# Twenty at once for a new PR: one record, every caller gets its path.
sed -e 's/"number":12/"number":15/' -e 's#pull/12#pull/15#' "$TMP/merged.json" > "$TMP/merged15.json"
before=$(ls "$H/releases" | wc -l | tr -d ' ')
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged15.json" sh "$SCRIPT" --home "$H" --project lstn --item '#12' --pr 15 >> "$TMP/paths" 2>&1 &
done; wait
after=$(ls "$H/releases" | wc -l | tr -d ' ')
[ "$((after - before))" = 1 ] && [ "$(sort -u "$TMP/paths" | wc -l | tr -d ' ')" = 1 ] && pass "concurrent runs for one PR write one record" || fail "concurrent runs wrote $((after - before)) records, $(sort -u "$TMP/paths" | wc -l | tr -d ' ') paths"

# Second stress pass: the user indented the PR line; a replay still finds the record
python3 - "$exp" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read().replace("- PR: ", "  - PR: ", 1); open(p, "w").write(s)
PY2
n1=$(ls "$H/releases" | wc -l | tr -d ' '); out5=$(run --project lstn --item '#12' --pr 12); n2=$(ls "$H/releases" | wc -l | tr -d ' ')
[ "$out5" = "$exp" ] && [ "$n1" = "$n2" ] && pass "an edited record is still recognised as this PR's" || fail "edited record gave a second one ($out5)"
chmod 555 "$H/releases"; sed -e 's/"number":12/"number":16/' -e 's#pull/12#pull/16#' "$TMP/merged.json" > "$TMP/merged16.json"
err=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged16.json" sh "$SCRIPT" --home "$H" --project lstn --item '#12' --pr 16 2>&1); rc=$?; chmod 755 "$H/releases"
[ "$rc" -eq 1 ] && case "$err" in "error: "*) true ;; *) false ;; esac && pass "a read-only releases folder is one error line" || fail "read-only releases folder (rc=$rc: $(printf '%s' "$err" | head -1))"

# what the suite did not notice when it was broken on purpose
sed -e 's/"number":12/"number":17/' -e 's#pull/12#pull/17#' -e 's/"conclusion":"SUCCESS"/"conclusion":"FAILURE"/' "$TMP/merged.json" > "$TMP/merged17.json"
out17=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged17.json" sh "$SCRIPT" --home "$H" --project lstn --item red --pr 17)
grep -q 'Checks on the PR head at merge: ci: FAILURE' "$out17" && pass "a check that was red at merge is in the record" || fail "red check not recorded"
sed -e 's/"number":12/"number":18/' -e 's#pull/12#pull/18#' "$TMP/merged.json" > "$TMP/merged18.json"
before=$(cat "$out17"); out18=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged18.json" sh "$SCRIPT" --home "$H" --project lstn --item red --pr 18)
[ "$out18" != "$out17" ] && [ "$(cat "$out17")" = "$before" ] && grep -q 'pull/18' "$out18" && pass "a second PR for an item never rewrites the first record" || fail "first record rewritten ($out18)"
printf '{"number":19,"url":"u","state":"MERGED","reviews":{},"statusCheckRollup":[]}\n' > "$TMP/odd19.json"
err=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/odd19.json" sh "$SCRIPT" --home "$H" --project lstn --item odd --pr 19 2>&1); rc=$?
[ "$rc" -eq 1 ] && [ "$err" = "error: gh: unreadable output" ] && pass "reviews that are not a list are one error line" || fail "non-list reviews (rc=$rc: $err)"

# the evidence folder (#73): named when the worktree holds evidence; worktree-clean.sh copies it there
mkdir -p "$TMP/wt/docs/superpowers/evidence/run"; echo r > "$TMP/wt/docs/superpowers/evidence/run/report.md"
printf '| ev | ev | lstn | %s | ready | - | 1 | t | d | 0 | https://github.com/o/lstn/pull/20 | abc1234 | - | - | - | now |\n' "$TMP/wt" >> "$H/ledger.md"
sed -e 's/"number":12/"number":20/' -e 's#pull/12#pull/20#' "$TMP/merged.json" > "$TMP/merged20.json"
out20=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged20.json" sh "$SCRIPT" --home "$H" --project lstn --item ev --pr 20)
grep -qx -- "- Evidence: $H/evidence/ev/" "$out20" && pass "the record names where the item's evidence is kept" || fail "evidence line ($(grep Evidence "$out20"))"
grep -q 'under its docs root' "$out20" && fail "the record still points into a folder that will be removed" || pass "the worktree line no longer points at the evidence"
grep -qx -- '- Evidence: none found' "$out3" && pass "a worktree with no evidence says none found" || fail "no-evidence line ($(grep Evidence "$out3"))"

# lane d: the build docs line and a big evidence folder's size
grep -qx -- "- Evidence: $H/evidence/ev/" "$out20" && sed -n '/^- Evidence:/{n;p;}' "$out20" | grep -qx -- '- Build docs: none found' && pass "no spec or plan anywhere says Build docs: none found" || fail "build docs none ($(grep -A1 Evidence "$out20"))"
mkdir -p "$TMP/wt2/docs/superpowers/plans"; echo p > "$TMP/wt2/docs/superpowers/plans/p.md"
printf '| bd | bd | lstn | %s | ready | - | 1 | t | d | 0 | https://github.com/o/lstn/pull/21 | abc1234 | - | - | - | now |\n' "$TMP/wt2" >> "$H/ledger.md"
sed -e 's/"number":12/"number":21/' -e 's#pull/12#pull/21#' "$TMP/merged.json" > "$TMP/merged21.json"
out21=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged21.json" sh "$SCRIPT" --home "$H" --project lstn --item bd --pr 21)
[ "$(sed -n '/^- Evidence:/{n;p;}' "$out21")" = "- Build docs: $H/builds/bd/" ] && pass "a plan in the worktree names the builds folder right after Evidence" || fail "build docs line ($(grep -A1 Evidence "$out21"))"
mkdir -p "$H/builds/only"
printf '| only | only | lstn | - | ready | - | 1 | t | d | 0 | https://github.com/o/lstn/pull/22 | abc1234 | - | - | - | now |\n' >> "$H/ledger.md"
sed -e 's/"number":12/"number":22/' -e 's#pull/12#pull/22#' "$TMP/merged.json" > "$TMP/merged22.json"
out22=$(PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged22.json" sh "$SCRIPT" --home "$H" --project lstn --item only --pr 22)
grep -qx -- "- Build docs: $H/builds/only/" "$out22" && pass "an existing builds folder is named" || fail "builds folder only ($(grep 'Build docs' "$out22"))"
grep -q '^- Evidence: .* GB)$' "$out20" && fail "a small evidence folder got a size suffix" || pass "no size suffix under the limit"
rm -f "$out20"; out20c=$(JUEL_EVIDENCE_GB_LIMIT=0 PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged20.json" sh "$SCRIPT" --home "$H" --project lstn --item ev --pr 20)
grep -qx -- "- Evidence: $H/evidence/ev/ (0.0 GB)" "$out20c" && pass "evidence over the limit ends with its size" || fail "size suffix ($(grep Evidence "$out20c"))"

# audit lane f: evidence size leaves out the skip classes
mkdir -p "$TMP/wt3/docs/superpowers/evidence/run/tmp" "$TMP/wt3/docs/superpowers/evidence/run/b.app"
EV3="$TMP/wt3/docs/superpowers/evidence/run"
echo r > "$EV3/report.md"; head -c 2000 /dev/zero > "$EV3/app.dmg"; head -c 2000 /dev/zero > "$EV3/m.gguf"
head -c 2000 /dev/zero > "$EV3/tmp/x"; head -c 2000 /dev/zero > "$EV3/b.app/y"
python3 -c "f=open('$EV3/take.wav','wb'); f.truncate(12*1024*1024)"; head -c 100 /dev/zero > "$EV3/beep.wav"
printf '| sz | sz | lstn | %s | ready | - | 1 | t | d | 0 | https://github.com/o/lstn/pull/23 | abc1234 | - | - | - | now |\n' "$TMP/wt3" >> "$H/ledger.md"
sed -e 's/"number":12/"number":23/' -e 's#pull/12#pull/23#' "$TMP/merged.json" > "$TMP/merged23.json"
# what counts is report.md (2 bytes) and beep.wav (100 bytes)
lim=$(python3 -c "print(50/1024**3)")
o=$(JUEL_EVIDENCE_GB_LIMIT=$lim PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged23.json" sh "$SCRIPT" --home "$H" --project lstn --item sz --pr 23)
grep -q '^- Evidence: .* GB)$' "$o" && pass "a limit under the proof bytes adds a size note" || fail "size note ($(grep Evidence "$o"))"
rm -f "$o"
lim=$(python3 -c "print(500/1024**3)")
o=$(JUEL_EVIDENCE_GB_LIMIT=$lim PATH="$TMP/bin:/usr/bin:/bin" STUB_JSON="$TMP/merged23.json" sh "$SCRIPT" --home "$H" --project lstn --item sz --pr 23)
grep -q '^- Evidence: .* GB)$' "$o" && fail "skipped classes were counted ($(grep Evidence "$o"))" || pass "packages, models, temp, bundles and large audio are left out of the size count"

# audit lane f: #165 gh runs as the account star.json configures
mkdir -p "$TMP/tokbin"
cat > "$TMP/tokbin/gh" <<'GHEOF'
#!/bin/sh
printf '%s\n' "${GH_TOKEN:-none}" >> "$STUB_SEEN"
case "${GH_TOKEN:-}" in tok-star|already) cat "$STUB_JSON" ;; *) echo "GraphQL: Could not resolve to a Repository" >&2; exit 1 ;; esac
GHEOF
chmod +x "$TMP/tokbin/gh"; ln -s "$(command -v python3)" "$TMP/tokbin/python3"
printf '{"tokenCmd":"echo tok-star"}\n' > "$H/star.json"
sed -e 's/"number":12/"number":24/' -e 's#pull/12#pull/24#' "$TMP/merged.json" > "$TMP/merged24.json"
rc=0; o=$(env -u GH_TOKEN PATH="$TMP/tokbin:/usr/bin:/bin" STUB_SEEN="$TMP/seen" STUB_JSON="$TMP/merged24.json" sh "$SCRIPT" --home "$H" --project lstn --item tk --pr 24 2>&1) || rc=$?
[ "$rc" -eq 0 ] && [ -f "$o" ] && [ "$(cat "$TMP/seen")" = tok-star ] && pass "#165 with no GH_TOKEN the record is written under star.json's account" || fail "#165 token (rc=$rc: $o; $(cat "$TMP/seen" 2>/dev/null))"
rm -f "$TMP/seen" "$o"
o=$(GH_TOKEN=already PATH="$TMP/tokbin:/usr/bin:/bin" STUB_SEEN="$TMP/seen" STUB_JSON="$TMP/merged24.json" sh "$SCRIPT" --home "$H" --project lstn --item tk --pr 24 2>&1)
[ "$(cat "$TMP/seen")" = already ] && pass "#165 a GH_TOKEN already set is kept" || fail "#165 existing token ($(cat "$TMP/seen" 2>/dev/null))"
rm -f "$H/star.json"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
