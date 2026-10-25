#!/bin/sh
# skills/star/how-it-works.html is the living doc of juel:star: its stages, states and models
# must match SKILL.md and template/star.json.
# docs/star-closed-loop.html is the same living page, kept under docs/: this page without its first line.
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
grep -qF 'its blockers and its not-before time' "$PAGE" && pass "G5 the queued state names the not-before time" || fail "G5 notBefore on the page"
grep -qF 'set <code>tokenCmd</code> in <code>star.json</code> once' "$PAGE" && pass "G6 the page says how a repository gh cannot see gets its token" || fail "G6 tokenCmd on the page"
# lane h: the page shows STAR's changes for issues #94 to #108
grep -qF 'once any person item the narrowed brief adds is done' "$PAGE" && pass "LH2 the re-scope waits for its person items (#101)" || fail "LH2 re-scope steps on the page"
grep -qF 'A file-name or id form is named only by quoting the check that enforces it' "$PAGE" && pass "LH3 a brief names a form only from the repo's own check (#107)" || fail "LH3 name forms on the page"
grep -qF 'goes into the brief'"'"'s decisions before it is sent' "$PAGE" && pass "LH3 a standing rule is logged before it is sent (#99)" || fail "LH3 standing rules on the page"
grep -qF '(a session Orca reports released with no retained reason is ended; one a person kept is still kept or held)' "$PAGE" && pass "LH4 a released session is ended (#95)" || fail "LH4 released session on the page"
grep -qF 'The full regression gate and every live check run once per PR, before the first draft push.' "$PAGE" && pass "LH5 the full gate runs once per PR (#102)" || fail "LH5 gate once on the page"
grep -qF 'plus a sweep that runs every test file once' "$PAGE" && pass "LH5 later pushes run the sweep (#102)" || fail "LH5 sweep on the page"
grep -qF 'A head GitHub ran no CI on, while the PR does not conflict, waits like a check that has not reported and spends a try only after 60 minutes.' "$PAGE" && pass "LH5 a head with no CI waits, then spends a try (#102)" || fail "LH5 ci-missing on the page"
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
grep -qF 'A worker sitting on a prompt is seen on its screen. STAR answers Claude Code'"'"'s safety prompt for an <code>rm</code> inside the item'"'"'s worktree or a scratchpad, and any other prompt comes to you.' "$PAGE" && pass "LH114 a prompt is seen, the bounded one answered (#114)" || fail "LH114 prompts on the page"
grep -qF 'On Claude Code 2.1.287 and later, a band above STAR'"'"'s prompt shows the pools and what needs you, three items at a time, and you answer them right there' "$PAGE" && pass "LHmod the page shows the band, answered in place" || fail "LHmod band on the page"
grep -qF 'With cswap installed it also shows each account'"'"'s usage and the one in use, and whether cswap'"'"'s auto-switch is running; STAR never starts it.' "$PAGE" && pass "LHmod the page shows the cswap accounts, read-only (#182)" || fail "LHmod cswap on the page"
grep -qF 'starts <code>cswap auto</code>' "$PAGE" && fail "#182 the page still says STAR starts cswap auto" || pass "#182 the page no longer says STAR starts cswap auto"
grep -qF 'synced at once: base merged in, gated, pushed. The push waits while a hosted review pass is running, so it never cuts that pass short.' "$PAGE" && pass "#179 a conflict push waits for a running hosted pass" || fail "#179 the conflict push on the page"
grep -qF 'GitHub reports it mergeable, so branch rules still apply; a PR behind its base passes when the base does not require branches to be up to date' "$PAGE" && pass "#180 a behind PR passes on a base that does not require up-to-date branches" || fail "#180 behind on the page"
grep -qF 'a direct <code>gh pr merge</code> is refused in STAR'"'"'s session and its workers, and so is reading a review, evidence, report or log file into STAR'"'"'s session.' "$PAGE" && pass "LHmod the page shows the guards" || fail "LHmod guards on the page"
# the STAR dashboard (star-dashboard-server)
grep -qF '<code>/juel:star dashboard</code> opens one local page for every STAR project on this Mac' "$PAGE" && pass "DASH the page names the dashboard" || fail "DASH dashboard on the page"
grep -qF 'When STAR has a pick on something it asks you, it marks the option it recommends and says why in one line, never for a secret.' "$PAGE" && pass "DASH the page names STAR picks" || fail "DASH picks on the page"
# the docs copy: docs/star-closed-loop.html changes in the same commit as this page
DOCS="$ROOT/docs/star-closed-loop.html"
if [ -f "$DOCS" ] && tail -n +2 "$PAGE" | cmp -s - "$DOCS"; then
  pass "docs/star-closed-loop.html is this page without its first line"
else
  fail "docs/star-closed-loop.html differs from this page: run tail -n +2 skills/star/how-it-works.html > docs/star-closed-loop.html"
fi
# #119 to #123: the page shows each change
grep -qF 'A previous terminal Orca no longer lists is gone and never holds a start' "$PAGE" && grep -qF 'sitting at an empty prompt with the recap of Claude Code as its newest lines, counts as quiet' "$PAGE" && pass "I119 a closed or recap-only terminal never holds a start (#119)" || fail "I119 previous terminal on the page"
grep -qF 'The worker resolves a conflict itself, keeping both changes'"'"' intent' "$PAGE" && ! grep -qi 'merge-union' "$PAGE" && pass "MU the worker resolves a conflict, merge-union is gone" || fail "MU conflict resolution on the page"
grep -qF 'and sourced decisions, and the item is queued, on a branch of its own that no other item, remote branch or local branch already uses' "$PAGE" && pass "I121 a brief names a branch of its own (#121)" || fail "I121 branch on the page"
grep -qF 'One pass per head: a second run on a head already reviewed is a refresh, never a pass' "$PAGE" && grep -qF 'the build never pings Greptile, since marking the PR ready starts its run' "$PAGE" && pass "I122 one hosted pass per head (#122)" || fail "I122 hosted passes on the page"
grep -qF 'or left at an empty prompt under an <code>API Error:</code> line (a connection lost or a server error mid-response), gets up to three retry nudges in one silent stretch, shared by both' "$PAGE" && grep -qF 'A progress line comes only from the step it names, never from a timer the worker left running' "$PAGE" && pass "I123 an API error at the prompt is nudged (#123)" || fail "I123 API error on the page"

# star-issues-remaining: the page shows #124 #125 #126 #129 #131 #137
grep -qF 'ownerApproval' "$PAGE" && fail "R124 ownerApproval on the page" || pass "R124 the page names no ownerApproval"
grep -qF 'A spec file outside the STAR folder is copied into it at ingest, with the files it names' "$PAGE" && pass "R125 the page says an outside spec is copied in" || fail "R125 import on the page"
grep -qF 'a worker merges the base in only when the PR conflicts or a gate round refuses with base-moved' "$PAGE" && pass "R126 the page states the one base-merge rule" || fail "R126 base-merge rule on the page"
grep -qF 'A hosted review that reviewed nothing (a usage limit) is not a pass: STAR parks every babysit and starts them again after 30 minutes, never merging past the reviewer and asking nobody.' "$PAGE" && pass "R129 the page says a skipped hosted review parks babysits and asks nobody" || fail "R129 hosted down on the page"
grep -qF 'The codex gate names every site of a finding class in one finding' "$PAGE" && pass "R131 the page names finding classes" || fail "R131 finding classes on the page"
grep -qF 'With no <code>tokenCmd</code>, every worker acts as the same GitHub account STAR does.' "$PAGE" && pass "R137 the page says workers act as STAR's account" || fail "R137 ghLogin on the page"
grep -qF "STAR's own scripts use that account too, whatever account the keyring has active." "$PAGE" && pass "R137b the page says STAR's scripts use the configured account" || fail "R137b STAR's scripts on the page"

# lane b: the page shows chat, the background wait and away; the Slack drafter is gone (#184)
grep -qF 'STAR ingests it, woken within seconds by a message wait that runs in the background' "$PAGE" && pass "LB1 the drawing's label names the background wait" || fail "LB1 background wait in the aria-label"
grep -qF '>Background message wait</text>' "$PAGE" && pass "LB1 the drawing shows the background wait" || fail "LB1 background wait in the drawing"
grep -qF 'STAR waits for worker messages in the background, one wait at a time, so a chat message, a nudge or your own words reach it within seconds.' "$PAGE" && pass "LB1 Never stalls names the background wait" || fail "LB1 background wait in Never stalls"
grep -qF 'or chat with STAR from the dashboard, which answers in the thread' "$PAGE" && pass "LB2 the drawing's label names chat" || fail "LB2 chat in the aria-label"
grep -qF '>From the dashboard</text>' "$PAGE" && grep -qF '>chat: STAR replies in the thread</text>' "$PAGE" && pass "LB2 the drawing shows chat" || fail "LB2 chat in the drawing"
grep -qF 'A chat message is you: STAR does what it asks within its hard rules, turns work on the code into an item, files work on the plugin itself as an issue, and asks you only for a step a person must do.' "$PAGE" && pass "LB2 the page says a chat message is you" || fail "LB2 chat as the owner on the page"
grep -qF 'acting only through its own rules' "$PAGE" && fail "LB2 the page still limits chat to STAR's rules" || pass "LB2 the page no longer limits chat to STAR's rules"
grep -qF 'On an iPhone, open that link in Safari and add it to the home screen: the icon opens the dashboard full screen, signed in.' "$PAGE" && pass "PWA the page names the home screen" || fail "PWA home screen on the page"
grep -qF 'A Claude review in a shape the gate cannot read runs once more, then is retried without spending the round.' "$PAGE" && pass "#185 the page names the fallback re-run" || fail "#185 fallback re-run on the page"
grep -qi 'slack' "$PAGE" && fail "#184 the page still mentions Slack" || pass "#184 the page has no Slack"
grep -qF 'Its away switch does what <code>/juel:star away</code> and <code>back</code> do, and STAR posts what still needs you into the chat.' "$PAGE" && pass "LB3 the page names the away switch" || fail "LB3 away switch on the page"
grep -qF 'a reply STAR drafted in your voice' "$PAGE" && fail "LB4 the page no longer says STAR drafts" || pass "LB4 the page no longer says STAR drafts"
grep -qF 'from a phone you reach it over your tailnet: <code>/juel:star dashboard --tailnet</code> maps it with <code>tailscale serve</code>, never <code>tailscale funnel</code>, and prints the link; the server itself stays on 127.0.0.1.' "$PAGE" && pass "LB5 the page says how to reach the dashboard from a phone" || fail "LB5 tailscale serve on the page"
grep -qF 'and a gate that prints nothing for 15 minutes is stopped and reported as stalled, so it never holds every build.' "$PAGE" && pass "LB6 a stalled gate is stopped and reported (#143)" || fail "LB6 stalled gate on the page"
# lane e: the page shows #147 #150 #151 #152 #154
grep -qF 'A step you turn down in words goes back to the brief worker, which plans without it.' "$PAGE" && pass "E150p a declined step on the page" || fail "E150p declined step on the page"
grep -qF 'go all' "$PAGE" && fail "E151p go all on the page" || pass "E151p the page has no go all"
grep -qF '<li>A criterion only CI can prove is not failed in a codex round while its check has not reported: the merge gate needs every check green on the head. A red check, or a change to the check itself, is still a finding.</li>' "$PAGE" && pass "E147p a CI-proven criterion on the page" || fail "E147p CI criterion on the page"
grep -qF '<li>Plan tasks only a session can run (a live measurement, a screen, a browser profile) run in the build worker'"'"'s own session, and codex runs the rest.</li>' "$PAGE" && pass "E154p session tasks on the page" || fail "E154p session tasks on the page"
# #155 to #161: quiet hours are gone; the executor stop, the login restart and the PR hand-over are on the page
! grep -qiE 'quiet hours|quiet window' "$PAGE" && pass "Q157p the page has no quiet hours" || fail "Q157p quiet hours on the page"
grep -qF '<li>Away holds nothing: it only limits notifications to what needs you. STAR marks ready, pings reviewers and merges as soon as the gates hold, at any hour.</li>' "$PAGE" && pass "Q157q away and outward actions on the page" || fail "Q157q away on the page"
grep -qF 'Every codex dispatch names the session task it stops before and the task it resumes at, so both hold even where Codex did not load the executor skill' "$PAGE" && grep -qF '<code>CODEX_HOME</code> included.</li>' "$PAGE" && pass "C158p the executor stop and CODEX_HOME on the page" || fail "C158p executor stop on the page"
grep -qF 'The probe checks the login in the worker'"'"'s own folder and shell, so it reads the profile the worker really uses' "$PAGE" && pass "LG156p the login restart on the page" || fail "LG156p login restart on the page"
grep -qF 'every blocking finding in a harness the build marked tooling (graded for safety only) goes on under one follow-up that continues the same PR with a fresh round budget, and the parent closes when the follow-up merges.</li>' "$PAGE" && pass "HO159p the PR hand-over on the page" || fail "HO159p hand-over on the page"
# STAR remembers: the decision library, notes that apply, kept build docs
grep -qF 'Before deciding, a brief worker searches the decisions already taken, in this project'"'"'s library and in every approved brief (<code>recall.sh</code>, one line per hit).' "$PAGE" && pass "R1 the brief worker searches before deciding" || fail "R1 search before deciding on the page"
grep -qF 'so you correct a call once. The digest in the dashboard chat lists reused decisions apart from new ones.</li>' "$PAGE" && pass "R2 the library and reused decisions" || fail "R2 library on the page"
grep -qF 'STAR searches the library before it answers a worker'"'"'s product call, so a mid-build answer never undoes your correction.</li>' "$PAGE" && pass "R3 STAR answers from the library" || fail "R3 STAR's product calls on the page"
grep -qF 'A sort-memory-notes report ends with a message in the dashboard chat saying where its proposal is and how to apply it; STAR never applies it unread, and until you do, workers read the old notes file.' "$PAGE" && pass "R4 the sort-memory-notes report" || fail "R4 sorting notes on the page"
grep -qF '(<code>library.base</code>, <code>notes.base</code>). Nothing in STAR needs Obsidian.</p>' "$PAGE" && pass "R5 Obsidian is optional" || fail "R5 Obsidian on the page"
grep -qF '<li>Workers read only the notes that apply: a brief copies the ones for its item, and every worker reads the short set marked always.' "$PAGE" && pass "R6 notes that apply" || fail "R6 notes that apply on the page"
grep -qF '<li>A finished worktree'"'"'s spec and plan are kept beside its evidence, and dependency and build folders are left out of evidence and listed.</li>' "$PAGE" && pass "R7 build docs kept" || fail "R7 build docs on the page"
# audit: the STAR audit fixes on the page
grep -qF '<li>Every check the branch rules require has reported on that head: one still missing waits, and a merge GitHub refuses for it is tried again, never counted as a failure</li>' "$PAGE" && pass "A1 the merge waits for every required check" || fail "A1 the merge waits for every required check"
grep -qF 'A hold you give with a date waits on its own, without asking again.' "$PAGE" && pass "A2 dated holds wait" || fail "A2 blockers carry a reason and dated holds wait"
grep -qF 'Each is asked once.' "$PAGE" && pass "A3 a person item is asked once" || fail "A3 person steps are checked after done"
grep -qF 'When the review gate is down on every model, nobody is asked: STAR parks builds and babysits and checks it every 30 minutes.' "$PAGE" && pass "A4 a down gate asks nobody" || fail "A4 approved work that waits is named"
grep -qF '<li>After round 1, a codex round reviews the commits since the last round and checks that round'"'"'s findings:' "$PAGE" && pass "A5 later gate rounds review what changed" || fail "A5 later gate rounds review what changed"
grep -qF 'A SAFE round'"'"'s P2 and P3 findings get no push of their own.</li>' "$PAGE" && pass "A6 no push for P2 and P3 after SAFE" || fail "A6 no push for P2 and P3 after SAFE"
grep -qF '<li>A re-scope that only narrows the brief, with no new code to write, goes straight back to the codex gate on the same head.</li>' "$PAGE" && pass "A7 a narrowing re-scope goes straight to the gate" || fail "A7 a narrowing re-scope goes straight to the gate"
grep -qF '<li>Evidence keeps proof, not inputs: packages, models, build output, git objects and audio over 10 MB are left out too,' "$PAGE" && pass "A8 evidence keeps proof" || fail "A8 evidence keeps proof"
grep -qF 'A worker at a Claude usage-limit screen that continues by itself at a set time is paused, not failed' "$PAGE" && pass "A9 usage limits restart or run in the session" || fail "A9 usage limits restart or run in the session"
grep -qF '<li>Before READY, babysit merges the base in only when the base requires up-to-date branches or the PR conflicts, never because it is behind alone' "$PAGE" && pass "A10 the final sync merges only when needed" || fail "A10 the final sync merges only when needed"
grep -qF 'A base merge whose shared files only gained lines on both sides (a test list, a changelog) keeps the last codex PASS too.</li>' "$PAGE" && pass "A11 lines both sides only added carry the PASS" || fail "A11 lines both sides only added carry the PASS"
# autonomy: the page shows STAR shipping without a go
! grep -qiE '\bsay go\b|Before go|Your go|merge grant|granted' "$PAGE" && pass "AUTO the page has no go, grant or batch summary to approve" || fail "AUTO go or grant on the page"
grep -qF 'STAR asks you only for what a person must supply (a secret, an account, an action at your screen, a required approval, access) and runs everything else itself' "$PAGE" && pass "AUTO the lede asks only for what a person must supply" || fail "AUTO lede on the page"
grep -qF '>Queue the brief</text>' "$PAGE" && grep -qF '>Only stop: a person item</text>' "$PAGE" && grep -qF '>straight to build</text>' "$PAGE" && pass "AUTO the drawing goes straight to build with person items as the only stop" || fail "AUTO drawing"
grep -qF 'tries budget is spent files a follow-up or sets the item aside as a note' "$PAGE" && grep -qF '>tries spent → re-scope or aside</text>' "$PAGE" && pass "AUTO the drawing ends the tries budget in a re-scope, follow-up or set-aside" || fail "AUTO tries in the drawing"
! grep -qE '<td class="k">go</td>' "$PAGE" && pass "AUTO the Stages table has no go row" || fail "AUTO go row"
grep -qF 'STAR posts one digest in the dashboard chat: each item, its criteria, the decisions made and the ones reused. No reply is expected and nothing waits on it, so there is no batch summary to approve.' "$PAGE" && pass "AUTO the batch digest expects no reply" || fail "AUTO digest on the page"
grep -qF 'Mobbin for how real apps solve it (screens, flows, sections), together with the <code>frontend-design:frontend-design</code> skill' "$PAGE" && grep -qF 'A technical question (a library, framework, SDK, API or CLI): Context7, for the version the project uses, else a web search' "$PAGE" && pass "AUTO sources: Mobbin and frontend-design, Context7 else web search" || fail "AUTO sources on the page"
grep -qF 'Each decision is a short record in the brief' "$PAGE" && grep -qF 'is a record you can overrule' "$PAGE" && pass "AUTO decision records the owner can overrule" || fail "AUTO overrule on the page"
grep -qF 'What needs a person is asked once, as a person item, at any time, and only the item that needs it waits.' "$PAGE" && grep -qF 'Your answer goes into STAR'"'"'s notes, so the same question never comes back.' "$PAGE" && pass "AUTO person items are asked once and remembered" || fail "AUTO checks at the screen"
grep -qF 'Green required checks plus the codex PASS merge it' "$PAGE" && grep -qF 'No second approval, unless branch protection requires one' "$PAGE" && pass "AUTO no hosted reviewer: green checks plus the PASS, no second approval" || fail "AUTO merge gate without a reviewer"
grep -qF 'Hosted reviewer set and not paused (Greptile)' "$PAGE" && grep -qF 'A hosted reviewer that is down is waited on, never merged past' "$PAGE" && pass "AUTO the hosted reviewer's passes when set and not paused" || fail "AUTO merge gate with a reviewer"
grep -qF '<code>mergeMethod</code>: merge, squash, rebase, or the first the repository allows' "$PAGE" && pass "AUTO the page names mergeMethod" || fail "AUTO mergeMethod"
grep -qF 'STAR never opens a PR into one or merges into one. sphere-os-browser merges to <code>dev</code> and you do <code>dev</code> to <code>main</code>.' "$PAGE" && pass "AUTO the page names baseBranch and ownerBranches" || fail "AUTO ownerBranches"
grep -qF 'passes only on a red-check-proof the gate confirms with <code>gh</code>' "$PAGE" && pass "AUTO a red check that is not required needs a red-check-proof" || fail "AUTO red-check-proof"
grep -qF '<code>Merging head &lt;sha&gt;: codex PASS, required checks green[, &lt;reviewer&gt; passed].</code>' "$PAGE" && pass "AUTO merge.sh posts the merge line" || fail "AUTO merge line"
grep -qF 'Only for person items, shown in one combined Needs you across every project on the dashboard.' "$PAGE" && pass "AUTO where you are needed: person items in one combined Needs you" || fail "AUTO where you are needed"
grep -qF '<code>tries.perStep</code> (3) per step, <code>tries.rescopes</code> (1) and <code>tries.followUpDepth</code> (2)' "$PAGE" && pass "AUTO the tries budget" || fail "AUTO tries budget"
grep -qF 'A quality failure (a NOT-SAFE gate round, red CI, a hosted review with blocking findings, a conflict) is re-scoped once after its tries are spent' "$PAGE" && grep -qF 'An infrastructure failure (a stage that could not start, a lost worker, a down executor) runs the stage again, then sets the item aside' "$PAGE" && pass "AUTO quality failures re-scope, infra failures set aside" || fail "AUTO failure classes"
grep -qF 'Set-aside is a note in the queue with try again or drop, never a question.' "$PAGE" && pass "AUTO set-aside is a note, never a question" || fail "AUTO set-aside"
grep -qF 'A follow-up is filed in the tracker (or as a spec file) and picked up by STAR itself, with no approval.' "$PAGE" && pass "AUTO follow-ups are picked up by STAR" || fail "AUTO follow-ups"
for state in inbox briefing needs-you queued building babysit-queued babysitting verifying post-queued done set-aside dropped; do
  grep -qF "<td class=\"k\">$state" "$PAGE" || fail "AUTO state $state missing"
done
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
