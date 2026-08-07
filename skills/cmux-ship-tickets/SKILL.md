---
name: cmux-ship-tickets
description: Use when starting your workday in CMUX to ship multiple Linear tickets in parallel. Wraps juel:daily-worktrees + per-item CMUX workspace creation + auto-launch of `claude` running `/juel:ship-ticket`. Triggers "ship my tickets", "start my day", "/juel:cmux-ship-tickets".
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: phase 2 (via juel:daily-worktrees) fetches Todo work items and sets them in_progress, when Linear resolves as the provider
        check: none
        fallback: phase 2 relies on juel:daily-worktrees' own provider fallback / no-list handling — CMUX workspaces still spawn for whatever refs it resolves
    cli:
      - id: cmux
        hard: true
        why: phase 4 creates one workspace per selected work item
        check: "resolve_bin cmux against PATH, then GUI/Homebrew candidates"
      - id: claude
        hard: true
        why: phase 4 launches claude inside each workspace
        check: "resolve_bin claude against PATH, then GUI/Homebrew candidates"
      - id: coreutils
        hard: true
        why: sleep/grep/head/cat are resolved once per session via resolve_bin and sourced from BINS every call, since each Bash call is an independent non-login shell
        check: "resolve_bin per binary against PATH, then /usr/bin,/bin candidates"
      - id: resolved-install-command
        hard: false
        why: phase 7 warms deps in a second tab while claude works in the first
        check: "see resolution layer"
        fallback: skip the second surface; install deps yourself
    context:
      - id: git-repo
        hard: true
        why: worktrees are created under <repo-root>/.worktrees
        check: "git rev-parse --show-toplevel"
    skills:
      - id: juel:daily-worktrees
        hard: true
        why: phase 2 creates/reuses the worktrees this skill spawns workspaces into
      - id: juel:ship-ticket
        hard: true
        why: queued as the startup prompt inside every spawned workspace
    perms:
      - id: permission-mode-auto
        hard: true
        why: spawned sessions must not stall on the first tool prompt — nobody is watching a spawned CMUX session to answer it
---

# Juel CMUX Ship Tickets

End-to-end daily kickoff: fetch open work items from the resolved work source, create git worktrees, spawn one CMUX workspace per item, start `claude` in each with `/juel:ship-ticket <REF>` queued, and kick off the resolved install command in a second tab so deps install in parallel (skipped entirely for a repo where nothing resolves).

**Announce:** "Using juel:cmux-ship-tickets to spin up worktrees + CMUX workspaces + claude sessions."

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v3 -->

**1. Preflight, then task list, before anything else.** Before any other output and before any tool call, emit the Preflight block (below). If the preflight verdict is STOP, print the preflight block and **stop** — do not create tasks and do not begin work. Otherwise, before any other work, create one task per phase in this skill's `## Phases` list via `TaskCreate` — `subject` is the phase name, `activeForm` is its present-continuous form. This task list, rendered persistently by the harness, IS the checklist; nothing else satisfies this rule. This is not optional on re-invocation, on resume, or when the user says "just do it".

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
- Passing any of this into another session (a CMUX prompt, a nested `claude`) carries these rules with it — say so explicitly in that prompt string.

**5. Confirmation gates stack; they do not replace this.** Where this skill pauses between phases, the checklist report comes first, then the "Proceed to phase N+1?" question. A user's "yes" advances exactly one phase — it never authorizes skipping ahead or batching the remainder.

## Preflight

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| cmux | cli | HARD | `resolve_bin cmux` against PATH, then GUI/Homebrew candidates | STOP → https://github.com/manaflow-ai/cmux |
| claude | cli | HARD | `resolve_bin claude` against PATH, then GUI/Homebrew candidates | STOP → install the Claude Code CLI |
| coreutils | cli | HARD | `resolve_bin` per binary (sleep/grep/head/cat) against PATH, then `/usr/bin`,`/bin` candidates | STOP |
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP |
| juel:daily-worktrees, juel:ship-ticket | skill | HARD | ship with this plugin | STOP |
| Linear MCP | mcp | SOFT | **none — render as `?`** | phase 2 relies on juel:daily-worktrees' own provider fallback / no-list handling — CMUX workspaces still spawn for whatever refs it resolves |
| resolved install command | cli | SOFT | see resolution layer | skip the second surface; install deps yourself |
| `--permission-mode auto` | perm | HARD | none — render as `?` | STOP → tell the user the account is not entitled to `--permission-mode auto`; never spawn a session nobody is watching on a lesser mode |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Preflight — resolve every binary via resolve_bin, persist to BINS
2. Run juel:daily-worktrees, declining its planning offer
3. Confirm the CMUX launch with the user
4. Per item: create the workspace and launch claude
5. Per item: guard the workspace id, rename it, set the status pill
6. Per item: wait for the TUI, send /juel:ship-ticket <REF> + Enter
7. Per item: open the second surface and start the resolved install command
8. Report the item → worktree → workspace table
9. Verify the QA checklist

## Prerequisites

- `cmux` CLI installed — resolved via `resolve_bin` (PATH first, then the GUI install at `/Applications/cmux.app/Contents/Resources/bin/cmux` and Homebrew paths as candidates, not the sole fallback). If nothing resolves, abort with install hint.
- `claude` CLI installed (same `resolve_bin` rule; GUI path and Homebrew paths are candidates).
- Inside a git repo with `juel:daily-worktrees` skill available.
- A work source resolved (Linear/Jira/GitHub/file) — `juel:daily-worktrees` handles provider
  fallback if none resolves.

### Resolve binaries once, persist, then source every call

Each Bash tool call is an **independent non-login shell** — the real reason a binary resolved in call N is unavailable in call N+1 is not "PATH drops"; it's that shell variables and function definitions from call N simply do not exist in call N+1. Resolve every binary once via `resolve_bin` (PATH first, then labelled candidates — never a hardcoded absolute path as the sole source), persist the resolved paths to `$GIT_COMMON/claude/bins.env`, and source that file at the top of every later call instead of re-resolving or assuming the previous call's variables survived.

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
SLEEP=$(resolve_bin sleep /usr/bin/sleep /bin/sleep) || SLEEP=
GREP=$(resolve_bin grep /usr/bin/grep /bin/grep) || GREP=
HEAD=$(resolve_bin head /usr/bin/head /bin/head) || HEAD=
CAT=$(resolve_bin cat /usr/bin/cat /bin/cat) || CAT=

[ -n "$CMUX" ] || { echo "cmux not found on PATH or any candidate location"; exit 1; }
[ -n "$CLAUDE_BIN" ] || { echo "claude not found on PATH or any candidate location"; exit 1; }
[ -n "$SLEEP" ] && [ -n "$GREP" ] && [ -n "$HEAD" ] && [ -n "$CAT" ] || { echo "missing coreutils"; exit 1; }

GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)   # normalized — --git-common-dir
                                                                   # can print a RELATIVE ".git"
MAIN_ROOT=$(dirname "$GIT_COMMON")                                # main checkout — worktrees live
                                                                   # under $MAIN_ROOT/.worktrees,
                                                                   # same convention juel:daily-worktrees
                                                                   # uses in its Step 7 "Roots" section
BINS="$GIT_COMMON/claude/bins.env"
mkdir -p "$(dirname "$BINS")"
{
  echo "CMUX=$CMUX"; echo "CLAUDE_BIN=$CLAUDE_BIN"
  echo "SLEEP=$SLEEP"; echo "GREP=$GREP"; echo "HEAD=$HEAD"; echo "CAT=$CAT"
} > "$BINS"
```

**Every subsequent Bash call in this skill starts with:**

```sh
GIT_COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
MAIN_ROOT="$(dirname "$GIT_COMMON")"
BINS="$GIT_COMMON/claude/bins.env"
. "$BINS"
```

(`MAIN_ROOT` is cheap to recompute — two `git`/`dirname` calls — so it is rederived fresh every call rather than persisted to `$BINS`; only the `resolve_bin` candidate search, which is the expensive/fragile part, is persisted.)

(`BINS` itself is a shell variable and does not survive either — recompute the path fresh, then source. Recomputing the path is cheap; re-running the `resolve_bin` candidate search every call is what this pattern avoids.) Use `"$CMUX"`, `"$CLAUDE_BIN"`, `"$SLEEP"`, `"$GREP"`, `"$HEAD"`, `"$CAT"` (never bare names) in every command — including within this same call, since `.` (source) does not export the values as bare command names, just as shell variables.

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

### Resolve the install command — once, before spawning any workspace

This is the "resolution layer" the Preflight table's `resolved-install-command` row points at.
Resolve `commands.install` **once**, from the main repo root (`$MAIN_ROOT`, derived the same way
`juel:daily-worktrees` derives it in its Step 7 "Roots" section), **before** the per-item loop in
Step 3 — every item's worktree is a
checkout of the same repo, so re-detecting per item is wasted work and risks a different answer
for the same repo mid-run.

Probed in tiers, stopping at the first verified hit — never invent a command if nothing resolves:

- **Tier A — project-authored task runners** (highest priority): `Makefile`, `justfile`,
  `Taskfile.yml`, `mise.toml`. Emit `make install` / `just install` / `task install` / `mise run
  install` only if that target actually exists.
- **Tier B — language manifests:** `package.json` (+ lockfile → package manager: `package-lock.json`
  →npm, `yarn.lock`→yarn, `pnpm-lock.yaml`→pnpm, `bun.lockb`→bun) → `<pm> install`; `pyproject.toml`
  (+ `uv.lock`→`uv sync`, `poetry.lock`→`poetry install`); `Cargo.toml`→`cargo fetch`;
  `go.mod`→`go mod download`; `mix.exs`→`mix deps.get`; `Gemfile`→`bundle install`; Gradle/Maven
  →`./gradlew build` / `mvn install -DskipTests`; `composer.json`→`composer install`;
  `*.csproj`→`dotnet restore`.
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
INSTALL_CMD=""   # resolved once here; every item's Step 3.6 below reuses this exact value
# ... detection per the tiers above against "$MAIN_ROOT", assigning INSTALL_CMD on the first
# verified hit; stays empty if nothing resolves and verifies ...
```

**If nothing resolves, `INSTALL_CMD` stays empty — that is not an error.** Step 3.6 below skips the
second surface entirely for every item rather than opening a tab that runs nothing.

## CMUX CLI cheat sheet (verified against cmux 0.62.x)

| Need                                                                 | Command                                                                                                  |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Create workspace + run startup command (Enter pressed automatically) | `cmux new-workspace --cwd "$path" --command "<cmd>"`                                                     |
| Output format                                                        | Single line on stdout: `OK workspace:<N>`                                                                |
| Open a new tab (surface) in a workspace                              | `cmux new-surface --type terminal --workspace workspace:<N>`                                             |
| Send literal text (no Enter) to specific surface/tab                 | `cmux send --workspace workspace:<N> --surface surface:<M> "<text>"`                                     |
| Send literal text (no Enter)                                         | `cmux send --workspace workspace:<N> "<text>"`                                                           |
| Press Enter (or other keys)                                          | `cmux send-key --workspace workspace:<N> Enter`                                                          |
| Rename a workspace                                                   | `cmux rename-workspace --workspace workspace:<N> "<REF>"` (title is POSITIONAL — no `--name` flag) |
| Set a sidebar status pill with color                                 | `cmux set-status <key> <value> --color "<#hex>" --workspace workspace:<N>`                               |
| List all workspaces                                                  | `cmux list-workspaces`                                                                                   |
| Close a workspace                                                    | `cmux close-workspace --workspace workspace:<N>`                                                         |

Anti-patterns confirmed broken:

- ❌ `cmux new-workspace --json` (flag does not exist)
- ❌ `cmux send-surface ...` (subcommand does not exist)
- ❌ Embedding `\n` in `cmux send` text to press Enter (sends literal backslash-n)
- ❌ Calling `cmux rename-workspace --workspace ""` — silently targets the currently-selected workspace (will rename whatever the user is looking at, including the orchestrator session itself)
- ❌ `cmux rename-workspace --workspace workspace:<N> --name "<title>"` — there is NO `--name` flag. The title is a positional arg. Passing `--name "MSTR-3034"` literally renames the workspace to the string `--name MSTR-3034`.

## Workflow

### Step 1: Run juel:daily-worktrees

Invoke the `juel:daily-worktrees` skill. Let the user pick work items and let it create worktrees, copy env files, set status to in_progress through whichever work source resolved.

**Stop at its Step 8 "Offer Planning" prompt and decline planning** (planning happens via `/juel:ship-ticket` inside each CMUX workspace).

Collect the list of newly-created or reused worktrees with absolute paths and refs:

```
[
  { "ref": "SAVI-1234", "path": "/abs/path/.worktrees/savi-1234" },
  ...
]
```

`ref` is never left null in this handoff — when no tracker ref was resolved, it holds the
descriptive slug used for the worktree dir instead (per `references/resolution.md` §5's
ref-optional naming table), never a placeholder like `none`/`NOREF`.

### Step 2: Confirm CMUX launch

Show the user the list and ask: "Spawn a CMUX workspace + claude session for each? [Y/n]"

If declined, stop and report worktree paths only.

### Step 3: For each item, spawn workspace

For each `{ref, path}`:

1. **Create workspace and launch claude in one call.** The `--command` flag runs the command in the new workspace's terminal and presses Enter automatically. Pass the absolute `$CLAUDE_BIN`, and start it in **auto permission mode** so the session works through `/juel:ship-ticket` without stopping at every tool prompt:

   ```bash
   raw=$("$CMUX" new-workspace --cwd "$path" --command "$CLAUDE_BIN --permission-mode auto")
   # raw looks like: "OK workspace:55"
   ws_id=$(echo "$raw" | "$GREP" -oE 'workspace:[0-9]+' | "$HEAD" -1)
   ```

   `auto` auto-approves tool calls but runs a background safety classifier that still blocks destructive actions (force push, mass deletion, `curl | bash`, production deploys) and falls back to manual prompting after repeated blocks. This is the point of the skill — an unattended session that pauses on the first `pnpm install` prompt has not shipped anything.

   If `--permission-mode auto` is rejected (older `claude` build, or the account is not entitled to auto mode), **STOP** — do not spawn the workspace, and do not fall back to `--permission-mode acceptEdits` or `bypassPermissions` / `--dangerously-skip-permissions`. Tell the user plainly that their account is not entitled to auto mode; a spawned CMUX session nobody is watching must never silently stall on a permission prompt, and these worktrees sit on the real filesystem with real credentials, not in a container.

2. **Guard: abort this item if ws_id is empty.** A blank `--workspace` arg silently targets the currently-selected workspace, which is the orchestrator running this skill — `send`/`send-key` against an empty ref will type into the user's own claude session.

   ```bash
   if [ -z "$ws_id" ]; then
     echo "WARN: failed to parse workspace id from: $raw — skipping $ref"
     continue
   fi
   ```

   If parsing fails repeatedly, fall back to `"$CMUX" list-workspaces` and take the newest entry whose `cwd` matches `$path`.

3. **Rename the workspace to the ref (non-negotiable).** CMUX defaults to the worktree dir basename (e.g. `mstr-3034`), which is fine but inconsistent with how the user thinks about their work items. Always rename to the canonical ref (e.g. `MSTR-3034`). The title is a POSITIONAL argument — there is no `--name` flag.

   ```bash
   "$CMUX" rename-workspace --workspace "$ws_id" "$ref"
   ```

   **Safety guard — re-check before this call:** `$ws_id` MUST be non-empty AND match `workspace:[0-9]+`. A blank or malformed `--workspace` value silently targets the currently-selected workspace, which is the orchestrator running this skill — you will rename the user's own claude session.

   ```bash
   case "$ws_id" in
     workspace:[0-9]*) ;;  # ok
     *) echo "REFUSE rename: bad ws_id='$ws_id'"; continue ;;
   esac
   ```

4. **Color the workspace green via a sidebar status pill.** CMUX has no "workspace tint" property, but `set-status` adds a colored pill next to the workspace in the sidebar. Use it to mark all ship-tickets workspaces green so they're visually distinguishable from ad-hoc workspaces. Use a stable key (`ship`) so re-runs overwrite the same pill rather than stacking new ones.

   ```bash
   "$CMUX" set-status ship "ready" --color "#22c55e" --workspace "$ws_id"
   ```

   Green hex: `#22c55e` (Tailwind green-500). Pick a darker/lighter shade if the user requests it, but default to green-500 for consistency.

5. **Wait for the claude TUI to be ready, then queue the slash command.** Claude's terminal UI needs several seconds to boot before it accepts keystrokes. `sleep 1` is too short.

   ```bash
   "$SLEEP" 6
   "$CMUX" send --workspace "$ws_id" "/juel:ship-ticket $ref"
   "$SLEEP" 1
   "$CMUX" send-key --workspace "$ws_id" Enter
   ```

6. **If `INSTALL_CMD` resolved (see "Resolve the install command" above), open a second tab and run it. If it did not resolve, skip this step entirely for this item** — do not open a tab that runs nothing.

   ```bash
   if [ -n "$INSTALL_CMD" ]; then
     raw2=$("$CMUX" new-surface --type terminal --workspace "$ws_id")
     surface_id=$(echo "$raw2" | "$GREP" -oE 'surface:[0-9]+' | "$HEAD" -1)
     case "$surface_id" in
       surface:[0-9]*) ;;
       *) echo "WARN: failed to parse surface id from: $raw2 — skipping install for $ref"; surface_id="" ;;
     esac
     if [ -n "$surface_id" ]; then
       "$SLEEP" 1
       "$CMUX" send --workspace "$ws_id" --surface "$surface_id" "$INSTALL_CMD"
       "$SLEEP" 1
       "$CMUX" send-key --workspace "$ws_id" --surface "$surface_id" Enter
     fi
   else
     echo "No install command resolved for this repo — skipping the second surface for $ref. Install dependencies yourself."
   fi
   ```

   **Why a second tab and not the claude tab:** typing the install command into the claude tab would feed it as a prompt to the agent, not as a shell command. The new surface is a fresh terminal in the same workspace + cwd.

   **Why not block on it:** an install command (e.g. `pnpm install`, `make install`) can take minutes. Fire-and-forget so claude can start planning in parallel.

   **Why skip the whole surface on null, not just the send:** an empty terminal tab with nothing running is noise, not a feature — the corollary to "a missing command is not an error" is that the *side effect* of a missing command (a tab) is also skipped, per item.

7. **Record the mapping** for the final report.

### Step 4: Report

Print a table:

```
Launched N CMUX workspaces:

| Ref        | Worktree                       | CMUX         |
|------------|--------------------------------|--------------|
| SAVI-1234  | .worktrees/savi-1234           | workspace:55 |
| SAVI-1235  | .worktrees/savi-1235           | workspace:56 |
```

Every workspace MUST be renamed to its canonical ref (e.g. `MSTR-3034`) per Step 3.3 — the default basename (lowercase, e.g. `mstr-3034`) is not acceptable.

## Edge cases

| Situation                                                                                            | Action                                                                                                                                                                                                 |
| ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `cmux` not installed                                                                                 | Abort, link https://github.com/manaflow-ai/cmux                                                                                                                                                        |
| `command not found: cmux` (or claude/sleep/head/grep/cat) mid-script after earlier resolution succeeded | Not a PATH drop — this is a fresh non-login shell that never had the earlier call's variables. Source `$BINS` (see "Resolve binaries once, persist, then source every call") and use `"$CMUX"` / `"$SLEEP"` / `"$GREP"` / `"$HEAD"` / `"$CAT"` everywhere. Do not retry with bare names.       |
| `juel:daily-worktrees` finds no work items                                                          | Stop after Step 1, nothing to do                                                                                                                                                                       |
| `claude` rejects `--permission-mode auto` (unknown value / not entitled)                             | STOP. Do not spawn the workspace. Tell the user their account is not entitled to `--permission-mode auto` (or the `claude` build is too old). Never fall back to `acceptEdits` or `bypassPermissions`                                                                    |
| `cmux <subcmd>` rejects a flag (CLI version drift)                                                   | Run `cmux <subcmd> --help`, adapt the call once, then continue. Do NOT loop on broken flags                                                                                                            |
| Workspace creation succeeds but `ws_id` parse fails                                                  | Skip that item (per Step 3.2 guard). Never call `rename-workspace` / `send` / `send-key` with an empty `--workspace` value — it silently targets the currently-selected workspace (the orchestrator) |
| Workspace creation fails for one item                                                                | Log error, continue with the rest, include in final report                                                                                                                                             |
| Slash command appears typed but not submitted                                                        | `send-key Enter` was not invoked after `send`; re-send Enter via `"$CMUX" send-key --workspace "$ws_id" Enter`                                                                                         |
| `juel:daily-worktrees` copy step fails on an untracked-file pattern                                 | Not this skill's bug. `juel:daily-worktrees` no longer globs at all — its `copy_untracked` is `find`-based, which never aborts on no-match (see `references/resolution.md` §4.2). If `config.worktreeCopy` extra patterns are involved, the applicable guard is `[ -n "$ZSH_VERSION" ] && setopt SH_WORD_SPLIT` before building `EXTRA_PATTERNS`, not `NULL_GLOB` — `daily-worktrees` already carries this guard. Document and continue |
| Loop runs once / wrong dir paired with wrong item                                                    | A `for x in $string` word-split was used instead of the here-doc `while IFS='|' read -r` form (see "Ref/dir iteration" section) — word-splitting behavior differs by shell, the here-doc form does not depend on it. Close any mis-created workspace and recreate                    |
| `command not found: cat` mid-script                                                                  | `$BINS` was not sourced in this call. Source it (see "Resolve binaries once..." above) and use `"$CAT"`, or just `echo`                                                                                            |
| User reused an existing worktree                                                                     | Still spawn a workspace; claude starts fresh in it                                                                                                                                                     |
| More than 5 items selected                                                                           | Ask user to confirm before launching that many parallel claudes                                                                                                                                        |

## QA checklist

- [ ] All binaries resolved once via `resolve_bin`, persisted to `$BINS`, and sourced (not re-resolved) at the top of every subsequent call (cmux, claude, sleep, grep, head, cat)
- [ ] No `cd` anywhere in the script
- [ ] Ref/dir iteration uses the `while IFS='|' read -r` here-doc form, NOT a `for x in $string` word-split (behavior differs by shell) and NOT `ref:dir` tokens re-split with `%%`/`##`
- [ ] Each `$path` echoed next to its `$ref` and confirmed to match before `new-workspace`
- [ ] Worktrees created/reused by `juel:daily-worktrees`
- [ ] One CMUX workspace per selected item, `cwd` = worktree absolute path
- [ ] `ws_id` parsed and non-empty before any `send`/`send-key`
- [ ] `claude` launched inside each workspace (no `--session-id`) with `--permission-mode auto` — no `acceptEdits`/`bypassPermissions` fallback attempted
- [ ] `/juel:ship-ticket <REF>` typed AND Enter pressed (visible as a submitted prompt, not a draft)
- [ ] Every workspace renamed to the canonical ref (e.g. `MSTR-3034`, not `mstr-3034`)
- [ ] `INSTALL_CMD` resolved once (from `$MAIN_ROOT`, before the per-item loop) via the tiered detection layer, reused unchanged for every item — never re-detected per item
- [ ] Per item: if `INSTALL_CMD` is non-empty, a second tab (surface) opened with it running (not typed into the claude tab); if empty, the second surface is skipped entirely for that item (no error, no empty tab)
- [ ] Workspace renamed via POSITIONAL title arg (NOT `--name`) — verify the sidebar shows just the ref, not `--name MSTR-XXXX`
- [ ] Workspace tagged green via `set-status ship "ready" --color "#22c55e"`
- [ ] `rename-workspace` never called with an empty or malformed `--workspace` (regex-guarded against `workspace:[0-9]+`)
- [ ] Final report lists every ref → workspace mapping
- [ ] No work-item status changes beyond what `juel:daily-worktrees` already did
- [ ] No accidental rename / send against the orchestrator workspace
