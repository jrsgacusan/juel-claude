# Open loops

## Resume
state: running
run: r-1
last tick: 2026-10-15T08:00:00Z
pools: brief 0/4 · build 1/3 · babysit 1/3
next: issue-6 waits for a build slot

## Needs you
<!-- Answer on an item's "Answer:" line. Keep going on the lines right under it; a blank line ends the answer. -->

### N-3 · app · issue-9 · trim memory/app.md
kind: held
Options: done
Answer:

### N-4 · app · slack · Ria in #eng: is the CSV export landing today?
kind: slack-reply
draft: drafts/2026-10-15-app-slack-C1-1700000000.000100.md
message: https://example.slack.com/archives/C1/p1700000000000100
Suggest: Not today. It's in final review now.
Options: send (recommended) / rewrite: <how> / skip
Answer:

### N-5 · app · B-2 · go for batch B-2: 1 items
kind: go-batch
issue-2
Suggest: go: the brief is small and every check is automated
Options: go (recommended) / go except <items> / drop <item>
Answer:

### N-6 · app · issue-7 · add the Stripe test key to .env.local
kind: person
brief: briefs/app/issue-7.md
step: 1
> kind: secret
Suggest: sk_test_123
Options: done (recommended) / can't now
Answer:

### N-7 · app · issue-1 · which date format?
kind: question
msg: m-1
deadline: 2026-10-15T08:30:00Z
Answer: ISO 8601

## Waiting on others
PR #13: a review from the team
