#!/bin/sh
# A stand-in for orca in the dashboard's tests. Each call is one line in $FAKE_ORCA_DIR/orca-calls.log.
# terminal list prints $FAKE_ORCA_DIR/terminals.json (exit 1 when it is missing); terminal send
# fails when $FAKE_ORCA_DIR/send-fails exists.
printf '%s\n' "$*" >> "$FAKE_ORCA_DIR/orca-calls.log"
case "$1 $2" in
  "terminal list") cat "$FAKE_ORCA_DIR/terminals.json" 2>/dev/null || exit 1 ;;
  "terminal send") [ -f "$FAKE_ORCA_DIR/send-fails" ] && exit 1; echo '{"result":{"sent":true}}' ;;
  *) exit 64 ;;
esac
