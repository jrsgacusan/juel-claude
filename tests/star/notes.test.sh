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

# lane b, task B2: promote, split, apply and the legacy mode
out=$(L promote a#D1 --source brief-worker); id=${out#added }; id=${id%% *}
f=$(echo "$out" | cut -d' ' -f3)
grep -q '^title: "The hosted review comes after ready"' "$f" && grep -q '^from: "\[\[a\]\]"' "$f" && grep -q '^fromDecision: "D1"' "$f" && grep -q '^since: "2026-10-13"' "$f" && pass "promote takes the record" || fail "promote ($out)"
grep -qx 'Decision: mark ready, then request it' "$f" && grep -qx 'Why: when does the hosted review run' "$f" && grep -qx 'Source: SKILL.md:1400' "$f" && pass "promote's body" || fail "promote body"
[ "$(L promote a#D1)" = "exists $id" ] && pass "promote twice writes nothing" || fail "promote again"
L promote a#D9 >/dev/null 2>&1; [ $? -eq 1 ] && pass "a missing record is exit 1" || fail "missing D"
# D2's heading says reused L-0001: superseding it replaces L-0001
printf '### D3 Ask once (2026-10-15, decided by the brief worker)\nContext: c\nDecision: d\nConsequences: e\nSource: s\n' >> "$H/briefs/app/a.md"
L promote a#D3 --source owner --supersedes a#D2 | grep -q ' replaces L-0001$' && pass "--supersedes finds the reused note" || fail "supersedes"
N promote a#D1 >/dev/null 2>&1; [ $? -eq 64 ] && pass "promote on memory is 64" || fail "promote memory"
# split a legacy file
H2="$TMP/h2"; mkdir -p "$H2/memory"; printf '{"project": {"name": "app"}, "notes": "legacy"}\n' > "$H2/star.json"
cat > "$H2/memory/app.md" <<'EOT'
# app notes

- 2026-10-07 user: tracker is Linear. Move each ticket's status.
  Statuses: Todo, In Progress, Done.
- 2026-10-08 SPH-60: w0 and w1 lag real time after a sleep.
- a bullet with no date
EOT
N2() { sh "$ROOT/skills/star/notes.sh" --home "$H2" --shelf memory --project app "$@"; }
[ "$(N2 split "$H2/memory/app.md")" = "split 3" ] && pass "one note per bullet" || fail "split"
grep -l 'Statuses: Todo' "$H2"/memory/app/M-*.md | xargs grep -q '^source: "owner"' && pass "a continuation line stays with its bullet; user is owner" || fail "continuation"
grep -l 'lag real time' "$H2"/memory/app/M-*.md | xargs grep -q '^source: "migration"' && pass "any other author is migration" || fail "author"
[ "$(N2 split "$H2/memory/app.md")" = "split 0 already" ] && pass "split is idempotent" || fail "split twice"
[ "$(N2 path)" = "$H2/memory/app.md" ] && pass "legacy path is the old file" || fail "legacy path"
N2 add --title 'New fact' --text 'learned today' >/dev/null; tail -1 "$H2/memory/app.md" | grep -q ': learned today$' && pass "legacy add also appends to the old file" || fail "legacy append"
# apply a proposal
printf '{"project": {"name": "app"}, "notes": "legacy", "standing": {"a": 1}}\n' > "$H2/star.json"
cat > "$TMP/proposal.md" <<'EOT'
Some prose the worker wrote.
M-0001 kind=rule always=true status=active why=owner policy
M-0002 kind=fact always=false status=replaced why=sleep bug fixed
M-0099 kind=fact always=false status=active
EOT
[ "$(N2 apply "$TMP/proposal.md" 2>/dev/null)" = "applied kind=1 always=1 replaced=1" ] && pass "apply" || fail "apply ($(N2 apply "$TMP/proposal.md" 2>&1))"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["notes"]=="split" and "standing" not in d and d["standingPreNotes"]=={"a":1}' "$H2/star.json" && pass "apply ends legacy and keeps the standing orders aside" || fail "apply star.json"
[ "$(N2 path)" = "$H2/memory/app.always.md" ] && pass "after apply, path is the always file" || fail "path after apply"
printf 'no lines here\n' > "$TMP/empty.md"; N2 apply "$TMP/empty.md" >/dev/null 2>&1; [ $? -eq 2 ] && pass "a proposal with no line is exit 2" || fail "empty proposal"
# review fixes: show, replace keeps kind and always, --once, migration notes stay out of the old file, split guard and dates
H3="$TMP/h3"; mkdir -p "$H3/memory"; printf '{"project": {"name": "app"}}\n' > "$H3/star.json"
N3() { sh "$ROOT/skills/star/notes.sh" --home "$H3" --shelf memory --project app "$@"; }
N3 add --title 'Never post to Slack' --text 'Write a draft; the owner sends it.' --kind rule --source owner --always >/dev/null
[ "$(N3 show M-0001)" = "M-0001 Never post to Slack: Write a draft; the owner sends it." ] && pass "show prints the whole note on one line" || fail "show ($(N3 show M-0001))"
long="word0 word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12 word13 word14 word15 word16 word17 word18 word19 word20 word21 word22 word23 word24 word25 word26 word27 word28 word29"
N3 add --title 'Long rule' --text "$long" >/dev/null
N3 show M-0002 | grep -q 'word29$' && pass "show is never cut" || fail "show cut"
N3 show M-0099 >/dev/null 2>&1; [ $? -eq 1 ] && pass "show of a missing id is exit 1" || fail "show missing"
N3 replace M-0001 --title 'Slack: drafts only' --text 'Drafts only, never send.' --source owner >/dev/null
grep -q '^kind: "rule"' "$H3"/memory/app/M-0003-*.md && grep -q '^always: true' "$H3"/memory/app/M-0003-*.md && pass "replace keeps the old note's kind and always" || fail "replace inherits"
grep -qx -e '- M-0003 Slack: drafts only: Drafts only, never send.' "$H3/memory/app.always.md" && pass "the reworded rule stays in the always file" || fail "always after replace ($(cat "$H3/memory/app.always.md"))"
N3 add --title 'Tests run with npm test' --text 'Tests run with npm test before every push.' --always >/dev/null
grep -qx -e '- M-0004 Tests run with npm test before every push.' "$H3/memory/app.always.md" && pass "a title that starts the text is not printed twice" || fail "doubled title"
[ "$(N3 add --title maxParallel --text 'two at most' --kind rule --source migration --once | cut -d' ' -f1)" = "added" ] && [ "$(N3 add --title maxParallel --text 'two at most' --kind rule --source migration --once)" = "exists M-0005" ] && pass "--once writes a note once" || fail "--once"
# migration notes never reach the old file, which workers still read
H4="$TMP/h4"; mkdir -p "$H4/memory"; printf '{"project": {"name": "app"}}\n' > "$H4/star.json"
printf -- '- 2026-10-07 user: tracker is Linear.\n- 2026-10-12 on the warm server: skip pilot mode.\n- 2026-10-13T21:11:43Z owner dropped SPH-9.\n' > "$H4/memory/app.md"; cp "$H4/memory/app.md" "$TMP/h4-before.md"
N4() { sh "$ROOT/skills/star/notes.sh" --home "$H4" --shelf memory --project app "$@"; }
N4 split "$H4/memory/app.md" >/dev/null
N4 add --title blanketGo --text 'go for everything tonight' --kind rule --source migration >/dev/null
cmp -s "$H4/memory/app.md" "$TMP/h4-before.md" && pass "a migration note is not appended to the old file" || fail "migration append"
grep -l 'warm server' "$H4"/memory/app/M-*.md | xargs grep -q '^since: "2026-10-12"' && pass "a dated bullet with no author keeps its date" || fail "date without author"
grep -l 'dropped SPH-9' "$H4"/memory/app/M-*.md | xargs grep -q '^since: "2026-10-13"' && pass "a date with a time keeps its date" || fail "date with time"
grep -l 'dropped SPH-9' "$H4"/memory/app/M-*.md | xargs grep -q '^2026-10-13T21:11:43Z owner dropped SPH-9.$' && pass "the time stays in the text" || fail "time kept"
# an owner-only file split twice is still split once
H5="$TMP/h5"; mkdir -p "$H5/memory"; printf '{"project": {"name": "app"}}\n' > "$H5/star.json"
printf -- '- 2026-10-07 user: one.\n- 2026-10-08 owner: two.\n' > "$H5/memory/app.md"
N5() { sh "$ROOT/skills/star/notes.sh" --home "$H5" --shelf memory --project app "$@"; }
[ "$(N5 split "$H5/memory/app.md")" = "split 2" ] && [ "$(N5 split "$H5/memory/app.md")" = "split 0 already" ] && [ "$(ls "$H5"/memory/app/M-*.md | wc -l | tr -d ' ')" = "2" ] && pass "a file of owner notes splits once" || fail "owner-only split twice"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
