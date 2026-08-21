---
name: start
description: Use when beginning work on a ticket inside a worktree - detects the work-item reference from the worktree or branch (or offers the no-ref options), fetches it from the resolved work source, analyzes requirements, then brainstorms implementation
metadata:
  requires:
    mcp:
      - id: linear
        hard: false
        why: phase 2 fetches the work item via the resolved work-source's get_issue, when a ref was detected and no local spec/inline path was chosen
        check: none
        fallback: resolve the work item from a spec file or inline conversation
    context:
      - id: git-repo
        hard: true
        why: phase 1 detects the work-item reference from the worktree directory name and the branch name
        check: "git rev-parse --show-toplevel"
    skills:
      - id: superpowers:brainstorming
        hard: true
        why: phase 4 explores the implementation approach before writing code
---

# Start Ticket Work

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v5 -->

**1. Preflight, then task list, before anything else.** Before any other output and before any tool call, emit the Preflight block (below). If the preflight verdict is STOP, print the preflight block and **stop** — do not create tasks and do not begin work. Otherwise, before any other work, create one task per phase in this skill's `## Phases` list via `TaskCreate` — `subject` is the phase name, `activeForm` is its present-continuous form. This task list, rendered persistently by the harness, IS the checklist; nothing else satisfies this rule. This is not optional on re-invocation, on resume, or when the user says "just do it".

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
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP → run from inside a repo |
| Linear MCP (`get_issue`) | mcp | SOFT | **none — render as `?`** | resolve the work item from a spec file or inline conversation |
| superpowers:brainstorming | skill | HARD | ships as a plugin dependency | STOP → `/plugin install superpowers@claude-plugins-official` |

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Detect the work-item reference (worktree, then branch)
2. Fetch the work item from the resolved source
3. Analyze requirements and present the summary
4. Brainstorm via superpowers:brainstorming

## Overview

Automates the "start working on a ticket" workflow: detect the work-item reference (worktree, then branch, or the four-option no-ref path if neither yields one), fetch it from the resolved work source, analyze requirements, brainstorm.

## Workflow

### Step 1: Detect the Work-Item Reference

Run `detect_ref` — anchored to whole `/`-delimited path segments, with a denylist of generic
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

If `config.tracker.refPattern` is set, pass it as `detect_ref`'s second argument — an *additional*
intersecting filter, never a substitute for the generic rule — to narrow matches to a known
tenant's prefix.

**"No ref" is a valid outcome, not an error.** If `detect_ref` finds nothing in either the worktree
name or the branch name, do **not** demand a ticket id. In order:
1. If the resolved provider supports `list`, offer the open items to pick from.
2. If a spec directory is configured, offer the local spec files.
3. Otherwise ask, with these options:
   - "Pick from my open items" (only when `list` is available)
   - "Point me at a requirements file"
   - "I'll paste the requirements here" → inline, then auto-promote to a spec file
   - "No ticket — just brainstorm with me"

Never block.

### Step 2: Fetch the Work Item

If a ref was detected, or the user picked "Pick from my open items" / "Point me at a requirements
file" in Step 1, fetch it through the work-source abstraction — never a hardcoded Linear call.

For a tracker ref (e.g. `SAVI-855`), resolve the Linear MCP prefix first. **Both prefixes are
real, and the active one depends on which Linear connector the user authenticated** — accept
either `mcp__linear__` (the plugin dependency) or `mcp__claude_ai_Linear__` (the claude.ai
connector). Use whichever prefix exposes a *domain* tool — anything other than
`authenticate`/`complete_authentication`, since the plugin connector can be installed but not yet
authorized, which is not the same as usable:

```
fetch(ref) → <LINEAR_PREFIX>get_issue(id: ref)
```

The verb is **`get_issue`** — not `fetch_issue`, not `get_ticket`.

If neither prefix exposes a domain tool, **STOP**: "Linear MCP is not connected. Enable the
connector, restart this session (connectors bind at startup), then re-run." Do not retry. Do not
fall back to `gh` or the web.

If a spec file was pointed at, or requirements were pasted inline (Step 1 auto-promotes inline
text to a spec file, so this and later steps read one consistent source), read that file directly
instead of calling `get_issue`.

If "No ticket — just brainstorm with me" was chosen, skip this step entirely — Step 3 works from
the conversation itself.

### Step 3: Analyze Requirements

Read the work item's description — from the fetched Linear issue, the spec file, or the inline
conversation — and extract:
- **Type**: Feature, Enhancement, Bug fix, etc.
- **Context**: Why this work is needed
- **Requirements**: What needs to be built (bullet points)
- **Acceptance Criteria**: Definition of done
- **Dependencies**: Other tickets this depends on
- **API endpoints**: Any backend APIs to integrate with

Present a concise summary to the user.

### Step 4: Brainstorm

Invoke `superpowers:brainstorming` to explore implementation approach before writing code.

## Edge Cases

| Situation | Action |
|-----------|--------|
| No ref detected (neither worktree name nor branch) | Offer the four options from Step 1 — never error, never block |
| Work item not found in `<source>` | Report error, ask user to verify |
| Work item has no description | Warn user, proceed with title only |
| Provider unavailable | Fall back per config, warn once |
| Linear tool unavailable | STOP. "Linear MCP is not connected. Enable the connector, restart this session (connectors bind at startup), then re-run." Do not retry; do not fall back to `gh` or the web. |
