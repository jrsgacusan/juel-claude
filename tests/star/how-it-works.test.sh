#!/bin/sh
# skills/star/how-it-works.html is the living doc of juel:star: its stages, states and models
# must match SKILL.md and template/star.json.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PAGE="$ROOT/skills/star/how-it-works.html"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$PAGE" ] || { echo "FAIL how-it-works.html missing"; exit 1; }
head -n 1 "$PAGE" | grep -qF '<!-- https://claude.ai/artifact/V2Qx9Cm469k1vuJvcjS2fC -->' && pass "the first line names the published page" || fail "artifact comment"
# worker-probe.sh judges progress by <H>/progress/<item>.log, the worktree's last commit and its changed files.
grep -qF 'Workers are judged by progress: their progress log, their latest commit and the files changed in their worktree.' "$PAGE" && pass "the progress sentence names the sources the probe reads" || fail "progress sentence"
# A re-scope is a brief worker in --rescope mode (SKILL.md, Re-scope mode), never STAR's own session.
grep -qF 'brief worker in re-scope mode' "$PAGE" && ! grep -qE '<td[^>]*>re-scope</td>' "$PAGE" && pass "the Stages table gives a re-scope to a brief worker" || fail "re-scope stage row"
grep -qF 'a brief worker narrows the PR' "$PAGE" && pass "the Re-scope box says a brief worker narrows the PR" || fail "re-scope box"
grep -qi 'astra' "$PAGE" && fail "the page names no astra" || pass "the page names no astra"
grep -qF 'restarts the stage on its own' "$PAGE" && pass "the page says STAR restarts a stuck stage" || fail "restart sentence"
grep -qF 'checks the gate every 30 minutes' "$PAGE" && pass "the page says what STAR does when the gate is down" || fail "gate-down sentence"
out=$(python3 - "$PAGE" "$ROOT/skills/star/SKILL.md" "$ROOT/skills/star/template/star.json" <<'PY'
import html, json, re, sys
page = open(sys.argv[1], encoding="utf-8").read()
skill = open(sys.argv[2], encoding="utf-8").read()
star = json.load(open(sys.argv[3], encoding="utf-8"))


def rows(title):
    m = re.search(r"<h2>" + re.escape(title) + r"</h2>(.*?)</table>", page, re.S)
    if not m:
        return None
    body = m.group(1).split("<tbody>", 1)[-1]
    found = []
    for tr in re.findall(r"<tr>(.*?)</tr>", body, re.S):
        cells = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)]
        if cells:
            found.append(cells)
    return found


def skill_table(after, first_col):
    part = skill.split(after, 1)[1]
    names = []
    for line in part.splitlines():
        if not line.startswith("|"):
            if names:
                break
            continue
        cell = line.split("|")[1].strip()
        m = re.fullmatch(r"`?([a-z][a-z-]*)`?", cell)
        if m and m.group(1) != first_col:
            names.append(m.group(1))
    return names


problems = []
states = rows("Item states")
if states is None:
    problems.append("no Item states table")
else:
    page_states = {s.strip() for r in states for s in r[0].split(",")}
    want = set(skill_table("| State | Pool | Meaning |", "state"))
    if page_states != want:
        problems.append(f"states differ: page only {sorted(page_states - want)}, skill only {sorted(want - page_states)}")
stages = rows("Stages")
if stages is None:
    problems.append("no Stages table")
else:
    page_stages = {r[0] for r in stages}
    workers = {r[0] for r in stages if "worker" in r[1]}
    want = set(skill_table("| Stage | Worktree | Agent | Prompt |", "stage"))
    if not want <= page_stages:
        problems.append(f"stages missing from the page: {sorted(want - page_stages)}")
    if not workers <= want:
        problems.append(f"page stages run by a worker the skill does not have: {sorted(workers - want)}")
models = rows("Models")
if models is None:
    problems.append("no Models table")
else:
    labelled = [(r[0], r[1], r[2]) for r in models if len(r) >= 3]

    def row(words):
        """The model and effort cells of the first Models row whose label names these words."""
        return next(((m, e) for label, m, e in labelled
                     if re.search(r"\b" + re.escape(words) + r"\b", label.lower())), None)

    def check(words, model, effort):
        r = row(words)
        if r is None:
            problems.append(f"no Models row names {words}")
        elif model.lower() not in r[0].lower() or r[1] != effort:
            problems.append(f"{words} row says {r[0]} / {r[1]}, star.json says {model} / {effort}")

    for stage, entry in star["stages"].items():
        check(stage, entry["model"], entry["effort"])
    check("executor", star["executor"]["model"].replace("latest-", ""), star["executor"]["effort"])
    check("codex gate", star["gate"]["model"].replace("latest-", ""), star["gate"]["effort"])
    fallback = star["gate"].get("fallback")
    if isinstance(fallback, dict):
        check("gate fallback", fallback["model"], fallback["effort"])
    coordinator = re.search(r"^\| STAR itself \| ([^|(]*?)\s*[(|]", skill, re.M)
    star_row = next((m for label, m, e in labelled if label.lower().startswith("star")), None)
    if coordinator is None:
        problems.append("SKILL.md has no | STAR itself | row")
    elif star_row is None or coordinator.group(1) not in star_row:
        problems.append(f"STAR's own model: the skill says {coordinator.group(1)}, the page says {star_row}")
print("\n".join(problems) or "ok")
PY
)
[ "$out" = ok ] && pass "stages, states and models match the skill" || { fail "drift"; echo "$out" | sed 's/^/     /'; }
# lane g: the page shows STAR's changes for issues #75 to #93
grep -qF 'with a <code>VERDICT: PASS</code> line' "$PAGE" && pass "G1 the merge gate names the receipt's VERDICT line and both carries" || fail "G1 receipt on the page"
grep -qF 'keeps the last codex PASS, so no codex round runs for it' "$PAGE" && pass "G1 a clean base merge keeps the PASS" || fail "G1 carried SAFE on the page"
grep -qF 'One merge per base branch at a time' "$PAGE" && pass "G2 the page names the merge order" || fail "G2 merge order on the page"
grep -qF '<code>refreshOutsideCap: false</code>' "$PAGE" && pass "G2 the page names refreshOutsideCap" || fail "G2 refreshOutsideCap on the page"
grep -qF 'babysit merges the base in before asking for it' "$PAGE" && pass "G2 the last pass reviews a current head" || fail "G2 last pass on the page"
grep -qF 'so two sessions never work on one item' "$PAGE" && pass "G3 the page says a stopped worker's terminal is closed" || fail "G3 stopped worker on the page"
grep -qF 'takes your answer as that value' "$PAGE" && pass "G4 the page says a step can take a value" || fail "G4 value step on the page"
grep -qF 'its blockers and any not-before date' "$PAGE" && pass "G5 the queued state names the not-before date" || fail "G5 notBefore on the page"
grep -qF 'set <code>tokenCmd</code> in <code>star.json</code> once' "$PAGE" && pass "G6 the page says how a repository gh cannot see gets its token" || fail "G6 tokenCmd on the page"
# lane h: the page shows STAR's changes for issues #94 to #108
grep -qF 'once any person-only step the narrowed brief adds is done, even under your go' "$PAGE" && pass "LH2 the re-scope waits for its person-only steps (#101)" || fail "LH2 re-scope steps on the page"
grep -qF 'A file-name or id form is named only by quoting the check that enforces it' "$PAGE" && pass "LH3 a brief names a form only from the repo's own check (#107)" || fail "LH3 name forms on the page"
grep -qF 'goes into the brief'"'"'s decisions before it is sent' "$PAGE" && pass "LH3 a standing rule is logged before it is sent (#99)" || fail "LH3 standing rules on the page"
grep -qF '(a session Orca reports released with no retained reason is ended; one a person kept is still kept or held)' "$PAGE" && pass "LH4 a released session is ended (#95)" || fail "LH4 released session on the page"
grep -qF 'The full regression gate and every live check run once per PR, before the first draft push.' "$PAGE" && pass "LH5 the full gate runs once per PR (#102)" || fail "LH5 gate once on the page"
grep -qF 'plus a sweep that runs every test file once' "$PAGE" && pass "LH5 later pushes run the sweep (#102)" || fail "LH5 sweep on the page"
grep -qF 'A head GitHub ran no CI on, while the PR does not conflict, comes to you.' "$PAGE" && pass "LH5 a head with no CI comes to you (#102)" || fail "LH5 ci-missing on the page"
grep -qF 'When the record of passes is missing, babysit rebuilds it from the PR'"'"'s reviews and Greptile'"'"'s summary comments first' "$PAGE" && pass "LH6 a missing pass record is rebuilt (#96, #116)" || fail "LH6 hosted log on the page"
grep -qF '>gates · push · ≤ 3 NOT-SAFE</text>' "$PAGE" && grep -qF '>3 NOT-SAFE in a row</text>' "$PAGE" && pass "LH6 the drawing counts NOT-SAFE rounds in a row (#108)" || fail "LH6 round budget in the drawing"
grep -qF 'after 3 NOT-SAFE rounds in a row or a second Greptile pass' "$PAGE" && pass "LH6 the drawing's label says the same (#108)" || fail "LH6 round budget in the aria-label"
grep -qF 'In babysit the count starts over at each SAFE round and each push' "$PAGE" && pass "LH6 a base merge after a SAFE round gets a fresh budget (#108)" || fail "LH6 round budget on the page"
grep -qF 'a direct verdict supersedes a carry' "$PAGE" && pass "LH7 a direct PASS supersedes a carried one (#104)" || fail "LH7 direct receipt on the page"
grep -qF 'git'"'"'s read-only commands (a denied run is retried once in the same round)' "$PAGE" && pass "LH7 the fallback's git reads and its retry (#100)" || fail "LH7 fallback reads on the page"
# fix: a released session a person kept is still kept or held (#95)
grep -qF 'ended, never held' "$PAGE" && fail "F95 the page no longer says a released session is never held" || pass "F95 the page no longer says a released session is never held"
grep -qF 'one a person kept is still kept or held' "$PAGE" && pass "F95 the page says a released session a person kept is still kept or held" || fail "F95 released session a person kept on the page"
# lane h: the page shows STAR's changes for issues #110 to #118 and the mod
grep -qF 'carried to it from a gated head by a base merge that changed none of the files the branch changes' "$PAGE" && pass "LH110 the merge gate's carry names the rule (#110)" || fail "LH110 carry rule in the merge gate"
grep -qF 'A base merge that changed none of the files the branch changes keeps the last codex PASS, so no codex round runs for it.' "$PAGE" && pass "LH110 a base merge keeps the PASS only when it changed none of the branch's files (#110)" || fail "LH110 carry rule in Never stalls"
grep -qF 'a script proves adds nothing of its own' "$PAGE" && fail "LH110 the old carry wording is gone (#110)" || pass "LH110 the old carry wording is gone (#110)"
grep -qF 'A gate round on a base that moved and changed the branch'"'"'s own files merges the base in first, so the round reviews a current head.' "$PAGE" && pass "LH113 a moved base that touches the branch is merged before the round (#113)" || fail "LH113 base-moved on the page"
grep -qF 'a push that only merges the base runs the sweep, after a clean merge too.' "$PAGE" && pass "LH111 a push that only merges the base runs the sweep (#111)" || fail "LH111 sweep after a base merge on the page"
grep -qF 'runs the tests for the files its conflicts changed' "$PAGE" && fail "LH111 the conflicted-files rule is gone (#111)" || pass "LH111 the conflicted-files rule is gone (#111)"
grep -qF 'Feedback you give while an item'"'"'s brief is still drafting lands in that brief.' "$PAGE" && pass "LH112 feedback given while a brief drafts lands in it (#112)" || fail "LH112 feedback while drafting on the page"
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
