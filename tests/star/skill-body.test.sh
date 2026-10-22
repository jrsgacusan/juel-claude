#!/bin/sh
# Guards on the STAR rule book: skills/star/SKILL.md and skills/star/references/*.md.
# They check the contract (names, states, kinds, report words, the owner's four lines), not the
# sentences. scripts/validate.mjs checks the protocol block, the Preflight table and the Phases.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
S="$ROOT/skills/star"
SKILL="$S/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# TEXT is SKILL.md plus every reference; BODY is the same without SKILL.md's frontmatter
cat "$SKILL" "$S"/references/*.md > "$tmp/text" 2>/dev/null
{ awk 'BEGIN{n=0} n>=2{print} /^---$/{n++}' "$SKILL"; cat "$S"/references/*.md 2>/dev/null; } > "$tmp/body"
# has <name> <text>: the text is in SKILL.md once line breaks and repeated spaces are folded
has() { tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qF -- "$2" && pass "$1" || fail "$1"; }
# hasT <name> <text>: the same over TEXT
hasT() { tr '\n' ' ' < "$tmp/text" | tr -s ' ' | grep -qF -- "$2" && pass "$1" || fail "$1"; }
# hasE <name> <regex>: an extended regex on one line of TEXT
hasE() { grep -qE -- "$2" "$tmp/text" && pass "$1" || fail "$1"; }

# Size and frontmatter
lines=$(wc -l < "$SKILL" | tr -d ' ')
[ "$lines" -le 550 ] && pass "A1 size ($lines lines)" || fail "A1 size ($lines lines)"
grep -q '^name: star$' "$SKILL" && pass "A2 name" || fail "A2 name"
desc=$(sed -n 's/^description: //p' "$SKILL")
case "$desc" in
  *"without asking"*"says go"*|*"says go"*|*"owner's go"*) fail "A3 description" ;;
  *"without asking"*) pass "A3 description" ;;
  *) fail "A3 description" ;;
esac

# References and scripts
a4=ok
for n in $(grep -oE 'references/[a-z0-9-]+\.md' "$SKILL" | sort -u); do
  b=${n#references/}
  [ -f "$S/references/$b" ] || [ -f "$ROOT/references/$b" ] || { a4="missing $n"; break; }
done
if [ "$a4" = ok ]; then
  for f in "$S"/references/*.md; do
    [ -f "$f" ] || { a4="no references folder"; break; }
    grep -q "references/$(basename "$f")" "$SKILL" || { a4="not named: $(basename "$f")"; break; }
  done
fi
[ "$a4" = ok ] && pass "A4 references exist and are named" || fail "A4 references: $a4"
a5=ok
for n in $(grep -oE '(^|[^A-Za-z/])S/[a-z-]+\.sh' "$tmp/text" | sed 's/.*S\///' | sort -u); do
  [ -f "$S/$n" ] || { a5="missing $n"; break; }
done
[ "$a5" = ok ] && pass "A5 scripts named in the text exist" || fail "A5 scripts: $a5"
a6=ok
for f in "$S"/*.sh; do
  b=$(basename "$f")
  case "$b" in person-check.sh|step-check.sh) continue ;; esac   # A7 covers these two
  grep -q "$b" "$tmp/text" && continue
  grep -l "$b" "$S"/*.sh 2>/dev/null | grep -qv "/$b$" && continue
  grep -l "$b" "$ROOT"/skills/*/SKILL.md 2>/dev/null | grep -qv '/skills/star/' && continue
  a6="$b is named nowhere"; break
done
[ "$a6" = ok ] && pass "A6 every script is named" || fail "A6 scripts: $a6"
if grep -qE 'person-check|step-check' "$tmp/body"; then
  fail "A7 removed scripts are named in the text"
elif [ -e "$S/step-check.sh" ] || [ -e "$S/person-check.sh" ]; then
  pass "A7 removed scripts ok (lane D)"
else
  pass "A7 removed scripts"
fi

# The contract
out=$(python3 - "$S/template/star.json" <<'PY'
import json, sys
want = ["schema", "maxParallel", "maxInReview", "maxBriefs", "stages", "worker", "executor", "gate",
        "tries", "mergeMethod", "baseBranch", "ownerBranches", "hostedReviewer", "hostGate",
        "progressDeadlineMin", "mcps", "notes", "gateDown", "hostedDown", "tokenCmd", "ghLogin", "run",
        "terminal", "caffeinatePid", "heartbeat", "notified", "away", "project"]
try:
    d = json.load(open(sys.argv[1]), object_pairs_hook=lambda p: p)
except Exception as e:
    print("cannot load: %s" % e); sys.exit()
keys = [k for k, _ in d]
d = dict(d)
bad = []
if keys != want: bad.append("keys %s" % keys)
if d.get("tries") != [("perStep", 3), ("rescopes", 1), ("followUpDepth", 2)]: bad.append("tries")
if d.get("mergeMethod") is not None or d.get("baseBranch") is not None: bad.append("mergeMethod/baseBranch not null")
if d.get("ownerBranches") != []: bad.append("ownerBranches")
if "ownerApproval" in d: bad.append("ownerApproval")
if "maxRounds" in dict(d.get("gate", [])): bad.append("gate.maxRounds")
print("; ".join(bad) or "ok")
PY
)
[ "$out" = ok ] && pass "A8 template (I-1)" || fail "A8 template (lane C writes it): $out"
want_states="inbox briefing needs-you queued building babysit-queued babysitting verifying post-queued posting done set-aside dropped"
got_states=$(awk '/^\| State \| Pool \| Meaning \|/{t=1;next} t&&/^\|/{split($0,c,"|");gsub(/[ `]/,"",c[2]);if(c[2]!~/^-+$/)printf "%s ",c[2];next} t{exit}' "$SKILL" | sed 's/ $//')
[ "$got_states" = "$want_states" ] && pass "A9 states (I-2)" || fail "A9 states: $got_states"
bad_kinds=$(grep -oE -- '--kind [a-z-]+' "$tmp/text" | sed 's/--kind //' | sort -u | grep -vxE 'person|set-aside|slack-reply|draft|rule|fact|decision|note')  # the last four are notes.sh kinds
[ -z "$bad_kinds" ] && pass "A10 queue kinds" || fail "A10 queue kinds: $bad_kinds"
a11=ok
for w in BRIEF SPLIT DONE RESCOPE REPORTED HELD READY MERGED POSTED reason=needs-person reason=out-of-tries \
         verify regression gate ci hosted-review conflict executor stack screen worker gh pr-draft hosted-wait ci-wait review-tool gate-lock gate-down; do
  grep -qF -- "$w" "$tmp/text" || { a11="$w"; break; }
done
[ "$a11" = ok ] && pass "A11 report words and steps (I-5)" || fail "A11 report words: $a11"

# Removed things
a12=ok
for w in go-batch go-merge ownerApproval --grant 'grant:' accept-report restart-or-drop brief-ready 'NEEDS CRITERIA' escalated confirm-id 'the batch summary and go'; do
  grep -qF -- "$w" "$tmp/text" && { a12="$w"; break; }
done
[ "$a12" = ok ] && pass "A12 removed things are gone" || fail "A12 still there: $a12"

# What must be present
a13=ok
while IFS= read -r l; do
  grep -qxF -- "$l" "$SKILL" || { a13="$l"; break; }
done <<'EOF'
- Never touch a teammate's PR or branch.
- Never force-push over work that is not STAR's own.
- Never delete anything STAR did not create.
- Never post as the owner anywhere but STAR's own PRs and tickets and the tickets it was handed; Slack replies and other drafts wait for the owner's send.
EOF
[ "$a13" = ok ] && pass "A13 the owner's four lines" || fail "A13 four lines: $a13"
a14=ok
for w in secret account screen approval access; do grep -qF -- "$w" "$SKILL" || { a14=$w; break; }; done
[ "$a14" = ok ] && pass "A14 person kinds" || fail "A14 person kinds: $a14"
a15=ok
for w in Mobbin frontend-design:frontend-design Context7; do grep -qF -- "$w" "$SKILL" || { a15=$w; break; }; done
[ "$a15" = ok ] && pass "A15 sources" || fail "A15 sources: $a15"
a16=ok
for w in tries.perStep tries.rescopes tries.followUpDepth mergeMethod baseBranch ownerBranches hostedReviewer.paused; do grep -qF -- "$w" "$tmp/text" || { a16=$w; break; }; done
[ "$a16" = ok ] && pass "A16 settings" || fail "A16 settings: $a16"
hasE "A17 merge.sh --head" 'merge\.sh.*--head'
hasE "A17 pr-verify.sh --merge-gate" 'pr-verify\.sh.*--merge-gate'
hasE "A17 pr-verify.sh --brief" 'pr-verify\.sh.*--brief'
hasT "A17 red-check-proof" 'red-check-proof'
hasE "A18 stage-start.sh close (#175)" 'stage-start\.sh.* close '
hasT "A18 trackerRef (#172)" 'trackerRef'
hasT "A18 CLAUDE.md and AGENTS.md (#169)" 'CLAUDE.md'
hasT "A18 AGENTS.md" 'AGENTS.md'
has "A19 look before asking, note after" "Before STAR asks the owner anything, it checks its notes and the project's \`CLAUDE.md\` and \`AGENTS.md\`. After an answer, it writes a note."
grep -qF '<!-- juel:protocol v9 -->' "$SKILL" && pass "A20 protocol block" || fail "A20 protocol block"
hasT "A21 review-tool is infra (R-1)" '| infra | `executor`, `stack`, `screen`, `worker`, `gh`, `pr-draft`, `hosted-wait`, `ci-wait`, `review-tool` |'
hasT "A21 gate-down is outside (R-1)" '| outside | `gate-lock`, `gate-down` |'
hasT "A22 merge.sh gets --hosted (R-4)" 'merge.sh <pr url> --head <head> --home HOME_DIR --item <item> [--hosted <login>]'
hasT "A22 FAIL settings (R-4)" 'FAIL settings:'
hasT "A23 follow-up for a proven red check is STAR's, after MERGED, once per check and base (R-3)" '<check name> fails on <base branch>'
hasT "A24 a note that did not work (R-6)" 'the note did not work'
hasT "A25 can't now stays open (R-7)" "stays open"
if grep -qF "STAR adds the item once more" "$tmp/text"; then fail "A25 can't now is never asked again"; else pass "A25 can't now is never asked again"; fi

# the rule-book lines for #176, #177, #180 and #181
has "A26 the merge gate says when behind holds it" "GitHub's merge state not blocked or dirty, and not behind when the base requires up-to-date branches"
if tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qF "not blocked, behind or dirty"; then fail "A26 the old behind wording is gone"; else pass "A26 the old behind wording is gone"; fi
hasT "A27 stages.md says behind needs a strict base" '`pr-verify.sh` reports behind only when the base requires branches to be up to date (`review-rule.sh` prints `strict`, or the rule cannot be read).'
hasT "A28 stages.md says parallel starts are safe" 'Parallel starts are safe: `stage-start.sh` holds a lock per repository around the branch step.'
for f in state recovery; do
  tr '\n' ' ' < "$S/references/$f.md" | tr -s ' ' | grep -qF 'A schema-3 home may delete an old `grants/` folder and the `grant` line in a brief'"'"'s frontmatter: nothing reads them.' && pass "A29 $f.md says an old grants/ may go" || fail "A29 $f.md says an old grants/ may go"
done

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
