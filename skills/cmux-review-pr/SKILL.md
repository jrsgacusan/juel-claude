---
name: cmux-review-pr
description: Use to review a GitHub PR (or arbitrary branch) inside an isolated CMUX workspace. Creates a git worktree for the PR branch, spawns a CMUX workspace, auto-launches the resolved agent with deterministic Claude/Codex session handling, resolves the linked work-item ref, then runs the review skill inside that workspace. Triggers "review pr", "/juel:cmux-review-pr".
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
        why: phase 6 launches the selected agent inside the review workspace
        check: "resolve_agent from rule 0; it calls resolve_bin against PATH, then GUI/Homebrew candidates"
      - id: gh
        hard: true
        why: phase 2 resolves the PR argument to a branch and label
        check: "gh auth status"
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
      - id: juel:review-pr
        hard: true
        why: queued as the startup prompt inside the spawned workspace
    perms:
      - id: permission-mode-auto
        hard: true
        why: the spawned session must not stall on the first tool prompt — nobody is watching a spawned CMUX session to answer it
---

# Juel CMUX Review PR

Sister skill of `juel:cmux-ship-tickets`. Same plumbing (worktree + CMUX workspace + deterministic claude session) — this skill's only job is to stand up that workspace and queue `/juel:review-pr` in it. It resolves the work-item ref (branch first, then PR title, via the same `detect_ref` helper `juel:start` inlines) and passes it along; everything about the review itself — grading against the work item, dispatching `pr-review-toolkit:review-pr`, validating findings, writing the consolidated report to `${docsRoot}/findings/findings-review.md` — lives in `juel:review-pr`, not here.

**Announce:** "Using juel:cmux-review-pr to set up a CMUX workspace for review."

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v7 -->

**0. Harness check, before every other rule.** If you do not have the `TaskCreate` tool, you are not running in Claude Code. Read `references/harness-codex.md`, resolved relative to this skill file's own location (`../../references/harness-codex.md`), and apply its construct map, corrected facts, dependency substitutions and degradation contract to every rule below and to every phase body in this skill. This single read is the one action permitted before rule 1's preflight, and only in that case. If you do have `TaskCreate`, ignore that file entirely and continue to rule 1.

**1. Preflight, then task list, before anything else.** Before any other output and before any tool call, emit the Preflight block (below). If the preflight verdict is STOP, print the preflight block and **stop** — do not create tasks and do not begin work. Otherwise, before any other work, create one task per phase in this skill's `## Phases` list via `TaskCreate` — `subject` is the phase name, `activeForm` is its present-continuous form. This task list, rendered persistently by the harness, IS the checklist; nothing else satisfies this rule. This is not optional on re-invocation, on resume, or when the user says "just do it".
- **If `TaskCreate`/`TaskUpdate` genuinely fail** — one attempted call returns an error, never merely assumed unavailable in advance — fall back to an explicit numbered phase log, printed after every phase transition with the same one-line evidence rule 3 already requires. State the degradation once, in one line, before continuing. Never silently swap to prose without saying so.

**2. Phases run in order.** No skipping, reordering, or merging. A phase that does not apply is still announced, not dropped: mark its task `completed` via `TaskUpdate`, with the one-line evidence required by rule 3 stating the skip reason (e.g. "SKIPPED: <reason>") — the task list has no separate "skipped" status, so a skipped phase becomes `completed` too. Never begin phase N+1 before phase N's task is marked `completed`.

**3. Report after every phase.** Mark the phase's task `in_progress` via `TaskUpdate` when starting it, then `completed` via `TaskUpdate` when it finishes or is skipped — each transition accompanied by exactly one line of evidence (path written, command run, count found). Do not re-print the checklist as text; the task list is the persistent record and replaces that. Never claim progress in prose alone.

**4. `review-pr`'s agents run in PARALLEL and FOREGROUND; `code-simplifier` runs FOREGROUND; `codex exec` runs BACKGROUND, WATCHED, and WAITED-ON.** This overrides every other instruction in this file and in any skill invoked from it. Foreground/background is about whether the tool call blocks; watched is about whether output still streams somewhere the user can see it — these are different axes, and `codex exec` needs the second without the first. `review-pr`'s agents additionally need PARALLEL: dispatched together, not one at a time.
- `pr-review-toolkit:review-pr`'s agents MUST be dispatched in parallel: pass `all parallel`, or dispatch the agents together in ONE message. Its sequential default — one agent at a time — is the exact slowness this rule exists to prevent; requesting it, or omitting `all parallel`, is a violation.
- `pr-review-toolkit:review-pr` and `code-simplifier` are foreground-only. Invoke both with `run_in_background: false` **explicitly** — the harness backgrounds subagents by default, so omitting the flag is a violation, not a neutral choice. Dispatching review-pr's agents in parallel does not relax this: each agent in that one message still carries its own explicit `run_in_background: false`. Never `&`. Never `run_in_background: true` for these two. Never "dispatch and continue".
- `codex exec` runs through the **Bash tool**, whose `timeout` parameter is capped at 600000ms (10 minutes). A real `codex exec` applying a plan routinely runs longer than that, so a foreground dispatch gets silently DETACHED by the harness at the cap regardless of this rule — nothing then watches it, nothing reads its output, and the skill would wrongly proceed as if the phase had ended. `review-pr` and `code-simplifier` run through the **Skill/Agent tool**, which carries no such cap — that is the entire reason only `codex exec` changes. Do not "fix" this back to foreground; the cap is a harness fact, not a preference.
- **Always dispatch `codex exec` with `run_in_background: true`** — not optional, not "if it looks long," always. Omitting the flag, or passing `false`, is a violation.
- **Never redirect a command's output to a log file.** No `> out.log`, no `| tee`, no writing output somewhere to read back later. This applies to all three, and is now MORE load-bearing for `codex exec`: backgrounded with no ceiling, the shell is the only place the user watches it work.
- For `review-pr` and `code-simplifier`: read the complete output and state the outcome — finding count, exit status, files changed — before marking the phase done. A summary may follow the raw output; it may never replace it.
- For `codex exec`: wait for it to exit before marking the phase done — backgrounding must never become fire-and-forget. Then state the outcome — exit status, files changed — not a transcript; the user already watched it stream in the shell, so its full output is never printed back into the conversation.
- **Never attach a `Monitor` or a polling loop to `codex exec`.** No `Monitor` armed on its output, no repeated reads of the `.output` file, no `tail -f`. Dispatch it backgrounded and wait for the completion notification — the user already watches it stream in their own shell, which is exactly why output must never be redirected; a watcher on top adds nothing, and a filter with no pattern for `Reading additional input from stdin...` will misread a stalled executor as healthy.
- Passing any of this into another session (a CMUX prompt, a nested `claude`) carries these rules with it — say so explicitly in that prompt string.

**5. Confirmation gates stack; they do not replace this.** Where this skill pauses between phases, the checklist report comes first, then the "Proceed to phase N+1?" question. A user's "yes" advances exactly one phase — it never authorizes skipping ahead or batching the remainder.

**6. `Idling` is a status, not a verdict — never read it as "returned nothing."** When a dispatched `pr-review-toolkit:review-pr` agent or `code-simplifier` shows `Idling` (or any non-streaming status) in the harness's agent view while its call is still in flight, that status alone never means the agent produced no output — `Idling` covers both "still working" and "finished, with a result already available but not yet consumed by this session" indistinguishably. Multi-agent dispatch is exactly where this bites: `pr-review-toolkit:review-pr`'s specialist agents run "all parallel" (rule 4), so several can sit at `Idling` simultaneously while one has already returned and the others haven't.
- **Before concluding a dispatch returned nothing, or re-dispatching it, check `ListAgents` for the agent by name.** If it's listed with a result available, read that result directly — do not wait further and do not re-dispatch a duplicate call.
- **Never re-dispatch `pr-review-toolkit:review-pr` or `code-simplifier` "to unstick it"** without first confirming via `ListAgents` that the original dispatch genuinely produced nothing — re-dispatching a call whose result already exists wastes a full review cycle and risks duplicate, conflicting findings.
- **Never go quiet past a check-in point with no status update.** If a dispatch has been running long enough that you would normally report progress, either report genuine progress or check `ListAgents` first — silently waiting while a subagent is actually done is the exact failure this rule exists to prevent.

## Preflight

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| cmux | cli | HARD | `resolve_bin cmux` against PATH, then GUI/Homebrew candidates | STOP → https://github.com/manaflow-ai/cmux |
| claude | cli | HARD | `resolve_agent` from rule 0 | STOP → install the selected agent CLI |
| gh (authenticated) | cli | HARD | `gh auth status` | STOP → `gh auth login` |
| coreutils | cli | HARD | `resolve_bin` per binary (sleep/grep/head) against PATH, then `/usr/bin`,`/bin` candidates | STOP |
| git repo matching the PR remote | context | HARD | `git remote get-url <remote>` | STOP |
| resolvable PR or branch | context | HARD | `gh pr view <N> --json number` | STOP |
| juel:review-pr | skill | HARD | ships with this plugin | STOP |
| `--permission-mode auto` | perm | HARD | none — render as `?` | STOP → under Claude, the account is not entitled to `--permission-mode auto`; under Codex, `--approve-for-me` is required or a spawned session stalls at its first commit. Never spawn a session nobody is watching without one of them. |
| Linear MCP | mcp | SOFT | **none — render as `?`** | review proceeds ungraded; the alignment section is omitted |
| resolved install command | cli | SOFT | see resolution layer | skip the second surface; install deps yourself |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Preflight — resolve binaries via resolve_bin, persist to BINS, set CMUX_QUIET
2. Resolve the PR to a branch and label
3. Extract the work-item ref from the branch, falling back to the PR title
4. Create the worktree and copy untracked env files
5. Compute the deterministic session id
6. Spawn the workspace, rename it, poll for the prompt, send the review prompt + Enter
7. Open the second surface and start the resolved install command
8. Report PR, work item, worktree, session, workspace, surface
9. Verify the QA checklist

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<pr-or-branch>` | yes | Either `#1234`, `1234`, a GitHub PR URL, or a branch name |

Usage: `/juel:cmux-review-pr 1234` or `/juel:cmux-review-pr feat/savi-1162-foo`.

## Prerequisites

- `cmux` CLI installed — resolved via `resolve_bin` (PATH first, then the GUI install at `/Applications/cmux.app/Contents/Resources/bin/cmux` and Homebrew paths as candidates, not the sole fallback).
- The selected agent CLI installed and resolved through `resolve_agent`.
- `gh` CLI on PATH and authenticated. `gh` embeds its own `jq` — a standalone `jq` binary is never required, see "Resolve the PR" below.
- Inside a git repo whose remote matches the PR.
- `juel:review-pr` skill available (ships with this plugin) — it runs `/pr-review-toolkit:review-pr` itself.

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
# Rule 0 already told you which harness you are in. Pass that explicit kind to
# resolve_agent; do not guess from the machine's installed binaries.
resolve_agent "$AGENT_KIND_FROM_RULE0" || { echo "no agent CLI found for $AGENT_KIND_FROM_RULE0"; exit 1; }
echo "AGENT_KIND=$AGENT_KIND"; echo "AGENT_BIN=$AGENT_BIN"
GH=$(resolve_bin gh /opt/homebrew/bin/gh /usr/local/bin/gh /usr/bin/gh) || GH=
SLEEP=$(resolve_bin sleep /usr/bin/sleep /bin/sleep) || SLEEP=
GREP=$(resolve_bin grep /usr/bin/grep /bin/grep) || GREP=
HEAD=$(resolve_bin head /usr/bin/head /bin/head) || HEAD=

[ -n "$CMUX" ] || { echo "cmux not found on PATH or any candidate location"; exit 1; }
[ -n "$GH" ] || { echo "gh not found on PATH or any candidate location"; exit 1; }
[ -n "$SLEEP" ] && [ -n "$GREP" ] && [ -n "$HEAD" ] || { echo "missing coreutils"; exit 1; }

GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)   # normalized — --git-common-dir
                                                                   # can print a RELATIVE ".git"
BINS="$GIT_COMMON/claude/bins.env"
mkdir -p "$(dirname "$BINS")"
{
  echo "CMUX=$CMUX"; echo "AGENT_KIND='$AGENT_KIND'"; echo "AGENT_BIN='$AGENT_BIN'"
  echo "AGENT_LAUNCH_FLAGS='$AGENT_LAUNCH_FLAGS'"; echo "AGENT_PROMPT_PREFIX='$AGENT_PROMPT_PREFIX'"
  echo "AGENT_READY_MARKER='$AGENT_READY_MARKER'"; echo "AGENT_APPROVAL_MARKER='$AGENT_APPROVAL_MARKER'"
  echo "AGENT_NOTIFICATION_LABEL='$AGENT_NOTIFICATION_LABEL'"; echo "GH=$GH"
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

(`BINS` itself is a shell variable and does not survive either — recompute the path fresh, then source. Recomputing the path is cheap; re-running the `resolve_bin` candidate search every call is what this pattern avoids.) Use `"$CMUX"`, `"$AGENT_BIN"`, `"$GH"`, `"$SLEEP"`, `"$GREP"`, `"$HEAD"` (never bare names) in every command.

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

Deterministic, uuid-shaped id from the label so Claude's `--resume` path is repeatable — no `python3`
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
`$session_id`, in `sh`, `bash` and `zsh` alike, which is the only property the Claude resume path
actually needs.

### Step 4: Spawn CMUX workspace and queue the review

```bash
# 1. Create workspace; --command launches the selected agent with Enter pressed automatically.
#    Pass the ABSOLUTE $AGENT_BIN — PATH may not resolve inside the workspace shell.
case "$AGENT_KIND" in
  claude) launch="$AGENT_BIN --session-id $session_id $AGENT_LAUNCH_FLAGS" ;;
  codex)  launch="$AGENT_BIN $AGENT_LAUNCH_FLAGS" ;;
  *) echo "unsupported agent kind: $AGENT_KIND"; exit 1 ;;
esac
raw=$("$CMUX" new-workspace --cwd "$abs_worktree" --command "$launch")
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

# 4. Wait for the agent TUI to actually be ready, then queue the composite prompt.
#    Do NOT use a blind `sleep N` — boot time varies (plugins/banners can push it
#    past 10s, and a send to a not-yet-ready input silently vanishes). Poll the live
#    screen with `read-screen` until a readiness marker appears, with a hard cap.
#    A single literal `❯` is fragile across Claude CLI versions/themes (glyph or
#    color can change) — match ANY of: the `❯` glyph, a `>` at the start of a
#    line, or the agent's configured idle-footer marker. The configured marker is
#    sufficient evidence the TUI is accepting input.
ready=0
for _ in $(seq 1 30); do          # up to ~30s
  if "$CMUX" read-screen --workspace "$ws_id" --lines 40 | "$GREP" -qF "$AGENT_READY_MARKER"; then
    ready=1; break
  fi
  "$SLEEP" 1
done
[ "$ready" = 1 ] || echo "WARN: agent input prompt not detected after 30s; sending anyway"

# Codex has no launch-time --session-id. Its live session can be named after the
# prompt is ready so `codex resume <name>` remains deterministic.
if [ "$AGENT_KIND" = codex ] && [ -n "$pr_number" ]; then
  codex_session_name=juel
  codex_session_name="${codex_session_name}-pr-$pr_number"
  "$CMUX" send --workspace "$ws_id" "/rename $codex_session_name"
  "$SLEEP" 1
fi
```

This skill does not resolve `docsRoot` or a base branch itself — the review skill, queued into the
workspace below, resolves both of those for itself once it is running inside the worktree.

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

**`REF` must be resolved here, in THIS shell (Step 1b, above), before the prompt string below is
built.** The spawned inner agent session inherits nothing from this script — it cannot resolve a
`${REF}` placeholder itself. The `prompt=` assignment below is a double-quoted bash string, so
`${REF}` inside it expands to the literal resolved ref (or nothing, if none resolved) at the moment
the string is built.

```bash
# Prompt — ONE LINE (real newlines submit prematurely). Everything the review needs to
# know — grading against the work item, dispatching pr-review-toolkit:review-pr,
# validating findings, writing the consolidated report — lives inside juel:review-pr
# itself; this orchestrator only queues the command and, if one resolved, the ref.
# ${REF:+ $REF} expands to " <REF>" when REF is non-empty, or nothing at all when it
# isn't — juel:review-pr resolves its own ref in that case rather than blocking.
prompt="${AGENT_PROMPT_PREFIX}juel:review-pr${REF:+ $REF}"

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
  Session   : <uuid>   (Claude: `claude --resume <uuid>`; Codex: `codex resume <name derived from PR>`)
  CMUX ws   : workspace:<N> (renamed to <label>)
  Deps      : <resolved install command> running in tab 2 (surface:<M>), or "none resolved — skipped, install deps yourself"
```

## Edge cases

| Situation | Action |
|-----------|--------|
| PR is merged or closed | Warn user, ask whether to continue |
| No ref in branch or title | Review proceeds ungraded; note "no ref" in the report. Do not block. |
| PR title has a ref with no surrounding `[...]`/`type(...)` tag (e.g. bare `SAVI-1343 Fix login`, no brackets) | Known limitation: the title fallback only extracts from a bracket or conventional-commit-scope span, deliberately, to avoid segmenting free-form prose (see Step 1b). Falls through to "no ref" unless the branch name already carried it — branch is tried first and usually does. |
| Ref extracted but Linear `get_issue` fails / not found | `juel:review-pr`, inside the workspace, proceeds with code review only; its Requirement-alignment section records the fetch failure instead of grading. |
| Local branch with same name already checked out elsewhere | Use `git worktree add --detach` + `gh pr checkout` style instead of duplicate branch |
| `.worktrees/review-<slug>` already exists | Reuse; do not re-fetch unless user asks |
| `juel:review-pr` not installed | Stop and instruct user to install/update the plugin |
| `command not found: cmux` (or the selected agent/sleep/head/grep/gh) mid-script after earlier resolution succeeded | Not a PATH drop — this is a fresh non-login shell that never had the earlier call's variables. Source `$BINS` (see "Resolve binaries once, persist, then source every call") and use the absolute-path variables everywhere. Do not retry with bare names. |
| `cmux <subcmd>` rejects a flag (CLI version drift) | Run `cmux <subcmd> --help`, adapt once, continue. Do NOT loop on broken flags. |
| Workspace creation succeeds but `ws_id` parse fails | Fall back to `cmux list-workspaces`, match by cwd. Never call `rename-workspace` / `send` / `send-key` with an empty `--workspace` — silently targets the orchestrator. |
| Prompt never appears / input box empty after send | Send hit the TUI before it was ready (blind `sleep` too short; plugins/banners delay boot). Use the `read-screen` readiness poll for `$AGENT_READY_MARKER` before sending. To recover: `read-screen` to confirm the empty input, then re-`send` the single-line prompt and `send-key Enter`. |
| Slash command typed but not submitted (sits as a draft) | `send-key Enter` was not invoked after `send`. Re-send Enter via `"$CMUX" send-key --workspace "$ws_id" Enter`. |
| Multi-line prompt submitted in fragments | Real newlines in a `cmux send` payload each act as Enter. Send the prompt as a SINGLE LINE. |
| Install second tab not created despite `INSTALL_CMD` being non-empty | `new-surface` output parse failed; review still proceeds in tab 1. Re-run `"$CMUX" new-surface --type terminal --workspace "$ws_id"` and send `$INSTALL_CMD` to the returned surface. |
| No install command resolves for this repo | Not an error — skip the second surface entirely (per "Resolve the install command once" above) and note "none resolved" in the Step 5 report. Never invent `npm install`/`make install` for a repo where nothing verified. |
| Claude rejects `--session-id` or Codex cannot name a session | Continue with the selected agent without deterministic launch-time naming; report that resume uses the picker or cmux workspace handle. |
| Selected agent rejects `$AGENT_LAUNCH_FLAGS` | STOP. Do not spawn the workspace. Tell the user the selected agent cannot run unattended. Never fall back to a lesser permission mode or `--dangerously-bypass-approvals-and-sandbox`. |
| User gave a forked-PR url and `gh pr checkout` fails auth | Surface `gh` error verbatim, do not retry blindly. |

## QA checklist

- [ ] All binaries resolved once via `resolve_bin`/`resolve_agent`, persisted to `$BINS`, and sourced (not re-resolved) at the top of every subsequent call (cmux, selected agent, gh, sleep, grep, head) — `python3` and `jq` are never resolved, both dependencies removed
- [ ] No `cd` in the orchestrator script (only inside subshells `( cd ... && ... )`)
- [ ] PR/branch resolved correctly (right repo, right head ref)
- [ ] Ref extracted from branch via `detect_ref` (fallback: PR title, but ONLY the `[...]`/`type(...)` tag span is fed to `detect_ref` — never the whole title, which would leak phantom refs from ordinary prose), uppercased; empty → review proceeds ungraded (not blocked). `DENY` byte-identical to `references/resolution.md` §5 / `skills/start/SKILL.md`
- [ ] Worktree under `<MAIN_ROOT>/.worktrees/review-<slug>` with env files copied
- [ ] CMUX workspace cwd = worktree absolute path
- [ ] `ws_id` parsed and matches `workspace:[0-9]+` before any `send` / `send-key` / `rename-workspace`
- [ ] Workspace tab renamed via POSITIONAL title (NOT `--name`) — verify the sidebar shows just `<label>`, not `--name <label>`
- [ ] `$AGENT_BIN` launched in the workspace with the appropriate session naming and `$AGENT_LAUNCH_FLAGS` (absolute path, not a bare binary) — no lesser-permission fallback attempted
- [ ] `read-screen` readiness poll waits for `$AGENT_READY_MARKER` before `send` — NOT a blind `sleep`
- [ ] Prompt (`${AGENT_PROMPT_PREFIX}juel:review-pr` plus the resolved `$REF`, if any) sent as a SINGLE LINE (no real newlines), typed AND Enter pressed (visible as a submitted prompt, not a draft)
- [ ] Prompt string built from `${REF:+ $REF}` only — no `docsRoot`, `base_branch`, or review-procedure prose embedded in it; `juel:review-pr` resolves and does all of that itself once running in the workspace
- [ ] `INSTALL_CMD` resolved once (against `$CWD_ROOT`, before Step 4's second-tab step) via the tiered detection layer; if non-empty, a second tab (surface) opened with it running (sent to the new surface, NOT the claude tab); if empty, the second surface is skipped entirely (no error, no empty tab)
- [ ] `export CMUX_QUIET=1` set so alias-deprecation notices are silenced
- [ ] Final report shows PR id, ref, worktree path, session id, workspace id, make-install surface
- [ ] No accidental rename / send against the orchestrator workspace
