---
name: babysit-pr
description: Use after a PR is open to wait for reviews and react until it is ready to merge - polls the PR every 10 minutes, runs juel:receive-review-and-execute on any new human feedback (review, inline or conversation comment), runs the gates, pushes, replies on every item and re-requests review; on a clean approval merges the base branch in, runs the gates and pushes. Never merges the PR. Invoked by juel:ship-ticket Phase 8. Triggers "babysit this PR", "watch my PR for reviews", "/juel:babysit-pr".
metadata:
  requires:
    cli:
      - id: gh
        hard: true
        why: every phase reads the PR and posts replies and review requests through gh
        check: "gh auth status"
      - id: git
        hard: true
        why: phases 3 and 4 merge the base branch and push
        check: "command -v git"
      - id: python3
        hard: true
        why: pr-state.sh parses the GitHub API output with python3
        check: "command -v python3"
    skills:
      - id: juel:receive-review-and-execute
        hard: true
        why: phase 3 delegates every review round to it
    context:
      - id: git-repo
        hard: true
        why: the PR branch is checked out here
        check: "git rev-parse --show-toplevel"
      - id: open-pr
        hard: true
        why: there must be a PR to babysit
        check: "gh pr view <N> --json number"
---

# Babysit PR

Wait on a PR you authored and keep it moving until a reviewer approves it with nothing left
unanswered: every round of human feedback goes through `juel:receive-review-and-execute`, then
the gates, a push, a reply on every item and a re-requested review. A clean approval ends with
the base branch merged in, the gates green and a push. You merge the PR yourself.

**Announce at start:** "Using juel:babysit-pr to watch PR #<n>."

Hard rules, in every phase:

- **Never merge the PR.**
- **Never resolve review threads.** Reply and leave resolving to the reviewer.
- **Never force-push.** Nothing is pushed while a gate is red.
- **Never hand-edit a fix.** Fixes come from `juel:receive-review-and-execute`.

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
| gh (authenticated) | cli | HARD | `gh auth status` | STOP → `gh auth login` |
| git | cli | HARD | `command -v git` | STOP |
| python3 | cli | HARD | `command -v python3` | STOP → install Python 3 |
| juel:receive-review-and-execute | skill | HARD | ships with this plugin | STOP |
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP |
| open PR | context | HARD | `gh pr view <N> --json number` | STOP → open the PR first |

All satisfied renders as: `Preflight: 6/6 OK (gh, git, python3, juel:receive-review-and-execute, git repo, open PR)` / `→ PROCEED: all requirements met.`

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Resolve PR and gates
2. Wait for feedback
3. Remediate and push
4. Final sync and push
5. Report

Phases 2 and 3 repeat once per review round. Set their tasks back to `in_progress` instead of
creating new ones, and put the round number in each evidence line ("round 2: 3 items, pushed
4f2a1c9").

## Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `[pr-number]` | the current branch's PR | The PR to babysit |
| `--gates "<cmd>;<cmd>"` | resolved once in Phase 1 | Gate commands, `;`-separated; ship-ticket passes its Phase 4 set |

Usage: `/juel:babysit-pr`, `/juel:babysit-pr 412`, `/juel:babysit-pr 412 --gates "make test;make lint"`

## Phase 1: Resolve PR and gates

1. PR: the argument, else `gh pr view --json number --jq .number` on the current branch.
2. `gh pr view <pr> --json author,baseRefName,headRefName,url,createdAt`. Refuse if `author` is
   not the current `gh api user --jq .login`: this skill answers reviews on your own PRs only.
3. Remote: the current branch's upstream remote (`git rev-parse --abbrev-ref @{upstream}`, the
   part before `/`). No upstream: the remote whose URL matches the PR's repo.
4. Gates: the `--gates` list when given. Otherwise resolve `test`, `lint`, `typecheck` and
   `build` once, using the "Toolchain commands" section of `juel:ship-ticket`
   (`../ship-ticket/SKILL.md`, relative to this file), and reuse that set for every round. A
   key that resolves to nothing is skipped with a one-line note.
5. Script: `${CLAUDE_PLUGIN_ROOT}/skills/babysit-pr/pr-state.sh` when `CLAUDE_PLUGIN_ROOT` is
   set, otherwise `pr-state.sh` next to this SKILL.md.
6. Cursor: the PR's `createdAt`, so feedback that arrived before this skill started is handled
   in round 1. Quiet-since: now.

## Phase 2: Wait for feedback

Run `sh <script> <pr> --wait --since <cursor> --interval 600 --silence-hours 24 --quiet-since <quiet-since>`.

- **Claude Code:** one Bash call with `run_in_background: true`. Do not poll it, tail it or
  attach a `Monitor`; the completion notification wakes you. Never `sleep` in the foreground.
- **Codex:** run it in the foreground with `--max-seconds 540` added, and run it again on
  `wake: timeout` with the same arguments.

Act on the printed object's `wake`:

| `wake` | Action |
|---|---|
| `feedback` | Phase 3 with this object's `new_feedback`, `reviewers` and `cursor` |
| `approved` | Phase 4 |
| `closed` | Phase 5: report "PR was closed or merged by someone else" and stop |
| `errors` | Tell the user the `error` in one line, then wait again (same arguments) |
| `silence` | Tell the user once "no feedback for 24 h, still waiting", then wait again with `--silence-hours 0` |
| `timeout` | Codex only: wait again |

## Phase 3: Remediate and push

1. Invoke `/juel:receive-review-and-execute <pr>`. It merges the base branch, reads every
   thread, validates findings into actionable / rejected / ambiguous, asks the user about
   ambiguous ones, writes a plan and runs the executor. Keep its final per-finding outcome: it
   is the source for every reply below.
2. If it ended with zero actionable findings, skip to step 5.
3. Run every gate. Red: invoke `/juel:receive-review-and-execute <pr>` again with the failing
   command and its output as context. Two red gates in a row: stop and ask the user. Never
   hand-edit.
4. `git push <remote> HEAD`. A rejected push means the remote moved: fetch, merge
   `<remote>/<head-branch>`, re-run the gates, push again. Never force-push.
5. Reply to every item in this round's `new_feedback`:
   - fixed: `Fixed in <short-sha>: <one line on what changed>`
   - declined: the technical reason from the validation
   - ambiguous: the user's decision and what was done
   Inline items (`kind: inline`): one threaded reply each, posted to the thread root, which is
   `in_reply_to` when set and `id` otherwise:
   `gh api -X POST repos/<owner>/<repo>/pulls/<pr>/comments/<root>/replies -F body=@<tmpfile>`.
   Review bodies and conversation comments (`kind: review` / `comment`): one PR comment that
   quotes each item and answers it under the quote: `gh pr comment <pr> --body-file <tmpfile>`.
   Write bodies to temp files; never inline a HEREDOC into the command.
6. `gh pr edit <pr> --add-reviewer <reviewers joined by ,>` using this round's `reviewers`.
7. Cursor = this round's `cursor`. Quiet-since = now. Back to Phase 2.

## Phase 4: Final sync and push

1. `git fetch <remote> <base>` then `git merge --no-edit <remote>/<base>`.
   Conflicts: list the conflicted files, stop and ask the user to resolve or abort
   (`git merge --abort`). Never resolve conflicts silently.
2. Already up to date and nothing unpushed (`git status -sb` shows no `ahead`): go to step 5.
3. Run every gate. Red: stop and report the failing command and output. Push nothing.
4. `git push <remote> HEAD`. Never force-push.
5. Run `sh <script> <pr> --since <cursor>` once more. If new feedback arrived while this phase
   was running, go to Phase 3 with it. Otherwise Phase 5.

## Phase 5: Report

- PR URL and final state
- rounds handled, with items fixed / declined / decided per round
- final gate result and the pushed head
- the outcome: **"Ready for you to merge"**, or why it stopped (closed, merged, red gate,
  merge conflict, user stop)

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Replying to a reply id | Reply to the thread root: `in_reply_to` when set |
| Treating the Linear link-back bot as feedback | `pr-state.sh` drops every `[bot]` author; never add your own filter on top |
| Pushing after a red gate "because the fix is obvious" | Back through `receive-review-and-execute`, or stop and ask |
| Ending on approval without re-checking | Phase 4 step 5: new feedback arrived while you were gating goes back to Phase 3 |
| Resolving threads after replying | Leave them; the reviewer resolves |
| Polling in the foreground in Claude Code | One background `--wait` call; the notification wakes you |
