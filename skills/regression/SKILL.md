---
name: regression
description: Use to verify a frontend change in a real browser against a work item's acceptance criteria, capturing screenshots as evidence. Invoked by juel:ship-ticket phase 7 for the frontend path, or directly when you want the browser driven for you. Triggers "verify this in the browser", "run the regression", "/juel:regression".
metadata:
  requires:
    mcp:
      - id: playwright
        hard: true
        why: phases 2-3 drive the browser through Playwright MCP tools to reach the app and exercise each criterion
        check: none
    context:
      - id: app-url
        hard: true
        why: phase 1 needs a URL to open — an explicit argument, or the resolved commands.run started in the foreground
        check: "resolved commands.run or an explicit URL argument"
      - id: verification-criteria
        hard: false
        why: phase 1 needs the acceptance criteria to verify — from the work item or the spec file
        fallback: ask the user for the steps to verify, and record them
---

# Regression

## Overview

Drives Playwright MCP to verify a frontend change in a real browser against a work item's acceptance criteria, capturing a screenshot per step as evidence. Every criterion resolves to exactly one of three outcomes — `pass`, `fail`, or `unverifiable` — never silently dropped and never guessed.

**Announce at start:** "Using juel:regression to verify this change in the browser against the resolved acceptance criteria."

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
| Playwright MCP | mcp | HARD | **none — render as `?`** | proceed; phase 2 fails loudly if the browser tools are absent |
| running app URL | context | HARD | resolved `commands.run` or an explicit URL argument | STOP → tell me where the app is running |
| acceptance criteria | context | SOFT | work item, or the spec file | ask the user for the steps to verify, and record them |

## Phases

[ ] 1. Resolve the target — URL, and the criteria to verify
[ ] 2. Launch the browser and reach the entry point
[ ] 3. Drive each criterion, capturing a screenshot per step
[ ] 4. Map every criterion to an observed result — pass, fail, or unverifiable
[ ] 5. Report the evidence and write it to ${docsRoot}/findings/

## Arguments

| Argument | Default | Description |
|----------|---------|--------------|
| `[url]` | resolved `commands.run`, started in the foreground | The running app's URL to verify against |
| `[ref]` | auto-detect from worktree (`detect_ref`, inlined in Phase 1 below) | Work item to pull acceptance criteria from |

Usage: `/juel:regression`, `/juel:regression https://localhost:3000`, or `/juel:regression SAVI-1162`

## Workflow

### Phase 1 — Resolve the target

**Resolve the URL, in order:**
1. Explicit URL argument.
2. The resolved `commands.run` — **only when this session already resolved and reported it** (e.g. `juel:ship-ticket` Phase 4's checkpoint, still visible earlier in this same conversation). Reuse that exact value and start it in the **foreground** (`run_in_background: false`), reading the listen URL from its own output — never redirected to a log file. **This skill never independently runs a tiered install/test/run-command probe of its own to invent a value here** — that full Tier A/B/C manifest table is defined in `juel:ship-ticket`'s "Toolchain commands" section, a file this skill has no guarantee of ever having loaded when invoked standalone, so treating it as available would be exactly the kind of guessed result this skill exists to avoid. When invoked standalone with nothing already resolved and reported, this step does not apply — fall through to step 3.
3. Ask the user where the app is running.

If none of the three resolves to a real URL, STOP — do not guess a port or protocol.

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
mkdir -p "$docsRoot/findings"
```

(If `.claude/workflow.json` or `.claude/workflow.local.json` sets `docsRoot`, that value wins over
the filesystem check above — config always takes precedence.)

Ensure the repo's `.gitignore` contains unanchored `superpowers/` and `.superpowers/` entries —
unanchored so they match at any depth. Add them if absent. This directory is scratch, not product.

**Resolve `ref`**, needed by step 2 below to fetch the work item's acceptance criteria. Run
`detect_ref` — anchored to whole `/`-delimited path segments, with a denylist of generic
branch-type words, so a branch like `chore/bump-2fa-lib` or `release/v2-1` is never mistaken for a
ticket key (the old loose match turned those into `BUMP-2` and `V2-1`). Try the worktree directory
name first, then fall back to the current branch name:

```sh
DENY='^(feat|fix|chore|refactor|docs|test|hotfix|release|wip|perf|build|ci|style|v|part|step|pr|review|backup|bugfix|day|demo|draft|new|old|phase|poc|revert|spike|sprint|sync|task|temp|tmp|update|week)$'

_ref_from_segment() {
  seg=$1
  case "$seg" in
    *-*) : ;;
    *) return 1 ;;
  esac
  prefix=${seg%%-*}
  rest=${seg#*-}
  case "$rest" in
    *-*) num=${rest%%-*} ;;
    *)   num=$rest ;;
  esac
  lc_prefix=$(printf '%s' "$prefix" | tr 'A-Z' 'a-z')
  case "$lc_prefix" in
    issue|issues)
      case "$num" in
        ''|*[!0-9]*) return 1 ;;
      esac
      printf '#%s\n' "$num"
      return 0
      ;;
  esac
  case "$prefix" in
    *[!A-Za-z]*) return 1 ;;
  esac
  [ "${#prefix}" -ge 2 ] || return 1
  case "$num" in
    ''|*[!0-9]*) return 1 ;;
  esac
  if printf '%s\n' "$lc_prefix" | grep -Eq "$DENY"; then
    return 1
  fi
  uc_prefix=$(printf '%s' "$prefix" | tr 'a-z' 'A-Z')
  printf '%s-%s\n' "$uc_prefix" "$num"
  return 0
}

detect_ref() {
  str=$1; pat=${2:-}
  result=$(printf '%s\n' "$str" | tr '/' '\n' | while IFS= read -r seg; do
    if ref=$(_ref_from_segment "$seg") && [ -n "$ref" ]; then
      if [ -n "$pat" ]; then
        printf '%s\n' "$ref" | grep -Eq "$pat" || continue
      fi
      printf '%s\n' "$ref"
      break
    fi
  done)
  [ -n "$result" ] && { printf '%s\n' "$result"; return 0; }
  return 1
}

REF=$(detect_ref "$(basename "$(pwd)")") || REF=$(detect_ref "$(git branch --show-current 2>/dev/null)")
```

Copied verbatim from `juel:start` (the same copy `juel:compact-context` and `juel:cmux-review-pr`
also carry) rather than referenced by name — `references/*.md` are never read at runtime, so a
skill that only *names* `detect_ref` is pointing at logic the agent executing it would never load.

**"No ref" is a valid outcome, not an error.** If `detect_ref` finds nothing in either the
worktree dirname or the branch name, `ref` is simply absent — proceed to resolve criteria from the
spec file or by asking, per the precedence below; never block this skill on a missing ref.

**Resolve the criteria to verify, in order:**
1. Explicit list passed as an argument.
2. The work item's `acceptance_criteria` (per `references/work-source.md`'s work-item interface — fetched via the `ref` resolved above).
3. The verification steps recorded in the spec under `${docsRoot}/specs/` (`juel:ship-ticket` Phase 2 records these when a work item has no AC of its own).
4. Ask the user for concrete verification steps.

**An empty criteria list is never a legitimate outcome — STOP here and ask.** This mirrors the guard `juel:ship-ticket` Phase 7 already enforces: a zero-item checklist must never be allowed to read as "verified," and this skill must never silently emit an empty report instead of stopping to ask.

**Checkpoint:** show the resolved URL and the numbered criteria list. Confirm before opening the browser.

### Phase 2 — Launch the browser and reach the entry point

Use the Playwright MCP tools to navigate to the resolved URL. Capture a screenshot of the initial load as the baseline — this is evidence the app was actually reached, not assumed reachable.

If the app does not respond (connection refused, timeout, DNS failure, a blank/error page that isn't the app), **STOP and report the exact URL tried.** Do not fabricate a result, and do not retry against a guessed alternate port or protocol.

**Checkpoint:** show the baseline screenshot path and the URL that loaded. Confirm before driving criteria.

### Phase 3 — Drive each criterion

For each criterion, in order: perform the interaction it describes, capture a screenshot once the interaction settles, and record what was actually observed — the DOM text present, the element's visible state, the network request that fired — never what was merely expected.

If a criterion cannot be driven in a browser at all (it describes backend-only behavior, a cron job, an email, a database row, anything outside the DOM/network surface Playwright can observe), do not attempt to fake or infer it here — leave it for Phase 4 to mark `unverifiable` with the reason.

**Checkpoint:** show the count of criteria driven and the screenshot paths captured so far.

### Phase 4 — Map every criterion to an observed result

Every criterion resolved in Phase 1 gets **exactly one** of three outcomes — never zero, never more than one:

- **pass** — the observed behavior from Phase 3 matches the criterion.
- **fail** — the observed behavior contradicts the criterion. State what was expected and what was actually observed.
- **unverifiable** — the criterion could not be driven in a browser, or the run hit an obstacle this session cannot clear (an auth wall, missing seed data, an environment this browser session cannot reach). **The reason is always stated alongside it.**

**"Unverifiable" is a legitimate third outcome, not a failure of this skill or something to route around.** A criterion that lands here still appears in the final report with its reason — it is never quietly omitted from the checklist, and it is never upgraded to `pass` because driving it failed for a reason unrelated to whether the app is actually correct. Guessing a result for a criterion that was never actually exercised is the one mistake this whole skill exists to prevent.

**Checkpoint:** show the full criterion → result table before writing the report.

### Phase 5 — Report the evidence

Write the report to `${docsRoot}/findings/{YYYY-MM-DD}[-{ref-lower}]-regression.md` — the ref segment included, lower-cased, only when a work item ref was resolved; dropped entirely when there is none, never a placeholder like `none` or `noref` (same ref-optional naming every other skill in this plugin uses). If the target filename already exists, bump to `-v2`, then `-v3`, and so on — never overwrite a prior run's report.

```markdown
# Regression report — {topic} ({YYYY-MM-DD})

**Ticket:** {ref or "none"}
**URL verified:** {resolved URL}

## Criteria → Result

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | {criterion text} | pass / fail / unverifiable | {screenshot path, or the unverifiable reason} |

## Observed vs. assumed

{What was actually driven and observed in the browser this run — vs. anything inferred, assumed, or never exercised. These two categories are never blended into one undifferentiated "verified" claim.}

## Screenshots

- `{path}` — {what it shows}
```

Report the written path and a one-line tally (`N pass / M fail / K unverifiable`) to whoever invoked this skill — the user directly, or `juel:ship-ticket` Phase 7 — before marking this phase done.

**Checkpoint:** show the report path and the tally. Done.

## Edge cases

| Situation | Action |
|---|---|
| Playwright tools unavailable | STOP. "Playwright MCP is not connected. It ships as a dependency of this plugin — restart the session so the connector binds, then re-run." Do not retry. |
| App not reachable at the URL | STOP and report the URL tried. Do not fabricate a result. |
| A criterion cannot be driven in a browser | Mark it `unverifiable` with the reason. Never mark it passed. |
| Criteria list resolves empty | STOP in Phase 1 and ask the user for concrete verification steps — never emit an empty checklist. |
| `commands.run` resolves to `null` and no explicit URL was given | Ask the user where the app is running; do not guess a port or protocol. |
| Work item has no ref and no spec file exists | Ask for criteria directly (Phase 1's last precedence step) rather than aborting the skill. |
| Screenshot capture fails mid-criterion | Record the result from whatever other Playwright signal is available (DOM text, network response); if none is available, mark `unverifiable` — a missing screenshot is not license to guess the result. |

## Output

- **Format:** Markdown, with screenshots referenced by path
- **Location:** `${docsRoot}/findings/`
- **File naming:** `{YYYY-MM-DD}[-{ref-lower}]-regression.md`, `-v2`/`-v3` suffix on collision, ref segment dropped entirely when there is no ref

## Common mistakes

| Mistake | Fix |
|---|---|
| Marking an untestable criterion "pass" to keep the report clean | Never. Use `unverifiable` with the reason — an honest gap beats a report that reads as verified when it wasn't. |
| Silently dropping a criterion that was hard to drive | Every resolved criterion appears in the final report exactly once, with one of the three outcomes. |
| Re-deriving `commands.run` when `juel:ship-ticket` already resolved it this session | Reuse the already-reported value from `juel:ship-ticket` Phase 4 — do not re-run the tiered probe. |
| Treating an empty criteria list as "nothing to verify, so pass" | STOP and ask instead — an empty checklist is never a pass (Phase 1 guard). |
| Backgrounding the browser session, or redirecting its output to a file | Everything in this skill runs in the foreground — see protocol rule 4. |
