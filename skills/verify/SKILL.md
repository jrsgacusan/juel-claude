---
name: verify
description: Use to verify that a change actually works by driving it live, not by reading it. Establishes the diff's scope, identifies the runtime surface it reaches (CLI, TUI, web UI, HTTP/RPC handler, background job), drives the change end-to-end through that real surface, pushes on adjacent edge cases, captures the evidence, and reports PASS/FAIL/BLOCKED/SKIP. Never runs the test suite or a typecheck as verification, and never calls the changed function directly in isolation - only the real interface counts. Invoked directly as /juel:verify, or delegated to from juel:ship-ticket's Phase 7 for every checklist item with a runtime surface.
metadata:
  requires:
    mcp:
      - id: playwright
        hard: false
        why: phase 4 drives a web UI surface through the real browser, not a mock or a direct API call underneath it
        check: none
        fallback: web UI surfaces cannot be driven directly; ask the user to drive the browser themselves and report which items were not verified by Claude
    cli:
      - id: git
        hard: true
        why: phase 1 establishes the diff's full range from git log/git diff
        check: "git --version"
      - id: gh
        hard: false
        why: phase 1 uses gh pr diff to establish scope when verifying an open PR
        check: "command -v gh"
        fallback: scope resolves from git diff against the upstream/base branch instead
    context:
      - id: git-repo
        hard: false
        why: phase 1 establishes scope from git log/diff when run inside a repository
        check: "git rev-parse --show-toplevel"
        fallback: outside a repository, scope is whatever the user names explicitly; ask if they didn't
      - id: app-url
        hard: false
        why: phase 4 needs a running target to drive - a launched app, a dev server, or a resolved commands.run
        check: none
        fallback: phase 3 asks where the app is running, or launches it itself via a discovered verifier-*/run-* skill
      - id: verification-criteria
        hard: false
        why: phase 1 compares the diff against a stated claim - acceptance criteria, a PR description, or the user's stated intent
        check: none
        fallback: phase 1 derives the claim from the diff alone and reports any mismatch as a finding
    skills:
      - id: run
        hard: false
        why: phase 3 falls back to the built-in run skill's launch primitives when no project-local verifier-* skill exists
        fallback: phase 3 cold-starts from the target's README/package.json/Makefile instead
---

# Verify

## Overview

Verification is runtime observation: build (if needed), drive the app to where the changed code
executes, and capture what actually happens. That capture is the evidence. Nothing else is.

**Announce:** "Using juel:verify to verify this change by running it."

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v6 -->

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

This skill has no `codex exec`, `pr-review-toolkit:review-pr`, or `code-simplifier` dispatch sites
of its own — rule 4 and rule 6's agent-dispatch clauses carry no live obligation here, kept
verbatim only because the block is copied byte-for-byte across every skill (see
`references/strict-protocol.md`).

## Preflight

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| git ≥ 2.5 | cli | HARD | `git --version` | STOP → establishing scope needs git |
| gh | cli | SOFT | `command -v gh` | scope resolves from git diff against the upstream/base branch instead |
| git repository | context | SOFT | `git rev-parse --show-toplevel` | outside a repository, scope is whatever the user names explicitly; ask if they didn't |
| resolved app URL | context | SOFT | **none — render as `?`** | phase 3 asks where the app is running, or launches it itself via a discovered verifier-*/run-* skill |
| acceptance criteria to verify | context | SOFT | **none — render as `?`** | phase 1 derives the claim from the diff alone and reports any mismatch as a finding |
| run | skill | SOFT | built-in | phase 3 cold-starts from the target's README/package.json/Makefile instead |
| Playwright MCP | mcp | SOFT | **none — render as `?`** | web UI surfaces cannot be driven directly; ask the user to drive the browser themselves and report which items were not verified by Claude |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Establish the change's scope from the diff
2. Identify the runtime surface the change reaches
3. Get a handle on that surface
4. Drive the change end-to-end through the real interface
5. Push on the edges around the change
6. Capture evidence for every observation
7. Report the verdict

## Workflow

### Step 1: Establish scope from the diff

The scope is whatever is being verified — usually a diff, sometimes just "does X work." In a git
repository, establish the full range first (a branch may carry many commits, or the change may
still be uncommitted) — run all of the following that apply, in one batched call, and use the
first one that yields a non-empty range:

```bash
git log --oneline @{u}..              # commit count, if upstream is set
git diff @{u}.. --stat                # full range against upstream, not HEAD~1
git diff origin/HEAD... --stat        # no upstream set: committed vs the base branch
git diff HEAD --stat                  # uncommitted: working tree vs HEAD
gh pr diff                            # in a PR context and gh is available
```

State the commit count out loud before continuing. A large diff that would truncate on read:
redirect it to a file, then read the file instead of the raw command output.

A repository with none of these yielding a range: say so, and treat this as SKIP (Step 7) — there
is nothing to verify. Outside a repository entirely, scope is whatever the user named when they
invoked this skill; ask if they didn't say.

**The diff is ground truth.** Any description of the change — a ticket, a PR description, the
user's own words — is a claim about what the diff does. Read both. State the claim in one line. If
the claim and the diff disagree, that disagreement is itself a finding for Step 7, not something to
silently resolve in the diff's favor.

### Step 2: Identify the runtime surface

The surface is where a user — human or programmatic — meets the change. Observation happens there,
nowhere else.

| Change reaches | Surface | Drive it by |
|---|---|---|
| CLI / TUI | terminal | Typing the command, capturing the pane |
| Web UI | browser | Clicking through the real page via Playwright — not curling the API underneath it |
| HTTP / RPC handler | request/response | Sending the real request and reading the real response body |
| Background job / queue consumer | logs, DB state | Triggering the job and reading what it actually wrote |
| Library / internal function | wherever its real caller sits | Trace to the CLI command, route, or render that calls it, then drive that |

A change can reach more than one surface (a UI action that also writes to a queue) — trace all of
them, not just the first one found.

### Step 3: Get a handle on the surface

```bash
ls .claude/skills/                    # target repo root
ls <touched-dir>/.claude/skills/      # each dir level the diff names
```

- A `verifier-*` skill matching the surface from Step 2 (a CLI verifier for a CLI change, and so
  on): invoke it with the `Skill` tool and follow its setup. A mismatched surface: skip it, try the
  next candidate. A stale verifier (fails on mechanics unrelated to the change): ask the user
  whether to patch it — never mark the change FAIL for verifier rot.
- A `run-*` project skill, or the built-in `run` skill, but no matching verifier: use its
  build/launch primitives as the handle.
- Neither: cold-start from the target's README, package manifest, or build file. Timebox this to
  roughly 15 minutes. Stuck: report BLOCKED (Step 7) with exactly where it stopped — check every
  skill under the touched subtree's `.claude/skills/` for one that unlocks the environment
  (headless-runner or login helpers commonly live there) before calling it BLOCKED. Got through:
  persist what was learned — create `.claude/skills/verify/SKILL.md` at the level just probed (the
  repo root for a single-package repo; the touched package/app directory in a monorepo where
  verification is per-package), capturing the build/launch/drive recipe that worked, so the next
  run skips this cold start. Keep it short: the commands that worked, the flows worth driving, any
  gotchas. A project verify skill already exists there: edit it only when it steered this run wrong
  (a documented command failed, or turned out incorrect), or a needed step is missing. Routine,
  unsurprising runs don't warrant an edit, and existing content is never rewritten for style alone.

### Step 4: Drive it

Take the smallest path that makes the changed code execute:

- Changed a flag: run with it.
- Changed a handler: hit that route.
- Changed error handling: trigger the error, not just the happy path.
- Changed an internal function: find the CLI command, request, or render that reaches it, and run
  that — not an `import`-and-call of the function in isolation. That's a unit test written on the
  spot, not a verification: the function did what reading it already showed it would do, and the
  app itself never ran.

Read the plan back before running it. If every step is build, typecheck, or run-the-test-file, that
plan reruns CI — it isn't a verification. Find a step that actually reaches the surface from Step
2, or report BLOCKED.

Drive it end-to-end, through the real interface. Pieces passing in isolation says nothing about
whether the flow works — seams are exactly where bugs hide. If users click buttons, verify by
clicking buttons, not by calling the API underneath.

**Destructive paths.** If the change touches code that deletes, publishes, sends, or writes outside
the workspace, and there is no dry-run or safe target available: do not drive it live. Verify
everything else, and state plainly which path was not exercised and why.

### Step 5: Push on the edges

Confirming the claim checks out is the first half, not the job. The claim is what the author
intended; the value here is what they didn't think to check. Probe around the exact change, at the
same surface just driven:

- New flag/option: empty value, passed twice, combined with a conflicting flag, typo'd — does the
  error name what's wrong?
- New handler/route: wrong method, malformed body, a missing required field, an oversized payload.
- Changed error path: the adjacent errors it didn't touch — did the fix catch those too, or only
  the one case in the diff?
- Interactive/TUI: Ctrl-C mid-operation, resize the pane, paste garbage, rapid-fire the key, Esc at
  the wrong moment.
- State/persistence: do the operation twice, do it with stale state underneath, do it from two
  sessions at once.
- Wander: what's adjacent? What looked slightly off while confirming the main claim? Go back to it.

These aren't a fixed checklist — pick the ones the change actually points at. Stop once the obvious
adjacents are covered or something worth flagging turns up. A probe that finds nothing is still
worth a line in the report: "passed `--from ''`, clean error, exit 2" tells the reader the author
didn't test it, but it holds anyway. This is still driving the real surface, typing what a user
would type wrong — not another test run.

### Step 6: Capture evidence

Stdout, response bodies, screenshots, pane dumps — captured output is evidence; memory of having
seen it is not. Anything unexpected along the way: don't route around it, capture it, note it, and
decide whether it belongs to the change under verification or to the environment. Unrelated
breakage is a finding, not noise to discard.

Shared process state (tmux sessions, ports, lockfiles): isolate it — a fresh `tmux -L <name>`, a
distinct socket, `mktemp -d` — rather than colliding with whatever the user already has running.

### Step 7: Report the verdict

Report inline, in the final message — a file only the model can open is not evidence anyone else
can check. If a tool for sending files to the user directly is available in this session, use it
for screenshots and recordings and let the report name what was sent; otherwise keep the evidence
that matters inline (pane captures, response bodies) rather than only a path.

```
## Verification: <one-line what changed>

**Verdict:** PASS | FAIL | BLOCKED | SKIP

**Claim:** <what it's supposed to do, per the diff and/or the stated claim from Step 1;
note any mismatch between them>

**Method:** <how a handle was found — which verifier/run skill, or cold start — and what
was actually launched>

### Steps
<what was actually run, and what came back, per checklist item if there is one>

### Findings
<Everything noticed, not just bugs — friction, surprises, anything a first-time user would
trip on. "Took three tries to find the right flag." "Error message on the typo was
unhelpful." "Works, but slower than expected." Lower the bar: if it caused a pause, it goes
here. The pause has to be the reviewer's own, from running the app — not from reading the
diff or a review comment; relaying someone else's already-visible finding isn't an
observation. Claim/diff mismatches, pre-existing breakage, and environment notes belong
here too.

Each Step 5 probe gets its own line even when it held — "empty `--from` -> clean error"
tells the reader what was covered, which a bare PASS can't. Lead with a flag on anything
worth interrupting the reader for; plain bullets are context. Empty is acceptable when
nothing stood out, but that itself is rare.>
```

Verdicts:
- **PASS** — the app was run, and the change did what it should at its surface. Not: tests pass,
  the build is clean, or the code looks right on read.
- **FAIL** — it was run and it doesn't do what it should, or it breaks something else, or the claim
  and the diff disagree materially.
- **BLOCKED** — no state was reached where the change is observable: the build broke, the
  environment is missing a dependency, or the handle from Step 3 never came up. Not a verdict on
  the change itself. State exactly where it stopped.
- **SKIP** — no runtime surface exists to verify: docs-only, types-only, or tests-only changes.
  Nothing went wrong; there is simply nothing here to run. State why in one line.

No partial pass: "3 of 4 items passed" is FAIL until all pass or the shortfall is explained away,
never rounded up in the summary.

When genuinely uncertain, FAIL rather than PASS: a false PASS ships something broken; a false FAIL
costs one more look by a human. Ambiguous output is reported as FAIL with the raw capture attached
— it is never interpreted into a verdict.

## Edge cases

| Situation | Handling |
|---|---|
| No diff found anywhere (no upstream, no base branch divergence, clean working tree) | SKIP — nothing to verify, not BLOCKED. |
| Change touches only docs/types/tests, no runtime surface | SKIP, with a one-line reason. |
| Change is destructive (delete/publish/send) with no dry-run or safe target | Verify everything else; state plainly which path was not exercised and why. Never drive it live. |
| A discovered `verifier-*` project skill fails on mechanics unrelated to the change | Ask the user whether to patch it. Never FAIL the change for verifier rot. |
| Invoked from `juel:ship-ticket` Phase 7 and Playwright MCP is unavailable | Ask the user to drive the browser themselves and confirm the affected checklist item(s), recording which were not verified directly. |
| Cold start (Step 3) exceeds the ~15-minute timebox | Report BLOCKED with exactly where it stopped, after checking every skill under the touched subtree's `.claude/skills/` for one that unlocks the environment. |
