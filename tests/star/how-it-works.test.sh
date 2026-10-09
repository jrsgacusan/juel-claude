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
    check("codex gate", star["gate"]["model"], star["gate"]["effort"])
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
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
