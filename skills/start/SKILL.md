---
name: start
description: Use when beginning work on a ticket inside a worktree - detects ticket ID from directory, fetches Linear ticket, analyzes requirements, then brainstorms implementation
---

# Start Ticket Work

## Overview

Automates the "start working on a ticket" workflow: detect ticket from worktree, fetch from Linear, analyze requirements, brainstorm.

## Workflow

### Step 1: Detect Ticket ID

Extract the ticket ID from the current working directory:

```bash
basename "$(pwd)"
```

Expected format: `savi-XXX` (from `.worktrees/savi-XXX`).

If the directory doesn't match a ticket pattern, ask the user for the ticket ID.

### Step 2: Fetch Linear Ticket

Convert directory name to Linear identifier (e.g., `savi-855` -> `SAVI-855`).

Fetch full ticket details:
```
linear__get_issue(id: "SAVI-XXX")
```

### Step 3: Analyze Requirements

Read the ticket description and extract:
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
| Not in a worktree directory | Ask user for ticket ID |
| Linear ticket not found | Report error, ask user to verify |
| Ticket has no description | Warn user, proceed with title only |
