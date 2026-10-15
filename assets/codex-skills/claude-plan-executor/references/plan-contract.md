# Plan Contract

## Accepted Inputs

Pass one plan source:

- an MCP resource URI
- a local file path
- pasted markdown
- an attached artifact whose contents are readable in the current environment

## Expected Plan Contents

The skill works best when the incoming plan includes:

- objective
- ordered steps or phases
- constraints
- acceptance criteria
- affected files, systems, or artifacts when known

The plan does not need to be perfect. The skill should refine missing implementation detail, but not silently change the requested scope.

**Required: a `**Files:**` block per task.** Each task names every file it may change, one list
line per file: `Create:`, `Modify:`, `Test:` or `Delete:`, then the backticked path, with the
function or line range when known (``Modify: `src/auth.py:40-62` ``). A path ending in `/` names
everything under it. A `:<lines>` or `::<test name>` suffix (``Test: `tests/test_a.py::test_x` ``)
is dropped when the path is matched. The executor changes nothing outside these blocks, and the
caller's scope check (`skills/ship-ticket/scope-check.sh` in the juel plugin) reverts any changed
file no block names.

## Execution Contract

When invoked, the agent should:

1. read the plan artifact first
2. restate the executable checklist in compact form if useful
3. execute the plan instead of only summarizing it
4. validate work against the plan's acceptance criteria
5. state deviations, blockers, and incomplete items clearly

The executor never runs `git add -f`, and never commits a path the repository ignores.

## Fix-round plans

A plan that changes a spec which is already implemented (a review fix, a gate fix, any later
round) carries this line in its header:

    **Base:** spec implemented at <full sha>; apply only the tasks below.

The executor applies the tasks and does not re-check the spec for completeness: a `Spec:` line on
such a plan is context, not a checklist, and "already implemented" is never a reason to stop.

## Progress ledger

The executor records each finished task in
`<repo root>/.superpowers/sdd/<plan file name without .md>/progress.md`. It is the ledger
`superpowers:executing-plans` keeps, in the same format, so a run that stopped part way resumes
from it on any executor: the same line again, the fallback model, or a Claude session.

    # SDD ledger — plan: <plan file path>
    Task 1: complete (commits a1b2c3d..d4e5f6a, tests: npm test -- hooks → 1/1 pass)
    Task 2: complete (uncommitted, tests: npm test -- recovery → 8/8 pass)

A run starts at the first task with no `complete` line, and checks that task's state before it
edits anything. The dispatcher makes sure `.superpowers/` is git-ignored before the first dispatch.

## Model Guidance

Use the model the session is already configured with. Do not name a specific id here; it goes
stale. Use higher reasoning effort when the plan is broad, cross-cutting, or risky, and lighter
effort only for narrow, mechanical steps.

## Example Prompts

- `Use $claude-plan-executor with resource app://claude/plan/123 and implement it.`
- `Use $claude-plan-executor with /tmp/claude-plan.md and execute the plan.`
- `Use $claude-plan-executor with the pasted Claude plan below and complete phases 1 and 2.`
