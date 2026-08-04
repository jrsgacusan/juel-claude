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
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP → run from inside a repo |
| Linear MCP (`get_issue`) | mcp | SOFT | **none — render as `?`** | resolve the work item from a spec file or inline conversation |
| superpowers:brainstorming | skill | HARD | ships as a plugin dependency | STOP → `/plugin install superpowers@claude-plugins-official` |

## Phases

[ ] 1. Detect the work-item reference (worktree, then branch)
[ ] 2. Fetch the work item from the resolved source
[ ] 3. Analyze requirements and present the summary
[ ] 4. Brainstorm via superpowers:brainstorming

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
