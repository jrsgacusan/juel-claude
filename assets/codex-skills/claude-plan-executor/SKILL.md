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
8. Validate the result against every explicit acceptance criterion using the tests, checks, inspections or screenshots the plan names.
9. Report:
   - what was completed
   - any deviations from the plan
   - what remains blocked or undecidable
   - notes: anything outside the tasks' `**Files:**` blocks that looks wrong, never fixed

## Execution Rules

- Run only the commands the plan names: never run the full test suite, the repository's whole test loop or a build on your own. A heavy step the plan names runs exactly as the plan writes it (through `gate-lock.sh` when it says so); the caller runs the full gates itself, under its lock.
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
- **Never `git add -f` (`--force`).** A path the repository ignores is never committed, even when
  a plan step says to commit it: leave it on disk and say in the task's report
  `not committed: <path> is git-ignored`. Before each `git commit`, run
  `git diff --cached --no-renames --name-only --diff-filter=A | git check-ignore --no-index --stdin`;
  for each path it prints, `git rm --cached -q -- <path>` (the file stays on disk), then commit.
- **A planned path that is git-ignored fails its task.** When a `not committed:` path is one a
  task's `**Files:**` block names, or lies under a folder one names, commit the rest of the task
  as the plan says, then fail the task: do not append its ledger line, do not start the next task,
  and end the run with this line in the report, the part in brackets being what
  `git check-ignore -v --no-index -- <path>` prints before the tab:
  `task <N> failed: planned file <path> is git-ignored (<source>:<line>:<pattern>)`.
  Never move or rename the file, or edit an ignore file, to get it committed: the caller decides.
  This holds over "finish the highest-value subset" in Failure Handling.
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
- **Keep a ledger, and resume from it.** The ledger is
  `<repo root>/.superpowers/sdd/<plan file name without .md>/progress.md`, where `<repo root>` is
  `git rev-parse --show-toplevel`. It is the file `superpowers:executing-plans` keeps, in the same
  format, so a run on the fallback model or in a Claude session resumes from the same record.
  - At start, if the ledger's first line names this plan file, every task with a
    `Task <N>: complete` line is done: do not redo it. Start at the first task without one.
    Before editing, check that task's state: a run stopped by a capacity error may have left it
    half applied. Finish it, and never apply its edits a second time.
  - With no ledger, or one whose first line names another plan file, start a fresh one whose
    first line is `# SDD ledger — plan: <plan file path>` (superpowers' literal, dash included).
  - Right after the task's commit, before the next task's first step, append one line, `<a7>` and
    `<b7>` being `HEAD` before and after the task:
    `Task <N>: complete (commits <a7>..<b7>, tests: <command> → <result>)`. Never hold the lines
    back for the end of the plan: a run that a capacity error or a kill stops resumes from them.
    When the sandbox denies commits, append
    `Task <N>: complete (uncommitted, tests: <command> → <result>)` as soon as the task's
    verification passes instead.
  - `<N>` is the number in the task's `### Task <N>` heading. The ledger is git-ignored scratch,
    and the one scratch file you write: never commit it.
- **A plan with a `**Base:**` line is a delta.** Its header says
  `**Base:** spec implemented at <sha>; apply only the tasks below.`: the spec it names is already
  implemented. Apply the tasks. Do not judge the spec for completeness, and never stop because the
  spec, or the work as a whole, already looks implemented.

## Plan Translation Heuristics

- Convert narrative instructions into explicit tasks with owners, artifacts, and checks.
- Expand vague verbs like "wire up", "finish", or "support" into concrete changes inside the files, functions and line ranges the task's `**Files:**` block names, never into files it does not name.
- Separate discovery tasks from write tasks.
- Convert validation lines into the commands, tests, screenshots or inspections they name, never into a full-suite run or a build the plan does not write out.
- Preserve non-functional requirements such as performance, accessibility, migration safety, or multi-tenant isolation.

## Failure Handling

- If the plan references missing files, missing resources, or unavailable tools, say exactly what is missing.
- If no `CLAUDE.md` files exist in scope, continue normally.
- If the affected path is unclear, read the repo-root `CLAUDE.md` first and add deeper scoped `CLAUDE.md` files once the relevant subtree is known.
- If the plan conflicts with the codebase or runtime reality, explain the conflict and propose the narrowest correction. Two things are not conflicts: on a resumed run, a task whose edits are already in the worktree (verify it and mark it complete, see "Progress protocol"); and, in a plan with a `**Base:**` line, a spec that is already implemented (apply the tasks anyway).
- If the plan cannot be completed in one pass, finish the highest-value subset and state what remains.
- If the requested execution pattern conflicts with repository instructions or available tools, call out the conflict and use the narrowest compliant alternative.

## Non-goals

- **Change only what each task's `**Files:**` block names**: those files, and inside them the
  functions or line ranges it gives. Imports, and the call sites of a symbol the task renames, are
  part of the task. Anything else you believe is wrong, however near, goes under a `Notes:` heading
  in your report, never into the diff. The caller reverts every changed file no block names.
- **Do not expand scope.** Implement what the plan's acceptance criteria require and nothing else.
  A migration, a config change, or a cap that the plan did not ask for is out of scope even when it
  looks obviously needed. Propose it in the report instead.
- **Do not re-plan.** Refine a step that is vague, technically wrong, or missing a dependency; do
  not redesign the approach because a different one seems better.
- **Do not touch files the plan marks as out of scope**, including gitignored scratch directories
  that hold the plan and spec themselves. The ledger (see "Progress protocol") is the one scratch
  file you write.

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
