---
name: receive-review-and-execute
description: Use when a PR already has external review comments and you want them validated, planned, and executed automatically - merges the PR's base branch in first, then fetches PR review comments, validates findings, asks about ambiguous ones, writes a plan, then dispatches Codex to execute fixes
metadata:
  requires:
    cli:
      - id: gh
        hard: true
        why: step 1 fetches PR comments, reviews and the diff via gh api
        check: "gh auth status"
      - id: codex
        hard: false
        why: phase 8 dispatches codex to execute the remediation plan
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
        why: phase 6 clarifies ambiguous findings and phase 2 asks how to handle merge conflicts via AskUserQuestion; satisfied by --unattended, which reports them instead of asking
      - id: clean-tree
        hard: true
        why: phase 2 merges the base branch and must not merge onto uncommitted changes
        check: "git status --porcelain empty"
    skills:
      - id: superpowers
        hard: true
        why: phases 5 and 7 delegate to superpowers:receiving-code-review and superpowers:writing-plans
      - id: claude-plan-executor
        hard: true
        why: phase 8 dispatches `codex exec '$claude-plan-executor <plan>'`; without it Codex silently executes something else
---

# Receive Review and Execute

## Overview

Orchestrates a receive-review-to-fix cycle for an **existing PR with review comments**: fetch PR comments → validate findings → clarify ambiguities with the user → write remediation plan → dispatch Codex to execute.

Differs from `/juel:review-and-execute`: that one runs a fresh PR review locally; this one consumes review comments already posted on a GitHub PR.

**Announce at start:** "I'm using the receive-review-and-execute skill to apply PR review feedback."

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v7 -->

**0. Harness check, before every other rule.** If you do not have the `TaskCreate` tool, you are not running in Claude Code. Read `references/harness-codex.md`, resolved relative to this skill file's own location (`../../references/harness-codex.md`), and apply its construct map, corrected facts, dependency substitutions and degradation contract to every rule below and to every phase body in this skill. This single read is the one action permitted before rule 1's preflight, and only in that case. If you do have `TaskCreate`, ignore that file entirely and continue to rule 1.

**1. Preflight, then task list, before anything else.** Before any other output and before any tool call, emit the Preflight block (below). If the preflight verdict is STOP, print the preflight block and **stop** — do not create tasks and do not begin work. Otherwise, before any other work, create one task per phase in this skill's `## Phases` list via `TaskCreate` — `subject` is the phase name, `activeForm` is its present-continuous form. This task list, rendered persistently by the harness, IS the checklist; nothing else satisfies this rule. This is not optional on re-invocation, on resume, or when the user says "just do it".
- **If `TaskCreate`/`TaskUpdate` genuinely fail** — one attempted call returns an error, never merely assumed unavailable in advance — fall back to an explicit numbered phase log, printed after every phase transition with the same one-line evidence rule 3 already requires. State the degradation once, in one line, before continuing. Never silently swap to prose without saying so.

**2. Phases run in order.** No skipping, reordering, or merging. A phase that does not apply is still announced, not dropped: mark its task `completed` via `TaskUpdate`, with the one-line evidence required by rule 3 stating the skip reason (e.g. "SKIPPED: <reason>") — the task list has no separate "skipped" status, so a skipped phase becomes `completed` too. Never begin phase N+1 before phase N's task is marked `completed`.

**3. Report after every phase.** Mark the phase's task `in_progress` via `TaskUpdate` when starting it, then `completed` via `TaskUpdate` when it finishes or is skipped — each transition accompanied by exactly one line of evidence (path written, command run, count found). Do not re-print the checklist as text; the task list is the persistent record and replaces that. Never claim progress in prose alone.

**4. `review-pr`'s agents run in PARALLEL and FOREGROUND; `code-simplifier` runs FOREGROUND; `codex exec` runs BACKGROUND, WATCHED, and WAITED-ON.** This overrides every other instruction in this file and in any skill invoked from it. Foreground/background is about whether the tool call blocks; watched is about whether output still streams somewhere the user can see it — these are different axes, and `codex exec` needs the second without the first. `review-pr`'s agents additionally need PARALLEL: dispatched together, not one at a time.
- `pr-review-toolkit:review-pr`'s agents MUST be dispatched in parallel: pass `all parallel`, or dispatch the agents together in ONE message. Its sequential default — one agent at a time — is the exact slowness this rule exists to prevent; requesting it, or omitting `all parallel`, is a violation.
- `pr-review-toolkit:review-pr` and `code-simplifier` are foreground-only. Invoke both with `run_in_background: false` **explicitly** — the harness backgrounds subagents by default, so omitting the flag is a violation, not a neutral choice. Dispatching review-pr's agents in parallel does not relax this: each agent in that one message still carries its own explicit `run_in_background: false`. Never `&`. Never `run_in_background: true` for these two. Never "dispatch and continue".
- `codex exec` runs through the **Bash tool**, whose `timeout` parameter is capped at 600000ms (10 minutes). A real `codex exec` applying a plan routinely runs longer than that, so a foreground dispatch gets silently DETACHED by the harness at the cap regardless of this rule — nothing then watches it, nothing reads its output, and the skill would wrongly proceed as if the phase had ended. `review-pr` and `code-simplifier` run through the **Skill/Agent tool**, which carries no such cap — that is the entire reason only `codex exec` changes. Do not "fix" this back to foreground; the cap is a harness fact, not a preference.
- **Always dispatch `codex exec` with `run_in_background: true`** — not optional, not "if it looks long," always. Omitting the flag, or passing `false`, is a violation.
- **Never redirect a command's output to a log file.** No `> out.log`, no `| tee`, no writing output somewhere to read back later. This applies to all three, and is now MORE load-bearing for `codex exec`: backgrounded with no ceiling, the shell is the only place the user watches it work.
- For `review-pr` and `code-simplifier`: read the complete output and state the outcome — finding count, exit status, files changed — before marking the phase done. A summary may follow the raw output; it may never replace it.
- For `codex exec`: wait for it to exit before marking the phase done — backgrounding must never become fire-and-forget. Then state the outcome — exit status, files changed — not a transcript; the user already watched it stream in the shell, so its full output is never printed back into the conversation.
- **Never attach a `Monitor` or a polling loop to `codex exec`.** No `Monitor` armed on its output, no repeated reads of the `.output` file, no `tail -f`. Dispatch it backgrounded and wait for the completion notification — the user already watches it stream in their own shell, which is exactly why output must never be redirected; a watcher on top adds nothing, and a filter with no pattern for `Reading additional input from stdin...` will misread a stalled executor as healthy.
- Passing any of this into another session (a CMUX prompt, a nested `claude`) carries these rules with it — say so explicitly in that prompt string.

**5. Confirmation gates stack; they do not replace this.** Where this skill pauses between phases, the checklist report comes first, then the "Proceed to phase N+1?" question. A user's "yes" advances exactly one phase — it never authorizes skipping ahead or batching the remainder.

**6. `Idling` is a status, not a verdict — never read it as "returned nothing."** When a dispatched `pr-review-toolkit:review-pr` agent or `code-simplifier` shows `Idling` (or any non-streaming status) in the harness's agent view while its call is still in flight, that status alone never means the agent produced no output — `Idling` covers both "still working" and "finished, with a result already available but not yet consumed by this session" indistinguishably. Multi-agent dispatch is exactly where this bites: `pr-review-toolkit:review-pr`'s specialist agents run "all parallel" (rule 4), so several can sit at `Idling` simultaneously while one has already returned and the others haven't.
- **Before concluding a dispatch returned nothing, or re-dispatching it, check `ListAgents` for the agent by name.** If it's listed with a result available, read that result directly — do not wait further and do not re-dispatch a duplicate call.
- **Never re-dispatch `pr-review-toolkit:review-pr` or `code-simplifier` "to unstick it"** without first confirming via `ListAgents` that the original dispatch genuinely produced nothing — re-dispatching a call whose result already exists wastes a full review cycle and risks duplicate, conflicting findings.
- **Never go quiet past a check-in point with no status update.** If a dispatch has been running long enough that you would normally report progress, either report genuine progress or check `ListAgents` first — silently waiting while a subagent is actually done is the exact failure this rule exists to prevent.

## Preflight

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| gh (authenticated) | cli | HARD | `gh auth status` | STOP → `gh auth login` |
| open PR + number | context | HARD | `gh pr view <N> --json number` | STOP → this skill consumes an existing PR |
| GitHub remote | context | HARD | `git remote get-url <remote>` matches github.com | STOP → non-GitHub remotes are unsupported here |
| superpowers | skill | HARD | ships as a plugin dependency | STOP |
| claude-plan-executor | skill | HARD | vendored by this plugin | STOP → `node scripts/link-agent-skills.mjs` |
| codex | cli | SOFT | `command -v codex` | execute the plan in-session |
| AskUserQuestion | context | HARD | always available interactively, or `--unattended` passed | STOP in headless sessions unless `--unattended` was passed |
| clean working tree | context | HARD | `git status --porcelain` empty | STOP → commit or stash first |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Ensure a PR number, asking if it was not supplied
2. Sync with the integration branch — merge the PR's base branch in before reading anything
3. Read every review thread and deliver the summary before forming an opinion
4. Fetch structured data — inline comments, reviews, issue comments, diff
5. Validate findings into actionable / rejected / ambiguous
6. Clarify ambiguous findings (SKIPPED if none were ambiguous)
7. Write the remediation plan, or stop here if there are zero actionable findings
8. Run the executor on the plan, BACKGROUND (watched, waited-on)
9. Report the result

## First action (non-negotiable)

Once the PR number is known and the branch is synced (phases 1-2), your **first action is always**:

1. Run `gh pr view <num> --comments`
2. Read every existing comment and review thread in full
3. Summarize what's already been raised before forming your own opinion

Do not skim. Do not skip to validation. Do not form opinions before this summary. The summary is delivered to the user before any further step.

## Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `[pr-number]` | (required) | GitHub PR number to fetch review comments from |
| `--unattended` | off | No human answers (a `juel:ship-tickets` worker under `juel:babysit-pr --unattended`): merge conflicts and ambiguous findings are reported and the run stops, instead of asking |
| `--brief <path>` | — | An approved `juel_brief: 1` brief. A reviewer request that needs work outside its Scope (or listed under Out) is not built: see below |
| `--only <ids>` | all unanswered feedback | Comma-separated comment / review ids to act on this run. Every other thread is still read as context, but is never re-classified, planned or answered |

Usage: `/juel:receive-review-and-execute 123`, `/juel:receive-review-and-execute 123 --unattended`

**With `--unattended`**, nothing is asked:
- A merge conflict in phase 2: `git merge --abort`, print `CONFLICT: <each conflicted file>` and stop.
- Any ambiguous finding in phase 5: do not ask and do not execute anything, including the
  actionable findings, so a fix never ships half-decided. Print `AMBIGUOUS: <author> <file:line>
  <comment, trimmed> — <why it is ambiguous>` for each one and stop; the caller escalates them.
- With `--brief`, a finding that needs work outside the brief's scope is not planned: print
  `BRIEF-VIOLATION: <author> <file:line> <request, trimmed> — <the scope line it breaks>` and stop
  before executing anything, so the human decides. Without `--brief`, scope is not checked.
- With `--only`, phase 5 classifies only the listed items; the rest are context.
- Heavy verification steps in the remediation plan (full test suites, builds) are written as
  `juel:ship-ticket`'s `gate-lock.sh` line (`sh <gate-lock.sh> --holder <pr> -- <command>`), so they
  wait their turn behind other unattended workers; targeted single-file tests run directly.
- Any other STOP (a preflight STOP, a dirty tree, a missing PR) prints `STOPPED: <reason>` as its
  last line, so the caller never mistakes it for a run with nothing to fix.
- Everything else runs as normal.

If no PR number is provided, ask the user for it before proceeding. Do not guess.

## Workflow

```dot
digraph flow {
    rankdir=TB;
    node [shape=box];

    ask [label="0. Ask for PR number\n(if not provided)"];
    sync [label="0a. Merge PR base branch\n(git fetch + git merge --no-edit)"];
    conflict [label="Conflicts?" shape=diamond];
    stop_conflict [label="Stop: list files,\nask resolve vs abort"];
    fetch [label="1. Fetch PR review comments\n(gh api)"];
    validate [label="2. Validate Findings\n(receiving-code-review)"];
    ambiguous [label="Any ambiguous findings?" shape=diamond];
    clarify [label="2a. Ask user clarifying questions"];
    has_findings [label="Actionable findings?" shape=diamond];
    plan [label="3. Write Plan\n(writing-plans)"];
    execute [label="4. Dispatch Codex\n(codex exec --sandbox workspace-write)"];
    done [label="Done - no action needed"];

    ask -> sync;
    sync -> conflict;
    conflict -> stop_conflict [label="yes"];
    conflict -> fetch [label="no"];
    stop_conflict -> fetch [label="resolved"];
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

### Step 0a: Sync with the integration branch

Bring the PR up to date with the branch it targets **before** reading any comment, so every
finding is validated against current code. A comment already fixed on the base branch is then
rejected as outdated instead of fixed twice.

```bash
gh pr view <PR> --json headRefName,baseRefName
git rev-parse --abbrev-ref HEAD
git status --porcelain
```

1. The current branch must equal `headRefName`. If it does not, STOP and say so, naming both
   branches. Never check out, switch, or stash on the user's behalf.
2. The working tree must be clean. If it is not, STOP: commit or stash first.
3. The integration branch is `baseRefName`, the PR's own target (`dev` in gitflow repos, `main`
   elsewhere). Resolve the remote: exactly one remote, use it; one named `origin`, use that;
   otherwise ask once.
4. Merge it in:

   ```bash
   git fetch <remote> <base>
   git merge --no-edit <remote>/<base>
   ```

5. Outcomes, each with one evidence line:
   - `Already up to date.`: continue.
   - Clean merge: report the merge commit's short SHA and the number of files it brought in.
   - Conflicts: STOP. List every conflicted file (`git diff --name-only --diff-filter=U`). Under
     `--unattended`, abort and print `CONFLICT:` per "Arguments". Otherwise ask via
     `AskUserQuestion`: resolve the conflicts in this session, or `git merge --abort` and stop the
     skill. Never auto-resolve, and never pick a side silently.
   - If the user chooses to resolve in-session: propose each file's resolution and apply it only
     after the user approves it. Then confirm no conflict markers remain
     (`git diff --check` and `grep -rn '^<<<<<<< ' <files>` both empty) and conclude the merge
     with `git commit --no-edit` before any later phase runs, so remediation commits never land
     inside an unfinished merge. One evidence line: the merge commit's short SHA.
6. Do not push here. The merge commit is pushed with the remediation commits.

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

If any findings are **ambiguous** (intent unclear, multiple valid interpretations, scope uncertain, or trade-off requires user judgment), STOP and ask the user before writing the plan. Under `--unattended`, print the `AMBIGUOUS:` lines from "Arguments" and stop instead.

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
`${docsRoot}/{specs,plans,context,findings,evidence}/`.

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

**Never overwrite an existing file under `${docsRoot}`.** On a name collision — a spec, plan,
findings report, or context file that already exists at the derived path — append `-v2` before
the extension; if `-v2` exists too, use `-v3`, and so on. This applies to every file type written
under `${docsRoot}`, not only the one this skill produces.

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

The harness pipes stdin and never closes it, so codex waits for an EOF that never arrives, and without `< /dev/null` here it hangs silently with the prompt unprocessed.

```bash
codex exec --sandbox workspace-write '$claude-plan-executor ${docsRoot}/plans/receive-review-plan<-vN if applicable>.md' < /dev/null
```

**Under Codex (rule 0 applies).** Do not run the command above — it would spawn a second Codex
session inside this one. Instead `spawn_agent` with the plan path as the task, then `wait` for
it. Report the same outcome the Claude path reports: exit status and files changed, never a
transcript. If `spawn_agent` is unavailable (the `multi_agent` feature is off), say so in one
line and apply the plan in this session directly rather than falling back to `codex exec`.

Always run this in the **background** (`run_in_background: true`) — `codex exec` runs through the Bash tool, whose 600s timeout cap would otherwise silently detach it mid-run. Do not redirect its output to a file — the user watches the executor run in the shell. Announce to the user that Codex has been dispatched and surface the command.

Wait for Codex to complete, then state the exit status and files changed before marking the phase done — do not print its full output back into the conversation.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Proceeding without a PR number | Step 0 — ask, do not guess |
| Validating comments against a stale base | Step 0a merges the PR's base branch first; outdated comments are then rejected, not re-fixed |
| Auto-resolving merge conflicts, or checking out the PR branch for the user | Never. Step 0a stops, lists the files, and asks |
| Acting on every PR comment blindly | Step 2 — validate before accepting |
| Guessing reviewer intent on ambiguous comments | Step 2a — ask the user explicitly |
| Skipping the plan and going straight to Codex | Codex needs a structured plan |
| Writing plan without file paths/line numbers/comment URLs | Codex needs specifics; reviewer needs traceability |
| Fixing findings directly instead of writing a plan | NEVER fix code yourself — always plan + dispatch Codex |
| Treating already-fixed comments as actionable | Verify against current PR HEAD before accepting |
| Forming an opinion before reading existing comments | Run `gh pr view <num> --comments` first, summarize, then think |
| Running the executor in the foreground, or redirecting its output to a file | Never. Phase 8 always backgrounds Codex (600s Bash-tool cap) but never redirects its output — the user watches it in the shell. |
| Backgrounding Codex and moving on without waiting for it to exit | Never. Background is not fire-and-forget — wait for exit, then report the outcome. |
| Forgetting `--sandbox workspace-write` | Codex needs write access to apply the plan |
| Overwriting an existing `receive-review-plan.md` | Always pick the next free `-vN` suffix; prior plans are historical |
