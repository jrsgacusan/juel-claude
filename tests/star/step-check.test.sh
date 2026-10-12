#!/bin/sh
# Runs skills/star/step-check.sh against a scratch STAR home: progress lines, gate run files with
# live and dead pids, verdict files, and a scratch worktree.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/star/step-check.sh"
TMP=$(mktemp -d)
LIVE_PID=
trap '[ -n "$LIVE_PID" ] && { kill "$LIVE_PID"; wait "$LIVE_PID"; } 2>/dev/null; rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
[ -f "$SCRIPT" ] || { echo "FAIL step-check.sh missing"; exit 1; }
H="$TMP/home"; R="$H/reviews/app"; mkdir -p "$R" "$H/progress"
printf '{"project": {"name": "app"}, "quietHours": null}\n' > "$H/star.json"
NOW=2026-10-12T12:00:00Z
# ago <minutes>: the ISO time that many minutes before NOW
ago() { python3 -c 'import sys,datetime; t=datetime.datetime(2026,10,12,12,0,tzinfo=datetime.timezone.utc)-datetime.timedelta(minutes=int(sys.argv[1])); print(t.strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
# age <minutes> <file>: the file was last changed that many minutes before NOW
age() { python3 -c 'import os,sys,datetime; t=(datetime.datetime(2026,10,12,12,0,tzinfo=datetime.timezone.utc)-datetime.timedelta(minutes=int(sys.argv[1]))).timestamp(); os.utime(sys.argv[2],(t,t))' "$1" "$2"; }
# say <minutes ago> <token> <text>: the item's newest progress line
say() { printf '%s %s %s\n' "$(ago "$1")" "$2" "$3" > "$H/progress/IT.log"; age "$1" "$H/progress/IT.log"; }
# runfile <k> <pid> <log minutes ago>: a gate round's run file, started 60 minutes ago
runfile() {
  printf '{"pid": %s, "gate": %s, "agent": "codex", "model": "gpt-6.1-sol", "attempt": 1, "started": "%s", "log": "%s"}\n' \
    "$2" "$2" "$(ago 60)" "$R/IT-r$1.log" > "$R/IT-r$1.run"
  : > "$R/IT-r$1.log"; age "$3" "$R/IT-r$1.log"; age 60 "$R/IT-r$1.run"
}
clean() { rm -f "$R"/IT-* "$H/progress/IT.log"; }
SC() { STAR_NOW=$NOW sh "$SCRIPT" --item IT --home "$H" "$@"; }
# t <name> <expected line> <args...>
t() { name=$1 exp=$2; shift 2; got=$(SC "$@"); if [ "$got" = "$exp" ]; then pass "$name"; else fail "$name (got: $got)"; fi; }
sleep 600 & LIVE_PID=$!
sleep 0 & DEAD_PID=$!; wait "$DEAD_PID" 2>/dev/null

t "no progress log is unknown" "unknown no-progress-source" --state building

# a gate round that runs
clean; say 40 gate-r2 "round 2"; runfile 2 "$LIVE_PID" 5
t "a live gate whose log grows is ok, though its progress line is old" "ok gate-r2" --state building
clean; say 40 gate-r2 "round 2"; runfile 2 "$LIVE_PID" 25
t "a live gate whose log is silent 20 min gets an instruction" \
  "act gate-r2 log silent 25 min -- STAR: gate round 2 has printed nothing for 25 min (pid $LIVE_PID/$LIVE_PID). Stop it and run round 2 again; it falls back to Claude by itself." --state building
t "an instruction sent 5 min ago is waited on" "note gate-r2 instructed 5 min ago: log silent 25 min" --state building --asked "$(ago 5)"
# a gate that died
clean; say 40 gate-r2 "round 2"; runfile 2 "$DEAD_PID" 12
t "a dead gate with no verdict and nothing written for 10 min is restarted" "restart gate-r2 gate process gone" --state building
clean; say 40 gate-r2 "round 2"; runfile 2 "$DEAD_PID" 5
t "a gate that died 5 min ago gets time" "ok gate-r2" --state building
clean; say 40 gate-r2 "round 2"; runfile 2 "$DEAD_PID" 30; echo "VERDICT" > "$R/IT-r2.md"; age 20 "$R/IT-r2.md"
t "a dead gate that left its verdict reads as a verdict unread, not a restart" \
  "act gate-r2 verdict unread -- STAR: round 2's verdict is at $R/IT-r2.md. Read its first line and continue." --state building
# a verdict nobody read
clean; say 40 gate-r2 "round 2"; echo "VERDICT" > "$R/IT-r2.md"; age 20 "$R/IT-r2.md"
t "a verdict unread for 15 min gets an instruction" \
  "act gate-r2 verdict unread -- STAR: round 2's verdict is at $R/IT-r2.md. Read its first line and continue." --state building
t "still unread 15 min after the instruction is a restart" "restart gate-r2 verdict unread after an instruction" --state building --asked "$(ago 16)"
t "unread 5 min after the instruction is waited on" "note gate-r2 instructed 5 min ago: verdict unread" --state building --asked "$(ago 5)"
clean; say 40 gate-r2 "round 2"; echo "VERDICT" > "$R/IT-r2.md"; age 10 "$R/IT-r2.md"
t "a verdict 10 min old is activity: ok" "ok gate-r2" --state building
clean; say 40 gate-r2 "round 2"
t "a gate step with no run and no verdict past the deadline is told to run the round" \
  "act gate-r2 no progress 40 min -- STAR: gate round 2 shows no run and no verdict after 40 min. Run codex-gate.sh for round 2 now; an ERROR keeps the round number, so rerun the same round." --state building

# the deadline row, per step
clean; say 40 phase6 "live check L3"
t "a phase past the deadline gets its instruction" \
  "act phase6 no progress 40 min -- STAR: IT has written no progress line for 40 min in phase 6. If a command is still running, append a progress line naming it; if nothing runs, continue phase 6 now." --state building
t "a longer deadline keeps it ok" "ok phase6" --state building --deadline 60
clean; say 5 phase6 "live check L3"
t "fresh progress is ok" "ok phase6" --state building
clean; say 40 wait-ci "wake: timeout"
t "waiting for CI past the deadline" \
  "act wait-ci no progress 40 min -- STAR: no wake for 40 min while you wait for CI. Run gh pr checks on the PR now and act on what it says." --state babysitting
clean; say 40 phase2 "wake: timeout"
t "a babysit waiting in Phase 2 past the deadline" \
  "act phase2 no progress 40 min -- STAR: no wake for 40 min while you wait for feedback in Phase 2. Run pr-state.sh on the PR once now and act on what it reports." --state babysitting
t "phase 2 of a build is a phase like any other" \
  "act phase2 no progress 40 min -- STAR: IT has written no progress line for 40 min in phase 2. If a command is still running, append a progress line naming it; if nothing runs, continue phase 2 now." --state building
clean; say 40 report "DONE"
t "a report that was never sent" \
  "act report no progress 40 min -- STAR: you have been at the report for 40 min. Send your worker_done report now, as the report lines your skill names." --state building
clean; printf '%s Phase 6 live check\n' "$(ago 40)" > "$H/progress/IT.log"; age 40 "$H/progress/IT.log"
t "an unknown step gets the general check-in" \
  "act Phase no progress 40 min -- STAR checking in on IT: say in one line where you are. Waiting on a background command: keep waiting. Blocked or unsure: ask me with orca orchestration ask. Finished: send your worker_done report now." --state building
clean; say 40 executor "codex exec running"
t "an instruction older than the newest progress line is forgotten" \
  "act executor no progress 40 min -- STAR: the executor has changed nothing for 40 min. If codex exec still runs, keep waiting and append a progress line; if it exited, read its exit status and continue." --state building --asked "$(ago 50)"

# a worktree's commits and changed files are progress too
WT="$TMP/wt"; git init -q "$WT"
(cd "$WT" && echo a > a.txt && git add a.txt && GIT_AUTHOR_DATE=2026-10-12T10:00:00Z GIT_COMMITTER_DATE=2026-10-12T10:00:00Z git commit -q -m init)
clean; say 40 executor "codex exec running"
t "a clean worktree with an old commit is no progress" \
  "act executor no progress 40 min -- STAR: the executor has changed nothing for 40 min. If codex exec still runs, keep waiting and append a progress line; if it exited, read its exit status and continue." --state building --worktree "$WT"
echo b > "$WT/b.txt"; age 2 "$WT/b.txt"
t "an executor that changes files without progress lines is ok" "ok executor" --state building --worktree "$WT"

# the PR beside the step (#69, #70): a stub pr-state.sh that logs its arguments
cat > "$TMP/pr-state.sh" <<'EOF'
printf '%s\n' "$*" >> "$STUB_DIR/pr-calls"
cat "$STUB_DIR/pr.json"
EOF
HEADX=abc1234def5678abc1234def5678abc1234def56
PR=https://github.com/o/r/pull/30
# snap <draft> <checks> <hosted JSON> <merge>
snap() { printf '{"head":"%s","draft":%s,"checks":"%s","hosted":%s,"merge":"%s"}\n' "$HEADX" "$1" "$2" "$3" "$4" > "$TMP/pr.json"; }
SCP() { STAR_NOW=$NOW QUIET_NOW=$NOW STEP_CHECK_PR_STATE="$TMP/pr-state.sh" STUB_DIR="$TMP" sh "$SCRIPT" --item IT --home "$H" "$@"; }
tp() { name=$1 exp=$2; shift 2; got=$(SCP "$@"); if [ "$got" = "$exp" ]; then pass "$name"; else fail "$name (got: $got)"; fi; }
clean; rm -f "$TMP/pr-calls"; snap false green '"success"' clean; say 20 wait-hosted "wake: timeout"
tp "a babysit still waiting on a hosted pass that landed is told to judge it" \
  "act wait-hosted hosted review passed on abc1234 -- STAR: the hosted review passed on abc1234 and checks are green. Judge the review and report READY." \
  --state babysitting --pr "$PR" --hosted 'greptile-apps[bot]'
grep -qx "$PR --hosted greptile-apps\[bot\]" "$TMP/pr-calls" && pass "one pr-state.sh snapshot with the hosted reviewer, never --wait" || fail "pr-state.sh call ($(cat "$TMP/pr-calls"))"
tp "still waiting 15 min after the instruction is a restart" \
  "restart wait-hosted hosted review passed on abc1234, worker still waiting after an instruction" \
  --state babysitting --pr "$PR" --hosted 'greptile-apps[bot]' --asked "$(ago 16)"
say 20 phase2 "wake: timeout"
tp "a babysit waiting in Phase 2 on a hosted pass that landed is told to judge it too" \
  "act phase2 hosted review passed on abc1234 -- STAR: the hosted review passed on abc1234 and checks are green. Judge the review and report READY." \
  --state babysitting --pr "$PR" --hosted 'greptile-apps[bot]'
say 20 wait-hosted "wake: timeout"
snap false green '"pending"' clean
tp "a hosted review still running is ok" "ok wait-hosted" --state babysitting --pr "$PR" --hosted 'greptile-apps[bot]'
snap false green '"success"' clean; say 10 wait-ci "wake: timeout"
tp "a pass 10 min old gets the worker's next wake first" "ok wait-ci" --state babysitting --pr "$PR" --hosted 'greptile-apps[bot]'
snap false green '"none"' clean; say 5 ready "marked ready"
tp "a ready green PR with no hosted run is named" "note ready checks green, no hosted run on abc1234" --state building --pr "$PR" --hosted 'greptile-apps[bot]'
printf '{"project": {"name": "app"}, "quietHours": {"tz": "Asia/Manila", "start": "19:00", "end": "07:00"}}\n' > "$H/star.json"
tp "inside quiet hours nothing may be requested, so there is no note" "ok ready" --state building --pr "$PR" --hosted 'greptile-apps[bot]'
printf '{"project": {"name": "app"}, "quietHours": null}\n' > "$H/star.json"
snap true green '"none"' clean
tp "a draft gets no hosted run by design" "ok ready" --state building --pr "$PR" --hosted 'greptile-apps[bot]'
snap false green null clean
tp "with no hosted reviewer there is nothing to request" "ok ready" --state building --pr "$PR"
snap false pending '"none"' dirty; say 5 wait-hosted "wake: timeout"
tp "a babysat PR that conflicts is named" "note wait-hosted PR conflicts with its base" --state babysitting --pr "$PR" --hosted 'greptile-apps[bot]'
say 40 wait-hosted "wake: timeout"
tp "a stuck worker gets its instruction before the PR's note" \
  "act wait-hosted no progress 40 min -- STAR: no wake for 40 min while you wait for the hosted review. Read the PR's hosted status on its head now; when it reviewed the head, judge it and go on." \
  --state babysitting --pr "$PR" --hosted 'greptile-apps[bot]'
printf '{"error":"gh exited 1: boom"}\n' > "$TMP/pr.json"; say 5 wait-hosted "wake: timeout"
tp "a PR that cannot be read says nothing about the worker" "ok wait-hosted" --state babysitting --pr "$PR" --hosted 'greptile-apps[bot]'
rm -f "$TMP/pr-calls"; say 5 phase6 "live check"
tp "without --pr the PR is not read" "ok phase6" --state building
[ ! -f "$TMP/pr-calls" ] && pass "no pr-state.sh call without --pr" || fail "pr-state.sh called without --pr"
rm -f "$TMP/pr-calls"; say 40 gate-r2 "round 2"; runfile 2 "$LIVE_PID" 5
tp "a running gate round is ok without reading the PR" "ok gate-r2" --state building --pr "$PR" --hosted 'greptile-apps[bot]'
[ ! -f "$TMP/pr-calls" ] && pass "no pr-state.sh call while a gate round runs" || fail "pr-state.sh called during a gate round"

# usage
SC >/dev/null 2>&1; [ $? -eq 64 ] && pass "no --state is 64" || fail "no --state"
SC --state reviewing >/dev/null 2>&1; [ $? -eq 64 ] && pass "a state with no worker is 64" || fail "bad state"
SC --state building --asked yesterday >/dev/null 2>&1; [ $? -eq 64 ] && pass "an --asked that is not a time is 64" || fail "bad --asked"
SC --state building --deadline 0 >/dev/null 2>&1; [ $? -eq 64 ] && pass "a zero deadline is 64" || fail "zero deadline"
SC --state building --bogus x >/dev/null 2>&1; [ $? -eq 64 ] && pass "an unknown option is 64" || fail "unknown option"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
