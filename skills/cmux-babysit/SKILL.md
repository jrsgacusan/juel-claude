---
name: cmux-babysit
description: Use when the user runs multiple claude sessions across CMUX workspaces (e.g. after juel:cmux-ship-tickets) and wants one manager session that monitors all of them, reports which need approval or replies, and relays the user's answers — so the user never switches tabs. Triggers "babysit my workspaces", "monitor my tickets", "/juel:cmux-babysit".
---

# Juel CMUX Babysit

Turn the current session into a manager for N CMUX workspaces each running a `claude` TUI. Poll screens, classify state, set sidebar pills, report only what needs the user, and relay their answers.

**Announce:** "Using juel:cmux-babysit to monitor your CMUX workspaces."

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
