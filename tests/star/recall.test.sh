#!/bin/sh
# Runs skills/star/recall.sh against a scratch STAR folder.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/recall.sh"
LEDGER="$ROOT/skills/star/ledger.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL recall.sh missing"; exit 1; }
H="$TMP/home"; mkdir -p "$H/briefs/app" "$H/releases" "$H/library/app" "$H/memory/app"
cp "$ROOT/skills/star/template/ledger.md" "$H/ledger.md"
printf '{"project": "app"}\n' > "$H/star.json"
L() { sh "$LEDGER" --home "$H" "$@" >/dev/null; }
L add a ref=a project=app; L add b ref=b project=app; L add c ref=c project=app; L add d ref=d project=app
L set d state=dropped

cat > "$H/briefs/app/a.md" <<'EOF'
---
approved: 2026-10-13T10:00:00Z
---
# Brief a

## Decisions

### D1 The hosted review comes after ready (2026-10-13, decided by the brief worker)
Context: the review needs a ready PR
Decision: mark the PR ready, then request the hosted review
Consequences: one more step
Source: SKILL.md

### D2 CSV over XLSX (2026-10-13, decided by the brief worker)
Context: export format
Decision: write CSV
- 2026-10-14 answer: keep the cap at 10,000 rows
EOF
cat > "$H/briefs/app/b.md" <<'EOF'
---
approved: 2026-10-14T10:00:00Z
---
## Decisions

### D1 Ready before review (2026-10-14, decided by the brief worker)
Decision: the hosted review is asked for after the PR is ready
Status: Superseded by D3 (owner feedback, 2026-10-14)
EOF
cat > "$H/briefs/app/c.md" <<'EOF'
---
title: draft
---
## Decisions

### D1 Draft hosted review (2026-10-14, decided by the brief worker)
Decision: hosted review
EOF
cat > "$H/briefs/app/d.md" <<'EOF'
---
approved: 2026-10-14T10:00:00Z
---
## Decisions

### D1 Dropped hosted review (2026-10-14, decided by the brief worker)
Decision: hosted review
EOF
printf '# app · a · Ship CSV export\n\nMerged. The export is CSV.\n' > "$H/releases/2026-10-15-app-a.md"
R() { sh "$SCRIPT" --home "$H" "$@"; }

R hosted review | head -1 | grep -q '^decision a#D1 · active · The hosted review comes after ready · ' && pass "a title match ranks first" || fail "rank ($(R hosted review))"
R hosted review | grep -q '^decision b#D1' && fail "a superseded decision is shown" || pass "superseded decisions are hidden"
R hosted review | tail -1 | grep -qx 'hidden 1 replaced or superseded' && pass "the hidden count is the last line" || fail "hidden line"
R --all hosted review | grep -q '^decision b#D1 · superseded · ' && pass "--all shows it" || fail "--all"
R hosted review | grep -qE '^decision (c|d)#' && fail "an unapproved or dropped brief is indexed" || pass "only approved, not dropped briefs"
R keep the cap | grep -q '10,000' && fail "a dated answer line was indexed into D2" || pass "a dated answer line ends the block"
R --kind release csv export | grep -q '^release 2026-10-15-app-a · merged · Ship CSV export · ' && pass "release records" || fail "release ($(R --kind release csv export))"
[ "$(R nothing-matches-this)" = "none" ] && pass "no hit prints none" || fail "none"
R --json hosted review | head -1 | python3 -c 'import json,sys; d=json.loads(sys.stdin.readline()); assert d["kind"]=="decision" and d["ref"]=="a#D1" and d["item"]=="a" and d["status"]=="active" and d["path"]=="briefs/app/a.md" and d["project"]=="app" and d["date"]=="2026-10-13" and "excerpt" in d and "title" in d' && pass "--json is one object per hit" || fail "--json"
[ -z "$(R --json nothing-matches-this)" ] && pass "--json prints nothing for no hit" || fail "--json none"
[ "$(R --limit 1 hosted review | grep -vc '^hidden')" = "1" ] && pass "--limit caps the hits" || fail "limit"
R --limit 21 x >/dev/null 2>&1; [ $? -eq 64 ] && pass "a limit over 20 is 64" || fail "limit 21"
R '"' >/dev/null 2>&1; [ $? -eq 64 ] && pass "no searchable word is 64" || fail "empty query"
[ "$(sh "$SCRIPT" --home "$H" rebuild)" = "indexed 3 files" ] && pass "rebuild counts only the files it indexed" || fail "rebuild ($(sh "$SCRIPT" --home "$H" rebuild))"
# lane a: library and memory notes, staleness, a broken cache
cat > "$H/library/app/L-0001-the-hosted-review-comes-after-ready.md" <<'EOF'
---
id: "L-0001"
kind: "decision"
title: "The hosted review comes after ready"
status: "active"
replacedBy: null
always: false
source: "brief-worker"
since: "2026-10-13"
from: "[[a]]"
fromDecision: "D1"
usedBy: []
---
Decision: mark the PR ready, then request the hosted review
Why: the review needs a ready PR
Source: SKILL.md
EOF
cat > "$H/library/app/L-0002-old-rule.md" <<'EOF'
---
id: "L-0002"
kind: "decision"
title: "Review before ready"
status: "replaced"
replacedBy: "L-0001"
always: false
source: "brief-worker"
since: "2026-10-01"
from: null
fromDecision: null
usedBy: []
---
Decision: request the review before the PR is ready
Why: none
Source: none
EOF
cat > "$H/memory/app/M-0001-never-post-to-slack.md" <<'EOF'
---
id: "M-0001"
kind: "rule"
title: "Never post to Slack"
status: "active"
replacedBy: null
always: true
source: "owner"
since: "2026-10-12"
from: null
fromDecision: null
usedBy: []
---
Never post to Slack; write a draft.
EOF
R --kind decision hosted review | head -1 | grep -q '^library L-0001 · active · The hosted review comes after ready · ' && pass "the library ranks above briefs" || fail "library first ($(R --kind decision hosted review))"
R --kind decision review before ready | grep -q 'L-0002' && fail "a replaced note is shown" || pass "replaced notes are hidden"
R --kind note slack | grep -q '^note M-0001 · active · Never post to Slack' && pass "memory notes" || fail "note"
R --kind note hosted review | grep -q '^decision' && fail "--kind note shows decisions" || pass "--kind filters"
# a changed brief is re-read on the next search
sleep 1; sed -i '' 's/CSV over XLSX/Parquet over CSV/' "$H/briefs/app/a.md"
R parquet | grep -q '^decision a#D2' && pass "a changed file is re-indexed" || fail "staleness"
# a removed file leaves the index
rm "$H/releases/2026-10-15-app-a.md"; R --kind release csv export | grep -q release && fail "a removed file stays" || pass "a removed file is dropped"
# a damaged or deleted cache is rebuilt, never an error
printf 'not a database' > "$H/index.db"; R hosted review | head -1 | grep -q 'L-0001' && pass "a damaged index is rebuilt" || fail "damaged index"
rm -f "$H/index.db"*; R hosted review | grep -q 'L-0001' && pass "a missing index is rebuilt" || fail "missing index"
# FTS syntax in the words is just words
R 'hosted* AND "review' 'NEAR(' ':ready' | grep -q 'L-0001' && pass "FTS syntax is quoted away" || fail "syntax"
# a brief with no front matter end or no Decisions is skipped quietly
printf -- '---\napproved: x\n## Decisions\n### D1 Broken\n' > "$H/briefs/app/e.md"; R broken >/dev/null 2>&1; [ $? -eq 0 ] && pass "a malformed brief does not fail a search" || fail "malformed"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
