#!/bin/sh
# Runs skills/ship-ticket/quiet-hours.sh with a fixed clock (QUIET_NOW, ISO UTC).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/skills/ship-ticket/quiet-hours.sh"
fails=0
[ -f "$SCRIPT" ] || { echo "FAIL quiet-hours.sh missing"; exit 1; }
# t <name> <expected output> <expected exit> <now> <window>
t() {
  out=$(QUIET_NOW="$4" sh "$SCRIPT" "$5" 2>/dev/null); rc=$?
  if [ "$out" = "$2" ] && [ "$rc" -eq "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got: '$out' rc=$rc)"; fails=$((fails + 1)); fi
}
t "always is inside at any time"            inside  0 2026-10-07T03:00:00Z always
t "ALWAYS in any case"                      inside  0 2026-10-07T15:00:00Z Always
t "same-day window, inside"                 inside  0 2026-10-07T10:30:00Z 09:00-17:00@UTC
t "same-day window, before"                 outside 0 2026-10-07T08:59:00Z 09:00-17:00@UTC
t "the end minute is outside"               outside 0 2026-10-07T17:00:00Z 09:00-17:00@UTC
t "the start minute is inside"              inside  0 2026-10-07T09:00:00Z 09:00-17:00@UTC
t "across midnight, late evening"           inside  0 2026-10-07T23:10:00Z 22:00-07:00@UTC
t "across midnight, early morning"          inside  0 2026-10-07T06:59:00Z 22:00-07:00@UTC
t "across midnight, midday"                 outside 0 2026-10-07T12:00:00Z 22:00-07:00@UTC
# 14:30 UTC is 22:30 in Manila (UTC+8)
t "the window's own time zone is used"      inside  0 2026-10-07T14:30:00Z 22:00-07:00@Asia/Manila
t "and outside it"                          outside 0 2026-10-07T03:00:00Z 22:00-07:00@Asia/Manila
# 17:00 UTC is 22:30 in Kolkata (UTC+5:30)
t "a half-hour offset"                      inside  0 2026-10-07T17:00:00Z 22:15-06:00@Asia/Kolkata
t "a half-hour offset, just before"         outside 0 2026-10-07T16:40:00Z 22:15-06:00@Asia/Kolkata
# US clocks go back on 2026-11-01: 06:30 UTC is 01:30 EST (the second 01:30 that night)
t "the night clocks change"                 inside  0 2026-11-01T06:30:00Z 01:00-02:00@America/New_York
t "equal ends are refused: say always"      ""      64 2026-10-07T12:00:00Z 22:00-22:00@UTC
t "an unknown time zone is refused"         ""      64 2026-10-07T12:00:00Z 22:00-07:00@Mars/Olympus
t "a missing time zone is refused"          ""      64 2026-10-07T12:00:00Z 22:00-07:00
t "an impossible hour is refused"           ""      64 2026-10-07T12:00:00Z 25:00-07:00@UTC
t "words are refused"                       ""      64 2026-10-07T12:00:00Z tonight
t "an empty window is refused"              ""      64 2026-10-07T12:00:00Z ""
sh "$SCRIPT" >/dev/null 2>&1; [ $? -eq 64 ] && echo "ok   no argument is exit 64" || { echo "FAIL no argument"; fails=$((fails + 1)); }
out=$(sh "$SCRIPT" always); [ "$out" = inside ] && echo "ok   works with the real clock" || { echo "FAIL real clock ($out)"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
