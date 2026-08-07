---
name: compact-context
description: Use to snapshot the current conversation into a compaction-style summary Markdown file under the resolved docsRoot's context/ directory, so context survives a /compact or a fresh session. Triggers - "compact the context", "save this conversation", "snapshot context", "dump session to a file".
metadata:
  requires:
    cli:
      - id: git
        hard: true
        why: resolves the project root for the output directory
        check: "command -v git"
    context:
      - id: git-repo
        hard: true
        why: output path is under the resolved docsRoot, rooted at <repo-root>
        check: "git rev-parse --show-toplevel"
---

# Compact Context

Produce a compaction-quality summary of the **entire conversation so far** and write it to a Markdown file under `${docsRoot}/context/` in the current project.

**Announce at start:** "Using juel:compact-context to snapshot this conversation to ${docsRoot}/context/."

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v4 -->

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

## Preflight

Run these as one batched Bash call, then render per the format below.

| Dep | Type | H/S | Check | If missing |
|---|---|---|---|---|
| git | cli | HARD | `command -v git` | STOP → install git |
| git repo | context | HARD | `git rev-parse --show-toplevel` | STOP → run from inside a repo |

All satisfied renders as: `Preflight: 2/2 OK (git, git repo)` / `→ PROCEED: all requirements met.`

## Phases

This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.

1. Resolve the output directory (docsRoot)
2. Derive the filename, bumping to -vN on collision
3. Write the summary covering the entire conversation
4. Confirm — report the path and a one-line summary
5. Verify the QA checklist

## Why this exists

`/compact` replaces the live context with a summary and returns nothing an agent can capture. So a skill cannot invoke `/compact` and grab its output. Instead this skill makes Claude generate the same kind of summary `/compact` would, then persists it to disk. The saved file is what survives an actual `/compact`, a `/clear`, or a new session, ready to be re-read to restore context.

## Workflow

### Step 1: Resolve the output directory

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
mkdir -p "$docsRoot/context"
```

(If `.claude/workflow.json` or `.claude/workflow.local.json` sets `docsRoot`, that value wins over
the filesystem check above — config always takes precedence.)

Ensure the repo's `.gitignore` contains unanchored `superpowers/` and `.superpowers/` entries —
unanchored so they match at any depth. Add them if absent. This directory is scratch, not product.

**Never overwrite an existing file under `${docsRoot}`.** On a name collision — a spec, plan,
findings report, or context file that already exists at the derived path — append `-v2` before
the extension; if `-v2` exists too, use `-v3`, and so on. This applies to every file type written
under `${docsRoot}`, not only the one this skill produces.

All output goes to `$docsRoot/context/`. Never write elsewhere.

### Step 2: Derive the filename

Pattern: `{YYYY-MM-DD}-{ticket-slug}-{topic-slug}-session.md`

- `{YYYY-MM-DD}` - today's date.
- `{ticket-slug}` - lowercase ref detected via `detect_ref` — anchored to whole `/`-delimited
  segments with a denylist of generic branch-type words (never a loose substring match), the same
  shared helper `juel:start` inlines. Try the worktree directory name first, then the branch name:

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

  Lowercase `$REF` for the filename segment (e.g. `savi-1346`). **If no ticket, drop this
  segment** — never a placeholder like `none` or `noref`.
- `{topic-slug}` - 2-4 word kebab-case summary of what the conversation is about (e.g. `shelf-schema`).

**Versioning on collision.** If the derived filename already exists in the dir, append `-v2` before `.md`. If `-v2` exists too, use `-v3`, and so on. Never overwrite an existing file.

```bash
BASE="2026-07-02-savi-1346-shelf-schema-session"   # example
DIR="$docsRoot/context"
NAME="$BASE.md"
n=2
while [ -e "$DIR/$NAME" ]; do NAME="${BASE}-v${n}.md"; n=$((n+1)); done
echo "$DIR/$NAME"
```

### Step 3: Write the summary

Write the compaction summary to the resolved path using this structure. Cover the **whole** conversation, not just the last few turns. Be concrete - names, file paths, decisions, exact commands, open threads. This is meant to fully restore working context.

```markdown
# Context snapshot - {topic} ({YYYY-MM-DD})

**Ticket:** {ticket id or "none"}
**Branch:** {branch}
**Snapshot reason:** {compaction / handoff / end of session}

## Goal
{What the user is ultimately trying to achieve.}

## What happened
{Chronological narrative of the conversation - what was asked, explored, decided, built. Enough detail to reconstruct the thread.}

## Key decisions
- {decision + why}

## Files touched / relevant
- `path` - {what and why}

## Current state
{What is done, what works, what is verified.}

## Open threads / next steps
- {unfinished work, known issues, what to do next}

## Useful commands / references
- {exact commands run, ticket links, docs}
```

### Step 4: Confirm

Report the written path and a one-line summary of what was captured. Do not modify any code or other files.

## Output

- **Format:** Markdown
- **File naming:** `{YYYY-MM-DD}-{ticket-slug}-{topic-slug}-session.md`, `-v2`/`-v3` suffix on collision
- **Location:** `${docsRoot}/context/`

## QA checklist

- [ ] Output dir resolved via the `docsRoot` rule (config, then existing dotted dir, then canonical), not hardcoded to one variant
- [ ] Filename matches the date-ticket-topic-session pattern
- [ ] Existing file NOT overwritten - `-vN` suffix used on collision
- [ ] Summary covers the entire conversation, not just recent turns
- [ ] Only the one Markdown file was written; no code changed
