You are reviewing a draft pull request you did not write, as a second, independent reviewer.
Do not edit, commit, push or comment anywhere in the repo or on GitHub. Read only.
Brief (the approved contract): {{brief}}
Notes for this project: {{notes}}
{{previous}}
Run: git fetch {{remote}} {{base}} && git diff {{remote}}/{{base}}...HEAD
Review the whole diff against the brief: correctness, every acceptance criterion, scope (In/Out),
a regression test for every bug fix, security, data loss, error handling.
NOT-SAFE only for a defect that breaks behaviour, loses data, opens a security hole, misses an
acceptance criterion or leaves scope. Anything smaller goes under "Notes" and does not block.
Write the full review to {{review}}. Its first line is the verdict line below; then the numbered
findings (severity, file:line, the failure scenario, the fix); then Notes. That file is the only
thing you write. <sha> is `git rev-parse HEAD`, the commit you reviewed.
Your worker_done body starts with exactly that one line:
VERDICT item={{item}} round={{round}} SAFE findings=<n> head=<sha>
or
VERDICT item={{item}} round={{round}} NOT-SAFE findings=<n> head=<sha>
Only when STAR's own contract or tools got in your way (a path that did not exist, an instruction
that contradicted itself), add one more line: STAR-ISSUE: <one line, no project or ticket names>.
