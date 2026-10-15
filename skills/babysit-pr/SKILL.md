---
name: babysit-pr
description: Use after a PR is open to wait for reviews and react until it is ready to merge - polls the PR every 10 minutes, runs juel:receive-review-and-execute on any new human feedback (review, inline or conversation comment), runs the gates, pushes, replies on every item and re-requests review; on a clean approval merges the base branch in, runs the gates and pushes. Never merges the PR. On a PR someone else authored it runs reviewer mode instead: waits for the author's re-request or a settled push, re-reviews through juel:review-pr and asks before every post. Invoked by juel:ship-ticket Phase 8; with --unattended it runs as a juel:star Orca worker: marks a draft ready once, gets the hosted reviewer's passes or a person's approval, re-gates every push with a headless codex review, escalates instead of asking and holds reviewer-facing actions during quiet hours. Triggers "babysit this PR", "watch my PR for reviews", "/juel:babysit-pr".
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
      - id: orca
        hard: false
        why: an unattended worker asks its coordinator and reports through orca orchestration
        check: "command -v orca"
        fallback: an interactive run does not need it; an unattended run stops with the preflight escalation
    skills:
      - id: juel:receive-review-and-execute
        hard: true
        why: phase 3 delegates every review round to it
      - id: juel:review-pr
        hard: true
        why: reviewer mode's phase 3 runs every re-review through it
    context:
      - id: git-repo
        hard: true
        why: the PR branch is checked out here
        check: "git rev-parse --show-toplevel"
      - id: open-pr
        hard: true
        why: there must be a PR to babysit
        check: "gh pr view <N> --json number"
      - id: interactive-user
        hard: false
        why: reviewer mode asks the user before every post, through juel:review-pr
        check: none
        fallback: reviewer mode stops; author mode runs
---

# Babysit PR

Wait on a PR you authored and keep it moving until a reviewer approves it with nothing left
unanswered: every round of human feedback goes through `juel:receive-review-and-execute`, then
the gates, a push, a reply on every item and a re-requested review. A clean approval ends with
the base branch merged in, the gates green and a push. You merge the PR yourself. On a PR someone else authored, it runs **reviewer mode** instead (below):
it waits until the author is ready for you again and re-reviews through `juel:review-pr`.

**Announce at start:** "Using juel:babysit-pr to watch PR #<n>."

Hard rules, in every phase:

- **Never merge the PR.**
- **Never resolve review threads** on your own PR. Reply and leave resolving to the reviewer. In reviewer mode you are the reviewer: a thread you opened is resolved only by `juel:review-pr`'s gated post, never by this skill.
- **Never force-push.** Nothing is pushed while a gate is red.
- **Never hand-edit a fix.** Fixes come from `juel:receive-review-and-execute`, or, for the codex gate's findings, from a fix plan the executor runs.

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v9 -->

**0. Harness check, before every other rule.** You are running in Codex when you have the `update_plan` tool and no `Skill` tool. Only then read `references/harness-codex.md`, resolved relative to this skill file's own location (`../../references/harness-codex.md`), and apply its construct map, corrected facts, dependency substitutions and degradation contract to every rule below and to every phase body in this skill. This single read is the one action permitted before rule 1's preflight, and only in that case. In every other case, Claude Code without the `TaskCreate` tool included, ignore that file entirely and continue to rule 1.

**1. Preflight, then task list, before anything else.** Before any other output and before any tool call, emit the Preflight block (below). If the preflight verdict is STOP, print the preflight block and **stop** — do not create tasks and do not begin work. Otherwise, before any other work, create one task per phase in this skill's `## Phases` list via `TaskCreate` — `subject` is the phase name, `activeForm` is its present-continuous form. This task list, rendered persistently by the harness, IS the checklist; nothing else satisfies this rule. This is not optional on re-invocation, on resume, or when the user says "just do it".
- **If `TaskCreate`/`TaskUpdate` are not in your tool list, or genuinely fail** — one attempted call returns an error; never assumed unavailable without checking the tool list — use `TodoWrite` when you have it (one todo per phase, the same names, updated at every transition), else an explicit numbered phase log, printed after every phase transition with the same one-line evidence rule 3 already requires. State the degradation once, in one line, before continuing. Never silently swap to prose without saying so.

**2. Phases run in order.** No skipping, reordering, or merging. A phase that does not apply is still announced, not dropped: mark its task `completed` via `TaskUpdate`, with the one-line evidence required by rule 3 stating the skip reason (e.g. "SKIPPED: <reason>") — the task list has no separate "skipped" status, so a skipped phase becomes `completed` too. Never begin phase N+1 before phase N's task is marked `completed`.

**3. Report after every phase.** Mark the phase's task `in_progress` via `TaskUpdate` when starting it, then `completed` via `TaskUpdate` when it finishes or is skipped — each transition accompanied by exactly one line of evidence (path written, command run, count found). Do not re-print the checklist as text; the task list is the persistent record and replaces that. Never claim progress in prose alone.

**4. `review-pr`'s agents run in PARALLEL and FOREGROUND; `code-simplifier` runs FOREGROUND; `codex exec` runs BACKGROUND, WATCHED, and WAITED-ON.** This overrides every other instruction in this file and in any skill invoked from it. Foreground/background is about whether the tool call blocks; watched is about whether output still streams somewhere the user can see it — these are different axes, and `codex exec` needs the second without the first. `review-pr`'s agents additionally need PARALLEL: dispatched together, not one at a time.
- `pr-review-toolkit:review-pr`'s agents MUST be dispatched in parallel: pass `all parallel`, or dispatch the agents together in ONE message. Its sequential default — one agent at a time — is the exact slowness this rule exists to prevent; requesting it, or omitting `all parallel`, is a violation.
- `pr-review-toolkit:review-pr` and `code-simplifier` are foreground-only. When your Agent tool has a `run_in_background` parameter, invoke both with `run_in_background: false` **explicitly** — the harness backgrounds subagents by default, so omitting the flag is a violation, not a neutral choice. Dispatching review-pr's agents in parallel does not relax this: each agent in that one message still carries its own explicit `run_in_background: false`. When your Agent tool has no such parameter, dispatch every one of them together in one message, wait for each one's completion, read each result in full, and check `ListAgents` before treating an idle agent as empty (rule 6); the phase never ends while one is still out. Never `&`. Never `run_in_background: true` for these two. Never "dispatch and continue".
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
| orca | cli | SOFT | `command -v orca` | an interactive run does not need it; an unattended run stops with the preflight escalation |
| juel:receive-review-and-execute | skill | HARD | ships with this plugin | STOP |
| juel:review-pr | skill | HARD | ships with this plugin | STOP |
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP |
| open PR | context | HARD | `gh pr view <N> --json number` | STOP → open the PR first |
| interactive user | context | SOFT | none: render as `?` | reviewer mode stops; author mode runs |

All satisfied renders as: `Preflight: 9/9 OK (gh, git, python3, orca, juel:receive-review-and-execute, juel:review-pr, git repo, open PR, interactive user)` / `→ PROCEED: all requirements met.`

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
| `[pr-number]` | the current branch's PR | The PR to babysit. One you did not author runs reviewer mode (Phase 1 step 2) |
| `--gates "<cmd>;<cmd>"` | resolved once in Phase 1 | Gate commands, `;`-separated; ship-ticket passes its Phase 4 set |
| `--gates-file <path>` | — | A JSON gate manifest (`{"test":{"cmd":…,"cwd":…},…}`, `null` for a skipped key) written by `juel:ship-ticket`'s build; each command runs in its `cwd`. Wins over `--gates`; an all-null manifest means no gates |
| `--unattended` | off | No human answers: see "Unattended mode". Requires `--item`. Refused in reviewer mode |
| `--item <item>` | — | The work item's name for report lines (its ref, or its slug) |
| `--mark-ready` | off | Mark a draft PR ready for review once, in Phase 1 (deferred while inside `--quiet-hours`). Under `--unattended` it needs `--reviewed`. A PR the build already marked ready is left as it is: under STAR the flag only acts when quiet hours kept the PR a draft |
| `--reviewed <path>` | — | The proof that this head passed the gate before it is shown to people: the item's newest review from `juel:star`'s `codex-gate.sh`, whose first line is `VERDICT … SAFE … head=<sha>`, or that round's `<item>-r<k>-carried.md` when the owner shipped with the round's findings deferred (`review-proof.sh` prints `OK carried round=<k>` for it) |
| `--quiet-hours <HH:MM-HH:MM@tz>` | off | Window in which marking ready, replies and review requests wait; pushes still happen. The word `always` means the user is away: every moment is inside it |
| `--brief <path>` | — | The item's approved brief. Passed on to `receive-review-and-execute`, which refuses reviewer requests outside its scope |
| `--executor <session|codex>` | `codex` | Who runs a remediation plan: passed on to `receive-review-and-execute` unchanged. `session` means this session runs it; `codex` dispatches `codex exec` |
| `--executor-model <id|latest-<family>>` | `star.json`'s `executor.model` under a `star:` brief, else `latest-luna` | Passed on to `receive-review-and-execute` |
| `--executor-effort <level>` | `star.json`'s `executor.effort` under a `star:` brief, else `xhigh` | Passed on to `receive-review-and-execute` |
| `--since <iso>` | the PR's `createdAt` | Feedback cursor: only feedback after it is handled. A resumed run passes the `cursor` from its last `READY`, so earlier comments are never re-answered |

Usage: `/juel:babysit-pr`, `/juel:babysit-pr 412`, `/juel:babysit-pr 412 --gates "make test;make lint"`,
or as a `juel:star` worker `/juel:babysit-pr 412 --unattended --mark-ready --item SAVI-1162 --gates "make test" --quiet-hours 22:00-07:00@Asia/Manila`

## Unattended mode

`--unattended` is how a `juel:star` Orca worker runs this skill after the build's codex gate said SAFE and STAR checked its report.
With `--brief`, first read the files under the brief's `star.notes`, then its `## Decisions`
section if it has one: the human's dated answers to earlier escalations on this item. A decision
settles the reviewer comment it answers: apply it, and never escalate that comment again. Nobody
is there to answer, so every place below that tells the user something or asks them changes.
Each row overrides the phase step it names: under `--unattended` or `--quiet-hours`, read this
table before doing a step, even where the step's own text does not point back here.

| Normally | With `--unattended` |
|---|---|
| Phase 2 waits in the background (Claude Code) | Always the foreground form with `--max-seconds 540`, repeated on `wake: timeout`: a background wait may never wake a headless session. The same applies whenever `--quiet-hours` is set, unattended or not, so deferred commands run within minutes of the window ending |
| `approved` wake needs `reviewDecision: APPROVED` | also on each `timeout` wake when `decision` is null or an empty string (`gh pr view` reports `""` when the base branch requires no review): `gh pr view <pr> --json reviews,headRefOid` → an `APPROVED` review whose `commit.oid` is the PR's `headRefOid`, and no reviewer whose latest review (of `APPROVED`, `CHANGES_REQUESTED`, `DISMISSED`) is `CHANGES_REQUESTED`, counts as approved → Phase 4 (the same rule `juel:star`'s final check uses, so `READY` is never followed by "changes requested by …"). A PR whose snapshot says `draft: true` is never approved for this purpose: see the `draft` wake. Dates are never compared: a commit made earlier and pushed later is older than the approval and was still never reviewed. Where the base branch's rules explicitly require 0 approving reviews, `pr-state.sh` itself wakes `approved` once no reviewer's latest review is `CHANGES_REQUESTED` and every check on the head has finished green, the required ones included (its snapshot says `approval: required` and `required: 0`): no approval is waited for, and none is looked for on these timeout wakes. A repo with no review rule (`approval: none`), or one the script could not read (`unknown`), keeps the rule above. With a hosted reviewer (the rows below), its clean pass on the head stands in for this approval: there is no approval to wait for unless a branch rule asks for one, which GitHub then enforces. |
| no limit on waiting | 72 h with no new feedback since the PR was marked ready → `ESCALATION item=<item> phase=8 reason=no-review needs=a reviewer`, after flushing (below) |
| `errors`: tell the user, wait again | wait again; three `errors` in a row → `ESCALATION item=<item> phase=8 reason=pr-state-errors needs=<the error>` |
| an `errors` or `timeout` wake whose `error` starts with `gh cannot see` | first look for the project's token rule: the files under the brief's `star.notes` (the project's memory notes) may name a `GH_TOKEN` rule, a command that prints the token (a keychain lookup, say). When one does, run the same wait once more with it in front, `GH_TOKEN="$(<that command>)" sh <script> …`, and put the same prefix on every later command that reaches GitHub, because an `export` does not outlive one shell call. No such rule, or `gh cannot see` again with it: at once, without waiting for three: `ESCALATION item=<item> phase=8 reason=needs-human-input needs=<the error>`; waiting again cannot fix a token. With `star.json`'s `tokenCmd` set, the plugin's session hook already gives every session the token |
| `silence`: tell the user once | say nothing; wait again with `--silence-hours 0` |
| `receive-review-and-execute` asks about ambiguous findings or merge conflicts | invoke it with `--unattended --only <ids>`, the ids of this round's `new_feedback` (older threads are context only, so feedback already answered is never re-planned or re-escalated), plus `--brief <path>` when given; its `BRIEF-VIOLATION:` lines → `ESCALATION item=<item> phase=8 reason=brief-violation needs=<each request>`; its `AMBIGUOUS:` lines → `ESCALATION item=<item> phase=8 reason=ambiguous-review needs=<each ambiguous finding>`. When the brief has a `star:` block, first write `<star.home>/drafts/<YYYY-MM-DD>-<star.project>-<item>-reply.md` (each ambiguous comment with its author and link, then two or three candidate decisions for it) and add `DRAFT <path>` to the report, so the human answers from a draft instead of from the thread; its `CONFLICT:` line → `ESCALATION item=<item> phase=8 reason=merge-conflict needs=<conflicted files>` |
| two red gates in a row: stop and ask | write the failing output to `<star.home>/reviews/<star.project>/<item>-gate.log` (or a temp file without a `star:` brief), then `ESCALATION item=<item> phase=8 reason=gate-red cursor=<last cursor> needs=<command> failed, output in <that path>`. A red is refunded, and does not count toward the two, when the fix for it changed only files outside runtime (`juel:ship-ticket` Phase 6 step 6's definition: test files, docs the app does not load, paths a memory note or the brief names), read from `git diff --name-only <the commit before the fix>..HEAD`. At most two such reds are refunded between two green gates; a third counts. The fix still comes from `receive-review-and-execute` or a fix plan, never by hand |
| every `ESCALATION` line in this table | has the shape `ESCALATION item=<item> phase=8 reason=<reason> cursor=<last cursor> needs=<one line>`. `<last cursor>` here is the cursor this round started from (the `--since` of the wait that woke it), never the wake object's own `cursor`: that one only becomes the cursor in Phase 3 step 7, after the round's items were fixed and answered. A round that escalates has answered nothing, so a restarted run must see its items again. The cursor is an opaque string from `pr-state.sh`: pass it back exactly as it came. It lets a restarted run skip feedback already answered, and `needs=` is always one line (long output goes in a file whose path it names) |
| Phase 2 wakes with `closed` and the PR is merged | not an escalation: the report's first line is `MERGED item=<item> pr=<url>`, and the run ends. A PR closed without a merge is `ESCALATION … reason=pr-closed` |
| `decision` is `CHANGES_REQUESTED`, this run has had nothing to act on since it started or since its last push, and 24 h have passed (a bot, or a reviewer who left no comment, blocks the PR; a reviewer who was just re-requested gets the same 24 h) | `ESCALATION item=<item> phase=8 reason=blocked-without-feedback needs=changes were requested with no comment to act on` |
| stuck on the same thing three times (a gate, a tool, two ways to read a comment) | ask the coordinator before escalating: `orca orchestration ask --question "<one question, with what you tried>" --json`. Its answer binds like a Decision. A check-in message from the coordinator in the terminal gets a one-line answer, then carry on |
| a question sent with `orca orchestration ask` comes back "No answer from the user: escalate this." | `ESCALATION item=<item> phase=8 reason=unanswered-question needs=<the question>` |
| merge conflicts `merge-union.sh` cannot resolve: stop and ask | `git merge --abort`, then `ESCALATION item=<item> phase=8 reason=merge-conflict needs=<conflicted files>` |
| `receive-review-and-execute` prints `STOPPED: <reason>` | `ESCALATION item=<item> phase=8 reason=remediation-stopped needs=<reason>`; never read it as "zero actionable" |
| before `READY`, whether or not Phase 4 pushed | **wait for CI and the approval** before reporting (the last Phase 3 push's checks may still be running when Phase 4 has nothing to push): poll `gh pr checks <pr> --json name,bucket` in foreground calls of at most 540 s until no check is `pending`, for at most 3 hours in all. `gh pr checks` exiting 1 with "no checks reported" means none has registered yet: that is pending for the first 5 minutes after the last push. After that it means "this repo has no CI" only when the base branch's head has no check runs either: `gh api repos/<owner>/<repo>/commits/<base>/check-runs --jq .total_count` prints `0`. Otherwise read `gh pr view <pr> --json mergeStateStatus --jq .mergeStateStatus`. On a PR that is not `DIRTY`: `ESCALATION item=<item> phase=8 reason=ci-missing cursor=<last cursor> needs=no CI ran on head <sha> (PR <mergeStateStatus>)`, `<sha>` being the PR's head. On a `DIRTY` PR the `conflict` wake acts first (Phase 2), and the report carries `NOTE: no CI ran on head <sha7> (PR DIRTY)`, `<sha7>` being that head's first 7 characters. Also before `READY`: one last snapshot, and `draft: true` in it is the `pr-draft-again` escalation, never `READY`; still pending then → `ESCALATION item=<item> phase=8 reason=ci-stuck needs=<the pending check names>`. Any `fail` or `cancel` → `ESCALATION item=<item> phase=8 reason=ci-failed needs=<failing or cancelled check names>`. Then re-read `reviewDecision` (null and an empty string mean the repo requires no review). If the push dismissed the approval, or (no review required, and the snapshot does not say `required: 0`) no `APPROVED` review has the new head as its `commit.oid`, run `gh pr edit <pr> --add-reviewer <each reviewer whose approval is for an older commit or was dismissed>` (a reviewer-facing action, deferred in quiet hours), then go back to Phase 2. With a hosted reviewer, its clean pass on the head stands in for this approval: there is no approval to wait for unless a branch rule asks for one, which GitHub then enforces. |
| Phase 5 report | its state line is `READY item=<item> pr=<url> head=<pushed sha> cursor=<last cursor>`, with the full 40-character sha as `<pushed sha>` (STAR's merge takes no shorter one) (only on "Ready for you to merge", with checks green; here `<last cursor>` is the newest cursor, everything before it is answered); a hosted review still not clean after its passes, or a gate still NOT SAFE after `gate.maxRounds` rounds, is `RESCOPE item=<item> reason=<hosted-review|gate> review=<path>` with `--outcome succeeded`; any other outcome is an `ESCALATION` with the reason. Print it as the last line in the terminal; the `worker_done` body starts with it. The `worker_done` body is these report lines and nothing else. It overrides any request for a prose summary, Orca's worker preamble included. The `worker_done` body is at most 12 lines: that line is the first line of the `worker_done` body, then `SENT replies=<n> review-requests=<m> base-syncs=<s>` when anything was posted or pushed for a base sync in this run (the coordinator logs it for the user's summary; `base-syncs=` counts Phase 2's syncs of a dirty PR), at most one `DRAFT <path>` (one draft file holds every ambiguous comment), one `HELD` line for all deferred commands together (below), at most two other `HELD` lines (more: write them to a file and report one `HELD item=<item> action=<n> held actions, listed in <path>`), at most one `NOTE: <one line>` of your own (a fact the next worker in this project should know), `NOTE: executor skill missing, the plan ran in this session` when `receive-review-and-execute` or a gate fix plan ran in this session for that reason, `NOTE: no CI ran on head <sha7> (PR DIRTY)` once when the wait for CI met a `DIRTY` PR (the row above), `NOTE: scope outside-merged <path>[, <path> ...]` once, relayed from `receive-review-and-execute` and naming every such path it reported in this run, and at most one `STAR-ISSUE: <one line>` (friction with STAR's own contract or tools, no project names). That is 11 lines at most, so the first line, with its head and cursor, is never dropped to fit; `--outcome failed` for an `ESCALATION` |
| gates run directly | run them through `juel:ship-ticket`'s `gate-lock.sh` and `run-gates.sh` (`../ship-ticket/` from this file, or `${CLAUDE_PLUGIN_ROOT}/skills/ship-ticket/`): `sh <gate-lock.sh> --holder "<star.project>/<item>" --progress <star.home>/progress/<item>.log -- sh <run-gates.sh> <the --gates-file manifest> --root <repo root>` (under a `star:` brief the holder is `<star.project>/<item>`, so two projects with an item of the same name never stop each other's gate; without a `star:` brief, leave out `--progress` and use `--holder "<item>"`): while the lock is busy, `gate-lock.sh` appends a `regression-gate` progress line when it starts waiting and another every 10 minutes, so STAR reads a worker queued for the lock as moving. `run-gates.sh` runs each gate in its own `cwd`, taken from the repo root, exactly as the manifest has it; never paste a gate command into a quoted `sh -c '…'` string (one quote in the command silently drops the rest). With `--gates` and no manifest, write the commands to a file, one per line under `set -e`, and run `-- sh <that file>`. Targeted tests go through the lock the same way, as such a file. The sweep is the same `run-gates.sh` line with `sweep` after `--root <repo root>`; with no manifest, it is the `test` command. Run it in the background, like `codex exec` (`run_in_background: true`, wait for the completion notification, never poll it): waiting for the lock plus the gates can outlast the 600 s foreground cap. Exit 75 means busy: run it once more; a second 75 → `ESCALATION item=<item> phase=8 reason=gate-busy needs=<its "busy, held by …" line>`. Exit 71 with `dependencies are not installed` in its message: run the install command once (Phase 1 step 4, with its escalation when the install fails), then the same line once more; a second 71 is the `gate-unavailable` escalation. Exit 71 or 124 (the gate could not run, or ran past its time limit) → `ESCALATION item=<item> phase=8 reason=gate-unavailable needs=<the script's message>`, never a red gate |
| `--mark-ready` on a draft PR | first the proof, checked by the script and never by eye: `sh <review-proof.sh> <the --reviewed file> --item <item> --head <the PR's current headRefOid>` (`review-proof.sh` is next to this file). It prints `OK round=<k>` only when the file's first line is a full `VERDICT` line for this item that says `SAFE`, its `head=` is at least 7 characters and the start of the PR's head, and it is the newest review file for the item (a later round replaces an earlier verdict). It prints `OK carried round=<k>` for an owner's carried PASS: a `<item>-r<k>-carried.md` file STAR wrote when the owner chose to ship round `k`'s head with its findings deferred, valid while its `head=` starts the PR's head and no newer round exists. Both `OK` forms are proof. A `NO …` is not final yet when the head is a merge of the base branch made after the review (a carry, see the push-gate row), which `review-proof.sh` rejects because the review names the head before the merge: when the newest `<star.reviews>/<item>-r<k>.md` says `SAFE` on its first line, run `git fetch <remote> <base>` and `sh <carry-check.sh> --from <its head=> --head <the PR's current headRefOid> --base <remote>/<base>` (`../star/carry-check.sh` from this file). `OK carried from …` is proof as well, and no codex round is spent on a merge that brings no change to a file this branch changes, as `carry-check.sh` decides. Any other `NO …`, no `--reviewed`, or a script that cannot run → leave the PR a draft and `ESCALATION item=<item> phase=8 reason=no-safe-verdict needs=a SAFE second-model review of <current head> (<what the script said>)`. A PR that is already ready needs no proof: it was shown to people before this run. Run the checks again right before a deferred `gh pr ready`: the head may have moved while the quiet window was on |
| an owner's carried PASS (`--reviewed` names a `<item>-r<k>-carried.md` file) | in Phase 1, once the proof says `OK carried round=<k>`, post its receipt: `sh <codex-gate.sh> post-pass --pr <url> --round <k> --head <the PR's full head> --review <that file>` (`../star/codex-gate.sh` from this file; deferred in quiet hours like any `post-pass`). `posted <url>` and `already <url>` both end the step. The receipt names the owner's decision: never write one by hand. `ERROR …` twice, a minute apart → `ESCALATION item=<item> phase=8 reason=review-unavailable cursor=<last cursor> needs=<its ERROR line>` |
| Phase 4 step 3, a red gate | once: back through `receive-review-and-execute` with the failing output, as in Phase 3 step 3. Twice in a row, counted as the row above counts them (a red whose fix stayed outside runtime is refunded): the `gate-red` escalation above. Nothing is pushed on red |
| settings | under a brief with a `star:` block, read `<star.home>/star.json` once in Phase 1: `gate` (`model`, `effort`, `fallback`, `maxRounds`) and `hostedReviewer` (`login`, `minScore`, `maxPasses`, `refreshOutsideCap`, true when absent, or null), and `mcps` (what STAR's session found: Mobbin for user-facing design decisions, citing the screen or flow URL; context7 for library, framework, SDK, API and CLI docs at the version the project uses). When a reviewer's comment turns on a library's behaviour or a design choice, check it there before accepting or declining it, using an MCP only when your own session lists its tools; otherwise a web search, named in the reply. Flags win over `gate` only: `hostedReviewer` has no flag |
| progress | under a `star:` brief, append one line to `<star.home>/progress/<item>.log` in `juel:ship-ticket`'s format (`printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "<step>" "<one line>" >> <that file>`), so STAR's progress check sees a worker that waits for a reviewer as alive. `<step>` is exactly one token, which STAR's `step-check.sh` reads: `phase<N>` at the start of phase N; `ready` after Phase 1 marks the PR ready (or a deferred `gh pr ready` runs); on each Phase 2 wake `wait-hosted` while a hosted reviewer is set and its review of the PR's current head is not in yet, else `phase2`; `wait-ci` on each poll of the before-`READY` wait for CI; `executor` right before each executor dispatch for a gate fix plan; `regression-gate` right before the gates run through the gate lock; `gate-r<k>` right before gate round `k`; `post-pass` right before `post-pass`; `sync` right before merging the base branch in (Phase 4, or a dirty PR in Phase 2); `report` right before the Phase 5 report line |
| a push in Phase 3 or Phase 4 | under a `star:` brief, every push is gated first. A push that only merges the base branch in (Phase 4 step 1, or a `conflict` wake) is gated by a carry when a script proves the merge brings no change to a file this branch changes: `G` is the `head=` on the first line of the newest `<star.reviews>/<item>-r<g>.md` when that line says `SAFE` (`<g>` is the round of G's review); run `sh <carry-check.sh> --from <G> --head <the merge head> --base <remote>/<base>` (`../star/carry-check.sh` from this file). `OK carried from <G>: <reason>` → no codex round: run the tests Phase 4 step 3 asks of a push that only merges the base branch in, through the gate lock (the `gates run directly` row), push, then `sh <codex-gate.sh> post-pass --pr <url> --round <g> --head <the pushed head> --review <that review's path> --carried-from <G> --reason "<the text after the colon>"` (deferred in quiet hours like any `post-pass`). `NO …`, no SAFE round yet, or `post-pass` printing `ERROR not carried: …` → the codex round below, as for any other push. Round `k` is 1 plus the highest `k` among `<star.reviews>/<item>-r<k>.md`: error logs, raw files and run files never count. Run `sh <codex-gate.sh> --brief <brief> --item <item> --round <k> --base <remote>/<base>` (`../star/codex-gate.sh` from this file), adding `--evidence <its "evidenceDir">` when the `--gates-file` manifest has that key, in the background like `codex exec`. The review streams on its stderr; when it ends, read only the last line of its output, the verdict line, never the transcript. `NOT-SAFE` → its findings are in `<star.reviews>/<item>-r<k>.md`, not in PR comments (all that `receive-review-and-execute` reads), so that skill cannot fix them. The `gate.maxRounds`-th NOT-SAFE round (3 by default) ends with `RESCOPE item=<item> reason=gate review=<the review path the gate printed>` and no fix. NOT-SAFE rounds are counted since the newest SAFE round or the last push, whichever is later. A SAFE round that could not be pushed, because the PR needed a base merge first, starts a fresh count. Any earlier NOT-SAFE round: validate each `[P0]` and `[P1]` finding with `superpowers:receiving-code-review` against the brief; one outside the brief's scope is `ESCALATION item=<item> phase=8 reason=brief-violation needs=<each finding>`. The round's `-fix.md` is `<star.reviews>/<item>-r<k>-fix.md`: one line per finding, `Fixed in <sha>.` or `Disposition: <the technical reason>`. No finding accepted: skip the plan, the executor, the tests and the commit, write the `-fix.md` and gate again on the same head (the gate's prompt carries the dispositions). Otherwise write a fix plan (`superpowers:writing-plans`, a new `-vN`) whose header carries `**Base:** spec implemented at <the full head>; apply only the tasks below.` and whose tasks each name their files in a `**Files:**` block, and run it with the executor the way `juel:ship-ticket` Phase 4 does (`../ship-ticket/SKILL.md` from this file): `--executor session` means this session, with `superpowers:executing-plans`, told "The plan's Base line overrides its Spec: apply the tasks, and do not re-check the spec for completeness."; otherwise `codex exec` on the model `executor-model.sh` resolves from `--executor-model` and `--executor-effort` (`../ship-ticket/executor-model.sh` from this file), with the capacity rule of `juel:ship-ticket` Phase 4 (each try resumes from the plan's ledger), and any other non-zero exit is `ESCALATION item=<item> phase=8 reason=codex-failed needs=<its last lines>`. When you invoke `superpowers:receiving-code-review`, `superpowers:writing-plans` or `superpowers:executing-plans` here, tell it "unattended: the brief is approved, take your default path, ask nothing". Right before the executor runs, from the repo root, note the head (`git rev-parse HEAD`) and record the files already changed: `sh <scope-check.sh> --record "$(git rev-parse --git-path juel_scope_before)"` (`../ship-ticket/scope-check.sh` from this file; write the path in literally, since shell variables do not survive between Bash calls). After the plan ran, run `juel:ship-ticket` Phase 4's scope check, `sh <scope-check.sh> <the plan> <the head before the executor> --before <that record file>`, and restore each `outside` file the way it says: a file in the record is never `outside`, so work that was already there before the executor ran is never restored or deleted. `unchecked …` means nothing was checked: say so in the round's evidence line and go on. Then run the tests for the files the plan changed and the sweep through the gate lock (the `gates run directly` row; `juel:ship-ticket`'s "Gate once per PR"), commit, write the `-fix.md` and gate again; the push waits for a SAFE round and is never forced. `[P2]` and `[P3]` findings never block: fix them when cheap, otherwise leave them in the review. `SAFE` → push, then `sh <codex-gate.sh> post-pass --pr <url> --round <k> --head <pushed head> --review <the review path the gate printed>`: a comment on a ready PR, so a re-gate inside quiet hours defers `post-pass` with the other deferred commands. `post-pass` printing `ERROR`: wait a minute and run it once more; a second `ERROR` → `ESCALATION item=<item> phase=8 reason=review-unavailable needs=<its ERROR line>`. The gate printing `ERROR base-moved …`: the base changed a file this branch changes. Merge it in as Phase 4 step 1 does (a conflict `merge-union.sh` cannot resolve is the `merge-conflict` row above), run the sweep as Phase 4 step 3 asks of a push that only merges the base branch in, and run the same round again: it is not an `ERROR` retry, never counts toward the second `ERROR`, and casts no vote toward `gate.maxRounds`. The gate printing any other `ERROR`: wait 10 minutes and run the same round once more (an `ERROR` leaves no `<item>-r<k>.md`, so the round number does not move); a second `ERROR` → the same escalation, its `ERROR` line quoted whole: an `ERROR gate-down …` line tells STAR the gate itself is down, and STAR parks the item |
| a hosted reviewer (`hostedReviewer` set) | mark ready first, then the review: Greptile skips draft PRs by default and starts its review when the PR is marked ready, so a decision that asks for its review before ready is answered by this order (#40). Pass `--hosted <login>` to `pr-state.sh` (in place of `--review-bots <login>`): it keeps the login as a review bot, reports the hosted reviewer's status on the head as `hosted`, and turns an edit of its summary comment into a `hosted-pass` item. Pass 1 is the review it started when the PR was marked ready, by the build or by this skill. Keep a pass record in `<star.reviews>/<item>-hosted.log`, one line each: `<iso> pass <n> head=<full sha>` when you judge its review of a head that has no `pass` line yet, `<iso> refresh head=<full sha>` when you comment for a status refresh. The passes used are the `pass` lines in that file, so a restarted run counts them from the file, never from memory. A missing file is rebuilt from the PR in Phase 1 step 9 (`--hosted-passes`), and is never read as zero passes. Judge each review the way a person would, from these guidelines, never from its exact markup, which Greptile changes: it is clean when it reviewed the PR's current head (its summary names the commit it last reviewed; when it does not, a review posted after that commit was pushed counts), its confidence is `minScore` (4) out of 5 or better (no score at all: judge from its findings alone), none of its P0 or P1 comments is still open, and nothing in it advises against merging. Clean → Phase 4. Not clean → one batched fix of every P0/P1 comment it left (and any other comment worth fixing), through `receive-review-and-execute`, gated as in the row above, in one push. When that push is for the last pass (the record holds `maxPasses` minus 1 `pass` lines), fetch the base again right before it, and when the base moved, merge it in first (Phase 4 step 1, carried as in the row above when it brings no change to a file this branch changes, as `carry-check.sh` decides), so the last pass reviews a head that is current with the base. No review of the head yet → wait. When you cannot tell, it is not clean: say why in a `NOTE`. Pass 2 is its review of that push: when none starts within 10 minutes (it reviews new pushes only when the repo turns on `triggerOnUpdates`), comment `@greptileai` (deferred in quiet hours). Still not clean after `maxPasses` (2): write its open findings to `<star.reviews>/<item>-hosted-p<n>.md` and end with `RESCOPE item=<item> reason=hosted-review review=<that file>`. Never ask it for a third pass. Report `READY` only on a head whose review you judged clean: STAR's merge gate trusts that and reads none of the review. A push that only merges the base branch in keeps the hosted review's clean judgement (the codex gate re-gates that push, or carries its SAFE across a merge that brings no change to a file this branch changes, as `carry-check.sh` decides), so `READY` may follow it. When the hosted reviewer posts a status on every head and the pushed head has none from it (the snapshot's `hosted` is `none`; it does not run by itself on a later push), comment `@greptileai` once on that head (deferred in quiet hours): a **status refresh**, which never counts toward `maxPasses` and is not the third pass. With `hostedReviewer.refreshOutsideCap` false in `star.json` (the project counts every run the reviewer starts against its cap), a head that needs the reviewer's status after the last pass gets no comment: end with `ESCALATION item=<item> phase=8 reason=hosted-cap cursor=<last cursor> needs=a reviewer run on <head>, which the project counts as pass <n+1>`, `<n>` being the passes used. Wait for its review of that head before `READY`: clean → `READY`; not clean → as a last pass that is not clean, its open findings written to `<star.reviews>/<item>-hosted-p<n>.md` and `RESCOPE item=<item> reason=hosted-review review=<that file>` |
| a review thread someone else opened | reply on every one before `READY`: `Fixed in <sha>.` or `Disposition: <the reason>, <a link when one helps>`. STAR's merge gate fails while one has no reply from you. Never resolve the thread yourself |
| after every background step (an executor run, a gate round, the regression gate, a CI poll, a Phase 2 wake) | before choosing the next step, check for news: re-read the brief's `## Decisions` (STAR appends every answer there before it sends it), then run `orca orchestration check --unread --json`. Read messages only with `--unread --json` (or `--peek --json` to look without consuming them). A plain `orca orchestration check` prints only the subjects and still marks them read; if that happened, run `orca orchestration check --all --json` and read the bodies. A decision that is new since the last check overrides this skill's next step: apply it, and never escalate what it settles. A coordinator decision cannot interrupt a background step, so this check is how it arrives within one step |
| the owner is away | not a reason to wait: only `--quiet-hours` holds marking ready, replies, review requests and the `@greptileai` comment |

**Nothing deferred is lost.** Before printing `READY`, run every deferred command; if the quiet
window is still on, keep waiting in Phase 2 (feedback that arrives meanwhile is handled as usual)
until it ends, then run them. While anything is deferred, every Phase 2 wait carries
`--hold-approval`: without it an approved PR (or an approved draft whose `gh pr ready` is the
deferred command) wakes the wait at once, every time, for the whole quiet window. Before printing an `ESCALATION`, write the deferred commands
that have not run to a file beside the draft or gate log (never a deferred `gh pr ready`: the
next run proves and marks ready itself) and print one `HELD` line for all deferred
commands: `HELD item=<item> action=run <n> deferred replies and review requests, listed in <path>`,
so the coordinator records one open loop, not one per command.

**Quiet hours.** With `--quiet-hours`, check the window at the moment of each reviewer-facing
action, not once at the start, and never by hand: `sh <quiet-hours.sh> "<the --quiet-hours value>"`
(`../ship-ticket/quiet-hours.sh` from this file, or
`${CLAUDE_PLUGIN_ROOT}/skills/ship-ticket/quiet-hours.sh`) prints `inside` or `outside`; `always`
is inside at every moment. A result that is anything but `inside` or `outside` (exit 64, a missing
script on an older install, no `python3`, an empty line) is never read as outside: defer the action
as if inside. Run it once in Phase 1 too: any such result there means the window cannot be judged, and
an unattended run stops with `ESCALATION item=<item> phase=8 reason=preflight needs=a valid
--quiet-hours window`. An action already being posted when the window opens is finished; the next
one is deferred. Inside it, `gh pr ready`, Phase 3's
replies (step 5) and review requests (step 6) are **deferred**: keep each composed body in its temp
file and the pending commands in order, keep waiting in Phase 2, and run every deferred command, in
order, at the first wake after the window ends. Fixes, gates and pushes never wait. A deferred
`gh pr ready` means no reviewer sees the PR yet, so Phase 2 simply times out until the window ends.

## Reviewer mode

Phase 1 step 2 chose it: someone else authored the PR, and you reviewed it with
`juel:review-pr`. Reviewer mode keeps the PR moving from the reviewer's side. It waits until the
author is ready for you again, re-reviews through `juel:review-pr` in place of
`juel:receive-review-and-execute`, and asks you before every post.
It never commits, pushes, merges, runs gates or edits the author's branch.
Neither "Unattended mode" nor `--quiet-hours` applies to it: nothing goes out without your answer.

`<you>` is `gh api user --jq .login`. Before the first wait, it stops with the reason when any of
these fails:

- `--unattended` is set: STAR never runs reviewer mode, because every round needs your answer.
  Under `--unattended` the stop prints `ESCALATION item=<item> phase=8 reason=preflight needs=the PR's author is <login>: reviewer mode runs only interactively`,
  `<login>` being the PR's author, so STAR's stage ends with a state line.
- You have no submitted review on the PR. This prints one line per review of yours, oldest first,
  so the last line is your newest:
  `gh api repos/<owner>/<repo>/pulls/<pr>/reviews --paginate --jq '.[] | select(.user.login == "<you>" and .state != "PENDING") | [.commit_id, .submitted_at] | @tsv'`.
  No line: stop with "Review it first with /juel:review-pr".
- The working tree is dirty: `git status --porcelain` prints anything. Name the files and stop;
  never discard them.
- Nobody can answer a question in this session: stop with "reviewer mode needs you at the
  keyboard".

Each row overrides the phase it names:

| Phase | Reviewer mode |
|---|---|
| 1. Resolve PR and gates | Steps 1, 3 and 5 as written. Steps 4 (gates), 7 (`--mark-ready`), 8 (review bots), 9 (the hosted log) and 10 (the hosted refresh) do not apply. The **reviewed head** is the `commit_id` of your newest review (the last line above), the **cursor** is its `submitted_at`, and quiet-since is the same time. When `gh pr view --json number --jq .number` on the current branch does not print `<pr>`, run `gh pr checkout <pr>`. |
| 2. Wait for feedback | `sh <script> <pr> --wait --as-reviewer <you> --reviewed-head <reviewed head> --settle-minutes 30 --since <cursor> --interval 600 --silence-hours 72 --quiet-since <quiet-since>`, in the background as in Phase 2 (Codex: the foreground form with `--max-seconds 540`, run again on `wake: timeout`). Every wait after the first passes `--head-seen <the last snapshot's head_seen>`, in both forms: a wait again after `errors`, `silence` or `timeout`, and the wait after a round, so the 30 minute settle clock never restarts. A snapshot that has no `head_seen` (an `errors` wake with no good snapshot) leaves it out, and the script ignores a sighting of another head. On `wake`: `rerequested` (the author asked for your review again) or `settled` (a new head has stayed put for 30 minutes) → Phase 3. `closed` → Phase 5. `silence` → say once "no re-request or settled push for 72 h, still waiting", then wait again with `--silence-hours 0`. `errors` and `timeout` as in Phase 2. No other wake comes in this mode. The snapshot's `reviewers` is empty here, and reviewer mode never takes the `cursor` the snapshot prints: in this mode it still moves with the author's items, so only Phase 3 step (4) sets the cursor. |
| 3. Remediate and push | **Re-review.** (1) `git status --porcelain` prints nothing; otherwise stop and name the dirty files: never discard them. (2) `gh pr checkout <pr> --force`, which moves the local branch to the PR's head, a force-push included. (3) `/juel:review-pr --pr <pr> --since <reviewed head> --from-babysit`: it reviews, asks you, then posts, replies and resolves your fixed threads, all behind its Step 7 question. (4) Read its last line, then set the cursor to now (an ISO time with `Z`) and quiet-since with it, whatever the line says and never from the snapshot, so a re-request already handled never wakes the wait again. `REVIEW-PR posted verdict=APPROVE …` → Phase 5. `REVIEW-PR posted verdict=REQUEST_CHANGES …` or `REVIEW-PR posted verdict=COMMENT …` → the reviewed head becomes its `commit=`, back to Phase 2. `REVIEW-PR not-posted head=<sha>` → the reviewed head becomes that `<sha>`, so the same head never wakes again, back to Phase 2. `REVIEW-PR head-moved from=<sha> to=<sha>` → the reviewed head stays, back to Phase 2: the new head wakes `settled` once it has stayed put for 30 minutes. `REVIEW-PR stopped reason=<why>` → Phase 5 with that reason. |
| 4. Final sync and push | SKIPPED: "reviewer mode: nothing to push". |
| 5. Report | The PR URL; each round with its verdict (or "not posted"), the threads it resolved and the comments it added; and the outcome: **"Approved by you"**, **"Merged or closed by someone else"**, or why it stopped. |

## Phase 1: Resolve PR and gates

1. PR: the argument, else `gh pr view --json number --jq .number` on the current branch.
2. `gh pr view <pr> --json author,baseRefName,headRefName,url,createdAt`. When `author` is the
   current `gh api user --jq .login`, this is **author mode**: every phase below, as written.
   Any other author is **reviewer mode**: read "Reviewer mode" above now, and let its table override
   each phase. It stops before any wait when one of its checks there fails.
3. Remote: the current branch's upstream remote (`git rev-parse --abbrev-ref @{upstream}`, the
   part before `/`). No upstream: the remote whose URL matches the PR's repo.
4. Gates: the `--gates` list when given. Otherwise resolve `test`, `lint`, `typecheck` and
   `build` once, using the "Toolchain commands" section of `juel:ship-ticket`
   (`../ship-ticket/SKILL.md`, relative to this file), and reuse that set for every round. A
   key that resolves to nothing is skipped with a one-line note.
   Then, before any gate runs, check for missing dependencies as `juel:ship-ticket` Phase 4 does:
   a `package.json` at the repo root, or in a gate's `cwd`, that declares dependencies (a non-empty
   `dependencies`, `devDependencies`, `optionalDependencies` or `peerDependencies`, or a `workspaces` key)
   with no `node_modules` folder, `.pnp.cjs` or `.pnp.js` file there or in any folder above it up to the repo root.
   When one is missing, run the install command once (`install`, resolved by the same section), in
   the background and not under the gate lock. An install that fails, or no install command
   resolved, stops the run with one line saying why. Under `--unattended` it ends with
   `ESCALATION item=<item> phase=8 reason=gate-unavailable needs=dependencies did not install: <one line>`.
5. Script: `${CLAUDE_PLUGIN_ROOT}/skills/babysit-pr/pr-state.sh` when `CLAUDE_PLUGIN_ROOT` is
   set, otherwise `pr-state.sh` next to this SKILL.md.
6. Cursor: `--since` when given, else the PR's `createdAt`, so feedback that arrived before this
   skill started is handled in round 1. After that the cursor is whatever `pr-state.sh` last
   printed as `cursor`, an opaque string passed back unchanged. Quiet-since: now, as an ISO time
   with `Z` (`2026-10-01T09:00:00Z`).
7. With `--mark-ready` and a draft PR (`gh pr view <pr> --json isDraft,headRefOid`): under
   `--unattended`, check the `--reviewed` proof first ("Unattended mode"); then `gh pr ready <pr>`, once,
   or defer it per "Unattended mode" when inside `--quiet-hours`. A PR that is already ready is left
   alone. Never mark it ready a second time.
8. Review bots: `config.reviewBots` from `.claude/workflow.local.json`, else `.claude/workflow.json`
   (a list of bot logins such as `greptile-apps[bot]`; none when absent). Pass them to every
   `pr-state.sh` call as `--review-bots <logins joined by ,>`. `pr-state.sh` already keeps the app
   behind each status check the base branch requires (a code-review app whose status is
   required), so most repos need no list.
9. Under a `star:` brief with a hosted reviewer: when `<star.reviews>/<item>-hosted.log` does not
   exist (a run before 2.2.0 kept no record), rebuild it from the PR before anything counts its
   passes: `sh <script> <pr> --hosted <login> --hosted-passes > <log>.tmp`, `<login>` being
   `hostedReviewer.login` and `<log>` that file. Exit 0: `mv <log>.tmp <log>`. Its lines are the
   record's `pass` lines, one per head the reviewer reviewed; an empty file means no pass yet.
   An `error` line writes no file: `rm -f <log>.tmp`, wait 60 seconds and run it once more.
   A second `error` → `ESCALATION item=<item> phase=8 reason=pr-state-errors needs=<its error line>`,
   the escalation for a GitHub that cannot be read. A missing log is never read as zero passes.
10. Under a `star:` brief with a hosted reviewer: when the PR's head has no status from the hosted
   reviewer while it already reviewed an earlier head (its summary comment is on the PR), run the
   status refresh (the hosted-reviewer row in "Unattended mode") before the first wait, or, with
   `refreshOutsideCap` false and every pass used, that row's `hosted-cap` escalation. STAR sends
   a PR back to this stage for exactly this case, after a base sync left the new head without the
   hosted reviewer's required status.

## Phase 2: Wait for feedback

Run `sh <script> <pr> --wait --since <cursor> --interval 600 --silence-hours 24 --quiet-since <quiet-since> [--review-bots <logins>] [--hosted <login>]`.

- **Claude Code:** one Bash call with `run_in_background: true`. Do not poll it, tail it or
  attach a `Monitor`; the completion notification wakes you. Never `sleep` in the foreground.
- **Codex:** run it in the foreground with `--max-seconds 540` added, and run it again on
  `wake: timeout` with the same arguments.

Act on the printed object's `wake`:

| `wake` | Action |
|---|---|
| `feedback` | Phase 3 with this object's `new_feedback`, `reviewers` and `cursor`. An item with `kind: hosted-pass` is the hosted reviewer's re-review of `head`, made by editing its summary comment: judge that review first, by the hosted-reviewer row of "Unattended mode" (clean → Phase 4; not clean → its batched fix), and leave the item itself out of Phase 3's replies |
| `conflict` | The PR conflicts with its base (`merge` is `dirty`): CI and the hosted review do not start on a conflicting head, so waiting is pointless. Run Phase 4 steps 1 to 4 now (merge the base in with `merge-union.sh`, the tests step 3 asks of a push that only merges the base, and under a `star:` brief the push's gate, a carry of the last SAFE when the merge brings no change to a file this branch changes, as `carry-check.sh` decides), add one to this run's base syncs, then wait again on the new head with the same cursor. When step 1 finds nothing to merge (the base is already in, so GitHub's `dirty` is stale), count no sync: wait 60 seconds and run the script again instead of re-entering `--wait`, which would wake `conflict` at once. A conflict `merge-union.sh` cannot resolve ends as in Phase 4 step 1 |
| `approved` | Phase 4 |
| `draft` | The PR is approved but is a draft (someone converted it back, or this run's own `gh pr ready` is still deferred). In the second case wait again, with `--hold-approval`. Otherwise tell the user and stop; under `--unattended`: `ESCALATION item=<item> phase=8 reason=pr-draft-again needs=someone turned the PR back into a draft` |
| `closed` | Phase 5: report "PR was closed or merged by someone else" and stop |
| `errors` | Tell the user the `error` in one line, then wait again (same arguments) |
| `silence` | Tell the user once "no feedback for 24 h, still waiting", then wait again with `--silence-hours 0` |
| `timeout` | Codex only: wait again |

The same holds for a snapshot whose `merge` is `dirty` on any other wake (a `timeout` under
`--unattended`, say): handle it as a `conflict` wake first. `behind` is not acted on here: CI still
runs on a head that is behind, and syncing after every merge into the base would cost a regression gate
each time. Phase 4 merges the base in before `READY`, and STAR's merge gate sends the PR back when
the repository requires an up-to-date branch.
A gate round that prints `ERROR base-moved` is the one case where a `behind` PR is merged outside Phase 4.

## Phase 3: Remediate and push

In reviewer mode, this phase is the re-review in "Reviewer mode"; the steps below are author mode's.

1. Invoke `/juel:receive-review-and-execute <pr>` (under `--unattended`: `/juel:receive-review-and-execute <pr> --unattended --only <ids> [--brief <path>] [--executor session]`, see "Unattended mode"; `--executor` is passed on exactly as this skill received it). It merges the base branch in only when the PR conflicts with it (a `behind` PR is synced in Phase 4), reads every
   thread, validates findings into actionable / rejected / ambiguous, asks the user about
   ambiguous ones, writes a plan and runs the executor. Keep its final per-finding outcome: it
   is the source for every reply below.
2. If it ended with zero actionable findings, skip to step 5.
3. Gate the round as `juel:ship-ticket`'s "Gate once per PR" says (`../ship-ticket/SKILL.md` from
   this file) for a push that carries your own changes: the tests for the files changed since the
   last push, then the sweep, `sh <run-gates.sh> <the --gates-file manifest> --root <repo root> sweep`
   (`../ship-ticket/run-gates.sh` from this file; with no manifest, the `test` command). Red: invoke
   `/juel:receive-review-and-execute <pr>` again with the failing command and its output as
   context. Two red gates in a row: stop and ask the user. Never hand-edit.
4. `git push <remote> HEAD`. A rejected push means the remote moved: fetch, merge
   `<remote>/<head-branch>`, re-run the gates, push again. Never force-push.
5. Reply to every item in this round's `new_feedback`. A `hosted-pass` item gets no reply: it is
   the hosted reviewer's own summary, judged in Phase 2, not a thread. The others:
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

1. `<base>` is the snapshot's `base` from the last `pr-state.sh` output, not the one resolved in
   Phase 1: someone may have retargeted the PR. `git fetch <remote> <base>` then `git merge --no-edit <remote>/<base>`.
   Note `git rev-parse HEAD` before the merge. Conflicts: first run `sh <merge-union.sh>`
   (next to this file; `${CLAUDE_PLUGIN_ROOT}/skills/babysit-pr/merge-union.sh` when that is set).
   It resolves only mechanical conflicts, where in every conflicted file both sides inserted text
   at the same point and changed nothing else (two rows appended to one table, two entries added
   to one list), and never touches a lockfile or a binary file.
   - Exit 0 (`resolved <path>` lines): commit the merge with
     `git commit -m "Merge <remote>/<base> into <branch>; mechanical conflicts resolved in <files>"`,
     then step 3's gates run as usual. A red gate there keeps the merge commit and is step 3's red,
     as for any other push (under `--unattended`, the red-gate row): the sweep may have caught a
     break in a file that did not conflict, which a fix of your own repairs. A green gate pushes,
     and the Phase 5 report names the resolved files.
   - Any other exit (`conflict <path> <why>` lines): list the conflicted files, stop and ask the
     user to resolve or abort (`git merge --abort`). Under `--unattended`: `git merge --abort`, then
     the `merge-conflict` escalation; nothing is asked.
   Never resolve a conflict that is not mechanical, and always name the files that were.
2. Already up to date and nothing unpushed (`git status -sb` shows no `ahead`): go to step 5.
3. Gate the push as `juel:ship-ticket`'s "Gate once per PR" says. A push that only merges the base
   branch in runs the sweep, `sh <run-gates.sh> <the --gates-file manifest> --root <repo root> sweep`
   (through the gate lock under `--unattended`, the `gates run directly` row; with no manifest, the
   `test` command), after a clean merge too: the base can change a call that an untouched file on
   this branch relies on, and no conflict shows it. A push that also carries unpushed commits of
   your own runs Phase 3 step 3's tests and sweep. Red: stop and report the failing command and
   output. Push nothing. (Under `--unattended`: the red-gate row of "Unattended mode".)
4. `git push <remote> HEAD`. Never force-push. Under a `star:` brief the push is gated first (the
   "a push in Phase 3 or Phase 4" row of "Unattended mode"), and a merge that brings no change to a
   file this branch changes, as `carry-check.sh` decides, carries the last SAFE with no codex round.
5. Run `sh <script> <pr> --since <cursor>` once more. If new feedback arrived while this phase
   was running, go to Phase 3 with it. Otherwise Phase 5.

## Phase 5: Report

In reviewer mode, report what the "Reviewer mode" table's Phase 5 row lists instead.

- PR URL and final state
- rounds handled, with items fixed / declined / decided per round
- final gate result and the pushed head
- the outcome: **"Ready for you to merge"**, or why it stopped (closed, merged, red gate,
  merge conflict, user stop)

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Replying to a reply id | Reply to the thread root: `in_reply_to` when set |
| Treating the Linear link-back bot as feedback | `pr-state.sh` drops every bot except the app behind a required check and the logins in `config.reviewBots`; never add your own filter on top |
| Pushing after a red gate "because the fix is obvious" | Back through `receive-review-and-execute`, or stop and ask |
| Ending on approval without re-checking | Phase 4 step 5: new feedback arrived while you were gating goes back to Phase 3 |
| Resolving threads after replying | Leave them; the reviewer resolves |
| Polling in the foreground in Claude Code | One background `--wait` call; the notification wakes you |
| Committing, pushing or running gates in reviewer mode | Reviewer mode only re-reviews: the author's branch is theirs |
| Re-reviewing on every push of the author's | Wait for a re-request, or for a head that has stayed put for 30 minutes (`--settle-minutes 30`) |
| Leaving the cursor where it was after a reviewer-mode round | Set it to now after every round, or a re-request already handled wakes the wait again |
