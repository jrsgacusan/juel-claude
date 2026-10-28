#!/bin/sh
# Guards on the text of juel:yuki and the --yuki modes it drives, which cannot be tested by running code.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
Y="$ROOT/skills/yuki/SKILL.md"
O="$ROOT/skills/orca-ship-tickets/SKILL.md"
T="$ROOT/skills/ship-ticket/SKILL.md"
B="$ROOT/skills/babysit-pr/SKILL.md"
R="$ROOT/skills/receive-review-and-execute/SKILL.md"
W="$ROOT/references/work-source.md"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
# has <file> <name> <text>: the text is in the file once line breaks and repeated spaces are folded
has() { tr '\n' ' ' < "$1" | tr -s ' ' | grep -qF -- "$3" && pass "$2" || fail "$2"; }
for f in "$Y" "$O" "$T" "$B" "$R" "$W"; do [ -f "$f" ] || { echo "FAIL missing $f"; exit 1; }; done

# The skill loader replaces $0..$9 in a skill body with the invocation's arguments, and these take arguments.
for f in "$Y" "$O"; do
  if grep -nE '\$[0-9]' "$f"; then fail "$(basename "$(dirname "$f")"): no positional parameters"; else pass "$(basename "$(dirname "$f")"): no positional parameters"; fi
done

# yuki: the loop
has "$Y" "yuki: ticks on a session cron every 10 minutes" 'cron: "7-59/10 * * * *"'
has "$Y" "yuki: the cron prompt carries the owner token" 'prompt: "/juel:yuki tick <token>"'
has "$Y" "yuki: a tick that lost the token deletes its own job" '`CronDelete` the job whose prompt is `/juel:yuki tick <this token>`'
has "$Y" "yuki: says the 7-day limit" 'expires after 7 days'
has "$Y" "yuki: five slots by default" '5 by default'
has "$Y" "yuki: re-queries the source every tick" 'Repeat every entry in `sources` exactly as stored'
has "$Y" "yuki: spawns through orca-ship-tickets --yuki" '/juel:orca-ship-tickets --yuki YUKI_HOME <ref>'
has "$Y" "yuki: records each SPAWNED line" 'run `Y add <item> ref=<ref> path=<path> branch=<branch>'
has "$Y" "yuki: checks memory before spawning" '`Y host`. `low <x> GB` → spawn nothing this tick'
has "$Y" "yuki: only the sweep removes worktrees" 'Only `Y sweep` removes a worktree'
has "$Y" "yuki: the coordinator never merges" 'The coordinator never merges.'
has "$Y" "yuki: never asks in a tick" 'Never call `AskUserQuestion` in a tick.'
has "$Y" "yuki: asks what to work on at the start" '"What should yuki work on?"'

# yuki: dependencies
has "$Y" "yuki: an item starts only once its blockers merged" 'Never start an item before its blockers have merged.'
has "$Y" "yuki: Linear blockers come from relations" 'includeRelations: true'
has "$Y" "yuki: GitHub blockers come from issue dependencies" 'dependencies/blocked_by'
has "$Y" "yuki: sharing files is not a blocker" 'Sharing or touching the same files is not a blocker.'
has "$Y" "yuki: blockers are gated by the script" '`Y deps gate <candidates> --done <the done ones>`'
has "$Y" "yuki: outside blockers are asked of the tracker" '`Y deps external <candidates>`'
has "$O" "orca-ship-tickets: --yuki fetches and cuts from the remote base" 'pass `--base-branch <remote>/<base>` to every `worktree create`'

# orca-ship-tickets --yuki
has "$O" "orca-ship-tickets: --yuki asks nothing" 'Do not list, do not confirm, and do not ask'
has "$O" "orca-ship-tickets: --yuki prompt" '"$AGENT_PROMPT_PREFIX $REF --yuki $YUKI_HOME --item $NAME"'
has "$O" "orca-ship-tickets: SPAWNED line" 'SPAWNED item=<name> ref=<ref> path=<result.worktree.path> branch=<the renamed branch> terminal=<handle>'
has "$O" "orca-ship-tickets: SKIPPED line" 'SKIPPED item=<name> reason=<one line>'

# ship-ticket --yuki
grep -q '^## Yuki mode' "$T" && pass "ship-ticket: Yuki mode documented" || fail "ship-ticket: Yuki mode"
has "$T" "ship-ticket: --yuki takes the recommended path" 'take the recommended option yourself'
has "$T" "ship-ticket: --yuki uses the gate lock" '"Gate lock" in "Unattended mode" applies as written, with `--holder "<item>"`'
has "$T" "ship-ticket: --yuki opens the PR ready" 'open the PR ready for review, never as a draft'
has "$T" "ship-ticket: --yuki hands Phase 8 to babysit --yuki" '/juel:babysit-pr <pr-number> --yuki <home> --item <item> --gates-file <the manifest>'
has "$T" "ship-ticket: PARKED line" 'print `PARKED item=<item> reason=<reason>` as the last line'
has "$T" "ship-ticket: --yuki refuses --unattended" '`--yuki` with `--unattended` or `--brief` is refused'

# babysit-pr --yuki
grep -q '^## Yuki mode' "$B" && pass "babysit-pr: Yuki mode documented" || fail "babysit-pr: Yuki mode"
has "$B" "babysit-pr: merges only in Yuki mode" '**Never merge the PR**, except in "Yuki mode", and there only through its merge check.'
has "$B" "babysit-pr: merges on the exact head" 'gh pr merge <pr> --<method> --match-head-commit <headRefOid>'
has "$B" "babysit-pr: never an admin merge" "never \`--admin\` and never \`--auto\`"
has "$B" "babysit-pr: the bot reviews once" 'A bot reviews once, and is never asked for a second pass.'
has "$B" "babysit-pr: never merges on red" 'Never merge on red'
has "$B" "babysit-pr: waits for requested people" 'every such person'"'"'s latest review is `APPROVED` and none is still requested'
has "$B" "babysit-pr: MERGED line" 'print `MERGED item=<item> pr=<url>` as the last line'
has "$B" "babysit-pr: leaves its own worktree" 'never remove the one this session runs in'

# receive-review-and-execute --autopilot
has "$R" "receive-review: --autopilot decides ambiguous findings" 'An ambiguous finding is decided, not reported.'
has "$R" "receive-review: --autopilot still aborts unmergeable conflicts" 'still ends with `git merge --abort` and the `CONFLICT:` line'


# The nudge (#214)
has "$Y" "yuki: the tick nudges stuck workers" '**Nudge.** `Y nudge` prints at most one line per running worker'
has "$Y" "yuki: a read-only permission prompt gets Enter" '`nudged <item> permission: <command>`'
has "$Y" "yuki: another dialog is news once" '`prompt <item> new <kind>: <text>`'
has "$Y" "yuki: the status line carries the nudge" '[, nudged <refs>][, prompt <item>: <kind>; ...]'
has "$Y" "yuki: only nudge and unblock read worker screens" '`Y nudge` reads worker screens for dialogs; `Y unblock` reads them to check for an empty prompt'
has "$Y" "yuki: only the script judges what is read-only" 'Only the script decides whether a command is read-only'
has "$Y" "yuki: a dialog shows within a tick" 'not a `quiet` one 2 hours later'

# The unblock (#215)
has "$Y" "yuki: the tick unblocks after the nudge" '**Unblock.** `Y unblock`'
has "$Y" "yuki: an idle worker is resumed" '`resumed <item> idle <age> <step>`'
has "$Y" "yuki: a parked worker with a plan is resumed once" '`resumed <item> plan <path>`'
has "$Y" "yuki: unblock is opt-in" '`unblock: "merge"`'
has "$Y" "yuki: the unblock line" '`unblocking <item> <pr or ->`'
has "$Y" "yuki: a parked row un-parks" '`unparked <item> <step>`'
has "$Y" "yuki: follow-ups come first" '`Y queue`'
has "$Y" "yuki: the coordinator still never merges" 'The coordinator never merges.'
has "$Y" "yuki: --unblock command" '/juel:yuki --unblock merge|off'
has "$T" "ship-ticket: Resumed by yuki" '**Resumed by yuki.**'
has "$T" "ship-ticket: the unblock never merges on red" 'never on red'
has "$T" "ship-ticket: the unblock records the follow-up" 'append `followup <ref>`'
has "$T" "ship-ticket: a park carries its plan" 'end `<reason>` with ` plan=<path>`'
has "$B" "babysit-pr: a park carries its plan" 'end `<reason>` with ` plan=<path>`'
has "$W" "work-source: yuki's unblock files without a preview" 'Under `juel:yuki` with `unblock: "merge"`'
echo "---"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
