#!/bin/sh
# Runs the read-only check that ends a person step (` (check: `<command>`)`) and says whether it passed.
#   person-check.sh '<command>'
#     -> one line: pass | fail <exit code> | timeout | refused <why>
# The command runs from the current folder with `sh -c`, stdin and output from/to /dev/null, and a
# limit of 60 seconds (PERSON_CHECK_TIMEOUT seconds overrides it, for tests): stock macOS has no
# `timeout`, so python's subprocess enforces it. A command that is refused is never run. It is refused
# when it contains `sudo`, an output redirection (`>` or `>>` outside quotes) to anything but /dev/null
# or a file descriptor (`2>&1`), or one of these as a command word (first word, or first word after
# `|`, `||`, `&&`, `;`, `&`, `(`, a backtick or `$(`): rm rmdir mv cp ln tee dd chmod chown touch
# mkdir install kill killall pkill open osascript, `defaults` other than `defaults read`, `launchctl`
# other than `launchctl list|print`, brew, npm, pip, `git` other than `git rev-parse|status|log|ls-files`,
# `curl` or `wget` with `-o` or `-O`. A command that cannot be split into words (an unclosed quote) is
# `refused unreadable command`. The list is a guard against mistakes, not a sandbox.
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
                    "open osascript brew npm pip".split())
GIT_OK = {"rev-parse", "status", "log", "ls-files"}
LAUNCHCTL_OK = {"list", "print"}
SKIP = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "}", "time", "command", "exec"}
OPS = ["&&", "||", ">>", ">&", ">|", "<<", "|", ";", "&", "(", ")", ">", "<"]


def tokenize(text):
    """Words as (text, quoted) and operators as (text, None). None on an unclosed quote."""
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
            flush(); out.append((op, None)); i += len(op); continue
        cur += c; have = True; i += 1
    flush()
    return out


def refusal(tokens):
    starters = {"|", "||", "&&", ";", "&", "(", "`", "$("}
    segment = []
    i = 0
    segments = []
    while i < len(tokens):
        word, quoted = tokens[i]
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
        i += 1
    for word, quoted in tokens:
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
    for seg in segments:
        words = list(seg)
        while words and (words[0] in SKIP or ("=" in words[0] and not words[0].startswith("=")
                                              and words[0].split("=", 1)[0].replace("_", "a").isalnum())):
            words.pop(0)
        if not words:
            continue
        name = os.path.basename(words[0])
        rest = words[1:]
        if name == "sudo":
            return "sudo"
        if name in REFUSED_WORDS:
            return "command " + name
        if name == "defaults" and (not rest or rest[0] != "read"):
            return "defaults other than defaults read"
        if name == "launchctl" and (not rest or rest[0] not in LAUNCHCTL_OK):
            return "launchctl other than list or print"
        if name == "git" and (not rest or rest[0] not in GIT_OK):
            return "git other than rev-parse, status, log or ls-files"
        if name in ("curl", "wget"):
            for w in rest:
                if w in ("--output", "--remote-name", "--output-dir") or w.startswith("--output="):
                    return name + " writing a file"
                if w.startswith("-") and not w.startswith("--") and ("o" in w[1:] or "O" in w[1:]):
                    return name + " writing a file"
    # `env sudo x` and the like: sudo as any later word
    for word, quoted in tokens:
        if quoted is not None and os.path.basename(word) == "sudo":
            return "sudo"
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
