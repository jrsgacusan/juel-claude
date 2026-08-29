# Harness adapter — Codex

**Read this only if you do not have the `TaskCreate` tool.** If you do have it, you are in Claude
Code, this file does not apply, and rule 0 has already told you to ignore it.

This plugin's skills are written against Claude Code. Everything below translates them for Codex
CLI. Apply it to every rule in the Strict Execution Protocol and to every phase body in the skill
you are running.

## 1. Construct map

| Claude Code | Codex | Notes |
| --- | --- | --- |
| `TaskCreate` | `update_plan` | One plan item per phase. The plan IS the checklist rule 1 demands. |
| `TaskUpdate` | `update_plan` | Rewrite the plan with the item's new status; there is no separate update call. |
| `Skill` | `$<skill-name>` | Explicit invocation. Plugin skills are namespaced `juel:<skill>`; skills under `~/.agents/skills/` are not namespaced. |
| `Agent` | `spawn_agent` | Then `wait` for the result. `list_agents` enumerates in-flight agents. |
| `ListAgents` | `list_agents` | Same purpose: confirm whether a dispatch produced a result before concluding it returned nothing. |
| `AskUserQuestion` | prose question | Ask in prose, one question at a time, and wait for the answer. Do not fabricate an answer to keep going. |
| `Monitor` | none | Rule 4 already forbids attaching one to `codex exec`, so there is nothing to translate. |
| `Write` | shell heredoc | Codex has no separate Write tool; use `cat > path <<'EOF'`. Quote the delimiter so `${...}` is not expanded. |

## 2. Corrected facts

These protocol statements are **false** in Codex, not merely spelled differently. Apply the
correction, not a rename.

- **Rule 4's 600s Bash cap does not exist here.** Codex's shell tool has no 10-minute ceiling, so
  the reason `codex exec` must be backgrounded in Claude Code does not apply. Run it in the
  foreground and read its output directly. Everything else in rule 4 still holds: never redirect
  output to a log file, and state the outcome before marking the phase done.
- **Rule 4's "the Skill/Agent tool carries no such cap" is meaningless here** because there is no
  cap to contrast against. Ignore that clause.
- **The permission model is different.** There is no `--permission-mode auto`. Codex sandboxes by
  default and escalates per command via `require_escalated` plus persisted prefix rules. A skill
  that tells you to pass a permission mode to a nested agent cannot be followed literally; request
  escalation for the specific command instead, and say so in one line.
- **Rule 1's `TaskCreate` fallback still applies**, keyed on `update_plan` instead. If `update_plan`
  genuinely fails — one attempted call returning an error, never assumed in advance — fall back to
  an explicit numbered phase log and state the degradation once.

- **Whether a sandboxed executor can commit depends on config - check, do not assume.** Under
  `--sandbox workspace-write`, `.git` is a documented protected path: recursively read-only,
  including a worktree's `.git` pointer file and the `gitdir:` target it resolves to.
  `writable_roots` does not override it, and no per-repo property changes it - path depth, trust
  entries, filesystem attributes and git history were each ruled out by probe.

  The denial is meant to be escalated past, not avoided. The runner re-requests the command with
  `require_escalated` and an approver decides. Who approves comes from `approvals_reviewer` in
  `~/.codex/config.toml`, whose accepted values are `user`, `auto_review` and `guardian_subagent`:

  | `approvals_reviewer` | Interactive TUI | Non-interactive `codex exec` |
  | --- | --- | --- |
  | `user` (the default) | prompts the human, who approves - commits work | **nobody to ask - commits fail** |
  | `auto_review` / `guardian_subagent` | auto-approved | auto-approved - commits work |

  This is why the same repo commits fine by hand and fails under automation. It is not repo-specific.

  **Detect it before a commit phase, not during one:**

  ```bash
  grep -E '^approvals_reviewer' "${CODEX_HOME:-$HOME/.codex}/config.toml" || echo 'approvals_reviewer = "user"  # default'
  ```

  Do not try to detect this from `codex debug prompt-input` - the permission profile is
  byte-identical whether commits succeed or fail, so it tells you nothing.

  Practical consequence for `juel:execute` and `juel:review-and-execute`: if the reviewer is `user`
  and you are non-interactive, either the caller passes `--approve-for-me` for that run, or the
  executor works author-only and the commits are made outside the sandbox. State which mode you are
  in, in one line, rather than discovering it when a commit phase dies.

## 3. Dependency substitutions

| Skill depends on | Use instead | Contract |
| --- | --- | --- |
| `code-simplifier` | `$simplify` | SOFT. Present in `~/.agents/skills/`. If absent, skip the polish phase and say so. |
| `pr-review-toolkit:review-pr` | `codex review` | SOFT, **and a downgrade.** See below. |
| `superpowers:brainstorming` | `$brainstorming` | HARD. Unnamespaced. If absent, STOP and point at `scripts/link-agent-skills.mjs`. |
| `superpowers:writing-plans` | `$writing-plans` | HARD. Unnamespaced. Same remedy. |
| `superpowers:receiving-code-review` | `$receiving-code-review` | HARD. Unnamespaced. Same remedy. |

**The reviewer substitution is a genuine downgrade, and you must say so in your report.**
`pr-review-toolkit:review-pr` dispatches six specialist agents in parallel. `codex review` is a
single-pass reviewer. A Codex review of a diff is thinner than a Claude Code review of the same
diff. State this in the findings report rather than presenting the result as equivalent coverage.
Rule 4's PARALLEL requirement has nothing to dispatch in parallel here; it does not apply.

The superpowers skills are unnamespaced because Codex treats each direct child of
`~/.agents/skills/` as one skill and does not recurse into a directory of skills.

## 4. Degradation contract

Reuse the HARD/SOFT vocabulary from `references/preflight.md` exactly as written:

- **HARD dependency, substitute missing** → STOP. Print the preflight block with the STOP verdict
  and the remedy. Do not begin work and do not improvise a replacement.
- **SOFT dependency, substitute missing** → degrade, state the degradation in one line, continue.
- **Unverifiable** → render `?`, treat as present, never block on it.

A substitution that is itself a downgrade (the reviewer, above) is **not** a degradation for
preflight purposes — the dependency is satisfied. It is a reporting obligation, discharged in
the skill's own output.
