---
name: ship-ticket
description: Use to ship a Linear ticket end-to-end in one go - fetches ticket, brainstorms, writes spec + plan, dispatches Codex, runs parallel review + remediation, a final simplify polish, then manual verification, then opens the PR. Pauses for confirmation between phases.
---

# Ship Ticket

## Overview

End-to-end orchestration that replaces the manual sequence `/juel:start` → `/juel:execute` → `/juel:review-and-execute` with a single skill. Simplify runs **last**, as the final polish after review remediation, so it cleans up whatever shape the code ends up in rather than producing findings that get rewritten by the review pass.

**Announce at start:** "I'm using juel:ship-ticket to drive SAVI-XXX from ticket to PR."

## Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `[ticket-id]` | auto-detect from worktree | Linear ticket id, e.g. `SAVI-1162` |
| `[base-branch]` | `dev` | Branch to diff/PR against |

Usage: `/juel:ship-ticket` or `/juel:ship-ticket SAVI-1162`

## Phase gating

**Pause for explicit user confirmation between every phase.** Never chain phases automatically. After each phase, summarize what was done and ask: "Proceed to phase N+1: <name>?"

## Workflow

```dot
digraph flow {
    rankdir=TB; node [shape=box];
    p1 [label="1. Start\n(juel:start: detect, fetch, brainstorm)"];
    p2 [label="2. Spec\n(write spec doc)"];
    p3 [label="3. Plan\n(superpowers:writing-plans)"];
    p4 [label="4. Execute\n(codex exec from worktree root)"];
    p5 [label="5. Review + remediation\n(juel:review-and-execute)"];
    p6 [label="6. Simplify (final polish)\n(simplify in apply mode)"];
    p7 [label="7. Manual verification\n(decide FE/BE, verify behavior)"];
    p8 [label="8. Open PR\n(gh pr create with QA instructions)"];
    p1 -> p2 -> p3 -> p4 -> p5 -> p6 -> p7 -> p8;
}
```

### Phase 1 — Start

Invoke `Skill("juel:start")`. It detects the ticket id from the worktree (`basename $(pwd)`), fetches the Linear issue, summarizes requirements, and runs `superpowers:brainstorming`.

If the user passed an explicit ticket id as argument, use that instead of the worktree-detected one.

**Checkpoint:** confirm the chosen approach before writing the spec.

### Phase 2 — Spec

Write a short spec doc capturing the agreed approach from brainstorming.

- Path: `docs/.superpowers/specs/<YYYY-MM-DD>-savi-XXX-<slug>.md` (gitignored, per user memory)
- Contents: problem, chosen approach, scope (in/out), risks, acceptance criteria pulled from the Linear ticket.

**Checkpoint:** show spec path, ask to proceed.

### Phase 3 — Plan

Invoke `Skill("superpowers:writing-plans")` using the spec as input.

- Plan path: `docs/.superpowers/plans/<YYYY-MM-DD>-savi-XXX-<slug>.md`
- Each step must include file paths, line refs where applicable, and a verification command.

**Checkpoint:** show plan path, ask to proceed.

### Phase 4 — Execute

Verify cwd is the worktree root (not `frontend/` or any subdirectory) — Codex sandbox requires this. If not at root, `cd` to it.

Dispatch Codex non-interactively, in the background:

```bash
codex exec --sandbox workspace-write '$claude-plan-executor docs/.superpowers/plans/<plan-file>.md'
```

Wait for Codex to complete.

**Checkpoint:** Codex finished. Summarize files changed (`git status`, `git diff --stat`). Ask to proceed.

### Phase 5 — Review + remediation

Delegate the full review-validate-plan-execute cycle to `/juel:review-and-execute`:

```
Skill("juel:review-and-execute", args: "<base-branch>")
```

That skill internally runs:
1. `pr-review-toolkit:review-pr` against the base branch
2. `superpowers:receiving-code-review` to filter findings with technical rigor
3. `superpowers:writing-plans` → writes to `docs/.superpowers/plans/review-plan.md` (auto-bumps to `-v2`, `-v3`, ... if a prior one exists)
4. `codex exec --sandbox workspace-write` to apply remediation

If the inner skill announces zero actionable findings, remediation is skipped automatically. Continue to phase 6 (simplify still runs) and phase 7 (verification still runs) either way.

After it returns, run `black . --check` and any project-relevant lint/test commands from `CLAUDE.md` to verify nothing regressed.

**Checkpoint:** show diff summary post-remediation. Ask to proceed.

### Phase 6 — Simplify (final polish)

This is the last **planned** code-change phase (phase 7 verification may still loop back if it finds a defect). Run after review remediation so simplify operates on the final shape of the code, not a draft that's about to be rewritten.

1. Invoke `Skill("simplify")` in normal apply mode — let it edit files directly. The skill itself targets recently-modified code, which is what we want.
2. After simplify finishes, re-run `black . --check` and project lint/test commands to verify the polish did not regress anything.
3. Review the simplify diff. If anything looks wrong, revert that specific change with `git restore -p` rather than the whole pass.

**Checkpoint:** show diff summary post-simplify. Ask to proceed to manual verification.

### Phase 7 — Manual verification

Verify the change actually works before opening the PR. This phase is **human-in-the-loop**: do not open the PR on the strength of passing unit tests alone.

1. **Ask the user, explicitly:** "How do we test these changes manually? Do you need anything from me (test account, env var, seed data, a specific org/case, a running service)?" Wait for their answer — they may already know the exact steps.
2. **Decide who drives, based on what changed (`git diff --stat`):**
   - **Frontend / UI** — the user usually verifies in the browser themselves. Offer concrete steps (route, inputs, expected result) derived from the ticket's acceptance criteria, and let them confirm. If the user wants automated help, the `regression` skill (Playwright MCP) is available.
   - **Backend / API** — Claude drives. Invoke `Skill("verify")` to run the app and observe real behavior (hit the endpoint, check the DB, exercise the background task). Ask the user only for inputs you cannot self-serve (credentials, a real org id, a sample upload).
   - **Mixed** — split: Claude verifies the BE surface, the user confirms the FE surface.
3. **Run the actual verification**, capturing evidence (request/response, log lines, screenshots, DB rows). Map each acceptance-criterion to an observed result.
4. If verification surfaces a defect, **do not patch by hand** — loop back to Phase 5 (`/juel:review-and-execute`) or adjust the plan and re-run Phase 4. Re-verify after the fix.

**Checkpoint:** summarize what was verified, who verified it, and the evidence. Ask to proceed to PR.

### Phase 8 — Open PR

1. Push the branch: `git push -u origin <branch>`
2. Create PR with `gh pr create`:
   - Title: `[SAVI-XXX] <short description>` (from Linear ticket title)
   - Body uses HEREDOC (per CLAUDE.md commit/PR rules) and contains:
     - **Summary** — 1-3 bullets of what changed and why
     - **Linear** — link to ticket
     - **QA instructions** — concrete steps a reviewer can follow to validate, derived from the ticket's acceptance criteria
     - **Test plan** — checklist
3. Update the Linear ticket status to "In Review" via `mcp__linear__save_issue`.
4. Return the PR URL to the user.

**No** Co-Authored-By or AI attribution trailers (per CLAUDE.md).

## Failure modes & recovery

| Situation | Action |
|-----------|--------|
| Codex fails in phase 4 | Stop. Show error. Ask user to adjust plan or escalate. Do not run phase 5+. |
| Working tree dirty before phase 4 | Stop. Ask user to commit/stash. |
| Zero actionable findings in phase 5 | `/juel:review-and-execute` handles this internally; still run phase 6 (simplify), phase 7 (verification), and phase 8 (PR). |
| Lint/tests fail after phase 5 | Loop back: invoke `/juel:review-and-execute` again — it will write a `-vN` plan and dispatch Codex. Do not hand-edit. |
| Simplify introduces a regression in phase 6 | `git restore -p` the offending hunks; do not revert the whole pass blindly. |
| Verification finds a defect in phase 7 | Do not hand-patch. Loop back to phase 5 (`/juel:review-and-execute`) or phase 4 (adjust plan, re-run Codex), then re-verify. Do not open the PR until verification passes. |
| User unavailable to verify a FE change in phase 7 | Offer the `regression` skill (Playwright MCP) to verify in their place, or note in the PR body which AC remain manually unverified so the reviewer covers them. |
| Not in a worktree | Ask user; do not auto-create one. |

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Skipping checkpoints to "save time" | Every phase pauses. The point is reviewable handoffs. |
| Running simplify before review remediation | Simplify is the last planned code-change phase (phase 6) so it polishes the final shape of the code, not a draft. |
| Hand-editing instead of delegating remediation | Never. Phase 5 delegates to `/juel:review-and-execute`; do not bypass it. |
| Dispatching Codex from `frontend/` or another subdir | Always cd to worktree root first. |
| Skipping `git status` review between phases | Each checkpoint must show what changed. |
| Opening the PR on green unit tests alone | Phase 7 requires observed behavior, not just passing tests. Verify the real surface first. |
| Posting PR review-style summary instead of QA-oriented body | Phase 8 PR body is for the reviewer, not a changelog. |
| Forgetting to update Linear status | Phase 8 step 3. |

## Notes

- Spec/plan/findings files live under `docs/.superpowers/` (gitignored) per user memory.
- Branch naming: `feat/savi-xxx-<slug>` or `fix/savi-xxx-<slug>` (CLAUDE.md).
- Commit messages must include the ticket id as scope, e.g. `feat(SAVI-1162): ...` (user memory).
- For dependent tickets: branch from the parent tip, do not rebase (user memory).
