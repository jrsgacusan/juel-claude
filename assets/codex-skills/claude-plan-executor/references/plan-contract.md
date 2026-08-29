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

## Execution Contract

When invoked, the agent should:

1. read the plan artifact first
2. restate the executable checklist in compact form if useful
3. execute the plan instead of only summarizing it
4. validate work against the plan's acceptance criteria
5. state deviations, blockers, and incomplete items clearly

## Model Guidance

Use the model the session is already configured with. Do not name a specific id here; it goes
stale. Use higher reasoning effort when the plan is broad, cross-cutting, or risky, and lighter
effort only for narrow, mechanical steps.

## Example Prompts

- `Use $claude-plan-executor with resource app://claude/plan/123 and implement it.`
- `Use $claude-plan-executor with /tmp/claude-plan.md and execute the plan.`
- `Use $claude-plan-executor with the pasted Claude plan below and complete phases 1 and 2.`
