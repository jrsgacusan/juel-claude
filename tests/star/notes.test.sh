#!/bin/sh
# Runs skills/star/notes.sh and library.sh against a scratch STAR folder.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/notes.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL notes.sh missing"; exit 1; }
H="$TMP/home"; mkdir -p "$H/briefs/app"
printf '{"project": {"name": "app"}}\n' > "$H/star.json"
cat > "$H/briefs/app/a.md" <<'EOT'
### D1 The hosted review comes after ready (2026-10-13, decided by the brief worker)
Context: when does the hosted review run
Decision: mark ready, then request it
Consequences: none
Source: SKILL.md:1400

### D2 Ask the reviewer again (2026-10-14, reused L-0001)
EOT
N() { sh "$ROOT/skills/star/notes.sh" --home "$H" --shelf memory --project app "$@"; }
L() { sh "$ROOT/skills/star/library.sh" --home "$H" --project app "$@"; }

out=$(N add --title 'Never post to Slack' --text 'Write a draft; the owner sends it.' --kind rule --source owner --always)
[ "$out" = "added M-0001 $H/memory/app/M-0001-never-post-to-slack.md" ] && pass "add prints id and path" || fail "add ($out)"
f="$H/memory/app/M-0001-never-post-to-slack.md"
python3 - "$f" <<'PY' && pass "front matter is the I-1 keys in order, JSON values" || fail "front matter"
import json, sys
lines = open(sys.argv[1]).read().split("\n")
assert lines[0] == "---"
end = lines.index("---", 1)
keys = [l.split(": ", 1)[0] for l in lines[1:end]]
assert keys == ["id","kind","title","status","replacedBy","always","source","since","from","fromDecision","usedBy"], keys
v = {l.split(": ",1)[0]: json.loads(l.split(": ",1)[1]) for l in lines[1:end]}
assert v["id"] == "M-0001" and v["kind"] == "rule" and v["always"] is True and v["status"] == "active" and v["usedBy"] == []
assert lines[end+1] == "Write a draft; the owner sends it."
PY
grep -qx -e '- M-0001 Never post to Slack: Write a draft; the owner sends it.' "$H/memory/app.always.md" && pass "the always file lists it" || fail "always file"
N add --title 'Tests run with npm test' --text 'npm test' >/dev/null
[ "$(N list --always | cut -f1)" = "M-0001" ] && pass "list --always" || fail "list always"
[ "$(N list | wc -l | tr -d ' ')" = "2" ] && pass "list" || fail "list"
out=$(N replace M-0001 --title 'Slack: drafts only' --text 'Drafts only, never send.' --kind rule --source owner --always)
[ "$out" = "added M-0003 $H/memory/app/M-0003-slack-drafts-only.md replaces M-0001" ] && pass "replace" || fail "replace ($out)"
grep -q '^status: "replaced"' "$f" && grep -q '^replacedBy: "M-0003"' "$f" && pass "the old note is marked, not deleted" || fail "old note"
tail -1 "$H/memory/app/M-0003-slack-drafts-only.md" | grep -qx 'Replaces M-0001.' && pass "the new note says what it replaces" || fail "replaces line"
grep -q 'M-0001' "$H/memory/app.always.md" && fail "a replaced note stays in the always file" || pass "always file drops replaced notes"
[ "$(N list | wc -l | tr -d ' ')" = "2" ] && [ "$(N list --all | wc -l | tr -d ' ')" = "3" ] && pass "list hides replaced unless --all" || fail "list --all"
N set M-0002 always=true >/dev/null && grep -q 'M-0002' "$H/memory/app.always.md" && pass "set always" || fail "set"
out=$(L add --title 'CSV over XLSX' --decision 'CSV' --why 'simpler' --source-text 'item text' --source star)
[ "$out" = "added L-0001 $H/library/app/L-0001-csv-over-xlsx.md" ] && pass "library.sh writes the library shelf" || fail "library add ($out)"
L use L-0001 b >/dev/null && grep -q '^usedBy: \["\[\[b\]\]"\]' "$H/library/app/L-0001-csv-over-xlsx.md" && pass "use appends the item" || fail "use"
L add --title x --always >/dev/null 2>&1; [ $? -eq 64 ] && pass "--always on the library is 64" || fail "library always"
out=$(N add --title 'He said "ok"
then left' --text 'x'); grep -q '^title: "He said \\"ok\\"' "${out##* }" && pass "quotes and newlines are JSON-encoded" || fail "escaping"
for n in 1 2 3 4 5; do N add --title "race $n" --text r > "$TMP/race$n" & done; wait
[ "$(cut -d' ' -f2 "$TMP"/race* | sort -u | wc -l | tr -d ' ')" = "5" ] && pass "parallel adds never share an id" || fail "race"
N path | grep -qx "$H/memory/app.always.md" && pass "path without legacy is the always file" || fail "path"

# lane b, task B2 goes below this line
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
