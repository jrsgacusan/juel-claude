---
name: team
description: Use only when the user asks for juel:team or /juel:team by name, or explicitly asks to spawn a supervised Orca team of Claude and Codex workers for a goal (research, testing, review, implementation) - discovers the models available right now, picks one per role, shows the roster for approval, then supervises the workers and a blind synthesizer to one result. Not for a passing mention of agents. Triggers "/juel:team", "use juel:team".
argument-hint: "<goal> [with N agents] [use <model>] [synthesize with <model>]"
metadata:
  requires:
    cli:
      - id: orca
        hard: true
        why: every worker is spawned and supervised through Orca orchestration
        check: "resolve_bin orca against PATH, then the app-bundle candidate"
      - id: python3
        hard: true
        why: discover-models.sh parses both model catalogs with python3
        check: "command -v python3"
      - id: codex
        hard: false
        why: lists Codex models and runs Codex workers
        check: "command -v codex"
        fallback: plan with Claude workers only and say so in the roster
      - id: claude
        hard: false
        why: lists Claude models and runs Claude workers
        check: "command -v claude"
        fallback: plan with Codex workers only and say so in the roster
    skills:
      - id: orchestration
        hard: true
        why: the version-matched Orca guide owns the run, task and worker lifecycle
    context:
      - id: orca-runtime
        hard: true
        why: workers start only against a reachable Orca runtime
        check: "orca status reports runtimeReachable: true and graphState: ready"
---

# Team

Turn a goal into a supervised Orca team: distinct worker briefs, the best current model per
role, a roster the user approves, then every report collected and blindly synthesized.
`/juel:team` plans; Orca orchestration runs. Never restate Orca command syntax beyond the
calls named here.

**Announce at start:** "Using juel:team to plan the team."

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
| orca | cli | HARD | `resolve_bin orca` against PATH, then the app-bundle candidate | STOP → https://www.onorca.dev |
| python3 | cli | HARD | `command -v python3` | STOP → install Python 3 |
| codex | cli | SOFT | `command -v codex` | plan with Claude workers only and say so in the roster |
| claude | cli | SOFT | `command -v claude` | plan with Codex workers only and say so in the roster |
| orchestration | skill | HARD | `$ORCA skills get orchestration` exits 0 | STOP → update Orca |
| reachable Orca runtime | context | HARD | `orca status` reports `runtimeReachable: true` and `graphState: ready` | STOP → run `orca open`, then re-run |

If both `codex` and `claude` are missing, the verdict is STOP: a team needs at least one agent CLI.

All satisfied renders as: `Preflight: 6/6 OK (orca, python3, codex, claude, orchestration, Orca runtime)` / `→ PROCEED: all requirements met.`

```bash
# No numbered positional parameters anywhere in this file: the skill loader replaces them
# with words from the user's request. Bare names are looked up on PATH, absolute paths tested.
resolve_bin() {
  for c in "$@"; do
    case $c in
      /*) [ -x "$c" ] && { printf '%s' "$c"; return 0; } ;;
      *) p=$(command -v "$c" 2>/dev/null) && { printf '%s' "$p"; return 0; } ;;
    esac
  done
  return 1
}
# Orca's own resolution order: ORCA_CLI_COMMAND, then orca-dev in a dev checkout
# (ORCA_DEV_REPO_ROOT set), then orca-ide on Linux outside Orca terminals, then orca.
# The app-bundle path is a labelled candidate tried after PATH, never inlined.
ORCA=${ORCA_CLI_COMMAND:-}
[ -z "$ORCA" ] && [ -n "${ORCA_DEV_REPO_ROOT:-}" ] && ORCA=orca-dev
[ -z "$ORCA" ] && [ "$(uname)" = Linux ] && [ -z "${ORCA_TERMINAL_HANDLE:-}" ] && ORCA=orca-ide
[ -z "$ORCA" ] && ORCA=$(resolve_bin orca /Applications/Orca.app/Contents/Resources/bin/orca \
        "$HOME/.local/bin/orca" /opt/homebrew/bin/orca /usr/local/bin/orca)
```

Below, `$ORCA` is the executable resolved here. Reuse it for every Orca call. If it cannot run,
report its exact error and stop; never fall through to another executable.

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Check team fit
2. Load the orchestration guide
3. Discover models
4. Decompose into roles
5. Assign models and effort
6. Show the roster
7. Launch and supervise workers
8. Synthesize and report

## Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `<goal>` | required | What the team should produce |
| `with N agents` | 2 to 3 | Number of parallel workers; the synthesizer is extra and shown as its own row |
| `use <model>` | rubric | Pin a model for all workers, or for a role (`use astra for research`) |
| `synthesize with <model>` | rubric | Pin the synthesizer's model |
| `no synthesizer` | off | The coordinator synthesizes instead of a separate agent |

Usage: `/juel:team research X with 3 agents, then synthesize`, `/juel:team spawn testers for the checkout flow, use gpt-6-luna`

## Phase 1: Check team fit

1. **Refuse inside a worker.** If this conversation carries an Orca dispatch preamble (a task id,
   a dispatch id and `worker_done` instructions), you are a worker: workers cannot spawn workers
   (`nested_worker_depth_exceeded`). Say so in one line and stop.
2. **Resources.** Run `vm_stat` (macOS) or `free -h` (Linux) and
   `ps -Ao pid,rss,command | sort -k2 -rn | head -15`. Count running agent CLIs. Each agent TUI
   holds hundreds of MB. If memory is tight or several agents already run, carry a warning into
   the roster and propose fewer workers.
3. **Is a team warranted?** Not for a single fact lookup, a short sequential task, or tightly
   coupled edits to the same files. Then say "this does not split well, I can do it inline" and
   ask once. If the user still wants a team, continue.

## Phase 2: Load the orchestration guide

Run `$ORCA skills get orchestration` and read it fully. It is the only authority on Orca
commands for the rest of this skill. If the binary rejects `skills get`, say updating Orca
restores the guide and stop.

## Phase 3: Discover models

Locate the script: `${CLAUDE_PLUGIN_ROOT}/skills/team/discover-models.sh` when
`CLAUDE_PLUGIN_ROOT` is set; otherwise (Codex) `discover-models.sh` in the same directory as
this SKILL.md. Run it with `sh <path>`.

Each stdout line is one JSON object:

- a model: `provider`, `id`, `name`, `description`, `efforts`, `default_effort`, `resolves_to`,
  `flags` (`retiring`, `legacy`, `alias`)
- or a failure: `provider`, `unavailable`

The output is the only source of model ids. Per provider:

- `unavailable` says `claude not found on PATH`: no Claude workers can launch; plan Codex-only.
- any other `claude` failure (timeout, shape, no `control_response`): the CLI exists but its
  listing broke; fall back to the aliases `fable`, `opus`, `sonnet`, `haiku` with `efforts`
  unknown (omit `--effort` for them).
- `codex` unavailable for any reason: plan Claude-only.

State any fallback in the roster. A listed model can still be unusable on this account (no
credits, no access); Phase 7 catches that at launch.

## Phase 4: Decompose into roles

Parse the request: goal, deliverable, worker count, global and per-role model or effort
overrides, synthesizer preference.

Create the team directory once:

- the session scratchpad if this harness provides one, else `${TMPDIR:-/tmp}/team-runs`
- plus `/<goal-slug>-<YYYYMMDD-HHMM>`; if that path exists, append `-v2`, `-v3`, never reuse it

Write one brief per worker to `<team-dir>/briefs/<role>-<n>.md` containing:

- **Goal** and the one question or test area this worker owns
- **Out of scope:** the other workers' areas, by name
- **Sources and tools** to use (Context7, web search, the repo, a browser)
- **May write:** its report file only, unless the role edits code; name shared resources
  (browser, ports, test accounts, fixtures) it may use and must not share
- **Report:** path `<team-dir>/reports/<role>-<n>.md` with exactly these headings:
  `## Findings`, `## Evidence`, `## Uncertainty`, `## Gaps`. Do not name your model or
  provider anywhere in the report.
- **Stop condition** and: "Do not spawn workers. Report `worker_done` with the report path."

Distinct angles beat role names: three researchers get three different questions (for example
primary sources, alternatives and economics, failure cases), never "research X" three times.
When the goal is confidence rather than breadth, replication of one question is allowed; label
it replication.

Sizing: default 2 to 3 parallel workers. More than 5 parallel workers needs the user to confirm
the count in the roster. Honor an explicit count exactly.

The synthesizer (unless the user said `no synthesizer`) gets
`<team-dir>/briefs/synthesizer.md`: read `<team-dir>/blind/*.md`; write
`<team-dir>/synthesis.md` with `## Agreements`, `## Disagreements` (each with a ruling and
reason), `## Single-source claims` (flagged unverified), `## Synthesis`. It does not know which
model wrote which report.

## Phase 5: Assign models and effort

**Overrides first.** Match each named model against discovered `id`, `name` or `resolves_to`,
case-insensitively. A miss that looks like a typo: show the closest ids and ask; never
substitute silently. A miss that looks like a deliberate custom or deployment id: keep it as
typed and note "not in catalog" in the roster. A named `retiring` model: keep it, warn.

**Rubric for everything else:**

1. Eligible: no `legacy` and no `retiring` flag, and not top tier.
   **Never propose a top-tier model** (frontier / toughest / most capable) for any role unless
   the user names it or explicitly asks for the top tier. They cost several times the mid tier
   and an account may lack credits for them.
2. Tier from the `description`, case-insensitive keywords:
   - top: frontier, toughest, hardest, most demanding, most capable
   - mid: workhorse, complex, everyday
   - light: fast, affordable, efficient, simpler, quick, routine
   - no match: "unclassified"; show it, never guess its tier
3. Newest within a tier: script output order (Codex is sorted by catalog priority; Claude keeps
   its listing order). Prefer a Claude `alias` over a pinned id of the same model, and show
   `resolves_to` so the user sees what the alias means today. Never read priority as price or
   speed.
4. Role to tier: tester, mechanical sweep, extraction → light; every other role (researcher,
   debugger, implementer, synthesizer, judge) → mid. A user who asks for "the best" or "top
   tier" for a role gets the top tier for that role only.
5. Parallel peers alternate providers unless the user pinned one.
6. The synthesizer runs on the minority provider among the workers (tie: the provider not used
   by the first worker).

**Effort:** tester `medium`; researcher `high`; synthesizer `high` on Claude, `xhigh` on Codex.
Clamp to the model's `efforts`: if the level is not listed, take the highest listed level below
it. Empty `efforts`: omit `--effort`. Never choose `max` or `ultra` yourself (`ultra` makes a
Codex worker delegate to sub-agents of its own); use them only when the user names them.
Always pass an effort for Codex workers, whose catalog default can be `low`.

## Phase 6: Show the roster

One table, then stop:

| # | Role | Agent | Model | Effort | Angle | Report |
|---|------|-------|-------|--------|-------|--------|
| 1 | researcher | codex | gpt-6.1-sol (GPT-6.1-Sol) | high | primary sources | reports/researcher-1.md |
| 2 | researcher | claude | opus (Opus 5.5) | high | failure cases | reports/researcher-2.md |
| 3 | synthesizer | claude | opus (Opus 5.5) | high | blind merge | synthesis.md |

(Example shape only; the values always come from Phases 3 to 5.)

Below the table: one-line rationale per row, total workers, the memory note from Phase 1, and
any unavailable provider, fallback or override warning. Then ask: **"Go?"**

Wait. "go" or "yes" launches. Edits ("2 researchers", "use astra for synthesis") rerun Phases
4 and 5 for what changed and show the table again. "no" ends the skill with nothing spawned.

## Phase 7: Launch and supervise workers

This is **supervised orchestration with `worker_done` waits**, not a handoff. Follow the guide
from Phase 2 for every command; the sequence is:

1. `run-create` with the goal as objective.
2. `task-create` for every worker, spec: "Read the brief at `<brief path>` and follow it
   exactly." Create the synthesizer task too, with `--deps` on every worker task.
3. `worker-start --task <id> --worktree current --agent <codex|claude> --model <id>
   [--effort <e>] --json` for each worker task. Use a `new-child` worktree only when two
   workers would edit the same files.
4. Read each receipt. If it rejects the effort (`does not support effort`), retry that worker
   once with the next lower listed level and note it. Any other start failure: report the
   receipt's stage and residual resources, mark that role failed, do not retry blindly.
5. Print one line per worker with `launch.effective` (agent, model, effort).
6. **Confirm each worker is actually working.** Read each worker's recent output once (the
   guide's bounded read command) and again for every worker still unreported at each wait
   timeout. A worker stuck at a prompt (model switch, usage credits, login, trust dialog) or
   showing no activity never sends a message on its own: stop it per the guide, tell the user
   why, and offer the next eligible model in the same tier. Never answer the prompt for it.
7. Wait with `check --wait --types worker_done,escalation,question`. Process every message in a
   Delivery, answer `question`s, then acknowledge. A timeout is a checkpoint, not a failure.
8. On each `worker_done`: confirm the report file exists, is non-empty, and has all four
   headings. If not, send the worker a follow-up asking for the complete report at that path
   and keep waiting. Once complete, `worker-release` that dispatch.
   If the release reports `retained`, follow the receipt's recovery action; if the terminal is
   still open after that, record the worker, the reason and its terminal handle for the final
   reply.
9. Continue until **every** worker dispatch has settled. A worker that fails is a gap: record
   it, never fill it in.

## Phase 8: Synthesize and report

1. Copy each complete report to `<team-dir>/blind/A.md`, `B.md`, ... in a shuffled order.
   Redact self-identification only: an author or title line naming the writing model ("report
   (Claude, Opus 5.5)") and phrases like "as <model>, I ...". Never delete lines because they
   mention a model or provider as the subject of the research. If anything beyond a header line
   was redacted, say so in the final reply. Keep the label-to-report mapping to yourself until
   the end.
2. `worker-start` the synthesizer task (it became ready when its dependencies completed) with
   its assigned model, supervise it exactly as in Phase 7, validate its four headings, release
   it. With `no synthesizer`, do the same synthesis yourself into `<team-dir>/synthesis.md`.
3. Reply with: the synthesis path, a 5-line summary, the label-to-worker mapping, the report
   paths, any failed or missing role, and every worker terminal still open (worker, retain
   reason, terminal handle) so the user can close it.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Spawning before the user says go | Phase 6 always stops |
| Same brief to every researcher | One distinct question each, with exclusions |
| Synthesizing on a partial set | Wait until every dispatch settled; gaps stay gaps |
| Passing `--effort` to a model with no efforts | Omit it |
| Picking `max` or `ultra` because the role feels important | Only when the user names them |
| Trusting a 3-sentence `worker_done` body | Read the report file |
| Letting /orchestration treat "use <model>" as a handoff | Say "supervised orchestration with worker_done waits" |
| Hardcoding a model name in a brief or rule | Use discovered ids only |
