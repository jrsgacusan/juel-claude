---
name: claude-plan-executor
description: Use when executing an implementation plan authored elsewhere, especially a Claude-created plan provided as a resource, attached artifact, or pasted markdown, and Codex should preserve the plan's sequencing, scope, and acceptance criteria while filling in missing engineering detail.
---

# Claude Plan Executor

## Overview

Consume a Claude-authored plan and turn it into completed work. Read the plan artifact first, extract its concrete tasks, then execute them with Codex while preserving scope, order, and acceptance criteria.

Use the model this session is already configured with. Do not pin a specific model id here - the
strongest available model changes, and a hard-coded id silently becomes a downgrade. If a plan
names a model explicitly, that instruction wins.

This skill is self-contained. Do not require another skill to execute or verify the plan.

## Inputs

Accept any of these as the plan source:

- An MCP resource URI that contains the plan
- A local file path to a markdown or text plan
- Pasted markdown in the user message
- A quoted plan block inside the request

If the plan source is ambiguous, resolve the artifact first before doing implementation work. If a resource is named but not included, ask for the missing resource instead of guessing.

For the expected plan shape and invocation examples, read `references/plan-contract.md`.

Before execution, discover and read every `AGENTS.md` and `CLAUDE.md` in scope for the affected
repo paths. Precedence, highest first: a direct instruction in the request; the most deeply nested
file covering the path being edited; then shallower files up to the repo root. `AGENTS.md` and
`CLAUDE.md` at the same depth are read as one combined set, not ranked against each other - if
they genuinely conflict, say so and ask rather than silently picking one. Many repos ship only one
of the two; that is normal and not a problem to report.

## Workflow

1. Load the plan artifact completely before proposing changes.
2. Discover the relevant `CLAUDE.md` files for the repo root and any affected subtrees, then read them before translating the plan into implementation work.
3. Extract:
   - goal
   - ordered steps
   - constraints
   - deliverables
   - validation requirements
   - open questions
4. Normalize the plan into a concrete execution checklist.
5. Keep the original plan's intent. Only refine steps where the plan is vague, technically incorrect, or missing dependencies.
6. Choose an execution mode:
   - Execute sequentially when tasks are coupled, ordered, or depend on ongoing discovery.
   - Delegate independent, well-bounded tasks in parallel only when suitable subagent tools are available.
   - Execute directly when delegation would add coordination overhead or no subagent tools are available.
7. Execute the work directly. Do not stop at summarizing the plan unless the user asked only for analysis.
8. Validate the result against every explicit acceptance criterion using relevant tests, checks, inspections, or screenshots.
9. Report:
   - what was completed
   - any deviations from the plan
   - what remains blocked or undecidable

## Execution Rules

- Treat the Claude plan as authoritative for sequencing and scope, not as infallible on implementation details.
- Always read and apply any relevant `CLAUDE.md` files before executing the plan. If multiple files apply, prefer the most specific file for the affected subtree while still honoring higher-level guidance that does not conflict.
- Preserve stated constraints unless they are impossible or harmful.
- Call out contradictions early and resolve them before broad edits.
- Prefer making progress over re-planning. Re-plan only when the plan is underspecified or blocked by new facts.
- If the plan includes phases, execute phase by phase and verify each phase before moving on when feasible.
- Keep the critical path local when the next decision depends on discovery, integration, or close coordination, even if other branches are delegated.
- When delegating, give each subagent a narrow ownership boundary. Let subagents inherit the
  session's model rather than naming one; `default_subagent_model` in `~/.codex/config.toml` is
  the place to override that, not this file.
- Treat delegated output as input to review, not as automatically accepted work. Inspect and integrate it before validation.
- Preserve the plan structure and validation requirements whether the work is delegated or executed directly.
- Before claiming completion, map the implemented result back to each acceptance criterion and report any criterion that could not be verified.

## Commit contract

- **A plan's commit steps are instructions, not decoration.** If a task ends with a `git commit`,
  run it. Do not batch several tasks into one commit, and do not skip a commit because the next
  task is about to touch the same file.
- **Use the plan's commit message verbatim** when it supplies one. If the plan states a commit
  convention, follow it. If it states none, do not invent one.
- **`.git` is a protected path under `--sandbox workspace-write`.** A commit only succeeds if the
  escalation is approved, and who approves is set by `approvals_reviewer` in
  `~/.codex/config.toml`: `user` means an interactive session prompts a human, and a
  non-interactive run has nobody to ask, so the commit fails with
  `Unable to create '.git/index.lock': Operation not permitted`. `auto_review` and
  `guardian_subagent` auto-approve and commits succeed.
- **When commits are denied, do not work around it.** Do not disable the sandbox, do not retry in
  a loop, and do not silently continue as if the commit happened. Make the file changes, then
  state in one line: `commits unavailable in this sandbox (approvals_reviewer=user,
  non-interactive) - N tasks are staged but uncommitted`. The caller commits them.
- **Never push, never tag, never bump a version** unless a plan step says to in those words.
  Pushing a tag is irreversible and is never implied by "execute the plan".

## Evidence before completion

- **Run the command, read the output, then make the claim.** A criterion is verified when you have
  fresh output in this run showing it passes. Not when the code looks right, not when it passed
  earlier, not when a subagent reported success.
- **Quote the evidence** - the command and the decisive line of its output - next to each criterion
  you claim. One line each is enough; a transcript is not wanted.
- **A subagent reporting success is not evidence.** Check the working tree or the command output
  yourself before accepting delegated work.
- **When a criterion cannot be verified, say so explicitly** and name what blocked it. An
  unverifiable criterion reported as passing is worse than a failed one, because it is invisible.

## Progress protocol

- Plans use `- [ ]` checkbox steps. Work them **in order**, one at a time. Do not batch a task's
  steps into a single action, and do not start task N+1 before task N's final step is done.
- Report per task, not per plan: what changed, the evidence, and anything skipped with the reason.
- **A plan's `## Global Constraints` section is binding on every task**, whether or not a given
  task repeats it. A step that succeeds while violating a Global Constraint is a failed step.
  Constraints about what must never be touched - gitignored paths, version numbers, tags - are the
  ones most often violated by accident.
- **A task marked BLOCKED BY TASK N does not start until task N is done.** If task N could not be
  completed, stop and report rather than proceeding on assumed values.

## Plan Translation Heuristics

- Convert narrative instructions into explicit tasks with owners, artifacts, and checks.
- Expand vague verbs like "wire up", "finish", or "support" into concrete code or design changes before editing.
- Separate discovery tasks from write tasks.
- Convert validation lines into actual commands, tests, screenshots, or inspections.
- Preserve non-functional requirements such as performance, accessibility, migration safety, or multi-tenant isolation.

## Failure Handling

- If the plan references missing files, missing resources, or unavailable tools, say exactly what is missing.
- If no `CLAUDE.md` files exist in scope, continue normally.
- If the affected path is unclear, read the repo-root `CLAUDE.md` first and add deeper scoped `CLAUDE.md` files once the relevant subtree is known.
- If the plan conflicts with the codebase or runtime reality, explain the conflict and propose the narrowest correction.
- If the plan cannot be completed in one pass, finish the highest-value subset and state what remains.
- If the requested execution pattern conflicts with repository instructions or available tools, call out the conflict and use the narrowest compliant alternative.

## Non-goals

- **Do not expand scope.** Implement what the plan's acceptance criteria require and nothing else.
  A migration, a config change, or a cap that the plan did not ask for is out of scope even when it
  looks obviously needed. Propose it in the report instead.
- **Do not re-plan.** Refine a step that is vague, technically wrong, or missing a dependency; do
  not redesign the approach because a different one seems better.
- **Do not touch files the plan marks as out of scope**, including gitignored scratch directories
  that hold the plan and spec themselves.

## Output Style

- Be concise.
- Lead with execution, not a restatement of the full plan.
- Mention deviations only when they matter.
- Include verification results when available.

## Quick Invocation

Use prompts like:

- `Use $claude-plan-executor with this Claude plan resource and implement it.`
- `Use $claude-plan-executor on the attached plan markdown and execute phase 1.`
- `Use $claude-plan-executor to turn this Claude plan into completed code changes and verification.`
