# The dashboard, the chat, hand-overs, Slack, drafts and being away

Read this when the owner talks to STAR (chat, the terminal, another session), when a batch finishes drafting,
when a Slack message arrives, and for `away` and `back`.

## Contents

- The dashboard
- Hand-over and inbox files
- Chat
- Feedback on a brief
- The batch digest
- Drafts and Slack
- Away and back

## The dashboard

`sh S/dashboard.sh` (or `--tailnet`) builds the dashboard's web app when it is missing or older than its
sources (after checking free memory), starts the one dashboard server on this Mac when it is not running (on
127.0.0.1 only; its port and token are in `~/.juel/dashboard.json`), prints `STAR dashboard: <url>`, then
`STAR dashboard on your tailnet: <https url>` when `tailscale serve` maps its port, and opens it. Print those
lines. It needs no STAR running, does not become the coordinator and writes nothing in the STAR folder. The
page lists every project in `~/.juel/star-homes.json`, shows one combined Needs you across them, records
answers with `loops.sh set-answer` and wakes STAR with `orca terminal send --terminal <handle> --text inbox
--enter`. It also has a Chat page per project, an away switch that writes the same control files as `away` and
`back`, and an Accounts page, read-only.

`--tailnet` runs `tailscale serve --bg <port>` once Tailscale is running and nothing else serves `/` over HTTPS
there, never `tailscale funnel`, so the server stays on 127.0.0.1 and the token in the link is its only key
(#152). It prints the tailnet line, or one `dashboard.sh:` line saying why it could not (Tailscale missing or
stopped, `/` already serving something else, left as it is, or Serve not enabled on the tailnet). A server
another checkout started is stopped and replaced by this one's, on the same port and token. A non-zero exit:
print its last line, nothing else.

## Hand-over and inbox files

A `/juel:star` typed in a second terminal of a project that already has a live STAR hands over: it writes an
inbox file, nudges STAR with `orca terminal send --terminal <handle> --text "inbox" --enter`, says "STAR for
<project> runs in <handle>; I handed it <refs, or the text's first words>", and ends. With no refs and no text
it says where STAR runs and prints `status`. The terminal list cannot be read → write the inbox file, say that
it could not be checked whether STAR runs, and end: never become a second coordinator on a guess. A message to
STAR that says only `inbox` means "run a tick now".

An inbox file is `HOME_DIR/inbox/<UTC YYYYMMDDTHHMMSSZ>-<4 random hex>.md` (never overwrite one; pick another
suffix):

```
repo: <project.repo from HOME_DIR/star.json>
refs:
- <ref or absolute spec path>
text: |
  <the free-text brief, word for word, every line indented two spaces; omit when there is none>
note: <anything the owner said about the refs, one line; omit when nothing>
```

A control command from another session is a file `HOME_DIR/inbox/<UTC timestamp>-control-<4 random hex>.md` with
the single line `control: away`, `control: back` or `control: stop`, followed by the same nudge. A stop or an
"I'm leaving" said in chat is written down at once the same way, before the tick goes on, so a compaction in the
middle of a tick cannot lose it. Whoever carries a control file out deletes it in the same step. A start deletes
every `control: stop` file it finds: a stop older than this start has already happened.

A `slack:` block in an inbox file is a Slack message the dashboard's watcher routed here:

```
slack:
  id: <channelId>-<ts>
  channel: <#name, or "a DM">
  channelId: <id>
  ts: <ts>
  threadTs: <ts, or ->
  from: <display name>
  permalink: <url>
  draft: <absolute draft path>
  drafterError: <one line why, only when the drafter failed>
  text: |
    <the message, every line indented four spaces>
  thread: |
    <at most 5 earlier thread lines, "name: text">
```

## Chat

A file with a `chat:` line is the owner talking to STAR from the dashboard, the same as words typed into this
terminal. Its `text:` block is the message, never a free-text brief. After the `repo:` check run `sh S/chat.sh
--home HOME_DIR pending`; when the file's `chat:` id is not among the ids it prints, it was already answered
(STAR stopped between its reply and the delete): delete the file and do nothing else. Otherwise answer it as
yourself, with your own judgement, acting only through rules this skill already has: an answer is recorded with
`loops.sh set-answer` and run at once (Answers step), refs and work it hands STAR become rows as a hand-over's
do (`counters.batch=B-<the file's name without .md>`), feedback on a brief is handled below, and `stop`, `away`
and `back` run as the commands they are. Chat gives STAR no new powers: something no rule covers gets a reply
that STAR cannot do that yet. Every hard rule holds in chat: no review, evidence, log or diff content read into
this session, merges only through `merge.sh`. A question that needs code, a PR or a review is answered from STAR's
own small files (the ledger, the queue, the brief lines the digest reads); when they do not answer it, the
reply names where the answer is, and STAR neither reads it nor starts a worker.

Reply with `sh S/chat.sh --home HOME_DIR reply <the chat: id> --body-file <f>` (`<f>` from `mktemp`): short,
Markdown, saying what STAR did. `replied <reply id>`, or exit 66 (`already replied`) → delete the file. Exit 65
(`no message <id>`) → `sh S/chat.sh --home HOME_DIR post --body-file <f>`, then delete the file. Any other exit
→ leave the file; the next tick tries again and the status line names it.

A chat message answers a queue item only when it names the item (its id, like `N-12`) and states the answer:
record it with `loops.sh set-answer <id> "<the answer>"` and run the Answers step for it at once. A message that
could be an answer but names no item gets a reply asking which item it is for, and nothing is recorded. A
follow-up question STAR needs about a chat message is asked in the thread, never in the terminal, and the next
chat message is read with the thread as its context (after a compaction, the thread's last 6 files in
`HOME_DIR/chat/`). Every start answers each pending message whose inbox file is gone, once.

## Feedback on a brief

The owner can overrule a brief or a decision at any time, in chat or in the brief's `## Feedback`. The briefing
page has no feedback feature. Append the words with the date under the brief's `## Feedback`, then by where the
row is:

- **Not built yet** (`inbox`, `needs-you`, `queued`): when the change only edits the brief's own text (a
  criterion the owner states in their own words, `deliverable`, a Scope line, a `notBefore` date), STAR makes the
  edit itself and ends the entry with "(applied by STAR)". Anything that needs the code or the work item read
  again: row `inbox`, and the brief stage runs again with `--feedback`.
- **Being built or reviewed** (`building`, `babysit-queued`, `babysitting`, `verifying`): append the decision to
  `## Decisions`, stop the worker (record, stop, release, close check) and put the row in the waiting state of
  its stage, so the stage restarts with the new decision. This is not a try.
- **Already merged**: the change becomes a follow-up (`references/stages.md`).
- **While a brief drafts** (`briefing`): never into the brief, which its worker may be writing, and never sent
  to the worker. STAR appends `- <YYYY-MM-DD HH:MM> <the words, line breaks folded to spaces>` to the feedback
  side file `<the brief path>.feedback.md`; STAR is its only writer. The brief worker copies it under `##
  Feedback` right before it writes. When the report arrives STAR settles the side file first: `BRIEF` → append
  each side-file line the brief lacks (`grep -cxF '<line>' <brief>` prints 0) under `## Feedback`, delete the
  side file, and when any line was missing treat it as feedback on a not-built row; `ESCALATION` → put the
  lines under `## Feedback`, creating the file with only that section when the worker wrote no brief, delete the
  side file; `SPLIT` → put the lines under `## Feedback` in each new row's brief file, delete the side file. A row
  that leaves `briefing` any other way keeps the side file.

A `branch` or `baseBranch` change on a brief with `existingPr` is not feedback: both come from the PR, so the
owner changes the base on GitHub, and a different head branch needs a different PR. Say so in the reply.

## The batch digest

A batch is the items one request brought in (`counters.batch`). When no row of a batch is `inbox` or `briefing`
any more and at least one was briefed, STAR posts one message to the dashboard chat with `sh S/chat.sh --home
HOME_DIR post --body-file <f>`. It is a digest: no reply is expected and nothing waits on it. STAR reads only
these lines of each brief, with `sed -n`: the frontmatter's `item.title`, `blockedBy`, `notBefore`, `hold` and
`deliverable`, and the lines under `## Acceptance criteria`, `## Approach` and `## Person-only steps`, with the
`### D<n>` headings under `## Decisions`.

```
Batch B-20261009T081200Z-a3f9 · 3 items

ITEM-1 · Export reports as CSV · queued
  Criteria (4) · Approach: one line
  Decisions I made (2): D1 CSV over XLSX · D2 a 10,000-row cap
  Reused (1): D3 The hosted review comes after ready (L-0007)
ITEM-2 · ... · needs you: sign in to <app> (account)
ITEM-3 · set aside: <one line why>

Tell me what to change on any of these and I will redo it.
```

A `Blocked by:`, `Not before:` or `Held:` line appears only for a brief that has one. The decision records are
where the owner overrules STAR: an answer that names one is feedback for that brief.

## Drafts and Slack

STAR writes for the owner only what shipping needs, and sends none of it by itself:

- "Draft a status note": STAR writes `HOME_DIR/drafts/<date>-status.md` from the ledger and the queue and queues
  it as a `draft` item. The owner sends it.
- A Slack reply is never STAR's to write. The dashboard's drafter writes each draft from the project's code,
  briefs and PRs before the message reaches STAR, and again when the owner answers `rewrite: <how>`
  (`slack-redraft.sh` asks for it). STAR queues it, posts it on the owner's `send`, and never writes or changes
  reply text. The draft file's first line is `to: slack <channelId> <threadTs, or ts>`.

## Away and back

The handoff is how the owner leaves and comes back without losing anything. `handoff.md` only lists: the queue
stays the one place to answer. **Away holds no work.** Every stage keeps starting while the owner is away,
babysitting and merging included.

**Away** (`/juel:star away`, "I'm leaving", or a `control: away` file). Away while already away changes nothing.
Finish the current tick. An away that came as a control file or a chat message finds nobody at STAR's
terminal: ask nothing there. Run `sh S/handoff.sh --home HOME_DIR start`: it writes `handoff.md` (A. Needs you
now: the `person` items; B. Waits for you: drafts and set-aside items; C. What runs while you're away) and marks
`away` in `star.json`. Print part A, and post it into the dashboard's chat thread (`sed -n '/^### A\./,/^$/p'
HOME_DIR/handoff.md` into a `mktemp` file, then `chat.sh post --body-file`), unless it said STAR was already
away.

While away: only `person` items notify. About every 4 hours Housekeeping's `handoff.sh summary --if-due` adds a
dated summary to the top of `handoff.md`, only when something changed (items per state, PRs waiting to merge,
what merged, what stopped, `sent.log` since the last summary, free memory and running workers, and the open
Needs-you list). It needs STAR's session open.

**Back** (`/juel:star back`, "I'm back", or `control: back`): `sh S/handoff.sh --home HOME_DIR end` clears `away`
and prints the latest summary. Print it, then the open queue (`loops.sh list`). When it prints `not away`, say so
and print only the queue. Send the notifications that were held, then run a tick.
