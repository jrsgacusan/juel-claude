---
name: cmux-review-pr
description: Use to review a GitHub PR (or arbitrary branch) inside an isolated CMUX workspace. Creates a git worktree for the PR branch, spawns a CMUX workspace, auto-launches `claude` with a deterministic session id derived from the PR id, fetches the linked Linear ticket so the review is graded against the ticket's requirements, runs `/pr-review-toolkit:review-pr`, then validates the findings with codex. Triggers "review pr", "/juel:cmux-review-pr".
---

# Juel CMUX Review PR

Sister skill of `juel:cmux-ship-tickets`. Same plumbing (worktree + CMUX workspace + deterministic claude session) but the payload is a code review followed by an independent codex validation pass.

**Two reviewers, one report — graded against the ticket.** Before reviewing, the inner claude fetches the linked Linear ticket (id extracted from the branch/PR title, `juel:start` style) so the diff is judged against the ticket's requirements and acceptance criteria, not just generic code quality. It then runs `/pr-review-toolkit:review-pr`, hands every finding to codex for a second opinion. Do NOT pin a codex model or reasoning effort — let codex use its own defaults. Final consolidated report lives at `docs/.superpowers/findings-review.md` with four buckets: Ticket-alignment, Confirmed, Disputed, Codex-only.

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
| cmux | cli | HARD | `command -v cmux`, else the cmux.app path | STOP → https://github.com/manaflow-ai/cmux |
| claude | cli | HARD | `command -v claude`, else the cmux.app path | STOP |
| gh (authenticated) | cli | HARD | `gh auth status` | STOP → `gh auth login` |
| codex | cli | SOFT | `command -v codex` | the inner session validates findings itself |
| coreutils | cli | HARD | one batched `test -x` | STOP |
| git repo matching the PR remote | context | HARD | `git remote get-url <remote>` | STOP |
| resolvable PR or branch | context | HARD | `gh pr view <N> --json number` | STOP |
| pr-review-toolkit | skill | SOFT | ships as a plugin dependency | inner session falls back to `/review` |
| Linear MCP | mcp | SOFT | **none — render as `?`** | review proceeds ungraded; the alignment section is omitted |

## Phases

[ ] 1. Preflight — resolve binaries, set CMUX_QUIET
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
| `[base-branch]` | no | Branch to diff against for codex validation. Defaults to `dev`. |

Usage: `/juel:cmux-review-pr 1234` or `/juel:cmux-review-pr feat/savi-1162-foo` or `/juel:cmux-review-pr 1234 main`.

## Prerequisites

- `cmux` CLI installed (on PATH or at default GUI install location `/Applications/cmux.app/Contents/Resources/bin/cmux`).
- `claude` CLI installed (same resolution rule; default GUI path `/Applications/cmux.app/Contents/Resources/bin/claude`).
- `gh` CLI on PATH and authenticated.
- Inside a git repo whose remote matches the PR.
- `pr-review-toolkit` plugin/skill installed (provides `/pr-review-toolkit:review-pr`).

### Resolve ALL binaries upfront — PATH drops mid-script

The Bash tool's subshell does not reliably inherit the login shell's PATH. `command -v <bin>` may succeed in one tool call and then a subsequent call in the same tool finds `command not found: python3` / `sleep` / `head` / `grep`. Resolve everything once at the start, then use absolute paths everywhere. Do NOT rely on `export PATH=...` — observed to be unreliable.

```bash
CMUX=$(command -v cmux 2>/dev/null || echo /Applications/cmux.app/Contents/Resources/bin/cmux)
CLAUDE_BIN=$(command -v claude 2>/dev/null || echo /Applications/cmux.app/Contents/Resources/bin/claude)
GH=$(command -v gh 2>/dev/null || echo /opt/homebrew/bin/gh)
PYTHON3=$(command -v python3 2>/dev/null || echo /usr/bin/python3)
SLEEP=/bin/sleep
GREP=/usr/bin/grep
HEAD=/usr/bin/head
JQ=$(command -v jq 2>/dev/null || echo /opt/homebrew/bin/jq)
[ -x "$CMUX" ] || { echo "cmux not found at $CMUX"; exit 1; }
[ -x "$CLAUDE_BIN" ] || { echo "claude not found at $CLAUDE_BIN"; exit 1; }
[ -x "$GH" ] || { echo "gh not found at $GH"; exit 1; }
[ -x "$PYTHON3" ] || { echo "python3 not found"; exit 1; }
[ -x "$JQ" ] || { echo "jq not found at $JQ"; exit 1; }
[ -x "$SLEEP" ] && [ -x "$GREP" ] && [ -x "$HEAD" ] || { echo "missing coreutils"; exit 1; }
export CMUX_QUIET=1   # silence cmux's "X is now an alias for Y" deprecation notices
```

Use `"$CMUX"`, `"$CLAUDE_BIN"`, `"$GH"`, `"$PYTHON3"`, `"$JQ"`, `"$SLEEP"`, `"$GREP"`, `"$HEAD"` (never bare names) in every subsequent command.

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

If the argument looks numeric or like a URL, treat it as a PR:

```bash
pr_number=<parsed>
data=$("$GH" pr view "$pr_number" --json number,headRefName,title,headRepository,headRepositoryOwner,isCrossRepository)
branch=$(echo "$data" | "$JQ" -r .headRefName)
title=$(echo "$data" | "$JQ" -r .title)
cross=$(echo "$data" | "$JQ" -r .isCrossRepository)
label="PR-$pr_number"
```

If cross-repo (`isCrossRepository == true`), use `gh pr checkout $pr_number` later instead of plain `git fetch`.

If the argument is a branch name, set `branch=<arg>`, `label=$(echo "$branch" | tr '/' '-' | tr '[:upper:]' '[:lower:]')`, and skip `gh`.

### Step 1b: Extract the Linear ticket id

The review is graded against the ticket, so resolve its id from the branch name (e.g. `feat/savi-1343-...` → `SAVI-1343`), falling back to the PR title (which often carries `[SAVI-XXX]`):

```bash
ticket_id=$(echo "$branch" | "$GREP" -oiE '[a-z]+-[0-9]+' | "$HEAD" -1 | tr '[:lower:]' '[:upper:]')
[ -z "$ticket_id" ] && ticket_id=$(echo "$title" | "$GREP" -oiE '[a-z]+-[0-9]+' | "$HEAD" -1 | tr '[:lower:]' '[:upper:]')
```

If `ticket_id` is empty, the review proceeds without ticket grading — note this in the report. Do NOT block the review on a missing ticket. The inner claude fetches the ticket itself via the Linear MCP `get_issue` inside the workspace (keeps large multi-line descriptions out of the single-line CMUX prompt); the orchestrator only passes the id.

### Step 2: Create the worktree

Worktree dir mirrors the ship-tickets convention so both skills coexist. Compute the absolute path from the repo root, not the current CWD:

```bash
repo_root=$(git rev-parse --show-toplevel)
slug=$(echo "$label" | tr '[:upper:]' '[:lower:]')
abs_worktree="$repo_root/.worktrees/review-$slug"
```

If the worktree already exists, reuse it (skip the create). Otherwise:

```bash
# Non-cross-repo PR or plain branch:
git -C "$repo_root" fetch origin "$branch"
git -C "$repo_root" worktree add "$abs_worktree" "origin/$branch"

# Cross-repo PR:
git -C "$repo_root" worktree add --detach "$abs_worktree"
( cd "$abs_worktree" && "$GH" pr checkout "$pr_number" )
```

Copy env files from repo root the same way `juel:daily-worktrees` does (`.env*`, `*.pem`). Wrap glob expansions in a subshell with `setopt NULL_GLOB` (zsh) or `shopt -s nullglob` (bash) so missing files do not abort.

**Do NOT copy or symlink `venv/` into the worktree.** `make install` runs `python3 -m venv venv`, which refuses to create over an existing file or symlink (`Error: Unable to create directory .../venv`). Leave `venv/` absent so the tab-2 `make install` builds a fresh one.

### Step 3: Compute session id

Deterministic uuidv5 from the label so `claude --resume` is repeatable:

```bash
session_id=$("$PYTHON3" -c "import uuid,sys; print(uuid.uuid5(uuid.NAMESPACE_DNS, sys.argv[1].upper()))" "$label")
```

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
#    screen with `read-screen` until the `❯` input prompt appears, with a hard cap.
ready=0
for _ in $(seq 1 30); do          # up to ~30s
  if "$CMUX" read-screen --workspace "$ws_id" --lines 40 | "$GREP" -q '❯'; then
    ready=1; break
  fi
  "$SLEEP" 1
done
[ "$ready" = 1 ] || echo "WARN: claude input prompt not detected after 30s; sending anyway"

# Composite prompt — ONE LINE (real newlines submit prematurely). Inner claude runs
# the review, then dispatches codex to second-opinion every finding against the diff.
# Codex validation: use `codex exec` (NOT `codex exec review`) so a custom prompt and a
# base diff can coexist. `codex exec review --base <b> "<prompt>"` is REJECTED by codex
# (>=0.140): `--base` cannot combine with a positional prompt. Instead let codex run the
# diff itself inside the prompt. Do NOT pin -m / model_reasoning_effort — codex defaults.
prompt="First, if a ticket id was resolved (${ticket_id:-NONE}), fetch it via the Linear MCP get_issue for ${ticket_id:-NONE} and read its requirements and acceptance criteria; treat them as the spec this PR must satisfy (if NONE, skip ticket grading and note that in the report). Then run /pr-review-toolkit:review-pr against base branch ${base_branch:-dev}. Capture every finding (file, line, severity, claim, suggested fix) AND assess whether the diff actually fulfils each ticket requirement / acceptance criterion, flagging any that are unmet, partially met, or scope-creep beyond the ticket. Then validate the code findings independently with codex: for each finding ask codex whether it is correct, incorrect, or out-of-scope with reference to the actual diff, using: codex exec --sandbox read-only \"First run: git diff ${base_branch:-dev}...HEAD to see the real changes, then validate the following review findings against that diff. For each return VALID / INVALID / OUT-OF-SCOPE with one-sentence justification. Findings: <paste findings here>\". Do NOT pin a codex model or reasoning effort. Produce a final consolidated report with four sections: Ticket-alignment (each requirement/acceptance criterion marked met / partial / unmet with evidence, plus any scope-creep), Confirmed (both reviewers agree), Disputed (codex disagrees with the original review), Codex-only (issues codex raised that the review missed). Save it to docs/.superpowers/findings-review.md. run /pr-review-toolkit:review-pr in the FOREGROUND (run_in_background: false), do not use parallel mode, read its complete output before continuing, and run codex in the foreground without redirecting its output to any file."

"$CMUX" send --workspace "$ws_id" "$prompt"
"$SLEEP" 1
"$CMUX" send-key --workspace "$ws_id" Enter

# 5. Open a second tab and run `make install` so deps install in parallel with the
#    review (mirrors juel:cmux-ship-tickets). Must be a NEW surface — typing into
#    the claude tab would feed `make install` to the agent as a prompt, not the shell.
raw2=$("$CMUX" new-surface --type terminal --workspace "$ws_id")
surface_id=$(echo "$raw2" | "$GREP" -oE 'surface:[0-9]+' | "$HEAD" -1)
case "$surface_id" in
  surface:[0-9]*)
    "$SLEEP" 1
    "$CMUX" send --workspace "$ws_id" --surface "$surface_id" "make install"
    "$SLEEP" 1
    "$CMUX" send-key --workspace "$ws_id" --surface "$surface_id" Enter ;;
  *) echo "WARN: failed to parse surface id from: $raw2 — skipping make install"; surface_id="" ;;
esac
```

If `cmux new-workspace` output cannot be parsed, fall back to `"$CMUX" list-workspaces` and pick the newest entry whose cwd matches `$abs_worktree`. Still re-verify against the `workspace:[0-9]+` regex before any send.

### Step 5: Report

```
Workspace ready for review:
  PR/branch : <pr or branch>
  Ticket    : <SAVI-XXX or "none — ungraded">
  Worktree  : <abs path>
  Session   : <uuid>   (resume: `claude --resume <uuid>`)
  CMUX ws   : workspace:<N> (renamed to <label>)
  Deps      : make install running in tab 2 (surface:<M>)
```

## Edge cases

| Situation | Action |
|-----------|--------|
| PR is merged or closed | Warn user, ask whether to continue |
| No ticket id in branch or title | Review proceeds ungraded; note "no ticket" in the report. Do not block. |
| Ticket id extracted but Linear `get_issue` fails / not found | Inner claude proceeds with code review only; Ticket-alignment section records the fetch failure instead of grading. |
| Local branch with same name already checked out elsewhere | Use `git worktree add --detach` + `gh pr checkout` style instead of duplicate branch |
| `.worktrees/review-<slug>` already exists | Reuse; do not re-fetch unless user asks |
| `pr-review-toolkit` not installed | Stop and instruct user to install the plugin |
| `command not found: cmux` (or python3/sleep/head/grep/jq/gh) mid-script after earlier resolution succeeded | Subshell lost PATH. Re-resolve via Prerequisites block and use absolute path variables everywhere. Do not retry with bare names. |
| `cmux <subcmd>` rejects a flag (CLI version drift) | Run `cmux <subcmd> --help`, adapt once, continue. Do NOT loop on broken flags. |
| Workspace creation succeeds but `ws_id` parse fails | Fall back to `cmux list-workspaces`, match by cwd. Never call `rename-workspace` / `send` / `send-key` with an empty `--workspace` — silently targets the orchestrator. |
| Prompt never appears / input box empty after send | Send hit the TUI before it was ready (blind `sleep` too short; plugins/banners delay boot). Use the `read-screen` readiness poll (wait for `❯`) before sending. To recover: `read-screen` to confirm the empty input, then re-`send` the single-line prompt and `send-key Enter`. |
| Slash command typed but not submitted (sits as a draft) | `send-key Enter` was not invoked after `send`. Re-send Enter via `"$CMUX" send-key --workspace "$ws_id" Enter`. |
| Multi-line prompt submitted in fragments | Real newlines in a `cmux send` payload each act as Enter. Send the prompt as a SINGLE LINE. |
| `make install` second tab not created | `new-surface` output parse failed; review still proceeds in tab 1. Re-run `"$CMUX" new-surface --type terminal --workspace "$ws_id"` and send `make install` to the returned surface. |
| `claude --session-id` rejects uuid | Launch `claude` without session id; warn that resume needs picker. |
| User gave a forked-PR url and `gh pr checkout` fails auth | Surface `gh` error verbatim, do not retry blindly. |

## QA checklist

- [ ] All binaries resolved to absolute paths upfront (cmux, claude, gh, python3, jq, sleep, grep, head)
- [ ] No `cd` in the orchestrator script (only inside subshells `( cd ... && ... )`)
- [ ] PR/branch resolved correctly (right repo, right head ref)
- [ ] Ticket id extracted from branch (fallback: PR title), uppercased; empty → review proceeds ungraded (not blocked)
- [ ] Worktree under `<repo_root>/.worktrees/review-<slug>` with env files copied
- [ ] CMUX workspace cwd = worktree absolute path
- [ ] `ws_id` parsed and matches `workspace:[0-9]+` before any `send` / `send-key` / `rename-workspace`
- [ ] Workspace tab renamed via POSITIONAL title (NOT `--name`) — verify the sidebar shows just `<label>`, not `--name <label>`
- [ ] `"$CLAUDE_BIN" --session-id <uuid>` launched in the workspace (absolute path, not bare `claude`)
- [ ] `read-screen` readiness poll (wait for `❯`) used before `send` — NOT a blind `sleep`
- [ ] Composite prompt sent as a SINGLE LINE (no real newlines), typed AND Enter pressed (visible as a submitted prompt, not a draft)
- [ ] Prompt instructs inner claude to fetch the Linear ticket (`get_issue` for `$ticket_id`) and grade the diff against its requirements/acceptance criteria before the code review
- [ ] Codex validation step uses `codex exec --sandbox read-only "<prompt>"` (NOT `codex exec review --base ...`, which rejects a prompt), with the prompt telling codex to `git diff <base>...HEAD` itself, and NO `-m` / `model_reasoning_effort` override (codex defaults)
- [ ] A second tab (surface) opened with `make install` running (sent to the new surface, NOT the claude tab)
- [ ] `export CMUX_QUIET=1` set so alias-deprecation notices are silenced
- [ ] Final report destination `docs/.superpowers/findings-review.md` mentioned in the prompt with the four buckets (Ticket-alignment / Confirmed / Disputed / Codex-only)
- [ ] Final report shows PR id, ticket id, worktree path, session id, workspace id, make-install surface
- [ ] No accidental rename / send against the orchestrator workspace
