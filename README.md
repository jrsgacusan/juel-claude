# juel-claude

Juel's personal Claude Code workflow plugin: ticket to PR.

A set of skills that wire together Linear, git worktrees, CMUX, Codex, and PR review into a
single ticket-to-PR workflow — fetch a ticket, brainstorm and plan, dispatch execution, review
and remediate, verify, and ship a PR, optionally running several tickets in parallel across
CMUX workspaces.

## Install

    /plugin marketplace add jrsgacusan/juel-claude
    /plugin install juel@juel-claude

Restart Claude Code to apply.

## Update

    /plugin marketplace update juel-claude
    /plugin update juel@juel-claude    # restart to apply

## Dependencies (install automatically)

This plugin declares five dependencies from the `claude-plugins-official` marketplace. Claude
Code resolves and installs them automatically when you install `juel` — you don't need to add
them yourself:

- `superpowers`
- `pr-review-toolkit`
- `linear`
- `playwright`
- `context7`

## Prerequisites this plugin cannot install

Several skills shell out to external CLIs that must already be installed and authenticated on
your machine. The plugin cannot install these for you:

- [`gh`](https://cli.github.com/) — GitHub CLI, used for PR creation and review comment fetching.
- [`cmux`](https://github.com/get-convex/cmux) — used by the `cmux-*` skills to spawn and manage
  isolated per-ticket workspaces.
- [`codex`](https://github.com/openai/codex) — dispatched as a sandboxed executor for plan
  implementation and remediation.

## Skills

| Skill | Description |
| --- | --- |
| `start` | Begin work on a ticket inside a worktree: detect the ticket ID, fetch the Linear ticket, analyze requirements, then brainstorm implementation. |
| `execute` | Dispatch Codex (sandboxed, workspace-write) to execute an existing plan, honoring any commit conventions the plan specifies. |
| `review-and-execute` | Run PR review, validate findings, write a remediation plan, then dispatch Codex to execute the fixes. |
| `receive-review-and-execute` | Fetch external PR review comments, validate and clarify ambiguous ones, write a plan, then dispatch Codex to execute fixes. |
| `ship-ticket` | Ship a Linear ticket end-to-end: fetch, brainstorm, spec + plan, dispatch Codex, parallel review + remediation, a final simplify pass, manual verification, then open the PR — pausing for confirmation between phases. |
| `create-linear-ticket` | Create a Linear ticket from a bug report, task, or a TODO discovered while reading code. |
| `daily-worktrees` | Start the day by listing Linear tickets assigned to you and setting up a git worktree per ticket for parallel work. |
| `compact-context` | Snapshot the current conversation into a compaction-style summary under `docs/.superpowers/context/`, so context survives a `/compact` or a fresh session. |
| `cmux-ship-tickets` | Daily kickoff in CMUX: fetch Linear todos, create worktrees, spawn one CMUX workspace per ticket, and auto-launch `claude` running `/juel:ship-ticket` in each. |
| `cmux-review-pr` | Review a GitHub PR (or branch) inside an isolated CMUX workspace: worktree, PR-derived session id, linked Linear ticket for context, `/pr-review-toolkit:review-pr`, then an independent Codex validation pass. |
| `cmux-babysit` | Turn the current session into a manager that monitors N CMUX workspaces, reports which need your input, and relays your replies — so you never switch tabs. |

11 skills today; a 12th is planned for a later phase.

## Commands

| Command | Description |
| --- | --- |
| `/juel:doctor` | Machine audit: for every skill, reports each dependency present / missing / unverifiable against `.claude-plugin/requirements.json`, ending in a runnable / degraded / blocked verdict. The only place in this plugin that runs `claude mcp list` — see the command for why, and for the session-binding caveat that comes with it. |

## License

MIT — see [LICENSE](LICENSE).
