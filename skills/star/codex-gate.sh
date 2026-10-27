#!/bin/sh
# STAR's second-model gate: one headless `codex review` of a branch against its base, with the
# brief as the contract, written to STAR's home and read back as one verdict line.
#   codex-gate.sh --brief <brief> --item <item> --round <k> --base <ref>
#                 [--model <id|latest-<family>>] [--effort <level>] [--evidence <dir>]
#   codex-gate.sh post-pass --pr <url> --round <k> --head <sha> [--review <path>]
#                 [--carried-from <sha> --reason <text>] [--model <id>] [--effort <level>]
#   codex-gate.sh check
# The gate prints one line:
#   SAFE round=<k> findings=<n> unproven=<u> head=<sha> review=<path>
#   NOT-SAFE round=<k> findings=<n> p0=<a> p1=<b> unproven=<u> head=<sha> review=<path>
#   NOT-SAFE round=<k> findings=<n> p0=<a> p1=<b> tooling=<t> unproven=<u> head=<sha> review=<path>   (with a tooling file, #160)
# p0 and p1 count only the findings that block: a P0 or P1 with no indented "Evidence:" line (a command in
# backticks, or "test <path> <name> fails") is unproven (#209, <u> counts them), and a finding that repeats one
# an earlier round's -fix.md answered with "Disposition:" is marked dismissed (#210, <item>-dismissed.md).
# After a SAFE round, a small push is reviewed as a diff (#211): the Gate line ends "· scope diff from <sha7>"
# or "· scope full since <sha7>".
#   ERROR <why>
#   ERROR base-moved <ref> at <B7> changes <path>, a file this branch changes: merge it in, then run round <k>
#   ERROR gate-down <why>    neither Sol nor the fallback could review: STAR holds new builds
# post-pass prints: posted <url> | already <url> | ERROR <why>
# check prints: up <agent:model> | down <why>. It sends "Reply with the single word ok." through the
# gate's chain at effort low, 120 seconds each: codex exec on star.json's gate model, read-only
# with no MCP servers, then the Claude fallback. An answer with the word ok is up. STAR runs it
# while its gateDown flag is set, to learn when the gate is back (#64).
# Run the gate from the item's worktree. The brief's star: block gives home, project, notes,
# reviews and gates. Model and effort come from the flags, else star.json's "gate" block, else
# latest-sol and xhigh. A latest-<family> name, from a flag or from star.json, is resolved by
# ../ship-ticket/executor-model.sh before codex sees it (#65); a plain id is used as given.
# The round's base is pinned (#113): the commit --base names when the round starts replaces the ref
# in the prompt, so a fetch during the round cannot move it, and the review's Gate line ends
# "· base <ref> <full sha>". A base git cannot resolve is "ERROR the base <ref> is not a commit here".
# When that commit is not in HEAD's history, and a file it changed since the merge base is one the
# branch changed too, no agent runs and no round file is written. The gate prints the ERROR
# base-moved line above (<path> is the first such file in byte order), and the caller merges the
# base in and runs the same round again. A base that moved only in files the branch does not change
# is reviewed as it is.
# The prompt is template/gate-prompt.md, kept as <home>/specs/<project>/<item>-gate-r<k>.md.
# Its {{since}} line, from round 2, reads the head= of <item>-r<k-1>.md's VERDICT line: an earlier
# commit of HEAD makes the round review the commits since and check the previous findings, HEAD itself
# makes it judge the previous findings against their dispositions, and anything else (round 1, no
# previous review, an unknown head, a rewritten history) is "Review the whole change.".
# --evidence names the folder of the live checks' evidence (ship-ticket's Phase 6): the prompt
# points the reviewer at its report.md and says a criterion with no change in the diff behind it
# is judged on that evidence (#63); a folder that does not exist is a usage error. From round 2,
# when the previous round has no -fix.md (a re-scope), the prompt names the brief's ## Decisions
# records dated that review's day (UTC) or later as its dispositions (#67).
# <gates>/<item>-tooling.md (the folder of <item>-screen.md) lists the paths a build marked as
# tooling, one prefix per non-blank line, # lines ignored (#160): a prefix ending in / covers
# everything under it, one without covers that path and everything under it. The prompt grades
# those paths for safety only, and the NOT-SAFE line gains tooling=<t>, the count of P0 and P1
# findings whose every place (path:line) is under a prefix. Without a prefix the line has no tooling=.
# codex review runs read-only with no MCP servers; its stdout goes to <reviews>/<item>-r<k>.raw.md
# and its stderr to <item>-r<k>.log, and every line of both is copied to this script's stderr as
# it arrives, so the worker's terminal shows the review running (#71). The verdict line is the
# only line on stdout and the last line printed. <item>-r<k>.md starts with the VERDICT line review-proof.sh
# reads. A run that ends in ERROR keeps no round files (#66): the log, then "--- stdout" and the
# review text, then "--- ERROR <why>", move to <item>-r<k>-error-<n>.log (n counts up from 1), and
# <item>-r<k>.raw.md, .log and .md are left absent, so the caller runs the same round again. While
# an agent reviews, <item>-r<k>.run holds one JSON object, {"pid": the agent, "gate": this script,
# "agent": "codex" or "claude", "model", "attempt", "started", "log"}, for worker-probe.sh; it is
# removed on every exit. TERM, INT or HUP stops the agent and prints "ERROR stopped by SIG<NAME>";
# an agent ended by a signal from outside is "ERROR <codex|claude> review stopped by signal <n>",
# never gate-down.
# A finding is a bullet (-, *, +, 1. or 1)) that starts with its tag, [P0] to [P3], bold or
# not. Only a [P0] or [P1] finding makes it NOT-SAFE. A capacity, overload or rate-limit failure
# is retried after 60 and 180 seconds; a usage-limit failure (the phrases usage limit, hit your usage
# limit, try again at, out of credits and credit balance, matched without case, and only in the last 20 non-empty lines of codex's output) is not retried (#64). After those
# tries, at once on a usage limit, or when the model does not resolve, the same prompt runs
# through star.json's gate.fallback, {"agent": "claude", "model": "opus", "effort": "xhigh"} by
# default (a string there, v2.0.0's codex fallback, means that default; "agent" must be claude):
# claude -p --output-format json with read-only tools (Read, Grep, Glob; git diff, git show and
# git log, also after --no-pager or -P; git ls-tree, ls-files, rev-parse, merge-base and cat-file
# (#100); each also as git -C <this worktree's path> <command>, the path literal; never git -c or
# git grep; --output is refused), access to <home>, an appended system prompt that fixes the
# finding format, says to search with Grep and Glob and never git grep (#117) and to single-quote
# a shell metacharacter (#100), no MCP server and no
# saved session. The JSON's "result" is the review, read by the same rules, and the review's line is
# "Gate: claude:<model> <effort> (fallback: <why>)". A fallback that did not review is
# "ERROR gate-down <why>", and so is gate.fallback null: a non-zero exit, no output, output that is
# not JSON, "is_error" true, a "subtype" other than success, an empty result, or any entry in
# "permission_denials" on the second try. claude -p exits 0 and answers in prose when a tool is
# denied, and that prose has no tag to read, so a denial is never taken for a clean review. A run
# whose only failure is a denial runs once more in the same round (#100), its prompt ending with
# one line per denied command: "Your previous run was denied: <command>. Search with Grep and find
# files with Glob (never git grep, grep or rg), read a file with Read, and run any other git command
# as one plain command, single-quoting any argument that holds a shell metacharacter." No git grep
# rule is safe, since its -O runs a program, so a denied search is sent to Grep (#117). The second
# run's result is the one read, and the first run's output stays in
# <item>-r<k>.log under "--- stdout", beside the second's. An ERROR reason is one
# line: its whitespace is collapsed, since it can quote model text. Anything else is ERROR,
# so a review the gate cannot read is never SAFE: any other codex failure, an empty review, an
# output whose first line starts with "error" (any case) or "⚠" (codex printed a failure and still
# exited 0), HEAD moving during the review,
# a line that holds a [P0]-[P3] tag outside that shape ("a finding in a shape the gate cannot
# read"), a "Review comment(s):" header with no tagged finding under it, and a bullet that ends
# with its place (<path>:<line> or <path>:<line>-<line>, after a hyphen, an en dash or an em
# dash, or in parentheses) and carries no tag ("findings without [P0]-[P3] tags").
# The parser stays strict: a tag outside a finding bullet is never read as prose. The fallback's
# prompt says to write a tag only at the start of a bullet, to state any P0 or P1 problem as a tagged
# finding bullet, and to end the review with exactly one last line, "VERDICT: SAFE" or "VERDICT:
# NOT-SAFE" (#185). Only a fallback review is held to that line, and the line is neither a note nor a
# finding. A fallback review with no VERDICT line or more than one ("no VERDICT line", "more than one
# VERDICT line"), or with VERDICT: NOT-SAFE and no P0 or P1 finding bullet ("VERDICT NOT-SAFE without
# a P0 or P1 finding"), is unreadable. VERDICT: SAFE beside a P0 or P1 bullet is NOT-SAFE: the bullets
# win. An unreadable fallback review runs once more in the same round (#185), its prompt ending with
# a line that names the problem: for a tag outside a finding bullet, "Your previous review wrote a
# grade tag outside a finding bullet: "<the first offending line, cut to 160 characters>". Write a
# [P0] to [P3] tag only at the start of a finding bullet."; for an untagged finding bullet, "Your
# previous review had a finding bullet without a [P0] to [P3] tag: "<line>". Start every finding bullet
# with its tag."; for a VERDICT problem, a line that names it and repeats the VERDICT rule. A round
# runs the fallback at most twice, counting the #100 denial re-run. HEAD is checked after each
# fallback run that is unreadable, before any re-run and before the ERROR below, so a moved HEAD is
# "ERROR HEAD moved during the review", never a free retry. An unreadable fallback review after the
# re-run is "ERROR fallback-unreadable <why>" (same exit code), with both runs kept in the error log;
# an unreadable codex review keeps "ERROR unreadable review: <why>". The worker waits 10 minutes and
# runs the round again, without spending its one retry on it.
# post-pass posts two lines on the PR, "Codex gate: PASS (head <sha>, round <k>, <model> <effort>)"
# and "VERDICT: PASS", the line a project's review rule reads (#84), once per head. A direct call
# (no --carried-from, and a --review that is not -carried.md) prints already only over a comment by
# the PR's author whose first line is "Codex gate: PASS (head <sha>, round <n>, <model> <effort>)"
# for this full head: a direct verdict supersedes a carry (#104). A carried call prints already over
# any comment by the PR's author that starts "Codex gate: PASS (head <sha>". --head must
# be the PR's current head, all 40 characters. GitHub can show the previous head
# for a few seconds after a push, so post-pass reads the PR's head every 5 seconds for up to 90
# (times CODEX_GATE_SLEEP) until it is --head, and only then refuses (#62). The model and effort are
# --model and --effort, else the "Gate: <model> <effort>" line of the --review file (the model
# that ran, a fallback included), else the "gate" block of the project's star.json
# ($JUEL_STAR_HOME, else the folder star-home.sh names), else latest-sol and xhigh; a
# latest-<family> name is resolved as above, or left as written when it does not resolve. A --review
# file that cannot be read is ERROR, and so is one that is not this round's SAFE verdict: its first
# line must be "VERDICT item=<item> round=<k> SAFE findings=<n> head=<7 to 40 hex characters>"
# with the head the start of --head, and no <item>-r<k+1>.md may lie beside it. Nothing is posted.
# Two receipts carry a verdict to a head no round reviewed, so none is ever written by hand.
# --carried-from <G> --reason <text> (#75): --review is G's SAFE review of round <k>, checked
# against G, and --head is merges of the base on top of G. post-pass runs carry-check.sh --from G
# --head <head> --base <the PR's baseRefName as a remote-tracking branch, origin's when there is
# one> itself, and anything but OK is "ERROR not carried: <why>". The first line then ends
# ", carried from <G full sha>: <reason>)". A --review named <item>-r<k>-carried.md (#82) is the
# owner's decision to ship with round k's findings deferred: review-proof.sh must answer
# "OK carried round=<k>" for --head; the model and effort come from round k's own review's "Gate:"
# line when the flags do not give them; the first line ends ", carried by owner decision <id>:
# findings deferred)" and the second line is "VERDICT: PASS (owner decision <id>)".
# --carried-from with a carried file, --carried-from without --review, and --reason without
# --carried-from or the reverse, are bad usage.
# Test seams: CODEX_GATE_SLEEP multiplies the waits (default 1); CODEX_GATE_TIMEOUT, seconds per
# codex run (default 3600).
# When GH_TOKEN is unset, gh runs with the token of the account star.json configures (gh-token.sh, #137).
# Exit: 0 with a verdict, a post-pass result or up; 69 with ERROR or down; 64 on bad usage.
STAR_SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
export STAR_SKILL_DIR
exec python3 - "$@" <<'PY'
import atexit
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time

S = os.environ["STAR_SKILL_DIR"]
CAPACITY = re.compile(r"at capacity|overloaded|rate.?limit|too many requests|service unavailable"
                      r"|\b(429|503|529)\b", re.I)
BULLET = r"(?:[-*+]|\d+[.)])"
TAG = re.compile(r"^\s*" + BULLET + r"\s*(?:\*\*)?\[P([0-3])\](?:\*\*)?\s+(.*\S)\s*$")
ANY_TAG = re.compile(r"\[P[0-3]\]")
FINDINGS_HEADER = re.compile(r"^\s*review comments?:\s*$", re.I)
# The shape of a finding with its tag dropped: a bullet at the margin that ends with its place,
# "<path>:<line>[-<line>]", set off by a hyphen, an en dash or an em dash, or put in parentheses
PLACED = re.compile(r"^" + BULLET + r"\s+(?!(?:\*\*)?\[P[0-3]\]).*\S\s+(?:[-–—]\s+|\()\S.*:\d+(?:-\d+)?\)?\s*$")
USAGE = re.compile(r"usage limit|hit your usage limit|try again at|out of credits|credit balance", re.I)
DEFAULT_FALLBACK = {"agent": "claude", "model": "opus", "effort": "xhigh"}
SUBCOMMANDS = ("diff", "show", "log")
# #100: the other read-only commands a review reaches for, and diff, show and log with the pager off. Never
# "git -c" (it sets any config, diff.external among them) and never "git grep" (its -O runs a command).
MORE_READS = ("ls-tree", "ls-files", "rev-parse", "merge-base", "cat-file", "--no-pager diff", "--no-pager show",
              "--no-pager log", "-P diff", "-P show", "-P log")


def worktree_paths():
    """The directory the gate runs in, as the process sees it, its realpath, and $PWD when that names
    the same directory (macOS: /var/... against /private/var/...), because the model uses any of them."""
    here = os.getcwd()
    logical = os.environ.get("PWD", "")
    same = logical and os.path.realpath(logical) == os.path.realpath(here)
    return here, os.path.realpath(here), logical if same else ""


def read_only(*roots):
    """The fallback's allow rules: Read, Grep, Glob, "git diff|show|log ...", and the same as
    "git -C <root> diff|show|log ..." for each given path, then the same for MORE_READS (#100). The path is
    literal: a "*" there would match a whole subcommand ("git -C x branch diff", "git -C x -c
    diff.external=<script> diff"). A path with a glob character gets no -C rule."""
    roots = list(dict.fromkeys(r for r in roots if r and not any(c in r for c in "*?[")))
    forms = []
    for commands in (SUBCOMMANDS, MORE_READS):
        forms += [f"{sub} *" for sub in commands]
        forms += [f"-C {root} {sub}{more}" for root in roots for sub in commands for more in ("", " *")]
    return ["Read", "Grep", "Glob"] + [f"Bash(git {form})" for form in forms]


# the options of those commands that write a file
NO_WRITE = ["Bash(git * --output*)"]
# codex review has its own output shape; the fallback is told the shape the parser below reads
FORMAT = ("Write the review as plain text: first one short paragraph with your overall verdict, then each "
          "finding as one bullet line, \"- [P<n>] <title> — <path>:<line>\", with any detail indented on the "
          "lines below it. Write a [P0] to [P3] tag only at the start of a finding bullet: outside a finding "
          "bullet, never write a [P0] to [P3] tag; state any P0 or P1 problem as a tagged finding bullet. "
          "Give every [P0] and [P1] finding one indented `Evidence:` line: a command whose output shows the "
          "defect, in backticks, or `test <path> <name> fails`; without it the finding is reported but does not "
          "block. Then end the review with exactly one last line, `VERDICT: SAFE` or `VERDICT: NOT-SAFE`, NOT-SAFE when "
          "you found any P0 or P1. Use only Read, Grep, Glob, git diff, git show, git log, git ls-tree, git ls-files, "
          "git rev-parse, git merge-base and git cat-file, one command per call with no pipe, redirect, && or "
          "||: any other command is refused, and a refused command fails the review. Search with Grep and find "
          "files with Glob, never git grep, grep or rg. Single-quote any argument that holds a shell "
          "metacharacter (`& | ; < > ( ) [ ] * ? $`), and never use `$(…)`. Write nothing else, and change "
          "nothing.")
# the line a fallback run's prompt gets for each command its previous run was denied (#100). It sends a search to
# Grep and Glob: no git grep rule is safe, since git grep -O runs a program (#117)
DENIED = ("Your previous run was denied: {}. Search with Grep and find files with Glob (never git grep, grep or rg), "
          "read a file with Read, and run any other git command as one plain command, single-quoting any argument "
          "that holds a shell metacharacter.")
try:
    PAUSE = float(os.environ.get("CODEX_GATE_SLEEP", "1"))
except ValueError:
    PAUSE = 1.0


def out(line, code=0):
    sys.stderr.flush()  # the review streamed on stderr; the verdict is the last line anyone sees
    print(line, flush=True)
    sys.exit(code)


ROUND = {}  # the round's files, set just before its first review run
CHILD = {}  # the review agent running now


def error(why):
    why = " ".join(str(why).split())  # model text can hold newlines: an ERROR is always exactly one line
    if ROUND.get("raw"):
        keep_error_log(why)
    out(f"ERROR {why}", 69)


def keep_error_log(why):
    """An ERROR keeps no round files (#66): the transcript moves to <item>-r<k>-error-<n>.log."""
    r, raw = ROUND, ROUND.pop("raw")
    pattern = re.compile(re.escape(r["item"]) + rf"-r{r['k']}-error-(\d+)\.log")
    taken = [int(m.group(1)) for m in map(pattern.fullmatch, os.listdir(r["reviews"])) if m]
    parts = []
    for path, title in ((r["log"], ""), (raw, "--- stdout\n")):
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                parts.append(title + f.read())
            os.remove(path)
        except OSError:
            pass
    target = os.path.join(r["reviews"], f"{r['item']}-r{r['k']}-error-{max(taken, default=0) + 1}.log")
    with open(target, "w", encoding="utf-8") as f:
        f.write("".join(p if p.endswith("\n") or not p else p + "\n" for p in parts) + f"--- ERROR {why}\n")
    drop_run()


def drop_run():
    try:
        os.remove(ROUND.get("run") or "")
    except OSError:
        pass


atexit.register(drop_run)


def die(msg):
    print(f"codex-gate.sh: {msg}", file=sys.stderr)
    sys.exit(64)


def run(cmd, timeout=120):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 127, "", f"{cmd[0]}: {e}")


def last_line(text):
    lines = [l.strip() for l in (text or "").splitlines() if l.strip()]
    return lines[-1][:160] if lines else ""


def last_lines(text, n):
    """The last n non-empty lines of a text, so words a diff quotes earlier in it are not read."""
    return "\n".join([l for l in (text or "").splitlines() if l.strip()][-n:])


def resolve(name, effort_):
    """(model, effort) for a Codex model name, or (None, why). latest-<family> is resolved by
    ../ship-ticket/executor-model.sh (#65); a plain id is used as given."""
    if not name.startswith("latest-"):
        return name, effort_
    r = run(["sh", os.path.join(os.path.dirname(S), "ship-ticket", "executor-model.sh"),
             "--model", name, "--effort", effort_], 60)
    words = r.stdout.split()
    if r.returncode == 0 and len(words) == 2 and words[0] != "default":
        return words[0], words[1]
    if r.returncode == 0 and words[:1] == ["default"]:
        return None, " ".join(words[1:]) or "executor-model.sh named no model"
    return None, last_line(r.stderr or r.stdout) or f"executor-model.sh exited {r.returncode}"


def fallback_of(gate_):
    """star.json's gate.fallback as a Claude block, or None when it is null or names another agent.
    A missing key, or a string (v2.0.0's codex fallback), means the default block."""
    fb = gate_.get("fallback", DEFAULT_FALLBACK)
    if fb is None:
        return None
    if not isinstance(fb, dict):
        return dict(DEFAULT_FALLBACK)
    fb = {**DEFAULT_FALLBACK, **{key: v.strip() for key, v in fb.items() if isinstance(v, str) and v.strip()}}
    return fb if fb["agent"] == "claude" else None


def options(argv, names):
    found, args = {}, list(argv)
    while args:
        arg = args.pop(0)
        if arg not in names or not args or not args[0].strip():
            die(f"unknown or empty argument: {arg}")
        found[arg[2:]] = args.pop(0).strip()
    return found


def project_gate():
    """star.json's "gate" block, for post-pass, which has no brief: $JUEL_STAR_HOME, else star-home.sh path."""
    home = os.environ.get("JUEL_STAR_HOME") or run(["sh", os.path.join(S, "star-home.sh"), "path"], 30).stdout.strip()
    try:
        gate = json.load(open(os.path.join(home, "star.json"), encoding="utf-8")).get("gate") if home else None
    except (OSError, ValueError, AttributeError):
        gate = None
    return gate if isinstance(gate, dict) else {}


def use_star_token(home):
    """GH_TOKEN for the account star.json configures (#137), when this process has none."""
    if os.environ.get("GH_TOKEN"):
        return
    cmd = ["sh", os.path.join(S, "gh-token.sh")]
    if home:
        cmd += ["--home", home]
    try:
        proc = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=40)
        if proc.returncode == 0:
            token = proc.stdout.strip()
            if token and "\n" not in token and "\r" not in token:
                os.environ["GH_TOKEN"] = token
    except (OSError, subprocess.TimeoutExpired):
        pass


def check_review(text, path, k, head):
    """ERROR unless the review is the SAFE verdict of round k on head, with no newer round beside it."""
    first = (text.splitlines() or [""])[0]
    m = re.fullmatch(r"VERDICT item=(\S+) round=(\d+) (SAFE|NOT-SAFE) findings=(\d+) head=([0-9a-fA-F]{7,40})", first)
    if not m:
        error(f"the review's first line is not a full VERDICT line: {first[:120]!r}")
    item, rnd, verdict, _, reviewed = m.groups()
    if verdict != "SAFE":
        error(f"the review says {verdict}, not SAFE")
    if int(rnd) != k:
        error(f"the review is of round {rnd}, not round {k}")
    if not head.startswith(reviewed.lower()):
        error(f"the review is of {reviewed[:7].lower()}, not {head[:7]}")
    later = os.path.join(os.path.dirname(os.path.abspath(path)), f"{item}-r{k + 1}.md")
    if os.path.exists(later):
        error(f"round {k + 1} has its own review at {later}")


CARRIED_REVIEW = re.compile(r".+-r\d+-carried\.md")


def pr_view(pr):
    """(author, comments, head, url, base branch) of the PR, or ERROR."""
    view = run(["gh", "pr", "view", pr, "--json", "author,baseRefName,comments,headRefOid,url"], 60)
    if view.returncode != 0:
        error("gh: " + (last_line(view.stderr or view.stdout) or "failed"))
    try:
        d = json.loads(view.stdout)
        author = (d.get("author") or {}).get("login") or ""
        comments = [c for c in (d.get("comments") or []) if isinstance(c, dict)]
    except (ValueError, AttributeError):
        error("gh: unreadable output")
    return author, comments, str(d.get("headRefOid") or "").lower(), d.get("url"), str(d.get("baseRefName") or "")


def full_commit(rev):
    """The full sha of a commit git knows here, or ERROR."""
    r = run(["git", "rev-parse", "--verify", "--quiet", rev + "^{commit}"], 30)
    if r.returncode != 0 or not r.stdout.strip():
        error(f"not carried: git knows no commit {rev}")
    return r.stdout.strip().lower()


def owner_carry(path, text, k, head):
    """(decision id, round k's own review) of the owner's carried PASS, once review-proof.sh accepts
    it for head (#82)."""
    first = (text.splitlines() or [""])[0]
    m = re.fullmatch(r"CARRIED item=(\S+) round=\d+ head=[0-9a-f]{40} from=(\S+) decision=(\S+)", first)
    if not m:
        error(f"the carried review's first line is not a full CARRIED line: {first[:120]!r}")
    item, source, decision = m.groups()
    proof = run(["sh", os.path.join(os.path.dirname(S), "babysit-pr", "review-proof.sh"), path,
                 "--item", item, "--head", head], 30)
    said = last_line(proof.stdout) or last_line(proof.stderr) or f"review-proof.sh exited {proof.returncode}"
    if said.startswith("OK carried round=") and said != f"OK carried round={k}":
        error(f"the carried review is of round {said.rsplit('=', 1)[1]}, not round {k}")
    if said != f"OK carried round={k}":
        error("the carried review is not proof for this head: " + (said[3:] if said.startswith("NO ") else said))
    return decision, os.path.join(os.path.dirname(os.path.abspath(path)), source)


def carry(gated, head, base):
    """ERROR unless carry-check.sh proves head is gated plus merges of the PR's base and nothing else (#75)."""
    if not base:
        error("not carried: the PR's base branch is unknown")
    refs = run(["git", "for-each-ref", "--format=%(refname:short)", f"refs/remotes/*/{base}"], 30).stdout.split()
    ref = f"origin/{base}" if f"origin/{base}" in refs else (refs[0] if len(refs) == 1 else "")
    if not ref:
        found = ", ".join(refs) or "none"
        error(f"not carried: no single remote-tracking branch for the base {base} (found: {found})")
    r = run(["sh", os.path.join(S, "carry-check.sh"), "--from", gated, "--head", head, "--base", ref], 120)
    said = last_line(r.stdout)
    if r.returncode != 0 or not said.startswith("OK carried from "):
        why = said[3:] if said.startswith("NO ") else (said or last_line(r.stderr) or f"carry-check.sh exited {r.returncode}")
        error("not carried: " + why)


def post_pass(o):
    use_star_token(None)
    head = o["head"].lower()
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        die("--head takes the full 40-character commit")
    k = int(o["round"])
    ran, clause, verdict = None, "", "VERDICT: PASS"
    gated = full_commit(o["carried-from"]) if o.get("carried-from") else head
    if o.get("review"):
        try:
            review_text = open(o["review"], encoding="utf-8", errors="replace").read()
        except OSError as e:
            error(f"cannot read the review: {e.strerror}")
        if CARRIED_REVIEW.fullmatch(os.path.basename(o["review"])):
            decision, source = owner_carry(o["review"], review_text, k, head)
            clause = f", carried by owner decision {decision}: findings deferred"
            verdict = f"VERDICT: PASS (owner decision {decision})"
            try:  # the model and effort of the round the owner carried
                review_text = open(source, encoding="utf-8", errors="replace").read()
            except OSError:
                review_text = ""
        else:
            check_review(review_text, o["review"], k, gated)
        ran = re.search(r"^Gate: (\S+) (\S+)", review_text, re.M)
    model, effort = o.get("model") or (ran and ran.group(1)), o.get("effort") or (ran and ran.group(2))
    if not model or not effort:
        gate = project_gate()
        model, effort = model or gate.get("model") or "latest-sol", effort or gate.get("effort") or "xhigh"
    if model.startswith("latest-"):
        named = resolve(model, effort)
        model, effort = named if named[0] else (model, effort)
    author, comments, pr_head, url, base = pr_view(o["pr"])
    for _ in range(18):  # GitHub can show the previous head for a few seconds after a push (#62)
        if pr_head == head:
            break
        time.sleep(5 * PAUSE)
        author, comments, pr_head, url, base = pr_view(o["pr"])
    if pr_head != head:
        error(f"the PR's head is {pr_head[:7] or '?'}, not {head[:7]}, after 90 s")
    if o.get("carried-from"):
        carry(gated, head, base)
        reason = " ".join(o["reason"].split())
        clause = f", carried from {gated}: {reason}"
    prefix = f"Codex gate: PASS (head {head}"
    # a direct verdict supersedes a carry (#104): a direct call counts only a direct receipt for this head, a
    # carried call (both carry forms set clause) any receipt for it
    direct = re.compile(re.escape(prefix) + r", round \d+, \S+ \S+\)")
    for c in comments:
        body = str(c.get("body") or "")
        done = body.startswith(prefix) if clause else direct.fullmatch((body.splitlines() or [""])[0])
        if (c.get("author") or {}).get("login") == author and done:
            out(f"already {c.get('url') or url}")
    body = f"Codex gate: PASS (head {head}, round {o['round']}, {model} {effort}{clause})\n{verdict}"
    posted = run(["gh", "pr", "comment", o["pr"], "--body", body], 60)
    if posted.returncode != 0:
        error("gh: " + (last_line(posted.stderr or posted.stdout) or "failed"))
    out(f"posted {last_line(posted.stdout) or url}")


PING = "Reply with the single word ok."


def check():
    """up <agent:model> when Sol or the fallback answers a one-line prompt, else down <why> (#64)."""
    gate = project_gate()
    asked = gate.get("model") or "latest-sol"
    model_, why = resolve(asked, "low")
    if model_ is None:
        reasons = [f"sol: cannot resolve {asked}: {why}"]
    else:
        r = run(["codex", "exec", "--strict-config", "--skip-git-repo-check", "-c", f'model="{model_}"',
                 "-c", 'model_reasoning_effort="low"', "-c", 'sandbox_mode="read-only"', "-c", "mcp_servers={}",
                 PING], 120)
        if r.returncode == 0 and re.search(r"\bok\b", r.stdout, re.I):
            out(f"up codex:{model_}")
        reasons = ["sol: " + (last_line(r.stderr or r.stdout) or f"exit {r.returncode}")]
    fb = fallback_of(gate)
    if fb is None:
        out("down " + reasons[0] + "; no fallback is set", 69)
    r = run(["claude", "-p", PING, "--model", fb["model"], "--effort", "low", "--strict-mcp-config",
             "--no-session-persistence"], 120)
    if r.returncode == 0 and re.search(r"\bok\b", r.stdout, re.I):
        out(f"up claude:{fb['model']}")
    out("down " + reasons[0] + "; claude: " + (last_line(r.stderr or r.stdout) or f"exit {r.returncode}"), 69)


argv = sys.argv[1:]
if argv[:1] == ["check"]:
    if argv[1:]:
        die("check takes no arguments")
    check()
if argv[:1] == ["post-pass"]:
    o = options(argv[1:], ("--pr", "--round", "--head", "--review", "--model", "--effort", "--carried-from", "--reason"))
    for key in ("pr", "round", "head"):
        if key not in o:
            die(f"post-pass needs --{key}")
    if not o["round"].isdigit():
        die("--round takes a number")
    if ("carried-from" in o) != ("reason" in o):
        die("--carried-from and --reason go together")
    if "carried-from" in o and "review" not in o:
        die("--carried-from needs --review, the gated head's SAFE review")
    if "carried-from" in o and CARRIED_REVIEW.fullmatch(os.path.basename(o["review"])):
        die("--carried-from does not go with a carried review")
    if "carried-from" in o and not re.fullmatch(r"[0-9a-fA-F]{7,40}", o["carried-from"]):
        die("--carried-from takes 7 to 40 hex characters")
    post_pass(o)

o = options(argv, ("--brief", "--item", "--round", "--base", "--model", "--effort", "--evidence"))
for key in ("brief", "item", "round", "base"):
    if key not in o:
        die(f"the gate needs --{key}")
if "evidence" in o:
    o["evidence"] = os.path.abspath(o["evidence"])
    if not os.path.isdir(o["evidence"]):
        die(f"--evidence is not a folder: {o['evidence']}")
if not o["round"].isdigit() or int(o["round"]) < 1:
    die("--round takes a number from 1")
item, k, base, brief = o["item"], int(o["round"]), o["base"], os.path.abspath(o["brief"])


def star_block(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        die(f"cannot read the brief: {e.strerror}")
    m = re.match(r"﻿?---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
    found, inside = {}, False
    for line in (m.group(1).splitlines() if m else []):
        kv = re.match(r"(\s*)([A-Za-z_]+):\s*(.*?)\s*$", line)
        if not kv:
            continue
        if not kv.group(1):
            inside = kv.group(2) == "star"
        elif inside:
            found[kv.group(2)] = kv.group(3).strip("'\"")
    return found


star = star_block(brief)
home, project = star.get("home"), star.get("project")
if not home or not project:
    die("the brief has no star: block with home and project")
reviews = star.get("reviews") or os.path.join(home, "reviews", project)
notes = [n.strip().strip("'\"") for n in star.get("notes", "").strip("[]").split(",") if n.strip()]
def read_tooling(gates_dir, item):
    try:
        lines = [l.strip() for l in open(os.path.join(gates_dir, f"{item}-tooling.md"), encoding="utf-8")]
    except OSError:
        return []
    return [l for l in lines if l and not l.startswith("#")]


def tooling_count(findings, prefixes):
    top = run(["git", "rev-parse", "--show-toplevel"], 30)
    top = top.stdout.strip().rstrip("/") if top.returncode == 0 else ""
    norm = [os.path.normpath(p[2:] if p.startswith("./") else p) for p in prefixes]

    def covered(path):
        return any(path == n or path.startswith(n.rstrip("/") + "/") for n in norm)

    count = 0
    for f in findings:
        if f["p"] > 1:
            continue
        paths = []
        for tok in re.split(r"[\s,;]+", f["where"].replace("`", "")):
            m = re.fullmatch(r"(.+):\d+(?:-\d+)?", tok)
            if not m:
                continue
            path = m.group(1)
            if top and path.startswith(top + "/"):
                path = path[len(top) + 1:]
            while path.startswith("./"):
                path = path[2:]
            paths.append(os.path.normpath(path))
        if paths and all(covered(p) for p in paths):
            count += 1
    return count


gates_dir = os.path.dirname(star.get("gates") or os.path.join(home, "gates", project, f"{item}.json"))
tooling_prefixes = read_tooling(gates_dir, item)
try:
    gate = json.load(open(os.path.join(home, "star.json"), encoding="utf-8")).get("gate")
except (OSError, ValueError, AttributeError):
    gate = None
gate = gate if isinstance(gate, dict) else {}
asked = o.get("model") or gate.get("model") or "latest-sol"
effort = o.get("effort") or gate.get("effort") or "xhigh"
model, resolved = resolve(asked, effort)
if model is not None:
    effort = resolved
fb = fallback_of(gate)
try:
    LIMIT = float(os.environ.get("CODEX_GATE_TIMEOUT", "3600"))
except ValueError:
    LIMIT = 3600.0


# the label anywhere in a finding, in codex's own shapes: Evidence:, **Evidence:**, **Evidence**: (#209)
EVIDENCE = re.compile(r"(?<![A-Za-z])Evidence(?:\*\*|\*|_)?\s*:(?:\*\*|\*|_)?", re.I)
FAILING_TEST = re.compile(r"test\s+\S+\s+\S.*?\s+fails\b", re.I)
MARKS = re.compile(r"\s*\((?:unproven: [^)]*|repeat of [^)]*)\)\s*$")
TEST_PATH = re.compile(r"(^|/)(tests?|__tests__|spec)/|\.(test|spec)\.|_test\.|^docs/|\.md$")
SMALL_LINES, SMALL_FILES = 400, 15
SCOPE = {}  # set by since_text when #211's rule applies: the review's "scope ..." footer


def proves(clause):
    """True when an evidence clause is a command in backticks or a test that fails."""
    return bool(re.search(r"`[^`]+`", clause) or FAILING_TEST.match(clause.strip()))


def label_alone(rest):
    """The clause of an Evidence label with nothing after it: the next non-blank line, or the fenced block after it."""
    rest = [l.strip() for l in rest if l.strip()]
    if not rest:
        return ""
    if not rest[0].startswith("```"):
        return rest[0]
    block = []
    for line in rest[1:]:
        if line.startswith("```"):
            break
        block.append(line)
    return f"`{' '.join(block)}`" if block else ""


def has_evidence(f):
    """True when an Evidence clause anywhere in the finding's title, place or body (#209) is a command in
    backticks or a test that fails; a label with nothing after it takes the next line or the fenced block."""
    lines = [f["title"], f["where"], *f["body"]]
    for i, line in enumerate(lines):
        for m in EVIDENCE.finditer(line):
            if proves(line[m.end():].strip() or label_alone(lines[i + 1:])):
                return True
    return False


def words(text):
    return re.findall(r"[a-z0-9_]+", text.lower())


def sha10(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:10]


def place_of(where):
    """(path, line) from a finding's place, a path relative to the worktree, or None. The whole place is tried
    first, so a path with a space reads; a list of places gives its first."""
    text = where.replace("`", "").strip()
    whole = re.fullmatch(r"((?:(?!:\d).)+):(\d+)(?:-\d+)?", text)
    for tok in ([text] if whole else re.split(r"[\s,;]+", text)):
        m = re.fullmatch(r"(.+):(\d+)(?:-\d+)?", tok)
        if m:
            path = m.group(1)
            top = run(["git", "rev-parse", "--show-toplevel"], 30).stdout.strip()
            if top and os.path.isabs(path) and path.startswith(os.path.realpath(top) + "/"):
                path = os.path.relpath(path, os.path.realpath(top))
            return path, int(m.group(2))
    return None


def cited_line(place, rev):
    """The stripped text of the line a place cites at rev, or None when it cannot be read."""
    r = run(["git", "show", f"{rev}:{place[0]}"], 30)
    lines = r.stdout.splitlines() if r.returncode == 0 else []
    return lines[place[1] - 1].strip() if 0 < place[1] <= len(lines) else None


def fingerprint(where, title, rev):
    """(path, hash): the path (spaces as %20, so an entry stays one word) and the sha1 of the cited line at rev, or
    ('-', the sha1 of the normalized title) for a finding with no place. A line that cannot be read hashes to '-',
    so only the title can match it (#210)."""
    place = place_of(where)
    if place is None:
        return "-", sha10(" ".join(words(title)))
    text = cited_line(place, rev)
    return place[0].replace(" ", "%20"), sha10(text) if text is not None else "-"


def round_findings(j):
    """{n: (p, title, where, blocked)} and the head of round j's review file, or ({}, ''). A finding blocked
    in its round when it is a P0 or P1 with neither the unproven nor the repeat mark."""
    found, head_of = {}, ""
    try:
        text = open(os.path.join(reviews, f"{item}-r{j}.md"), encoding="utf-8").read()
    except OSError:
        return found, head_of
    m = re.search(r"\bhead=([0-9a-f]{7,40})\b", text.split("\n", 1)[0])
    head_of = m.group(1) if m else ""
    for line in text.splitlines():
        m = re.match(r"(\d+)\. \[P([0-3])\] (.*)$", line)
        if m:
            title, sep, where = m.group(3).rpartition(" — ")
            shown = title if sep else m.group(3)
            found[int(m.group(1))] = (int(m.group(2)), MARKS.sub("", shown), where if sep else "",
                                      int(m.group(2)) <= 1 and not MARKS.search(shown))
    return found, head_of


def dispositions(j):
    """{n: reason} from round j's -fix.md; a line with no number is ignored (#210)."""
    try:
        lines = open(os.path.join(reviews, f"{item}-r{j}-fix.md"), encoding="utf-8").read().splitlines()
    except OSError:
        return {}
    out = {}
    for line in lines:
        m = re.match(r"\s*(\d+)[.)]\s+Disposition:\s*(.+?)\s*$", line)
        if m:
            out.setdefault(int(m.group(1)), m.group(2))
    return out


DISMISSED_LINE = re.compile(r"^(\S+) r(\d+)#(\d+) \[P([0-3])\] (\S+) (.*)$")


def record_dismissed():
    """Record, once per finding, every blocking finding an earlier round's -fix.md answered with a Disposition (#210)
    in <item>-dismissed.md, and return the entries as (path, hash, ref, p, place, title, reason). A finding that did
    not block in its round (P2, P3, unproven, repeat) needs no disposition and is never recorded."""
    path = os.path.join(reviews, f"{item}-dismissed.md")
    reasons = {}
    try:
        have = {"r" + m.group(2) + "#" + m.group(3) for m in map(DISMISSED_LINE.match, open(path, encoding="utf-8").read().splitlines()) if m}
    except OSError:
        have = set()
    fresh = []
    for j in range(1, k):
        found, head_of = round_findings(j)
        for n, reason in dispositions(j).items():
            reasons[(j, n)] = reason
            if n in found and found[n][3] and f"r{j}#{n}" not in have:
                p, title, where, _ = found[n]
                fp = fingerprint(where, title, head_of or "HEAD")
                place = place_of(where)
                fresh.append(f"{fp[0]}:{fp[1]} r{j}#{n} [P{p}] {fp[0] + ':' + str(place[1]) if place else '-'} {title}")
    if fresh:
        with open(path, "a", encoding="utf-8") as f:
            f.write("\n".join(fresh) + "\n")
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        return []
    entries = []
    for m in filter(None, map(DISMISSED_LINE.match, lines)):
        fp_path, _, fp_hash = m.group(1).rpartition(":")
        reason = reasons.get((int(m.group(2)), int(m.group(3)))) or dispositions(int(m.group(2))).get(int(m.group(3)), "no reason recorded")
        entries.append((fp_path, fp_hash, f"r{m.group(2)}#{m.group(3)}", int(m.group(4)), m.group(5), m.group(6), reason))
    return entries


def dismissed_text(entries):
    if not entries:
        return "No finding has been dismissed."
    listing = "\n".join(f"- {ref} [P{p}] {place.replace('%20', ' ')} {title}: {reason}"
                        for _, _, ref, p, place, title, reason in entries)
    return ("Findings dismissed in earlier rounds, each with its reason:\n" + listing + "\nThese were dismissed with a "
            "reason. Do not raise them again unless the code at their place has changed since; then say what changed.")


TRIVIAL = {"if", "else", "elif", "end", "fi", "then", "do", "done", "for", "while", "return", "try", "catch",
           "except", "finally", "break", "continue", "pass", "nil", "null", "none", "true", "false", "in", "not",
           "and", "or", "def", "func", "function", "fn", "class"}


def substantial(text):
    """True when a line has at least two identifier-like tokens that are not a keyword: `}`, `end` and
    `if err != nil {` are lines every file has, so they never identify a place."""
    return sum(1 for t in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", text) if t.lower() not in TRIVIAL) >= 2


def repeat_of(f, entries, rev):
    """The ref of the dismissed entry this finding repeats (#210), or None. With a place: the same path, the
    stripped text of the cited line at rev hashing to the entry's, within 10 lines of the entry's line, and the
    line not trivial. Without one: the normalized title hashing to the entry's exactly. Code that changed at the
    entry's place has another hash, so a finding raised there again counts."""
    place = place_of(f["where"])
    if place is None:
        key = sha10(" ".join(words(f["title"])))
        return next((ref for e_path, e_hash, ref, *_ in entries if e_path == "-" and e_hash == key), None)
    text = cited_line(place, rev)
    if text is None or not substantial(text):
        return None
    path, digest = place[0].replace(" ", "%20"), sha10(text)
    for e_path, e_hash, ref, _, e_place, *_ in entries:
        e_line = re.search(r":(\d+)(?:-\d+)?$", e_place)
        if e_path == path and e_hash == digest and e_line and abs(place[1] - int(e_line.group(1))) <= 10:
            return ref
    return None


def small_push(g, cur):
    """('diff', []) or ('full', [paths whose behaviour changed]) for the push g..cur (#211): a diff when it is at
    most 400 changed lines in 15 files and every path is new to the branch, a test or doc path, or changed in
    whitespace only."""
    r = run(["git", "diff", "--numstat", "--no-renames", "-z", g, cur], 60)
    if r.returncode != 0:
        return "full", []
    lines, paths = 0, []
    for rec in filter(None, r.stdout.split("\0")):
        added, deleted, path = rec.split("\t", 2)
        lines += int(added) + int(deleted) if added.isdigit() and deleted.isdigit() else SMALL_LINES + 1
        paths.append(path)
    earlier = run(["git", "diff", "--name-only", "--no-renames", "-z", f"{base_sha}...{g}"], 60)
    reviewed = set(earlier.stdout.split("\0")) if earlier.returncode == 0 else set(paths)
    behaviour = [p for p in paths if p in reviewed and not TEST_PATH.search(p)
                 and run(["git", "diff", "-w", g, cur, "--", p], 60).stdout.strip()]
    return ("diff", []) if not behaviour and lines <= SMALL_LINES and len(paths) <= SMALL_FILES else ("full", behaviour)


def newest_round():
    """(j, verdict, head) of the newest earlier round with a review file, or None."""
    for j in range(k - 1, 0, -1):
        try:
            first = open(os.path.join(reviews, f"{item}-r{j}.md"), encoding="utf-8").readline()
        except OSError:
            continue
        m = re.search(r"\bround=\d+ (SAFE|NOT-SAFE)\b.*\bhead=([0-9a-f]{7,40})\b", first)
        return (j, m.group(1), m.group(2)) if m else None
    return None


def since_safe_text():
    """#211: when the newest earlier round was SAFE at a head that is an ancestor of HEAD, the push since is
    classified: a diff review, or a full one naming the files whose behaviour changed. None when the rule does not
    apply."""
    last = newest_round()
    if last is None or last[1] != "SAFE":
        return None
    r = run(["git", "rev-parse", "--verify", "--quiet", last[2] + "^{commit}"], 30)
    g, cur = (r.stdout.strip().lower() if r.returncode == 0 else ""), head()
    if not g or not cur or g == cur or run(["git", "merge-base", "--is-ancestor", g, cur], 30).returncode != 0:
        return None
    kind, files = small_push(g, cur)
    if kind == "diff":
        SCOPE["footer"] = f"scope diff from {g[:7]}"
        return (f"Round {last[0]} found this change SAFE at {g[:7]}. The review covers the push since only: "
                f"git log --oneline {g}..HEAD; their change: git diff {g}..HEAD. A merge among them brings the base's "
                f"own changes: grade only the files git diff {base_sha}...HEAD --name-only lists. A finding outside "
                "those lines is [P2] at most, marked \"(earlier code)\".")
    SCOPE["footer"] = f"scope full since {g[:7]}"
    return (f"Review the whole change. Round {last[0]} found it SAFE at {g[:7]}, and the push since "
            + (f"changes behaviour in: {', '.join(files)}." if files else "is too large for a diff review."))


def since_text():
    """{{since}}: what the previous round reviewed, from the head= of its VERDICT line. Any doubt is a whole review."""
    whole = "Review the whole change."
    if k < 2:
        return whole
    safe = since_safe_text()
    if safe:
        return safe
    try:
        first = open(os.path.join(reviews, f"{item}-r{k - 1}.md"), encoding="utf-8").readline()
    except OSError:
        return whole
    m = re.search(r"\bhead=([0-9a-f]{7,40})\b", first)
    if not m:
        return whole
    r = run(["git", "rev-parse", "--verify", "--quiet", m.group(1) + "^{commit}"], 30)
    prev = r.stdout.strip().lower() if r.returncode == 0 else ""
    cur = head()
    if not prev or not cur:
        return whole
    if prev == cur:
        return (f"Round {k - 1} reviewed this same head. Judge each of its [P0] and [P1] findings against the "
                f"disposition in its -fix.md, or the brief's newest ## Decisions records when there is no -fix.md. "
                f"A defect round {k - 1} did not raise is [P2] at most, marked \"(earlier code)\". "
                "A [P0] anywhere still blocks.")
    if run(["git", "merge-base", "--is-ancestor", prev, cur], 30).returncode != 0:
        return whole
    return (f"Round {k - 1} reviewed {prev[:7]}. The commits since: git log --oneline {prev}..HEAD; their change: "
            f"git diff {prev}..HEAD. A merge among them brings the base's own changes: grade only the files "
            f"git diff {base_sha}...HEAD --name-only lists. Check each [P0] and [P1] finding of round {k - 1}: "
            "fixed, or a disposition in its -fix.md you accept. Raise a new [P1] only in code these commits "
            "changed, or for a defect they cause elsewhere. A defect in code round "
            f"{k - 1} already reviewed and these commits did not change is [P2] at most, marked \"(earlier code)\". "
            "A [P0] anywhere still blocks.")


def prompt_text():
    template = open(os.path.join(S, "template", "gate-prompt.md"), encoding="utf-8").read()
    if k >= 2:
        last, fix = os.path.join(reviews, f"{item}-r{k - 1}.md"), os.path.join(reviews, f"{item}-r{k - 1}-fix.md")
        previous = (f"Previous round: {last}, and the dispositions of the findings that were not fixed in {fix} "
                    "when that file exists.")
        if os.path.exists(last) and not os.path.exists(fix):  # a re-scope wrote no -fix.md (#67)
            day = time.strftime("%Y-%m-%d", time.gmtime(os.path.getmtime(last)))
            previous += (f" No `-fix.md` exists for round {k - 1}. Treat the records in the brief's `## Decisions` "
                         f"dated {day} or later as the dispositions of its findings.")
    else:
        previous = "This is round 1: there is no previous review."
    evidence = (f"Evidence of the live checks: {o['evidence']}; start at its report.md. A criterion with no change "
                "in the diff behind it is judged on this evidence. Call it unproven only when the evidence does "
                "not show it." if o.get("evidence") else "No evidence folder was given.")
    try:
        pending = [l.strip() for l in open(os.path.join(gates_dir, f"{item}-screen.md"), encoding="utf-8") if l.strip()]
    except OSError:
        pending = []
    pending_text = ("Pending at the screen, verified separately with a person and never a finding here: "
                    + "; ".join(pending)) if pending else "No check is pending at the screen."
    tooling_text = ("Tooling, graded for safety only: " + ", ".join(tooling_prefixes) + ". A finding whose every site is "
                    "under these paths is [P2] at most, unless the code there opens a device (camera, microphone, "
                    "screen capture), reads or sends a secret or user data, or plays sound. A path here that the "
                    "deliverable's runtime code imports is not tooling: grade it in full."
                    if tooling_prefixes else "No path is tooling: grade every file in full.")
    values = {"item": item, "round": str(k), "base": base_sha, "brief": brief, "notes": ", ".join(notes) or "none",
              "previous": previous, "since": since_text(), "pending": pending_text, "evidence": evidence,
              "tooling": tooling_text, "dismissed": dismissed_text(DISMISSED)}
    return re.sub(r"\{\{(\w+)\}\}", lambda m: values.get(m.group(1), m.group(0)), template)


def head():
    r = run(["git", "rev-parse", "HEAD"], 30)
    return r.stdout.strip().lower() if r.returncode == 0 else ""


def head_unmoved():
    """ERROR when HEAD is not the commit the round started on."""
    after = head()
    if after != before:
        error(f"HEAD moved during the review ({before[:7]} to {after[:7] or '?'})")
    return after


def pinned_base():
    """The full sha --base names as the round starts (#113): the prompt and the review name it, so a fetch
    during the round cannot move what the round reviews."""
    r = run(["git", "rev-parse", "--verify", "--quiet", base + "^{commit}"], 30)
    sha = r.stdout.strip().lower()
    if r.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40}", sha):
        error(f"the base {base} is not a commit here")
    return sha


def changed(a, b):
    """The paths that differ between two commits, a rename counted as a delete and an add."""
    r = run(["git", "diff", "--name-only", "--no-renames", "-z", a, b], 60)
    if r.returncode != 0:
        error(f"git diff {a[:7]} {b[:7]} failed: " + (last_line(r.stderr) or f"exit {r.returncode}"))
    return {p for p in r.stdout.split("\0") if p}


def base_moved(base_commit, here):
    """The first path, in byte order, that the base changed since it and here last met and here changed too,
    or None (#113). None when the base commit is already in here's history, or the two share none."""
    if run(["git", "merge-base", "--is-ancestor", base_commit, here], 30).returncode == 0:
        return None
    met = run(["git", "merge-base", base_commit, here], 30).stdout.strip()
    if not met:
        return None
    both = sorted(changed(met, base_commit) & changed(met, here))
    return both[0] if both else None


os.makedirs(reviews, exist_ok=True)
specs = os.path.join(home, "specs", project)
os.makedirs(specs, exist_ok=True)
review_path = os.path.join(reviews, f"{item}-r{k}.md")
raw_path = os.path.join(reviews, f"{item}-r{k}.raw.md")
log_path = os.path.join(reviews, f"{item}-r{k}.log")
run_path = os.path.join(reviews, f"{item}-r{k}.run")
before = head()
if not re.fullmatch(r"[0-9a-f]{40}", before):
    error("not inside a git checkout")
base_sha = pinned_base()
moved = base_moved(base_sha, before)
if moved:  # merge the base in first, or the base's own change reads as the PR's (#113)
    error(f"base-moved {base} at {base_sha[:7]} changes {moved}, a file this branch changes: merge it in, "
          f"then run round {k}")
DISMISSED = record_dismissed()
prompt = prompt_text()
with open(os.path.join(specs, f"{item}-gate-r{k}.md"), "w", encoding="utf-8") as f:
    f.write(prompt)


def codex_cmd(m, e):
    return ["codex", "review", prompt, "--strict-config", "-c", f'model="{m}"', "-c", f'model_reasoning_effort="{e}"',
            "-c", 'sandbox_mode="read-only"', "-c", "mcp_servers={}"]


def claude_cmd(m, e, notes=()):
    """claude -p on the round's prompt; on a re-run, the prompt ends with one line per note: a denied command
    (#100) or an unreadable review (#185)."""
    asked = prompt.rstrip("\n") + "\n\n" + "\n".join(notes) + "\n" if notes else prompt
    return ["claude", "-p", asked, "--model", m, "--effort", e, "--append-system-prompt", FORMAT,
            "--add-dir", home, *([o["evidence"]] if o.get("evidence") else []),
            "--allowedTools", *read_only(*worktree_paths()),
            "--disallowedTools", "Edit", "Write", "NotebookEdit", *NO_WRITE,
            "--output-format", "json", "--strict-mcp-config", "--no-session-persistence"]


LOCK = threading.Lock()


def pump(stream, sink):
    """Copies each line as it arrives to its file and to stderr, whole lines at a time (#71)."""
    try:
        for line in iter(stream.readline, ""):
            with LOCK:
                sink.write(line)
                sink.flush()
                sys.stderr.write(line)
                sys.stderr.flush()
    except (OSError, ValueError):
        pass  # the file closed under a pipe that a grandchild still held open


def attempt(cmd, label, agent, model_):
    """One review run, stdout to the raw file and stderr to the log, both streamed to stderr:
    (rc, stdout, this run's stderr). rc is 127 when the program is missing, 124 past
    CODEX_GATE_TIMEOUT, negative when a signal ended it."""
    ROUND["attempt"] = ROUND.get("attempt", 0) + 1
    start = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    header = f"--- {label} {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n"
    with open(raw_path, "w", encoding="utf-8") as so, open(log_path, "a", encoding="utf-8") as se:
        se.write(header)
        se.flush()
        sys.stderr.write(header)
        sys.stderr.flush()
        try:
            proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    text=True, encoding="utf-8", errors="replace", bufsize=1,
                                    start_new_session=True)
        except FileNotFoundError:
            se.write(f"{cmd[0]} not found on PATH\n")
            proc = None
        if proc is None:
            rc = 127
        else:
            CHILD["proc"] = proc
            write_run(proc.pid, agent, model_)
            pumps = [threading.Thread(target=pump, args=(proc.stdout, so), daemon=True),
                     threading.Thread(target=pump, args=(proc.stderr, se), daemon=True)]
            for t in pumps:
                t.start()
            try:
                rc = proc.wait(timeout=LIMIT)
            except subprocess.TimeoutExpired:
                stop_child(proc)
                rc = 124
            for t in pumps:
                t.join(10)
            CHILD.clear()
    with open(log_path, encoding="utf-8", errors="replace") as f:
        f.seek(start)
        tail = "\n".join(f.read().splitlines()[1:])  # this run's stderr, without the script's own header line
    return rc, open(raw_path, encoding="utf-8", errors="replace").read(), tail


def keep_output(text):
    """Appends a run's stdout to the round's log under "--- stdout", before the round runs the agent again (#100)."""
    with open(log_path, "a", encoding="utf-8") as f:
        f.write("--- stdout\n" + text + ("" if not text or text.endswith("\n") else "\n"))


def refusal(text):
    """The first line, when it reports a failure although the run exited 0 ("error…", "API Error…", "⚠")."""
    first = next((l.strip() for l in text.splitlines() if l.strip()), "")
    return first if first.lower().startswith(("error", "api error")) or first.startswith("⚠") else ""


def claude_review(rc, text, tail):
    """(review, None, []) when claude -p reviewed, else (None, why, denied) (#64). claude -p exits 0 and
    answers in prose when a tool is denied, so the JSON result decides: an error, a denial or output that
    is not JSON is a fallback that did not review, whatever the prose says. denied names what each
    permission denial asked for, one line each, when a denial is the run's only failure (#100)."""
    try:
        d = json.loads(text)
    except ValueError:
        d = None
    if not isinstance(d, dict):
        first = next((l.strip() for l in text.splitlines() if l.strip()), "")
        return None, ("unreadable output: " + first[:120] if first and rc == 0
                      else last_line(tail) or ("empty review" if rc == 0 else f"exit {rc}")), []
    result = d.get("result") if isinstance(d.get("result"), str) else ""
    denied = d.get("permission_denials")
    if rc != 0 or d.get("is_error") or d.get("subtype") != "success":
        return None, last_line(result) or last_line(tail) or str(d.get("subtype") or f"exit {rc}"), []
    if not isinstance(denied, list):
        return None, "unreadable output: no permission_denials", []
    if denied:
        named = []
        for entry in denied:
            entry = entry if isinstance(entry, dict) else {}
            asked_for = entry.get("tool_input") if isinstance(entry.get("tool_input"), dict) else {}
            what = " ".join(str(asked_for.get("command") or asked_for.get("file_path") or asked_for.get("pattern")
                                or "").split())
            named.append((entry.get("tool_name") or "a tool", what))
        tool, what = named[0]
        why = f"{tool} was denied" + (f": {what}" if what else "")
        return None, why, list(dict.fromkeys(w or t for t, w in named))
    if not result.strip():
        return None, "empty review", []
    return result, None, []


def write_run(pid, agent, model_):
    """<item>-r<k>.run says which process reviews this round, for worker-probe.sh (#70)."""
    tmp = f"{run_path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"pid": pid, "gate": os.getpid(), "agent": agent, "model": model_, "attempt": ROUND["attempt"],
                   "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "log": log_path}, f)
        f.write("\n")
    os.replace(tmp, run_path)


def stop_child(proc):
    """TERM to the agent's whole process group, then KILL if it is still there after 5 seconds."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(proc.pid, sig)
        except OSError:
            return
        try:
            proc.wait(timeout=5)
            return
        except subprocess.TimeoutExpired:
            pass


def stopped(signum, _frame):
    proc = CHILD.get("proc")
    if proc is not None and proc.poll() is None:
        stop_child(proc)
    error(f"stopped by {signal.Signals(signum).name}")
# the line a fallback run's prompt gets when its previous review wrote a tag outside a finding bullet (#185)
RETAG = ("Your previous review wrote a grade tag outside a finding bullet: \"{}\". Write a [P0] to [P3] tag only at "
         "the start of a finding bullet.")
UNTAGGED = ("Your previous review had a finding bullet without a [P0] to [P3] tag: \"{}\". Start every finding bullet "
            "with its tag.")
VERDICT_RULE = ("End the review with exactly one last line, VERDICT: SAFE or VERDICT: NOT-SAFE "
                "(NOT-SAFE when you found any P0 or P1).")
NO_VERDICT, TWO_VERDICTS = "no VERDICT line", "more than one VERDICT line"
NOT_SAFE_BARE = "VERDICT NOT-SAFE without a P0 or P1 finding"
# the correction line for each reason a fallback review is unreadable (#185); {} is the offending line when there is one
CORRECTIONS = {
    "a finding in a shape the gate cannot read": RETAG,
    "findings without [P0]-[P3] tags": UNTAGGED,
    NO_VERDICT: "Your previous review had no VERDICT line. " + VERDICT_RULE,
    TWO_VERDICTS: "Your previous review had more than one VERDICT line. " + VERDICT_RULE,
    NOT_SAFE_BARE: ("Your previous review ended VERDICT: NOT-SAFE but had no P0 or P1 finding bullet. State every P0 or "
                    "P1 problem as a finding bullet that starts with its [P0] or [P1] tag, or end with VERDICT: SAFE. "
                    + VERDICT_RULE),
}
VERDICT_LINE = re.compile(r"^\s*VERDICT:\s*(SAFE|NOT-SAFE)\s*$")


def parse_review(text, fallback=False):
    """(findings, overall, why, offending): why is None when the review is readable, else the reason it is not;
    offending is the first line that made it unreadable. Strict on purpose: a tag outside a finding bullet is
    never read as prose, since a real P1 written that way must not pass as SAFE. A fallback review (#185) must
    also end with one VERDICT: SAFE or VERDICT: NOT-SAFE line: it is neither a note nor a finding, a missing or
    doubled one is unreadable, NOT-SAFE needs a P0 or P1 bullet behind it, and SAFE never outweighs one."""
    findings, overall, current, listing, verdicts = [], [], None, False, []
    odd_tag = untagged = header = None
    for line in text.splitlines():
        tag = TAG.match(line)
        said = VERDICT_LINE.match(line) if fallback else None
        if said:
            verdicts.append(said.group(1))
        elif tag:
            title, _, where = tag.group(2).rpartition(" — ")
            current = {"p": int(tag.group(1)), "title": (title or tag.group(2)).strip(),
                       "where": where.strip() if title else "", "body": []}
            findings.append(current)
            listing = True
        elif ANY_TAG.search(line):
            odd_tag = odd_tag or line
        elif PLACED.match(line):
            untagged = untagged or line
        elif current is not None and line[:1].isspace() and line.strip():
            current["body"].append(line.strip())
        elif FINDINGS_HEADER.match(line):
            header = header or line
            listing = True
        elif not listing and line.strip():
            overall.append(line.strip())
    if odd_tag:
        return findings, overall, "a finding in a shape the gate cannot read", odd_tag
    if untagged or (listing and not findings):
        return findings, overall, "findings without [P0]-[P3] tags", untagged or header or ""
    if fallback and len(verdicts) != 1:
        return findings, overall, TWO_VERDICTS if verdicts else NO_VERDICT, ""
    if fallback and verdicts == ["NOT-SAFE"] and not any(f["p"] <= 1 for f in findings):
        return findings, overall, NOT_SAFE_BARE, ""
    return findings, overall, None, ""


ROUND.update(reviews=reviews, item=item, k=k, raw=raw_path, log=log_path, run=run_path)
for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(sig, stopped)
used, text, tail = None, "", ""
short, why = f"cannot resolve {asked}", resolved
if model is not None:
    for wait in (0, 60, 180):
        if wait:
            time.sleep(wait * PAUSE)
        rc, text, tail = attempt(codex_cmd(model, effort), f"codex review {model} {effort}", "codex", model)
        if rc < 0:
            error(f"codex review stopped by signal {-rc}")
        if rc == 0 and text.strip():
            if refusal(text):
                error("codex review failed: " + refusal(text)[:160])
            used = (model, effort, "")
            break
        if rc == 0:
            error("empty review")
        if rc == 127:
            error("codex not found on PATH")
        if USAGE.search(last_lines(tail, 20)) or USAGE.search(last_lines(text, 20)):
            short, why = "sol usage limit", last_line(tail or text)
            break
        if not CAPACITY.search(tail):
            error("codex review failed: " + (last_line(tail) or f"exit {rc}"))
        short, why = "sol at capacity", last_line(tail)
if used is None:
    if fb is None:
        error(f"gate-down {short}: {why}; no fallback is set")
    label = f"claude {fb['model']} {fb['effort']}"
    rc, output, tail = attempt(claude_cmd(fb["model"], fb["effort"]), label, "claude", fb["model"])
    if rc < 0:
        error(f"claude review stopped by signal {-rc}")
    text, failed, denied = claude_review(rc, output, tail)
    runs = 1  # a round runs the fallback at most twice, counting the re-run after a denial (#100) and after an unreadable review (#185)
    if denied:  # once more in the same round, told what was denied; a second denial is gate-down (#100)
        keep_output(output)
        rc, output, tail = attempt(claude_cmd(fb["model"], fb["effort"], [DENIED.format(d) for d in denied]),
                                   label + " (again, after a denial)", "claude", fb["model"])
        if rc < 0:
            error(f"claude review stopped by signal {-rc}")
        text, failed, _ = claude_review(rc, output, tail)
        runs = 2
    if failed:
        error(f"gate-down {short}: {why}; claude: {failed[:160]}")
    with open(raw_path, "w", encoding="utf-8") as f:  # the raw file holds the review, not the JSON around it
        f.write(text)
    _, _, bad, line = parse_review(text, fallback=True)
    if bad:
        head_unmoved()  # a moved HEAD is ERROR HEAD moved, never a free retry (#185)
    if bad and runs < 2:  # once more in the same round, told what was wrong (#185)
        keep_output(text)
        fix = CORRECTIONS[bad].format(" ".join(line.split())[:160])
        rc, output, tail = attempt(claude_cmd(fb["model"], fb["effort"], [fix]),
                                   label + " (again, after an unreadable review)", "claude", fb["model"])
        if rc < 0:
            error(f"claude review stopped by signal {-rc}")
        text, failed, _ = claude_review(rc, output, tail)
        if failed:
            error(f"gate-down {short}: {why}; claude: {failed[:160]}")
        with open(raw_path, "w", encoding="utf-8") as f:
            f.write(text)
        _, _, bad, line = parse_review(text, fallback=True)
    if bad:
        head_unmoved()
        error(f"fallback-unreadable {bad}")
    used = (f"claude:{fb['model']}", fb["effort"], short)
after = head_unmoved()

findings, overall, bad, _ = parse_review(text, fallback=used[0].startswith("claude:"))
if bad:
    error("unreadable review: " + bad)
for f in findings:  # a repeat of a dismissed finding (#210) and a P0 or P1 with no evidence line (#209) never block
    f["mark"] = ""
    ref = repeat_of(f, DISMISSED, after) if DISMISSED else None
    if ref:
        f["mark"] = f" (repeat of {ref}, dismissed)"
    elif f["p"] <= 1 and not has_evidence(f):
        f["mark"] = " (unproven: no evidence, does not block)"
        f["unproven"] = True
blocking = [f for f in findings if f["p"] <= 1 and not f["mark"]]
unproven = sum(1 for f in findings if f.get("unproven"))
p0 = sum(1 for f in blocking if f["p"] == 0)
p1 = sum(1 for f in blocking if f["p"] == 1)
verdict = "NOT-SAFE" if p0 + p1 else "SAFE"
lines = [f"VERDICT item={item} round={k} {verdict} findings={len(findings)} head={after}", "", "## Findings"]
for i, f in enumerate(findings, 1):
    lines.append(f"{i}. [P{f['p']}] {f['title']}{f['mark']}" + (f" — {f['where']}" if f["where"] else ""))
    lines += ["   " + b for b in f["body"]]
if not findings:
    lines.append("none")
lines += ["", "## Notes", " ".join(overall) or "-", "",
          f"Gate: {used[0]} {used[1]}" + (f" (fallback: {used[2]})" if used[2] else "")
          + f" · base {base} {base_sha} · raw {raw_path} · log {log_path}"
          + (f" · {SCOPE['footer']}" if SCOPE.get("footer") else "")]
tmp = f"{review_path}.tmp.{os.getpid()}"
with open(tmp, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
os.replace(tmp, review_path)
if verdict == "SAFE":
    out(f"SAFE round={k} findings={len(findings)} unproven={unproven} head={after} review={review_path}")
tooling_mark = f" tooling={tooling_count(blocking, tooling_prefixes)}" if tooling_prefixes else ""
out(f"NOT-SAFE round={k} findings={len(findings)} p0={p0} p1={p1}{tooling_mark} unproven={unproven} head={after} review={review_path}")
PY
