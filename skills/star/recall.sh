#!/bin/sh
# Finds, in a few lines, the decisions, notes and release records a STAR home already holds.
#   recall.sh [--home H] [--kind decision|note|release] [--limit N] [--all] [--project P] [--json] <words> ...
#     -> one line per hit, best first:  <kind> <ref> · <status> · <title> · <excerpt>
#        then, without --all, "hidden <n> replaced or superseded" when any match was hidden
#     -> "none" when nothing matches
#     -> with --json: one JSON object per hit, one per line (kind, ref, item, status, title, excerpt,
#        project, date, path relative to the home); no hidden line; nothing when there is no hit
#   recall.sh [--home H] rebuild   -> indexed <n> files
# <kind> printed is library, decision, note or release; --kind decision matches library and decision.
# --limit defaults to 5, at most 20. Each word is reduced to its letters, digits, - and _, so search
# syntax in the words is only words. Library notes rank first, then by match, then newer first.
# The index is <H>/index.db (SQLite FTS5), built from briefs/*/*.md (approved, ledger row not dropped),
# library/*/*.md, memory/*/*.md and releases/*.md. Every search first brings it up to date: a changed
# or removed file is re-read or dropped. It is a cache: deleting it, or a damaged one, loses nothing
# and is rebuilt without a word. Updates run under an fcntl lock on <H>/index.lock.
# Without --home the folder is $JUEL_STAR_HOME, else the one star-home.sh names for this directory.
# Exit: 0 ok (a search with no hit too); 2 the home or index cannot be read or written; 64 usage.
STAR_HOME_DEFAULT=${JUEL_STAR_HOME:-$(sh "$(dirname "$0")/star-home.sh" path 2>/dev/null)}
RECALL_DIR=$(cd "$(dirname "$0")" && pwd)
export STAR_HOME_DEFAULT RECALL_DIR
exec python3 - "$@" <<'PY'
import fcntl
import glob
import json
import os
import re
import sqlite3
import subprocess
import sys

USAGE = ("usage: recall.sh [--home H] [--kind decision|note|release] [--limit N] [--all] "
         "[--project P] [--json] <words> | rebuild")
SCHEMA = "1"
HIDDEN = ("superseded", "replaced")


def die(code, msg):
    print(f"recall.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def front_matter(lines):
    """(front matter lines, index of the closing line) or (None, None) when it never closes."""
    if not lines or lines[0].strip() != "---":
        return None, None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i], i
    return None, None


def parse_brief(text):
    """None when the brief is not approved; else its decision blocks."""
    lines = text.split("\n")
    fm, end = front_matter(lines)
    if fm is None:
        return None
    ok = False
    for l in fm:
        m = re.match(r"approved:\s*(.*)$", l)
        if m and m.group(1).strip().strip("\"'").strip():
            ok = True
    if not ok:
        return None
    blocks, cur, in_dec = [], None, False

    def close():
        nonlocal cur
        if cur:
            blocks.append(cur)
        cur = None

    for l in lines[end + 1:]:
        if l.startswith("## "):
            close()
            in_dec = bool(re.match(r"##\s+Decisions\b", l))
            continue
        if not in_dec:
            continue
        m = re.match(r"### (D\d+)\s+(.*?)\s*$", l)
        if m:
            close()
            cur = {"n": m.group(1), "heading": m.group(2), "lines": []}
        elif l.startswith("### ") or re.match(r"- \d{4}-\d{2}-\d{2}", l):
            close()
        elif cur is not None:
            cur["lines"].append(l)
    close()
    out = []
    for b in blocks:
        tm = re.match(r"^(.*?)\s*\(([^()]*)\)$", b["heading"])
        title, paren = (tm.group(1), tm.group(2)) if tm else (b["heading"], "")
        dm = re.search(r"\d{4}-\d{2}-\d{2}", paren)
        status = "active"
        for l in b["lines"]:
            sm = re.match(r"Status:\s*(Superseded|Amended)", l)
            if sm:
                status = sm.group(1).lower()
        out.append({"n": b["n"], "title": title, "date": dm.group(0) if dm else "",
                    "status": status, "body": "\n".join(b["lines"])})
    return out


def parse_note(text, stem):
    lines = text.split("\n")
    fm, end = front_matter(lines)
    props = {}
    if fm is None:
        body = text
    else:
        for l in fm:
            m = re.match(r"([A-Za-z_]\w*):\s?(.*)$", l)
            if m:
                try:
                    props[m.group(1)] = json.loads(m.group(2))
                except ValueError:
                    props[m.group(1)] = m.group(2)
        body = "\n".join(lines[end + 1:])
    idm = re.match(r"[LM]-\d{4}", stem)
    ref = props.get("id") if isinstance(props.get("id"), str) else (idm.group(0) if idm else stem)
    title = props.get("title") if isinstance(props.get("title"), str) else stem
    status = props.get("status") if isinstance(props.get("status"), str) else "active"
    since = props.get("since") if isinstance(props.get("since"), str) else ""
    frm = props.get("from")
    item = re.sub(r"^\[\[|\]\]$", "", frm) if isinstance(frm, str) else ""
    return ref, title, status, since, item, body


def parse_release(text, stem):
    first = text.split("\n", 1)[0]
    first = re.sub(r"^#\s*", "", first).strip()
    parts = first.split(" · ", 2)
    if len(parts) == 3:
        project, item, title = parts
    else:
        project, item, title = "", "", first
    dm = re.match(r"\d{4}-\d{2}-\d{2}", stem)
    return project, item, title, dm.group(0) if dm else ""


def stat_of(path):
    st = os.stat(path)
    return (st.st_mtime, st.st_size)


def create(conn):
    conn.execute("CREATE VIRTUAL TABLE docs USING fts5(title, body, kind UNINDEXED, ref UNINDEXED, "
                 "item UNINDEXED, status UNINDEXED, date UNINDEXED, path UNINDEXED, "
                 "project UNINDEXED, tokenize='porter unicode61')")
    conn.execute("CREATE TABLE sources(path TEXT PRIMARY KEY, mtime REAL, size INTEGER)")
    conn.execute("CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)")
    conn.execute("INSERT INTO meta VALUES ('schema', ?)", (SCHEMA,))
    conn.commit()


def open_db(db):
    fresh = not os.path.exists(db)
    conn = sqlite3.connect(db, timeout=30)
    conn.execute("PRAGMA journal_mode=WAL")
    if fresh:
        create(conn)
        return conn
    row = conn.execute("SELECT value FROM meta WHERE key='schema'").fetchone()
    if not row or row[0] != SCHEMA:
        raise sqlite3.DatabaseError("old schema")
    return conn


def wipe(db):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(db + suffix)
        except FileNotFoundError:
            pass


def dropped_items(home):
    script = os.path.join(os.environ["RECALL_DIR"], "ledger.sh")
    try:
        out = subprocess.run(["sh", script, "--home", home, "list"], capture_output=True,
                             text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return set()
    return {c[0] for c in (l.split("\t") for l in out.splitlines()) if len(c) > 1 and c[1] == "dropped"}


def update(conn, home):
    sources = {p: (m, s) for p, m, s in conn.execute("SELECT path, mtime, size FROM sources")}
    ledger = os.path.join(home, "ledger.md")
    try:
        lstat = "%r:%d" % stat_of(ledger)
    except OSError:
        lstat = ""
    row = conn.execute("SELECT value FROM meta WHERE key='ledger'").fetchone()
    ledger_changed = (row[0] if row else None) != lstat
    dropped = None
    walked = set()

    def files(pattern):
        return sorted(p for p in glob.glob(os.path.join(home, pattern)) if os.path.isfile(p))

    def forget(rel):
        conn.execute("DELETE FROM docs WHERE path=?", (rel,))
        conn.execute("DELETE FROM sources WHERE path=?", (rel,))

    def put(rel, st, rows):
        forget(rel)
        for r in rows:
            conn.execute("INSERT INTO docs(title, body, kind, ref, item, status, date, path, project) "
                         "VALUES (?,?,?,?,?,?,?,?,?)", (r[0], r[1], r[2], r[3], r[4], r[5], r[6], rel, r[7]))
        conn.execute("INSERT INTO sources VALUES (?,?,?)", (rel, st[0], st[1]))

    for kind, pattern in (("brief", "briefs/*/*.md"), ("library", "library/*/*.md"),
                          ("note", "memory/*/*.md"), ("release", "releases/*.md")):
        for path in files(pattern):
            rel = os.path.relpath(path, home)
            walked.add(rel)
            try:
                st = stat_of(path)
            except OSError:
                continue
            if sources.get(rel) == st and not (kind == "brief" and ledger_changed):
                continue
            try:
                text = read(path)
            except OSError:
                forget(rel)
                continue
            stem = os.path.basename(path)[:-3]
            project = os.path.basename(os.path.dirname(path))
            if kind == "brief":
                blocks = parse_brief(text)
                if blocks is None:
                    forget(rel)
                    continue
                if dropped is None:
                    dropped = dropped_items(home)
                if stem in dropped:
                    forget(rel)
                    continue
                put(rel, st, [(b["title"], b["body"], "decision", f"{stem}#{b['n']}", stem,
                               b["status"], b["date"], project) for b in blocks])
            elif kind in ("library", "note"):
                ref, title, status, since, item, body = parse_note(text, stem)
                put(rel, st, [(title, body, kind, ref, item if kind == "library" else "",
                               status, since, project)])
            else:
                project_r, item, title, date = parse_release(text, stem)
                put(rel, st, [(title, text, "release", stem, item, "merged", date, project_r)])
    for rel in set(sources) - walked:
        forget(rel)
    conn.execute("INSERT OR REPLACE INTO meta VALUES ('ledger', ?)", (lstat,))
    conn.commit()
    return conn.execute("SELECT count(*) FROM sources").fetchone()[0]


def locked(home, fn):
    db = os.path.join(home, "index.db")
    with open(os.path.join(home, "index.lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for attempt in (1, 2):
            conn = None
            try:
                conn = open_db(db)
                return fn(conn, db)
            except sqlite3.DatabaseError as e:
                if conn is not None:
                    conn.close()
                    conn = None
                if attempt == 2:
                    die(2, f"cannot use the index: {e}")
                wipe(db)
            finally:
                if conn is not None:
                    conn.close()


def one_line(text):
    return re.sub(r"[\r\n\t]+", " ", text or "")


def main():
    argv, home = sys.argv[1:], os.environ.get("STAR_HOME_DEFAULT") or ""
    kind = limit = project = None
    show_all = as_json = False
    words, i = [], 0
    while i < len(argv):
        a = argv[i]
        if a in ("--home", "--kind", "--limit", "--project"):
            if i + 1 >= len(argv):
                die(64, f"{a} needs a value; {USAGE}")
            v = argv[i + 1]
            if a == "--home":
                home = v
            elif a == "--kind":
                kind = v
            elif a == "--limit":
                limit = v
            else:
                project = v
            i += 2
        elif a == "--all":
            show_all, i = True, i + 1
        elif a == "--json":
            as_json, i = True, i + 1
        elif a.startswith("--"):
            die(64, f"unknown option {a}; {USAGE}")
        else:
            words.append(a)
            i += 1
    if kind not in (None, "decision", "note", "release"):
        die(64, f"--kind is decision, note or release; {USAGE}")
    n = 5
    if limit is not None:
        if not re.fullmatch(r"\d+", limit) or not 1 <= int(limit) <= 20:
            die(64, "--limit must be a whole number from 1 to 20")
        n = int(limit)
    rebuild = words == ["rebuild"]
    runs = []
    if not rebuild:
        for w in words:
            runs += [r for r in re.findall(r"[\w-]+", w) if re.search(r"[^\W_]", r)]
        runs = runs[:12]
        if not runs:
            die(64, f"no searchable word; {USAGE}")
    if not home or not os.path.isdir(home):
        die(2, f"no STAR folder at {home or '(unset)'}")
    try:
        if rebuild:
            def do_rebuild(conn, db):
                for t in ("docs", "sources", "meta"):
                    conn.execute(f"DROP TABLE IF EXISTS {t}")
                conn.commit()
                create(conn)
                return update(conn, home)
            print(f"indexed {locked(home, do_rebuild)} files")
            return

        def do_search(conn, db):
            update(conn, home)
            where, args = ["docs MATCH ?"], [" OR ".join('"%s"' % r for r in runs)]
            if kind == "decision":
                where.append("kind IN ('library','decision')")
            elif kind:
                where.append("kind = ?")
                args.append(kind)
            if project:
                where.append("project = ?")
                args.append(project)
            hidden = conn.execute("SELECT count(*) FROM docs WHERE " + " AND ".join(where) +
                                  " AND status IN ('superseded','replaced')", args).fetchone()[0]
            if not show_all:
                where.append("status NOT IN ('superseded','replaced')")
            rows = conn.execute(
                "SELECT kind, ref, item, status, title, snippet(docs, 1, '', '', '…', 24), "
                "project, date, path FROM docs WHERE " + " AND ".join(where) +
                " ORDER BY (kind = 'library') DESC, bm25(docs, 5.0, 1.0), date DESC LIMIT ?",
                args + [n]).fetchall()
            return rows, hidden

        rows, hidden = locked(home, do_search)
    except OSError as e:
        die(2, f"cannot read or write the STAR folder: {e}")
    if as_json:
        for k, ref, item, status, title, excerpt, proj, date, path in rows:
            print(json.dumps({"kind": k, "ref": ref, "item": item, "status": status,
                              "title": one_line(title), "excerpt": one_line(excerpt),
                              "project": proj, "date": date, "path": path}, ensure_ascii=False))
        return
    for k, ref, item, status, title, excerpt, proj, date, path in rows:
        print(f"{k} {ref} · {status} · {one_line(title)[:80]} · {one_line(excerpt)}")
    if not rows:
        print("none")
    if hidden and not show_all:
        print(f"hidden {hidden} replaced or superseded")


main()
PY
