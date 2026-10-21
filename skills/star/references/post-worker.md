# Post worker mode: `post-report`

Read this when you are a post worker (your prompt is `/juel:star post-report …`). Nothing else in SKILL.md
applies to a worker in this mode except the Strict Execution Protocol.

`/juel:star post-report <ref> --item <name> --report <path>` runs in the project's main checkout as an Orca
worker, after a report item's build wrote its report. It never edits the repository and never changes the work
item's status (STAR does that). It is unattended: nobody is at its terminal, so it never asks there.

The owner handed STAR the ticket, so posting the report to it is STAR's own ask and needs no confirmation. The
report goes to that ticket and nowhere else.

1. Resolve the work source as `references/brief-worker.md` steps 2 and 3 do.
2. Look at the work item's latest comments. One that already starts with the report's first line is this report,
   posted by an earlier post worker that was lost: report `POSTED` with its URL and post nothing.
3. Post the report file as one comment:

| Provider | Post |
|---|---|
| `linear` | the Linear MCP's comment tool, `<LINEAR_PREFIX>save_comment` or `<LINEAR_PREFIX>create_comment`, whichever that prefix has, with `(issueId: <id>, body: <the report file's text>)`. The prefix is the first loaded of `mcp__linear__`, `mcp__plugin_linear_linear__` or `mcp__claude_ai_Linear__`, as `references/work-source.md` resolves it |
| `github` | `gh issue comment <n> --body-file <path>` |
| `jira` | the connected Jira or Atlassian MCP's add-comment tool |
| `mcp:<type>` | `<TRACKER_PREFIX>add_comment` on the item, with the report file's text as its body (resolve `TRACKER_PREFIX` as `references/brief-worker.md` does; no such tool is a failed post) |
| `file` | nothing to post: add `report: <path>` to the spec file's frontmatter |

Report, as the `worker_done` body and nothing else (it overrides any request for a prose summary, Orca's worker
preamble included): `POSTED item=<name> url=<comment url, or the spec path>`, then `SENT report posted to <ref>`.
A post that fails reports `ESCALATION item=<name> phase=0 reason=out-of-tries step=gh`, with what the tracker
said as the line after it. STAR spends a try and starts a new post worker; the check for an earlier comment in
step 2 makes that safe.
