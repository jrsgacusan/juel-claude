#!/bin/sh
# The only writer of the decision library and the memory notes: one Markdown file per note with
# JSON-valued properties (Obsidian reads them), and the file every worker reads.
#   notes.sh [--home H] --shelf library|memory --project P <command> ...
#     add --title T [--text TEXT] [--decision D --why W --source-text S] [--kind rule|fact]
#         [--source owner|brief-worker|worker-note|star|migration] [--always] [--since YYYY-MM-DD]
#         [--from <item> [--from-decision D<n>]]              -> added <id> <path>
#     replace <old-id> <add options>                          -> added <new-id> <path> replaces <old-id>
#     promote <item>#D<n> [--source owner|brief-worker|star] [--supersedes <item>#D<m>]
#                                                             -> added <id> <path>[ replaces <old-id>] | exists <id>
#     use <id> <item>                                         -> used <id> <item>
#     set <id> kind=rule|fact | always=true|false | status=replaced
#                                                             -> set <id>
#     list [--always] [--all]                                 -> <id>\t<kind>\t<status>\t<always>\t<title>  per note, by id
#     path                                                    -> the one file a worker reads
#     split <legacy file>                                     -> split <n>  |  split 0 already
#     apply <proposal file>                                   -> applied kind=<a> always=<b> replaced=<c>
# Files: HOME/library/<project>/L-<nnnn>-<slug>.md (decisions) and HOME/memory/<project>/M-<nnnn>-<slug>.md
# (notes). --decision, --why and --source-text are the library body; --text is the memory body.
# --kind defaults to decision (library) or fact (memory); --source defaults to star. --always, promote, use,
# split, apply and path belong to one shelf each; the other shelf is a usage error (64).
# After every memory write HOME/memory/<project>.always.md is rewritten: the active notes marked always
# (a note's closing "Replaces <id>." line is left out of its entry).
# While star.json "notes" is "legacy" (or is absent and memory/<project>.md exists), add also appends a
# line to that old file, and path prints it.
# Ids come from ids.sh (sequence <shelf>/<project>), so parallel writers never share one. Every command
# runs under an fcntl lock on HOME/notes.lock; files are written whole then moved into place.
# Exit: 0; 1 an id or a decision was not found; 2 a file cannot be read or written, or a proposal has
# no line to apply; 64 usage.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
export STAR_HOME_DEFAULT
NOTES_IDS_SH="$(cd "$(dirname "$0")" && pwd)/ids.sh"
export NOTES_IDS_SH
exec python3 - "$@" <<'PY'
import datetime
import fcntl
import glob
import json
import os
import re
import subprocess
import sys

USAGE = ("usage: notes.sh [--home H] --shelf library|memory --project P add|replace|promote|use|set|list|path|split|apply ...")
NAME_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,59}")
KEYS = ["id", "kind", "title", "status", "replacedBy", "always", "source", "since", "from",
        "fromDecision", "usedBy"]
SOURCES = ("owner", "brief-worker", "worker-note", "star", "migration")
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")


def die(code, msg):
    print(f"notes.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def today():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def write_atomic(path, text):
    tmp = f"{path}.tmp.{os.getpid()}"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except OSError as e:
        die(2, f"cannot write {path}: {e.strerror}")


def create_new(path, text):
    """Exclusive create: the whole file is written first, then linked into place."""
    tmp = f"{path}.tmp.{os.getpid()}"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.link(tmp, path)
    except FileExistsError:
        die(2, f"{path} already exists")
    except OSError as e:
        die(2, f"cannot write {path}: {e.strerror}")
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def parse_args():
    argv = sys.argv[1:]
    g = {"--home": os.environ.get("STAR_HOME_DEFAULT") or "", "--shelf": None, "--project": None}
    while argv and argv[0] in g:
        if len(argv) < 2:
            die(64, USAGE)
        g[argv[0]], argv = argv[1], argv[2:]
    if not argv or g["--shelf"] not in ("library", "memory") or not g["--project"] \
            or not NAME_RE.fullmatch(g["--project"]):
        die(64, USAGE)
    return g, argv[0], argv[1:]


G, CMD, REST = parse_args()
HOME, SHELF, PROJECT = G["--home"], G["--shelf"], G["--project"]
PREFIX = "L" if SHELF == "library" else "M"
if CMD not in ("add", "replace", "promote", "use", "set", "list", "path", "split", "apply"):
    die(64, USAGE)
if not HOME or not os.path.isdir(HOME):
    die(2, f"no STAR folder at {HOME or '(unset)'}")
if SHELF == "library" and CMD in ("split", "apply", "path"):
    die(64, f"{CMD} belongs to the memory shelf")
if SHELF == "memory" and CMD in ("promote", "use"):
    die(64, f"{CMD} belongs to the library shelf")
DIR = os.path.join(HOME, SHELF, PROJECT)
ALWAYS_FILE = os.path.join(HOME, "memory", PROJECT + ".always.md")
LEGACY_FILE = os.path.join(HOME, "memory", PROJECT + ".md")
ID_RE = re.compile(PREFIX + r"-\d{4}")
FILE_RE = re.compile(r"(" + PREFIX + r")-(\d{4})-.*\.md")


def star_json():
    try:
        d = json.loads(read(os.path.join(HOME, "star.json")))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def is_legacy():
    mode = star_json().get("notes")
    return mode == "legacy" or (mode is None and os.path.isfile(LEGACY_FILE))


# ---- notes on disk -------------------------------------------------------------------------------

def parse_note(path):
    lines = read(path).split("\n")
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        return None
    end = lines.index("---", 1)
    fm = {}
    for l in lines[1:end]:
        if ": " not in l:
            continue
        k, v = l.split(": ", 1)
        try:
            fm[k] = json.loads(v)
        except ValueError:
            fm[k] = v
    return {"path": path, "fm": fm, "body": "\n".join(lines[end + 1:])}


def render(fm, body):
    out = ["---"]
    keys = [k for k in KEYS if k in fm] + [k for k in fm if k not in KEYS]
    for k in keys:
        v = fm[k]
        out.append(f"{k}: {json.dumps(v, ensure_ascii=False)}")
    out.append("---")
    return "\n".join(out) + "\n" + body


def notes():
    found = []
    for p in sorted(glob.glob(os.path.join(DIR, "*.md"))):
        if FILE_RE.fullmatch(os.path.basename(p)):
            try:
                n = parse_note(p)
            except OSError as e:
                die(2, f"cannot read {p}: {e.strerror}")
            if n and isinstance(n["fm"].get("id"), str):
                found.append(n)
    return found


def find(note_id):
    if not ID_RE.fullmatch(note_id or ""):
        die(64, f"{note_id!r} is not a {SHELF} id")
    for n in notes():
        if n["fm"]["id"] == note_id:
            return n
    die(1, f"no note {note_id}")


def highest():
    top = 0
    if os.path.isdir(DIR):
        for name in os.listdir(DIR):
            m = FILE_RE.fullmatch(name)
            if m:
                top = max(top, int(m.group(2)))
    return top


def reserve(item, count, floor):
    ids = []
    while count > 0:
        step = min(count, 100)
        r = subprocess.run(["sh", os.environ["NOTES_IDS_SH"], "--home", HOME, "reserve",
                            f"{SHELF}/{PROJECT}", "--item", item, "--count", str(step),
                            "--floor", str(floor)], capture_output=True, text=True)
        if r.returncode != 0:
            die(2, f"ids.sh refused: {r.stderr.strip()}")
        got = [int(x) for x in r.stdout.split()]
        ids += got
        floor = max(floor, max(got))
        count -= step
    return ids


def slug(title):
    s = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:50]
    return s or "note"


def one_line(text):
    return " ".join(text.split())


def sync_always():
    if SHELF != "memory":
        return
    lines = [f"# {PROJECT}: notes every worker reads", ""]
    for n in notes():
        fm = n["fm"]
        if fm.get("status") == "active" and fm.get("always") is True:
            text = one_line(re.sub(r"\n?Replaces [LM]-\d{4}\.\s*$", "", n["body"]))
            lines.append(f"- {fm['id']} {one_line(str(fm.get('title', '')))}" + (f": {text}" if text else ""))
    os.makedirs(os.path.dirname(ALWAYS_FILE), exist_ok=True)
    write_atomic(ALWAYS_FILE, "\n".join(lines) + "\n")


def new_note(ids_item, fm_in, body, note_id=None):
    """Writes one note file under the lock. Returns (id, path)."""
    os.makedirs(DIR, exist_ok=True)
    if note_id is None:
        note_id = f"{PREFIX}-{reserve(ids_item, 1, highest())[0]:04d}"
    fm = {"id": note_id, "kind": fm_in["kind"], "title": fm_in["title"], "status": "active",
          "replacedBy": None, "always": fm_in["always"], "source": fm_in["source"],
          "since": fm_in["since"], "from": fm_in.get("from"),
          "fromDecision": fm_in.get("fromDecision"), "usedBy": []}
    path = os.path.join(DIR, f"{note_id}-{slug(fm['title'])}.md")
    create_new(path, render(fm, body if body.endswith("\n") or not body else body + "\n"))
    return note_id, path


def save(n):
    write_atomic(n["path"], render(n["fm"], n["body"]))


def options(args, flags, switches=()):
    found, i = {}, 0
    while i < len(args):
        if args[i] in switches:
            found[args[i]] = True
            i += 1
        elif args[i] in flags and i + 1 < len(args):
            found[args[i]] = args[i + 1]
            i += 2
        else:
            die(64, f"unexpected argument {args[i]!r}; {USAGE}")
    return found


ADD_FLAGS = {"--title", "--text", "--decision", "--why", "--source-text", "--kind", "--source",
             "--since", "--from", "--from-decision"}


def add_parts(args):
    """Validates the add options; returns (frontmatter inputs, body, item)."""
    o = options(args, ADD_FLAGS, {"--always"})
    title = o.get("--title", "")
    if not title.strip():
        die(64, "--title is required")
    kind = o.get("--kind", "decision" if SHELF == "library" else "fact")
    if kind not in (("decision",) if SHELF == "library" else ("rule", "fact")):
        die(64, f"--kind {kind!r} does not fit the {SHELF} shelf")
    if o.get("--always") and SHELF == "library":
        die(64, "--always belongs to the memory shelf")
    source = o.get("--source", "star")
    if source not in SOURCES:
        die(64, f"--source must be one of {', '.join(SOURCES)}")
    since = o.get("--since", today())
    if not DATE_RE.fullmatch(since):
        die(64, "--since must be YYYY-MM-DD")
    item = o.get("--from")
    if item is not None and not NAME_RE.fullmatch(item):
        die(64, f"bad item name {item!r}")
    dec = o.get("--from-decision")
    if dec is not None and (item is None or not re.fullmatch(r"D\d+", dec)):
        die(64, "--from-decision needs --from and a D<n>")
    if SHELF == "library":
        if "--text" in o:
            die(64, "--text belongs to the memory shelf")
        body = (f"Decision: {o.get('--decision', '')}\nWhy: {o.get('--why', '')}\n"
                f"Source: {o.get('--source-text', '')}")
    else:
        if {"--decision", "--why", "--source-text"} & set(o):
            die(64, "--decision, --why and --source-text belong to the library shelf")
        body = o.get("--text", "")
    fm = {"kind": kind, "title": title, "always": bool(o.get("--always")), "source": source,
          "since": since, "from": f"[[{item}]]" if item else None, "fromDecision": dec}
    return fm, body, item


def legacy_append(fm, body, item):
    text = one_line(body) or one_line(fm["title"])
    try:
        have = read(LEGACY_FILE) if os.path.exists(LEGACY_FILE) else ""
        os.makedirs(os.path.dirname(LEGACY_FILE), exist_ok=True)
        with open(LEGACY_FILE, "a", encoding="utf-8") as f:
            f.write(("" if not have or have.endswith("\n") else "\n")
                    + f"- {fm['since']} {item or 'star'}: {text}\n")
    except OSError as e:
        die(2, f"cannot write {LEGACY_FILE}: {e.strerror}")


def cmd_add(args, replaces=None):
    fm, body, item = add_parts(args)
    if replaces:
        old = find(replaces)
        body = (body + "\n" if body else "") + f"Replaces {replaces}."
    nid, path = new_note(item or "star", fm, body)
    if replaces:
        old["fm"]["status"], old["fm"]["replacedBy"] = "replaced", nid
        save(old)
    elif SHELF == "memory" and is_legacy():
        legacy_append(fm, body, item)
    sync_always()
    print(f"added {nid} {path}" + (f" replaces {replaces}" if replaces else ""))


def cmd_list(args):
    o = options(args, set(), {"--always", "--all"})
    for n in notes():
        fm = n["fm"]
        if fm.get("status") == "replaced" and not o.get("--all"):
            continue
        if o.get("--always") and not (fm.get("always") is True and fm.get("status") == "active"):
            continue
        cells = [fm["id"], fm.get("kind"), fm.get("status"), json.dumps(fm.get("always")), fm.get("title")]
        print("\t".join(one_line(str(c)) for c in cells))


def cmd_use(args):
    if len(args) != 2 or not NAME_RE.fullmatch(args[1]):
        die(64, "usage: use <id> <item>")
    n = find(args[0])
    used = n["fm"].get("usedBy")
    used = used if isinstance(used, list) else []
    mark = f"[[{args[1]}]]"
    if mark not in used:
        n["fm"]["usedBy"] = used + [mark]
        save(n)
    print(f"used {args[0]} {args[1]}")


def cmd_set(args):
    if len(args) != 2 or "=" not in args[1]:
        die(64, "usage: set <id> kind=|always=|status=replaced")
    key, value = args[1].split("=", 1)
    if key == "kind":
        if value not in (("decision",) if SHELF == "library" else ("rule", "fact")):
            die(64, f"kind {value!r} does not fit the {SHELF} shelf")
    elif key == "always":
        if value not in ("true", "false") or (SHELF == "library" and value == "true"):
            die(64, "always must be true or false, and true only on the memory shelf")
    elif key == "status":
        if value != "replaced":
            die(64, "status can only be set to replaced")
    else:
        die(64, f"cannot set {key!r}")
    n = find(args[0])
    n["fm"][key] = (value == "true") if key == "always" else value
    save(n)
    sync_always()
    print(f"set {args[0]}")


def main():
    os.makedirs(HOME, exist_ok=True)
    with open(os.path.join(HOME, "notes.lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if CMD == "add":
            cmd_add(REST)
        elif CMD == "replace":
            if not REST:
                die(64, "usage: replace <old-id> <add options>")
            cmd_add(REST[1:], replaces=REST[0])
        elif CMD == "list":
            cmd_list(REST)
        elif CMD == "use":
            cmd_use(REST)
        elif CMD == "set":
            cmd_set(REST)
        elif CMD == "path":
            cmd_path()
        elif CMD == "promote":
            cmd_promote(REST)
        elif CMD == "split":
            cmd_split(REST)
        elif CMD == "apply":
            cmd_apply(REST)


def cmd_path():
    if is_legacy():
        print(LEGACY_FILE)
        return
    if not os.path.exists(ALWAYS_FILE):
        sync_always()
    print(ALWAYS_FILE)


def cmd_promote(args):
    die(64, "promote is not built yet")


def cmd_split(args):
    die(64, "split is not built yet")


def cmd_apply(args):
    die(64, "apply is not built yet")


main()
PY
