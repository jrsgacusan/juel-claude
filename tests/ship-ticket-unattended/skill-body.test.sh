#!/bin/sh
# Guards on skills/ship-ticket/SKILL.md: unattended and brief modes for juel:star workers.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/ship-ticket/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
# has <name> <text>: the text is in $SKILL once line breaks and repeated spaces are folded
has() { tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qF -- "$2" && pass "$1" || fail "$1"; }
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
for f in '--unattended' '--brief <path>' '--executor-model <id|latest-<family>>' '--executor-effort <level>'; do
  grep -q -- "$f" "$SKILL" && pass "flag $f" || fail "flag $f"
done
grep -q '## Unattended mode' "$SKILL" && pass "section" || fail "section"
grep -q 'ESCALATION item=' "$SKILL" && pass "escalation line" || fail "escalation line"
for r in 'brief-violation' 'codex-failed' 'verification-failed' 'gate-red' 'merge-conflict' 'needs-human-input' 'stack-unavailable'; do
  grep -qi "$r" "$SKILL" && pass "escalation: $r" || fail "escalation: $r"
done
grep -q 'gh pr create --draft' "$SKILL" && pass "draft PR under unattended" || fail "draft PR"
grep -qi 'instead of calling the provider.s `fetch`' "$SKILL" && pass "--brief skips fetch" || fail "--brief skips fetch"
grep -q 'HELD item=' "$SKILL" && pass "HELD on missing connector" || fail "HELD line"
grep -q 'Pause for explicit user confirmation between every phase' "$SKILL" && pass "interactive unchanged" || fail "interactive gating text changed"
grep -qi 'never marked PASS' "$SKILL" && pass "unverifiable never PASS" || fail "unverifiable rule"
grep -q 'Never merge the PR from this skill' "$SKILL" && pass "never merge" || fail "never merge"
grep -q 'do not invoke `juel:start`' "$SKILL" && pass "--brief bypasses juel:start" || fail "--brief bypasses juel:start"
grep -q 'without `--brief` is refused' "$SKILL" && pass "unattended requires brief" || fail "unattended requires brief"
for l in 'PHASE <n> <item>' 'PR item=<item> url=<url> draft' 'DONE item=<item> pr=<url>'; do
  grep -qF "$l" "$SKILL" && pass "line $l" || fail "line $l"
done
grep -q 'reason=preflight' "$SKILL" && pass "preflight stop escalates" || fail "preflight stop escalation"
grep -q 'Clean up before escalating' "$SKILL" && pass "cleanup before escalation" || fail "cleanup before escalation"
grep -q 'gh pr create --draft --base <baseBranch>' "$SKILL" && pass "draft PR uses the brief base" || fail "draft PR base"
grep -q 'the `--brief`.s `baseBranch` → explicit argument' "$SKILL" && pass "brief base heads the chain" || fail "brief base chain"
for p in linear jira github file; do
  grep -q "^   | \`$p\` |" "$SKILL" && pass "phase 7 status row $p" || fail "phase 7 status row $p"
done
grep -q 'ship a Linear ticket' "$SKILL" && fail "description is source-neutral" || pass "description is source-neutral"
for gone in 'REVIEW-FINDINGS' 'CONTINUE item=' 'ACK <item>' 'fleet-ship-tickets'; do
  grep -q -- "$gone" "$SKILL" && fail "removed: $gone" || pass "removed: $gone"
done
grep -q 'first line of the `worker_done` body' "$SKILL" && pass "report rides worker_done" || fail "worker_done body"
grep -q 'gate.lock' "$SKILL" && pass "gate lock" || fail "gate lock"
grep -q 'kernel lock' "$SKILL" && ! grep -q 'reclaims a lock whose' "$SKILL" && pass "gate lock is a kernel lock, nothing to reclaim" || fail "gate lock description"
grep -q 'Under `--unattended`, this phase is SKIPPED' "$SKILL" && pass "phase 8 left to the coordinator" || fail "phase 8 unattended"
grep -q 'HELD item=<item> action=open a draft PR from <compare-url>' "$SKILL" && pass "no-gh unattended path" || fail "no-gh unattended path"
grep -q 'gate-lock.sh' "$SKILL" && pass "S2 gates run through gate-lock.sh" || fail "S2 gate-lock.sh"
grep -q 'Phase 5.s targeted tests' "$SKILL" && pass "S2 Phase 5 gates locked too" || fail "S2 phase 5 locked"
grep -q 'unanswered-question' "$SKILL" && pass "S4 unanswered-question escalation" || fail "S4 unanswered-question"
grep -q 'Tier C is never used' "$SKILL" && pass "S12 no interactive Tier C unattended" || fail "S12 Tier C"
grep -q 'item.path' "$SKILL" && pass "S11 file status write targets item.path" || fail "S11 item.path"
grep -q -- '-fix.md' "$SKILL" && grep -q 'Disposition:' "$SKILL" && pass "S16 every finding left unfixed has a disposition" || fail "S16 dispositions"
grep -q 'older than 2 h' "$SKILL" && fail "S8 no age-only stale rule" || pass "S8 no age-only stale rule"
grep -q 'run_in_background: true' "$SKILL" && grep -q 'gate-lock.sh' "$SKILL" && grep -q 'background, like `codex exec`' "$SKILL" && pass "T1 gate runs backgrounded" || fail "T1 backgrounded gate"
grep -q 'heavy verification commands in the plan' "$SKILL" && pass "T9 executor heavy commands locked" || fail "T9 executor lock"
grep -q 'at most 12 lines' "$SKILL" && pass "report capped at 12 lines" || fail "12-line cap"
grep -q 'GATES <path>' "$SKILL" && pass "gate manifest written to a file" || fail "GATES path"
grep -q 'NOTE: <one line>' "$SKILL" && pass "one NOTE line allowed" || fail "NOTE line"
grep -q 'star.notes' "$SKILL" && pass "reads the memory notes first" || fail "memory notes"
grep -q 'GATES {"test":' "$SKILL" && fail "no inline gate JSON in the report" || pass "no inline gate JSON in the report"
grep -q 'item.name' "$SKILL" && pass "item named by the brief's item.name" || fail "item.name"
grep -q '## Decisions' "$SKILL" && pass "brief decisions are binding" || fail "Decisions"
grep -q 'batch-dir' "$SKILL" && fail "no stale batch-dir paths" || pass "no stale batch-dir paths"
# Stress test pass fixes
grep -q 'Nothing is asked at the terminal' "$SKILL" && pass "S4 no prompt survives unattended" || fail "S4 catch-all for prompts"
grep -q 'needs=verification steps' "$SKILL" && pass "S4 an empty checklist escalates" || fail "S4 empty checklist"
grep -q 'needs=browser verification of' "$SKILL" && pass "S4 no browser tool escalates" || fail "S4 browser fallback"
grep -q 'gate-busy' "$SKILL" && pass "S15 a busy gate lock is bounded" || fail "S15 gate-busy"
grep -q 'the later one wins' "$SKILL" && pass "S12 contradictory decisions have an order" || fail "S12 decision precedence"
grep -q 'more than two `HELD` lines' "$SKILL" && pass "S11 held lines are aggregated" || fail "S11 HELD aggregate"
! grep -q 'JUEL_GATE_LOCK=<star.home>' "$SKILL" && grep -q '/tmp/juel.gate.<uid>.lock' "$SKILL" && pass "T1 one gate lock per user, no path to pass" || fail "T1 gate lock path"
grep -q 'A gate inside an invoked skill' "$SKILL" && pass "T8 gates inside invoked skills are covered" || fail "T8 nested gates"
grep -q 'ask the coordinator' "$SKILL" && grep -q 'three times' "$SKILL" && pass "a stuck worker asks the coordinator before giving up" || fail "ask when stuck"
grep -q 'anything else only a person can supply' "$SKILL" && pass "R9 needs-human-input covers what it is used for" || fail "R9 reason 6 definition"
# Final pass
g() { grep -qF -- "$2" "$SKILL" && pass "$1" || fail "$1"; }
g "W1 gates run from the manifest, never from a hand-quoted string" 'run-gates.sh'
! grep -qF "sh -c '<test command> && <lint command>'" "$SKILL" && pass "W1 the hand-quoted gate line is gone" || fail "W1 hand-quoted gate line still there"
g "W4 the gate's own exit codes are not a red gate" 'gate-unavailable'
g "W5 every invoked skill is told the run is unattended" 'Unattended run: the approved brief'
g "W6 verification steps the user gave in a decision count" 'verification steps given under `## Decisions`'
grep -q 'id: orca' "$SKILL" && pass "W7 orca is declared (a worker asks the coordinator through it)" || fail "W7 orca not declared"
# Who runs the plan
g "X1 the plan executor is a choice" '| `--executor <session|codex>` |'
g "X2 session means this session runs the plan" 'superpowers:executing-plans'
grep -qF -- '--executor' "$ROOT/skills/review-and-execute/SKILL.md" && pass "X3 review-and-execute takes the same choice" || fail "X3 review-and-execute --executor"
# STAR issues #7 to #18: reports, the screen, status
for gone in '`--screen-checks <file>`' '`--fix-review <file>`' 'VERIFIED item=' 'SCREEN path=' 'FIXED item=' 'blocked: needs you at the screen' 'Screen-check mode' 'Fix mode ('; do
  grep -qF -- "$gone" "$SKILL" && fail "removed: $gone" || pass "removed: $gone"
done
for l in 'REPORTED item=' 'RESCOPE item=<item> reason=gate review=' 'DONE item=<item> pr=<url> head=<sha> review=<path>' 'STAR-ISSUE:' 'screen-lock.sh' 'renew --holder' 'Status: skipped (STAR owns the status)' 'deliverable: report' 'screen-busy' 'Decisions made without you' 'executor-model.sh' 'codex-gate.sh' 'post-pass' 'review-unavailable' 'red-first' 'progress/<item>.log' 'Mobbin' 'context7' 'frontend-design' 'auto: playwright' 'auto: computer-use' 'gate.maxRounds' 'Resume on an existing draft PR' 'was removed in v2'; do
  grep -qF -- "$l" "$SKILL" && pass "has: $l" || fail "has: $l"
done
# Issue #26
g "I1 shared ids are reserved, not counted" 'ids.sh'
g "Z10 --floor takes the number only" '`<highest>` is the number only (40 for D-040)'
grep -qF 'When `ids.sh` exits' "$SKILL" && grep -qF 'non-zero or is missing, escalate `needs-human-input`, and never take the next number yourself' "$SKILL" && pass "Z10 an ids.sh that cannot run is escalated" || fail "Z10 an ids.sh that cannot run is escalated"
g "Z11 Codex gets the ids in the plan" 'With `executor: codex`, reserve the ids while writing the plan and put them in it.'
# Issue #33
g "E1 an existing PR is updated, not opened" 'url=<url> existing'
g "E2 its body keeps the author's text" '<!-- juel:update -->'
g "E3 never rebased or force-pushed" 'never by rebasing'
# Issue #32
g "T32a Phase 5 runs targeted tests only" 'run only the tests for the files remediation changed'
g "T32b project instructions on test scope win" 'say something else about test scope, they win'
grep -qF 'run the `test` and `lint` commands resolved in Phase 4' "$SKILL" && fail "T32c the full run after remediation is gone" || pass "T32c the full run after remediation is gone"
# Issue #21
g "T21a the evidence names its head" 'evidence head=<sha>'
g "T21b a test-only fix reuses it" 'evidence reused from <evidence head> for <HEAD>'
g "T21c any doubt runs the whole phase" 'or any doubt about a file'
# Issue #24
g "T24a a cleanup entry can be handed off" 'handed-off'
g "T24b handed-off records are listed in the PR" 'Left for you to clean up'
g "T24c and held for the user" 'action=clean up <identifier> on <service>'
grep -qF 'handed-off' "$ROOT/references/local-e2e.md" && pass "T24d rule 3 knows handed-off" || fail "T24d local-e2e rule 3"
# Task 13-15 review, round 1
g "T21d a file the app loads is runtime whatever its extension" 'is runtime whatever its extension'
grep -qF 'docs, `*.md` and `docs/`' "$SKILL" && fail "T21e every Markdown file no longer counts as outside runtime" || pass "T21e every Markdown file no longer counts as outside runtime"
g "T21f the failure row defers to the reuse case" "re-run phase 6 in full (except step 6's evidence-reuse case)"
g "T24e a PR template gets the handed-off section" 'the only sections added to a template'
g "T24f an existing PR gets it inside its update section" '(plus **Left for you to clean up** when Phase 6 handed off an entry'
# Task C1 fix round 1
g "F1a a Phase 4 status under --unattended is a progress line, never a NOTE" 'a progress line and a terminal line, never a `NOTE`'
[ "$(grep -cF 'never a `NOTE`' "$SKILL")" -ge 2 ] && pass "F1b both Phase 4 places say never a NOTE" || fail "F1b both Phase 4 places say never a NOTE"
grep -qF ', a `NOTE`)' "$SKILL" && fail "F1c no Phase 4 status is a NOTE any more" || pass "F1c no Phase 4 status is a NOTE any more"
g "F2 a round with no accepted finding skips the fix and runs the next round" 'No finding accepted: skip the plan, the executor, the tests, Phase 6, the commit and the push'
g "F3a the round cap comes before any fix" 'go straight to step 5, before any fix'
g "F3b a fix round runs one regression gate" 'the one regression gate of the round'
g "F3c its evidence is reused when only non-runtime files changed" 'is outside the runtime, as its step 6 defines it'
grep -qF 'then the regression gate through the gate lock' "$SKILL" && fail "F3d the second regression run is gone" || pass "F3d the second regression run is gone"
g "F4a codex-failed covers a gate-loop fix" 'or in a gate-loop fix'
g "F4b review-unavailable covers post-pass" '`post-pass` printed `ERROR` twice, a minute apart'
g "F6a the screen lock is for the visible screen" 'Before launching an app you will drive on the visible screen'
g "F6b a lapsed lock is handled like exit 65" 'printing `free` (the lock lapsed)'
g "F7a a failing executor-model.sh counts as default" 'counts as `default <why>`'
g "F7b Phase 5 passes on what ran" 'or `--executor session` when this session ran the plan'
g "F8 a person: check runs its automated part" 'citing the person-only step the owner did before go'
g "F9 without a star block the run ends with a plain DONE" 'then ends with `DONE item=<item> pr=<url> head=<sha>`'
g "F10 the progress folder is created first" 'mkdir -p <star.home>/progress'
g "F11 the unanswered-question sentence ends with a period" '`unanswered-question`. A step that needs a person'
# Final fixes C-3: only a run under a star: brief has a star.home, so only it creates the folder and keeps the log
g "C3a the progress paragraph applies under a star: brief" '**Progress.** Under a `star:` brief, STAR judges this run by its progress'
g "C3b a run without a star: brief keeps no progress log" 'A run without a `star:` brief has no `star.home` and keeps no progress log.'
# Progress step tokens (spec 5, feeds #70)
g "P1a a progress line carries a step token" '"<step>" "<one line>"'
for t in '| `phase<N>` |' '| `executor` |' '| `live-check` |' '| `regression-gate` |' '| `gate-r<k>` |' '| `post-pass` |' '| `sync` |' '| `report` |'; do
  grep -qF -- "$t" "$SKILL" && pass "P1b token row $t" || fail "P1b token row $t"
done
grep -qF '"<phase or round>"' "$SKILL" && fail "P1c the free-form step field is gone" || pass "P1c the free-form step field is gone"
g "P1d a gate round's progress line names its round" 'Append a progress line with the step `gate-r<k>`.'
# Issue #60: fixed NOTE lines are reported on top of the one free NOTE
g "N60a fixed NOTE lines do not use up the free NOTE" 'plus the fixed `NOTE:` lines this file names'
g "N60b an unattended preflight does not stop on the executor skill" 'under `--unattended` not a STOP'
# Issues #63, #66, #71: the gate round from the worker's side
g "G66a only verdict files count toward the round" 'Only those verdict files count'
g "G66b an ERROR keeps the round number" 'an `ERROR` leaves no `<item>-r<k>.md`, so the round number does not move'
g "G63a the gate gets the evidence folder" '--evidence <the Phase 6 evidence directory>'
g "G63b the manifest names the evidence folder" '"evidenceDir": "<the evidence directory>"'
g "G63d a resumed run reads the folder from the manifest and drops a missing one" 'leave `--evidence` out: a missing'
g "G71a the round streams and only the verdict line is read" 'read only the last line of its output'
g "G64a a gate-down line is quoted whole" 'quoted whole: an `ERROR gate-down'
# Issue #61: a criterion accepted with a residual
g "R61a the verdict exists" '`ACCEPTED-RESIDUAL`'
g "R61b it needs a decision record that names a follow-up" 'accepts the residual and names a follow-up spec item'
g "R61c the worker asks before escalating" 'whether it accepts the criterion with that residual'
g "R61d the PR body carries it" '`## Accepted residual`'
g "R61e the report carries it" 'NOTE: accepted residual <criterion>: <follow-up path>'
g "R61f it is a fixed NOTE" '`NOTE: accepted residual'
g "R61g never written as PASS" 'never written as PASS'
# Issue #69: ready at the final SAFE round
g "Y69a the build marks the PR ready after post-pass" 'mark the PR ready: `gh pr ready <url>`'
g "Y69c the progress table has ready" '| `ready` |'
g "Y69d the DONE row says ready" 'and it is marked ready'
grep -qF 'It is marked ready once, by the babysit stage, after the gate passed.' "$SKILL" && fail "Y69e babysit no longer marks every PR ready" || pass "Y69e babysit no longer marks every PR ready"
# Issue #56: one instruction for the report's shape
g "W56a the worker_done body is the report lines only" 'The `worker_done` body is these report lines and nothing else.'
g "W56b it overrides Orca's preamble" "It overrides any request for a prose summary, Orca's worker preamble included."
# Issue #55: research MCPs
g "M55a the settings include mcps" 'and its `mcps`'
g "M55b mcps names what STAR found" '`needs-sign-in`'
g "M55c Mobbin cites the screen or flow URL" 'cite the screen or flow URL'
g "M55d only tools your own session lists" 'only when your own session lists its tools'
# Issue #74
g "EL16 the screen lock rule points to juel:verify's Electron row" "as \`juel:verify\`'s Electron row says) takes none either"
g "EL17 Phase 6 runs hidden-window checks through juel:verify's Electron row" "\`juel:verify\`'s Electron row: a hidden dev build driven over CDP"
grep -q 'window that paints' "$SKILL" && fail "EL18 no 'window that paints' description left" || pass "EL18 no 'window that paints' description left"
# lane f: the worker skills carry, resume, scope, and read decisions (#77, #78, #81, #83, #89, #90)
g "L77a the executor resumes from the shared ledger" '`<repo root>/.superpowers/sdd/<plan basename without .md>/progress.md`'
g "L77b the ledger is git-ignored before the first dispatch" 'git rev-parse --git-path info/exclude'
g "L77c a capacity retry needs no hand-written resume prompt" 'never write a resume prompt by hand'
g "L78a the scope check runs after the plan" 'sh <scope-check.sh> <the plan> <that sha>'
g "L78b out-of-scope files are restored in one commit" '`revert: out-of-scope edits in <files>`'
g "L78c every plan task names its files" 'Every task has a `**Files:**` block naming each file it changes'
g "L81a a gate-loop fix plan carries a Base line" '`**Base:** spec implemented at <the full head>; apply only the tasks below.`'
g "L81b a Phase 6 loop-back plan carries one" '`**Base:** spec implemented at <the evidence head>; apply only the tasks below.`'
g "L81c a resumed build's plan carries one" 'spec implemented at <the branch head'
g "L81d the in-session run is told the Base line wins" "The plan's Base line overrides its Spec: apply the tasks, and do not re-check the spec for completeness."
g "L78d the gate loop runs the scope check" "(Phase 4's line, its session tasks, its capacity rule and its scope check)"
g "L83a decisions are read after every background step" 'after every background step returns, before choosing the next step'
g "L83b through orca's unread messages" 'orca orchestration check --unread --json'
g "L89a the gate lock line takes the progress log" '[--progress <star.home>/progress/<item>.log]'
g "L89b never inside a plan the executor runs" 'Never put `--progress` in a plan the executor runs'
g "L89c the progress row says gate-lock writes the wait" '`gate-lock.sh --progress` writes this step itself every 10 minutes'
g "L90a a red fixed outside runtime does not count" 'A red does not count toward the two when the fix'
g "L90b at most two refunds between green gates" 'At most two such reds are refunded between two green gates'
# fix-1: R4 the gate lock is one file per user, so under a star: brief the holder names the project (#76)
g "R4a a star: brief's gate-lock holder carries the project" '--holder "<star.project>/<item>"'
g "R4b a run without a star: brief keeps the item as the holder" 'The holder is `"<item>"`, except under a `star:` brief'
# lane f: gate once per PR, gate-lock slots, dependencies, messages, outside-merged, name forms (#97, #99, #102, #105, #106, #107)
g "L97a gate-lock waiters take a ticket" 'Waiters take a ticket. With one slot'
g "L97b the shared slot count is set with --slots" '`sh <gate-lock.sh> --slots <n>` (1 to 4) sets the slot count'
g "L97c only the owner changes the slots" 'Only the owner changes it: never run `--slots` from this skill or a plan.'
g "L97d exit 75 means the queue did not move" 'means the queue ahead of it did not move for its whole'
grep -qF '`/tmp/juel.gate.<uid>.lock`; nothing to' "$SKILL" && fail "L97e the lock is no longer nothing to configure" || pass "L97e the lock is no longer nothing to configure"
g "L97f gates overlap only when the owner raised the slots" 'so two workers never run heavy test or build gates at once unless the owner raised'
g "L102a the gate-once paragraph" '**Gate once per PR.** The full regression gate (every gate in the manifest) and every Phase 6 live'
g "L102b a later push runs the sweep through the gate lock" '-- sh <run-gates.sh> <gate manifest> --root <repo root> sweep`.'
g "L102c the sweep is that push's one regression gate" 'The sweep is that push'"'"'s one regression gate: a red'
g "L102d a live check runs again only for touched runtime code" 'A Phase 6 live check runs again only for a criterion whose runtime code the change touched.'
grep -qF 'runs the tests for the files the conflict resolution' "$SKILL" && fail "L102e a base-only merge push no longer tests only the conflict resolution" || pass "L102e a base-only merge push no longer tests only the conflict resolution"
g "L102f a project rule that asks for more wins" "unless the project's own rule (its \`CLAUDE.md\` or \`AGENTS.md\`) asks"
g "L102g the merge state is read after every push" 'read `gh pr view <pr> --json mergeable,mergeStateStatus`'
g "L102h missing checks are never a pass" 'Missing checks are never read as a pass.'
g "L102i no CI on a DIRTY head is a fixed NOTE" '`NOTE: no CI ran on head <sha7> (PR DIRTY)` (see "Gate once per PR")'
g "L102j the gate manifest carries sweep" '(`test`, `lint`, `typecheck`, `build`, `sweep`;'
g "L102k Phase 4 resolves the sweep" 'then `.sweep`: a command that runs each test file the resolved `test` registers'
g "L102l Phase 5 points to the rule" 'step 5, before the PR (see "Gate once per PR")'
g "L102m the gate loop follows the rule" 'then gate it as "Gate once per PR" says'
grep -qF 'run the tests for the files it changed, then Phase 6' "$SKILL" && fail "L102n the gate loop no longer runs Phase 6 again" || pass "L102n the gate loop no longer runs Phase 6 again"
g "L102o an UNKNOWN merge state is read again" 'is read again up to 3 times, 10 seconds apart.'
g "L102p a merge state still UNKNOWN adds no NOTE" 'Still `UNKNOWN`, it cannot tell: add no NOTE.'
g "L105a missing dependencies are checked before the first dispatch" '**Dependencies.** Under `--unattended`, before the first dispatch (Codex or this session), check'
g "L105b the check is run-gates.sh's own rule" 'folder above it up to the repo root (`run-gates.sh` makes the same check for a gate that runs a JS'
g "L105c the install runs in the background, outside the gate lock" 'and not through `gate-lock.sh`'
g "L105d a failed install is gate-unavailable" 'reason=gate-unavailable needs=dependencies did not install: <one line>'
g "L105e resolution still installs and runs nothing" 'resolution still installs and runs nothing'
g "L105f the resolution sentence is unchanged" 'it must not install or run'
g "L105g exit 71 for missing dependencies installs once, then reruns" '`dependencies are not installed`: run the resolved `commands.install` once (Phase 4'"'"'s'
g "L105h a second 71 is gate-unavailable" 'a second 71 is `gate-unavailable`'
g "L105i the escalation list names the failed install" 'dependency install failed (Phase 4'"'"'s "Dependencies")'
g "L99a messages are read only with --unread --json or --peek --json" 'Read messages only with `--unread --json` (or `--peek --json` to'
g "L99b a plain check prints only subjects and marks them read" 'A plain `orca orchestration check` prints only the subjects and still'
g "L99c a consumed body is read back with --all --json" 'run `orca orchestration check --all --json` and read the bodies.'
grep -oE 'orchestration check( --?[a-z-]+)+' "$SKILL" | grep -vqF -- '--json' && fail "L99d every orchestration check with flags carries --json" || pass "L99d every orchestration check with flags carries --json"
g "L106a an outside-merged path is never restored" 'An `outside-merged <path>` line is never restored'
g "L106b restoring it would drop the base's change" 'restoring it from that sha would drop the base'"'"'s'
g "L106c it is reported with a fixed NOTE" 'report every such path in one fixed line, `NOTE: scope outside-merged <path>[, <path> ...]`'
g "L106d the NOTE is in the fixed list" '`NOTE: scope outside-merged <path>[, <path> ...]` line naming every path Phase 4'"'"'s scope check did not restore'
g "L106e run interactively it goes in the checkpoint" 'run interactively, name it in this phase'"'"'s checkpoint'
g "L107a a task creating a checked name names the check" 'names that check as its verification command. The check runs before the task'"'"'s commit.'
g "L107b the checker wins over a brief's name form" 'project'"'"'s own checker rejects (a pretest checker, a lint rule), the checker wins.'
g "L107c the worker says so in its one NOTE" 'say so in your one `NOTE: <one line>`.'
# fix: the install step names a package.json that declares dependencies (#105)
g "F105a the install step is for a package.json that declares dependencies" 'at the repo root, or in a manifest gate'"'"'s `cwd`, that declares dependencies (a non-empty'
g "F105b it names the four dependency keys and workspaces" '`dependencies`, `devDependencies`, `optionalDependencies` or `peerDependencies`, or a `workspaces`'
g "F105c it counts node_modules, .pnp.cjs and .pnp.js as installed" 'key), with no `node_modules` folder, no `.pnp.cjs` and no `.pnp.js` file in that folder or any'
grep -qF 'with no `node_modules` folder and no `.pnp.cjs`' "$SKILL" && fail "F105d the old condition (any package.json) is gone" || pass "F105d the old condition (any package.json) is gone"
# fix: strict arrival order holds with one gate slot only (#97)
g "F97a ship-ticket: strict arrival order is for one slot, the default" 'Waiters take a ticket. With one slot (the default), they are served in strict arrival'
g "F97b ship-ticket: with more slots the first waiters race for a freed slot" 'With more slots, the first waiters in the queue race for a freed slot.'
grep -qF 'Waiters take a ticket and are served in arrival order' "$SKILL" && fail "F97c ship-ticket: arrival order is no longer unqualified" || pass "F97c ship-ticket: arrival order is no longer unqualified"
# fix: one NOTE line names every outside-merged path (#106)
g "F106a the fixed NOTE list has one outside-merged line naming every path" '`NOTE: scope outside-merged <path>[, <path> ...]` line naming every path Phase 4'"'"'s scope check did not restore'
g "F106b Phase 4 reports every such path in one fixed line" 'report every such path in one fixed line, `NOTE: scope outside-merged <path>[, <path> ...]`;'
grep -qF 'NOTE: scope outside-merged <path>`' "$SKILL" && fail "F106c no outside-merged NOTE is per path any more" || pass "F106c no outside-merged NOTE is per path any more"
# lane f: a base-only merge push runs the sweep, a moved base is merged before the round, the executor link is current (#111, #113, #118)
g "L111a a base-only merge push runs the sweep" '2. A push that only merges the base branch in runs the sweep, through the gate lock as item 1'
g "L111b after a clean merge too" 'runs it, after a clean merge too. A red sweep keeps the merge: the fix is a push of the worker'"'"'s'
g "L111c the fix of a red sweep is a push of the worker's own changes" 'own changes, and item 1 applies to it.'
grep -qF 'and none after a clean merge' "$SKILL" && fail "L111d no base-only merge push skips the tests" || pass "L111d no base-only merge push skips the tests"
g "L113a a base-moved round merges the base before it runs" '6. `ERROR base-moved …`: the base changed a file this branch changes, so the round did not run.'
g "L113b the merge follows babysit's Phase 4 step 1" 'Fetch the base and merge it in as `juel:babysit-pr`'"'"'s Phase 4 step 1 does'
g "L113c then the same round runs again, not as an ERROR retry" 'the same round again. This is not an `ERROR` retry: it never counts toward a second `ERROR`, and'
g "L113d it casts no maxRounds vote" 'it casts no vote toward `gate.maxRounds`.'
g "L113e any other ERROR still waits 10 minutes" 'Any other `ERROR …`: wait 10 minutes (foreground waits of at most 540 s) and run the same round once more'
g "L113f review-unavailable never counts a base-moved round" 'An `ERROR base-moved` never counts: the gate loop'"'"'s step 6 merges the base and runs the round again.'
g "L118a the executor check compares the link with this plugin's copy" 'cmp -s "${CODEX_HOME:-$HOME/.codex}/skills/claude-plan-executor/SKILL.md" <plugin root>/assets/codex-skills/claude-plan-executor/SKILL.md'
g "L118b right before each dispatch it checks that the skill is current" 'Right before the line, check that the skill is current:'
g "L118c a link into another version's copy fails it" 'link into another version'"'"'s copy, which would run an older executor.'
grep -qF 'test -f "${CODEX_HOME:-$HOME/.codex}/skills/claude-plan-executor/SKILL.md"' "$SKILL" && fail "L118d no test -f check of the executor is left" || pass "L118d no test -f check of the executor is left"
g "L118e the Preflight row runs the same check" '| claude-plan-executor | skill | HARD | `cmp -s "${CODEX_HOME:-$HOME/.codex}/skills/claude-plan-executor/SKILL.md" <plugin root>/assets/codex-skills/claude-plan-executor/SKILL.md`'
g "L118f a failing check under --unattended relinks once" '`--unattended`: relink once with `node <plugin root>/scripts/link-agent-skills.mjs` and check'
# #122: the build never pings the hosted reviewer; the ready mark starts its run
g "L122a the build never pings or comments to the hosted reviewer (#122)" 'The build never pings or comments to the hosted reviewer on the PR at any point (no'
g "L122b marking ready is the only thing that starts its run (#122)" '`@greptileai`, no review request): marking the PR ready is the only thing that starts its run,'
# #123: progress lines come only from the step they name
g "L123a a progress line comes only from its own step (#123)" 'A progress line is written only by the step it names, at that step, never by a background or'
g "L123b never from a detached timer loop (#123)" 'detached timer loop the worker starts: such a timer keeps writing after the turn it belongs to'
g "L123c gate-lock.sh --progress stays the one timer writer (#123)" 'moving (#123). `gate-lock.sh --progress` stays the one writer on a timer, since it lives only as'
g "L122c a ping would start a second run (#122)" 'and a ping on top of it would start a second run on the same head (#122). A PR that is'

R126="Outside babysit's Phase 4 sync before \`READY\` and STAR's \"Sync after the base moved\", a worker merges the base in only when the PR is CONFLICTING or a gate round refuses with \`ERROR base-moved\`, never otherwise."
R128a="Each review agent writes its scratch files only under \`<scratchpad>/review-<agent>/\` (\`<agent>\` the agent's name), never in the build's scratchpad root: tell every agent so in its prompt."
R128b="A base snapshot kept for a base run lives only at \`<scratchpad>/ship-base-<full sha>/\` and is made read-only (\`chmod -R a-w\`) once written; before trusting a base run on it, confirm that a token only the fix adds is absent from it (\`grep -rF \"<token>\" <snapshot>\` prints nothing)."
R131b="For each accepted \`[P0]\` or \`[P1]\` finding, the fix searches the branch for every other site of the same pattern and fixes them all in the same round, and its \`-fix.md\` line names the sites (\`Fixed in <sha>. Sites: <path:line>, <path:line>.\`)."
S126="An \`existingPr\` brief's first merge (\"An existing PR\") is the build's start, not a later sync."
has "#126 the one base-merge rule" "$R126"
has "#126 an existingPr's first merge is the build's start" "$S126"
has "#128 each review agent writes under its own scratch folder" "$R128a"
has "#128 a base snapshot is named by its sha and read-only" "$R128b"
has "#131 the fix covers every site of the pattern" "$R131b"
has "#141 the Codex prompt runs only the plan's commands" 'Run only the commands the plan names, never the full suite or a build.'

# lane c: #143 a stalled gate is gate-unavailable at once; #145 anchored ignore entries, and a planned file git ignores stops the build
has "C143a exit 125 is a stalled gate, with its line" 'Exit 125 is a stalled gate, with this line on stderr: `gate-lock.sh: stalled, the command printed nothing for <n> s and was stopped`.'
has "C143b a stalled gate is not red and not run again" 'It is not red and it is not run again: it is the `gate-unavailable` escalation at once, with `needs=stalled gate: <the stalled line>`.'
has "C143c the escalation list names a stalled gate" 'or 125 (a stalled gate: the command printed nothing for `--idle-max` seconds and was stopped)'
has "C143d needs= for a stalled gate" 'for a stalled gate, `stalled gate: <the stalled line>`; for a failed install, `dependencies did not install: <one line>`.'
grep -qF 'stalled, the command printed nothing for' "$ROOT/skills/ship-ticket/gate-lock.sh" && pass "C143e gate-lock.sh prints the line the skill quotes" || fail "C143e gate-lock.sh prints the line the skill quotes"
has "C145a the ignore entries are anchored to the repo root" 'For each one that fails, the entry is anchored to the repo root, so no other folder of the same name is ignored'
has "C145b the entries it names" '(`/docs/superpowers/`, or `/docs/.superpowers/`), and `/.superpowers/`.'
has "C145c an exact unanchored line is replaced in the same change" 'In the same change, replace a line that is exactly `superpowers/` with the docs root'"'"'s entry, and a line that is exactly `.superpowers/` with `/.superpowers/`'
grep -qF 'unanchored so they match at any depth' "$SKILL" && fail "C145d the unanchored rule is gone" || pass "C145d the unanchored rule is gone"
g "C145e the ledger's exclude entry is anchored" "echo '/.superpowers/' >>"
IG=$(mktemp -d); trap 'rm -rf "$IG"' EXIT
(cd "$IG" && git init -q . && mkdir -p docs/superpowers/plans .superpowers/sdd tests/superpowers tests/.superpowers && touch docs/superpowers/plans/p.md .superpowers/sdd/l.md tests/superpowers/a.test.sh tests/.superpowers/x)
ig() { (cd "$IG" && git check-ignore -q --no-index -- "$1"); }
printf '/docs/superpowers/\n/.superpowers/\n' > "$IG/.gitignore"
ig docs/superpowers/plans/p.md && ig .superpowers/sdd/l.md && ! ig tests/superpowers/a.test.sh && ! ig tests/.superpowers/x && pass "C145f the anchored entries ignore the docs root and the scratch folder, and nothing under tests/" || fail "C145f the anchored entries in a scratch repo"
printf 'superpowers/\n.superpowers/\n' > "$IG/.gitignore"
ig tests/superpowers/a.test.sh && pass "C145g (control) the old unanchored line ignores tests/superpowers/" || fail "C145g (control) the old unanchored line"
has "C145h ship-ticket stops on a planned file git ignores" '**A planned file git ignores.** After every run of the plan in this skill'
has "C145i it reads the executor's failed-task line and stops before the scope check" 'look in the executor'"'"'s report for a line that begins `task <N> failed: planned file`. One such line means a file the plan needs never reached a commit: stop there, before the scope check.'
has "C145j the escalation it raises" '`ESCALATION item=<item> phase=<n> reason=codex-failed needs=planned file is git-ignored: <path> (<source>:<line>:<pattern>)`'
has "C145k never forced, moved or unignored" 'Never `git add -f` the file, move it, or edit an ignore file to carry on.'
has "C145l the escalation list names it" 'or a task fails on a planned file git ignores, whoever ran the plan'
has "C145m a session run stops the same way" 'a path a task'"'"'s `**Files:**` block names that `git add` refuses as ignored stops the run the same way'
grep -qF 'task <N> failed: planned file <path> is git-ignored' "$ROOT/assets/codex-skills/claude-plan-executor/SKILL.md" && pass "C145n the executor writes the line ship-ticket reads" || fail "C145n the executor writes the line ship-ticket reads"
# lane a: #153 git is asked first, an unattended run never edits .gitignore, an interactive edit is its own commit
has "A153a .gitignore is touched only when git does not ignore the paths" 'Make sure git ignores the docs root and the scratch folder, and touch `.gitignore` only when it does not (#153).'
has "A153b the two checks" 'run `git check-ignore -q -- <docsRoot as a path from the repo root>/x` and `git check-ignore -q -- .superpowers/x`'
has "A153c both ignored leaves .gitignore as it is" 'When both succeed, leave `.gitignore` as it is, an unanchored line included'
has "A153d unattended writes info/exclude, never .gitignore" 'Under `--unattended`, append it to `$(git rev-parse --git-path info/exclude)`, never to `.gitignore`'
has "A153e an interactive edit is its own commit" 'Commit that change alone, right away, as `chore: ignore the docs root and the scratch folder`'
grep -qF 'Add each one that is absent.' "$SKILL" && fail "A153f the unconditional add is gone" || pass "A153f the unconditional add is gone"
printf 'superpowers/\n' > "$IG/.gitignore"
(cd "$IG" && git check-ignore -q -- docs/superpowers/x) && pass "A153g (control) an unanchored line already ignores the docs root, so Phase 2 leaves it" || fail "A153g (control) unanchored line"
: > "$IG/.gitignore"
printf '/docs/superpowers/\n/.superpowers/\n' >> "$IG/.git/info/exclude"
(cd "$IG" && git check-ignore -q -- docs/superpowers/x && git check-ignore -q -- .superpowers/x) && [ ! -s "$IG/.gitignore" ] && pass "A153h (control) info/exclude ignores both with .gitignore untouched" || fail "A153h (control) info/exclude"
has "A153i run interactively, the #145 repair still runs" 'Run interactively, the one exception is the #145 repair: when `git check-ignore -v -- <path>` shows the match comes from a `.gitignore` line that is exactly `superpowers/` or `.superpowers/`, make the second bullet'"'"'s replacement below, as its lone commit.'
grep -qx 'product.' "$SKILL" && fail "A153j no stray wrapped line is left in Phase 2" || pass "A153j no stray wrapped line is left in Phase 2"
# lane f: #160 a harness beside a deliverable is tooling, graded for safety only
has "TL160f the build writes the tooling file beside the gate manifest" '`<item>-tooling.md` in the folder of the gate manifest (the folder of the file `star.gates` names, `<HOME_DIR>/gates/<project>/`; one path per line)'
! grep -qF '<star.gates>/<item>-tooling.md' "$SKILL" && pass "TL160f2 no tooling file under the manifest's own path" || fail "TL160f2 tooling file under star.gates"
has "TL160g the threshold is 20 files never imported" '20 or more files under one folder that the deliverable'"'"'s runtime code never imports'
has "TL160h the cap line carries tooling=all" '`RESCOPE item=<item> reason=gate review=<the last review'"'"'s path> tooling=all`'
has "TL160i tooling=all when every blocking finding is in tooling" 'when that round'"'"'s `tooling=` equals `p0 + p1`'
# lane b: #157 quiet hours are gone
! grep -qiE 'quiet[ -]hours|quietHours|--quiet-hours|quiet-hours\.sh|quiet window' "$SKILL" && pass "Q157g ship-ticket has no quiet hours" || fail "Q157g quiet hours still in ship-ticket"
g "Q157h a resumed build on a ready PR posts its PASS at once" 'A resumed build on a ready PR posts its PASS comment at once.'
# audit lane f: Phase 6's evidence is proof only
has "F5 Phase 6 points to the evidence write rule" '(rule 5 of `references/local-e2e.md`)'
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
