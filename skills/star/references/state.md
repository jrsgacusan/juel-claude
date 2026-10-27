# STAR's state: the home, star.json, the queue and the ledger

Read this when you write a file in the home, change a setting, add a queue item or touch a ledger row.
Every file is written by one script, because two writers lose each other's rows and a person's typing.

## Contents

- The home
- `star.json`
- The queue
- The ledger

## The home

`HOME_DIR` is never worked out by hand: `sh S/star-home.sh path` prints it, `init` creates it. It is
`<main checkout>/docs/superpowers/context/star`, so every worktree of a project shares one folder and a
project has exactly one STAR. `init` writes one line to `.git/info/exclude` so git ignores it (never
`.gitignore`: nothing shows as a change, and a read-only repository is fine), records the project in
`star.json` as `"project": {"name": <main checkout folder name>, "repo": <its path>}` and lists the home
in `~/.juel/star-homes.json` under a lock. That registry is what the dashboard reads; `star-home.sh
register` does that part alone. Nothing here is committed or pushed.

```
star.json               settings (below) plus the run id, STAR's terminal, caffeinate pid, heartbeat id
open-loops.md           Resume block, Needs you, Waiting on others (loops.sh only), with its archive and .seq
handoff.md              summaries written while the owner is away (handoff.sh)
sent.log                <iso>\t<project>\t<item>\t<what was sent>: everything STAR or a worker posted
ledger.md               one row per item (ledger.sh only)
processed.log           <message id> <dispatch> <iso>, plus "<dispatch> stopped <iso>" and "<dispatch> released <iso>"
messages-wait           while a background wait runs: "<pid> <iso start>" (messages.sh)
inbox/                  one file per hand-over, chat message or control command; deleted once handled
chat/                   the dashboard's thread, one file per message, never rewritten (chat.sh)
items/<project>/        spec items from free text, splits, follow-ups and re-scopes
briefs/<project>/<item>.md
reviews/<project>/<item>-r<k>.md       the codex gate's verdict file (first line the verdict), with .raw.md, .log, -fix.md, -carried.md, .run and -error-<n>.log beside it
reviews/<project>/<item>-dismissed.md the findings a -fix.md dismissed with a Disposition, one line each: `<fp> r<j>#<n> [P<p>] <path>:<line> <title>`
reviews/<project>/<item>-hosted.log    one line per hosted-reviewer run a babysit worker logged
reviews/<project>/<item>-hosted-p<n>.md   hosted findings that sent an item to a re-scope
specs/<project>/<item>-gate-r<k>.md    the gate's prompt (codex-gate.sh)
progress/<item>.log     one line per milestone, appended by the item's workers
workers/<terminal>.json the worker's last hook event (a StopFailure or Notification, or clear), written by hooks/worker-state.sh, read by worker-probe.sh; files older than 7 days are deleted
reports/<project>/<item>.md            a report item's report
gates/<project>/<item>.json            the gate manifest
releases/<date>-<project>-<item>.md    release records (release-record.sh)
evidence/<item>/        the item's evidence, copied from its worktree before worktree-clean.sh removes it
builds/<item>/          the build's specs and plans, copied the same way
drafts/                 drafts of status notes and issues
memory/<project>/       one note per file (notes.sh), memory/<project>.always.md the notes every worker reads
library/<project>/      decisions that apply beyond one item (library.sh)
issues.log, ids.json, index.db, library.base, notes.base
```

`<project>` is the name in `star.json`. A folder holds one project; the name stays in paths, the
queue and the ledger so every file says what it belongs to. Old files such as `grants/` stay on disk
unread; nothing in a migration deletes them. A schema-3 home may delete an old `grants/` folder and the `grant` line in a brief's frontmatter: nothing reads them.

## `star.json`

Schema 3. `star-home.sh migrate` brings an older home here; `template/star.json` is the default.

```jsonc
{
  "schema": 3,
  "maxParallel": 3,                 // build pool
  "maxInReview": 3,                 // babysit pool
  "maxBriefs": 4,                   // brief pool
  "stages": {                       // the best model for each stage's kind of work
    "brief":   { "agent": "claude", "model": "opus", "effort": "high" },
    "build":   { "agent": "claude", "model": "opus", "effort": "xhigh" },
    "babysit": { "agent": "claude", "model": "opus", "effort": "xhigh" },
    "post":    { "agent": "claude", "model": "opus", "effort": "xhigh" }
  },
  "worker":   { "agent": "claude", "model": "opus", "effort": "xhigh" },   // a stage with no entry, and the fallback
  "executor": { "model": "latest-luna", "effort": "xhigh", "fallback": "latest-sol" },
  "gate":     { "model": "latest-sol", "effort": "xhigh", "fallback": { "agent": "claude", "model": "opus", "effort": "xhigh" } },
  "tries":    { "perStep": 3, "rescopes": 1, "followUpDepth": 2 },
  "mergeMethod": null,              // "merge", "squash", "rebase" or null
  "baseBranch": null,               // the branch every STAR PR targets; null is the repository's default
  "ownerBranches": [],              // branches only the owner merges into
  "keepBranches": false,            // true: a branch Orca deletes with a finished worktree is recreated (#200)
  "hostedReviewer": null,           // or { "login": "greptile-apps[bot]", "minScore": 4, "maxPasses": 2, "refreshOutsideCap": true, "paused": false }
  "hostGate": { "minFreeGB": 3, "maxAgents": 40, "maxSwapGB": 11, "minDiskGB": 25 },
  "progressDeadlineMin": 30,        // no progress for this long: a check-in
  "mcps": null,                     // every start writes { "mobbin": "...", "context7": "..." } from the Preflight
  "notes": "split",                 // "legacy" in an old home: workers then read memory/<project>.md
  "gateDown": null,                 // while the review gate is down: { "since", "why", "checked" }
  "hostedDown": null,               // while the hosted reviewer reviews nothing: { "since", "why" }
  "tokenCmd": null,                 // a command that prints a GitHub token, or null
  "ghLogin": null,                  // STAR's own gh login, written at every start
  "run": null, "terminal": null, "caffeinatePid": null, "heartbeat": null,
  "notified": [], "away": null, "project": null
}
```

Each stage runs on `stages.<stage>`; a stage with no entry runs on `worker`. The executor and the
gate are not stages: every worker reads `executor`, `gate`, `hostedReviewer` and `mcps` from this file
through its brief's `star.home`. `latest-<family>` is the newest model of that family `codex debug
models` lists, resolved at each run. A model of `default` means pass neither `--model` nor
`--effort`; model ids come from the CLIs, never from memory. `maxAgents` is 40 because this Mac ran 29
agent processes on 2026-10-09; `max` effort costs about three times `xhigh` for a gain nobody could
measure, so it is not the default.

| Key | Rule |
|---|---|
| `tries.perStep`, `tries.rescopes`, `tries.followUpDepth` | The budget in SKILL.md. Migration carries an old `gate.maxRounds` into `perStep`. |
| `mergeMethod` | `merge.sh` uses it when the repository allows it, else it prints `FAIL merge methods: <method> not allowed`. Null keeps squash, merge, rebase: the first the repository allows. |
| `baseBranch`, `ownerBranches` | Where PRs go and where only the owner merges (SKILL.md, the merge gate). |
| `keepBranches` | False by default. True: `worktree-clean.sh` notes the worktree's branch and HEAD, and when Orca deleted the branch with the worktree (it has no option to keep one), recreates it at that HEAD in the main checkout and prints `kept-branch <branch> <sha7>` before `removed`. Branch names are the trace back to a ticket. |
| `hostedReviewer.paused` | True stops the ready ping, the score wait and the pass count; the merge gate then runs as for a project with no reviewer. The babysit worker also treats the reviewer as paused when the project's `CLAUDE.md` or `AGENTS.md` says so. |
| `hostedReviewer.refreshOutsideCap` | True when absent: a status refresh after the last pass stays outside `maxPasses`. False: babysit never asks for a run past `maxPasses`; a head that needs one reports `ESCALATION reason=out-of-tries step=hosted-review`. Before it asks for the last pass, babysit merges the base in when the base requires up-to-date branches (or is a merge queue), the PR conflicts, or the rule is unknown, never on behind alone, so that pass reviews a current head. |
| `tokenCmd` | For a repository the default `gh` account cannot see: a command that prints a token, such as `security find-generic-password -s <item> -w`. The plugin's session hook adds `export GH_TOKEN="$(<tokenCmd>)"` to every session that starts in this project, STAR's and every worker's. It writes the command, never the token, and leaves a session that already has `GH_TOKEN` alone. The command must be quick and must not ask anything. With `tokenCmd` null the hook keys the token to `ghLogin` with `gh auth token --user <ghLogin>`, so every worker acts as the account STAR does. STAR's own scripts do the same through `gh-token.sh`. Setting it is the owner's `access` item. |
| `mcps` | The research MCPs STAR's session found: `available`, `needs-sign-in` or `absent`. Workers read it to know which tools to expect; a brief worker whose tools show another state reports `MCP <name>=<state>` and STAR writes it here (#192). |
| `notes` | `legacy` or `split`. The mode of a home is never changed by STAR. |

The hosted-reviewer lookup, run once at the first start and after a migrate when `hostedReviewer` is
null: when `greptile-apps[bot]` commented on one of the repository's last 20 merged PRs, set
`hostedReviewer` to `{"login": "greptile-apps[bot]", "minScore": 4, "maxPasses": 2, "refreshOutsideCap": true, "paused": false}` and say so in one line. The
lookup is `gh pr list --state merged --limit 20 --json number --jq '.[].number'`, then for each `<n>`
`gh api "repos/{owner}/{repo}/pulls/<n>/reviews" --jq '.[].user.login'` and `gh api
"repos/{owner}/{repo}/issues/<n>/comments" --jq '.[].user.login'`, stopping at the first line that is
exactly `greptile-apps[bot]`. The `mergeMethod` and `baseBranch` lookups work the same way: read the
project's `CLAUDE.md`, `AGENTS.md` and STAR's rule notes for a rule, set the key, say so in one line.

The first start (`run` still null) also looks the repo path up in `orca repo list --json` and adds the
id as `project.orcaRepo`, plus `project.remote`: the only remote `git -C <project.repo> remote` prints,
else `origin`.

## The queue

`open-loops.md` is written only through `loops.sh`, which re-reads it every time and never loses text
the owner typed. The owner answers on an item's `Answer:` line (or in the dashboard, or by telling
STAR), and STAR records it with `loops.sh set-answer <id> "<text>"` and acts on it in the same turn.

STAR creates three kinds of item and no other:

| Kind | Title | Body lines | Options |
|---|---|---|---|
| `person` | the thing only a person can do, one line | `kind: secret\|account\|screen\|approval\|access`, then what it is for | `done / can't now` |
| `set-aside` | `<item> set aside: <one-line reason>` | `step: <step>`, plus `review: <path>` when there is one | `try again / drop` |
| `draft` | what the draft is, or `by hand: <action>` for a worker's `HELD` line | the draft path, or `action: <action>` | `send / drop`, or `done / skip` |

```sh
sh S/loops.sh add --kind person --project <p> --item <i> --title "<the thing>" --body "kind: <kind>\n<what it is for>\nOptions: done / can't now"
sh S/loops.sh add --kind set-aside --project <p> --item <i> --title "<i> set aside: <reason>" --body "step: <step>\nreview: <path>\nOptions: try again / drop"
sh S/loops.sh add --kind draft --project <p> --item <i> --title "by hand: <action>" --body "action: <action>\nOptions: done / skip"
```

- **A pick.** When STAR has a pick it marks that option ` (recommended)` and adds `Suggest: <one line,
  why>`. A `secret` never gets either. The answer words do not change: a trailing ` (recommended)` is
  dropped before STAR compares an answer.
- `loops.sh add` is safe to repeat: for an item already open with the same kind, project, item, title and
  body it prints that id and adds nothing. A `person` item is also matched across items by title (case
  and spacing ignored), and the line `also: <item> <brief path> #<n> <kind>` is added once to its body,
  so one step several items share is asked once. It refuses (exit 64) a project or item with a line break
  or ` · ` in it and writes body lines that look like headings or `Answer:` lines as quotes, so ticket
  text can never forge an answer.
- Open items are repeated in every status line until answered, by id and title.
- Every row STAR sets aside, and every person item a row waits on, has an open item, so no row is
  stranded. A `loops.sh list` line `missing` (an id handed out that is in neither the queue nor the
  archive) is named in the status line, and any ask a row still needs is added again.
- A `person` item is the only item anything waits on, and only the row that needs it. A `set-aside` item
  is a note; nothing waits on it.
- Exit 3 (conflict markers in `open-loops.md`): stop writing the queue, say so, keep workers running.

## The ledger

`ledger.md` holds one row per item and is written only through `ledger.sh`, which re-reads the file
under a lock, cleans every value (`|` and line breaks become `/ `, an empty value is `-`) and stamps
`updated` itself. Every field is its own quoted argument: never build a `set` line by splitting a
string, which once turned a value into two rows.

| Command | Does |
|---|---|
| `sh S/ledger.sh name <ref>` | the item name the ref gets, or `open <item>` when the ref already has an open row |
| `sh S/ledger.sh add <item> ref=<raw ref> project=<p>` | a new `inbox` row; exit 65 when the item, or an open row for the ref, exists |
| `sh S/ledger.sh add rescopedFrom=<parent> review=<path>` | a follow-up row for findings left in a review file |
| `sh S/ledger.sh set <item> <col>=<value> … counters.<key>=<n>\|+1\|-` | changes only the named cells, in that order; `counters=keep:<k>,…` drops every other counter |
| `sh S/ledger.sh get <item> [<col>\|counters.<key>]` | one cell (`-` when absent), or the row as `col=value` lines |
| `sh S/ledger.sh list [--state <s>,…]`, `counts` | one row per line, or `<state> <n>` |

`| item | ref | project | worktree | state | stage | round | task | dispatch | restarts | pr | head | cursor | verify | counters | updated |`

`updated` is one UTC time and nothing else. `verify` holds `retry=<iso>` or `-`. `restarts` is the
attempt number that keeps request ids unique; it is not a budget. A row's counters are
space-separated `key=value` pairs, `-` when there are none, and there are only these:

| Key | Holds | Cleared when |
|---|---|---|
| `tries=<n>` | failed attempts since the row last made progress | the row first reaches a state further along than `reached`, or STAR re-scopes it, or the owner answers `try again` |
| `reached=<state>` | the furthest of `briefing`, `building`, `babysitting`, `verifying`, `done` the row has been in | never |
| `rescoped=<n>` | re-scopes spent | `try again` |
| `depth=<n>` | follow-up depth counted from the original item | never |
| `hold=<n>` | ticks in a row the host gate held this row | it starts |
| `start=<n>` | written by `stage-start.sh`: the attempt it is on | never |
| `parent=<item>` | the item a follow-up was split off from | never |
| `trackerRef=<ref>` | on each part of a split tracker item: the parent's ref | never |
| `batch=<id>` | the inbox file or start that brought the item in (`B-<file name>`) | never |
| `last=<message id>` | the last message applied to this row | the next message overwrites it |
| `tracker=<status>` | the last status STAR wrote to the work item, `!<status>` when that write failed | the next write overwrites it |
| `rescope=<file>` | the review file the next brief stage narrows the item by | the re-scoping `BRIEF` arrives |

`reached` is why a `verifying` to `babysit-queued` to `verifying` loop never resets `tries` and cannot
run forever.

**An item has one name everywhere**, set once at ingest by `sh S/ledger.sh name <ref>` and used for its
row, brief, review and gate paths, worktree and every report line: a tracker ref as written
(`SAVI-1162`); a GitHub ref `#<n>` becomes `issue-<n>`; a spec path becomes the kebab-case of its file
name. It keeps only `A-Za-z0-9._-`, drops a leading `.` or `-` and is cut at 60 characters. The raw
reference stays in the `ref` column; it is what the brief worker fetches. A ref that already has a row
that is not `done` or `dropped` is the same item: no new row, and the status line says so. A name is used
once per project, ever: a different ref that maps to a taken name, and a ref whose earlier row is `done`
or `dropped`, get `-2`, `-3`, with their own brief, reviews and queue items.

**Pools.** Brief pool (at most `maxBriefs`): `inbox` rows, oldest `updated` first. Briefs only read, so
they never take a build slot. Build pool (at most `maxParallel`): `post-queued` rows, then `queued`
rows whose `blockedBy` items are all cleared (`done`, or `dropped` with every part of it cleared, #37, #189),
whose `notBefore` time has passed (#87) and whose brief has no `hold:` line; within each, oldest first.
Babysit pool (at most `maxInReview`): `babysit-queued` rows, oldest first, skipping a row whose `blockedBy` is
not cleared (#205). `stage-start.sh` prints `wait <item>` for any row it is asked to start while a blocker is open. A row counts against a pool exactly while its state has that pool
in the State table. Each stage has a waiting state used whenever it is to run (again): brief `inbox`,
build `queued`, babysit `babysit-queued`, post `post-queued`. Nothing starts a worker except "Fill
slots", so a restarted stage waits for its pool like any other.

`needs-you` keeps the `stage` column of the stage it waits to resume. When its last open `person` item is
done, the row goes to that stage's waiting state.
