#!/bin/sh
# The one place that knows where a project's STAR folder is, and brings an old one up to date.
#   star-home.sh [--cwd <dir>] path      print the folder for the repo containing <dir> (default: here)
#   star-home.sh [--cwd <dir>] init      create it from the template when missing, make git ignore it,
#                                        print it. Safe to repeat; never overwrites a file. It makes
#                                        library/ and builds/ beside the other folders and copies
#                                        library.base and notes.base (the Obsidian tables) from the template.
#   star-home.sh [--cwd <dir>] migrate   bring a folder to star.json schema 3 (STAR ships without asking). A schema 1
#                                        folder is first brought to schema 2's shape (below), then on to 3 in the same run.
#                                        Prints one "stop <dispatch>" per worker of a removed stage,
#                                        then "migrated gate" when it moved a v2.0.0 gate to Sol,
#                                        then "migrated quiet-hours" when it dropped a quietHours key
#                                        (the feature is gone; a schema 3 folder is cleaned too),
#                                        then "migrated notes=<n> item=sort-memory-notes" when it split
#                                        memory/<project>.md once (notes.sh split), kept the original as
#                                        memory/<project>.md.pre-notes, copied each standing key into a note
#                                        and added the sort-memory-notes item (a folder with no old notes
#                                        gets "notes": "split" and no line),
#                                        then "migrated evidence folders=<n> gb=<x.x>" on the first migrate
#                                        (star.json has no evidenceChecked) when worktree-clean.sh
#                                        --evidence-report finds dependency folders in evidence/; the key is
#                                        set either way, and a failing report leaves it unset,
#                                        then "migrated slack items=<n>" when it closed <n> >= 1 open
#                                        slack-reply items (Slack reply drafting is gone, #184) through
#                                        loops.sh close, on every schema; slack/, slack/redraft/ and
#                                        drafts/*-slack-*.md are left in place, never moved or deleted,
#                                        (schema 1 and 2: a loops.sh failure ends the run; schema 3: it
#                                        prints "warn slack items unchecked: <loops.sh's reason>" in that
#                                        place, after any "migrated slack items" line, and the run goes on
#                                        to "current", exit 0, queue untouched; the next start tries again;
#                                        close exit 4, already closed, counts as closed),
#                                        then "current" (schema 3) or "migrated schema=3 rows=<n> loops=<n>"
#                                        (rows: ledger rows whose state or stage it changed; loops: queue
#                                        items it closed), then "warn executor.fallback equals
#                                        executor.model" when the two are equal, on every path (#173).
# The schema 2 to 3 step, in this order, each part safe to repeat (star.json is written last): star.json gets
# tries (perStep from gate.maxRounds, else 3; rescopes 1; followUpDepth 2), mergeMethod, baseBranch and
# ownerBranches, hostedReviewer.paused false when a reviewer is set, and loses ownerApproval and gate.maxRounds;
# every open queue item of a removed kind (go-batch, go-merge, accept-report, restart-or-drop, question,
# escalation, held, and a person item whose "kind:" is not secret, account, screen, approval or access) is closed
# with the answer "closed by the schema-3 migration"; an answer it already held is first appended to its row's
# brief under ## Decisions ("- <date> answered before the schema-3 migration (<kind> <N-id>): <answer>"; no
# brief, no line). An escalation, question or held item that names, as whole words, a need only a person can
# meet comes back as a person item through loops.sh (keywords: "approval from someone other than" approval;
# "cannot see", "tokenCmd" access; "login", "trust" screen; "secret", "token", "api key", "password" secret;
# "account", "sign up", "sign in", "paid", "credit" account; the first match wins). Ledger rows then move through
# ledger.sh (brief-ready to needs-you when an open person item names the row's item, else queued; escalated and
# failed to needs-you, keeping the stage, when a person item came back for them, else to set-aside with a
# set-aside queue item "<item> set aside: <old item's title, or stopped before the schema-3 migration>", body
# "step: migration", options "try again / drop"; reported to post-queued; counters keep only schema 3's keys,
# live among them, and gain tries=0). Grant files are left alone. Each row keeps its `updated` time.
#   star-home.sh [--cwd <dir>] import <spec path>
#                                        copy a spec from outside the folder, with each file under the spec's folder that its text
#                                        names, into items/<project>/<kebab name>[-<n>]/ and print the copy's path; a spec already
#                                        in the folder prints as given; an earlier copy of the same source is reused, a changed
#                                        source gets the next -<n>. The name is a folder-safe kebab form. References to copied files
#                                        with the source's given or real folder prefix are rewritten to the destination; .import.json
#                                        records that source and digest.
#                                        Imports take the folder lock.
#   star-home.sh [--cwd <dir>] register  list the folder in ~/.juel/star-homes.json ({"name", "repo",
#                                        "home"}, once per home, under a lock): the registry the STAR
#                                        dashboard reads. Prints "registered <home>" (added or changed)
#                                        or "listed <home>". An entry with the same name whose folder
#                                        is gone (a moved project) is dropped. init does the same write
#                                        but prints only the folder; when the registry cannot be read or
#                                        written it says so on stderr and still succeeds.
#                                        JUEL_DIR, when set and not empty, is the folder in place of
#                                        ~/.juel, for the registry and its lock alike.
# The folder is <main checkout>/<docsRoot>/context/star. The main checkout is the first worktree
# git lists, so a linked worktree and a subfolder give the same answer. docsRoot follows the
# plugin's rule: "docsRoot" in .claude/workflow.local.json, else .claude/workflow.json; else
# docs/.superpowers when that folder exists and is not empty; else docs/superpowers.
# Ignoring never edits .gitignore: one line goes into <git common dir>/info/exclude, and only when
# git does not already ignore the folder.
# In a submodule or a --separate-git-dir repo git lists the git directory first; the checkout is
# found through core.worktree or the current directory. star.json's "project" keeps its name and
# everything STAR learned when the project folder is moved; only "repo" follows.
# migrate copies star.json and ledger.md to *.v1.bak (never over a backup), drops the review, fix
# and screen stages, "reviewer" and every stage's "executor", adds the schema 2 keys it lacks,
# moves rows out of the seven v1-only states and out of v1's verifying (pr-draft, reviewing,
# fix-queued, fixing, screen-queued, screening, ready, verifying to queued) with a
# decision record in each brief, and closes open approve-brief, prep and merge-pr queue items
# (a schema 2 folder skips this: its verifying rows stay verifying). Any other row that is not done or dropped and is
# still at the review, fix or screen stage (an escalated or failed row, say) gets stage=build.
# The stop lines go to migrate-stops.txt in the folder and are printed at once, before the first
# row moves, so a run that fails later has still named every worker to stop (they come first, on
# stdout, even when the exit is 1). The file is deleted only when the run succeeds; a run that
# finds it (an earlier migrate stopped half way) prints its lines again, before the main line.
# migrate also moves a v2.0.0 gate to v2.1.0's: "model": "gpt-6-astra" becomes "latest-sol", and a
# string "fallback" (v2.0.0's codex fallback) becomes {"agent": "claude", "model": "opus",
# "effort": "xhigh"}. Any other gate value is the owner's and is left alone. init and migrate both
# create the folders (inbox, briefs, reviews, gates, releases, drafts, memory, specs, reports, items,
# progress, evidence, library, builds; evidence/ is where worktree-clean.sh copies a worktree's evidence)
# and never grants/, which nothing reads.
# Exit: 0 ok; 1 not inside a usable git checkout, import with a spec that is not a readable file, no STAR folder, an unreadable star.json
# or project name, a named file it cannot read, or a copy that fails, register with no STAR folder or a registry it cannot read or write,
# a STAR folder migrate cannot read, or ledger.sh or loops.sh failing during
# migrate (the message names it; on a schema 3 home the slack step only warns); 64 usage.
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd) exec python3 - "$@" <<'PY'
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

SUBDIRS = ("inbox", "briefs", "reviews", "gates", "releases", "drafts", "memory", "specs", "reports",
           "items", "progress", "evidence", "library", "builds")
BASES = ("library.base", "notes.base")
FILES = ("open-loops.md", "ledger.md", "star.json")
DEFAULTS = {
    "executor": {"model": "latest-luna", "effort": "xhigh", "fallback": "latest-sol"},
    "gate": {"model": "latest-sol", "effort": "xhigh",
             "fallback": {"agent": "claude", "model": "opus", "effort": "xhigh"}},
    "tries": {"perStep": 3, "rescopes": 1, "followUpDepth": 2},
    "mergeMethod": None,
    "baseBranch": None,
    "ownerBranches": [],
    "keepBranches": False,
    "hostedReviewer": None,
    "hostGate": {"minFreeGB": 3, "maxAgents": 40, "maxSwapGB": 11, "minDiskGB": 25},
    "progressDeadlineMin": 30,
    "tokenCmd": None,
}
# schema 3 (STAR ships without asking): a queue item of one of these kinds is closed by migrate; a
# person item whose "kind:" line is not one of PERSON_KINDS is closed too.
REMOVED_KINDS = ("go-batch", "go-merge", "accept-report", "restart-or-drop", "question", "escalation", "held",
                 "approve-brief", "prep", "merge-pr")
PERSON_KINDS = ("secret", "account", "screen", "approval", "access")
# The first match wins; the text is a removed item's title and body, lower-cased.
NEED_WORDS = (("approval", ("approval from someone other than",)),
              ("access", ("cannot see", "tokencmd")),
              ("screen", ("login", "trust")),
              ("secret", ("secret", "token", "api key", "password")),
              ("account", ("account", "sign up", "sign in", "paid", "credit")))
NEED_KINDS = ("escalation", "question", "held")
KEEP_COUNTERS = ("tries", "rescoped", "depth", "hold", "start", "reached", "parent", "trackerRef", "batch",
                 "last", "tracker", "rescope", "live")
CLOSE_ANSWER = "closed by the schema-3 migration"
MOVES = {"pr-draft": ("queued", "build", "resume"), "reviewing": ("queued", "build", "resume"),
         "fix-queued": ("queued", "build", "resume"), "fixing": ("queued", "build", "resume"),
         "screen-queued": ("queued", "build", "screen"), "screening": ("queued", "build", "screen"),
         "ready": ("queued", "build", "merge"), "verifying": ("queued", "build", "merge")}
RUNNING_V1 = ("reviewing", "fixing", "screening")
REMOVED_STAGES = ("review", "fix", "screen")
CLOSED = ("done", "dropped")
RECORDS = {
    "resume": ("Resume under the closed loop",
               "STAR moved to the closed loop (juel v2.0.0) while this item was {old}.",
               "Run the build again on the item's existing branch and draft PR: verify it, then the codex gate loop.",
               "No separate review or fix stage runs for it; the build worker gates its own PR."),
    "screen": ("Screen checks become person items",
               "STAR moved to the closed loop (juel v2.0.0) while this item was {old}: checks waited for a person at the screen.",
               "Ask the checks listed in {pending} as person items; the build resumes on the existing PR.",
               "No check waits for a person unless it is a person item."),
    "merge": ("Merge under the merge gate",
              "STAR moved to the closed loop (juel v2.0.0) while this item was {old}: its PR waited for the owner's merge.",
              "A v1 item: the build resumes the gate loop on its existing PR, and STAR merges it once the merge gate holds.",
              "The owner no longer presses merge for this PR."),
}


def die(code, msg):
    print(f"star-home.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def git(where, *args):
    return subprocess.run(["git", "-C", where, *args], capture_output=True, text=True)


argv, cwd, cmd, import_path = sys.argv[1:], os.getcwd(), None, None
while argv:
    arg = argv.pop(0)
    if arg == "--cwd":
        if not argv:
            die(64, "--cwd needs a directory")
        cwd = argv.pop(0)
    elif arg in ("path", "init", "migrate", "register") and cmd is None:
        cmd = arg
    elif arg == "import" and cmd is None:
        cmd = arg
        if not argv:
            die(64, "usage: star-home.sh [--cwd <dir>] path|init|migrate|import <spec path>|register")
        import_path = argv.pop(0)
        if argv:
            die(64, f"unknown argument: {argv[0]}")
    else:
        die(64, f"unknown argument: {arg}")
if cmd is None:
    die(64, "usage: star-home.sh [--cwd <dir>] path|init|migrate|import <spec path>|register")

listing = git(cwd, "worktree", "list", "--porcelain")
if listing.returncode != 0:
    die(1, f"{cwd} is not inside a git repository")
first = listing.stdout.split("\n\n")[0].splitlines()
main = next((l[len("worktree "):] for l in first if l.startswith("worktree ")), "")


def is_checkout(path):
    return os.path.isdir(path) and git(path, "rev-parse", "--is-inside-work-tree").stdout.strip() == "true"


def rev_parse(*args):
    return git(cwd, "rev-parse", *args).stdout.strip()


if main and "bare" not in first and not is_checkout(main):
    # A submodule or a --separate-git-dir repo: git lists the git directory, not the checkout.
    # core.worktree names the checkout when set (submodules); otherwise the directory we were
    # started in is the main checkout exactly when its git dir is the common one.
    worktree = git(main, "config", "core.worktree").stdout.strip()
    if worktree:
        main = os.path.normpath(os.path.join(main, worktree))
    elif os.path.realpath(rev_parse("--absolute-git-dir")) == os.path.realpath(
            os.path.join(cwd, rev_parse("--git-common-dir"))):
        main = rev_parse("--show-toplevel")
if not main or "bare" in first or not is_checkout(main):
    die(1, "STAR needs a project checkout (this is a bare repository, or its main checkout cannot be found)")
main = os.path.realpath(main)


def docs_root():
    for name in ("workflow.local.json", "workflow.json"):
        try:
            value = json.load(open(os.path.join(main, ".claude", name), encoding="utf-8")).get("docsRoot")
        except (OSError, ValueError, AttributeError):
            continue
        if isinstance(value, str) and value.strip():
            return os.path.normpath(os.path.join(main, value.strip()))
    dotted = os.path.join(main, "docs", ".superpowers")
    if os.path.isdir(dotted) and os.listdir(dotted):
        return dotted
    return os.path.join(main, "docs", "superpowers")


home = os.path.join(docs_root(), "context", "star")
if cmd == "path":
    print(home)
    sys.exit(0)


def write_json(path, data):
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def add_to_decisions(project, item, make_block):
    """Append make_block(text) to the item's brief, inside ## Decisions (made when missing); a missing brief is skipped."""
    path = os.path.join(home, "briefs", project, f"{item}.md")
    if not os.path.isfile(path):
        return
    text = open(path, encoding="utf-8").read()
    block = make_block(text)
    heading = re.search(r"^## Decisions[ \t]*$", text, re.M)
    if not heading:
        text = text.rstrip("\n") + "\n\n## Decisions\n" + block
    else:
        later = re.search(r"^## ", text[heading.end():], re.M)
        cut = heading.end() + later.start() if later else len(text)
        text = text[:cut].rstrip("\n") + "\n" + block + ("\n" + text[cut:] if later else "")
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def record(project, item, old, kind):
    """Append a decision record to the item's brief, inside ## Decisions."""
    title, context, decision, consequences = RECORDS[kind]
    pending = os.path.join(home, "gates", project, f"{item}-screen.md")

    def block(text):
        n = len(re.findall(r"^### D\d+ ", text, re.M)) + 1
        return (f"### D{n} {title} ({datetime.now(timezone.utc).strftime('%Y-%m-%d')}, decided by STAR)\n"
                f"Context: {context.format(old=old)}\n"
                f"Decision: {decision.format(pending=pending)}\n"
                f"Consequences: {consequences}\n"
                f"Source: star-home.sh migrate\n")
    add_to_decisions(project, item, block)


def forget(path):
    """The run succeeded, so the stop lines it printed need no second chance."""
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def upgrade_gate(data):
    """v2.0.0's gate defaults to v2.1.0's (astra to latest-sol, a string fallback to the Claude block).
    True when something changed; any other value is the owner's and stays."""
    gate = data.get("gate")
    if not isinstance(gate, dict):
        return False
    changed = False
    if gate.get("model") == "gpt-6-astra":
        gate["model"] = "latest-sol"
        changed = True
    if isinstance(gate.get("fallback"), str):
        gate["fallback"] = dict(DEFAULTS["gate"]["fallback"])
        changed = True
    return changed


ITEM_BODY = """---
status: todo
title: Sort the memory notes into rules and facts
deliverable: report
---
STAR moved this project's notes from `memory/{p}.md` into one file per note under
`memory/{p}/`, each with `source: "migration"`, and copied the standing orders it kept in
`star.json` into notes of their own. Workers keep reading the old file until the owner accepts
this report.

This is a report, not a code change. Read every note in `memory/{p}/` and the original file
`memory/{p}.md.pre-notes`, and write a report whose proposal has one line per note, in exactly
this form, with nothing else on the line:

M-<nnnn> kind=<rule|fact> always=<true|false> status=<active|replaced> why=<a few words>

- kind: `rule` for an instruction from the owner, `fact` for something learned about the project
  or its tools.
- always: `true` only for a rule or fact every worker needs on every item (for example "never
  post to Slack", the test command, how to get a GitHub token). Keep that set short.
- status: `replaced` when a later note contradicts it, when it names a feature STAR no longer has
  (quiet hours), or when its own words limit it to a session, a run or a night ("in this session
  only", "for every open item of this run", "I have to go now"). Standing orders that pre-approve
  briefs or grant a go or a merge are `replaced`: each batch asks for go again (the owner's call,
  2026-10-20).

## Acceptance criteria
- [ ] Every note in `memory/{p}/` has exactly one proposal line.
- [ ] Every `replaced` line says why.
- [ ] Above the proposal, the report lists by title the notes proposed as `always` and the notes
      proposed as `replaced`.
"""


def create_new(path, text):
    """Exclusive create: an existing file is kept."""
    try:
        with open(path, "x", encoding="utf-8") as f:
            f.write(text)
    except FileExistsError:
        pass


def run_skill(script, *args):
    done = subprocess.run(["sh", os.path.join(os.environ["STAR_SKILL_DIR"], script), "--home", home, *args],
                          capture_output=True, text=True)
    if done.returncode != 0:
        die(1, f"{script} {' '.join(args[:1])}: " + (done.stderr.strip() or f"exit {done.returncode}"))
    return done.stdout


def migrate_notes(data):
    """Split the old notes file once. True when star.json changed."""
    if "notes" in data:
        return False
    project = (data.get("project") or {}).get("name") if isinstance(data.get("project"), dict) else ""
    if not project:
        return False
    legacy = os.path.join(home, "memory", project + ".md")
    try:
        has_notes = any(l.startswith("- ") for l in open(legacy, encoding="utf-8", errors="replace"))
    except OSError:
        has_notes = False
    if not has_notes:
        data["notes"] = "split"
        return True
    keep = legacy + ".pre-notes"
    if not os.path.exists(keep):
        shutil.copyfile(legacy, keep)
    out = run_skill("notes.sh", "--shelf", "memory", "--project", project, "split", legacy).split()
    count = out[1] if len(out) > 1 and out[0] == "split" else "0"
    standing = data.get("standing") if isinstance(data.get("standing"), dict) else {}
    for key, value in standing.items():
        text = value if isinstance(value, str) else json.dumps(value)
        run_skill("notes.sh", "--shelf", "memory", "--project", project, "add", "--title", key, "--text", text,
                  "--kind", "rule", "--source", "migration", "--once")
    item = os.path.join(home, "items", project, "sort-memory-notes.md")
    os.makedirs(os.path.dirname(item), exist_ok=True)
    create_new(item, ITEM_BODY.format(p=project))
    rows = run_skill("ledger.sh", "list").splitlines()
    if not any(l.split("\t")[0] == "sort-memory-notes" for l in rows):
        run_skill("ledger.sh", "add", "sort-memory-notes", f"ref={item}", f"project={project}")
    data["notes"] = "legacy"
    print(f"migrated notes={count} item=sort-memory-notes")
    return True


def migrate_evidence(data):
    """Measure the dependency folders kept in evidence, once. Best effort. True when star.json changed."""
    if "evidenceChecked" in data:
        return False
    script = os.path.join(os.environ["STAR_SKILL_DIR"], "worktree-clean.sh")
    try:
        done = subprocess.run(["sh", script, "--home", home, "--evidence-report"],
                              capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return False
    if done.returncode != 0:
        return False
    lines = done.stdout.strip().splitlines()
    found = re.fullmatch(r"total (\d+) gb=([0-9.]+)", lines[-1].strip()) if lines else None
    if not found:
        return False
    if int(found.group(1)) > 0:
        print(f"migrated evidence folders={found.group(1)} gb={found.group(2)}")
    data["evidenceChecked"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return True


class QueueUnchecked(Exception):
    """loops.sh could not list or close; the message is its one-line reason."""


def one_line(done):
    return " ".join((done.stderr.strip() or f"exit {done.returncode}").split())


def queue_items(queue, soft=False):
    """The open queue items with their title and body: [{id, kind, project, item, state, title, text, sub}].
    Read straight from open-loops.md (loops.sh list has no body); every write goes through loops.sh.
    soft: a list that fails raises QueueUnchecked instead of ending the run."""
    loops = os.path.join(os.environ["STAR_SKILL_DIR"], "loops.sh")
    listed = subprocess.run(["sh", loops, "--file", queue, "list"], capture_output=True, text=True)
    if listed.returncode != 0:
        if soft:
            raise QueueUnchecked(one_line(listed))
        die(1, "loops.sh list: " + (listed.stderr.strip() or f"exit {listed.returncode}"))
    bodies, current = {}, None
    for line in open(queue, encoding="utf-8", errors="surrogateescape").read().split("\n"):
        found = re.match(r"^### (N-\d+) · ", line)
        if found:
            current = bodies.setdefault(found.group(1), [])
        elif line.startswith("## "):
            current = None
        elif current is not None:
            current.append(line)
    found = []
    for line in listed.stdout.splitlines():
        cells = line.split("\t")
        if len(cells) < 6 or cells[4] == "missing":
            continue
        body = [l for l in bodies.get(cells[0], []) if not re.match(r"\s{0,3}(?:[-*+]\s+)?(?:\[[ xX]\]\s*)?[*_]{0,2}answer\s*[:：]", l, re.I)]
        sub = next((m.group(1) for l in body[1:] for m in [re.match(r"(?:> )?kind:\s*(\S+)", l)] if m), "")
        found.append({"id": cells[0], "kind": cells[1], "project": cells[2], "item": cells[3], "state": cells[4],
                      "title": cells[5], "text": (cells[5] + " " + " ".join(body)).lower(), "sub": sub})
    return found


def person_need(entry):
    """Only an escalation, question or held item can name a need; a word counts whole ("token" is not "tokens")."""
    if entry["kind"] not in NEED_KINDS:
        return None
    for need, words in NEED_WORDS:
        if any(re.search(r"(?<![a-z0-9])" + re.escape(w) + r"(?![a-z0-9])", entry["text"]) for w in words):
            return need
    return None


def migrate_slack(soft=False):
    """Close every open slack-reply item (Slack reply drafting is gone, #184). Never touches slack/ or drafts/.
    Prints "migrated slack items=<n>" when it closed at least one; safe to repeat.
    soft (a schema 3 home): a queue loops.sh cannot list or close prints "warn slack items unchecked: <reason>"
    and goes on, so a broken queue does not block STAR's start; the next start tries again."""
    queue = os.path.join(home, "open-loops.md")
    if not os.path.exists(queue):
        return
    loops = os.path.join(os.environ["STAR_SKILL_DIR"], "loops.sh")
    closed = 0
    try:
        for entry in queue_items(queue, soft):
            if entry["kind"] != "slack-reply":
                continue
            done = subprocess.run(["sh", loops, "--file", queue, "close", entry["id"]], capture_output=True, text=True)
            if done.returncode not in (0, 4):  # 4: already closed
                if soft:
                    raise QueueUnchecked(f"loops.sh close {entry['id']}: " + one_line(done))
                die(1, f"loops.sh close {entry['id']}: " + (done.stderr.strip() or f"exit {done.returncode}"))
            closed += 1
    except QueueUnchecked as why:
        if closed:
            print(f"migrated slack items={closed}")
        print(f"warn slack items unchecked: {why}")
        return
    if closed:
        print(f"migrated slack items={closed}")


def migrate_queue(skill):
    """Close the open items of a removed kind (and person items of a removed sub-kind); a person-only need
    among them comes back as a person item, and an answer one of them already holds is kept in its row's brief.
    Returns (how many it closed, the items a person item came back for, {item: the first old title})."""
    queue, loops = os.path.join(home, "open-loops.md"), os.path.join(skill, "loops.sh")
    closed, readded, titles = 0, set(), {}
    entries = queue_items(queue)  # first, so a queue loops.sh cannot read fails on "list"
    answered = subprocess.run(["sh", loops, "--file", queue, "answers"], capture_output=True, text=True)
    if answered.returncode != 0:
        die(1, "loops.sh answers: " + (answered.stderr.strip() or f"exit {answered.returncode}"))
    answers = {c[0]: c[4] for c in (l.split("\t") for l in answered.stdout.splitlines()) if len(c) >= 5}
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    for entry in entries:
        removed = entry["kind"] in REMOVED_KINDS or (entry["kind"] == "person" and entry["sub"] not in PERSON_KINDS)
        if not removed:
            continue
        need = person_need(entry) if entry["state"] == "open" else None
        if need:
            added = subprocess.run(["sh", loops, "--file", queue, "add", "--kind", "person", "--project", entry["project"],
                                    "--item", entry["item"], "--title", entry["title"],
                                    "--body", f"kind: {need}\n{entry['title']}"], capture_output=True, text=True)
            if added.returncode != 0:
                die(1, f"loops.sh add {entry['id']}: " + (added.stderr.strip() or f"exit {added.returncode}"))
            readded.add(entry["item"])
        titles.setdefault(entry["item"], entry["title"])
        if entry["id"] in answers:
            line = f"- {today} answered before the schema-3 migration ({entry['kind']} {entry['id']}): {answers[entry['id']]}\n"
            add_to_decisions(entry["project"], entry["item"], lambda text: line)
        for args in (("set-answer", entry["id"], CLOSE_ANSWER), ("close", entry["id"])):
            done = subprocess.run(["sh", loops, "--file", queue, *args], capture_output=True, text=True)
            if done.returncode not in (0, 4):  # 4: already closed
                die(1, f"loops.sh {args[0]} {entry['id']}: " + (done.stderr.strip() or f"exit {done.returncode}"))
        closed += 1
    return closed, readded, titles


def ledger_rows(skill):
    rows = subprocess.run(["sh", os.path.join(skill, "ledger.sh"), "--home", home, "list"],
                          capture_output=True, text=True)
    if rows.returncode != 0:
        die(1, "ledger.sh list: " + (rows.stderr.strip() or f"exit {rows.returncode}"))
    return [l.split("\t") for l in rows.stdout.splitlines() if len(l.split("\t")) >= 6]


def ledger_run(skill, *args, now=None):
    env = dict(os.environ)
    if now and re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?Z", now):
        env["STAR_NOW"] = now  # the row keeps the updated time it had
    done = subprocess.run(["sh", os.path.join(skill, "ledger.sh"), "--home", home, *args], capture_output=True, text=True, env=env)
    if done.returncode != 0:
        die(1, f"ledger.sh {' '.join(args[:2])}: " + (done.stderr.strip() or f"exit {done.returncode}"))
    return done.stdout.strip()


def migrate_ledger(skill, queue_entries, readded, titles, project):
    """Schema-3 states and counters. A row that goes to set-aside gets a set-aside queue item, unless a person
    item came back for it: then it is needs-you and keeps its stage. Returns the items whose row changed."""
    queue, loops = os.path.join(home, "open-loops.md"), os.path.join(skill, "loops.sh")
    waiting = {e["item"] for e in queue_entries if e["kind"] == "person" and e["state"] == "open" and e["sub"] in PERSON_KINDS}
    changed = []
    for cells in ledger_rows(skill):
        item, state = cells[0], cells[1]
        updated = cells[7] if len(cells) > 7 else None
        new = {"escalated": "needs-you" if item in readded else "set-aside",
               "failed": "needs-you" if item in readded else "set-aside", "reported": "post-queued",
               "brief-ready": "needs-you" if item in waiting else "queued"}.get(state)
        if new == "set-aside":  # the item first, so a stop half way leaves the row where a rerun finds it
            why = titles.get(item) or "stopped before the schema-3 migration"
            added = subprocess.run(["sh", loops, "--file", queue, "add", "--kind", "set-aside", "--project", project,
                                    "--item", item, "--title", f"{item} set aside: {why}",
                                    "--body", "step: migration\noptions: try again / drop"], capture_output=True, text=True)
            if added.returncode != 0:
                die(1, f"loops.sh add set-aside {item}: " + (added.stderr.strip() or f"exit {added.returncode}"))
        have = ledger_run(skill, "get", item, "counters")
        kept = [p.split("=", 1)[0] for p in have.split() if "=" in p]
        fields = [f"state={new}"] if new else []
        if any(k not in KEEP_COUNTERS for k in kept):
            fields.append("counters=keep:" + ",".join(KEEP_COUNTERS))
        if "tries" not in kept:
            fields.append("counters.tries=0")
        if fields:
            ledger_run(skill, "set", item, *fields, now=updated)
            if new:
                changed.append(item)
    return changed


def migrate():
    star_path = os.path.join(home, "star.json")
    stops_path = os.path.join(home, "migrate-stops.txt")
    try:  # an earlier run that stopped half way left these: their workers still have to be stopped
        stops = [l.strip() for l in open(stops_path, encoding="utf-8") if l.strip()]
    except OSError:
        stops = []
    printed = []

    def announce():
        """Print each stop line once, as soon as it is on disk: a run that fails later has named it."""
        for line in stops:
            if line not in printed:
                print(line, flush=True)
                printed.append(line)

    def warn(data):
        ex = data.get("executor") if isinstance(data.get("executor"), dict) else {}
        if isinstance(ex.get("model"), str) and ex.get("model") == ex.get("fallback"):
            print("warn executor.fallback equals executor.model")

    announce()
    try:
        data = json.load(open(star_path, encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(1, f"cannot read {star_path} ({e})")
    if not isinstance(data, dict):
        die(1, f"{star_path} is not a JSON object")
    if isinstance(data.get("schema"), int) and data["schema"] >= 3:
        gate_moved = upgrade_gate(data)
        quiet_gone = "quietHours" in data
        data.pop("quietHours", None)
        if gate_moved:
            print("migrated gate")
        if quiet_gone:
            print("migrated quiet-hours")
        notes_moved = migrate_notes(data)
        evidence_set = migrate_evidence(data)
        migrate_slack(soft=True)
        if gate_moved or quiet_gone or notes_moved or evidence_set:
            write_json(star_path, data)
        print("current")
        warn(data)
        forget(stops_path)
        return
    skill = os.environ["STAR_SKILL_DIR"]
    project = (data.get("project") or {}).get("name") or ""
    touched = set()
    from_v1 = data.get("schema") != 2
    if from_v1:  # schema 1: bring it to schema 2's shape first, then on to schema 3
        for name in ("star.json", "ledger.md"):
            src = os.path.join(home, name)
            if os.path.exists(src) and not os.path.exists(src + ".v1.bak"):
                shutil.copyfile(src, src + ".v1.bak")
        stages = data.get("stages") if isinstance(data.get("stages"), dict) else {}
        for gone in REMOVED_STAGES:
            stages.pop(gone, None)
        for entry in stages.values():
            if isinstance(entry, dict):
                entry.pop("executor", None)
        data["stages"] = stages
        data.pop("reviewer", None)
    # star.json is changed in memory and written last, so a run that stops half way starts over with
    # gate.maxRounds still in place
    tries = data.get("tries") if isinstance(data.get("tries"), dict) else None
    if tries is None:
        gate = data.get("gate") if isinstance(data.get("gate"), dict) else {}
        rounds = gate.get("maxRounds")
        data["tries"] = {**DEFAULTS["tries"], "perStep": rounds if isinstance(rounds, int) and rounds > 0 else 3}
    for key, value in DEFAULTS.items():
        data.setdefault(key, json.loads(json.dumps(value)))
    if upgrade_gate(data):
        print("migrated gate")
    if "quietHours" in data:
        del data["quietHours"]
        print("migrated quiet-hours")
    migrate_notes(data)
    migrate_evidence(data)
    if isinstance(data.get("hostedReviewer"), dict):
        data["hostedReviewer"].setdefault("paused", False)
    data.pop("ownerApproval", None)
    if isinstance(data.get("gate"), dict):
        data["gate"].pop("maxRounds", None)
    moving, restage = [], []
    for cells in ledger_rows(skill) if from_v1 else []:  # a schema 2 row is already in schema 2's states
        if cells[1] in MOVES:
            moving.append((cells[0], cells[1], cells[7] if len(cells) > 7 else None))
            if cells[1] in RUNNING_V1 and cells[5] not in ("", "-") and f"stop {cells[5]}" not in stops:
                stops.append(f"stop {cells[5]}")
        elif cells[1] not in CLOSED and cells[2] in REMOVED_STAGES:
            restage.append((cells[0], cells[7] if len(cells) > 7 else None))
    if stops:  # on disk and printed before any row moves, so a run that stops half way has named them
        tmp = f"{stops_path}.tmp.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(stops) + "\n")
        os.replace(tmp, stops_path)
        announce()
    for item, old, updated in moving:
        new, stage, kind = MOVES[old]
        ledger_run(skill, "set", item, f"state={new}", f"stage={stage}", "task=-", "dispatch=-", now=updated)
        record(project, item, old, kind)
        touched.add(item)
    # no state move reaches an escalated or failed row, but v2 cannot start a row at a removed stage
    for item, updated in restage:
        ledger_run(skill, "set", item, "stage=build", now=updated)
        touched.add(item)
    migrate_slack()  # after the stop lines are on disk: a queue it cannot read stops here
    loops, readded, titles = migrate_queue(skill)
    touched.update(migrate_ledger(skill, queue_items(os.path.join(home, "open-loops.md")), readded, titles, project))
    data["schema"] = 3
    write_json(star_path, data)
    forget(stops_path)
    print(f"migrated schema=3 rows={len(touched)} loops={loops}")
    warn(data)


class RegistryError(Exception):
    pass


def juel_dir():
    return os.environ.get("JUEL_DIR") or os.path.join(os.path.expanduser("~"), ".juel")


def registry_label():
    if os.environ.get("JUEL_DIR"):
        return os.path.join(os.environ["JUEL_DIR"], "star-homes.json")
    return "~/.juel/star-homes.json"


def register():
    """List this STAR folder in star-homes.json in juel_dir() ($JUEL_DIR, else ~/.juel), once per home,
    under a lock beside it.
    Returns "registered" (added, or its name or repo changed) or "listed" (already there as it is)."""
    juel = juel_dir()
    os.makedirs(juel, exist_ok=True)
    path = os.path.join(juel, "star-homes.json")
    with open(path + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            with open(path, encoding="utf-8") as f:
                entries = json.load(f)
        except FileNotFoundError:
            entries = []
        except ValueError as e:
            raise RegistryError(f"{path} is not JSON ({e}); fix or delete it")
        if not isinstance(entries, list):
            raise RegistryError(f"{path} is not a JSON list; fix or delete it")
        try:
            data = json.load(open(os.path.join(home, "star.json"), encoding="utf-8"))
        except (OSError, ValueError):
            data = None
        if not isinstance(data, dict) and any(
                isinstance(e, dict) and e.get("home") == home for e in entries):
            # star.json cannot be read now: keep the entry as it is rather than rename the project
            return "listed"
        project = data.get("project") if isinstance(data, dict) else None
        project = project if isinstance(project, dict) else {}
        name = project.get("name") if isinstance(project.get("name"), str) and project.get("name") else os.path.basename(main)
        repo = project.get("repo") if isinstance(project.get("repo"), str) and project.get("repo") else main
        entry = {"name": name, "repo": repo, "home": home}
        mine = [e for e in entries if isinstance(e, dict) and e.get("home") == home]

        def moved(e):
            return (isinstance(e, dict) and e.get("name") == name and e.get("home") != home and
                    not os.path.isfile(os.path.join(str(e.get("home") or ""), "star.json")))

        if mine == [entry] and not any(moved(e) for e in entries):
            return "listed"
        out, placed = [], False
        for e in entries:
            if moved(e):
                continue
            if isinstance(e, dict) and e.get("home") == home:
                if not placed:
                    out.append(entry)
                    placed = True
                continue
            out.append(e)
        if not placed:
            out.append(entry)
        write_json(path, out)
        return "registered"


def register_why(e):
    filename = getattr(e, "filename", None)
    strerror = getattr(e, "strerror", None)
    if filename and strerror:
        return f"{filename}: {strerror}"
    return strerror or str(e)


if cmd == "register":
    if not os.path.isfile(os.path.join(home, "star.json")):
        die(1, f"no STAR folder at {home}: run star-home.sh init first")
    try:
        print(f"{register()} {home}")
    except (OSError, RegistryError) as e:
        die(1, f"could not register {home} in {registry_label()} ({register_why(e)})")
    sys.exit(0)


if cmd == "import":
    path = import_path
    if not path or not os.path.isfile(path) or not os.access(path, os.R_OK):
        die(1, f"{path} is not a readable file")
    star_path = os.path.join(home, "star.json")
    if not os.path.isfile(star_path):
        die(1, f"no STAR folder at {home}: run star-home.sh init first")
    spec_real = os.path.realpath(path)
    home_real = os.path.realpath(home)
    if spec_real == home_real or spec_real.startswith(home_real + os.sep):
        print(path)
        sys.exit(0)
    try:
        star_data = json.load(open(star_path, encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        die(1, f"cannot read the project name from {star_path}")
    project_data = star_data.get("project") if isinstance(star_data, dict) else None
    project = project_data.get("name") if isinstance(project_data, dict) else None
    project = project if isinstance(project, str) and project else os.path.basename(main)
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,59}", project):
        die(1, f"project name {project} in {star_path} is not a folder name")
    stem = os.path.splitext(os.path.basename(path))[0]
    name = re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")
    name = re.sub(r"[^A-Za-z0-9._-]", "-", name).lstrip(".-")[:60] or "item"
    given = os.path.dirname(os.path.abspath(path))
    real = os.path.realpath(given)
    try:
        text_bytes = open(path, "rb").read()
    except OSError as e:
        die(1, f"{path} is not a readable file")
    try:
        text = text_bytes.decode("utf-8")
    except UnicodeDecodeError:
        text = None
    candidates = {}

    def add_candidate(candidate):
        candidate = candidate.strip().strip("\"'[]()<> ")
        if not candidate:
            return
        candidate = re.split(r"[?#]", candidate, maxsplit=1)[0].rstrip(".,:;!?")
        if not candidate:
            return
        if os.path.isabs(candidate):
            full = os.path.realpath(candidate)
        else:
            if ".." in candidate.replace("\\", "/").split("/"):
                return
            full = os.path.realpath(os.path.join(real, candidate))
        if not (full == real or full.startswith(real + os.sep)) or full == spec_real or not os.path.isfile(full):
            return
        candidates[full] = os.path.relpath(full, real)

    source_text = text if text is not None else text_bytes.decode("utf-8", "ignore")
    candidate_texts = []
    candidate_texts.extend(re.findall(r"`([^`]+)`", source_text))
    candidate_texts.extend(re.findall(r"\]\(\s*([^\s)]+)", source_text))
    candidate_texts.extend(re.findall(r'"([^"]+)"|\'([^\']+)\'|<([^>]+)>', source_text))
    candidate_texts.extend(re.findall(r"\S+", source_text))
    for token in candidate_texts:
        if isinstance(token, tuple):
            token = next((part for part in token if part), "")
        add_candidate(token)
    prefixes = sorted({given + os.sep, real + os.sep}, key=len, reverse=True)
    if source_text:
        pattern = re.compile(r"(?<![A-Za-z0-9._/~\-])(?:" + "|".join(re.escape(x) for x in prefixes) + r")")
        for match in pattern.finditer(source_text):
            tail = source_text[match.end():]
            tail = re.split(r"[\s`'\")>\]}]+", tail, maxsplit=1)[0]
            add_candidate(match.group(0) + tail)
    copies = [(spec_real, os.path.basename(path))] + sorted(candidates.items(), key=lambda kv: kv[1])
    source_bytes = {}
    for src, _ in copies:
        try:
            source_bytes[src] = open(src, "rb").read()
        except OSError as e:
            die(1, f"cannot read {src}: {e.strerror}")
    project_dir = os.path.join(home, "items", project)
    lock_path = os.path.join(home, "init.lock")
    with open(lock_path, "a") as init_lock:
        fcntl.flock(init_lock, fcntl.LOCK_EX)
        number = 1
        while True:
            folder_name = name if number == 1 else f"{name}-{number}"
            dest = os.path.join(project_dir, folder_name)
            rewrite_alternatives = []
            for src, rel in copies:
                for prefix in prefixes:
                    rewrite_alternatives.append((prefix + rel, rel))
            rewrite_alternatives.sort(key=lambda item: len(item[0]), reverse=True)
            rewrite_re = re.compile(
                r"(?<![A-Za-z0-9._/~\-])(?:" + "|".join(re.escape(src) for src, _ in rewrite_alternatives) +
                r")(?!\.?[A-Za-z0-9_/-])"
            )

            def content(src):
                raw = source_bytes[src]
                try:
                    decoded = raw.decode("utf-8")
                except UnicodeDecodeError:
                    return raw
                return rewrite_re.sub(
                    lambda match: dest + os.sep + next(rel for src_path, rel in rewrite_alternatives
                                                       if match.group(0) == src_path), decoded
                ).encode("utf-8")

            expected = {}
            for src, rel in copies:
                expected[rel] = content(src)
            digest = hashlib.sha256()
            for rel, data in sorted(expected.items()):
                digest.update(rel.encode("utf-8"))
                digest.update(b"\0")
                digest.update(data)
                digest.update(b"\0")
            metadata = {"source": spec_real, "digest": digest.hexdigest()}
            if os.path.isdir(dest):
                metadata_path = os.path.join(dest, ".import.json")
                if os.path.isfile(metadata_path):
                    try:
                        existing = json.load(open(metadata_path, encoding="utf-8"))
                    except (OSError, ValueError, TypeError):
                        existing = None
                    if isinstance(existing, dict) and existing.get("source") == spec_real and existing.get("digest") == metadata["digest"]:
                        print(os.path.join(dest, os.path.basename(path)))
                        sys.exit(0)
                elif all(os.path.isfile(os.path.join(dest, rel)) and open(os.path.join(dest, rel), "rb").read() == data
                         for rel, data in expected.items()):
                    print(os.path.join(dest, os.path.basename(path)))
                    sys.exit(0)
            if os.path.exists(dest):
                number += 1
                continue
            tmp = os.path.join(project_dir, f".{folder_name}.tmp.{os.getpid()}")
            try:
                os.makedirs(project_dir, exist_ok=True)
                os.makedirs(tmp)
                for rel, data in expected.items():
                    target = os.path.join(tmp, rel)
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    with open(target, "wb") as out_file:
                        out_file.write(data)
                with open(os.path.join(tmp, ".import.json"), "w", encoding="utf-8") as metadata_file:
                    json.dump(metadata, metadata_file)
                    metadata_file.write("\n")
                os.rename(tmp, dest)
            except OSError as e:
                shutil.rmtree(tmp, ignore_errors=True)
                die(1, f"could not import {path}: {e.strerror}")
            print(os.path.join(dest, os.path.basename(path)))
            sys.exit(0)


os.makedirs(home, exist_ok=True)
lock = open(os.path.join(home, "init.lock"), "w")
fcntl.flock(lock, fcntl.LOCK_EX)
for d in SUBDIRS:
    os.makedirs(os.path.join(home, d), exist_ok=True)
for name in BASES:  # the Obsidian tables: copied when missing, never over an edited one
    target = os.path.join(home, name)
    if not os.path.exists(target):
        tmp = f"{target}.tmp.{os.getpid()}"
        shutil.copyfile(os.path.join(os.environ["STAR_SKILL_DIR"], "template", name), tmp)
        os.replace(tmp, target)
if cmd == "migrate":
    migrate()
    sys.exit(0)
template = os.path.join(os.environ["STAR_SKILL_DIR"], "template")
for name in FILES:
    target = os.path.join(home, name)
    if not os.path.exists(target):
        tmp = f"{target}.tmp.{os.getpid()}"
        shutil.copyfile(os.path.join(template, name), tmp)
        os.replace(tmp, target)

star = os.path.join(home, "star.json")
try:
    data = json.load(open(star, encoding="utf-8"))
except (OSError, ValueError):
    data = None
project = data.get("project") if isinstance(data, dict) else None
if isinstance(data, dict) and not (isinstance(project, dict) and project.get("repo") == main):
    # a first run, or a project folder that was moved: the name stays, the path follows
    kept = project if isinstance(project, dict) else {}
    data["project"] = {**kept, "name": kept.get("name") or os.path.basename(main), "repo": main}
    write_json(star, data)

inside = home == main or home.startswith(main + os.sep)
if inside and git(main, "check-ignore", "-q", os.path.join(home, "star.json")).returncode != 0:
    common = git(main, "rev-parse", "--git-common-dir").stdout.strip()
    exclude = os.path.join(os.path.normpath(os.path.join(main, common)), "info", "exclude")
    line = "/" + os.path.relpath(home, main).replace(os.sep, "/") + "/"
    try:
        os.makedirs(os.path.dirname(exclude), exist_ok=True)
        have = open(exclude, encoding="utf-8", errors="replace").read() if os.path.exists(exclude) else ""
        if line not in have.splitlines():
            with open(exclude, "a", encoding="utf-8") as f:
                f.write(("" if have.endswith("\n") or not have else "\n") + line + "\n")
    except OSError as e:
        print(f"star-home.sh: could not make git ignore {home} ({e.strerror}); add '{line}' to .git/info/exclude yourself",
              file=sys.stderr)
try:
    register()
except (OSError, RegistryError) as e:
    print(f"star-home.sh: could not register {home} in {registry_label()} ({register_why(e)})", file=sys.stderr)
print(home)
PY
