---
name: cmux-review-pr
description: Use to review a GitHub PR (or arbitrary branch) inside an isolated CMUX workspace. Creates a git worktree for the PR branch, spawns a CMUX workspace, auto-launches `claude` with a deterministic session id derived from the PR id, fetches the linked work item so the review is graded against its requirements, runs `/pr-review-toolkit:review-pr`, then validates the findings with codex. Triggers "review pr", "/juel:cmux-review-pr".
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: phase 3 grades the review against the linked work item's requirements
        check: none
        fallback: review proceeds ungraded; the alignment section is omitted
    cli:
      - id: cmux
        hard: true
        why: phase 6 creates the review workspace
        check: "resolve_bin cmux against PATH, then GUI/Homebrew candidates"
      - id: claude
        hard: true
        why: phase 6 launches claude inside the review workspace
        check: "resolve_bin claude against PATH, then GUI/Homebrew candidates"
      - id: gh
        hard: true
        why: phase 2 resolves the PR argument to a branch and label
        check: "gh auth status"
      - id: codex
        hard: false
        why: the inner session dispatches codex to second-opinion the review findings
        check: "command -v codex"
        fallback: the inner session validates findings itself
      - id: coreutils
        hard: true
        why: sleep/grep/head are resolved once per session via resolve_bin and sourced from BINS every call, since each Bash call is an independent non-login shell
        check: "resolve_bin per binary against PATH, then /usr/bin,/bin candidates"
      - id: resolved-install-command
        hard: false
        why: end of Step 4 warms deps in a second tab while the inner review runs in the first
        check: "see resolution layer"
        fallback: skip the second surface; install deps yourself
    context:
      - id: git-repo
        hard: true
        why: phase 4 creates the review worktree under the repo matching the PR remote
        check: "git remote get-url <remote>"
      - id: open-pr
        hard: true
        why: phase 2 resolves the PR argument to a branch
        check: "gh pr view <N> --json number"
    skills:
      - id: pr-review-toolkit
        hard: false
        why: the inner session runs pr-review-toolkit:review-pr
        fallback: inner session falls back to /review
---

# Juel CMUX Review PR

Sister skill of `juel:cmux-ship-tickets`. Same plumbing (worktree + CMUX workspace + deterministic claude session) but the payload is a code review followed by an independent codex validation pass.

**Two reviewers, one report — graded against the work item.** Before reviewing, the inner claude fetches the linked work item (ref extracted from the branch/PR title via the same `detect_ref` helper `juel:start` inlines — a different source than `juel:start`, which reads the worktree dirname instead, but the same spirit: resolve a ref before doing anything else) so the diff is judged against the work item's requirements and acceptance criteria, not just generic code quality. It then runs `/pr-review-toolkit:review-pr`, hands every finding to codex for a second opinion. Do NOT pin a codex model or reasoning effort — let codex use its own defaults. Final consolidated report lives at `${docsRoot}/findings/findings-review.md` with four buckets: Requirement-alignment, Confirmed, Disputed, Codex-only.

> **Codex invocation (important).** Use `codex exec --sandbox read-only "<prompt>"`, NOT `codex exec review --base <base> "<prompt>"`. Codex (>=0.140) rejects combining `--base` with a positional prompt (`error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'`). Since validation needs both a custom prompt and the base diff, instruct codex to run the diff itself inside the prompt: start the prompt with "First run: git diff <base>...HEAD to see the real changes, then validate...".

**Announce:** "Using juel:cmux-review-pr to set up a CMUX workspace for review."

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v1 -->

**1. Preflight, then checklist, before anything else.** Before any other output and before any tool call, emit the Preflight block (below), then this skill's `## Phases` checklist rendered as:

```
<skill-name> — N phases
[ ] 1. <phase name>
[ ] 2. <phase name>
```

If the preflight verdict is STOP, print the preflight block and **stop** — do not print the checklist and do not begin work. Otherwise no work begins until the checklist is on screen. This is not optional on re-invocation, on resume, or when the user says "just do it".

**2. Phases run in order.** No skipping, reordering, or merging. A phase that does not apply is still announced: mark it `[-] N. <name> — SKIPPED: <one-line reason>` and continue at N+1. Never drop a phase silently. Never begin phase N+1 before phase N is marked done or skipped.

**3. Report after every phase.** Re-emit the checklist (`[x]` done, `[-]` skipped, `[ ]` pending) plus one line of evidence for the phase just finished — path written, command run, count found. Never claim progress in prose alone.

**4. Everything runs in the FOREGROUND.** This overrides every other instruction in this file and in any skill invoked from it.
- `pr-review-toolkit:review-pr`, `simplify`, and `codex exec` are all foreground-only. Invoke subagents with `run_in_background: false` **explicitly** — the harness backgrounds subagents by default, so omitting the flag is a violation, not a neutral choice.
- Never `&`. Never `run_in_background: true`. Never "dispatch and continue".
- **Never redirect a command's output to a log file.** No `> out.log`, no `| tee`, no writing output somewhere to read back later. The user must be able to watch the run as it happens.
- Do not request `review-pr`'s parallel / `all parallel` mode.
- Read the complete output and state the outcome — finding count, exit status, files changed — before marking the phase done. A summary may follow the raw output; it may never replace it.
- Passing any of this into another session (a CMUX prompt, a nested `claude`) carries these rules with it — say so explicitly in that prompt string.

**5. Confirmation gates stack; they do not replace this.** Where this skill pauses between phases, the checklist report comes first, then the "Proceed to phase N+1?" question. A user's "yes" advances exactly one phase — it never authorizes skipping ahead or batching the remainder.

## Preflight

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| cmux | cli | HARD | `resolve_bin cmux` against PATH, then GUI/Homebrew candidates | STOP → https://github.com/manaflow-ai/cmux |
| claude | cli | HARD | `resolve_bin claude` against PATH, then GUI/Homebrew candidates | STOP |
| gh (authenticated) | cli | HARD | `gh auth status` | STOP → `gh auth login` |
| codex | cli | SOFT | `command -v codex` | the inner session validates findings itself |
| coreutils | cli | HARD | `resolve_bin` per binary (sleep/grep/head) against PATH, then `/usr/bin`,`/bin` candidates | STOP |
| git repo matching the PR remote | context | HARD | `git remote get-url <remote>` | STOP |
| resolvable PR or branch | context | HARD | `gh pr view <N> --json number` | STOP |
| pr-review-toolkit | skill | SOFT | ships as a plugin dependency | inner session falls back to `/review` |
| Linear MCP | mcp | SOFT | **none — render as `?`** | review proceeds ungraded; the alignment section is omitted |
| resolved install command | cli | SOFT | see resolution layer | skip the second surface; install deps yourself |

## Phases

[ ] 1. Preflight — resolve binaries via resolve_bin, persist to BINS, set CMUX_QUIET
[ ] 2. Resolve the PR to a branch and label
[ ] 3. Extract the work-item ref from the branch, falling back to the PR title
[ ] 4. Create the worktree and copy untracked env files
[ ] 5. Compute the deterministic session id
[ ] 6. Spawn the workspace, rename it, poll for the prompt, send the review prompt + Enter
[ ] 7. Open the second surface and start the resolved install command
[ ] 8. Report PR, work item, worktree, session, workspace, surface
[ ] 9. Verify the QA checklist

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<pr-or-branch>` | yes | Either `#1234`, `1234`, a GitHub PR URL, or a branch name |
| `[base-branch]` | no | Branch to diff against for codex validation. Auto-detected if omitted — see "Resolve the base branch" in Step 4. |

Usage: `/juel:cmux-review-pr 1234` or `/juel:cmux-review-pr feat/savi-1162-foo` or `/juel:cmux-review-pr 1234 main`.

## Prerequisites

- `cmux` CLI installed — resolved via `resolve_bin` (PATH first, then the GUI install at `/Applications/cmux.app/Contents/Resources/bin/cmux` and Homebrew paths as candidates, not the sole fallback).
- `claude` CLI installed (same `resolve_bin` rule; GUI path and Homebrew paths are candidates).
- `gh` CLI on PATH and authenticated. `gh` embeds its own `jq` — a standalone `jq` binary is never required, see "Resolve the PR" below.
- Inside a git repo whose remote matches the PR.
- `pr-review-toolkit` plugin/skill installed (provides `/pr-review-toolkit:review-pr`).

### Resolve binaries once, persist, then source every call

Each Bash tool call is an **independent non-login shell** — the real reason a binary resolved in call N is unavailable in call N+1 is not "PATH drops"; it's that shell variables and function definitions from call N simply do not exist in call N+1. Resolve every binary once via `resolve_bin` (PATH first, then labelled candidates — never a hardcoded absolute path as the sole source), persist the resolved paths to `$GIT_COMMON/claude/bins.env`, and source that file at the top of every later call instead of re-resolving or assuming the previous call's variables survived. `python3` and `jq` are **not resolved at all** — both dependencies are removed outright, see "Resolve the PR" and "Compute session id" below.

```bash
resolve_bin() {
  n=$1; shift
  p=$(command -v "$n" 2>/dev/null) && { printf '%s' "$p"; return 0; }
  for c in "$@"; do [ -x "$c" ] && { printf '%s' "$c"; return 0; }; done
  return 1
}

CMUX=$(resolve_bin cmux /Applications/cmux.app/Contents/Resources/bin/cmux \
        "$HOME/.local/bin/cmux" /opt/homebrew/bin/cmux /usr/local/bin/cmux) || CMUX=
CLAUDE_BIN=$(resolve_bin claude "$HOME/.claude/local/claude" "$HOME/.local/bin/claude" \
        /Applications/cmux.app/Contents/Resources/bin/claude \
        /opt/homebrew/bin/claude /usr/local/bin/claude) || CLAUDE_BIN=
GH=$(resolve_bin gh /opt/homebrew/bin/gh /usr/local/bin/gh /usr/bin/gh) || GH=
SLEEP=$(resolve_bin sleep /usr/bin/sleep /bin/sleep) || SLEEP=
GREP=$(resolve_bin grep /usr/bin/grep /bin/grep) || GREP=
HEAD=$(resolve_bin head /usr/bin/head /bin/head) || HEAD=

[ -n "$CMUX" ] || { echo "cmux not found on PATH or any candidate location"; exit 1; }
[ -n "$CLAUDE_BIN" ] || { echo "claude not found on PATH or any candidate location"; exit 1; }
[ -n "$GH" ] || { echo "gh not found on PATH or any candidate location"; exit 1; }
[ -n "$SLEEP" ] && [ -n "$GREP" ] && [ -n "$HEAD" ] || { echo "missing coreutils"; exit 1; }

GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)   # normalized — --git-common-dir
                                                                   # can print a RELATIVE ".git"
BINS="$GIT_COMMON/claude/bins.env"
mkdir -p "$(dirname "$BINS")"
{
  echo "CMUX=$CMUX"; echo "CLAUDE_BIN=$CLAUDE_BIN"; echo "GH=$GH"
  echo "SLEEP=$SLEEP"; echo "GREP=$GREP"; echo "HEAD=$HEAD"
  echo "export CMUX_QUIET=1"   # silence cmux's "X is now an alias for Y" deprecation notices —
                                # exported here too since env vars don't survive across calls either
} > "$BINS"
. "$BINS"
```

**Every subsequent Bash call in this skill starts with:**

```sh
BINS="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/claude/bins.env"
. "$BINS"
```

(`BINS` itself is a shell variable and does not survive either — recompute the path fresh, then source. Recomputing the path is cheap; re-running the `resolve_bin` candidate search every call is what this pattern avoids.) Use `"$CMUX"`, `"$CLAUDE_BIN"`, `"$GH"`, `"$SLEEP"`, `"$GREP"`, `"$HEAD"` (never bare names) in every command.

### Long snippets run as a temp file under `bash`

Any snippet longer than ~5 lines is written to a temp file and run as `bash "$f"`, which normalizes semantics regardless of the user's login shell (this machine's is zsh, but the pattern must not assume that). Inline one-liners stay POSIX `sh` and need no such wrapping.

### CWD persistence — never `cd` in this skill

The Bash tool's working directory persists across calls. A `cd .worktrees/review-XXXX` in one call leaks into the next and any relative path then resolves to a nested location. **Never `cd` in this skill.** Always use absolute paths. To run something inside the worktree, use `git -C "$abs_worktree" ...` or `( cd "$abs_worktree" && ... )` in a subshell so it does not leak.

## CMUX CLI cheat sheet (verified against cmux 0.62.x)

| Need | Command |
|---|---|
| Create workspace + run startup command (Enter pressed automatically) | `cmux new-workspace --cwd "$path" --command "<cmd>"` |
| Output format | Single line on stdout: `OK workspace:<N>` |
| Send literal text (no Enter) to specific surface/tab | `cmux send --workspace workspace:<N> --surface surface:<M> "<text>"` |
| Send literal text (no Enter) | `cmux send --workspace workspace:<N> "<text>"` |
| Press Enter (or other keys) | `cmux send-key --workspace workspace:<N> Enter` |
| Read the live terminal screen (for readiness polling) | `cmux read-screen --workspace workspace:<N> --lines <n>` |
| Open a new tab (surface) in a workspace | `cmux new-surface --type terminal --workspace workspace:<N>` |
| Rename workspace | `cmux rename-workspace --workspace workspace:<N> "<label>"` (title is POSITIONAL — no `--name` flag) |
| List all workspaces | `cmux list-workspaces` |

Anti-patterns confirmed broken:
- ❌ `cmux new-workspace --json` (flag does not exist)
- ❌ `cmux send-surface ...` (subcommand does not exist)
- ❌ Embedding `\n` in `cmux send` text to press Enter (sends literal backslash-n). Also: real newlines in a multi-line `cmux send` payload submit prematurely line-by-line. Send the prompt as a SINGLE LINE, then one `send-key Enter`.
- ❌ `cmux rename-workspace --workspace "" ...` — silently targets the currently-selected workspace (renames the orchestrator's own session)
- ❌ `cmux rename-workspace --workspace ws --name "<label>"` — there is NO `--name` flag; it renames the workspace to the literal string `--name <label>`. The title is a POSITIONAL arg: `cmux rename-workspace --workspace ws "<label>"`.

## Workflow

### Step 1: Resolve PR → branch + label

If the argument looks numeric or like a URL, treat it as a PR. `gh` embeds its own `jq` —
`--jq='<expr>'` filters the `--json` output directly, so no standalone `jq` binary is ever needed:

```bash
pr_number=<parsed>
branch=$("$GH" pr view "$pr_number" --json headRefName --jq='.headRefName')
title=$("$GH" pr view "$pr_number" --json title --jq='.title')
cross=$("$GH" pr view "$pr_number" --json isCrossRepository --jq='.isCrossRepository')
label="PR-$pr_number"
```

If cross-repo (`isCrossRepository == true`), use `gh pr checkout $pr_number` later instead of plain `git fetch`.

If the argument is a branch name, set `branch=<arg>`, `label=$(echo "$branch" | tr '/' '-' | tr '[:upper:]' '[:lower:]')`, and skip `gh`.

### Step 1b: Extract the work-item ref

The review is graded against the work item, so resolve its ref via `detect_ref` — anchored to
whole `/`-delimited segments with a denylist of generic branch-type words (never a loose substring
match), the same shared helper `juel:start` inlines. Try the branch name first, then the PR title:

```bash
DENY='^(feat|fix|chore|refactor|docs|test|hotfix|release|wip|perf|build|ci|style|v|part|step|pr|review|backup|bugfix|day|demo|draft|new|old|phase|poc|revert|spike|sprint|sync|task|temp|tmp|update|week)$'

_ref_from_segment() {
  seg=$1
  case "$seg" in
    *-*) : ;;
    *) return 1 ;;
  esac
  prefix=${seg%%-*}
  rest=${seg#*-}
  case "$rest" in
    *-*) num=${rest%%-*} ;;
    *)   num=$rest ;;
  esac
  lc_prefix=$(printf '%s' "$prefix" | tr 'A-Z' 'a-z')
  case "$lc_prefix" in
    issue|issues)
      case "$num" in
        ''|*[!0-9]*) return 1 ;;
      esac
      printf '#%s\n' "$num"
      return 0
      ;;
  esac
  case "$prefix" in
    *[!A-Za-z]*) return 1 ;;
  esac
  [ "${#prefix}" -ge 2 ] || return 1
  case "$num" in
    ''|*[!0-9]*) return 1 ;;
  esac
  if printf '%s\n' "$lc_prefix" | grep -Eq "$DENY"; then
    return 1
  fi
  uc_prefix=$(printf '%s' "$prefix" | tr 'a-z' 'A-Z')
  printf '%s-%s\n' "$uc_prefix" "$num"
  return 0
}

detect_ref() {
  str=$1; pat=${2:-}
  result=$(printf '%s\n' "$str" | tr '/' '\n' | while IFS= read -r seg; do
    if ref=$(_ref_from_segment "$seg") && [ -n "$ref" ]; then
      if [ -n "$pat" ]; then
        printf '%s\n' "$ref" | grep -Eq "$pat" || continue
      fi
      printf '%s\n' "$ref"
      break
    fi
  done)
  [ -n "$result" ] && { printf '%s\n' "$result"; return 0; }
  return 1
}

REF=$(detect_ref "$branch") || {
  # PR titles aren't pre-segmented by '/' the way branch names are, and free-form prose must
  # NEVER be fed to detect_ref's segment matcher wholesale: DENY enumerates branch-type words
  # (feat, chore, release, ...), not general technical vocabulary, so converting every space to
  # a '/' delimiter would let ordinary titles leak phantom refs — "Fix UTF-8 handling" -> UTF-8,
  # "Upgrade to Node-18" -> NODE-18, "Add OAuth-2 support" -> OAUTH-2. Instead, extract ONLY the
  # tag span from a leading "[...]" or "type(...)" conventional-commit scope (e.g.
  # "[SAVI-1343] Fix login redirect bug" -> "SAVI-1343"; "feat(SAVI-1343): fix login" ->
  # "SAVI-1343") and run detect_ref on that span alone — text outside the tag is never
  # segmented at all. detect_ref's own algorithm and DENY list (above) are untouched by this
  # narrowing; the normalization lives entirely outside the shared function.
  tag=$(printf '%s' "$title" | sed -n 's/^\[\([^]]*\)\].*/\1/p')
  [ -n "$tag" ] || tag=$(printf '%s' "$title" | sed -n 's/^[A-Za-z]*(\([^)]*\)).*/\1/p')
  if [ -n "$tag" ]; then
    title_norm=$(printf '%s' "$tag" | tr ':' '/')
    REF=$(detect_ref "$title_norm") || REF=""
  else
    REF=""
  fi
}
```

If `REF` is empty, the review proceeds without grading — note "no ref" in the report. Do NOT block
the review on a missing ref. The inner claude fetches the work item itself via the Linear MCP
`get_issue` inside the workspace (keeps large multi-line descriptions out of the single-line CMUX
prompt); the orchestrator only passes the ref.

### Step 2: Create the worktree

Worktree dir mirrors the ship-tickets convention so both skills coexist. **Never derive it from
`--show-toplevel` alone** — invoked from inside a worktree, that returns the *worktree's* root, so
the review worktree would be created nested inside another worktree. Use the three-root discipline
instead:

```bash
CWD_ROOT=$(git rev-parse --show-toplevel)                        # current checkout — for reading project files
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)   # main repo's .git, normalized —
                                                                   # --git-common-dir can print a
                                                                   # RELATIVE path (e.g. bare ".git"
                                                                   # from the main repo's own root),
                                                                   # so never use its raw output
MAIN_ROOT=$(dirname "$GIT_COMMON")                                # main checkout — worktrees always go here
slug=$(echo "$label" | tr '[:upper:]' '[:lower:]')
abs_worktree="$MAIN_ROOT/.worktrees/review-$slug"
```

Worktrees are created under `$MAIN_ROOT/.worktrees`, **never** `$CWD_ROOT` — otherwise a review
launched from inside item A's worktree nests item B's review worktree inside item A's.

If the worktree already exists, reuse it (skip the create). Otherwise:

```bash
# Non-cross-repo PR or plain branch:
git -C "$MAIN_ROOT" fetch origin "$branch"
git -C "$MAIN_ROOT" worktree add "$abs_worktree" "origin/$branch"

# Cross-repo PR:
git -C "$MAIN_ROOT" worktree add --detach "$abs_worktree"
( cd "$abs_worktree" && "$GH" pr checkout "$pr_number" )
```

**Copy untracked project files only** — same `copy_untracked` semantics `juel:daily-worktrees` uses
(`references/resolution.md` §4.2): untracked-only (`git ls-files --error-unmatch` skips anything
tracked, so a tracked `CLAUDE.md`/config file is never clobbered), `find`-based so a no-match never
aborts the script (no `NULL_GLOB` / `nullglob` needed — that glob-based approach is exactly what
`daily-worktrees` moved away from), and secrets (`*.pem` and anything else wider than the
`.env`-family default) are opt-in only via `config.worktreeCopy`, never copied by default:

```bash
# Guard REQUIRED under zsh: without it, an unquoted $EXTRA_PATTERNS is passed to `find` as ONE
# literal argument instead of being word-split, `find` fails outright, and the ENTIRE copy
# silently produces ZERO files, including the always-on .env/.npmrc defaults.
[ -n "$ZSH_VERSION" ] && setopt SH_WORD_SPLIT

EXTRA_PATTERNS=""   # built from config.worktreeCopy, e.g. -o -name *.pem — opt-in only.
                     # No embedded quotes: this value is only ever word-split by
                     # SH_WORD_SPLIT/bash, never re-parsed by a shell, so a literal
                     # quote character would pass straight through to `find` as text.

# copy_untracked SRC DST — portable, untracked-only, no glob-abort.
copy_untracked() {
  find "$1" -maxdepth 1 \( \
        -name '.env' -o -name '.env.*' -o -name '*.local' \
     -o -name '.envrc' -o -name '.npmrc' -o -name '.tool-versions' \
     $EXTRA_PATTERNS \) -type f -print | while IFS= read -r f; do
    git -C "$1" ls-files --error-unmatch "${f#"$1"/}" >/dev/null 2>&1 && continue
    cp -p "$f" "$2/"
  done
}

copy_untracked "$MAIN_ROOT" "$abs_worktree"
```

**Do NOT copy or symlink `venv/` into the worktree.** If the resolved install command builds a Python venv (e.g. `python3 -m venv venv`, common behind a `make install` target), it refuses to create over an existing file or symlink (`Error: Unable to create directory .../venv`). Leave `venv/` absent so the tab-2 install command builds a fresh one.

### Step 3: Compute session id

Deterministic, uuid-shaped id from the label so `claude --resume` is repeatable — no `python3`
dependency. `shasum` (a Perl wrapper around `Digest::SHA`, widely available on macOS and Linux)
gives the SHA-1 hex digest of the label directly; the first 32 hex chars are reformatted `8-4-4-4-12` with
the version nibble forced to `5` and the variant nibble forced into the RFC4122 range (`8`/`9`/`a`/`b`)
so the result is always a well-formed UUID string, not just a UUID-shaped one:

```bash
hex=$(printf '%s' "${label}" | tr '[:lower:]' '[:upper:]' | shasum -a 1 | cut -c1-32)
p1=$(printf '%s' "$hex" | cut -c1-8)
p2=$(printf '%s' "$hex" | cut -c9-12)
p3=$(printf '%s' "$hex" | cut -c13-16)
p4=$(printf '%s' "$hex" | cut -c17-20)
p5=$(printf '%s' "$hex" | cut -c21-32)
p3="5$(printf '%s' "$p3" | cut -c2-4)"            # force version nibble -> 5
variant=$(printf '%s' "$p4" | cut -c1)
case "$variant" in
  [89abAB]) : ;;                                   # already RFC4122-valid
  *) variant=8 ;;                                   # force into range
esac
p4="${variant}$(printf '%s' "$p4" | cut -c2-4)"
session_id=$(printf '%s-%s-%s-%s-%s\n' "$p1" "$p2" "$p3" "$p4" "$p5" | tr '[:upper:]' '[:lower:]')
```

This is not a byte-for-byte RFC4122 uuid5 (that hashes namespace-UUID bytes + name; this hashes the
label alone), but it is **stable per label** — the same `$label` always produces the same
`$session_id`, in `sh`, `bash` and `zsh` alike, which is the only property `claude --resume`
actually needs.

### Step 4: Spawn CMUX workspace and queue the review

```bash
# 1. Create workspace; --command launches claude with Enter pressed automatically.
#    Pass the ABSOLUTE $CLAUDE_BIN — PATH may not resolve inside the workspace shell.
raw=$("$CMUX" new-workspace --cwd "$abs_worktree" --command "$CLAUDE_BIN --session-id $session_id")
ws_id=$(echo "$raw" | "$GREP" -oE 'workspace:[0-9]+' | "$HEAD" -1)

# 2. Guard: abort if ws_id is empty or malformed. A blank --workspace silently
#    targets the currently-selected workspace (the orchestrator running this skill).
case "$ws_id" in
  workspace:[0-9]*) ;;
  *) echo "REFUSE: bad ws_id='$ws_id' from raw='$raw'"; exit 1 ;;
esac

# 3. Rename tab so the workspace is identifiable in the CMUX UI.
#    Title is a POSITIONAL arg — there is NO --name flag (it would rename to the
#    literal string "--name <label>"). Re-check ws_id is non-empty + well-formed first.
"$CMUX" rename-workspace --workspace "$ws_id" "$label"

# 4. Wait for the claude TUI to actually be ready, then queue the composite prompt.
#    Do NOT use a blind `sleep N` — boot time varies (plugins/banners can push it
#    past 10s, and a send to a not-yet-ready input silently vanishes). Poll the live
#    screen with `read-screen` until a readiness marker appears, with a hard cap.
#    A single literal `❯` is fragile across Claude CLI versions/themes (glyph or
#    color can change) — match ANY of: the `❯` glyph, a `>` at the start of a
#    line, or the idle-footer string "for shortcuts". Any one of the three is
#    sufficient evidence the TUI is accepting input.
ready=0
for _ in $(seq 1 30); do          # up to ~30s
  if "$CMUX" read-screen --workspace "$ws_id" --lines 40 | "$GREP" -qE '❯|^>|for shortcuts'; then
    ready=1; break
  fi
  "$SLEEP" 1
done
[ "$ready" = 1 ] || echo "WARN: claude input prompt not detected after 30s; sending anyway"
```

**Resolve `docsRoot` once, then reuse it.** In order:
1. `config.docsRoot`, if set.
2. `<repo-root>/docs/.superpowers/` **if it exists and is non-empty** — an existing repo keeps
   using the dotted path so prior specs, plans and context are never stranded or split.
3. Otherwise `<repo-root>/docs/superpowers/` — canonical for every new repo.

Never pick between the two variants ad hoc. Layout underneath is
`${docsRoot}/{specs,plans,context,findings}/`.

```bash
# Step 1 of the precedence above (config.docsRoot in .claude/workflow.json /
# .claude/workflow.local.json) — if set there, use that value directly
# instead of the filesystem check below. Steps 2-3 (filesystem fallback):
if [ -d "$CWD_ROOT/docs/.superpowers" ] && [ -n "$(ls -A "$CWD_ROOT/docs/.superpowers" 2>/dev/null)" ]; then
  docsRoot="$CWD_ROOT/docs/.superpowers"
else
  docsRoot="$CWD_ROOT/docs/superpowers"
fi
mkdir -p "$docsRoot/findings"
```

Ensure the repo's `.gitignore` contains unanchored `superpowers/` and `.superpowers/` entries —
unanchored so they match at any depth. Add them if absent. This directory is scratch, not product.

**Resolve the install command once, then reuse it.** Same resolution layer as
`juel:cmux-ship-tickets` — probed in tiers, stopping at the first verified hit, never invented if
nothing resolves:

- **Tier A — project-authored task runners** (highest priority): `Makefile`, `justfile`,
  `Taskfile.yml`, `mise.toml`. Emit `make install` / `just install` / `task install` / `mise run
  install` only if that target actually exists.
- **Tier B — language manifests:** `package.json` (+ lockfile → package manager) → `<pm> install`;
  `pyproject.toml` (+ `uv.lock`/`poetry.lock`) → `uv sync` / `poetry install`; `Cargo.toml` →
  `cargo fetch`; `go.mod` → `go mod download`; `mix.exs` → `mix deps.get`; `Gemfile` →
  `bundle install`; Gradle/Maven → `./gradlew build` / `mvn install -DskipTests`; `composer.json`
  → `composer install`; `*.csproj` → `dotnet restore`.
- **Tier C — CI, as a last resort:** an install-shaped `run:` step from `.github/workflows/*.yml`,
  treated as a suggestion and confirmed with the user, never run blind.

**Verify before accepting:**

```sh
head_bin=$(printf '%s' "$cmd" | awk '{print $1}')
case "$head_bin" in
  ./*) [ -x "$head_bin" ] || reject ;;
  *)   command -v "$head_bin" >/dev/null 2>&1 || reject ;;
esac
```

For `make`/`just`/`task`, additionally confirm the `install` target exists. On reject, fall through
to the next tier. Resolution is side-effect free — never run the command itself while resolving.

```bash
INSTALL_CMD=""   # resolved once here against "$CWD_ROOT"; the "open second tab" step below
                  # (end of Step 4) reuses this exact value — never re-detected
# ... detection per the tiers above, assigning INSTALL_CMD on the first verified hit ...
```

**If `INSTALL_CMD` stays empty, that is not an error** — the second-tab step at the end of Step 4
skips itself entirely for this review rather than opening a tab that runs nothing.

**Resolve the base branch once, then reuse it.** In order: explicit `[base-branch]` argument (the
second word of the invocation, if the user gave one) → `config.baseBranch` → `git config --get
claude.baseBranch` → `git symbolic-ref --short refs/remotes/origin/HEAD` (if missing, `git remote
set-head origin --auto` and retry once) → `gh repo view --json defaultBranchRef -q
.defaultBranchRef.name` → first existing of main, master, develop, dev, trunk → ask once and offer
to persist.

**Caveat:** default and *integration* branch differ in gitflow repos. If a `develop`/`dev` branch
exists on the remote AND ≥70% of the last 30 merges into it came from `feat/*`-shaped branches,
prefer it and say so. Config always wins.

```bash
# Resolve once, in THIS shell, before the prompt string below is built — the spawned inner
# claude inherits nothing and cannot resolve a base-branch placeholder itself.
base_branch="<explicit [base-branch] argument, if the user gave one — else leave empty>"
[ -n "$base_branch" ] || base_branch=$(git -C "$CWD_ROOT" config --get claude.baseBranch 2>/dev/null)
if [ -z "$base_branch" ]; then
  base_branch=$(git -C "$CWD_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
fi
if [ -z "$base_branch" ]; then
  git -C "$CWD_ROOT" remote set-head origin --auto >/dev/null 2>&1
  base_branch=$(git -C "$CWD_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
fi
if [ -z "$base_branch" ]; then
  base_branch=$("$GH" repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
fi
if [ -z "$base_branch" ]; then
  for cand in main master develop dev trunk; do
    git -C "$CWD_ROOT" show-ref --verify --quiet "refs/remotes/origin/$cand" && { base_branch=$cand; break; }
  done
fi
# Gitflow caveat: prefer develop/dev as the INTEGRATION branch (not just the default
# branch) when >=70% of its last 30 merges came from feat/*-shaped branches.
for integ in develop dev; do
  git -C "$CWD_ROOT" show-ref --verify --quiet "refs/remotes/origin/$integ" || continue
  total=$(git -C "$CWD_ROOT" log --merges -n 30 "origin/$integ" --format=%s 2>/dev/null | wc -l | tr -d ' ')
  [ "$total" -gt 0 ] || continue
  feat=$(git -C "$CWD_ROOT" log --merges -n 30 "origin/$integ" --format=%s 2>/dev/null | "$GREP" -ciE 'feat/')
  if [ "$(( feat * 100 / total ))" -ge 70 ]; then
    base_branch="$integ"
  fi
  break
done
if [ -z "$base_branch" ]; then
  echo "No base branch detected from git/gh. Ask the user once for the base branch before continuing (offer to persist the answer as config.baseBranch in .claude/workflow.json) — do not guess silently, do not fall back to any hardcoded branch name."
fi
```

**`base_branch` must be resolved here, in THIS shell, before the prompt string below is built.**
Exactly like `docsRoot`, the spawned inner `claude` session inherits nothing and cannot resolve a
`${base_branch}` placeholder itself; the `prompt=` assignment below is a double-quoted bash string,
so `${base_branch}` inside it expands to the literal resolved branch name at the moment the string
is built — the inner session always receives a real, detected branch name and never
an unresolved placeholder.

**`docsRoot` must be resolved here, in THIS shell, before the prompt string below is built.** The
spawned inner `claude` session inherits nothing from this script — it cannot resolve `${docsRoot}`
itself. The `prompt=` assignment below is a double-quoted bash string, so `${docsRoot}` inside it
expands to the literal resolved path at the moment the string is built; what gets sent to the inner
session is that literal path, never an unresolved placeholder.

```bash
# Composite prompt — ONE LINE (real newlines submit prematurely). Inner claude runs
# the review, then dispatches codex to second-opinion every finding against the diff.
# Codex validation: use `codex exec` (NOT `codex exec review`) so a custom prompt and a
# base diff can coexist. `codex exec review --base <b> "<prompt>"` is REJECTED by codex
# (>=0.140): `--base` cannot combine with a positional prompt. Instead let codex run the
# diff itself inside the prompt. Do NOT pin -m / model_reasoning_effort — codex defaults.
prompt="First, if a work-item ref was resolved (${REF:-NONE}), fetch it via the Linear MCP get_issue for ${REF:-NONE} and read its requirements and acceptance criteria; treat them as the spec this PR must satisfy (if NONE, skip work-item grading and note that in the report). Then run /pr-review-toolkit:review-pr against base branch ${base_branch}. Capture every finding (file, line, severity, claim, suggested fix) AND assess whether the diff actually fulfils each work-item requirement / acceptance criterion, flagging any that are unmet, partially met, or scope-creep beyond the work item. Then validate the code findings independently with codex: for each finding ask codex whether it is correct, incorrect, or out-of-scope with reference to the actual diff, using: codex exec --sandbox read-only \"First run: git diff ${base_branch}...HEAD to see the real changes, then validate the following review findings against that diff. For each return VALID / INVALID / OUT-OF-SCOPE with one-sentence justification. Findings: <paste findings here>\". Do NOT pin a codex model or reasoning effort. Produce a final consolidated report with four sections: Requirement-alignment (each requirement/acceptance criterion marked met / partial / unmet with evidence, plus any scope-creep), Confirmed (both reviewers agree), Disputed (codex disagrees with the original review), Codex-only (issues codex raised that the review missed). Save it to ${docsRoot}/findings/findings-review.md. run /pr-review-toolkit:review-pr in the FOREGROUND (run_in_background: false), do not use parallel mode, read its complete output before continuing, and run codex in the foreground without redirecting its output to any file."

"$CMUX" send --workspace "$ws_id" "$prompt"
"$SLEEP" 1
"$CMUX" send-key --workspace "$ws_id" Enter

# 5. If an install command resolved (INSTALL_CMD, above), open a second tab and run it
#    so deps install in parallel with the review (mirrors juel:cmux-ship-tickets). Must
#    be a NEW surface — typing into the claude tab would feed it to the agent as a
#    prompt, not the shell. If nothing resolved, skip this whole step — do not open a
#    tab that runs nothing.
if [ -n "$INSTALL_CMD" ]; then
  raw2=$("$CMUX" new-surface --type terminal --workspace "$ws_id")
  surface_id=$(echo "$raw2" | "$GREP" -oE 'surface:[0-9]+' | "$HEAD" -1)
  case "$surface_id" in
    surface:[0-9]*)
      "$SLEEP" 1
      "$CMUX" send --workspace "$ws_id" --surface "$surface_id" "$INSTALL_CMD"
      "$SLEEP" 1
      "$CMUX" send-key --workspace "$ws_id" --surface "$surface_id" Enter ;;
    *) echo "WARN: failed to parse surface id from: $raw2 — skipping install"; surface_id="" ;;
  esac
else
  echo "No install command resolved for this repo — skipping the second surface. Install dependencies yourself."
fi
```

If `cmux new-workspace` output cannot be parsed, fall back to `"$CMUX" list-workspaces` and pick the newest entry whose cwd matches `$abs_worktree`. Still re-verify against the `workspace:[0-9]+` regex before any send.

### Step 5: Report

```
Workspace ready for review:
  PR/branch : <pr or branch>
  Work item : <SAVI-XXX or "none — ungraded">
  Worktree  : <abs path>
  Session   : <uuid>   (resume: `claude --resume <uuid>`)
  CMUX ws   : workspace:<N> (renamed to <label>)
  Deps      : <resolved install command> running in tab 2 (surface:<M>), or "none resolved — skipped, install deps yourself"
```

## Edge cases

| Situation | Action |
|-----------|--------|
| PR is merged or closed | Warn user, ask whether to continue |
| No ref in branch or title | Review proceeds ungraded; note "no ref" in the report. Do not block. |
| PR title has a ref with no surrounding `[...]`/`type(...)` tag (e.g. bare `SAVI-1343 Fix login`, no brackets) | Known limitation: the title fallback only extracts from a bracket or conventional-commit-scope span, deliberately, to avoid segmenting free-form prose (see Step 1b). Falls through to "no ref" unless the branch name already carried it — branch is tried first and usually does. |
| Ref extracted but Linear `get_issue` fails / not found | Inner claude proceeds with code review only; Requirement-alignment section records the fetch failure instead of grading. |
| Local branch with same name already checked out elsewhere | Use `git worktree add --detach` + `gh pr checkout` style instead of duplicate branch |
| `.worktrees/review-<slug>` already exists | Reuse; do not re-fetch unless user asks |
| `pr-review-toolkit` not installed | Stop and instruct user to install the plugin |
| `command not found: cmux` (or claude/sleep/head/grep/gh) mid-script after earlier resolution succeeded | Not a PATH drop — this is a fresh non-login shell that never had the earlier call's variables. Source `$BINS` (see "Resolve binaries once, persist, then source every call") and use the absolute-path variables everywhere. Do not retry with bare names. |
| `cmux <subcmd>` rejects a flag (CLI version drift) | Run `cmux <subcmd> --help`, adapt once, continue. Do NOT loop on broken flags. |
| Workspace creation succeeds but `ws_id` parse fails | Fall back to `cmux list-workspaces`, match by cwd. Never call `rename-workspace` / `send` / `send-key` with an empty `--workspace` — silently targets the orchestrator. |
| Prompt never appears / input box empty after send | Send hit the TUI before it was ready (blind `sleep` too short; plugins/banners delay boot). Use the `read-screen` readiness poll (wait for `❯`, `>` at line start, or `for shortcuts`) before sending. To recover: `read-screen` to confirm the empty input, then re-`send` the single-line prompt and `send-key Enter`. |
| Slash command typed but not submitted (sits as a draft) | `send-key Enter` was not invoked after `send`. Re-send Enter via `"$CMUX" send-key --workspace "$ws_id" Enter`. |
| Multi-line prompt submitted in fragments | Real newlines in a `cmux send` payload each act as Enter. Send the prompt as a SINGLE LINE. |
| Install second tab not created despite `INSTALL_CMD` being non-empty | `new-surface` output parse failed; review still proceeds in tab 1. Re-run `"$CMUX" new-surface --type terminal --workspace "$ws_id"` and send `$INSTALL_CMD` to the returned surface. |
| No install command resolves for this repo | Not an error — skip the second surface entirely (per "Resolve the install command once" above) and note "none resolved" in the Step 5 report. Never invent `npm install`/`make install` for a repo where nothing verified. |
| `claude --session-id` rejects uuid | Launch `claude` without session id; warn that resume needs picker. |
| User gave a forked-PR url and `gh pr checkout` fails auth | Surface `gh` error verbatim, do not retry blindly. |

## QA checklist

- [ ] All binaries resolved once via `resolve_bin`, persisted to `$BINS`, and sourced (not re-resolved) at the top of every subsequent call (cmux, claude, gh, sleep, grep, head) — `python3` and `jq` are never resolved, both dependencies removed
- [ ] No `cd` in the orchestrator script (only inside subshells `( cd ... && ... )`)
- [ ] PR/branch resolved correctly (right repo, right head ref)
- [ ] Ref extracted from branch via `detect_ref` (fallback: PR title, but ONLY the `[...]`/`type(...)` tag span is fed to `detect_ref` — never the whole title, which would leak phantom refs from ordinary prose), uppercased; empty → review proceeds ungraded (not blocked). `DENY` byte-identical to `references/resolution.md` §5 / `skills/start/SKILL.md`
- [ ] Worktree under `<MAIN_ROOT>/.worktrees/review-<slug>` with env files copied
- [ ] CMUX workspace cwd = worktree absolute path
- [ ] `ws_id` parsed and matches `workspace:[0-9]+` before any `send` / `send-key` / `rename-workspace`
- [ ] Workspace tab renamed via POSITIONAL title (NOT `--name`) — verify the sidebar shows just `<label>`, not `--name <label>`
- [ ] `"$CLAUDE_BIN" --session-id <uuid>` launched in the workspace (absolute path, not bare `claude`)
- [ ] `read-screen` readiness poll (wait for ANY of `❯`, `>` at line start, or `for shortcuts`) used before `send` — NOT a blind `sleep`, NOT a poll for `❯` alone
- [ ] Composite prompt sent as a SINGLE LINE (no real newlines), typed AND Enter pressed (visible as a submitted prompt, not a draft)
- [ ] Prompt instructs inner claude to fetch the work item (`get_issue` for `$REF`) and grade the diff against its requirements/acceptance criteria before the code review
- [ ] Codex validation step uses `codex exec --sandbox read-only "<prompt>"` (NOT `codex exec review --base ...`, which rejects a prompt), with the prompt telling codex to `git diff <base>...HEAD` itself, and NO `-m` / `model_reasoning_effort` override (codex defaults)
- [ ] `INSTALL_CMD` resolved once (against `$CWD_ROOT`, before Step 4's second-tab step) via the tiered detection layer; if non-empty, a second tab (surface) opened with it running (sent to the new surface, NOT the claude tab); if empty, the second surface is skipped entirely (no error, no empty tab)
- [ ] `export CMUX_QUIET=1` set so alias-deprecation notices are silenced
- [ ] `docsRoot` resolved once (config, then existing non-empty dotted dir, then canonical) before the prompt string is built, and expanded to a literal path inside the double-quoted `prompt=` assignment — never sent to the inner session as an unresolved `${docsRoot}` placeholder
- [ ] `base_branch` resolved once (explicit argument → config → git → gh → main/master/develop/dev/trunk → ask) before the prompt string is built, and expanded to a literal branch name inside the double-quoted `prompt=` assignment — never an unresolved `${base_branch}` placeholder, never a bash-fallback literal
- [ ] Repo's `.gitignore` contains unanchored `superpowers/` and `.superpowers/` entries (added if absent)
- [ ] Final report destination `${docsRoot}/findings/findings-review.md` mentioned in the prompt with the four buckets (Requirement-alignment / Confirmed / Disputed / Codex-only)
- [ ] Final report shows PR id, ref, worktree path, session id, workspace id, make-install surface
- [ ] No accidental rename / send against the orchestrator workspace
