---
name: cmux-babysit
description: Use when the user runs multiple claude sessions across CMUX workspaces (e.g. after juel:cmux-ship-tickets) and wants one manager session that monitors all of them, reports which need approval or replies, and relays the user's answers — so the user never switches tabs. Triggers "babysit my workspaces", "monitor my tickets", "/juel:cmux-babysit".
---

# Juel CMUX Babysit

Turn the current session into a manager for N CMUX workspaces each running a `claude` TUI. Poll screens, classify state, set sidebar pills, report only what needs the user, and relay their answers.

**Announce:** "Using juel:cmux-babysit to monitor your CMUX workspaces."

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
| coreutils | cli | HARD | one batched `test -x` for tail/grep/sleep | STOP |
| ≥1 CMUX workspace running a claude TUI | context | HARD | `cmux list-workspaces` non-empty | STOP → nothing to babysit |
| AskUserQuestion | context | HARD | always available interactively | STOP |
| Notification + Stop hooks | perm | SOFT | `grep -q 'cmux wait-for' <settings>` | run poll-only mode; offer to add the hooks |

## Phases

[ ] 1. Setup — resolve binaries, discover target workspaces, confirm the list
[ ] 2. Poll — list notifications, read the screens of flagged workspaces
[ ] 3. Classify — assign state per the marker table, set sidebar pills
[ ] 4. Triage — present pending workspaces one at a time, approvals first
[ ] 5. Relay — send the answer, verify it landed, update the pill
[ ] 6. Summarize + rearm — one line per workspace, restart the waiter, return to phase 2

Phases 2–6 loop: after phase 6, control returns to phase 2 for the next wake/poll cycle. This is intentional re-entry, not a violation of protocol rule 2 ("no skipping, reordering, or merging") — the phases still run in order on each pass through the loop; only the loop's repeat is exempt from the "never begin phase N+1 before phase N" one-way reading.

## Setup

Resolve binaries once, absolute paths everywhere (PATH drops mid-script):

```bash
CMUX=$(command -v cmux 2>/dev/null || echo /Applications/cmux.app/Contents/Resources/bin/cmux)
TAIL=/usr/bin/tail; GREP=/usr/bin/grep; SLEEP=/bin/sleep
```

**Discover targets:** workspaces with a `ship` status pill (`"$CMUX" list-status --workspace workspace:<N>`), or take the list from the conversation / `"$CMUX" list-workspaces` (ticket-id titles). Confirm the list with the user once.

**Self-guard:** never `send`/`send-key` to the orchestrator's own workspace (`$CMUX_WORKSPACE_ID` if set). Only target refs matching `workspace:[0-9]+`.

## Poll cycle

**Cheap pass first:** `"$CMUX" list-notifications` — cmux aggregates Claude Code events. Lines look like `idx:NOTIF_UUID|WS_UUID|SURFACE_UUID|read/unread|Claude Code|Permission/Waiting|message`. Map WS_UUID to refs via `"$CMUX" list-workspaces --id-format both`. Only `read-screen` workspaces with unread notifications (plus any not seen recently). `"$CMUX" clear-notifications` after handling so the next pass is clean.

For each flagged workspace: `"$CMUX" read-screen --workspace "$ws" --lines 25`

Classify by these verified markers (check in order, first match wins):

| State | Screen markers | Pill |
|---|---|---|
| NEEDS APPROVAL | `Do you want to proceed?` or `❯ 1. Yes` | `set-status ship "approve?" --color "#ef4444"` |
| NEEDS REPLY | idle footer (`? for shortcuts`) AND last assistant text ends in a question | `set-status ship "question" --color "#f59e0b"` |
| WORKING | spinner `✻ …` with elapsed time, or `N shell still running` / `Running in the background` | `set-status ship "working" --color "#22c55e"` |
| IDLE/DONE | idle footer, no question (e.g. PR opened, summary printed) | `set-status ship "done" --color "#3b82f6"` |
| ERROR | `error`, `failed`, traceback near prompt | `set-status ship "error" --color "#ef4444"` |

Present pending tickets **one at a time, interactively** — never a batched list. For each ticket needing input, in priority order (approvals first, then questions):

1. Show the ticket id, state, and the verbatim question/command.
2. Ask via AskUserQuestion with options mirroring the actual dialog (e.g. "Yes", "Always allow", "No" for approvals; "Proceed"/"Hold" for phase gates). Include a recommendation when there's an obvious default.
3. Relay the answer immediately (`send`/`send-key`), verify it landed, update the pill.
4. Only then present the next pending ticket.

After all pending tickets are handled, summarize working/done tickets in one line each. If nothing needs action, one line: "All N working."

## Relaying user answers

| User says | Action |
|---|---|
| "approve 1249" / "yes" | `"$CMUX" send --workspace "$ws" "1"` (selects option 1; no Enter needed for numbered dialogs) |
| "approve always" | `send "2"` only if option 2 is the don't-ask-again variant — re-read screen first to confirm option numbering |
| "deny" | send the number of the `No` option (read screen first; it's `2` or `3`) |
| free-text reply | `send --workspace "$ws" "<text>"`, `"$SLEEP" 1`, `send-key --workspace "$ws" Enter` |
| "what's X doing" | `read-screen` that workspace, summarize |

After every relay, `"$SLEEP" 2` then `read-screen` to verify it landed (dialog gone / prompt submitted). If a numbered send didn't register, fall back to `send-key Down`/`Enter`.

**Never auto-approve.** Only relay what the user explicitly answered. Batch: "approve all" = approve each currently-pending dialog, re-reading each screen first.

## Wake model: push first, poll fallback

**Push (preferred):** global `~/.claude/settings.json` has async `Notification` + `Stop` hooks running `cmux wait-for -S babysit`. Start a background waiter each cycle:

```bash
"$CMUX" wait-for babysit --timeout 3500
```

Run it via Bash `run_in_background: true` — the harness wakes this session the moment any claude session (started AFTER the hooks were added) needs permission or finishes a turn. On wake: run the cheap poll pass, handle, restart the waiter.

> This is a blocking waiter, not a subagent or an executor. Protocol rule 4 does not apply to it.

**Poll fallback:** sessions started before the hooks existed never signal (hooks snapshot at startup). For those, also keep a ScheduleWakeup loop: **60–90s** while anything is WORKING or pending; 1200s+ only when all idle/done. Both mechanisms coexist safely — each wake just runs the same cheap poll cycle.

Stop when user says stop or all workspaces are done (kill the waiter task too).

## Edge cases

| Situation | Action |
|---|---|
| read-screen returns empty / errors | Mark workspace `unknown`, report it, keep looping |
| Workspace closed mid-loop | Drop from target list, note in next report |
| Two dialogs queued back-to-back | After relaying, re-read screen; a new dialog may already be up |
| User answer ambiguous about target | Ask which ticket — never guess the workspace |
| Approval is destructive (rm, push, deploy) | Quote the full command in the report; require explicit per-item confirmation, exclude from "approve all" |
