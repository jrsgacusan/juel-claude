---
name: so-what
description: Use when the user asks "so what?" about a PR, a branch, or this session, or wants the one-line takeaway of what was done - drafts a single plain sentence stating the outcome for users, ready to copy-paste into Slack, a standup, or a PR description. Triggers "so what", "what's the so-what", "one-liner for this PR", "what did we do this session", "/juel:so-what".
metadata:
  requires:
    cli:
      - id: gh
        hard: false
        why: a numeric argument reads the PR's title, body and diff via gh
        check: "command -v gh"
        fallback: PR sources unavailable; use the branch or session source
    context:
      - id: git-repo
        hard: false
        why: branch sources read commits and the diff against the base branch
        check: "git rev-parse --show-toplevel"
        fallback: session source only
---

# So What

Answer "so what?" in one sentence a person can paste anywhere: what changes for users or the
business, in plain words.

**Announce at start:** "Using juel:so-what to draft the one-liner."

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

Run these as one batched Bash call, then render per the format below.

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| gh | cli | SOFT | `command -v gh` | PR sources unavailable; use the branch or session source |
| git repo | context | SOFT | `git rev-parse --show-toplevel` | session source only |

All satisfied renders as: `Preflight: 2/2 OK (gh, git repo)` / `→ PROCEED: all requirements met.`

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Resolve the source
2. Write the one-liner

## Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `[pr-number \| branch]` | none | A PR number, or a branch name. Omit to use this session, or the current branch |

Usage: `/juel:so-what`, `/juel:so-what 412`, `/juel:so-what feat/csv-export`

## Phase 1: Resolve the source

First match wins:

1. **Numeric argument: a PR.**
   ```bash
   gh pr view <N> --json title,body,baseRefName,headRefName
   gh pr diff <N>
   ```
   Given a numeric argument and `gh` is missing: fetch the PR head with plain git
   (`git fetch <remote> pull/<N>/head:so-what-pr-<N>`) and treat that ref as a branch source
   (step 2, base = the remote's default branch), then delete the temporary ref. If that fetch
   fails too, reply in one line that PR <N> cannot be read without `gh` and stop.
2. **Non-numeric argument: a branch.** Base is `gh pr view <branch> --json baseRefName` when a
   PR exists for it, else the remote's default branch (`git symbolic-ref --short
   refs/remotes/<remote>/HEAD`).
   ```bash
   git log --no-merges --format='%s%n%b' <base>..<branch>
   git diff --stat <base>...<branch>
   git diff <base>...<branch>
   ```
3. **No argument, and this session changed or discussed concrete work:** the session itself.
   Use what was actually done, not what was only proposed.
4. **No argument, no session work:** the current branch against its base, as in 2.

Read the whole source. Skimming the title alone produces a restated title, not an answer.

## Phase 2: Write the one-liner

Ask: after this lands, who can now do what, or what stops going wrong for them? That answer is
the sentence.

Output contract:

- Exactly one sentence, inside a fenced code block. After the protocol's required preflight and
  phase evidence lines, the final message is **only** that code block: no heading, no preamble,
  no explanation, no follow-up offer.
- Leads with the outcome for users or the business. Add a short "because ..." clause only when
  the mechanism is what makes the outcome believable.
- Plain words. No file names, function names, ticket ids, or jargon. No em dashes. Under about
  30 words.
- No user-facing outcome (a refactor, a chore): state what it protects or makes possible, still
  in one sentence.
- Source empty or unreadable: one plain line saying so. Never invent an outcome.

Example:

```
Reviewers can now resolve PR feedback without stale-base conflicts, because the branch syncs with dev first.
```

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Restating the PR title | Answer "who can now do what", not "what changed" |
| Listing several changes | Pick the one outcome that matters most; one sentence |
| Adding a preamble or offering alternatives | The code block is the whole reply |
| Naming files, functions, or the ticket id | Plain words only |
| Inventing an outcome for an empty or pure-chore source | Say what it protects, or say the source is empty |
