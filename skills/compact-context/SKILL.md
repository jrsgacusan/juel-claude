---
name: compact-context
description: Use to snapshot the current conversation into a compaction-style summary Markdown file under docs/.superpowers/context/, so context survives a /compact or a fresh session. Triggers - "compact the context", "save this conversation", "snapshot context", "dump session to a file".
---

# Compact Context

Produce a compaction-quality summary of the **entire conversation so far** and write it to a Markdown file under `docs/.superpowers/context/` in the current project.

**Announce at start:** "Using juel:compact-context to snapshot this conversation to docs/.superpowers/context/."

## Why this exists

`/compact` replaces the live context with a summary and returns nothing an agent can capture. So a skill cannot invoke `/compact` and grab its output. Instead this skill makes Claude generate the same kind of summary `/compact` would, then persists it to disk. The saved file is what survives an actual `/compact`, a `/clear`, or a new session, ready to be re-read to restore context.

## Workflow

### Step 1: Resolve the output directory

Find the project root and target dir:

```bash
ROOT=$(git rev-parse --show-toplevel)
mkdir -p "$ROOT/docs/.superpowers/context"
```

All output goes to `$ROOT/docs/.superpowers/context/`. Never write elsewhere.

### Step 2: Derive the filename

Pattern: `{YYYY-MM-DD}-{ticket-slug}-{topic-slug}-session.md`

- `{YYYY-MM-DD}` - today's date.
- `{ticket-slug}` - lowercase ticket id from the branch / worktree if there is one (e.g. `savi-1346`). Get it from `git rev-parse --abbrev-ref HEAD`. If no ticket, drop this segment.
- `{topic-slug}` - 2-4 word kebab-case summary of what the conversation is about (e.g. `shelf-schema`).

**Versioning on collision.** If the derived filename already exists in the dir, append `-v2` before `.md`. If `-v2` exists too, use `-v3`, and so on. Never overwrite an existing file.

```bash
BASE="2026-07-02-savi-1346-shelf-schema-session"   # example
DIR="$ROOT/docs/.superpowers/context"
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
- **Location:** `<project-root>/docs/.superpowers/context/`

## QA checklist

- [ ] Output dir resolved from `git rev-parse --show-toplevel`, not hardcoded
- [ ] Filename matches the date-ticket-topic-session pattern
- [ ] Existing file NOT overwritten - `-vN` suffix used on collision
- [ ] Summary covers the entire conversation, not just recent turns
- [ ] Only the one Markdown file was written; no code changed
