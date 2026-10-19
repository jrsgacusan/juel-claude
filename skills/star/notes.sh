#!/bin/sh
# The only writer of the decision library and the memory notes: one Markdown file per note with
# JSON-valued properties (Obsidian reads them), and the file every worker reads.
#   notes.sh [--home H] --shelf library|memory --project P <command> ...
#     add --title T [--text TEXT] [--decision D --why W --source-text S] [--kind rule|fact]
#         [--source owner|brief-worker|worker-note|star|migration] [--always] [--since YYYY-MM-DD]
#         [--from <item> [--from-decision D<n>]] [--once]     -> added <id> <path> | exists <id>
#     replace <old-id> <add options>                          -> added <new-id> <path> replaces <old-id>
#     show <id>                                               -> <id> <title>: <text>  (one line, any status)
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
# --kind defaults to decision (library) or fact (memory); --source defaults to star. replace keeps the old
# note's kind and always unless --kind or --always is given. --once: a note on the shelf with the same title
# and source already exists -> "exists <id>", nothing written. --always, promote, use, split, apply and path
# belong to one shelf each; the other shelf is a usage error (64).
# After every memory write HOME/memory/<project>.always.md is rewritten: the active notes marked always, one
# "- <entry>" line each, the entry as show prints it (the title is left out when the text starts with it, and
# a note's closing "Replaces <id>." line is left out).
# While star.json "notes" is "legacy" (or is absent and memory/<project>.md exists), add also appends a
# line to that old file (never for --source migration: a migrated note is already in it), and path prints it.
# split writes memory/<project>/.split when it is done, and prints "split 0 already" whenever that marker or
# a note with source migration exists. A bullet that starts with a date gives the note that date.
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

USAGE = ("usage: notes.sh [--home H] --shelf library|memory --project P add|replace|show|promote|use|set|list|path|split|apply ...")
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
if CMD not in ("add", "replace", "promote", "use", "set", "list", "path", "split", "apply", "show"):
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


def entry(n):
    """<id> <title>: <text> on one line; the title alone when there is no text, the text alone when it
    starts with the title (a split or worker note's title is its text's start)."""
    fm = n["fm"]
    title = one_line(str(fm.get("title", "")))
    text = one_line(re.sub(r"\n?Replaces [LM]-\d{4}\.\s*$", "", n["body"]))
    if not text:
        return f"{fm['id']} {title}"
    if text.startswith(title):
        return f"{fm['id']} {text}"
    return f"{fm['id']} {title}: {text}"


def sync_always():
    if SHELF != "memory":
        return
    lines = [f"# {PROJECT}: notes every worker reads", ""]
    for n in notes():
        fm = n["fm"]
        if fm.get("status") == "active" and fm.get("always") is True:
            lines.append(f"- {entry(n)}")
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


def add_parts(args, old=None):
    """Validates the add options; returns (frontmatter inputs, body, item, once). With old (replace),
    kind and always default to the old note's."""
    o = options(args, ADD_FLAGS, {"--always", "--once"})
    title = o.get("--title", "")
    if not title.strip():
        die(64, "--title is required")
    kind = o.get("--kind", (old or {}).get("kind") or ("decision" if SHELF == "library" else "fact"))
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
    always = bool(o.get("--always")) or (old is not None and old.get("always") is True and SHELF == "memory")
    fm = {"kind": kind, "title": title, "always": always, "source": source,
          "since": since, "from": f"[[{item}]]" if item else None, "fromDecision": dec}
    return fm, body, item, bool(o.get("--once"))


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
    old = find(replaces) if replaces else None
    fm, body, item, once = add_parts(args, old["fm"] if old else None)
    if once and not replaces:
        for n in notes():
            if n["fm"].get("title") == fm["title"] and n["fm"].get("source") == fm["source"]:
                print(f"exists {n['fm']['id']}")
                return
    if replaces:
        body = (body + "\n" if body else "") + f"Replaces {replaces}."
    nid, path = new_note(item or "star", fm, body)
    if replaces:
        old["fm"]["status"], old["fm"]["replacedBy"] = "replaced", nid
        save(old)
    elif SHELF == "memory" and is_legacy() and fm["source"] != "migration":
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


def cmd_show(args):
    if len(args) != 1:
        die(64, "usage: show <id>")
    print(entry(find(args[0])))


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
        elif CMD == "show":
            cmd_show(REST)
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


def brief_block(item, number):
    """The lines of the ### D<number> block of a brief: (heading, block lines), or None."""
    path = os.path.join(HOME, "briefs", PROJECT, item + ".md")
    try:
        lines = read(path).split("\n")
    except FileNotFoundError:
        die(1, f"no brief for {item}")
    except OSError as e:
        die(2, f"cannot read {path}: {e.strerror}")
    start = None
    for i, l in enumerate(lines):
        if re.match(rf"### D{number} ", l):
            start = i
            break
    if start is None:
        return None
    block = []
    for l in lines[start + 1:]:
        if l.startswith("### ") or l.startswith("## ") or re.match(r"- \d{4}-\d{2}-\d{2}", l):
            break
        block.append(l)
    return lines[start], block


def block_line(block, name):
    for l in block:
        if l.startswith(name + ":"):
            return l[len(name) + 1:].strip()
    return ""


def parse_ref(ref):
    m = re.fullmatch(r"([A-Za-z0-9_][A-Za-z0-9._-]{0,59})#D(\d+)", ref or "")
    if not m:
        die(64, f"{ref!r} is not <item>#D<n>")
    return m.group(1), m.group(2)


def from_note(item, number):
    for n in notes():
        if n["fm"].get("from") == f"[[{item}]]" and n["fm"].get("fromDecision") == f"D{number}":
            return n
    return None


def cmd_promote(args):
    if not args:
        die(64, "usage: promote <item>#D<n> [--source ...] [--supersedes <item>#D<m>]")
    item, number = parse_ref(args[0])
    o = options(args[1:], {"--source", "--supersedes"})
    source = o.get("--source", "brief-worker")
    if source not in ("owner", "brief-worker", "star"):
        die(64, "--source must be owner, brief-worker or star")
    sup = parse_ref(o["--supersedes"]) if "--supersedes" in o else None
    got = brief_block(item, number)
    if got is None:
        die(1, f"no D{number} in {item}")
    existing = from_note(item, number)
    if existing:
        print(f"exists {existing['fm']['id']}")
        return
    heading, block = got
    title = re.sub(rf"^### D{number} ", "", heading)
    paren = re.search(r"\s*\(([^()]*)\)\s*$", title)
    date = today()
    if paren:
        title = title[:paren.start()]
        d = DATE_RE.search(paren.group(1))
        if d:
            date = d.group(0)
    old = None
    if sup:
        old = from_note(*sup)
        if old is None or old["fm"].get("status") == "replaced":
            old = None
            hit = brief_block(sup[0], sup[1])
            if hit:
                m = re.search(r"\(([^()]*)\)\s*$", hit[0])
                tail = m.group(1) if m else ""
                r1 = re.search(r"reused (L-\d{4})", tail)
                r2 = re.search(r"reused (\S+) D(\d+)", tail)
                if r1:
                    old = find(r1.group(1))
                elif r2:
                    old = from_note(r2.group(1), r2.group(2))
    if old is not None and old["fm"].get("status") == "replaced":
        old = None
    body = (f"Decision: {block_line(block, 'Decision')}\nWhy: {block_line(block, 'Context')}\n"
            f"Source: {block_line(block, 'Source')}")
    if old:
        body += f"\nReplaces {old['fm']['id']}."
    fm = {"kind": "decision", "title": title.strip(), "always": False, "source": source,
          "since": date, "from": f"[[{item}]]", "fromDecision": f"D{number}"}
    nid, path = new_note(item, fm, body)
    if old:
        old["fm"]["status"], old["fm"]["replacedBy"] = "replaced", nid
        save(old)
    print(f"added {nid} {path}" + (f" replaces {old['fm']['id']}" if old else ""))


def cut_title(text):
    flat = one_line(text)
    if len(flat) <= 80:
        return flat
    cut = flat[:80]
    if flat[80] != " " and " " in cut:
        cut = cut[:cut.rindex(" ")]
    return cut.rstrip()


def cmd_split(args):
    if len(args) != 1:
        die(64, "usage: split <legacy file>")
    try:
        text = read(args[0])
    except OSError as e:
        die(2, f"cannot read {args[0]}: {e.strerror}")
    marker = os.path.join(DIR, ".split")
    if os.path.exists(marker) or any(n["fm"].get("source") == "migration" for n in notes()):
        print("split 0 already")
        return
    bullets = []
    for l in text.split("\n"):
        if l.startswith("- "):
            bullets.append([l[2:]])
        elif bullets:
            bullets[-1].append(l.strip())
    parsed = []
    for b in bullets:
        while b and not b[-1]:
            b.pop()
        body = "\n".join(b)
        m = re.match(r"(\d{4}-\d{2}-\d{2}) (\S+): ", body)
        d = re.match(r"(\d{4}-\d{2}-\d{2})(?![0-9])", body)
        if m:
            since, source, body = m.group(1), ("owner" if m.group(2) in ("user", "owner") else "migration"), body[m.end():]
        elif d:
            since, source = d.group(1), "migration"  # the date stays in the text: it may carry a time
        else:
            since, source = today(), "migration"
        parsed.append((since, source, body))
    os.makedirs(DIR, exist_ok=True)
    ids = reserve("star", len(parsed), highest()) if parsed else []
    for nid, (since, source, body) in zip(ids, parsed):
        fm = {"kind": "fact", "title": cut_title(body), "always": False, "source": source, "since": since}
        new_note("star", fm, body, note_id=f"{PREFIX}-{nid:04d}")
    write_atomic(marker, today() + "\n")
    sync_always()
    print(f"split {len(parsed)}")


PROPOSAL_RE = re.compile(r"(M-\d{4}) kind=(rule|fact) always=(true|false) status=(active|replaced)( why=.*)?")


def cmd_apply(args):
    if len(args) != 1:
        die(64, "usage: apply <proposal file>")
    try:
        lines = read(args[0]).split("\n")
    except OSError as e:
        die(2, f"cannot read {args[0]}: {e.strerror}")
    props = [m.groups() for m in (PROPOSAL_RE.fullmatch(l.rstrip("\r")) for l in lines) if m]
    if not props:
        die(2, "no proposal line in the file; nothing changed")
    star_path = os.path.join(HOME, "star.json")
    try:
        star = json.loads(read(star_path))
        if not isinstance(star, dict):
            raise ValueError("not an object")
    except (OSError, ValueError) as e:
        die(2, f"cannot read {star_path}: {e}")
    by_id = {n["fm"]["id"]: n for n in notes()}
    kinds = always = replaced = skipped = 0
    for nid, kind, alw, status, _ in props:
        n = by_id.get(nid)
        if n is None:
            skipped += 1
            continue
        fm = n["fm"]
        if fm.get("kind") != kind:
            fm["kind"], kinds = kind, kinds + 1
        if fm.get("always") is not (alw == "true"):
            fm["always"], always = (alw == "true"), always + 1
        if fm.get("status") != status:
            fm["status"] = status
            if status == "replaced":
                replaced += 1
            else:
                fm["replacedBy"] = None
        save(n)
    if skipped:
        print(f"notes.sh: skipped {skipped} unknown id(s)", file=sys.stderr)
    out = {}
    for k, v in star.items():
        out["standingPreNotes" if k == "standing" else k] = v
    out["notes"] = "split"
    write_atomic(star_path, json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    sync_always()
    print(f"applied kind={kinds} always={always} replaced={replaced}")


main()
PY
