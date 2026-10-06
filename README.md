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

## Install (Codex CLI)

This plugin runs under [Codex CLI](https://developers.openai.com/codex) 0.148.0+ as well as Claude
Code. Codex reads `.codex-plugin/plugin.json` and the same `skills/` tree.

    codex plugin marketplace add jrsgacusan/juel-claude --ref main
    codex plugin add juel@juel-claude
    node scripts/link-agent-skills.mjs

Start a new thread afterwards — that is the boundary at which Codex picks up new skills.

The third command is not optional. Codex has no cross-marketplace dependency resolution, so the
`dependencies` in `.claude-plugin/plugin.json` are ignored and superpowers never arrives on its own.
The script links the superpowers skills and installs the vendored `claude-plan-executor` into
`~/.codex/skills/` as well. `juel:execute`, `juel:review-and-execute`,
`juel:receive-review-and-execute` and `juel:ship-ticket` all hard-depend on the plan executor in
both harnesses and will STOP without it. A pre-existing personal copy at that path is left alone
rather than overwritten; move it aside if you want the vendored symlink. Re-run the script after a
superpowers update; `juel:doctor` reports stale links and an unmanaged plan-executor copy.

The bundled Mobbin MCP server registers automatically on install — it appears in `codex mcp list`
without touching `config.toml`. You still need your own Mobbin plan and a one-time authorization.

### What differs under Codex

Skills are invoked as `$juel:<skill>`, not `/juel:<skill>`. Protocol rule 0 detects the harness and
applies `references/harness-codex.md`, which maps every Claude construct the skills use.

Two things are genuinely weaker, by design rather than oversight:

- **PR review is thinner.** `pr-review-toolkit:review-pr` dispatches six specialist agents in
  parallel; its Codex substitute, `codex review`, is a single pass. `juel:review-pr` says so in its
  report rather than presenting the two as equivalent.
- **The three `cmux-*` skills work under both agents.** They resolve the active agent through
  `resolve_agent`, which supplies the binary, launch flags, prompt syntax and TUI markers. Under
  Codex, `--approve-for-me` is required; without it, an unattended spawned session stalls at its
  first commit.

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
| `receive-review-and-execute` | Merge the PR's base branch in first, then fetch external PR review comments, validate and clarify ambiguous ones, write a plan, then dispatch Codex to execute fixes. |
| `babysit-pr` | Watch your open PR until it is ready to merge: every new human review, inline or conversation comment goes through `receive-review-and-execute`, then gates, push, a reply on every item and a re-requested review (skipped when the PR is already approved); a clean approval ends with the base branch merged in, gates green and a push. Never merges. |
| `ship-ticket` | Ship a Linear ticket end-to-end: fetch, brainstorm, spec + plan, dispatch Codex, parallel review + remediation, Claude-driven end-to-end verification on an isolated local stack (`juel:verify`, screenshots and evidence under docsRoot), then open the PR and babysit it through review with `babysit-pr` until approved and green — pausing for confirmation between phases. |
| `verify` | Verify a change actually works by driving it live through its real runtime surface (CLI, web UI via Playwright, HTTP/RPC handler) — establishes scope from the diff, drives it end-to-end, pushes on adjacent edge cases, and reports PASS / FAIL / BLOCKED / SKIP. Invoked directly, or delegated to from `ship-ticket` Phase 6 for every checklist item with a UI surface. |
| `so-what` | Answer "so what?" for a PR, branch, or session with one plain, copy-pasteable sentence about the outcome for users. |
| `team` | Plan and launch a supervised Orca team of Claude and Codex workers for a goal: discovers the models available right now, picks one per role, shows the roster for approval, then collects every report and synthesizes them blind. Starts only when asked for by name. |
| `create-ticket` | Create a ticket in whatever tracker the project uses (Linear, Jira, GitHub Issues or a spec file, resolved from `.claude/workflow.json` or a `## Work Source` block in CLAUDE.md/AGENTS.md) from a bug report, task, or a TODO discovered while reading code. Scopes the request through `superpowers:brainstorming` first, so the acceptance criteria are unambiguous and grounded in the real codebase before anything is drafted. |
| `daily-worktrees` | Start the day by listing the work items assigned to you (Linear, Jira, GitHub Issues or a spec directory, resolved from the project) and setting up a git worktree per item for parallel work. |
| `compact-context` | Snapshot the current conversation into a compaction-style summary under `docs/.superpowers/context/`, so context survives a `/compact` or a fresh session. |
| `cmux-ship-tickets` | Daily kickoff in CMUX: fetch your open work items, create worktrees, spawn one CMUX workspace per ticket, and auto-launch the resolved agent running the ticket skill in each. |
| `cmux-review-pr` | Workspace plumbing for a PR review: worktree, agent-aware session naming, linked work-item ref, then auto-launch the resolved agent running the review skill inside an isolated CMUX workspace. |
| `review-pr` | Review the current diff, graded against a linked work item when one resolves: `pr-review-toolkit:review-pr` in parallel, requirement-alignment assessment, technically-rigorous finding validation, then a consolidated report with every finding sorted into Confirmed / Rejected / Ambiguous. |
| `orca-ship-tickets` | Ship several work items in parallel through Orca: one Orca worktree per item, agent already running `/juel:ship-ticket`. Fire and forget. |
| `star` | STAR, a permanent coordinator for shipping work across all your projects. It lives in its own git repo (`~/juel-star`), takes work from any session with `/juel:star add`, and has a worker draft a brief per item for your approval. It then runs build, a second-model review, fixes and babysitting through Orca, 3 at a time. Your queue is the "Needs you" block at the top of `open-loops.md`, and every merged PR gets a release record. Workers report in 12 lines or fewer, so STAR's context stays small, and it picks itself up after compaction. You merge. |
| `orca-review-pr` | Review a PR in its own Orca worktree, checked out on the real PR head branch, agent already running `/juel:review-pr`. |

19 skills.

### Orca flow

The `orca-*` skills are the flow being trialed. They drive [Orca](https://www.onorca.dev) instead
of CMUX; the `cmux-*` skills are unchanged and still work.

Four things differ from the CMUX flow, and all four are worth knowing before you use them:

- **Orca owns the checkout.** Worktrees land in `~/orca/workspaces/<repo>/<name>`, not
  `<repo>/.worktrees/`. They are real git worktrees registered with the main repo, so `git` and
  `gh` behave normally.
- **The two flows do not share worktrees.** Orca cannot adopt a checkout it did not create, so an
  existing `.worktrees/` checkout cannot be handed to it. Recreate it through Orca instead.
- **The first spawn into a new location asks twice.** Claude Code's folder-trust and
  bypass-permissions dialogs both default to "No, exit". The skill clears them once, then never
  again for that location.
- **Teardown deletes branches.** `orca worktree rm` removes the checked-out local branch with or
  without `--force`. Move off any branch you want to keep before removing its worktree.

Orca ships its own CLI, which is not on `PATH` — the skills resolve it from the app bundle. Run
`/juel:doctor` for a read on whether Orca is installed, reachable, and knows about this repo.

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
