#!/bin/sh
# Runs the read-only check that ends a person step (` (check: `<command>`)`) and says whether it passed.
#   person-check.sh '<command>'
#     -> one line: pass | fail <exit code> | timeout | refused <why>
# The command runs from the current folder with `sh -c`, stdin and output from/to /dev/null, and a
# limit of 60 seconds (PERSON_CHECK_TIMEOUT seconds overrides it, for tests): stock macOS has no
# `timeout`, so python's subprocess enforces it. A command that is refused is never run. It is refused
# when it contains:
#   - a command substitution outside single quotes, also inside double quotes (`$(` or a backtick);
#   - `sudo` as a word anywhere, even inside quotes passed to another command;
#   - a redirection anywhere in a segment, also before the command word, other than `> /dev/null`
#     and a descriptor dup (`2>&1`);
#   - one of these as a command word (first word, or first word after `|`, `||`, `&&`, `;`, `&`, `(`
#     or a backtick, once redirections are skipped): rm rmdir mv cp ln tee dd chmod chown touch mkdir
#     install kill killall pkill open osascript npm sh bash zsh dash env eval exec xargs nohup command
#     builtin source `.`, and any word starting with pip;
#   - `find` with -delete, -exec, -execdir, -ok or -okdir;
#   - `brew` other than `brew list|info|--prefix|config`;
#   - `defaults` other than `defaults read`, `launchctl` other than `launchctl list|print`;
#   - `git` other than rev-parse, status, log or ls-files, after any `-C <dir>` or `--no-pager`
#     (`git -c ...` is refused);
#   - `curl` or `wget` with an output target (-o, -O, --output, --remote-name) other than /dev/null.
# A command that cannot be split into words (an unclosed quote) is `refused unreadable command`.
# The list is a guard against mistakes, not a sandbox.
# Exit: 0 for every result above; 64 usage (no argument, more than one, or an empty one).
if [ "$#" -ne 1 ] || [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; then
  echo "usage: person-check.sh '<command>'" >&2
  exit 64
fi
exec python3 - "$1" <<'PY'
import os
import signal
import subprocess
import sys

cmd = sys.argv[1]

REFUSED_WORDS = set("rm rmdir mv cp ln tee dd chmod chown touch mkdir install kill killall pkill "
                    "open osascript npm sudo sh bash zsh dash env eval exec xargs nohup command "
                    "builtin source .".split())
BREW_OK = {"list", "info", "--prefix", "config"}
GIT_OK = {"rev-parse", "status", "log", "ls-files"}
LAUNCHCTL_OK = {"list", "print"}
FIND_BAD = {"-delete", "-exec", "-execdir", "-ok", "-okdir"}
SKIP = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "}", "time"}
OPS = ["&&", "||", ">>", ">&", ">|", "<<", "|", ";", "&", "(", ")", ">", "<"]
REDIRS = {">", ">>", ">|", ">&", "<", "<<"}
# short options that take a value, per tool (the value is the rest of the cluster or the next word)
VALUED = {"curl": set("AbcCdDeEFHKmPQrtTuUwxXyYz"), "wget": set("aeiBtTwQPUlIXDARO")}


def tokenize(text):
    """Words as (text, quoted) and operators as (text, None). None on an unclosed quote.
    A command substitution anywhere outside single quotes is an operator token "$(" or "`"."""
    out, cur, quoted, i, n = [], "", False, 0, len(text)
    have = False

    def flush():
        nonlocal cur, quoted, have
        if have:
            out.append((cur, quoted))
        cur, quoted, have = "", False, False

    while i < n:
        c = text[i]
        if c == "\\":
            if i + 1 >= n:
                return None
            cur += text[i + 1]; have = True; i += 2; continue
        if c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                return None
            cur += text[i + 1:j]; have = quoted = True; i = j + 1; continue
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "`" or text.startswith("$(", j):
                    out.append(("$(", None))
                j += 2 if text[j] == "\\" else 1
            if j >= n:
                return None
            cur += text[i + 1:j]; have = quoted = True; i = j + 1; continue
        if c == "`":
            flush(); out.append(("`", None)); i += 1; continue
        if text.startswith("$(", i):
            flush(); out.append(("$(", None)); i += 2; continue
        if c in " \t":
            flush(); i += 1; continue
        if c == "\n":
            flush(); out.append((";", None)); i += 1; continue
        if c == "#" and not have:
            while i < n and text[i] != "\n":
                i += 1
            continue
        op = next((o for o in OPS if text.startswith(o, i)), None)
        if op:
            if op in REDIRS and have and not quoted and cur.isdigit():
                cur, have = "", False  # a descriptor prefix such as the 2 of 2>&1
            flush(); out.append((op, None)); i += len(op); continue
        cur += c; have = True; i += 1
    flush()
    return out


def redirect_refusal(tokens):
    for i, (word, quoted) in enumerate(tokens):
        if quoted is None and word in (">", ">>", ">|", ">&"):
            target = tokens[i + 1] if i + 1 < len(tokens) else None
            ok = False
            if target is not None and target[1] is not None:
                t = target[0]
                if t == "/dev/null":
                    ok = True
                elif word == ">&" and (t.isdigit() or t == "-"):
                    ok = True
            if not ok:
                return "output redirection to " + (target[0] if target else "nothing")
    return None


def segments_of(tokens):
    """Command words per segment; a redirection and its target are not command words."""
    starters = {"|", "||", "&&", ";", "&", "(", "`", "$("}
    segments, segment, skip = [], [], False
    for word, quoted in tokens:
        if skip:
            skip = False
            if quoted is not None:
                continue
        if quoted is None and word in REDIRS:
            skip = True
            continue
        if quoted is None and word in starters:
            if segment:
                segments.append(segment)
            segment = []
            continue
        if quoted is None:
            continue
        segment.append(word)
    if segment:
        segments.append(segment)
    return segments


def writes_file(name, rest):
    """True when curl or wget has an output target other than /dev/null."""
    i = 0
    while i < len(rest):
        w = rest[i]
        i += 1
        target = None
        if w == "--remote-name" or w == "--output-dir" or w.startswith("--output-dir="):
            return True
        if w in ("--output", "--output-document", "--output-file"):
            target = rest[i] if i < len(rest) else ""
            i += 1
        elif w.startswith(("--output=", "--output-document=", "--output-file=")):
            target = w.split("=", 1)[1]
        elif w.startswith("-") and not w.startswith("--") and len(w) > 1:
            for k, ch in enumerate(w[1:], 1):
                if ch == "o" or (ch == "O" and name == "wget"):
                    target = w[k + 1:]
                    if not target:
                        target = rest[i] if i < len(rest) else ""
                        i += 1
                    break
                if ch == "O":
                    return True
                if ch in VALUED[name]:
                    if k == len(w) - 1:
                        i += 1
                    break
        if target is not None and target != "/dev/null":
            return True
    return False


def refusal(tokens):
    if any(q is None and w in ("`", "$(") for w, q in tokens):
        return "command substitution"
    why = redirect_refusal(tokens)
    if why:
        return why
    # sudo as any word, even inside quotes passed to another command
    for word, quoted in tokens:
        if quoted is not None and any(os.path.basename(part) == "sudo" for part in word.split()):
            return "sudo"
    for words in segments_of(tokens):
        while words and (words[0] in SKIP or ("=" in words[0] and not words[0].startswith("=")
                                              and words[0].split("=", 1)[0].replace("_", "a").isalnum())):
            words.pop(0)
        if not words:
            continue
        name = os.path.basename(words[0])
        rest = words[1:]
        if name in REFUSED_WORDS:
            return "command " + name
        if name.startswith("pip"):
            return "command " + name
        if name == "brew" and (not rest or rest[0] not in BREW_OK):
            return "brew other than list, info, --prefix or config"
        if name == "find" and any(w in FIND_BAD for w in rest):
            return "find with -delete, -exec, -execdir or -ok"
        if name == "defaults" and (not rest or rest[0] != "read"):
            return "defaults other than defaults read"
        if name == "launchctl" and (not rest or rest[0] not in LAUNCHCTL_OK):
            return "launchctl other than list or print"
        if name == "git":
            while rest and rest[0] in ("-C", "--no-pager"):
                rest = rest[2:] if rest[0] == "-C" else rest[1:]
            if not rest or rest[0] not in GIT_OK:
                return "git other than rev-parse, status, log or ls-files"
        if name in ("curl", "wget") and writes_file(name, rest):
            return name + " writing a file"
    return None


tokens = tokenize(cmd)
if tokens is None:
    print("refused unreadable command")
    sys.exit(0)
why = refusal(tokens)
if why:
    print("refused " + why)
    sys.exit(0)

try:
    limit = float(os.environ.get("PERSON_CHECK_TIMEOUT") or 60)
except ValueError:
    limit = 60.0
p = subprocess.Popen(["sh", "-c", cmd], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
try:
    code = p.wait(timeout=limit)
except subprocess.TimeoutExpired:
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except OSError:
        p.kill()
    p.wait()
    print("timeout")
    sys.exit(0)
if code == 0:
    print("pass")
else:
    print("fail %d" % (code if code > 0 else 128 - code))
PY
