#!/bin/sh
# The STAR mod (hooks/register.tsx, spec 2026-10-15 §6). hooks.json keeps the SessionStart hook
# beside the module; plugin.json adds only the types and the three /config toggles; the band reads
# STAR's files with the columns and patterns ledger.sh and loops.sh use; and, on Claude Code 2.1.287
# or later, the plugin validates and the mod's own tests pass. With an older claude, or none, that
# last part is skipped with a pass line.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# hooks.json: the classic SessionStart hook exactly as before, and the module beside it
python3 - "$ROOT/hooks/hooks.json" 2> "$TMP/err" <<'PY' && pass "hooks.json keeps the SessionStart hook and names ./register.tsx" || fail "hooks.json: $(tail -1 "$TMP/err")"
import json, os, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
want = {"SessionStart": [{"matcher": "startup|resume|compact|clear", "hooks": [
    {"type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/star-session.sh\""}]}]}
assert d.get("hooks") == want, d.get("hooks")
assert d.get("modules") == ["./register.tsx"], d.get("modules")
assert os.path.isfile(os.path.join(os.path.dirname(sys.argv[1]), "register.tsx"))
PY

# plugin.json: still juel, plus the types and the three toggles
python3 - "$ROOT/.claude-plugin/plugin.json" 2> "$TMP/err" <<'PY' && pass "plugin.json adds the types and the star_band, star_guards and star_rm_guard toggles" || fail "plugin.json: $(tail -1 "$TMP/err")"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["name"] == "juel" and d["description"].startswith("Ticket-to-PR workflow skills"), d
assert "superpowers@claude-plugins-official" in d["dependencies"], d["dependencies"]
assert d["types"] == "./types/index.d.ts", d.get("types")
u = d["userConfig"]
assert sorted(u) == ["star_band", "star_guards", "star_rm_guard"], sorted(u)
assert all(u[k]["type"] == "boolean" for k in u), u
assert u["star_band"]["default"] is True and u["star_guards"]["default"] is True, u
assert isinstance(u["star_rm_guard"]["default"], bool), u
PY

(cd "$ROOT" && git check-ignore -q .claude-plugin/types/claude-code/index.d.ts) && pass "the engine's .claude-plugin/types/ is git-ignored" || fail ".claude-plugin/types/ is not ignored"

# parity: the band reads what ledger.sh and loops.sh write, so columns and patterns are the same text
python3 - "$ROOT" > "$TMP/parity.txt" <<'PY'
import ast, re, sys
root = sys.argv[1]
ledger = open(f"{root}/skills/star/ledger.sh", encoding="utf-8").read()
loops = open(f"{root}/skills/star/loops.sh", encoding="utf-8").read()
star = open(f"{root}/hooks/star.ts", encoding="utf-8").read()
cols = ast.literal_eval(re.search(r"^COLS = (\[.*?\])", ledger, re.S | re.M).group(1))
ts = re.search(r"export const LEDGER_COLS = \[(.*?)\] as const", star, re.S)
ts_cols = re.findall(r"'([^']*)'", ts.group(1)) if ts else None
print("COLS", "same" if cols == ts_cols else f"differ: {cols} != {ts_cols}")
for name in ("ITEM_RE", "ANSWER_RE", "COMMENT_RE"):
    py = re.search(rf'^{name} = re\.compile\(r"(.*?)"(?:, re\.IGNORECASE)?\)$', loops, re.M)
    ts = re.search(rf"^const {name} = /(.*)/i?$", star, re.M)
    if not py or not ts:
        print(name, "missing")
    else:
        print(name, "same" if py.group(1) == ts.group(1) else f"differ: {py.group(1)} != {ts.group(1)}")
py = re.search(r"^SECTIONS = (\(.*?\))", loops, re.M)
ts = re.search(r"^const SECTIONS = \[(.*?)\]", star, re.M)
same = py and ts and list(ast.literal_eval(py.group(1))) == re.findall(r"'([^']*)'", ts.group(1))
print("SECTIONS", "same" if same else "differ")
PY
for k in COLS ITEM_RE ANSWER_RE COMMENT_RE SECTIONS; do
  line=$(grep "^$k " "$TMP/parity.txt")
  [ "$line" = "$k same" ] && pass "parity: hooks/star.ts $k is STAR's own" || fail "parity: ${line:-$k not printed}"
done

# The plugin validates and the mod's own tests pass, on a Claude Code that loads mods
ver=$(claude --version 2>/dev/null | awk 'NR == 1 {print $1}')
if [ -z "$ver" ] || ! python3 -c 'import sys; v = tuple(int(x) for x in sys.argv[1].split(".")); sys.exit(0 if v >= (2, 1, 287) else 1)' "$ver" 2>/dev/null; then
  pass "skipped: claude ${ver:-not found} cannot load mods (2.1.287 or later)"
else
  # `validate .` checks the marketplace only; the manifest path checks the manifest and hooks.json
  (cd "$ROOT" && claude plugin validate --strict .claude-plugin/plugin.json) > "$TMP/validate.txt" 2>&1 \
    && grep -q 'register.tsx hooks: session.start' "$TMP/validate.txt" \
    && pass "claude plugin validate --strict passes the manifest and the hooks module" \
    || fail "plugin validate: $(tail -5 "$TMP/validate.txt")"
  (cd "$ROOT" && claude plugin validate --strict .) > "$TMP/market.txt" 2>&1 \
    && pass "claude plugin validate --strict passes the marketplace" || fail "marketplace validate: $(tail -5 "$TMP/market.txt")"
  # `claude plugin test` runs every *.test.ts under its folder, git-ignored ones included (docs/,
  # .worktrees/), so it runs on a copy that holds the mod and its tests only
  M="$TMP/mod"; mkdir -p "$M/tests"
  cp -R "$ROOT/.claude-plugin" "$ROOT/hooks" "$ROOT/types" "$M/" && cp -R "$ROOT/tests/mod" "$M/tests/mod"
  (cd "$M" && claude plugin test .) > "$TMP/test.txt" 2>&1 \
    && pass "claude plugin test: $(grep -E '^ *[0-9]+ pass' "$TMP/test.txt" | tr -s ' ' | sed 's/^ //')" \
    || fail "plugin test: $(grep -E '^\(fail\)|^ *[0-9]+ fail' "$TMP/test.txt" | head -5)"
fi

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
