# Local end-to-end rules

Read at runtime by `juel:ship-ticket` (Phase 6) and `juel:verify` (Step 3). This file is the
single source of truth for how an end-to-end run sets up, isolates, touches remote data, captures
screenshots, and stores evidence. The skills name the five rules; the details live here.

## 1. Local, running stack, always

- Every checklist item is verified against a stack started from **this worktree**. A deployed
  environment is never a substitute for the local run.
- Tests, typecheck and build are the regression gate. They are never the verification.
- Before starting the stack, check resources: free memory (`vm_stat` on macOS, `free -h` on Linux)
  and the heaviest processes machine-wide (`ps -Ao pid,rss,command | sort -k2 -rn | head -20`).
  If another heavy run is active or memory is tight, say so and wait, or start only the services
  the checklist needs.

## 2. Port and container isolation

Other worktrees run their own stacks on this machine. This run must never block them, and must
never be blocked by them.

- **Never stop, kill, or reuse a process or container this run did not start.** A port held by
  something else means "pick another port", not "tear it down".
- For each port the stack binds, check it: `lsof -nP -iTCP:<port> -sTCP:LISTEN`. If taken,
  increment until free. Pass the chosen port through the repo's own mechanism: an env var, an
  untracked `.env.local`, a compose override file, or a CLI flag.
- Update every dependent URL to match: frontend-to-backend base URL, CORS origins, OAuth or
  webhook callback URLs, anything the diff's flow calls.
- Run Docker Compose with `COMPOSE_PROJECT_NAME=<worktree-basename>` so containers, networks and
  volumes never collide with another worktree's stack.
- Any file written only to redirect ports must be untracked or gitignored, and is removed at
  teardown.
- Record the final port map (service to port) in the evidence report.
- Teardown stops only what this run started.

## 3. Remote data

The owner pre-authorizes remote data access for local runs. No need to ask.

- **Reading** remote data (staging or dev databases, APIs) to seed or drive the local stack is
  allowed.
- **Writing** to remote is allowed only when a checklist item cannot be reproduced with local
  data, and only under these conditions:
  - Before each write, append an entry to `cleanup.md` in the evidence directory: what was
    created or changed, where, its identifier, and the exact command that reverses it.
  - Tag created records with a recognizable marker, `e2e-<ref>-<timestamp>`, wherever the data
    model allows.
  - Never trigger outbound side effects on real people: no emails, SMS, push notifications,
    payments, or third-party webhooks.
  - Never modify or delete a record this run did not create.
- Cleanup runs at the end of the run whatever the verdict, including FAIL and BLOCKED. Reverse
  each ledger entry, confirm it is gone by reading it back, and mark it done in `cleanup.md`.
- Delete local copies of remote data (dumps, exports) at teardown.
- **The run cannot be reported complete with an open ledger entry.** A failed cleanup is reported
  first and loudly, with the exact leftover identifiers and where they live.

## 4. Screenshots for frontend changes

- Any diff touching UI (components, styles, templates, client routes) needs a Playwright
  screenshot of every changed screen or state.
- Default: light mode (`browser_emulate_media` with `colorScheme: 'light'`), desktop viewport
  1440x900 (`browser_resize`), full page. Dark mode, mobile, or before/after pairs only when the
  owner explicitly asks.
- Save to `screenshots/<NN>-<checklist-item-slug>.png` in the evidence directory, and reference
  each one from the report next to the checklist item it proves.

## 5. Evidence directory

- Path: `${docsRoot}/evidence/<YYYY-MM-DD>[-<ref-lower>]-<slug>/`, with `docsRoot` resolved the
  same way as every other juel skill. The ref segment is included only when the work item has one.
- Never overwrite an existing evidence directory. On a collision, use `-v2`, then `-v3`, and so on.
- Ensure the repo's `.gitignore` has unanchored `superpowers/` and `.superpowers/` entries, as the
  other docsRoot writers do.
- Contents:
  - `report.md`: the per-item checklist (method, evidence, PASS/FAIL), the port map, and notes
    on any remote data used.
  - `screenshots/`: per rule 4.
  - `cleanup.md`: only when remote writes happened, per rule 3.
  - Captured responses and logs, when an item's evidence is too long to inline in the report.
- When `juel:verify` runs inside `juel:ship-ticket`, it writes into ship-ticket's evidence
  directory instead of creating its own.
- The final message of the run ends with the absolute path of the evidence directory.
