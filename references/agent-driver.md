# Agent driver — authoring source of truth

This file is **not** read at runtime. It exists so that the four things which differ
between driving a `claude` session and a `codex` session live in one place, instead of
being re-derived in each `cmux-*` skill.

`resolve_agent` in `references/resolution.md` is the runtime implementation. Every
`cmux-*` skill calls it and then uses the exported variables. No skill may name a bare
`claude` or `codex` binary, hard-code `--permission-mode auto`, or grep for a TUI string
directly.

## The four axes

| Axis | Variable | claude | codex |
| --- | --- | --- | --- |
| Binary | `AGENT_BIN` | resolved `claude` | resolved `codex` |
| Launch flags | `AGENT_LAUNCH_FLAGS` | `--permission-mode auto` | `--approve-for-me` |
| Prompt syntax | `AGENT_PROMPT_PREFIX` | `/juel:ship-ticket` | `$juel:ship-ticket` |
| Screen markers | `AGENT_READY_MARKER`, `AGENT_APPROVAL_MARKER` | `? for shortcuts`, `Do you want to proceed?` | `Ask Codex to do anything`, `Would you like to run the following command?` |

## Why the launch flags are not equivalent

`--permission-mode auto` is a Claude Code entitlement, checked as a HARD `perm` dependency
because spawning an unattended session on a lesser mode means it stops at the first prompt
with nobody watching. Codex has no analogue. Its nearest equivalent is `--approve-for-me`,
which routes each escalation through automated review rather than granting a blanket mode.

The consequence is real and must not be papered over: under Codex, `.git` is a protected
path, so a spawned session that cannot escalate cannot commit. `--approve-for-me` is what
makes an unattended Codex workspace able to finish a ticket. A session launched without it
runs until its first commit and then stalls.

## Notification matching

cmux's Codex notification field includes a dynamic spinner and workspace title around the
stable `codex` provider token. The driver therefore uses `AGENT_NOTIFICATION_LABEL` as a
substring match for Codex notifications, while retaining the exact `Claude Code` label for
Claude notifications in a mixed fleet.

## Adding a third agent

Add a `case` arm to `resolve_agent`, add a column here, and add a row to the marker table.
Nothing else should need to change. If a skill needs an axis this file does not list, add
the axis here first rather than special-casing it in that skill.
