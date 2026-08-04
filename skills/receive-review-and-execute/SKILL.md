---
name: receive-review-and-execute
description: Use when a PR already has external review comments and you want them validated, planned, and executed automatically - fetches PR review comments, validates findings, asks about ambiguous ones, writes a plan, then dispatches Codex to execute fixes
metadata:
  requires:
    cli:
      - id: gh
        hard: true
        why: step 1 fetches PR comments, reviews and the diff via gh api
        check: "gh auth status"
      - id: codex
        hard: false
        why: phase 7 dispatches codex to execute the remediation plan
        check: "command -v codex"
        fallback: execute the plan in-session
    context:
      - id: open-pr
        hard: true
        why: this skill consumes review comments from an existing PR
        check: "gh pr view <N> --json number"
      - id: github-remote
        hard: true
        why: step 1 resolves the PR's repo and requires a github.com remote
        check: "git remote get-url <remote> matches github.com"
      - id: interactive-user
        hard: true
        why: phase 5 clarifies ambiguous findings via AskUserQuestion
    skills:
      - id: superpowers
        hard: true
        why: phases 4 and 6 delegate to superpowers:receiving-code-review and superpowers:writing-plans
---

# Receive Review and Execute

## Overview

Orchestrates a receive-review-to-fix cycle for an **existing PR with review comments**: fetch PR comments → validate findings → clarify ambiguities with the user → write remediation plan → dispatch Codex to execute.

Differs from `/juel:review-and-execute`: that one runs a fresh PR review locally; this one consumes review comments already posted on a GitHub PR.

**Announce at start:** "I'm using the receive-review-and-execute skill to apply PR review feedback."

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v2 -->

**1. Preflight, then task list, before anything else.** Before any other output and before any tool call, emit the Preflight block (below). If the preflight verdict is STOP, print the preflight block and **stop** — do not create tasks and do not begin work. Otherwise, before any other work, create one task per phase in this skill's `## Phases` list via `TaskCreate` — `subject` is the phase name, `activeForm` is its present-continuous form. This task list, rendered persistently by the harness, IS the checklist; nothing else satisfies this rule. This is not optional on re-invocation, on resume, or when the user says "just do it".

**2. Phases run in order.** No skipping, reordering, or merging. A phase that does not apply is still announced, not dropped: mark its task `completed` via `TaskUpdate`, with the one-line evidence required by rule 3 stating the skip reason (e.g. "SKIPPED: <reason>") — the task list has no separate "skipped" status, so a skipped phase becomes `completed` too. Never begin phase N+1 before phase N's task is marked `completed`.

**3. Report after every phase.** Mark the phase's task `in_progress` via `TaskUpdate` when starting it, then `completed` via `TaskUpdate` when it finishes or is skipped — each transition accompanied by exactly one line of evidence (path written, command run, count found). Do not re-print the checklist as text; the task list is the persistent record and replaces that. Never claim progress in prose alone.

**4. Everything runs in the FOREGROUND; `review-pr`'s agents run in PARALLEL.** This overrides every other instruction in this file and in any skill invoked from it. Foreground/background and parallel/sequential are different axes: foreground vs. background is about whether you wait and watch; parallel vs. sequential is about whether agents run concurrently. The requirement is concurrent-and-watched — dispatched together, run in the foreground, waited on in full.
- `pr-review-toolkit:review-pr`'s agents MUST be dispatched in parallel: pass `all parallel`, or dispatch the agents together in ONE message. Its sequential default — one agent at a time — is the exact slowness this rule exists to prevent; requesting it, or omitting `all parallel`, is a violation.
- `pr-review-toolkit:review-pr`, `simplify`, and `codex exec` are all foreground-only. Invoke every subagent with `run_in_background: false` **explicitly** — the harness backgrounds subagents by default, so omitting the flag is a violation, not a neutral choice. Dispatching agents in parallel does not relax this: each agent in that one message still carries its own explicit `run_in_background: false`.
- Never `&`. Never `run_in_background: true`. Never "dispatch and continue".
- **Never redirect a command's output to a log file.** No `> out.log`, no `| tee`, no writing output somewhere to read back later. The user must be able to watch the run as it happens.
- Read the complete output and state the outcome — finding count, exit status, files changed — before marking the phase done. A summary may follow the raw output; it may never replace it.
- Passing any of this into another session (a CMUX prompt, a nested `claude`) carries these rules with it — say so explicitly in that prompt string.

**5. Confirmation gates stack; they do not replace this.** Where this skill pauses between phases, the checklist report comes first, then the "Proceed to phase N+1?" question. A user's "yes" advances exactly one phase — it never authorizes skipping ahead or batching the remainder.

## Preflight

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| gh (authenticated) | cli | HARD | `gh auth status` | STOP → `gh auth login` |
| open PR + number | context | HARD | `gh pr view <N> --json number` | STOP → this skill consumes an existing PR |
| GitHub remote | context | HARD | `git remote get-url <remote>` matches github.com | STOP → non-GitHub remotes are unsupported here |
| superpowers | skill | HARD | ships as a plugin dependency | STOP |
| codex | cli | SOFT | `command -v codex` | execute the plan in-session |
| AskUserQuestion | context | HARD | always available interactively | STOP in headless sessions |

## Phases

[ ] 1. Ensure a PR number, asking if it was not supplied
[ ] 2. Read every review thread and deliver the summary before forming an opinion
[ ] 3. Fetch structured data — inline comments, reviews, issue comments, diff
[ ] 4. Validate findings into actionable / rejected / ambiguous
[ ] 5. Clarify ambiguous findings (SKIPPED if none were ambiguous)
[ ] 6. Write the remediation plan, or stop here if there are zero actionable findings
[ ] 7. Run the executor on the plan, FOREGROUND
[ ] 8. Report the result

## First action (non-negotiable)

When asked to review a PR, your **first action is always**:

1. Run `gh pr view <num> --comments`
2. Read every existing comment and review thread in full
3. Summarize what's already been raised before forming your own opinion

Do not skim. Do not skip to validation. Do not form opinions before this summary. The summary is delivered to the user before any further step.

For **simplify passes** in this flow (if invoked): read the last 3 commits (`git log -3 --stat`) and ask the user to confirm scope before changing anything.

## Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `[pr-number]` | (required) | GitHub PR number to fetch review comments from |

Usage: `/juel:receive-review-and-execute 123`

If no PR number is provided, ask the user for it before proceeding. Do not guess.

## Workflow

```dot
digraph flow {
    rankdir=TB;
    node [shape=box];

    ask [label="0. Ask for PR number\n(if not provided)"];
    fetch [label="1. Fetch PR review comments\n(gh api)"];
    validate [label="2. Validate Findings\n(receiving-code-review)"];
    ambiguous [label="Any ambiguous findings?" shape=diamond];
    clarify [label="2a. Ask user clarifying questions"];
    has_findings [label="Actionable findings?" shape=diamond];
    plan [label="3. Write Plan\n(writing-plans)"];
    execute [label="4. Dispatch Codex\n(codex exec --sandbox workspace-write)"];
    done [label="Done - no action needed"];

    ask -> fetch;
    fetch -> validate;
    validate -> ambiguous;
    ambiguous -> clarify [label="yes"];
    ambiguous -> has_findings [label="no"];
    clarify -> has_findings;
    has_findings -> plan [label="yes"];
    has_findings -> done [label="no"];
    plan -> execute;
}
```

### Step 0: Ensure PR number

If the user did not supply a PR number, ask:

> "Which PR number should I receive review feedback from?"

Do not proceed until you have a valid integer PR number.

### Step 1: Fetch PR review comments

**Start with `gh pr view <PR> --comments`** to read every existing comment and review thread, then write a short summary of what reviewers have already raised. Deliver that summary to the user before continuing.

Then pull structured data:

```bash
# Repo context
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# Inline review comments (file/line specific)
gh api "repos/$repo/pulls/<PR>/comments" --paginate

# PR-level reviews (overall summaries / approvals)
gh api "repos/$repo/pulls/<PR>/reviews" --paginate

# Issue-style comments on the PR (general discussion)
gh api "repos/$repo/issues/<PR>/comments" --paginate
```

Capture: comment id, author, file path, line, diff hunk, body, created_at. Group by file for readability.

Also fetch the PR diff so validation can ground findings against actual code:

```bash
gh pr diff <PR>
```

### Step 2: Validate Findings

Invoke the receiving-code-review skill:

```
Skill("superpowers:receiving-code-review")
```

For each comment from step 1:
- Verify the finding against the current code on the PR branch
- Reject suggestions that are incorrect, outdated (already fixed), or unnecessary
- Classify each finding as: **actionable**, **rejected**, or **ambiguous**

### Step 2a: Clarify ambiguous findings

If any findings are **ambiguous** (intent unclear, multiple valid interpretations, scope uncertain, or trade-off requires user judgment), STOP and ask the user before writing the plan.

Use `AskUserQuestion` with the specific ambiguous finding(s). For each ambiguity, present:
- The original comment (author + body, trimmed)
- File and line
- Why it is ambiguous
- 2-4 concrete options the user can pick

Do not invent an interpretation. Do not proceed to step 3 until every ambiguity is resolved or explicitly deferred.

After clarification, fold the user's answers into the actionable list.

### Step 3: Write Remediation Plan

**Resolve `docsRoot` once, then reuse it.** In order:
1. `config.docsRoot`, if set.
2. `<repo-root>/docs/.superpowers/` **if it exists and is non-empty** — an existing repo keeps
   using the dotted path so prior specs, plans and context are never stranded or split.
3. Otherwise `<repo-root>/docs/superpowers/` — canonical for every new repo.

Never pick between the two variants ad hoc. Layout underneath is
`${docsRoot}/{specs,plans,context,findings}/`.

```bash
ROOT=$(git rev-parse --show-toplevel)
# Step 1 of the precedence above (config.docsRoot in .claude/workflow.json /
# .claude/workflow.local.json) — if set there, use that value directly
# instead of the filesystem check below. Steps 2-3 (filesystem fallback):
if [ -d "$ROOT/docs/.superpowers" ] && [ -n "$(ls -A "$ROOT/docs/.superpowers" 2>/dev/null)" ]; then
  docsRoot="$ROOT/docs/.superpowers"
else
  docsRoot="$ROOT/docs/superpowers"
fi
```

(If `.claude/workflow.json` or `.claude/workflow.local.json` sets `docsRoot`, that value wins over
the filesystem check above — config always takes precedence.)

Ensure the repo's `.gitignore` contains unanchored `superpowers/` and `.superpowers/` entries —
unanchored so they match at any depth. Add them if absent. This directory is scratch, not product.

If there are NO actionable findings after validation and clarification, announce this and stop. Do not proceed.

Otherwise invoke writing-plans:

```
Skill("superpowers:writing-plans")
```

Write the resulting plan to: `${docsRoot}/plans/receive-review-plan.md`.

**Never overwrite an existing plan file.** If `receive-review-plan.md` already exists, write the new plan to the next available versioned suffix: `receive-review-plan-v2.md`, then `-v3.md`, etc. Prior plan files are historical records — leave them in place.

Determine the next suffix with:

```bash
ls "$docsRoot/plans"/receive-review-plan*.md 2>/dev/null
```

Then pass the chosen path to Codex in Step 4.

The plan must:
- Reference each confirmed finding (link to the GitHub comment URL)
- Include file paths and line numbers
- Note user decisions for previously ambiguous findings
- Have bite-sized, executable steps
- Include verification commands per task

### Step 4: Dispatch Codex

Run Codex CLI non-interactively with the workspace-write sandbox:

```bash
codex exec --sandbox workspace-write '$claude-plan-executor ${docsRoot}/plans/receive-review-plan<-vN if applicable>.md'
```

Run this in the **foreground** (`run_in_background: false`). Do not redirect its output to a file — the user watches the executor run. Wait for it to exit, read the complete output, and state the exit status and files changed before marking the phase done. Announce to the user that Codex has been dispatched and surface the command.

Wait for Codex to complete before reporting results.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Proceeding without a PR number | Step 0 — ask, do not guess |
| Acting on every PR comment blindly | Step 2 — validate before accepting |
| Guessing reviewer intent on ambiguous comments | Step 2a — ask the user explicitly |
| Skipping the plan and going straight to Codex | Codex needs a structured plan |
| Writing plan without file paths/line numbers/comment URLs | Codex needs specifics; reviewer needs traceability |
| Fixing findings directly instead of writing a plan | NEVER fix code yourself — always plan + dispatch Codex |
| Treating already-fixed comments as actionable | Verify against current PR HEAD before accepting |
| Forming an opinion before reading existing comments | Run `gh pr view <num> --comments` first, summarize, then think |
| Simplify pass without scope confirmation | Read last 3 commits, ask user to confirm scope before edits |
| Backgrounding the executor or redirecting its output to a file | Never. Phase 7 runs it in the foreground so the user can watch. |
| Forgetting `--sandbox workspace-write` | Codex needs write access to apply the plan |
| Overwriting an existing `receive-review-plan.md` | Always pick the next free `-vN` suffix; prior plans are historical |
