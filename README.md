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

**The installed plugin cache is version-gated, not commit-gated.** Claude Code caches an
installed plugin on disk at `<config-dir>/plugins/cache/juel-claude/juel/<version>/`. A `git push`
to this repo that does not also bump `plugin.json`'s `version` leaves that cache directory
untouched — `claude plugin marketplace update` will refresh the marketplace listing, but
`claude plugin update juel@juel-claude` will report "already at the latest version" and keep
serving the old cache contents. This bit this project three times during development. If you
update and don't see new content, check `claude plugin details juel` for the version and skill
count you expect; if it's stale, force a fresh pull with:

    /plugin uninstall juel@juel-claude
    /plugin install juel@juel-claude

## Prerequisites

### Install automatically

This plugin declares five dependencies from the `claude-plugins-official` marketplace. Claude
Code resolves and installs them automatically when you install `juel` — you don't need to add
them yourself:

- `superpowers`
- `pr-review-toolkit`
- `linear`
- `playwright`
- `context7`

### You must install yourself

Several skills shell out to external CLIs that must already be installed and authenticated on
your machine. The plugin cannot install these for you:

- [`gh`](https://cli.github.com/) — GitHub CLI, used for PR creation and review comment fetching.
- [`cmux`](https://github.com/get-convex/cmux) — used by the `cmux-*` skills to spawn and manage
  isolated per-ticket workspaces.
- [`codex`](https://github.com/openai/codex) — dispatched as a sandboxed executor for plan
  implementation and remediation.

### Bundled MCP server (requires your own Mobbin plan)

This plugin's `.mcp.json` registers the [Mobbin MCP server](https://mobbin.com/mcp)
(`search_screens` / `search_flows` / `search_sections` over Mobbin's library of real shipped UI)
so it's available for design-reference lookups during UI work — no skill here depends on it, it's
just there to use ad hoc. It starts automatically when the plugin is enabled, but two things are
on you:

- **A Mobbin Pro, Team, or Enterprise plan** — the server is gated behind a paid subscription.
- **One-time OAuth** — run `/mcp`, select `mobbin`, choose Authenticate, and sign in when the
  browser opens.

## Skills

| Skill | Description |
| --- | --- |
| `start` | Begin work on a ticket inside a worktree: detect the ticket ID, fetch the Linear ticket, analyze requirements, then brainstorm implementation. |
| `execute` | Dispatch Codex (sandboxed, workspace-write) to execute an existing plan, honoring any commit conventions the plan specifies. |
| `review-and-execute` | Run PR review, validate findings, write a remediation plan, then dispatch Codex to execute the fixes. |
| `receive-review-and-execute` | Fetch external PR review comments, validate and clarify ambiguous ones, write a plan, then dispatch Codex to execute fixes. |
| `ship-ticket` | Ship a Linear ticket end-to-end: fetch, brainstorm, spec + plan, dispatch Codex, parallel review + remediation, a final code-simplifier pass, Claude-driven end-to-end verification (`juel:verify`), then open the PR — pausing for confirmation between phases. |
| `verify` | Verify a change actually works by driving it live through its real runtime surface (CLI, web UI via Playwright, HTTP/RPC handler) — establishes scope from the diff, drives it end-to-end, pushes on adjacent edge cases, and reports PASS / FAIL / BLOCKED / SKIP. Invoked directly, or delegated to from `ship-ticket` Phase 7 for every checklist item with a UI surface. |
| `create-linear-ticket` | Create a Linear ticket from a bug report, task, or a TODO discovered while reading code. |
| `daily-worktrees` | Start the day by listing Linear tickets assigned to you and setting up a git worktree per ticket for parallel work. |
| `compact-context` | Snapshot the current conversation into a compaction-style summary under `docs/.superpowers/context/`, so context survives a `/compact` or a fresh session. |
| `cmux-ship-tickets` | Daily kickoff in CMUX: fetch Linear todos, create worktrees, spawn one CMUX workspace per ticket, and auto-launch `claude` running `/juel:ship-ticket` in each. |
| `cmux-review-pr` | Workspace plumbing for a PR review: worktree, PR-derived session id, linked work-item ref, then auto-launch `claude` running `/juel:review-pr` inside an isolated CMUX workspace. |
| `review-pr` | Review the current diff, graded against a linked work item when one resolves: `pr-review-toolkit:review-pr` in parallel, requirement-alignment assessment, technically-rigorous finding validation, then a consolidated report with every finding sorted into Confirmed / Rejected / Ambiguous. |
| `cmux-babysit` | Turn the current session into a manager that monitors N CMUX workspaces, reports which need your input, and relays your replies — so you never switch tabs. |

13 skills.

## Commands

| Command | Description |
| --- | --- |
| `/juel:doctor` | Machine audit: for every skill, reports each dependency present / missing / unverifiable against `.claude-plugin/requirements.json`, ending in a runnable / degraded / blocked verdict. The only place in this plugin that runs `claude mcp list` — see the command for why, and for the session-binding caveat that comes with it. Also reports the plugin's cache location and warns if a newer version sits in the cache than the one this session loaded (see "Update" above). Run it any time you want a read of what this plugin can and can't do on the current machine — it changes nothing itself. |

## Configuration — `.claude/workflow.json` (optional)

Every skill in this plugin auto-detects a repo's conventions — its base branch, install/test/lint
commands, branch naming, commit style, docs layout, and more — from evidence already in the repo
(manifests, git history, `.github/` templates). **You never have to create this file.** A repo
with no config behaves the same as one with every field filled in by hand, wherever that
detection is actually possible.

`.claude/workflow.json` exists only to override auto-detection when you want to pin something
explicitly instead of letting it be inferred — e.g. a monorepo where the "obvious" command isn't
the one you want, or a tracker whose ref pattern needs disambiguating from another tenant's. An
untracked `.claude/workflow.local.json`, if present, deep-merges over it key-by-key for anything
personal you don't want committed (local wins). Every field is optional; set only what you need
to pin.

Worked example — pinning explicit toolchain commands and a Jira status map in a repo where
auto-detection would otherwise guess wrong:

```jsonc
// .claude/workflow.json
{
  "commands": {
    "install": "pnpm install",
    "test": "pnpm test:ci",
    "lint": "pnpm lint",
    "typecheck": "pnpm typecheck",
    "run": "pnpm dev"
  },
  "baseBranch": "develop",
  "branchPattern": "{type}/{ticket-lower}-{slug}",
  "commitStyle": "conventional-ticket",
  "tracker": {
    "type": "jira",
    "project": "SAVI",
    "statusMap": { "todo": "To Do", "in_progress": "In Progress", "done": "Done" },
    "refPattern": "^SAVI-"
  },
  "executor": "codex"
}
```

A malformed file, an unrecognized key, or a configured command whose binary doesn't resolve is
never fatal — each falls through to auto-detection for just that field, with a warning, never an
abort.

## Rollback

Task 28 of this plugin's build plan retires the pre-plugin, hand-maintained originals these
skills replace. Before that happens, they're backed up (not deleted) to
`~/.claude/skills-backup-<date>/`.

If `juel@juel-claude` misbehaves and you need your old skills back:

1. Move the contents of `~/.claude/skills-backup-<date>/` back to where your skills previously
   lived (`~/.claude/skills/`).
2. Uninstall the plugin: `/plugin uninstall juel@juel-claude`.
3. Restart Claude Code.

Only delete the backup once you're confident you no longer need to roll back — there's no
automatic expiry on it, and nothing in this plugin deletes it for you.

## License

MIT — see [LICENSE](LICENSE).
