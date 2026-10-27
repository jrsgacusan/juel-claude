---
name: babysit-pr
description: Use after a PR is open to wait for reviews and react until it is ready to merge - polls the PR every 10 minutes, runs juel:receive-review-and-execute on any new human feedback (review, inline or conversation comment), runs the gates, pushes, replies on every item and re-requests review; on a clean approval merges the base branch in when the base requires it or the PR conflicts, runs the gates and pushes. Never merges the PR, except with --yuki: as a juel:yuki worker it merges once CI is green on the head, every requested reviewer approved and a bot reviewer's one review is answered. On a PR someone else authored it runs reviewer mode instead: waits for the author's re-request or a settled push, re-reviews through juel:review-pr and asks before every post. Invoked by juel:ship-ticket Phase 8; with --unattended it runs as a juel:star Orca worker: marks a draft ready once, gets the hosted reviewer's passes or a person's approval, re-gates every push with a headless codex review, escalates instead of asking. Triggers "babysit this PR", "watch my PR for reviews", "/juel:babysit-pr".
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

- **Never merge the PR**, except in "Yuki mode", and there only through its merge check.
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

## Superpowers skill names

Call each `superpowers:` skill by that name; when the Skill tool answers "Unknown skill", call the same name without the `superpowers:` prefix, and use whichever answered for the rest of the run.

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
| `--mark-ready` | off | Mark a draft PR ready for review once, in Phase 1. Under `--unattended` it needs `--reviewed`. A PR the build already marked ready is left as it is: under STAR the flag only acts on a PR the build left a draft |
| `--reviewed <path>` | — | The proof that this head passed the gate before it is shown to people: the item's newest review from `juel:star`'s `codex-gate.sh`, whose first line is `VERDICT … SAFE … head=<sha>`, or that round's `<item>-r<k>-carried.md` when the owner shipped with the round's findings deferred (`review-proof.sh` prints `OK carried round=<k>` for it) |
| `--brief <path>` | — | The item's approved brief. Passed on to `receive-review-and-execute`, which refuses reviewer requests outside its scope |
| `--executor <session|codex>` | `codex` | Who runs a remediation plan: passed on to `receive-review-and-execute` unchanged. `session` means this session runs it; `codex` dispatches `codex exec` |
| `--executor-model <id|latest-<family>>` | `star.json`'s `executor.model` under a `star:` brief, else `latest-luna` | Passed on to `receive-review-and-execute` |
| `--executor-effort <level>` | `star.json`'s `executor.effort` under a `star:` brief, else `xhigh` | Passed on to `receive-review-and-execute` |
| `--yuki <home>` | off | Run as a `juel:yuki` worker: nothing is asked, and the PR is merged once the merge check holds. See "Yuki mode". Requires `--item`. Refused in reviewer mode, and with `--unattended` |
| `--yuna <home>` | off | Run as a `juel:yuna` worker: reviewer mode with nobody to ask, every re-review posts by itself, and the run ends in `APPROVED`, `RELEASED` or `PARKED`. See "Yuna mode" inside "Reviewer mode". Requires `--item`. Refused in author mode, with `--unattended`, and with `--yuki` |
| `--since <iso>` | the PR's `createdAt` | Feedback cursor: only feedback after it is handled. A resumed run passes the `cursor` from its last `READY`, so earlier comments are never re-answered |

Usage: `/juel:babysit-pr`, `/juel:babysit-pr 412`, `/juel:babysit-pr 412 --gates "make test;make lint"`,
or as a `juel:star` worker `/juel:babysit-pr 412 --unattended --mark-ready --item SAVI-1162 --gates "make test"`

## Unattended mode

`--unattended` is how a `juel:star` Orca worker runs this skill after the build's codex gate said SAFE and STAR checked its report.
With `--brief`, first read the files under the brief's `star.notes`, then its `## Decisions`
section if it has one: the human's dated answers to earlier escalations on this item. A decision
settles the reviewer comment it answers: apply it, and never escalate that comment again. Nobody
is there to answer, so every place below that tells the user something or asks them changes.
Each row overrides the phase step it names: under `--unattended`, read this
table before doing a step, even where the step's own text does not point back here.

| Normally | With `--unattended` |
|---|---|
| Phase 2 waits in the background (Claude Code) | Always the foreground form with `--max-seconds 540`, repeated on `wake: timeout`: a background wait may never wake a headless session. |
| `approved` wake needs `reviewDecision: APPROVED` | also on each `timeout` wake when `decision` is null or an empty string (`gh pr view` reports `""` when the base branch requires no review): `gh pr view <pr> --json reviews,headRefOid` → an `APPROVED` review whose `commit.oid` is the PR's `headRefOid`, and no reviewer whose latest review (of `APPROVED`, `CHANGES_REQUESTED`, `DISMISSED`) is `CHANGES_REQUESTED`, counts as approved → Phase 4 (the same rule `juel:star`'s final check uses, so `READY` is never followed by "changes requested by …"). A PR whose snapshot says `draft: true` is never approved for this purpose: see the `draft` wake. Dates are never compared: a commit made earlier and pushed later is older than the approval and was still never reviewed. Where the base branch's rules explicitly require 0 approving reviews, `pr-state.sh` itself wakes `approved` once no reviewer's latest review is `CHANGES_REQUESTED` and every check on the head has finished green, the required ones included (its snapshot says `approval: required` and `required: 0`): no approval is waited for, and none is looked for on these timeout wakes. A repo with no review rule (`approval: none`), or one the script could not read (`unknown`), keeps the rule above. With a hosted reviewer (the rows below), its clean pass on the head stands in for this approval. Babysit requests no reviewer and waits for no human approval: a PR whose base branch requires one is reported `READY` once the other bars hold, and STAR's merge gate raises the approval item (`PENDING approval`), never this skill. |
| no limit on waiting | 72 h with no new feedback since the PR was marked ready → `ESCALATION item=<item> phase=8 reason=out-of-tries step=hosted-wait`, after flushing (below) |
| `errors`: tell the user, wait again | wait again; three `errors` in a row → `ESCALATION item=<item> phase=8 reason=out-of-tries step=gh review=<a file holding the error>` |
| an `errors` or `timeout` wake whose `error` starts with `gh cannot see` | first look for the project's token rule: the files under the brief's `star.notes` (the project's memory notes) may name a `GH_TOKEN` rule, a command that prints the token (a keychain lookup, say). When one does, run the same wait once more with it in front, `GH_TOKEN="$(<that command>)" sh <script> …`, and put the same prefix on every later command that reaches GitHub, because an `export` does not outlive one shell call. No such rule, or `gh cannot see` again with it: at once, without waiting for three: `ESCALATION item=<item> phase=8 reason=needs-person needs=access: <the error>`; waiting again cannot fix a token. With `star.json`'s `tokenCmd` set, the plugin's session hook already gives every session the token |
| `silence`: tell the user once | say nothing; wait again with `--silence-hours 0` |
| `receive-review-and-execute` asks about ambiguous findings or merge conflicts | invoke it with `--unattended --only <ids>`, the ids of this round's `new_feedback` (older threads are context only, so feedback already answered is never re-planned or re-escalated), plus `--brief <path>` when given; its `BRIEF-VIOLATION:` lines → `RESCOPE item=<item> reason=brief review=<a file naming what each request needs and why the brief excludes it>`; its `AMBIGUOUS:` lines → decide the finding from the brief, the code and sources, record a `## Decisions` line, and go on: run it again so the decision plans or declines the finding. Nothing is drafted for the owner; its `CONFLICT:` line → the conflict rule in Phase 4 step 1 |
| `tries.perStep` red gates in a row: stop and ask | write the failing output to `<star.home>/reviews/<star.project>/<item>-gate.log` (or a temp file without a `star:` brief), then `ESCALATION item=<item> phase=8 reason=out-of-tries step=regression review=<that path>`. A red is refunded, and does not count toward the budget, when the fix for it changed only files outside runtime (`juel:ship-ticket` Phase 6 step 6's definition: test files, docs the app does not load, paths a memory note or the brief names), read from `git diff --name-only <the commit before the fix>..HEAD`. At most two such reds are refunded between two green gates; a third counts. The fix still comes from `receive-review-and-execute` or a fix plan, never by hand |
| every `ESCALATION` line in this table | is one of two shapes: `ESCALATION item=<item> phase=8 reason=needs-person needs=<kind>: <what>` or `ESCALATION item=<item> phase=8 reason=out-of-tries step=<step>[ review=<path>]`. The report carries no cursor: STAR resumes a restarted run from the cursor of your last `READY`, and the replies already on the PR show what is answered. `needs=` is always one line; long output goes in a file whose path `review=` names |
| Phase 2 wakes with `closed` and the PR is merged | not an escalation: the report's first line is `MERGED item=<item> pr=<url>`, and the run ends. A PR closed without a merge is `ESCALATION … reason=out-of-tries step=gh` |
| `decision` is `CHANGES_REQUESTED`, this run has had nothing to act on since it started or since its last push, and 24 h have passed (a bot, or a reviewer who left no comment, blocks the PR; a reviewer who was just re-requested gets the same 24 h) | a PR blocked only on a required approval is reported `READY` (STAR's merge gate raises the approval item), so it is never this row; a PR blocked on anything else for 24 h: `ESCALATION item=<item> phase=8 reason=out-of-tries step=gh` |
| stuck on the same thing three times (a gate, a tool, two ways to read a comment) | ask the coordinator before escalating: `orca orchestration ask --question "<one question, with what you tried>" --json`. Its answer binds like a Decision. A check-in message from the coordinator in the terminal gets a one-line answer, then carry on |
| a question sent with `orca orchestration ask` comes back "No answer from the user: escalate this." | decide the question yourself from sources, record it in the brief's `## Decisions` with its `Source:`, and go on |
| a merge conflict: stop and ask | the conflict rule in Phase 4 step 1: resolve, record, gate. A resolution that fails its gates `tries.perStep` times ends as `ESCALATION item=<item> phase=8 reason=out-of-tries step=conflict` |
| `receive-review-and-execute` prints `STOPPED: <reason>` | `ESCALATION item=<item> phase=8 reason=out-of-tries step=executor review=<a file holding the reason>`; never read it as "zero actionable" |
| before `READY`, whether or not Phase 4 pushed | **wait for CI** before reporting (the last Phase 3 push's checks may still be running when Phase 4 has nothing to push): poll `gh pr checks <pr> --json name,bucket` in foreground calls of at most 540 s until no check is `pending`, for at most 3 hours in all. `gh pr checks` exiting 1 with "no checks reported" means none has registered yet: that is pending for the first 5 minutes after the last push. After that it means "this repo has no CI" only when the base branch's head has no check runs either: `gh api repos/<owner>/<repo>/commits/<base>/check-runs --jq .total_count` prints `0`. Otherwise read `gh pr view <pr> --json mergeStateStatus --jq .mergeStateStatus`. On a PR that is not `DIRTY`, with no check required by the base branch: this is not a stop. Go on, since codex SAFE is the bar. On a `DIRTY` PR the `conflict` wake acts first (Phase 2), and the report carries `NOTE: no CI ran on head <sha7> (PR DIRTY)`, `<sha7>` being that head's first 7 characters. Also before `READY`: one last snapshot, and `draft: true` in it is `ESCALATION item=<item> phase=8 reason=out-of-tries step=pr-draft`, never `READY`; still pending then → `ESCALATION item=<item> phase=8 reason=out-of-tries step=ci-wait`. Any `fail` or `cancel` → the red-CI rule (the next row). Under `--unattended`, request no reviewer and wait for no approval, one dismissed by the push included: `READY` follows once the codex gate is SAFE on the head, the required checks are green and (with a hosted reviewer that is set and not paused) its passes are in. A required approval that is missing is raised by STAR's merge gate (`PENDING approval`), not by this skill. |
| a failing check (red CI), before `READY` or after a push | the red-CI rule, for each failing check. (1) Rerun it once. Green means a flake: go on. (2) If it is still red, find out whether the base branch's head fails the same check name, or the run's conclusion is `cancelled`, `startup_failure`, `timed_out` or `stale`. (3) When either holds, write the proof line to the brief's `## Decisions`: `- <date> red-check-proof check=<name> head=<head> cause=base|infra base=<base head> url=<url>` (`<head>` and `<base head>` full 40-character shas; `<base head>` is the PR base branch's current head, `baseRefOid` from `gh pr view <pr> --json baseRefOid`, read when the line is written, so a base that moved needs a fresh line; a `<name>` holding a space or `=` is written in double quotes: `check="test (ubuntu-latest)"`); write the proof line and nothing else: STAR files any follow-up after the merge, once per check name per base branch. (4) Otherwise it is the PR's fault: fix it, up to `tries.perStep` attempts, then `RESCOPE item=<item> reason=ci review=<path>`. A required check never passes on a proof: it is the PR's fault, or the item waits. By hand, a red check is shown to the user. |
| Phase 5 report | its state line is `READY item=<item> pr=<url> head=<pushed sha> cursor=<last cursor>`, with the full 40-character sha as `<pushed sha>` (STAR's merge takes no shorter one) (only on "Ready for you to merge", with checks green; here `<last cursor>` is the newest cursor, everything before it is answered); a hosted review still not clean after its passes, or a gate still NOT SAFE after `tries.perStep` rounds, is `RESCOPE item=<item> reason=<gate|hosted-review|ci|brief> review=<path>` with `--outcome succeeded`, and the `gate` form ends ` tooling=all` (`RESCOPE item=<item> reason=gate review=<path> tooling=all`) when that round's `tooling=` equals `p0 + p1`; any other outcome is an `ESCALATION` with the reason. Print it as the last line in the terminal; the `worker_done` body starts with it. The `worker_done` body is these report lines and nothing else. It overrides any request for a prose summary, Orca's worker preamble included. The `worker_done` body is at most 12 lines: that line is the first line of the `worker_done` body, then `SENT replies=<n> review-requests=<m> base-syncs=<s>` when anything was posted or pushed for a base sync in this run (the coordinator logs it for the user's summary; `base-syncs=` counts Phase 2's syncs of a dirty PR), at most two `HELD` lines (more: write them to a file and report one `HELD item=<item> action=<n> held actions, listed in <path>`), at most one `NOTE: <one line>` of your own (a fact the next worker in this project should know), `NOTE: executor skill missing, the plan ran in this session` when `receive-review-and-execute` or a gate fix plan ran in this session for that reason, `NOTE: no CI ran on head <sha7> (PR DIRTY)` once when the wait for CI met a `DIRTY` PR (the row above), `NOTE: scope outside-merged <path>[, <path> ...]` once, relayed from `receive-review-and-execute` and naming every such path it reported in this run, `NOTE: inherited from <base>: <one line>` once when the cause of an `ESCALATION` is a defect the PR took over from its base branch (STAR waits for the row that fixes it; without the NOTE it guesses nothing), and at most one `STAR-ISSUE: <one line>` (friction with STAR's own contract or tools, no project names). That is 11 lines at most, so the first line, with its head and cursor, is never dropped to fit; `--outcome failed` for an `ESCALATION` |
| gates run directly | run them through `juel:ship-ticket`'s `gate-lock.sh` and `run-gates.sh` (`../ship-ticket/` from this file, or `${CLAUDE_PLUGIN_ROOT}/skills/ship-ticket/`): `sh <gate-lock.sh> --holder "<star.project>/<item>" --progress <star.home>/progress/<item>.log -- sh <run-gates.sh> <the --gates-file manifest> --root <repo root>` (under a `star:` brief the holder is `<star.project>/<item>`, so two projects with an item of the same name never stop each other's gate; without a `star:` brief, leave out `--progress` and use `--holder "<item>"`): while the lock is busy, `gate-lock.sh` appends a `regression-gate` progress line when it starts waiting and another every 10 minutes, so STAR reads a worker queued for the lock as moving. `run-gates.sh` runs each gate in its own `cwd`, taken from the repo root, exactly as the manifest has it; never paste a gate command into a quoted `sh -c '…'` string (one quote in the command silently drops the rest). With `--gates` and no manifest, write the commands to a file, one per line under `set -e`, and run `-- sh <that file>`. Targeted tests go through the lock the same way, as such a file. The sweep is the same `run-gates.sh` line with `sweep` after `--root <repo root>`; with no manifest, it is the `test` command. Run it in the background, like `codex exec` (`run_in_background: true`, wait for the completion notification, never poll it): waiting for the lock plus the gates can outlast the 600 s foreground cap. Exit 75 means busy: run it once more; a second 75 → `ESCALATION item=<item> phase=8 reason=out-of-tries step=gate-lock review=<a file holding its "busy, held by …" line>`. Exit 71 with `dependencies are not installed` in its message: run the install command once (Phase 1 step 4, with its escalation when the install fails), then the same line once more; a second 71 is `reason=out-of-tries step=review-tool`. Exit 71, 124 or 125 (the gate could not run, ran past its time limit, or stalled: it printed nothing for `--idle-max` seconds) → `ESCALATION item=<item> phase=8 reason=out-of-tries step=review-tool review=<the file holding the script's message>`, never a red gate and never run again; for 125 the file holds `stalled gate: <the stalled line>` |
| `--mark-ready` on a draft PR | first the proof, checked by the script and never by eye: `sh <review-proof.sh> <the --reviewed file> --item <item> --head <the PR's current headRefOid>` (`review-proof.sh` is next to this file). It prints `OK round=<k>` only when the file's first line is a full `VERDICT` line for this item that says `SAFE`, its `head=` is at least 7 characters and the start of the PR's head, and it is the newest review file for the item (a later round replaces an earlier verdict). It prints `OK carried round=<k>` for an owner's carried PASS: a `<item>-r<k>-carried.md` file STAR wrote when the owner chose to ship round `k`'s head with its findings deferred, valid while its `head=` starts the PR's head and no newer round exists. Both `OK` forms are proof. A `NO …` is not final yet when the head is a merge of the base branch made after the review (a carry, see the push-gate row), which `review-proof.sh` rejects because the review names the head before the merge: when the newest `<star.reviews>/<item>-r<k>.md` says `SAFE` on its first line, run `git fetch <remote> <base>` and `sh <carry-check.sh> --from <its head=> --head <the PR's current headRefOid> --base <remote>/<base>` (`../star/carry-check.sh` from this file). `OK carried from …` is proof as well, and no codex round is spent on a merge that brings no change to a file this branch changes, as `carry-check.sh` decides. Any other `NO …`, no `--reviewed`, or a script that cannot run → leave the PR a draft, print a progress line saying what the script said, and `ESCALATION item=<item> phase=8 reason=out-of-tries step=gate`. A PR that is already ready needs no proof: it was shown to people before this run |
| an owner's carried PASS (`--reviewed` names a `<item>-r<k>-carried.md` file) | in Phase 1, once the proof says `OK carried round=<k>`, post its receipt: `sh <codex-gate.sh> post-pass --pr <url> --round <k> --head <the PR's full head> --review <that file>` (`../star/codex-gate.sh` from this file). `posted <url>` and `already <url>` both end the step. The receipt names the owner's decision: never write one by hand. `ERROR …` twice, a minute apart → `ESCALATION item=<item> phase=8 reason=out-of-tries step=review-tool review=<the file holding its ERROR line>` |
| Phase 4 step 3, a red gate | once: back through `receive-review-and-execute` with the failing output, as in Phase 3 step 3. `tries.perStep` times in a row, counted as the row above counts them (a red whose fix stayed outside runtime is refunded): the `step=regression` escalation above. Nothing is pushed on red |
| settings | under a brief with a `star:` block, read `<star.home>/star.json` once in Phase 1: `gate` (`model`, `effort`, `fallback`), `tries` (`perStep`, the cap on every loop in this run), `hostedReviewer` (`login`, `minScore`, `maxPasses`, `refreshOutsideCap`, `paused`, or null; `refreshOutsideCap` is true when absent), and `mcps` (what STAR's session found: Mobbin for user-facing design decisions, citing the screen or flow URL; context7 for library, framework, SDK, API and CLI docs at the version the project uses). When a reviewer's comment turns on a library's behaviour or a design choice, check it there before accepting or declining it, using an MCP only when your own session lists its tools; otherwise a web search, named in the reply. Flags win over `gate` only: `hostedReviewer` has no flag |
| progress | under a `star:` brief, append one line to `<star.home>/progress/<item>.log` in `juel:ship-ticket`'s format (`printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "<step>" "<one line>" >> <that file>`), so STAR's progress check sees a worker that waits for a reviewer as alive. `<step>` is exactly one token, which STAR reads: `phase<N>` at the start of phase N; `ready` after Phase 1 marks the PR ready; on each Phase 2 wake `wait-hosted` while a hosted reviewer is set and its review of the PR's current head is not in yet, else `phase2`; `wait-ci` on each poll of the before-`READY` wait for CI; `executor` right before each executor dispatch for a gate fix plan; `regression-gate` right before the gates run through the gate lock; `gate-r<k>` right before gate round `k`; `post-pass` right before `post-pass`; `sync` right before merging the base branch in (Phase 4, or a dirty PR in Phase 2); `report` right before the Phase 5 report line. A progress line is written only by the step it names, at that step, never by a background or detached timer loop the worker starts: such a timer keeps writing after the turn it belongs to ends, and STAR would read a stalled worker as moving (#123). `gate-lock.sh --progress` stays the one writer on a timer, since it lives only as long as the gate it waits for |
| a push in Phase 3 or Phase 4 | under a `star:` brief, every push is gated first. A push that only merges the base branch in (Phase 4 step 1, or a `conflict` wake) is gated by a carry when a script proves the merge brings no change to a file this branch changes: `G` is the `head=` on the first line of the newest `<star.reviews>/<item>-r<g>.md` when that line says `SAFE` (`<g>` is the round of G's review); run `sh <carry-check.sh> --from <G> --head <the merge head> --base <remote>/<base>` (`../star/carry-check.sh` from this file). `OK carried from <G>: <reason>` → no codex round: run the tests Phase 4 step 3 asks of a push that only merges the base branch in, through the gate lock (the `gates run directly` row), push, then `sh <codex-gate.sh> post-pass --pr <url> --round <g> --head <the pushed head> --review <that review's path> --carried-from <G> --reason "<the text after the colon>"`. `NO …`, no SAFE round yet, or `post-pass` printing `ERROR not carried: …` → the codex round below, as for any other push. Round `k` is 1 plus the highest `k` among `<star.reviews>/<item>-r<k>.md`: error logs, raw files and run files never count. Run `sh <codex-gate.sh> --brief <brief> --item <item> --round <k> --base <remote>/<base>` (`../star/codex-gate.sh` from this file), adding `--evidence <its "evidenceDir">` when the `--gates-file` manifest has that key, in the background like `codex exec`. The review streams on its stderr; when it ends, read only the last line of its output, the verdict line, never the transcript. `NOT-SAFE` → its findings are in `<star.reviews>/<item>-r<k>.md`, not in PR comments (all that `receive-review-and-execute` reads), so that skill cannot fix them. The `tries.perStep`-th NOT-SAFE round (3 by default) ends with `RESCOPE item=<item> reason=gate review=<the review path the gate printed>` and no fix, with ` tooling=all` at its end when that round's `tooling=` equals `p0 + p1` (every blocking finding left is in tooling: `RESCOPE item=<item> reason=gate review=<path> tooling=all`). NOT-SAFE rounds are counted since the newest SAFE round or the last push, whichever is later. A SAFE round that could not be pushed, because the PR needed a base merge first, starts a fresh count. Any earlier NOT-SAFE round: validate each `[P0]` and `[P1]` finding with `superpowers:receiving-code-review` against the brief; one outside the brief's scope ends the run as `RESCOPE item=<item> reason=brief review=<a file naming what each finding needs and why the brief excludes it>`. Run each finding's evidence line first (a command in backticks, or a test the finding names): a command whose output does not show the defect, or a test that passes, is a `Disposition:` with that output as the reason. The round's `-fix.md` is `<star.reviews>/<item>-r<k>-fix.md`: one line per finding of that round, numbered as in `<item>-r<k>.md`: `<n>. Fixed in <sha>.[ Sites: …]` or `<n>. Disposition: <the technical reason>`; the gate records each `Disposition:` finding in `<item>-dismissed.md` and never counts a repeat of it. For each accepted `[P0]` or `[P1]` finding, the fix searches the branch for every other site of the same pattern and fixes them all in the same round, and its `-fix.md` line names the sites (`Fixed in <sha>. Sites: <path:line>, <path:line>.`). No finding accepted: skip the plan, the executor, the tests and the commit, write the `-fix.md` and gate again on the same head (the gate's prompt carries the dispositions). Otherwise write a fix plan (`superpowers:writing-plans`, a new `-vN`) whose header carries `**Base:** spec implemented at <the full head>; apply only the tasks below.` and whose tasks each name their files in a `**Files:**` block, and run it with the executor the way `juel:ship-ticket` Phase 4 does (`../ship-ticket/SKILL.md` from this file): `--executor session` means this session, with `superpowers:executing-plans`, told "The plan's Base line overrides its Spec: apply the tasks, and do not re-check the spec for completeness."; otherwise `codex exec` on the model `executor-model.sh` resolves from `--executor-model` and `--executor-effort` (`../ship-ticket/executor-model.sh` from this file), with the capacity and out-of-usage rules of `juel:ship-ticket` Phase 4 (each try resumes from the plan's ledger; a codex usage limit runs the plan in this session), and any other non-zero exit is a failed try of the executor: run the plan again from its ledger, and after `tries.perStep` failed runs `ESCALATION item=<item> phase=8 reason=out-of-tries step=executor review=<a file holding its last lines>`. When the fallback model resolves, through `executor-model.sh`, to the same model id as the executor, there is no fallback: skip straight to running the plan in this session. When you invoke `superpowers:receiving-code-review`, `superpowers:writing-plans` or `superpowers:executing-plans` here, tell it "unattended: the brief is approved, take your default path, ask nothing". Right before the executor runs, from the repo root, note the head (`git rev-parse HEAD`) and record the files already changed: `sh <scope-check.sh> --record "$(git rev-parse --git-path juel_scope_before)"` (`../ship-ticket/scope-check.sh` from this file; write the path in literally, since shell variables do not survive between Bash calls). After the plan ran, run `juel:ship-ticket` Phase 4's scope check, `sh <scope-check.sh> <the plan> <the head before the executor> --before <that record file>`, and restore each `outside` file the way it says: a file in the record is never `outside`, so work that was already there before the executor ran is never restored or deleted. `unchecked …` means nothing was checked: say so in the round's evidence line and go on. Then run the tests for the files the plan changed and the sweep through the gate lock (the `gates run directly` row; `juel:ship-ticket`'s "Gate once per PR"), commit, write the `-fix.md` and gate again; the push waits for a SAFE round and is never forced. `[P2]` and `[P3]` findings never block. A NOT-SAFE round's fix plan fixes them when cheap. A SAFE round's `[P2]` and `[P3]` findings stay in its review: no commit and no push after a SAFE round for them alone. `SAFE` → push, then `sh <codex-gate.sh> post-pass --pr <url> --round <k> --head <pushed head> --review <the review path the gate printed>`: a comment on a ready PR. `post-pass` printing `ERROR`: wait a minute and run it once more; a second `ERROR` → `ESCALATION item=<item> phase=8 reason=out-of-tries step=review-tool review=<the file holding its ERROR line>`. The gate printing `ERROR base-moved …`: the base changed a file this branch changes. Merge it in as Phase 4 step 1 does (a conflict follows the conflict rule in Phase 4 step 1), run the sweep as Phase 4 step 3 asks of a push that only merges the base branch in, and run the same round again: it is not an `ERROR` retry, never counts toward the second `ERROR`, and casts no vote toward `tries.perStep`. An `ERROR fallback-unreadable …` line waits 10 minutes and runs the same round again; it never counts toward the second `ERROR` and casts no vote toward `tries.perStep`. The third `ERROR fallback-unreadable` on the same round ends as `step=review-tool`. The gate's Claude fallback ran because Sol was at capacity, and its format slip says nothing about the code, so it does not spend the round's one retry. The gate printing any other `ERROR`: wait 10 minutes and run the same round once more (an `ERROR` leaves no `<item>-r<k>.md`, so the round number does not move); a second `ERROR` → the same escalation, its `ERROR` line quoted whole, except that an `ERROR gate-down …` line that `codex-gate.sh` itself printed ends as `ESCALATION item=<item> phase=8 reason=out-of-tries step=gate-down review=<the file holding its ERROR line>` (the gate itself is down, and STAR parks the item); any other `ERROR` → `ESCALATION item=<item> phase=8 reason=out-of-tries step=review-tool review=<the file holding its ERROR line>` |
| a hosted reviewer (`hostedReviewer` set) | mark ready first, then the review: Greptile skips draft PRs by default and starts its review when the PR is marked ready, so a decision that asks for its review before ready is answered by this order (#40). Pass `--hosted <login>` to `pr-state.sh` (in place of `--review-bots <login>`): it keeps the login as a review bot, reports the hosted reviewer's status on the head as `hosted`, and turns an edit of its summary comment into a `hosted-pass` item. Pass 1 is the review it started when the PR was marked ready, by the build or by this skill. Keep a pass record in `<star.reviews>/<item>-hosted.log`, one line each: `<iso> pass <n> head=<full sha>` when you judge its review of a head that has no `pass` line yet, `<iso> refresh head=<full sha>` when you comment for a status refresh, or for a second run (below). A second hosted run on a head that already has a `pass` line in `<item>-hosted.log` (a run the reviewer starts again on a head it already reviewed) is logged as `refresh head=<sha>` and never counted as a pass, so a head gets at most one `pass` line (#122). Passes are counted per distinct head: the passes used are the distinct heads with a `pass` line in that file, so a restarted run counts them from the file, never from memory. A missing file is rebuilt from the PR in Phase 1 step 9 (`--hosted-passes`), and is never read as zero passes. A hosted run that reviewed nothing (no confidence score, and its body says the review was skipped or a usage limit was hit; `pr-state.sh --hosted-passes` prints it as `skipped`) is not a pass: log `<iso> skipped head=<sha> <reason>` in `<item>-hosted.log`, spend no pass on it (the passes stay the `pass` lines), and end with `ESCALATION item=<item> phase=8 reason=out-of-tries step=hosted-wait`: STAR parks every babysit while the hosted reviewer reviews nothing (#129). Judge each review the way a person would, from these guidelines, never from its exact markup, which Greptile changes: it is clean when it reviewed the PR's current head (its summary names the commit it last reviewed; when it does not, a review posted after that commit was pushed counts), its confidence is `minScore` (4) out of 5 or better (no score at all: judge from its findings alone), none of its P0 or P1 comments is still open, and nothing in it advises against merging. Clean → Phase 4. Not clean → one batched fix of every P0/P1 comment it left (and any other comment worth fixing), through `receive-review-and-execute`, gated as in the row above, in one push. When that push is for the last pass (the record holds `pass` lines for `maxPasses` minus 1 distinct heads), fetch the base again right before it, and when the base moved and Phase 4 step 1's condition holds (the PR conflicts, or `review-rule.sh` prints `strict` or `unknown …`, or the `synced with <base> at <sha7>` line in `## Decisions` orders the sync: never `behind` alone), merge it in first (Phase 4 step 1, carried as in the row above when it brings no change to a file this branch changes, as `carry-check.sh` decides), so the last pass reviews a head that is current with the base. No review of the head yet → wait. When you cannot tell, it is not clean: say why in a `NOTE`. Pass 2 is its review of that push: when none starts within 10 minutes (it reviews new pushes only when the repo turns on `triggerOnUpdates`), comment `@greptileai`. Still not clean after `maxPasses` (2): write its open findings to `<star.reviews>/<item>-hosted-p<n>.md` and end with `RESCOPE item=<item> reason=hosted-review review=<that file>`. Never ask it for a third pass. Report `READY` only on a head whose review you judged clean: STAR's merge gate trusts that and reads none of the review. A push that only merges the base branch in keeps the hosted review's clean judgement (the codex gate re-gates that push, or carries its SAFE across a merge that brings no change to a file this branch changes, as `carry-check.sh` decides), so `READY` may follow it. When the hosted reviewer posts a status on every head and the pushed head has none from it (the snapshot's `hosted` is `none`; it does not run by itself on a later push), comment `@greptileai` once on that head: a **status refresh**, which never counts toward `maxPasses` and is not the third pass. With `hostedReviewer.refreshOutsideCap` false in `star.json` (the project counts every run the reviewer starts against its cap), a head that needs the reviewer's status after the last pass gets no comment: end with `ESCALATION item=<item> phase=8 reason=out-of-tries step=hosted-review review=<a file saying a reviewer run on <head> would count as pass <n+1>>`, `<n>` being the passes used. Wait for its review of that head before `READY`: clean → `READY`; not clean → as a last pass that is not clean, its open findings written to `<star.reviews>/<item>-hosted-p<n>.md` and `RESCOPE item=<item> reason=hosted-review review=<that file>` |
| the hosted reviewer is paused | The hosted reviewer is paused when `hostedReviewer.paused` is true, or when the project's `CLAUDE.md` or `AGENTS.md` says the hosted reviewer is paused. When paused: no ready-for-review ping, no score wait, and `READY` once codex is SAFE on the head and the checks hold. The hosted-reviewer row above does not apply |
| a review thread someone else opened | reply on every one before `READY`: `Fixed in <sha>.` or `Disposition: <the reason>, <a link when one helps>`. STAR's merge gate fails while one has no reply from you. Never resolve the thread yourself |
| after every background step (an executor run, a gate round, the regression gate, a CI poll, a Phase 2 wake) | before choosing the next step, check for news: re-read the brief's `## Decisions` (STAR appends every answer there before it sends it), then run `orca orchestration check --terminal "$ORCA_TERMINAL_HANDLE" --unread --json` (a dispatched worker names its own terminal). Read messages only with `--terminal "$ORCA_TERMINAL_HANDLE" --unread --json` (or `--terminal "$ORCA_TERMINAL_HANDLE" --peek --json` to look without consuming them). A plain `orca orchestration check` prints only the subjects and still marks them read; if that happened, run `orca orchestration check --terminal "$ORCA_TERMINAL_HANDLE" --all --json` and read the bodies. Act on each message once: before acting on one, look for its id in `<star.home>/progress/<item>.log` and skip it when the id is there; after acting, append `<iso> message <id>`, since Orca has been seen to return a message it already delivered (#213). A decision that is new since the last check overrides this skill's next step: apply it, and never escalate what it settles. A coordinator decision cannot interrupt a background step, so this check is how it arrives within one step |
| the owner is away | not a reason to wait: nothing holds marking ready, replies, review requests or the `@greptileai` comment |

## Yuki mode

`--yuki <home>` is how `juel:ship-ticket --yuki` runs this skill for `juel:yuki`. Nobody watches the
terminal, and this skill **merges the PR** once the merge check below holds. It is not
`--unattended`: there is no brief, no STAR coordinator and no codex gate, and of "Unattended mode"
only the rows this section names apply. In Phase 1, read `<home>/yuki.json` once for `bot` (the bot
reviewer's login, or null) and `mergeMethod`. The progress log is `<home>/progress/<item>.log`, one
`printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "<step>" "<one line>"` line per step. A PR
someone else authored ends at once, as a park: "the PR's author is <login>".

| Normally | With `--yuki` |
|---|---|
| a question to the user: `receive-review-and-execute`'s ambiguous findings or merge conflict, two red gates, a draft PR | invoke `/juel:receive-review-and-execute <pr> --autopilot --only <ids>`, with the ids of this round's `new_feedback`: it decides ambiguous findings and resolves conflicts itself. Its `CONFLICT:` or `STOPPED:` line → park. A red gate goes back through it with the failing output, 3 tries in all, then park. A `draft` wake → `gh pr ready <pr>` once; a second → park |
| Phase 2's wait | the background form with `--max-seconds 600` added, so it wakes at least every 10 minutes, or `--max-seconds 120` while the merge check waits on CI or on GitHub's merge state: `pr-state.sh` has no wake for checks that finish, so a green PR would otherwise sit until the timeout. On each wake, act on it as Phase 2 says, then run the merge check. `timeout` is no news: the merge check alone. `silence`: say nothing, and wait again with `--silence-hours 0`. Three `errors` wakes in a row, or an error starting `gh cannot see` → park. `closed`: merged by someone → the merged step; closed without a merge → park |
| the bot reviewer (`bot` set) | until its review is in, pass `--hosted <bot>` to every `pr-state.sh` call. Its review is in once `sh <script> <pr> --hosted <bot> --hosted-passes` prints a line: a `pass`, or a `skipped` run that reviewed nothing (say so in the progress log, and never wait for it again). Its items are one Phase 3 round like any reviewer's: fix every P0 and P1 and anything else worth fixing, reply on each, one push. After that round, append `bot-done <bot> <head>` to the progress log and leave `--hosted` out of every later call, and `<bot>` out of `--review-bots` (step 8 of Phase 1), so its later comments are neither waited for nor fixed. A restarted run finds the `bot-done` line in the progress log. A bot reviews once, and is never asked for a second pass. No review 24 h after the PR was ready → park |
| Phase 3 step 6 (re-request review) | as written: a person who asked for changes is asked again |
| Phase 4 | runs from the merge check (step 6), not on an `approved` wake |
| gates | through `juel:ship-ticket`'s `gate-lock.sh`, as the `gates run directly` row of "Unattended mode" says, with `--holder "<item>" --progress <home>/progress/<item>.log` |
| Phase 5 | the merged step, or the park |

**The merge check**, once at the end of Phase 1, before the first wait (a PR that is already
mergeable never waits 10 minutes for a timeout), then on every wake once that wake's work is done.
Take the steps in order. The first that does not hold is what this run waits on: append a progress
line whose step is `wait` and whose text names it (`bot`, `review alice`, `ci on <sha7>`), and wait
again.

1. Feedback: `sh <script> <pr> --since <cursor>` (with `--hosted <bot>` while the bot's review is
   not in). New feedback → Phase 3 first.
2. Conflicts: a `merge` of `dirty` → Phase 4 step 1's conflict rule, resolved as `--autopilot`
   resolves it, then the gate and a push. A binary file, a delete/rename conflict, or a file added on
   both sides with no clear union → park.
3. The bot: its review is in and its round is done (above).
4. People: `gh pr view <pr> --json reviewDecision,reviewRequests,latestReviews`, leaving out every
   `[bot]` login. A person who is requested or has reviewed counts. With such a person: the
   `reviewDecision` is `APPROVED`. Or, when it is empty (no rule requires a review), every such
   person's latest review is `APPROVED` and none is still requested. With no such person, there is
   nobody to wait for. Changes requested with no new feedback and no push for 72 h → park.
5. CI on the head: the snapshot's `checks` is `green`. `pending` → wait; still pending 3 h after the
   last push → park. `failing` → rerun each failing check once (`gh run rerun <run id> --failed`).
   Green is a flake. Still red, it is the PR's to fix: through `receive-review-and-execute` with the
   failing log, gated and pushed, 3 tries, then park. Never merge on red, even when the base fails
   the same check: park and say so. No check registered 5 minutes after the last push, while the
   base's head has none either (`gh api repos/<owner>/<repo>/commits/<base>/check-runs --jq
   .total_count` prints `0`), means the repository has no CI, and the gates this run passed are the
   bar.
6. Phase 4 steps 1 to 5: the sync the base requires, its gate and its push. A push goes back to
   step 1.
7. GitHub agrees: `gh pr view <pr> --json mergeStateStatus,headRefOid`. `CLEAN`, `UNSTABLE` or
   `HAS_HOOKS` → merge. `BEHIND` on a base that wants an up-to-date head → Phase 4 step 1, then
   step 1 here. `UNKNOWN` → the next wake. `BLOCKED` with every step above holding is a rule yuki
   cannot meet, such as an approval nobody was asked for or a required check that never reports:
   park, naming it.
8. Merge: `gh pr merge <pr> --<method> --match-head-commit <headRefOid>`, never `--admin` and never
   `--auto`. `<method>` is `mergeMethod`, else the first of squash, merge and rebase the repository
   allows (`gh api repos/<owner>/<repo> --jq '[.allow_squash_merge, .allow_merge_commit,
   .allow_rebase_merge]'`). Refused because the head moved → step 1. Any other refusal → park, with
   GitHub's message.

**Merged.** Append `merged <url> <merge commit sha>` to the progress log, print
`MERGED item=<item> pr=<url>` as the last line, and end. The worktree is `juel:yuki`'s to remove:
never remove the one this session runs in.

**Parking.** Append `parked <reason>` to the progress log, print `PARKED item=<item> reason=<reason>`
as the last line, and end. `<reason>` is one line naming what is needed. Yuki frees the slot and
tells the owner, and the worktree and this session stay. Never merge to avoid a park.

## Reviewer mode

Phase 1 step 2 chose it: someone else authored the PR, and you reviewed it with
`juel:review-pr`. Reviewer mode keeps the PR moving from the reviewer's side. It waits until the
author is ready for you again, re-reviews through `juel:review-pr` in place of
`juel:receive-review-and-execute`, and asks you before every post.
It never commits, pushes, merges, runs gates or edits the author's branch.
"Unattended mode" does not apply to it: nothing goes out without your answer, except under
`--yuna` (see "Yuna mode" at the end of this section), where yuna's owner has already said yes.

`<you>` is `gh api user --jq .login`. Before the first wait, it stops with the reason when any of
these fails:

- `--unattended` is set: STAR never runs reviewer mode, because every round needs your answer.
  Under `--unattended` the stop prints a progress line, `the PR's author is <login>: reviewer mode runs only interactively`, then
  `ESCALATION item=<item> phase=8 reason=out-of-tries step=worker`, `<login>` being the PR's author, so STAR's stage ends with a state line.
- You have no submitted review on the PR. This prints one line per review of yours, oldest first,
  so the last line is your newest:
  `gh api repos/<owner>/<repo>/pulls/<pr>/reviews --paginate --jq '.[] | select(.user.login == "<you>" and .state != "PENDING") | [.commit_id, .submitted_at] | @tsv'`.
  No line: stop with "Review it first with /juel:review-pr".
- The working tree is dirty: `git status --porcelain` prints anything. Name the files and stop;
  never discard them.
- Nobody can answer a question in this session: stop with "reviewer mode needs you at the
  keyboard". Under `--yuna` this stop does not apply.

Each row overrides the phase it names:

| Phase | Reviewer mode |
|---|---|
| 1. Resolve PR and gates | Steps 1, 3 and 5 as written. Steps 4 (gates), 7 (`--mark-ready`), 8 (review bots), 9 (the hosted log) and 10 (the hosted refresh) do not apply. The **reviewed head** is the `commit_id` of your newest review (the last line above), the **cursor** is its `submitted_at`, and quiet-since is the same time. When `gh pr view --json number --jq .number` on the current branch does not print `<pr>`, run `gh pr checkout <pr>`. |
| 2. Wait for feedback | `sh <script> <pr> --wait --as-reviewer <you> --reviewed-head <reviewed head> --settle-minutes 30 --since <cursor> --interval 600 --silence-hours 72 --quiet-since <quiet-since>`, in the background as in Phase 2 (Codex: the foreground form with `--max-seconds 540`, run again on `wake: timeout`). Every wait after the first passes `--head-seen <the last snapshot's head_seen>`, in both forms: a wait again after `errors`, `silence` or `timeout`, and the wait after a round, so the 30 minute settle clock never restarts. A snapshot that has no `head_seen` (an `errors` wake with no good snapshot) leaves it out, and the script ignores a sighting of another head. On `wake`: `rerequested` (the author asked for your review again) or `settled` (a new head has stayed put for 30 minutes) → Phase 3. `closed` → Phase 5. `silence` → say once "no re-request or settled push for 72 h, still waiting", then wait again with `--silence-hours 0`. `errors` and `timeout` as in Phase 2. No other wake comes in this mode. The snapshot's `reviewers` is empty here, and reviewer mode never takes the `cursor` the snapshot prints: in this mode it still moves with the author's items, so only Phase 3 step (4) sets the cursor. |
| 3. Remediate and push | **Re-review.** (1) `git status --porcelain` prints nothing; otherwise stop and name the dirty files: never discard them. (2) `gh pr checkout <pr> --force`, which moves the local branch to the PR's head, a force-push included. (3) `/juel:review-pr --pr <pr> --since <reviewed head> --from-babysit`: it reviews, asks you, then posts, replies and resolves your fixed threads, all behind its Step 7 question. (4) Read its last line, then set the cursor to now (an ISO time with `Z`) and quiet-since with it, whatever the line says and never from the snapshot, so a re-request already handled never wakes the wait again. `REVIEW-PR posted verdict=APPROVE …` → Phase 5. `REVIEW-PR posted verdict=REQUEST_CHANGES …` or `REVIEW-PR posted verdict=COMMENT …` → the reviewed head becomes its `commit=`, back to Phase 2. `REVIEW-PR not-posted head=<sha>` → the reviewed head becomes that `<sha>`, so the same head never wakes again, back to Phase 2. `REVIEW-PR head-moved from=<sha> to=<sha>` → the reviewed head stays, back to Phase 2: the new head wakes `settled` once it has stayed put for 30 minutes. `REVIEW-PR stopped reason=<why>` → Phase 5 with that reason. |
| 4. Final sync and push | SKIPPED: "reviewer mode: nothing to push". |
| 5. Report | The PR URL; each round with its verdict (or "not posted"), the threads it resolved and the comments it added; and the outcome: **"Approved by you"**, **"Merged or closed by someone else"**, or why it stopped. |

### Yuna mode

`--yuna <home> --item <item>` runs reviewer mode as a `juel:yuna` worker. `<home>` is yuna's folder,
absolute, and `Y` is `sh <yuna.sh> --home <home>`, `<yuna.sh>` being `../yuna/yuna.sh` from this
file. The flag is refused, with one line, in author mode, with `--unattended`, with `--yuki`, and
without `--item`. Nobody is at the keyboard, so these rows change the reviewer mode above:

| Where | Yuna mode |
|---|---|
| The stops | The stop "Nobody can answer a question in this session" does not apply. The other stops print `PARKED item=<item> reason=<why>` as the last line and append `parked <why>` to `<home>/progress/<item>.log`. |
| Every `gh` and `git` call | Runs as `Y gh …` and `Y git …`, which carry yuna's GitHub token. `<you>` is `Y gh api user --jq .login`. |
| Every wait | Before each Phase 2 wait, append `wait author` to the progress log: the sweep reads it as "not quiet". The wait itself is as written. |
| Phase 2, `silence` | Do not wait again. Append `released author silent for <silenceHours> h`, print `RELEASED item=<item> reason=author silent for <silenceHours> h` as the last line, and end. `<silenceHours>` is `silenceHours` in `<home>/yuna.json` (72 when absent), and the wait's `--silence-hours` is that number. A later re-request lists the PR again and yuna starts a new round. |
| Phase 2, `closed` | Phase 5. The sweep sees the PR is merged or closed and removes the worktree. |
| Phase 3, step (3) | `/juel:review-pr --pr <pr> --since <reviewed head> --from-babysit --yuna <home> --item <item>`. It posts by itself, with no question. |
| Phase 3, step (4) | `REVIEW-PR posted verdict=APPROVE …` → append `approved <url> <commit>`, print `APPROVED item=<item> pr=<pr url>` as the last line, and end. Other `posted` lines, `head-moved` and `not-posted` as written. `REVIEW-PR stopped reason=<why>` → append `parked <why>`, print `PARKED item=<item> reason=<why>` as the last line, and end. |
| 5. Report | The last line is `APPROVED`, `RELEASED` or `PARKED` as above. When the PR merged or closed there is no result line: the sweep sees the state and removes the worktree. |

Progress lines are written as `printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "<step>" "<text>" >> <home>/progress/<item>.log`.
The worker never pushes, commits or merges: the reviewer only reviews.

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
   `ESCALATION item=<item> phase=8 reason=out-of-tries step=review-tool review=<the file holding the one line>`.
5. Script: `${CLAUDE_PLUGIN_ROOT}/skills/babysit-pr/pr-state.sh` when `CLAUDE_PLUGIN_ROOT` is
   set, otherwise `pr-state.sh` next to this SKILL.md.
6. Cursor: `--since` when given, else the PR's `createdAt`, so feedback that arrived before this
   skill started is handled in round 1. After that the cursor is whatever `pr-state.sh` last
   printed as `cursor`, an opaque string passed back unchanged. Quiet-since: now, as an ISO time
   with `Z` (`2026-10-01T09:00:00Z`).
7. With `--mark-ready` and a draft PR (`gh pr view <pr> --json isDraft,headRefOid`): under
   `--unattended`, check the `--reviewed` proof first ("Unattended mode"); then `gh pr ready <pr>`, once. A PR that is already ready is left
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
   record's `pass` lines, one per head the reviewer reviewed; an empty file means no pass yet. A `skipped` line it prints stays in the log as it is and is never a pass.
   An `error` line writes no file: `rm -f <log>.tmp`, wait 60 seconds and run it once more.
   A second `error` → `ESCALATION item=<item> phase=8 reason=out-of-tries step=gh review=<the file holding its error line>`,
   the escalation for a GitHub that cannot be read. A missing log is never read as zero passes.
   When the log exists and holds a second `pass` line for a head that already has one (a log
   written before the one-pass-per-head rule, #122), rewrite each such later line as
   `<its iso> refresh head=<that sha>`, keeping the first `pass` line of each head and every other
   line as it is, before anything counts its passes: STAR's merge order counts `pass` lines with
   `grep -cE '^[^ ]+ pass [0-9]+ head='`, so a head must never hold two.
10. Under a `star:` brief with a hosted reviewer: when the PR's head has no status from the hosted
   reviewer while it already reviewed an earlier head (its summary comment is on the PR), run the
   status refresh (the hosted-reviewer row in "Unattended mode") before the first wait, or, with
   `refreshOutsideCap` false and every pass used, that row's `step=hosted-review` escalation. STAR sends
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
| `feedback` | Phase 3 with this object's `new_feedback`, `reviewers` and `cursor`. An item with `kind: hosted-pass` is the hosted reviewer's re-review of `head`, made by editing its summary comment: judge that review first, by the hosted-reviewer row of "Unattended mode" (clean → Phase 4; not clean → its batched fix), and leave the item itself out of Phase 3's replies. An item with `kind: hosted-skip` is a hosted run that reviewed nothing (its `reason` says why): log `<iso> skipped head=<its head> <reason>` in `<item>-hosted.log`, spend no pass on it, and end with the hosted-reviewer row's `ESCALATION item=<item> phase=8 reason=out-of-tries step=hosted-wait`; leave the item out of Phase 3's replies. |
| `conflict` | The PR conflicts with its base (`merge` is `dirty`): CI and the hosted review do not start on a conflicting head, so waiting is pointless. Run Phase 4 steps 1 to 4 now (merge the base in under the conflict rule of Phase 4 step 1, the tests step 3 asks of a push that only merges the base, and under a `star:` brief the push's gate, a carry of the last SAFE when the merge brings no change to a file this branch changes, as `carry-check.sh` decides; push it only as the hold in Phase 4 step 4 allows), add one to this run's base syncs, then wait again on the new head with the same cursor. When step 1 finds nothing to merge (the base is already in, so GitHub's `dirty` is stale), count no sync: wait 60 seconds and run the script again instead of re-entering `--wait`, which would wake `conflict` at once. A conflict follows the conflict rule in Phase 4 step 1, and ends as it says |
| `approved` | Phase 4 |
| `draft` | The PR is approved but is a draft (someone converted it back). Tell the user and stop; under `--unattended`: `ESCALATION item=<item> phase=8 reason=out-of-tries step=pr-draft` |
| `closed` | Phase 5: report "PR was closed or merged by someone else" and stop |
| `errors` | Tell the user the `error` in one line, then wait again (same arguments) |
| `silence` | Tell the user once "no feedback for 24 h, still waiting", then wait again with `--silence-hours 0` |
| `timeout` | Codex only: wait again |

The same holds for a snapshot whose `merge` is `dirty` on any other wake (a `timeout` under
`--unattended`, say): handle it as a `conflict` wake first. `behind` is not acted on here: CI still
runs on a head that is behind, and syncing after every merge into the base would cost a regression gate
each time. Phase 4 merges the base in before `READY` only by the one sync rule in step 1 (a conflict, a
base that requires an up-to-date head or is unreadable, or a STAR order in `## Decisions`), once per run, and
STAR's merge gate still sends a strict base back when the base moved after that.
A gate round that prints `ERROR base-moved` is the one case where a `behind` PR is merged outside Phase 4. Outside babysit's Phase 4 sync before `READY` and STAR's "Sync after the base moved", a worker merges the base in only when the PR is CONFLICTING or a gate round refuses with `ERROR base-moved`, never otherwise. The last hosted pass's base merge runs Phase 4 step 1, so it is part of that sync.

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

## Phase 4: Final sync and push (merges the base in when the base requires it or the PR conflicts)

1. Phase 4 merges the base in only when the last snapshot's `merge` is `dirty`, or
   `review-rule.sh <repo> <base>` (next to this file) prints `strict` or `unknown …`, or the brief's
   `## Decisions` holds the line `synced with <base> at <sha7>`, which STAR's "Sync after the base moved"
   writes to order a base sync before `READY` (STAR's decisions are orders). A `queue` base is no reason to sync
   (#212): the queue tests the base plus the PR on its own branch, so a sync only gives it a head to test
   again, and STAR's `merge.sh` queues the PR instead; a `strict` line printed beside `queue` does not
   count either. `unknown` means the rule could not be read, so it is not assumed to be absent.
   `behind` alone is not a reason (#204): on a base that moves every few minutes each sync is behind
   again before CI and the gate finish, so the sync never settles, and STAR's merge gate and `merge.sh`
   decide what a behind PR needs. Phase 4 syncs at most once per run: a PR the base left behind again
   while CI and the gate ran reports `READY` all the same. Otherwise it
   goes on as step 2's "Already up to date" path. That condition is for the final sync alone: a
   merge another rule orders (a `conflict` wake, an `ERROR base-moved` round, STAR's "Sync after
   the base moved") always fetches and merges the base as below. `<base>` is the snapshot's `base` from the last `pr-state.sh` output, not the one resolved in
   Phase 1: someone may have retargeted the PR. `git fetch <remote> <base>` then `git merge --no-edit <remote>/<base>`.
   Note `git rev-parse HEAD` before the merge. **The conflict rule** (the one rule for a conflicted
   base merge, here, in `juel:receive-review-and-execute` and in `juel:ship-ticket`): resolve the
   conflicted files yourself, keeping both changes' intent, from both items' briefs and `## Decisions`
   and the sibling PR's diff and description. The merge commit message is
   `Merge <remote>/<base> into <branch>; conflicts resolved in <files>`. A lockfile is never merged by
   hand: take the base's version, run the project's install command to regenerate it, and stage the
   result.
   - Under `--unattended` or `--brief`: if a `## Decisions` entry names those files and a resolution,
     apply it as written; otherwise resolve them as above and record the resolution as a
     `## Decisions` line. Then run the regression gate and the codex gate on the result (step 3 and the
     push-gate row). Failing those gates spends tries, and `tries.perStep` failures end as
     `ESCALATION item=<item> phase=8 reason=out-of-tries step=conflict`. A binary file, a
     delete/rename conflict, or a file added on both sides with no clear union is
     `ESCALATION item=<item> phase=8 reason=out-of-tries step=conflict` with the files named.
   - By hand: resolve the same way but do not commit yet. Stage the resolution, run the tests the
     push needs, then show the user the resolved hunks of each conflicted file
     (`git diff --cached -- <files>`) and ask before committing and pushing; "abort" is
     `git merge --abort`. A binary file, a delete/rename conflict, or a file added on both sides with
     no clear union: ask.
   Step 3's gates run on the merge as usual. A red gate keeps the merge commit and is step 3's red, as
   for any other push: the sweep may have caught a break in a file that did not conflict, which a fix
   of your own repairs. A green gate pushes, and the Phase 5 report names the resolved files.
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
   Under `--unattended` with a hosted reviewer set and not paused, every push a `conflict` wake or Phase 4 step 1 makes (the base merge, and any fix it needed to go green) holds first, because a push ends a running pass early
   and starts another run, so the pass the reviewer is working on never finishes and a run is spent
   for nothing: while the snapshot's `hosted` is `pending` or `unknown` on the PR's head, keep the merged, gated
   commits local, wait 60 seconds and run the script again, and push only once `hosted` is neither
   (`unknown` holds too: a status that cannot be read may be a pass still running). The wait ends where the hosted-reviewer row's wait ends: 72 hours with no new feedback
   since the PR was marked ready ends with `ESCALATION item=<item> phase=8 reason=out-of-tries
   step=hosted-wait`. When the pass that finished is not yet judged, judge it first, as the
   hosted-reviewer row says, and then push: a clean review keeps its judgement across the push; a
   not clean one gets its batched fix in this push, except when it was the last pass (`maxPasses`), push nothing and end with `RESCOPE item=<item> reason=hosted-review` as the hosted-reviewer row says, its open findings in `<star.reviews>/<item>-hosted-p<n>.md`. When the passes used (the distinct heads with a
   `pass` line in `<item>-hosted.log`) equal `maxPasses` and `hostedReviewer.refreshOutsideCap` is
   false, the push would start a reviewer run that counts as a pass beyond the cap, so push nothing
   and end with `ESCALATION item=<item> phase=8 reason=out-of-tries step=hosted-review review=<a file
   saying a push of the base merge on <head> would start a reviewer run that counts as pass <n+1>>`,
   `<n>` being the passes used. With `refreshOutsideCap` true that push stays as the hosted-reviewer
   row says: a status refresh that does not count.
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
