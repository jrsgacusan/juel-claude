---
name: orca-ship-tickets
description: Use when starting your workday in Orca to ship multiple work items in parallel. Selects items through the work-source layer, then creates one Orca worktree per item with the resolved agent already running `/juel:ship-ticket`. Fire and forget - it does not monitor the spawned sessions. Triggers "ship my tickets in orca", "start my day in orca", "/juel:orca-ship-tickets".
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: phase 2 fetches Todo work items and sets them in_progress, when Linear resolves as the provider
        check: none
        fallback: selection degrades through the work-source layer's own provider fallback; worktrees still spawn for whatever refs resolve
    cli:
      - id: orca
        hard: true
        why: phases 1 and 3 resolve the runtime and create one worktree per item
        check: "resolve_bin orca against PATH, then the app-bundle candidate"
      - id: claude
        hard: true
        why: phase 3 launches the selected agent inside each worktree
        check: "resolve_agent from rule 0"
      - id: git
        hard: true
        why: phase 4 renames the Orca-created branch to the repo's own convention
        check: "resolve_bin git"
      - id: coreutils
        hard: true
        why: grep/head/cat are resolved once per session via resolve_bin and sourced from BINS every call, since each Bash call is an independent non-login shell
        check: "resolve_bin per binary against PATH, then /usr/bin,/bin candidates"
      - id: resolved-install-command
        hard: false
        why: phase 6 warms deps in a second tab while the agent works in the first
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
      - id: work-source-list-capable
        hard: false
        why: phase 2 lists the user's open items
        check: none
        fallback: ask for refs directly, one per line
    skills:
      - id: juel:ship-ticket
        hard: true
        why: it is the command each spawned session runs
---

# Juel Orca Ship Tickets

Spawn one Orca worktree per work item, each with the resolved agent already running
`/juel:ship-ticket <REF>`. Orca creates the checkout, launches the agent and delivers the prompt
in a single call, so there is no readiness polling and no separate Enter keystroke.

This skill is **fire and forget**: once the worktrees are up it reports and stops. It does not
monitor the spawned sessions, relay approvals, or wait for them to finish.

**Announce:** "Using juel:orca-ship-tickets to spawn one Orca worktree per item."

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
| git | cli | HARD | `resolve_bin git` | STOP |
| coreutils | cli | HARD | `resolve_bin` per binary (grep/head/cat) against PATH, then `/usr/bin`,`/bin` candidates | STOP |
| git repo | context | HARD | `git rev-parse --git-dir` | STOP |
| reachable Orca runtime | context | HARD | `orca status` reports `runtimeReachable: true` and `graphState: ready` | STOP → run `orca open`, then re-run |
| repo registered with Orca | context | HARD | `orca repo list` contains this repo's path | offer `orca repo add` once, then continue |
| juel:ship-ticket | skill | HARD | ships with this plugin | STOP |
| Linear MCP | mcp | SOFT | **none — render as `?`** | selection degrades through the work-source layer's own provider fallback; worktrees still spawn for whatever refs resolve |
| work item list capability | context | SOFT | **none — render as `?`** | ask for refs directly, one per line |
| resolved install command | cli | SOFT | see resolution layer | skip the second tab; install deps yourself |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Preflight — resolve binaries via resolve_bin, persist to BINS, confirm the Orca runtime and this repo's Orca id
2. Select work items through the work-source layer and confirm the list
3. Create one Orca worktree per item with the agent and prompt in the same call
4. Rename each branch to the repo convention and copy untracked files into the new checkout
5. Clear the first-run trust and bypass dialogs, if any are present
6. Open the install tab in each worktree when an install command resolved
7. Set the board status and report every worktree, branch and handle
8. Verify the QA checklist

## Prerequisites

- Orca installed and its CLI registered (Settings → General → Orca CLI), resolved via `resolve_bin` (PATH first, then the app-bundle path as a labelled candidate, never as the sole source).
- The Orca app running, with a reachable runtime. `orca open` starts it and waits.
- This repo registered with Orca. `orca repo add` registers it.
- The selected agent CLI installed and resolved through `resolve_agent`.
- Inside a git repo, with a work source resolved (Linear/Jira/GitHub/file) or refs supplied directly.

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
GIT=$(resolve_bin git /usr/bin/git /opt/homebrew/bin/git) || GIT=
GREP=$(resolve_bin grep /usr/bin/grep /bin/grep) || GREP=
HEAD=$(resolve_bin head /usr/bin/head /bin/head) || HEAD=
CAT=$(resolve_bin cat /usr/bin/cat /bin/cat) || CAT=

[ -n "$ORCA" ] || { echo "orca not found on PATH or any candidate location"; exit 1; }
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
  echo "GIT=$GIT"; echo "GREP=$GREP"; echo "HEAD=$HEAD"; echo "CAT=$CAT"
} > "$BINS"
```

**Every subsequent Bash call in this skill starts with:**

```sh
GIT_COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
MAIN_ROOT="$(dirname "$GIT_COMMON")"
BINS="$GIT_COMMON/claude/bins.env"
. "$BINS"
```

Use `"$ORCA"`, `"$AGENT_BIN"`, `"$GIT"`, `"$GREP"`, `"$HEAD"`, `"$CAT"` (never bare names) in every command — including within this same call, since `.` (source) does not export the values as bare command names, just as shell variables.

### Long snippets run as a temp file under `bash`

Any snippet longer than ~5 lines is written to a temp file and run as `bash "$f"`, which normalizes semantics regardless of the user's login shell (this machine's is zsh, but the pattern must not assume that). Inline one-liners stay POSIX `sh` and need no such wrapping.

### CWD persistence — never `cd` in this skill

The Bash tool's working directory persists across calls. A `cd .worktrees/savi-XXXX` in one call leaks into the next call and any relative path (e.g. `.worktrees/savi-XXXX`) then resolves to a nested location. **Never `cd` in this skill.** Always use absolute paths for everything. If you must operate in a worktree, use the absolute path directly.

### Ref/dir iteration — do not word-split, do not pack tokens

Word-splitting behavior differs across shells (zsh does not field-split unquoted variables the way bash and POSIX `sh` do), and this previously broke a run under zsh: a loop written `for pair in $refs` (where `refs` was a space-joined string `"SAVI-1287:savi-1287 SAVI-1312:savi-1312 ..."`) executed **once** with `pair` bound to the _entire_ string, and `${pair%%:*}` / `${pair##*:}` then produced the first item's ref paired with the **last** item's dir — so a workspace was created in the wrong worktree and renamed to the wrong item.

**The fix is not shell-specific arrays (zsh arrays don't exist in `sh`/`bash`) — it's a form that never needed word-splitting in the first place.** Build the ref/dir pairs as a here-doc, one `REF|dir` pair per line, and read them with `while IFS='|' read -r`, which behaves identically in `sh`, `bash` and `zsh`:

```bash
while IFS='|' read -r ref dir; do
  [ -n "$ref" ] || continue
  path="$MAIN_ROOT/.worktrees/$dir"
  printf 'ref=%s path=%s\n' "$ref" "$path"
  # ... spawn workspace for $ref at $path ...
done <<'EOF'
SAVI-1287|savi-1287
SAVI-1312|savi-1312
SAVI-1282|savi-1282
SAVI-1277|savi-1277
EOF
```

If a step instead needs a plain counted loop (no per-item data), use `for i in $(seq 1 "$n")`, never zsh's `{1..$n}` brace-expansion form — `seq` is portable, brace ranges with a variable bound are a zsh/bash-only extension `sh` does not expand.

Rules — this is the most important guidance in this file and is entirely shell-independent, only the mechanics above changed:

- Build the ref/dir list as literal `REF|dir` here-doc lines, never a space-joined string you later split.
- Each line already keeps ref and dir **paired atomically** — there is no separate "parallel array" to drift out of sync, and no `ref:dir` token to mis-split with `%%`/`##` (the classic bug this section exists to prevent: packing two values into one token and re-splitting it is fragile regardless of shell — the here-doc's `|`-delimited fields sidestep that entirely).
- After computing `path`, echo it next to `$ref` and **eyeball that they match** before calling `new-workspace` — a mismatch here means a workspace lands in the wrong worktree.
- If a workspace does get created with the wrong cwd/name, `close-workspace --workspace workspace:<N>` it and recreate, rather than trying to repoint it.


### Resolve the install command — once, before spawning any worktree

Resolve `INSTALL_CMD` once, per the tiers in `references/resolution.md` §2: project-authored task
runners first (`Makefile`, `justfile`, `Taskfile.yml`, `mise.toml` — only for targets that exist),
then language manifests (`package.json` + lockfile, `pyproject.toml`, `Cargo.toml`, `go.mod`, …),
then `.github/workflows/*.yml` `run:` steps as a suggestion confirmed with the user, never run
blind. `install` is the one key that needs no script to exist, since it is a package-manager
primitive.

If nothing resolves and verifies, `INSTALL_CMD` stays empty and **phase 6 is skipped with a
one-line note**. Never invent `npm install` for a repo with no manifest.

## Orca CLI surface

The full primitive table, selector grammar and verified behavior live in
`references/workspace-driver.md`. Never guess a flag: `"$ORCA" agent-context --json` prints the
machine-readable schema for every command, and `"$ORCA" skills get orca-cli` prints the
version-matched guide. Both ship with the installed app, so they describe the CLI actually present.

## Workflow

### Step 1: Preflight

Resolve the binaries per the block above, then confirm the runtime and this repo's Orca id in one
call:

```sh
. "$BINS"
"$ORCA" status --json
"$ORCA" repo list --json
```

`status` must report `runtimeReachable: true` and `graphState: ready`. If it does not, offer
`"$ORCA" open` — which launches Orca and waits for the runtime — rather than aborting.

From `repo list --json`, match this repo's absolute path (`$MAIN_ROOT`) to its `id` and keep it as
`REPO_ID`. If no row matches, offer `"$ORCA" repo add` **once**, then continue. Never proceed with
an empty `REPO_ID`: `worktree create` would infer a repo from the caller's context and can land the
checkout against the wrong project.

### Step 2: Select the work items

Resolve the provider and fetch this user's open items per `references/work-source.md`, present them
for confirmation, and flip the confirmed ones to in-progress. Branch names come from
`branchPattern` per `references/resolution.md`.

**Do not invoke `juel:daily-worktrees` here.** Its Step 7 creates worktrees under
`<repo>/.worktrees/<ref>` and its strict protocol forbids skipping a phase, so calling it would
race Orca for worktree creation and leave orphan checkouts behind. This skill reuses the same
work-source layer that skill resolves through, which gets the selection without the directory side
effect and without modifying a skill the cmux flow still depends on.

If no provider resolves, ask for refs directly, one per line, and continue.

### Step 3: Create one worktree per item

The whole spawn is one call per item. `--agent` launches the agent in the worktree's **first**
terminal and `--prompt` delivers the work once its TUI is ready, so there is no readiness poll and
no Enter keystroke.

```sh
. "$BINS"
"$ORCA" worktree create --repo "id:$REPO_ID" --name "$REF" --linear-issue "$REF" \
  --agent claude --prompt "$AGENT_PROMPT_PREFIX $REF" --no-parent --json
```

From the response keep, per item:

- `result.worktree.path` — the checkout, under `~/orca/workspaces/<repo>/<name>`
- `result.worktree.branch` — Orca's own name for it, `<repo.gitUsername>/<REF>`
- `result.agentTerminalHandle` — the agent's terminal, or `result.startupTerminal.handle` on older
  runtimes. A handle that later returns `terminal_handle_stale` is reacquired with
  `"$ORCA" terminal list --worktree <sel> --json`; never dual-send to the old and new handles.

`--linear-issue` links the item even when Orca's Linear is disconnected, and the link comes back as
`linkedLinearIssue`. Pass the bare ref; a full issue URL works too.

**When the repo's untracked set is non-empty, do not use `--agent` here.** The agent must not start
before phase 4's copy lands. Create bare, run phase 4, then start the agent yourself:

```sh
"$ORCA" worktree create --repo "id:$REPO_ID" --name "$REF" --linear-issue "$REF" --no-parent --json
# ... phase 4 for this worktree ...
"$ORCA" terminal create --worktree "id:$REPO_ID::$WT_PATH" \
  --command "$AGENT_BIN $AGENT_LAUNCH_FLAGS" --json
"$ORCA" terminal send --terminal "$H" --text "$AGENT_PROMPT_PREFIX $REF" --enter
```

### Step 4: Rename the branch, then provision the checkout

Orca names the branch `<repo.gitUsername>/<name>` and no flag overrides it. Rename it to the repo's
own convention; Orca reads git and follows.

```sh
. "$BINS"
"$GIT" -C "$WT_PATH" branch -m "$BRANCH_FROM_BRANCHPATTERN"
copy_untracked "$MAIN_ROOT" "$WT_PATH"
# Verify, then report what landed. A missing .env surfaces as a failing agent
# run minutes later, in a session nobody is watching, so silence here is the
# expensive failure. List the copied files in the phase 7 report.
for f in $COPIED; do [ -e "$WT_PATH/$f" ] || echo "MISSING AFTER COPY: $f"; done
```

`copy_untracked` is the helper from `references/resolution.md` §4. Orca's repo setup hook may be
empty (`hookSettings.scripts.setup: ""`), in which case `--setup run` copies nothing and this step
is the only thing that puts `.env`, `.npmrc` and `.claude/` in the new checkout.

### Step 5: Clear the first-run dialogs

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

### Step 6: Open the install tab

Only when `INSTALL_CMD` is non-empty. It must be a **new** tab: typing into the agent's tab would
feed the command to the agent as a prompt, not to a shell.

```sh
. "$BINS"
"$ORCA" terminal create --worktree "id:$REPO_ID::$WT_PATH" --title INSTALL \
  --command "$INSTALL_CMD" --json
```

If nothing resolved, skip this step entirely and say so in one line. Do not open a tab that runs
nothing.

### Step 7: Set the board status and report

```sh
. "$BINS"
"$ORCA" worktree set --worktree "id:$REPO_ID::$WT_PATH" \
  --workspace-status in-progress --comment "$ITEM_TITLE" --json
```

Then report one row per item: ref, worktree path, branch, terminal handle, whether the install tab
opened, and what phase 4 copied. Close with an explicit statement that nothing is being monitored,
and that the sessions are reached in the Orca app or via `"$ORCA" terminal read`.

## Common mistakes

- **Sending Enter into an unanswered dialog.** Both first-run dialogs default to `No, exit`. A bare
  `--enter` kills the session before the prompt is ever seen.
- **Assuming `<repo>/.worktrees/<ref>`.** Orca checks out to `~/orca/workspaces/<repo>/<name>`.
  Every path in this skill comes from `result.worktree.path`, never from string-building against
  `$MAIN_ROOT`.
- **Assuming the branch you asked for.** Orca prefixes it with `repo.gitUsername`. Phase 4's rename
  is what restores the repo convention.
- **Expecting `--setup run` to copy `.env`.** A repo whose `hookSettings.scripts.setup` is empty
  copies nothing. Phase 4 is the mechanism, not the hook.
- **Reusing a stale handle.** `terminal_handle_stale` means reacquire via `terminal list`, not
  retry the old handle, and never send to both.
- **Blank or malformed selectors.** Build every selector as `id:<repoId>::<path>` from the create
  response. `repoId` alone identifies only the repo, never a worktree.
- **Invoking `juel:daily-worktrees`.** See phase 2: it would create a second, competing checkout.

## Edge cases

| Situation | Handling |
|---|---|
| `orca status` reports the runtime unreachable | Offer `orca open`, which launches Orca and waits. Re-run preflight after. Never spawn against an unreachable runtime. |
| This repo is not in `orca repo list` | Offer `orca repo add` once. If declined, STOP: `worktree create` without a resolved repo id can land against the wrong project. |
| A worktree already exists for a ref | Report it and skip that ref. Do not create a second checkout for the same item. |
| The agent handle is missing from the create response | Reacquire with `terminal list --worktree <sel> --json` before sending anything. |
| A dialog is still present after 3 gauntlet rounds | Report the captured screen and stop. Never guess further keystrokes. |
| No install command resolves | Skip phase 6 with a one-line note. Never invent one. |
| Orca's Linear is disconnected | Selection already runs through the work-source layer, so nothing changes. `--linear-issue` still links the ref offline. |
| A spawned session needs teardown | `orca worktree rm --worktree <sel> --force` also deletes the checked-out local branch. Move off any branch you want to keep first. |

## QA checklist

1. Every spawned worktree's path came from `result.worktree.path`, not from string-building.
2. Every branch was renamed to the resolved `branchPattern`, and `worktree show` reflects it.
3. `copy_untracked` ran for every worktree, and the verification loop reported no missing files.
4. No session was left sitting on an unanswered first-run dialog.
5. The install tab is a separate tab from the agent's, or was skipped with a note.
6. Every worktree carries its board status and its item title as the comment.
7. The report states plainly that nothing is being monitored.
