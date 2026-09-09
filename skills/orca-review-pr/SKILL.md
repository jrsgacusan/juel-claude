---
name: orca-review-pr
description: Use to review a GitHub PR (or an arbitrary branch) in its own Orca worktree, checked out on the real PR head branch, with the resolved agent already running `/juel:review-pr`. Resolves the linked work-item ref so the review is graded against it. Triggers "review pr in orca", "/juel:orca-review-pr".
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: grading the review against a work item, when one resolves
        check: none
        fallback: the review proceeds ungraded; the alignment section is omitted
    cli:
      - id: orca
        hard: true
        why: phases 1 and 4 resolve the runtime and create the review worktree
        check: "resolve_bin orca against PATH, then the app-bundle candidate"
      - id: claude
        hard: true
        why: phase 4 launches the selected agent inside the worktree
        check: "resolve_agent from rule 0"
      - id: gh
        hard: true
        why: phase 2 resolves the PR to a head branch
        check: "gh auth status"
      - id: git
        hard: true
        why: phase 4 checks out the real PR head branch after create
        check: "resolve_bin git"
      - id: coreutils
        hard: true
        why: grep/head/cat are resolved once per session via resolve_bin and sourced from BINS every call, since each Bash call is an independent non-login shell
        check: "resolve_bin per binary against PATH, then /usr/bin,/bin candidates"
      - id: resolved-install-command
        hard: false
        why: phase 7 warms deps in a second tab while the review runs in the first
        check: "see resolution layer"
        fallback: skip the second tab; install deps yourself
    context:
      - id: git-repo
        hard: true
        why: Orca creates worktrees against a registered git repo
        check: "git rev-parse --git-dir"
      - id: orca-runtime
        hard: true
        why: every phase talks to the Orca runtime
        check: "orca status reports runtimeReachable: true and graphState: ready"
      - id: orca-repo-registered
        hard: true
        why: worktree create needs this repo's Orca id
        check: "orca repo list contains this repo's path"
      - id: open-pr
        hard: true
        why: the review targets a resolvable PR or branch
        check: "gh pr view <N> --json number"
    skills:
      - id: juel:review-pr
        hard: true
        why: it is the command the spawned session runs
---

# Juel Orca Review PR

Review a PR in its own Orca worktree, sitting on the real PR head branch, with the resolved agent
already running `/juel:review-pr`. Orca creates the checkout, launches the agent and delivers the
prompt in a single call.

Everything the review itself does — grading against the work item, dispatching
`pr-review-toolkit:review-pr`, validating findings, writing the consolidated report — lives inside
`juel:review-pr`. This skill only prepares the worktree and queues the command.

**Announce:** "Using juel:orca-review-pr to review this PR in its own Orca worktree."

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
| orca | cli | HARD | `resolve_bin orca` against PATH, then the app-bundle candidate | STOP → https://www.onorca.dev |
| claude | cli | HARD | `resolve_agent` from rule 0 | STOP → install the selected agent CLI |
| gh (authenticated) | cli | HARD | `gh auth status` | STOP → `gh auth login` |
| git | cli | HARD | `resolve_bin git` | STOP |
| coreutils | cli | HARD | `resolve_bin` per binary (grep/head/cat) against PATH, then `/usr/bin`,`/bin` candidates | STOP |
| git repo | context | HARD | `git rev-parse --git-dir` | STOP |
| reachable Orca runtime | context | HARD | `orca status` reports `runtimeReachable: true` and `graphState: ready` | STOP → run `orca open`, then re-run |
| repo registered with Orca | context | HARD | `orca repo list` contains this repo's path | offer `orca repo add` once, then continue |
| resolvable PR or branch | context | HARD | `gh pr view <N> --json number` | STOP |
| juel:review-pr | skill | HARD | ships with this plugin | STOP |
| Linear MCP | mcp | SOFT | **none — render as `?`** | the review proceeds ungraded; the alignment section is omitted |
| resolved install command | cli | SOFT | see resolution layer | skip the second tab; install deps yourself |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Preflight — resolve binaries via resolve_bin, persist to BINS, confirm the Orca runtime and this repo's Orca id
2. Resolve the PR to a head branch and label
3. Extract the work-item ref from the branch, falling back to the PR title and body
4. Create the Orca worktree and check out the real PR head branch
5. Copy untracked files into the new checkout
6. Clear the first-run trust and bypass dialogs, if any are present
7. Open the install tab when an install command resolved
8. Link the work item and report PR, branch, worktree and handle
9. Verify the QA checklist

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<pr-or-branch>` | yes | Either `#1234`, `1234`, a GitHub PR URL, or a branch name |

Usage: `/juel:orca-review-pr 1234` or `/juel:orca-review-pr feat/savi-1162-foo`.

## Prerequisites

- Orca installed and its CLI registered (Settings → General → Orca CLI), resolved via `resolve_bin` (PATH first, then the app-bundle path as a labelled candidate, never as the sole source).
- The Orca app running, with a reachable runtime. `orca open` starts it and waits.
- This repo registered with Orca. `orca repo add` registers it.
- The selected agent CLI installed and resolved through `resolve_agent`.
- `gh` authenticated against the PR's remote.

### Resolve binaries once, persist, then source every call

Each Bash tool call is an **independent non-login shell** — a binary resolved in call N is unavailable in call N+1 because shell variables and function definitions from call N simply do not exist there. Resolve every binary once via `resolve_bin` (PATH first, then labelled candidates — never a hardcoded absolute path as the sole source), persist the resolved paths to `$GIT_COMMON/claude/bins.env`, and source that file at the top of every later call.

```bash
resolve_bin() {
  n=$1; shift
  p=$(command -v "$n" 2>/dev/null) && { printf '%s' "$p"; return 0; }
  for c in "$@"; do [ -x "$c" ] && { printf '%s' "$c"; return 0; }; done
  return 1
}

# orca is NOT on PATH: the app ships it inside the bundle. The bundle path is a
# labelled candidate tried after PATH, never a value inlined into a command.
ORCA=$(resolve_bin orca /Applications/Orca.app/Contents/Resources/bin/orca \
        "$HOME/.local/bin/orca" /opt/homebrew/bin/orca /usr/local/bin/orca) || ORCA=
# Rule 0 already told you which harness you are in. Pass that explicit kind to
# resolve_agent; do not guess from the machine's installed binaries.
resolve_agent "$AGENT_KIND_FROM_RULE0" || { echo "no agent CLI found for $AGENT_KIND_FROM_RULE0"; exit 1; }
GH=$(resolve_bin gh /opt/homebrew/bin/gh /usr/local/bin/gh) || GH=
GIT=$(resolve_bin git /usr/bin/git /opt/homebrew/bin/git) || GIT=
GREP=$(resolve_bin grep /usr/bin/grep /bin/grep) || GREP=
HEAD=$(resolve_bin head /usr/bin/head /bin/head) || HEAD=
CAT=$(resolve_bin cat /usr/bin/cat /bin/cat) || CAT=

[ -n "$ORCA" ] || { echo "orca not found on PATH or any candidate location"; exit 1; }
[ -n "$GH" ] || { echo "gh not found"; exit 1; }
[ -n "$GIT" ] && [ -n "$GREP" ] && [ -n "$HEAD" ] && [ -n "$CAT" ] || { echo "missing coreutils"; exit 1; }

GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)   # normalized — --git-common-dir
                                                                   # can print a RELATIVE ".git"
MAIN_ROOT=$(dirname "$GIT_COMMON")                                # main checkout. Orca's worktrees
                                                                   # do NOT live under it — see
                                                                   # references/workspace-driver.md §5
BINS="$GIT_COMMON/claude/bins.env"
mkdir -p "$(dirname "$BINS")"
{
  echo "ORCA=$ORCA"; echo "AGENT_KIND='$AGENT_KIND'"; echo "AGENT_BIN='$AGENT_BIN'"
  echo "AGENT_LAUNCH_FLAGS='$AGENT_LAUNCH_FLAGS'"; echo "AGENT_PROMPT_PREFIX='$AGENT_PROMPT_PREFIX'"
  echo "GH=$GH"; echo "GIT=$GIT"; echo "GREP=$GREP"; echo "HEAD=$HEAD"; echo "CAT=$CAT"
} > "$BINS"
```

**Every subsequent Bash call in this skill starts with:**

```sh
GIT_COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
MAIN_ROOT="$(dirname "$GIT_COMMON")"
BINS="$GIT_COMMON/claude/bins.env"
. "$BINS"
```

Use `"$ORCA"`, `"$AGENT_BIN"`, `"$GH"`, `"$GIT"`, `"$GREP"`, `"$HEAD"`, `"$CAT"` (never bare names) in every command — including within this same call, since `.` (source) does not export the values as bare command names, just as shell variables.

### Long snippets run as a temp file under `bash`

Any snippet longer than ~5 lines is written to a temp file and run as `bash "$f"`, which normalizes semantics regardless of the user's login shell (this machine's is zsh, but the pattern must not assume that). Inline one-liners stay POSIX `sh` and need no such wrapping.

### CWD persistence — never `cd` in this skill

The Bash tool's working directory persists across calls. A `cd .worktrees/review-XXXX` in one call leaks into the next and any relative path then resolves to a nested location. **Never `cd` in this skill.** Always use absolute paths. To run something inside the worktree, use `git -C "$abs_worktree" ...` or `( cd "$abs_worktree" && ... )` in a subshell so it does not leak.


## Orca CLI surface

The full primitive table, selector grammar and verified behavior live in
`references/workspace-driver.md`. Never guess a flag: `"$ORCA" agent-context --json` prints the
machine-readable schema for every command, and `"$ORCA" skills get orca-cli` prints the
version-matched guide. Both ship with the installed app, so they describe the CLI actually present.

## Workflow

### Step 1: Preflight

Resolve the binaries per the block above, then confirm the runtime and this repo's Orca id:

```sh
. "$BINS"
"$ORCA" status
"$ORCA" repo list --json
```

Use `status` in its **text** form here. `runtimeReachable` is a flat key only in that output; the
JSON nests it as `result.runtime.reachable`, so grepping the text key against `--json` reports
every reachable runtime as unreachable. `repo list` still uses `--json`, where the shape is stable.

`status` must report `runtimeReachable: true` and `graphState: ready`. If it does not, offer
`"$ORCA" open` rather than aborting. Match `$MAIN_ROOT` in `repo list --json` to get `REPO_ID`, and
offer `"$ORCA" repo add` once if no row matches. Never proceed with an empty `REPO_ID`.

### Step 2: Resolve PR → branch + label

```sh
. "$BINS"
"$GH" pr view "$PR" --json number,headRefName,headRepository,headRepositoryOwner,title,url,body
```

Keep `headRefName` as `HEAD_REF` and the PR title for the label. A cross-repo (fork) PR is
identified by `headRepositoryOwner.login` differing from this repo's owner: its head branch does
not exist on this remote and phase 4 fetches it explicitly.

For a bare branch argument, skip `gh` and use the branch name as `HEAD_REF`.

### Step 3: Extract the work-item ref

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
the review on a missing ref. The spawned agent fetches the work item itself via the Linear MCP
`get_issue` inside the worktree, so a large multi-line description never has to travel through the
launch prompt; this skill only passes the ref.


### Step 4: Create the worktree and check out the PR head

`--base-branch` **cuts a new branch from** the ref; it does not check it out. Create, then check out
the real head — Orca reads git and follows, so `worktree show` reports the branch you checked out.

```sh
. "$BINS"
"$ORCA" worktree create --repo "id:$REPO_ID" --name "review-$PR" \
  --base-branch "$HEAD_REF" --agent claude \
  --prompt "$AGENT_PROMPT_PREFIX $PR${REF:+ $REF}" --no-parent --json
# keep result.worktree.path as WT_PATH, result.worktree.branch as ORCA_BRANCH (the throwaway
# branch Orca created), and result.agentTerminalHandle as H
"$GIT" -C "$WT_PATH" checkout "$HEAD_REF"
```

`${REF:+ $REF}` expands to ` <REF>` when a ref resolved and to nothing when it did not, so
`juel:review-pr` resolves its own ref rather than blocking.

**Cross-repo fork.** The head branch is not on this remote, so fetch it into a local branch first:

```sh
. "$BINS"
"$GIT" -C "$WT_PATH" fetch "$FORK_REMOTE_URL" "$HEAD_REF:$LOCAL_REVIEW_BRANCH"
"$GIT" -C "$WT_PATH" checkout "$LOCAL_REVIEW_BRANCH"
```

Keep `ORCA_BRANCH` regardless of which path ran: phase 8's teardown note needs it.

### Step 5: Provision the checkout

```sh
. "$BINS"
copy_untracked "$MAIN_ROOT" "$WT_PATH"
for f in $COPIED; do [ -e "$WT_PATH/$f" ] || echo "MISSING AFTER COPY: $f"; done
```

`copy_untracked` is the helper from `references/resolution.md` §4. Orca's repo setup hook may be
empty (`hookSettings.scripts.setup: ""`), in which case `--setup run` copies nothing and this step
is the only thing that puts `.env`, `.npmrc` and `.claude/` in the new checkout.

### Step 6: Clear the first-run dialogs

A spawn into a never-trusted path stops on the folder-trust dialog and then the bypass-permissions
dialog. **Both default to `No, exit`, so a blind Enter kills the session:** move the selection down
first. Once a location is trusted this loop matches nothing and exits immediately.

```sh
. "$BINS"
i=0
while [ "$i" -lt 3 ]; do
  screen=$("$ORCA" terminal read --terminal "$H" --screen --json)
  printf '%s' "$screen" | "$GREP" -q 'No, exit' || break
  "$ORCA" terminal send --terminal "$H" --text "$(printf '\033[B')"
  "$ORCA" terminal send --terminal "$H" --enter
  i=$((i + 1))
done
```

If a dialog is still present after 3 rounds, report the screen and stop. Never guess further
keystrokes. This is the only screen matching in this skill, and it self-disables once the location
is trusted.

### Step 7: Open the install tab

Only when `INSTALL_CMD` resolved, per the tiers in `references/resolution.md` §2. It must be a
**new** tab: typing into the agent's tab would feed the command to the agent as a prompt.

```sh
. "$BINS"
"$ORCA" terminal create --worktree "id:$REPO_ID::$WT_PATH" --title INSTALL \
  --command "$INSTALL_CMD" --json
```

If nothing resolved, skip this step and say so in one line.

### Step 8: Link the work item and report

```sh
. "$BINS"
"$ORCA" worktree set --worktree "id:$REPO_ID::$WT_PATH" --linear-issue "$REF" --json
```

Only when a ref resolved. The link works even when Orca's Linear is disconnected.

Report the PR, the work item (or "no ref"), the worktree path, the checked-out branch, the terminal
handle, and whether the install tab opened. Include this teardown warning verbatim:

> Before removing this worktree, check out its throwaway branch first:
> `git -C <path> checkout <orca-created-branch>` then `orca worktree rm --worktree <sel> --force`.
> `worktree rm` attempts to delete the checked-out local branch with or without `--force`, so
> removing it while the PR head is checked out deletes your local copy of that branch.

### On session ids

`juel:cmux-review-pr` computes a deterministic `--session-id` from the PR id so the session can be
resumed by name. There is no argv seam for that under `--agent`: Orca's launcher owns the command
line. This skill therefore does not compute one. Identify the workspace by `name:review-<PR#>` or
by `branch:<HEAD_REF>` instead — both are first-class selectors.

## Common mistakes

- **Assuming `--base-branch` checks out the branch.** It cuts a new branch from it. Step 4's
  explicit checkout is what puts the worktree on the real PR head.
- **Removing the worktree while the PR branch is checked out.** `worktree rm` deletes the
  checked-out local branch with or without `--force`. Move to `ORCA_BRANCH` first.
- **Sending Enter into an unanswered dialog.** Both first-run dialogs default to `No, exit`.
- **Assuming `<repo>/.worktrees/`.** Orca checks out to `~/orca/workspaces/<repo>/<name>`. Take
  every path from `result.worktree.path`.
- **Expecting `--setup run` to copy `.env`.** A repo whose setup hook is empty copies nothing.
- **Reusing a stale handle.** `terminal_handle_stale` means reacquire via `terminal list`.
- **Blocking on a missing ref.** The review proceeds ungraded; note "no ref" and continue.

## Edge cases

| Situation | Handling |
|---|---|
| `orca status` reports the runtime unreachable | Offer `orca open`, then re-run preflight. Never spawn against an unreachable runtime. |
| This repo is not in `orca repo list` | Offer `orca repo add` once. If declined, STOP. |
| Cross-repo (fork) PR | Fetch the fork ref into a local branch, then check that out. The head branch does not exist on this remote. |
| A `review-<PR#>` worktree already exists | Report it and reuse it rather than creating a second checkout for the same PR. |
| No work-item ref resolves | Proceed ungraded, note "no ref" in the report, and pass no ref to `juel:review-pr`. |
| A dialog is still present after 3 gauntlet rounds | Report the captured screen and stop. |
| No install command resolves | Skip phase 7 with a one-line note. |
| The PR head branch is already checked out in another worktree | git refuses the checkout. Report it and stop rather than forcing; the other worktree is someone's live work. |

## QA checklist

1. The worktree sits on the real PR head branch, confirmed by `worktree show` or `git -C <path> rev-parse --abbrev-ref HEAD`.
2. The throwaway branch Orca created was recorded, so teardown can move off the PR head safely.
3. `copy_untracked` ran and the verification loop reported no missing files.
4. No session was left sitting on an unanswered first-run dialog.
5. The queued prompt carries the PR number, and the ref when one resolved.
6. The report includes the teardown warning verbatim.
