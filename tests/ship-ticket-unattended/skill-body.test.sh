#!/bin/sh
# Guards on skills/ship-ticket/SKILL.md: unattended and brief modes for juel:star workers.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/ship-ticket/SKILL.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
if grep -nE '\$[0-9]' "$SKILL"; then fail "no positional parameters"; else pass "no positional parameters"; fi
for f in '--unattended' '--brief <path>' '--quiet-hours <HH:MM-HH:MM@tz>' '--executor-model <id|latest-<family>>' '--executor-effort <level>'; do
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
grep -q 'once at the start' "$SKILL" && pass "quiet window checked per action" || fail "quiet window per action"
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
grep -q '`always`' "$SKILL" && pass "quiet window can be always" || fail "always window"
# Stress test pass fixes
grep -q 'Nothing is asked at the terminal' "$SKILL" && pass "S4 no prompt survives unattended" || fail "S4 catch-all for prompts"
grep -q 'needs=verification steps' "$SKILL" && pass "S4 an empty checklist escalates" || fail "S4 empty checklist"
grep -q 'needs=browser verification of' "$SKILL" && pass "S4 no browser tool escalates" || fail "S4 browser fallback"
grep -q 'quiet-hours.sh' "$SKILL" && ! grep -q 'date +%H:%M' "$SKILL" && pass "S6 the quiet window is decided by the script" || fail "S6 quiet-hours.sh"
grep -q 'needs=a valid --quiet-hours window' "$SKILL" && pass "S6 an unreadable window stops the run at the start" || fail "S6 window validation"
grep -q 'gate-busy' "$SKILL" && pass "S15 a busy gate lock is bounded" || fail "S15 gate-busy"
grep -q 'the later one wins' "$SKILL" && pass "S12 contradictory decisions have an order" || fail "S12 decision precedence"
grep -q 'more than two `HELD` lines' "$SKILL" && pass "S11 held lines are aggregated" || fail "S11 HELD aggregate"
! grep -q 'JUEL_GATE_LOCK=<star.home>' "$SKILL" && grep -q '/tmp/juel.gate.<uid>.lock' "$SKILL" && pass "T1 one gate lock per user, no path to pass" || fail "T1 gate lock path"
grep -q 'A gate inside an invoked skill' "$SKILL" && pass "T8 gates inside invoked skills are covered" || fail "T8 nested gates"
grep -q 'anything but `inside` or `outside`' "$SKILL" && pass "T6 a broken quiet-hours check holds, never sends" || fail "T6 quiet helper failure"
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
g "F5a quiet-hours always does not wait for a PASS" 'action=post the codex PASS'
g "F5b and ends asking for the PASS to be posted" 'post the codex PASS on <url> when you are back'
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
g "Y69b not inside quiet hours, and no HELD line for it" 'leave the PR a draft and print no `HELD` line for it'
g "Y69c the progress table has ready" '| `ready` |'
g "Y69d the DONE row says ready" 'and it is marked ready (outside quiet hours)'
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
g "L78d the gate loop runs the scope check" "(Phase 4's line, its capacity rule and its scope check)"
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
g "L97a gate-lock waiters are served in arrival order" 'Waiters take a ticket and are served in arrival order'
g "L97b the shared slot count is set with --slots" '`sh <gate-lock.sh> --slots <n>` (1 to 4) sets the slot count'
g "L97c only the owner changes the slots" 'Only the owner changes it: never run `--slots` from this skill or a plan.'
g "L97d exit 75 means the queue did not move" 'means the queue ahead of it did not move for its whole'
grep -qF '`/tmp/juel.gate.<uid>.lock`; nothing to' "$SKILL" && fail "L97e the lock is no longer nothing to configure" || pass "L97e the lock is no longer nothing to configure"
g "L97f gates overlap only when the owner raised the slots" 'so two workers never run heavy test or build gates at once unless the owner raised'
g "L102a the gate-once paragraph" '**Gate once per PR.** The full regression gate (every gate in the manifest) and every Phase 6 live'
g "L102b a later push runs the sweep through the gate lock" '-- sh <run-gates.sh> <gate manifest> --root <repo root> sweep`.'
g "L102c the sweep is that push's one regression gate" 'The sweep is that push'"'"'s one regression gate: a red'
g "L102d a live check runs again only for touched runtime code" 'A Phase 6 live check runs again only for a criterion whose runtime code the change touched.'
g "L102e a base-only merge push tests only the conflict resolution" 'runs the tests for the files the conflict resolution'
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
g "L105b the check is run-gates.sh's own rule" 'file in that folder or any folder above it up to the repo root (the check `run-gates.sh` makes).'
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
g "L106c it is reported with a fixed NOTE" 'report it with the fixed line `NOTE: scope outside-merged <path>`'
g "L106d the NOTE is in the fixed list" '`NOTE: scope outside-merged <path>` per path Phase 4'"'"'s scope check did not restore'
g "L106e run interactively it goes in the checkpoint" 'run interactively, name it in this phase'"'"'s checkpoint'
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
