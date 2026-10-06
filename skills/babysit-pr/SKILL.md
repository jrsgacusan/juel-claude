---
name: babysit-pr
description: Use after a PR is open to wait for reviews and react until it is ready to merge - polls the PR every 10 minutes, runs juel:receive-review-and-execute on any new human feedback (review, inline or conversation comment), runs the gates, pushes, replies on every item and re-requests review; on a clean approval merges the base branch in, runs the gates and pushes. Never merges the PR. Invoked by juel:ship-ticket Phase 8; with --unattended it runs as a juel:star Orca worker, marks a draft ready once, escalates instead of asking and holds reviewer-facing actions during quiet hours. Triggers "babysit this PR", "watch my PR for reviews", "/juel:babysit-pr".
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
| `--gates-file <path>` | — | A JSON gate manifest (`{"test":{"cmd":…,"cwd":…},…}`, `null` for a skipped key) written by `juel:ship-ticket`'s build; each command runs in its `cwd`. Wins over `--gates`; an all-null manifest means no gates |
| `--unattended` | off | No human answers: see "Unattended mode". Requires `--item` |
| `--item <item>` | — | The work item's name for report lines (its ref, or its slug) |
| `--mark-ready` | off | Mark a draft PR ready for review once, in Phase 1 (deferred while inside `--quiet-hours`) |
| `--quiet-hours <HH:MM-HH:MM@tz>` | off | Window in which marking ready, replies and review requests wait; pushes still happen |
| `--brief <path>` | — | The item's approved brief. Passed on to `receive-review-and-execute`, which refuses reviewer requests outside its scope |
| `--since <iso>` | the PR's `createdAt` | Feedback cursor: only feedback after it is handled. A resumed run passes the `cursor` from its last `READY`, so earlier comments are never re-answered |

Usage: `/juel:babysit-pr`, `/juel:babysit-pr 412`, `/juel:babysit-pr 412 --gates "make test;make lint"`,
or as a `juel:star` worker `/juel:babysit-pr 412 --unattended --mark-ready --item SAVI-1162 --gates "make test" --quiet-hours 22:00-07:00@Asia/Manila`

## Unattended mode

`--unattended` is how a `juel:star` Orca worker runs this skill after the second-model review said SAFE. Nobody
is there to answer, so every place below that tells the user something or asks them changes:

| Normally | With `--unattended` |
|---|---|
| Phase 2 waits in the background (Claude Code) | Always the foreground form with `--max-seconds 540`, repeated on `wake: timeout`: a background wait may never wake a headless session. The same applies whenever `--quiet-hours` is set, unattended or not, so deferred commands run within minutes of the window ending |
| `approved` wake needs `reviewDecision: APPROVED` | also on each `timeout` wake when `decision` is null or an empty string (`gh pr view` reports `""` when the base branch requires no review): `gh pr view <pr> --json reviews,commits` → an `APPROVED` review submitted after the last commit, and no `CHANGES_REQUESTED` after it, counts as approved → Phase 4 |
| no limit on waiting | 72 h with no new feedback since the PR was marked ready → `ESCALATION item=<item> phase=8 reason=no-review needs=a reviewer`, after flushing (below) |
| `errors`: tell the user, wait again | wait again; three `errors` in a row → `ESCALATION item=<item> phase=8 reason=pr-state-errors needs=<the error>` |
| `silence`: tell the user once | say nothing; wait again with `--silence-hours 0` |
| `receive-review-and-execute` asks about ambiguous findings or merge conflicts | invoke it with `--unattended --only <ids>`, the ids of this round's `new_feedback` (older threads are context only, so feedback already answered is never re-planned or re-escalated), plus `--brief <path>` when given; its `BRIEF-VIOLATION:` lines → `ESCALATION item=<item> phase=8 reason=brief-violation needs=<each request>`; its `AMBIGUOUS:` lines → `ESCALATION item=<item> phase=8 reason=ambiguous-review needs=<each ambiguous finding>`. When the brief has a `star:` block, first write `<star.home>/drafts/<YYYY-MM-DD>-<star.project>-<item>-reply.md` (each ambiguous comment with its author and link, then two or three candidate decisions for it) and add `DRAFT <path>` to the report, so the human answers from a draft instead of from the thread; its `CONFLICT:` line → `ESCALATION item=<item> phase=8 reason=merge-conflict needs=<conflicted files>` |
| two red gates in a row: stop and ask | `ESCALATION item=<item> phase=8 reason=gate-red needs=<command and output>` |
| a question sent with `orca orchestration ask` comes back "No answer from the user: escalate this." | `ESCALATION item=<item> phase=8 reason=unanswered-question needs=<the question>` |
| merge conflicts: stop and ask | `git merge --abort`, then `ESCALATION item=<item> phase=8 reason=merge-conflict needs=<conflicted files>` |
| `receive-review-and-execute` prints `STOPPED: <reason>` | `ESCALATION item=<item> phase=8 reason=remediation-stopped needs=<reason>`; never read it as "zero actionable" |
| Phase 4 ends after the push | **wait for CI and the approval** before reporting: poll `gh pr checks <pr> --json name,bucket` in foreground calls of at most 540 s until no check is `pending`. Any `fail` or `cancel` → `ESCALATION item=<item> phase=8 reason=ci-failed needs=<failing or cancelled check names>`. Then re-read `reviewDecision` (null and an empty string mean the repo requires no review). If the push dismissed the approval, or (no review required) the only `APPROVED` reviews are now older than the push, run `gh pr edit <pr> --add-reviewer <each reviewer whose approval is now older than the last commit or was dismissed>` (a reviewer-facing action, deferred in quiet hours), then go back to Phase 2 |
| Phase 5 report | its last line is `READY item=<item> pr=<url> head=<pushed sha> cursor=<last cursor>` (only on "Ready for you to merge", with checks green); any other outcome is an `ESCALATION` with the reason. The `worker_done` body is at most 12 lines: that line is the first line of the `worker_done` body, then any `HELD` lines and at most one `NOTE: <one line>` (a fact the next worker in this project should know); `--outcome failed` for an `ESCALATION` |
| gates run directly | run them through `juel:ship-ticket`'s `gate-lock.sh` (`../ship-ticket/gate-lock.sh` from this file, or `${CLAUDE_PLUGIN_ROOT}/skills/ship-ticket/gate-lock.sh`): `sh <gate-lock.sh> --holder "<item>" -- sh -c '<each gate as cd <cwd> && <cmd>, joined with &&>'`, run in the background, like `codex exec` (`run_in_background: true`, wait for the completion notification, never poll it): waiting for the lock plus the gates can outlast the 600 s foreground cap. Exit 75 means busy: run it again |

**Nothing deferred is lost.** Before printing `READY`, run every deferred command; if the quiet
window is still on, keep waiting in Phase 2 (feedback that arrives meanwhile is handled as usual)
until it ends, then run them. Before printing an `ESCALATION`, print one
`HELD item=<item> action=<the deferred command>` line per command that has not run, so the driver
records it as an open loop.

**Quiet hours.** With `--quiet-hours`, check the window at the moment of each reviewer-facing
action, not once at the start (`now=$(TZ="<tz>" date +%H:%M)`; inside when start <= end:
start <= now < end; across midnight: now >= start || now < end). Inside it, `gh pr ready`, Phase 3's
replies (step 5) and review requests (step 6) are **deferred**: keep each composed body in its temp
file and the pending commands in order, keep waiting in Phase 2, and run every deferred command, in
order, at the first wake after the window ends. Fixes, gates and pushes never wait. A deferred
`gh pr ready` means no reviewer sees the PR yet, so Phase 2 simply times out until the window ends.

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
6. Cursor: `--since` when given, else the PR's `createdAt`, so feedback that arrived before this
   skill started is handled in round 1. Quiet-since: now.
7. With `--mark-ready` and a draft PR (`gh pr view <pr> --json isDraft`): `gh pr ready <pr>`, once,
   or defer it per "Unattended mode" when inside `--quiet-hours`. A PR that is already ready is left
   alone. Never mark it ready a second time.

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

1. Invoke `/juel:receive-review-and-execute <pr>` (under `--unattended`: `/juel:receive-review-and-execute <pr> --unattended --only <ids> [--brief <path>]`, see "Unattended mode"). It merges the base branch, reads every
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
   Skip this step when the round's `decision` is `APPROVED`: the reviewer already approved and
   only asked for follow-up changes, so the fixes, push and replies are enough. Say "approved
   PR: review not re-requested" in the round's evidence line.
7. Cursor = this round's `cursor`. Quiet-since = now. Back to Phase 2. On an approved PR the
   next wait wakes with `approved` unless new feedback arrived, which leads to Phase 4. If
   branch protection dismissed the approval on push, `decision` is no longer `APPROVED` and
   the wait continues as normal.

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
