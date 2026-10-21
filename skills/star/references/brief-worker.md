# Brief worker mode: `draft-brief`

Read this when you are a brief worker (your prompt is `/juel:star draft-brief …`), and when STAR reads a
`BRIEF` or a `SPLIT`. Nothing else in SKILL.md applies to a worker in this mode except the Strict Execution
Protocol.

`/juel:star draft-brief <ref> --project <name> --item <name> --out <path> [--feedback] [--rescope <file>]`
runs in the project's main checkout as an Orca worker. It never edits the repository. It writes only the brief
at `--out`, spec items under `<HOME_DIR>/items/<project>/` when it splits an item or moves part of it to a
follow-up, and, in re-scope mode, the `-fix.md` of the review it narrowed by. Nobody is at its terminal, so it
never asks there. When it must ask STAR, it sends `orca orchestration ask --question "<question>" --json` and
waits for the reply.

The brief is the contract the build, the gate and STAR read, and the owner can overrule any line of it. Its job
is to leave the builder nothing to ask: every question the item leaves open is decided here, from a source, and
written down.

## Steps

1. **Read what is already known.** Read the file `sh S/notes.sh --home <HOME_DIR> --shelf memory --project
   <project> path` prints (HOME_DIR is two levels above `--out`'s directory) and `mcps` in
   `<HOME_DIR>/star.json`. When `notes` is `split`, run `sh S/recall.sh --home <HOME_DIR> --kind note <the item's
   key words>`; for each note in force that applies, `notes.sh … show M-<nnnn>` prints it on one line, and you
   copy that line under `## Notes that apply` as `- <the line>`. Never open the `memory/<project>/` folder, and
   never copy a search excerpt: it is cut. Read the project's `CLAUDE.md` and `AGENTS.md` for rules that apply.
   When a file already exists at `--out`, read its `## Feedback` (the owner's dated answers to earlier drafts).
   `--feedback` only says there is something new there. An answer there settles the question it answers: use it
   and never ask or report the same thing again. Read `<--out>.feedback.md` too when it exists (feedback STAR took
   while no brief existed); its lines count as `## Feedback` entries, and you never edit or delete it.
2. **Resolve the work source** as `references/work-source.md` §1 does: an explicit source in the ref, then
   `.claude/workflow.local.json` or `.claude/workflow.json` `tracker`, then a `## Work Source` block in
   `CLAUDE.md` or `AGENTS.md`, then the ref's shape (`#412` is GitHub, an existing path is a `file` item), then
   the single connected tracker. Still ambiguous: look for the answer in the tracker the ticket URL or the
   project's other briefs point to, and take a decision record. Only when nothing can settle it report
   `ESCALATION item=<name> phase=0 reason=needs-person needs=access: which tracker holds <ref>`.
3. **Fetch the item in full** with the provider's fetch from `references/work-source.md` (for Linear,
   `<LINEAR_PREFIX>get_issue(id: <ref>)`). A workspace-MCP tracker needs `get_work_item`; its absence is the
   same `needs=access` report.
4. **Normalize:** `ref` (null when none), `slug` (kebab-case from the title, at most 6 words), `title`, `url`,
   `path` (a `file` item's absolute spec path), `source`, `labels`, description, acceptance criteria. The
   item's name is `--item`, exactly as given: every later report line carries it.
5. **Resolve the repo's conventions.**
   - The remote: one remote is it, else `origin`.
   - **The base branch** comes from `star.json`: `baseBranch` when set, else the repository's default branch
     (`git symbolic-ref --short refs/remotes/<remote>/HEAD`). A brief or ticket that names a base listed in
     `ownerBranches` is re-targeted to that base, and the change is a decision record. An item whose whole
     point is a merge into an owner branch (a `dev` to `main` release PR) keeps that base in the brief, with a
     decision record saying so: STAR sets it aside, because that merge is the owner's.
   - Branch naming: sample `git for-each-ref --sort=-committerdate --count=60 refs/remotes/<remote>`, take the
     modal pattern; default `{type}/{ref-lower}-{slug}`, `{type}/{slug}` when the ref is null, a GitHub ref
     `#412` renders as `issue-412`; type is `fix`, `refactor`, `chore` or `feat`. When `--item` ends in a number
     the ref does not have (`SAVI-1162-2`), the branch gets the same suffix.
   - **Check the branch for a collision** (#121) against the `branch:` line of every other row's brief in
     `<HOME_DIR>/ledger.md`, the remote's branches (`git ls-remote --heads <remote>`) and the main checkout's
     local branches. The branch the brief at `--out` already names, and the head of an `existingPr`, belong to
     this item. On a collision extend the slug with the next words of the title, then distinguishing words of
     the item, then `-2`, `-3`, until it is unique. Record the slug as `item.slug`, and check again right before
     writing: a brief another worker wrote meanwhile counts too.
6. **Read enough of the code** to choose an approach and decide the item's open questions, then write the brief
   to `--out`. Right before writing, read `<--out>.feedback.md` again and copy each line the brief lacks,
   verbatim, under `## Feedback`. When a brief exists at `--out`, revise it to answer every `## Feedback`
   entry, keep that section and every `## Decisions` entry, and add new records after them with the next free
   `D<n>`. A record that overrules or narrows an earlier one ends the earlier with `Status: Superseded by D<m>
   (<why>)` or `Status: Amended by D<m> (<what>)`; one written because of the owner's feedback is reported as
   `CORRECTED D<new> replaces D<old>`.
7. **Report** (below).

## The brief

```markdown
---
juel_brief: 1
item:
  name: <the --item value>
  ref: <ref or null>
  slug: <slug>
  title: <title>
  url: <url>              # omit when absent
  path: <absolute spec path, file sources only>
  source: <source>
  labels: [<labels>]
branch: <branch>
baseBranch: <base>
existingPr: <url>         # only for an item that brings an open PR to mergeable
deliverable: pr           # or report
blockedBy: [<item>, <item>]
notBefore: <YYYY-MM-DD or ISO datetime>   # only when the item must not be built before then
hold: <the owner's words>                 # only for an owner's hold that is no date and no other item
star:
  home: <HOME_DIR>
  project: <project>
  notes: [<the path notes.sh path printed>]
  reviews: <HOME_DIR>/reviews/<project>
  gates: <HOME_DIR>/gates/<project>/<item>.json
  reports: <HOME_DIR>/reports/<project>
---
## Work item
<the description, word for word, every Markdown heading in it demoted one level>
## Acceptance criteria
- [ ] <one per criterion>
## Approach
<2-6 sentences: the chosen approach, the components touched>
## Scope
In: <what this item changes>
Out: <what it deliberately does not touch>
## Checks
- <what is checked> | auto: <playwright, hidden-window, computer-use, api or cli>[ | helper: <path>]
## Person-only steps
1. [<kind>] <what to do>
## Notes that apply
- M-<nnnn> <title>: <text>   # or: none
## Decisions
### D1 <title> (<date>, decided by the brief worker)
Context: <the question the item leaves open>
Decision: <the choice>
Consequences: <what it changes or rules out>
Source: <a URL, a Mobbin screen or flow URL, a Context7 library id and topic, or file:line>
```

The description's headings are demoted so the item's own sections never collide with the brief's (#36); STAR
and the workers read only the brief's own top-level sections.

**Acceptance criteria.** The item's own and any the owner states in a `## Feedback` entry go in together. When
neither gives any, write them: derive them from the item's text (its description, what it links to, what the
code does now), ground a user-facing criterion in the sources below, and log a decision record `Acceptance
criteria written by the brief worker` that names those sources. STAR does not ask the owner for criteria, and
the criteria never claim more than the item's text and the code support.

**Checks.** One line per acceptance check, marked with how the build runs it: `auto: playwright` (a web page,
headless), `auto: hidden-window` (an Electron window, a hidden dev build driven over CDP with no screen lock;
add `| helper: <path>` when the project has its own launch helper), `auto: computer-use` (a native window
through `orca computer`, under the screen lock), `auto: api` or `auto: cli`. A check that needs a person first
(sign in with 2FA, grant a macOS permission once) adds `| person: <what>`, and the same step goes under
`## Person-only steps`. A check no tool can run is not left for later: find an automated check that proves the
same criterion and record why it is enough. Write `none` when there is nothing to check live.

## Decisions are taken, not asked

Every question the item leaves open that a builder would otherwise ask (a product call, a library, a name, a
format, how an edge case behaves, a risky call that has a safe option) is decided here and written as a
decision record. The owner can overrule any of them; the workers read them as binding. Ground each in a
source, in this order of fit:

- **A user-facing change:** the Mobbin MCP (`search_screens`, `search_flows`, `search_sections`) for how real
  apps solve it, together with the `frontend-design:frontend-design` skill for the visual and interaction
  choices. Mobbin searches spend paid credits: use them for user-facing changes only.
- **A library, framework, SDK, API or CLI:** Context7 at the version the project uses.
- **When neither fits:** a web search, official docs first.
- **A project convention:** the repository, cited as `file:line`. A brief names a file-name, path or id form
  only by quoting the rule the repository enforces it with (a checker, a lint or pretest script, `file:line`);
  when it finds none it names no form and the build follows the repository (#107).

Look for the tools `mcps` names `available` (with `ToolSearch` when they are deferred) before you decide they are
missing, and use an MCP only when this session lists its tools. When it does not, or `mcps` says `needs-sign-in`
or `absent`, search the web and say so in `Source:`.

**Search before deciding.** Run `sh S/recall.sh --home <HOME_DIR> --kind decision <the question's key words>`.
A library decision in force that fits is reused: write `### D<n> <title> (<date>, reused L-<nnnn>)` with the
library's `Decision:` (`sh S/library.sh --home <HOME_DIR> --project <project> show L-<nnnn>`) and `Source:
library L-<nnnn>`, and report `REUSED L-<nnnn>`. An earlier item's decision that fits is reused the same way
(`reused <item> D<m>`, reported `REUSED <item>#D<m>`). Recall finds candidates; whether one fits is your call.
Read at most the one record you reuse, never a whole earlier brief.

**External ids are checked live** (#42). Every service slug, project id, DSN, host name or account name the
brief carries is checked where a CLI or API can reach it (`gh api`, the service's own CLI, a DNS lookup) and
marked `(verified <date> via <how>)`, or `(unverified: <why>)` with a decision record of how the build copes.

**A hosted review comes after ready** (#40). When the item, a note or a feedback entry asks for the hosted
reviewer's review before the PR is ready, take a decision record that the order is ready first, then the
review (Greptile skips draft PRs by default); cite its docs.

## What only a person can supply

`## Person-only steps` lists only what a person must do, one numbered line each, `<n>. [<kind>] <what and what
it is for>`. The kinds are the owner's five: `secret` (a key or token the work needs, and where it goes),
`account` (signing up for or in to a third-party service, or anything that costs money), `screen` (an action
at the Mac: a trust dialog STAR could not clear, a lost Claude login, hardware), `approval` (the base branch's
protection requires an approving review STAR cannot give) and `access` (`gh` cannot see the repository, so
`tokenCmd` must be set). Nothing else belongs here. A product call is a decision record. A risky call
(deleting data, a migration that cannot be undone) has a safe option: take it and record why. An owner's hold
is never a step. Write `none` when there is nothing.

Before adding a step, look it up: the notes, the project's `CLAUDE.md` and `AGENTS.md`, and `open-loops.md`
with `open-loops-archive.md` (`grep -iF` on the step's key words). A step the owner answered in the last 7 days
goes into `## Decisions` with that answer (`- <date> person-only step: <step> → <answer> (N-<id>, answered in
the last 7 days)`) and is not asked again. Never put a secret's value in the brief or an answer.

## Blocked by, not before, holds

- `blockedBy` lists the items this one needs merged first, `[]` when none; the line holds only the list, never a
  comment (the queue reads it with `sed -n 's/^blockedBy: //p'`). An item goes on it only when the item's own
  links say so, the owner said so (quoted in the reason), or this item needs code the other adds (named as a
  path, function or endpoint). Each has a record `- <date> blocked by <item>: <reason>`. Use each item's ledger
  name. Sharing files is never a blocker. Never a cycle: keep the link the code needs.
- `notBefore` when the text, a note or a feedback entry says the item may only be built after a date or time
  (#87): `YYYY-MM-DD` for a day, starting at 00:00 local, or an ISO datetime. "After <day>" is the day after it;
  "not before <day>", "from <day>" and "on <day>" are that day; a weekday is the next one after today. Take a
  record that quotes the words.
- Any other hold ("until I confirm the design") is the line `hold: <the owner's words>`. The row waits by itself
  and the owner lifts it by telling STAR.

`deliverable` is `report` when every acceptance criterion asks only for evidence, a disposition or a write-up
and nothing asks for a change to code or docs in the repository; otherwise `pr`. A feedback entry that names
one wins.

`existingPr` is set only when the item's outcome is to bring an open PR to mergeable: `gh pr view <url> --json
url,headRefName,baseRefName,isCrossRepository,state,author`, and only when `state` is `OPEN`. Then `branch` is
its `headRefName` and `baseBranch` its `baseRefName`. An item file with `existingPr:` (a follow-up that
`ledger.sh add rescopedFrom=` wrote, #161) takes it through the same checks and copies its `rescopedFrom:`; its
Scope, criteria and checks are the parent brief's, with the parent's `## Decisions` copied in, plus one
criterion per finding still open in its `review:` file. A PR that is not `OPEN`, or that you cannot continue,
is a new PR from a copy of its branch, with a decision record. A fork's PR, and a PR whose author is not the
`gh` user (`gh api user --jq .login`), is carried as a new PR (#94): `existingPr` is left out, `branch` is named
by step 5 and never the original's, and the record's `Decision:` line is exactly `Decision: carried as a new PR:
<url> (<login>'s PR)`. The build opens the new PR from the original's head so the commits keep their author;
STAR never touches the original, which is the teammate's.

## Report

The `worker_done` body is the report lines and nothing else; it overrides any request for a prose summary,
Orca's worker preamble included. STAR reads the first line.

- `BRIEF item=<name> path=<--out> asks=<n> [followup=<path>]`, where `<n>` is the number of lines under `##
  Person-only steps` (0 for `none`). Add `followup=` when a `## Feedback` entry made part of the item
  impossible as written and you moved that part to a spec item, `<HOME_DIR>/items/<project>/<name>-followup.md`
  (`-followup-2` when that exists; `status: todo`, `title:`, then what is left and the feedback that moved it),
  with a record saying what moved and why. Then one `REUSED` or `CORRECTED` line per reused or corrected
  record, at most one `NOTE: <one line>` (`NOTE: always <text>` for a note every worker needs on every item),
  and at most one `STAR-ISSUE: <one line>` when STAR's own contract or tools got in the way (no project or
  ticket names).
- An item that holds more than one piece of work that could ship on its own is split instead: write each piece
  as a spec item, `<HOME_DIR>/items/<project>/<name>-<k>.md` (`status: todo`, `title:`, the words of the item
  that describe that piece), write no brief, and report `SPLIT item=<name> into=<path>,<path>`. When the item is
  a tracker item, STAR links each part to it (`trackerRef`) and writes the parent's status from the parts.
- `ESCALATION item=<name> phase=0 reason=needs-person needs=<kind>: <what>` for something only a person can
  supply that blocks the brief itself, and nothing else.

## Re-scope mode (`--rescope <file>`)

The build or babysit worker could not get the item past a reviewer (the codex gate after its rounds, the hosted
reviewer after its passes, or CI), and `<file>` holds the findings still open. Read the brief with its `##
Decisions`, then `<file>`, then what the branch changed so far (`git fetch <remote>`, then `git diff --stat
<remote>/<baseBranch>...<remote>/<branch>`). Narrow the brief to what the branch can ship safely: move each part
the findings show cannot be done safely in this item to Scope `Out:`, drop or reword the criteria that belonged
to it, and take a decision record that says what moved and why, with the findings file as its source. Keep
`branch`, `baseBranch` and `existingPr` as they are: the narrowed item builds on the same branch and PR.
`## Person-only steps` follows the rules above and leaves out a step `## Decisions` already records as answered.
Write what moved as a follow-up spec item, `<HOME_DIR>/items/<project>/<name>-followup.md` (`status: todo`,
`title:`, what is left and the findings that sent it there). When `<file>` is a codex gate review
(`<item>-r<k>.md`) and no `<item>-r<k>-fix.md` lies beside it, write that file: one line per finding, in its
order, `Disposition: moved to <follow-up path> (decision D<n>)` or `Disposition: kept, <why> (decision D<n>)`.
The next gate round reads it as the dispositions of those findings, so it does not raise settled findings
again. A hosted review file gets none: the gate never saw its findings. When every finding is moved or kept
with a disposition and no criterion left needs a code change, add `- <date> gate-only: the narrowed brief needs
no new code; the next build runs the gate on <branch head7>` to `## Decisions`. Report `BRIEF item=<name>
path=<--out> asks=<n> rescoped=1 followup=<path>`. When narrowing cannot leave anything safe to ship, report
`ESCALATION item=<name> phase=0 reason=out-of-tries step=conflict review=<file>`: STAR sets the item aside.
