# Workspace driver — authoring source of truth

This file is **not** read at runtime. It exists so that the things which differ between
driving a CMUX workspace and driving an Orca worktree live in one place, instead of being
re-derived in each `orca-*` skill.

Unlike `references/agent-driver.md`, there is no runtime `resolve_workspace` helper: Orca and
CMUX do not share a seam, because Orca owns the checkout itself (see §5, finding 7). The two
flows are separate skills by design. This file is the Orca half's command surface, its
verified behavior, and the ways it degrades.

## 1. Resolving the binary

```sh
# orca is NOT on PATH on macOS; the app ships it inside the bundle.
ORCA=$(resolve_bin orca /Applications/Orca.app/Contents/Resources/bin/orca)
[ -n "$ORCA" ] || { echo "orca not found on PATH or any candidate location"; exit 1; }
```

The bundle path is a labelled candidate tried after `PATH`, never a value inlined into an
executable line — a non-default install location or a Linux host turns an inlined path into a
silent no-op. `scripts/validate.mjs` check 15 (`orca-driver`) enforces this.

## 2. Discovery — never guess a flag

| Need | Command |
| --- | --- |
| Machine-readable schema for every command (usage, flags, notes, examples) | `orca agent-context --json` |
| Version-matched prose guide | `orca skills get orca-cli` |

The installed CLI carries 234 commands at schema v1. Both sources ship *with the app*, so they
describe the CLI actually installed rather than the one the docs site describes. Read one of
them before using a flag this file does not list.

## 3. Selector grammar

Most commands take a `--worktree <selector>`:

| Selector | Meaning |
| --- | --- |
| `active` | The worktree Orca currently has focused |
| `path:<absolutePath>` | By checkout path |
| `id:<repoId>::<worktreePath>` | The full two-part id |
| `name:<displayName>` | By display name |
| `branch:<branchName>` | By checked-out branch |
| `issue:<number>` | By linked issue |

The `id:` form is copied verbatim from `worktree create --json` or `worktree list --json`.
`repoId` alone identifies only the repo, never a worktree.

## 4. The primitive table

| Need | Command |
| --- | --- |
| Runtime readiness | `orca status` (`runtimeReachable`, `graphState`) — **text form**, see below |
| Repo id | `orca repo list`, register with `orca repo add` |
| Create worktree + agent + prompt | `orca worktree create --repo id:<id> --name <n> --agent claude --prompt "<text>" --no-parent --json` |
| Agent handle | `result.agentTerminalHandle`, else `result.startupTerminal.handle` |
| Extra tab | `orca terminal create --worktree <sel> --title <t> --command "<cmd>" --json` |
| Read rendered screen | `orca terminal read --terminal <h> --screen --json` |
| Send text / keys | `orca terminal send --terminal <h> --text "<t>"`, `--enter`, `--interrupt` |
| Wait | `orca terminal wait --terminal <h> --for tui-idle --timeout-ms <ms>` |
| Board status | `orca worktree set --worktree <sel> --workspace-status in-progress --comment "<text>"` |
| Teardown | `orca worktree rm --worktree <sel> --force` |

`terminal read` defaults to accumulated stream output, in which a repainted line comes back as
stacked fragments. Pass `--screen` whenever the answer depends on what the terminal *renders*.

**`status` is the one command to read in its text form.** `runtimeReachable` and `graphState` are
flat keys only there; `--json` nests them as `result.runtime.reachable` and `result.runtime.state`.
Grepping the text key against `--json` reports every reachable runtime as unreachable — silently,
since both forms exit 0. Every other command in this table is read as `--json`.

## 5. Verified behavior

Probed against a live Orca on 2026-09-09. Each finding carries the consequence that makes it
load-bearing; a future editor must be able to see why the skills are shaped this way without
re-probing.

1. **Worktree path** — `worktree create --name <n>` checks out to
   `~/orca/workspaces/<repo>/<n>`, not `<repo>/.worktrees/<n>`. It is a real git worktree,
   registered in the main repo's `git worktree list`, so `git` and `gh` behave normally.
   *Consequence:* nothing in an `orca-*` skill may assume the `.worktrees/` layout.
2. **Branch naming** — the created branch is `<repo.gitUsername>/<name>`, e.g.
   `mstr-juel/MSTR-4147`. `gitUsername` comes from `orca repo show --json`; no flag overrides
   it. A post-create `git -C <path> branch -m <name>` **is** picked up by Orca, which reads git
   rather than owning the name.
   *Consequence:* the plugin's own `branchPattern` is restored by renaming after create.
3. **Orca's view of git is eventually consistent** — after `git -C <path> branch -m` (or a
   `checkout`), the very next `worktree show` can still report the *old* branch; a second read
   moments later reports the new one. Observed twice: a read after a ~2s gap was correct, a read
   issued immediately was stale.
   *Consequence:* never assert on `worktree show` in the same breath as the git command that
   changed it. Read git for the authoritative answer (`git -C <path> rev-parse --abbrev-ref HEAD`),
   and re-read Orca's view before reporting a mismatch as a failure.
4. **Setup hooks may copy nothing** — `repo show` reports `hookSettings.scripts.setup: ""` for
   a repo with no configured hook, and `--setup run` is then a no-op. A probe worktree
   contained no `.claude/` and no `.env`.
   *Consequence:* untracked provisioning stays the plugin's job, via `copy_untracked` from
   `references/resolution.md`. Orca hooks are the optional upgrade, not the mechanism.
5. **Agent launch** — `worktree create --agent claude --prompt "<text>"` returns
   `result.agentTerminalHandle` and delivers the prompt once the TUI is ready. Orca launches
   Claude with `--dangerously-skip-permissions`.
   *Consequence:* no readiness polling, no separate Enter keystroke, and no argv seam is needed
   for unattended permission mode.
6. **First-run dialog gauntlet** — a spawn into a never-trusted path stops on two sequential
   dialogs: folder trust, then bypass-mode consent. **Both default to `No, exit`**, so a blind
   Enter kills the session. `terminal send --text $'\x1b[B'` moves the selection and
   `terminal send --enter` confirms. After clearing them once, a fresh worktree spawned clean.
   The queued `--prompt` survives both dialogs.
   *Consequence:* the gauntlet is a bounded, self-disabling phase, not per-ticket polling.
7. **Orca cannot adopt foreign checkouts** — `terminal create --worktree path:<a plain git
   worktree>` returns `selector_not_found`. Such a worktree is also absent from
   `worktree list`, and `worktree current` run from inside it answers with the *main* repo
   worktree rather than erroring. The repo record carries
   `externalWorktreeVisibility: "hide"`, and no CLI command sets it.
   *Consequence:* `.worktrees/` and Orca are mutually exclusive. There is no fallback that
   reuses an existing checkout; recreate through Orca instead.
8. **Existing branches** — `--base-branch <ref>` cuts a *new* branch from that ref rather than
   checking it out. A post-create `git -C <path> checkout <ref>` is tracked by Orca.
   *Consequence:* a review worktree reaches the real PR head by checking out after create.
9. **Removal deletes branches** — `worktree rm` "attempts to delete the checked-out local
   branch, with or without `--force`".
   *Consequence:* move a review worktree off the PR head branch before removing it, or the
   local copy of that branch is deleted with the worktree.
10. **Linear may be disconnected in Orca** — `orca linear list-issues` can return
   `linear_not_connected` with an empty `linear team list`, while `--linear-issue <REF>` still
   links offline and comes back as `linkedLinearIssue` in `worktree list --json`.
   *Consequence:* selection goes through the work-source layer; `orca linear` is a gated
   optional path, checked with `orca linear team list` before use.

## 6. Degradations

- **Stale handle.** A handle that returns `terminal_handle_stale` is reacquired via
  `orca terminal list --worktree <sel> --json`, and the run continues with the replacement
  only. Never dual-send to the old and new handles.
- **Older CLI.** One that rejects `--agent`, `--prompt` or `--setup` degrades to
  `orca terminal create --worktree <sel> --command "<AGENT_BIN> <AGENT_LAUNCH_FLAGS>"` followed
  by `orca terminal send`. This is also the path taken deliberately when a repo needs untracked
  files in place before the agent's first input.
- **No foreign checkout.** Per §5 finding 7 there is no degradation that reuses
  `<repo>/.worktrees/`. A skill that cannot create an Orca worktree stops and says so.

## 7. Adding a second workspace driver

Add a column to §4's primitive table, a row to §6, and a findings block to §5 recording what
was actually probed rather than what the vendor's docs claim. If a skill needs an axis this
file does not list, add the axis here first rather than special-casing it in that skill.
