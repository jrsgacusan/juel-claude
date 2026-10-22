# Start, stop, recovery and edge cases

Read this at every start, on `stop`, after a compaction or a restart, and when something looks odd.

## Contents

- Start in detail
- Stop
- Recovery
- Edge cases

## Start in detail

`/juel:star` in a project whose folder already has rows is a resume; there is no separate command. **One STAR
per home**, and a home is one project's folder. "Coordinator, or hand-over" (SKILL.md) already decided that this
session is the coordinator: `star.json` named no terminal, or this one, or one `orca terminal list --limit 500
--json` no longer lists. Two coordinators would fill the same slot twice and overwrite each other's ledger.
Then claim the home: write this session's handle to `star.json` at once and read it back after the next
command. Another handle there means a second STAR started in the same moment: stop. "take over" from the owner
is the one way past a listed handle.

1. **Migrate:** `sh S/star-home.sh migrate`. `current` → nothing. `migrated schema=3 rows=<n> loops=<n>` → say it
   in one line. Print every `warn …` line as it is (for example `warn executor.fallback equals executor.model`:
   a fallback equal to the model counts as none, so at capacity the plan goes straight to the next option).
   Any other `migrated …` line goes into the status line in one line. For each `stop <dispatch>` line (a worker
   of a stage that no longer exists): append `<dispatch> stopped <iso>` to `processed.log`, then `orca
   orchestration worker-stop --dispatch <id> --json`, `worker-release` and `stage-start.sh close <dispatch>`, all
   before the reconcile. A non-zero exit stops the start: print its message, release the claim (`"terminal":
   null`), tell the owner the folder may be half moved and that `/juel:star` again retries, and end. Then `sh
   S/star-home.sh register` (`registered <home>` or `listed <home>`; a non-zero exit is one line in the status,
   never a stop). Give every open row with no `counters.batch` the batch `B-<this start's UTC time>-<4 hex>`.
2. **Look up what the project already says.** The hosted-reviewer lookup when `hostedReviewer` is null and the
   migrate changed rows. When `mergeMethod` or `baseBranch` is null, look for a rule in the project's
   `CLAUDE.md` and `AGENTS.md` and in STAR's rule notes; set the key and say so in one line. Print one line when
   those instructions say the hosted reviewer is paused while `hostedReviewer.paused` is false (#169). The
   details are in `references/state.md`.
3. **Bind the run:** `orca orchestration run-use --id <run from star.json> --json`; when it no longer exists,
   `orca orchestration run-create --objective "STAR" --json`. Record the run id and `$ORCA_TERMINAL_HANDLE`
   in `star.json`, the Preflight's Mobbin and Context7 states as `"mcps": {"mobbin": "<state>", "context7":
   "<state>"}` (every start writes them again, so a sign-in made between runs shows), and STAR's own `gh` login
   as `ghLogin` (`gh api user --jq .login`; no line leaves it as it was and says so).
4. **caffeinate:** when `star.json` has a pid and `ps -p <pid> -o comm=` prints `caffeinate`, kill it. Start
   `caffeinate -dimsu >/dev/null 2>&1 &` and record its pid. It deliberately outlives a closed session.
5. **Heartbeat:** load the scheduler (`ToolSearch("select:CronCreate,CronDelete")`), delete the job id in
   `star.json` if any, and create a recurring job `7,37 * * * *` with the prompt `STAR heartbeat: if you are
   not already in a tick, run one.` Record its id and, as `heartbeatAt`, the time. Jobs fire only while the
   session is idle and die with it, so every start registers a fresh one; a job also expires after 7 days, so
   any tick that finds `heartbeatAt` 6 or more days old registers a new one. No scheduler tool → say so: an idle
   STAR then wakes only on a nudge or the owner.
6. **Reconcile** every row in a worker stage, except a `building` row whose `verify` holds `retry=`, with
   `worker-probe.sh` as "Watching a running worker" in `references/stages.md` says. A row in a worker stage with
   no task never started (STAR stopped between writing the row and `task-create`), and a row with a task but no
   dispatch never got its worker: put either back in its stage's waiting state, no try spent; the next
   `stage-start.sh` replays the same request ids, and Orca hands back the task or dispatch it already made. A
   `verifying` row has no worker: run its gate only when its `verify` is `-` or its `retry=` time has passed.
   A `building` row with a `retry=` has reported: once the time has passed run `done-check.sh` for it.
7. **Look for a background wait left by a session that died:** `sh S/messages.sh --home HOME_DIR --waiting`; on
   `waiting <pid> <since>`, `kill <pid>`. Killing it is always safe: the next tick starts a fresh one. Then
   `loops.sh resume --state running --run <id> --pools "…" --next "<one line>"`, and `sh S/chat.sh --home HOME_DIR
   pending`: answer each pending chat message whose inbox file is gone, once, as `references/dashboard.md` says.
   Then tick.

## Stop

`/juel:star stop`, the owner says stop, or a `control: stop` file. Finish the current tick, kill the background
wait (`messages.sh --waiting`, `kill <pid>`), kill the recorded caffeinate (only when `ps -p <pid> -o comm=` still
prints `caffeinate`), delete the heartbeat, run `loops.sh resume --state stopped --next "run /juel:star to
resume"`, set `"terminal": null` in `star.json` (the claim is released, so the session hook goes quiet and the
next `/juel:star` becomes the coordinator) and print the queue. Workers still running are left alone; their
reports wait in the Orca run. When any `queued` row exists, the printed queue starts with `Stopping leaves <n>
items unbuilt until /juel:star runs again: <items>`.

## Recovery

- **Compaction.** The plugin's session hook tells the session that owns STAR for this project (the terminal
  named in `star.json`) that it is the coordinator and to run `/juel:star` if it is not in a tick. Other
  sessions in the repository hear nothing. The hook also lists the notes every worker reads. The Resume block at
  the top of `open-loops.md` holds the run, the pools and the next step. Nothing is needed from the owner.
- **A closed session.** Workers keep running and their reports wait in the Orca run. The owner runs `/juel:star`
  in the project again from any Orca terminal: the old terminal is no longer listed, so the new session takes
  over.
- **An Orca restart.** Every worker is gone. The reconcile step treats each as a lost worker: one try, and the
  stage runs again.
- **A stop in the middle of a tick.** Nothing is lost and nothing runs twice. A message not yet in
  `processed.log` is replayed into the same end state (the order of effects in `references/tick.md`); a row
  written before its `task-create` goes back to its waiting state; an inbox file read twice adds no row.
- **The background message wait** belongs to the session that started it, and only that session hears its
  notification. After a compaction, `messages.sh --waiting` says whether it is still alive: no second wait
  starts, and its notification still comes. After a restart the old session's wait does not end by itself (the
  Bash tool's shell wrapper outlives a killed Claude), so the start and Stop kill it. A wait that died without a
  notification reads as `none`: the next tick starts a new one.
- **Chat.** A chat message is answered once: the Inbox step checks `chat.sh pending`, `chat.sh reply` refuses a
  second reply, and every start answers each pending message whose inbox file is gone.
- **An older STAR folder.** The start's first step, `star-home.sh migrate`, brings it to the current schema.
  Grant files and old counters stay on disk, unread; nothing is deleted. The notes mode is left as it is.
  A schema-3 home may delete an old `grants/` folder and the `grant` line in a brief's frontmatter: nothing reads them.
  Standing orders saved in `star.json` as free-text keys are not reread as rules: STAR reads its rules from
  notes and the project's instructions only, and a standing order the owner still wants comes back as a rule
  note (`notes.sh add --kind rule --source owner`).

## Edge cases

| Situation | Handling |
|---|---|
| Refs given while STAR is stopped | The invoking session becomes the coordinator and ingests them |
| The same ref given twice | One row. The second time changes nothing |
| The owner merges or closes a PR before STAR merged it | The PR check before "Fill slots" sees it in every state that has a PR: merged → release record and `done`; closed → `set-aside` |
| The owner says "drop" while the item's worker runs | The worker is stopped and released first, then the row `dropped` |
| The owner changes a brief while a worker builds it | `references/dashboard.md`, "Feedback on a brief" |
| A second `/juel:star` in another terminal | It hands its refs to the running STAR and ends; never a second coordinator |
| `loops.sh` exits 3 (conflict markers in `open-loops.md`) | Stop writing the queue, say so in the status line, keep workers running |
| The project is not registered with Orca | The status line says `orca repo add`; inbox files wait until it is |
| The drafter failed or timed out on a Slack message | Its draft holds only the `to:` line: the item says `no draft: <why>` and offers `rewrite: <how>` or `skip`; a `send` is refused |
| `codex` is missing | STAR does not start (Preflight) |
| A stage's model is refused at launch | The stage falls back to `worker` once and the status line says which model ran |
| `/juel:star` typed in a linked worktree or a subfolder | The same folder as the main checkout: one STAR per project |
| `/juel:star` typed outside a git repository | One line: STAR needs a project repository. Nothing is created |
| The tracker cannot be reached | The write fails, `counters.tracker=!<status>`, the status line names it; no question |
| A finding that is already an open issue | `star-issue.sh comment` adds the new evidence to it |
| The STAR folder was deleted | That project's state is gone; the next `/juel:star` starts fresh. Stop STAR first: workers still running would report to nobody |
| Two projects each run a STAR | Each has its own queue and slots; the gate lock and the host gate are shared by the machine |
| A check turns out to need a person in the middle of a build | The build reports `ESCALATION … reason=needs-person`: the row waits in `needs-you` for that item only |
| An Orca nudge whose batch holds only heartbeats | `messages.sh` acknowledges it; nothing happens |
| The base moves under a gate loop | The round prints `ERROR base-moved`: the worker merges the base in and runs the same round again; STAR does nothing |
| The review gate is down on every model | STAR parks each build and babysit that reports it, starts no new ones, and checks the gate every 30 minutes until it is back; nobody is asked |
| Two items that each add a decision to the same register | Each worker reserves its ids through `ids.sh`, so siblings never take the same number |
| A project with no hosted reviewer | The merge gate needs green CI and a codex PASS, and an approval only when the base branch's protection requires one |
| An older STAR folder, v1 | The first start migrates it and stops the workers of the removed stages |
