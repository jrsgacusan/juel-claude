---
name: cmux-ship-tickets
description: Use when starting your workday in CMUX to ship multiple Linear tickets in parallel. Wraps juel:daily-worktrees + per-ticket CMUX workspace creation + auto-launch of `claude` running `/juel:ship-ticket`. Triggers "ship my tickets", "start my day", "/juel:cmux-ship-tickets".
---

# Juel CMUX Ship Tickets

End-to-end daily kickoff: fetch Linear todos, create git worktrees, spawn one CMUX workspace per ticket, start `claude` in each with `/juel:ship-ticket <TICKET>` queued, and kick off `make install` in a second tab so deps install in parallel.

**Announce:** "Using juel:cmux-ship-tickets to spin up worktrees + CMUX workspaces + claude sessions."

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
| cmux | cli | HARD | `command -v cmux`, else `/Applications/cmux.app/Contents/Resources/bin/cmux` | STOP → https://github.com/manaflow-ai/cmux |
| claude | cli | HARD | `command -v claude`, else the cmux.app path | STOP → install the Claude Code CLI |
| coreutils | cli | HARD | one batched `test -x` for sleep/grep/head/cat | STOP |
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP |
| juel:daily-worktrees, juel:ship-ticket | skill | HARD | ship with this plugin | STOP |
| Linear MCP | mcp | HARD | **none — render as `?`** | proceed; phase 2 fails loudly if absent |
| resolved install command | cli | SOFT | see resolution layer | skip the second surface; install deps yourself |
| `--permission-mode auto` | perm | SOFT | none (attempt + catch) | relaunch with `acceptEdits`, never `bypassPermissions` |

## Phases

[ ] 1. Preflight — resolve every binary to an absolute path
[ ] 2. Run juel:daily-worktrees, declining its planning offer
[ ] 3. Confirm the CMUX launch with the user
[ ] 4. Per item: create the workspace and launch claude
[ ] 5. Per item: guard the workspace id, rename it, set the status pill
[ ] 6. Per item: wait for the TUI, send /juel:ship-ticket <REF> + Enter
[ ] 7. Per item: open the second surface and start the resolved install command
[ ] 8. Report the item → worktree → workspace table
[ ] 9. Verify the QA checklist

## Prerequisites

- `cmux` CLI installed (on PATH or at the default GUI install location `/Applications/cmux.app/Contents/Resources/bin/cmux`). If neither resolves, abort with install hint.
- `claude` CLI installed (same resolution rule; default GUI path `/Applications/cmux.app/Contents/Resources/bin/claude`).
- Inside a git repo with `juel:daily-worktrees` skill available.
- Linear plugin authenticated.

### Resolve ALL binaries upfront — PATH drops mid-script

The Bash tool's subshell does not reliably inherit the login shell's PATH. `command -v <bin>` may succeed in one tool call and then a subsequent call in the same tool finds `command not found: python3` / `sleep` / `head` / `grep`. Resolve everything once at the start, then use absolute paths everywhere. Do NOT rely on `export PATH=...` — observed to be unreliable.

```bash
CMUX=$(command -v cmux 2>/dev/null || echo /Applications/cmux.app/Contents/Resources/bin/cmux)
CLAUDE_BIN=$(command -v claude 2>/dev/null || echo /Applications/cmux.app/Contents/Resources/bin/claude)
SLEEP=/bin/sleep
GREP=/usr/bin/grep
HEAD=/usr/bin/head
CAT=/bin/cat
[ -x "$CMUX" ] || { echo "cmux not found at $CMUX"; exit 1; }
[ -x "$CLAUDE_BIN" ] || { echo "claude not found at $CLAUDE_BIN"; exit 1; }
[ -x "$SLEEP" ] && [ -x "$GREP" ] && [ -x "$HEAD" ] && [ -x "$CAT" ] || { echo "missing coreutils"; exit 1; }
```

Use `"$CMUX"`, `"$CLAUDE_BIN"`, `"$SLEEP"`, `"$GREP"`, `"$HEAD"`, `"$CAT"` (never bare names) in every subsequent command. `echo` is a shell builtin so it is safe; `cat` is NOT — it drops out with the rest of PATH, so use `"$CAT"`.

### CWD persistence — never `cd` in this skill

The Bash tool's working directory persists across calls. A `cd .worktrees/savi-XXXX` in one call leaks into the next call and any relative path (e.g. `.worktrees/savi-XXXX`) then resolves to a nested location. **Never `cd` in this skill.** Always use absolute paths for everything. If you must operate in a worktree, use the absolute path directly.

### The shell is zsh — DO NOT word-split a string in a `for` loop

The Bash tool runs under **zsh** on this machine, and zsh does **not** field-split unquoted variables the way bash does. This silently broke a run: a loop written `for pair in $tickets` (where `tickets` was a space-joined string `"SAVI-1287:savi-1287 SAVI-1312:savi-1312 ..."`) executed **once** with `pair` bound to the _entire_ string, and `${pair%%:*}` / `${pair##*:}` then produced the first ticket's id paired with the **last** ticket's dir — so a workspace was created in the wrong worktree and renamed to the wrong ticket.

**Never iterate a space-joined string.** Use real zsh arrays and index them explicitly (zsh arrays are 1-based):

```bash
tickets=(SAVI-1287 SAVI-1312 SAVI-1282 SAVI-1277)
dirs=(savi-1287 savi-1312 savi-1282 savi-1277)   # parallel arrays, same order
for i in {1..${#tickets[@]}}; do
  ticket=${tickets[$i]}; dir=${dirs[$i]}
  path="$ROOT/.worktrees/$dir"
  # ... spawn workspace for $ticket at $path ...
done
```

Rules:

- Build the ticket list as a literal array `(A B C)`, never a quoted string you later split.
- Keep `tickets` and `dirs` (and any ws-id map) as **parallel arrays** indexed by the same `$i`. Do NOT pack `ticket:dir` into one token and re-split with `%%`/`##`.
- After computing `path`, echo it next to `$ticket` and **eyeball that they match** before calling `new-workspace` — a mismatch here means a workspace lands in the wrong worktree.
- If a workspace does get created with the wrong cwd/name, `close-workspace --workspace workspace:<N>` it and recreate, rather than trying to repoint it.

## CMUX CLI cheat sheet (verified against cmux 0.62.x)

| Need                                                                 | Command                                                                                                  |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Create workspace + run startup command (Enter pressed automatically) | `cmux new-workspace --cwd "$path" --command "<cmd>"`                                                     |
| Output format                                                        | Single line on stdout: `OK workspace:<N>`                                                                |
| Open a new tab (surface) in a workspace                              | `cmux new-surface --type terminal --workspace workspace:<N>`                                             |
| Send literal text (no Enter) to specific surface/tab                 | `cmux send --workspace workspace:<N> --surface surface:<M> "<text>"`                                     |
| Send literal text (no Enter)                                         | `cmux send --workspace workspace:<N> "<text>"`                                                           |
| Press Enter (or other keys)                                          | `cmux send-key --workspace workspace:<N> Enter`                                                          |
| Rename a workspace                                                   | `cmux rename-workspace --workspace workspace:<N> "<TICKET-ID>"` (title is POSITIONAL — no `--name` flag) |
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

Invoke the `juel:daily-worktrees` skill. Let user pick tickets and let it create worktrees, copy env files, set Linear status to In Progress.

**Stop at its Step 8 "Offer Planning" prompt and decline planning** (planning happens via `/juel:ship-ticket` inside each CMUX workspace).

Collect the list of newly-created or reused worktrees with absolute paths and ticket ids:

```
[
  { "ticket": "SAVI-1234", "path": "/abs/path/.worktrees/savi-1234" },
  ...
]
```

### Step 2: Confirm CMUX launch

Show the user the list and ask: "Spawn a CMUX workspace + claude session for each? [Y/n]"

If declined, stop and report worktree paths only.

### Step 3: For each ticket, spawn workspace

For each `{ticket, path}`:

1. **Create workspace and launch claude in one call.** The `--command` flag runs the command in the new workspace's terminal and presses Enter automatically. Pass the absolute `$CLAUDE_BIN`, and start it in **auto permission mode** so the session works through `/juel:ship-ticket` without stopping at every tool prompt:

   ```bash
   raw=$("$CMUX" new-workspace --cwd "$path" --command "$CLAUDE_BIN --permission-mode auto")
   # raw looks like: "OK workspace:55"
   ws_id=$(echo "$raw" | "$GREP" -oE 'workspace:[0-9]+' | "$HEAD" -1)
   ```

   `auto` auto-approves tool calls but runs a background safety classifier that still blocks destructive actions (force push, mass deletion, `curl | bash`, production deploys) and falls back to manual prompting after repeated blocks. This is the point of the skill — an unattended session that pauses on the first `pnpm install` prompt has not shipped anything.

   If `--permission-mode auto` is rejected (older `claude` build, or the account is not entitled to auto mode), fall back to `--permission-mode acceptEdits` and note it in the final report. Do **not** fall back to `bypassPermissions` / `--dangerously-skip-permissions`: these worktrees sit on the real filesystem with real credentials, not in a container.

2. **Guard: abort this ticket if ws_id is empty.** A blank `--workspace` arg silently targets the currently-selected workspace, which is the orchestrator running this skill — `send`/`send-key` against an empty ref will type into the user's own claude session.

   ```bash
   if [ -z "$ws_id" ]; then
     echo "WARN: failed to parse workspace id from: $raw — skipping $ticket"
     continue
   fi
   ```

   If parsing fails repeatedly, fall back to `"$CMUX" list-workspaces` and take the newest entry whose `cwd` matches `$path`.

3. **Rename the workspace to the ticket id (non-negotiable).** CMUX defaults to the worktree dir basename (e.g. `mstr-3034`), which is fine but inconsistent with how the user thinks about tickets. Always rename to the canonical ticket id (e.g. `MSTR-3034`). The title is a POSITIONAL argument — there is no `--name` flag.

   ```bash
   "$CMUX" rename-workspace --workspace "$ws_id" "$ticket"
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
   "$CMUX" send --workspace "$ws_id" "/juel:ship-ticket $ticket"
   "$SLEEP" 1
   "$CMUX" send-key --workspace "$ws_id" Enter
   ```

6. **Open a second tab and run `make install` to install deps.** Each worktree starts with no installed dependencies — kick off `make install` in a separate tab so it runs in parallel with the claude session. Do NOT run it in the main tab (that's where claude lives).

   ```bash
   raw2=$("$CMUX" new-surface --type terminal --workspace "$ws_id")
   surface_id=$(echo "$raw2" | "$GREP" -oE 'surface:[0-9]+' | "$HEAD" -1)
   case "$surface_id" in
     surface:[0-9]*) ;;
     *) echo "WARN: failed to parse surface id from: $raw2 — skipping make install for $ticket"; surface_id="" ;;
   esac
   if [ -n "$surface_id" ]; then
     "$SLEEP" 1
     "$CMUX" send --workspace "$ws_id" --surface "$surface_id" "make install"
     "$SLEEP" 1
     "$CMUX" send-key --workspace "$ws_id" --surface "$surface_id" Enter
   fi
   ```

   **Why a second tab and not the claude tab:** typing `make install` into the claude tab would feed it as a prompt to the agent, not as a shell command. The new surface is a fresh terminal in the same workspace + cwd.

   **Why not block on it:** `make install` can take minutes (pnpm install + venv + wheels). Fire-and-forget so claude can start planning in parallel.

7. **Record the mapping** for the final report.

### Step 4: Report

Print a table:

```
Launched N CMUX workspaces:

| Ticket     | Worktree                       | CMUX         |
|------------|--------------------------------|--------------|
| SAVI-1234  | .worktrees/savi-1234           | workspace:55 |
| SAVI-1235  | .worktrees/savi-1235           | workspace:56 |
```

Every workspace MUST be renamed to its canonical ticket id (e.g. `MSTR-3034`) per Step 3.3 — the default basename (lowercase, e.g. `mstr-3034`) is not acceptable.

## Edge cases

| Situation                                                                                            | Action                                                                                                                                                                                                 |
| ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `cmux` not installed                                                                                 | Abort, link https://github.com/manaflow-ai/cmux                                                                                                                                                        |
| `command not found: cmux` (or python3/sleep/head/grep) mid-script after earlier resolution succeeded | The subshell lost PATH. Re-resolve via the Prerequisites block and use `"$CMUX"` / `"$SLEEP"` / `"$GREP"` / `"$HEAD"` everywhere. Do not retry with bare names.                                        |
| `juel:daily-worktrees` finds no tickets                                                            | Stop after Step 1, nothing to do                                                                                                                                                                       |
| `claude` rejects `--permission-mode auto` (unknown value / not entitled)                             | Relaunch that workspace with `--permission-mode acceptEdits` and say so in the final report. Never fall back to `bypassPermissions`                                                                    |
| `cmux <subcmd>` rejects a flag (CLI version drift)                                                   | Run `cmux <subcmd> --help`, adapt the call once, then continue. Do NOT loop on broken flags                                                                                                            |
| Workspace creation succeeds but `ws_id` parse fails                                                  | Skip that ticket (per Step 3.2 guard). Never call `rename-workspace` / `send` / `send-key` with an empty `--workspace` value — it silently targets the currently-selected workspace (the orchestrator) |
| Workspace creation fails for one ticket                                                              | Log error, continue with the rest, include in final report                                                                                                                                             |
| Slash command appears typed but not submitted                                                        | `send-key Enter` was not invoked after `send`; re-send Enter via `"$CMUX" send-key --workspace "$ws_id" Enter`                                                                                         |
| `juel:daily-worktrees` zsh glob error (`no matches found: .env.*`)                                 | Not this skill's bug — fix in `juel:daily-worktrees` by wrapping the copy block in `setopt NULL_GLOB`. Document and continue                                                                         |
| Loop runs once / wrong dir paired with wrong ticket                                                  | zsh did not word-split your `for x in $string`. Rewrite with literal parallel arrays indexed by `$i` (see "The shell is zsh" section). Close any mis-created workspace and recreate                    |
| `command not found: cat` mid-script                                                                  | `cat` is not a builtin and dropped with PATH. Use `"$CAT"` (resolved to `/bin/cat` upfront), or just `echo`                                                                                            |
| User reused an existing worktree                                                                     | Still spawn a workspace; claude starts fresh in it                                                                                                                                                     |
| More than 5 tickets selected                                                                         | Ask user to confirm before launching that many parallel claudes                                                                                                                                        |

## QA checklist

- [ ] All binaries resolved to absolute paths upfront (cmux, claude, sleep, grep, head, cat)
- [ ] No `cd` anywhere in the script
- [ ] Ticket/dir iteration uses literal zsh arrays + index, NOT a `for x in $string` word-split (zsh does not split) and NOT `ticket:dir` tokens re-split with `%%`/`##`
- [ ] Each `$path` echoed next to its `$ticket` and confirmed to match before `new-workspace`
- [ ] Worktrees created/reused by `juel:daily-worktrees`
- [ ] One CMUX workspace per selected ticket, `cwd` = worktree absolute path
- [ ] `ws_id` parsed and non-empty before any `send`/`send-key`
- [ ] `claude` launched inside each workspace (no `--session-id`) with `--permission-mode auto`
- [ ] `/juel:ship-ticket <TICKET>` typed AND Enter pressed (visible as a submitted prompt, not a draft)
- [ ] Every workspace renamed to the canonical ticket id (e.g. `MSTR-3034`, not `mstr-3034`)
- [ ] A second tab (surface) opened per workspace with `make install` running (not typed into the claude tab)
- [ ] Workspace renamed via POSITIONAL title arg (NOT `--name`) — verify the sidebar shows just the ticket id, not `--name MSTR-XXXX`
- [ ] Workspace tagged green via `set-status ship "ready" --color "#22c55e"`
- [ ] `rename-workspace` never called with an empty or malformed `--workspace` (regex-guarded against `workspace:[0-9]+`)
- [ ] Final report lists every ticket → workspace mapping
- [ ] No Linear status changes beyond what `juel:daily-worktrees` already did
- [ ] No accidental rename / send against the orchestrator workspace
