---
name: claude-plan-executor
description: Use when executing an implementation plan authored elsewhere, especially a Claude-created plan provided as a resource, attached artifact, or pasted markdown, and Codex should preserve the plan's sequencing, scope, and acceptance criteria while filling in missing engineering detail.
---

# Claude Plan Executor

## Overview

Consume a Claude-authored plan and turn it into completed work. Read the plan artifact first, extract its concrete tasks, then execute them with Codex while preserving scope, order, and acceptance criteria.

Prefer the strongest Codex model available in the current environment. In this environment, use `gpt-5.4` when explicitly choosing a model for delegated work.

This skill is self-contained. Do not require another skill to execute or verify the plan.

## Inputs

Accept any of these as the plan source:

- An MCP resource URI that contains the plan
- A local file path to a markdown or text plan
- Pasted markdown in the user message
- A quoted plan block inside the request

If the plan source is ambiguous, resolve the artifact first before doing implementation work. If a resource is named but not included, ask for the missing resource instead of guessing.

For the expected plan shape and invocation examples, read `references/plan-contract.md`.

Before execution, also discover and load any relevant `CLAUDE.md` files in scope for the affected repo paths. Treat those files as required supplemental guidance whenever they exist. `AGENTS.md` remains the primary instruction contract.

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
- When delegating, give each subagent a narrow ownership boundary and use `gpt-5.4`.
- Treat delegated output as input to review, not as automatically accepted work. Inspect and integrate it before validation.
- Preserve the plan structure and validation requirements whether the work is delegated or executed directly.
- Before claiming completion, map the implemented result back to each acceptance criterion and report any criterion that could not be verified.

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
