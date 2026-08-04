# Preflight render spec — authoring source of truth

This file is **not** read at runtime, for the same reason as
`references/strict-protocol.md`: no `SKILL.md` links to it, and progressive
disclosure (a sibling file loaded only if the model chooses to) cannot
deliver an "always render preflight this way" guarantee. It exists so that
Tasks 7–11 have one canonical spec to derive each skill's own `## Preflight`
dependency table from, and so that changing the render format later is a
diffable sweep across all 13 skills rather than an archaeology exercise.

## Preflight render spec

Emitted immediately after the skill line, before the phase checklist.

```
Preflight: <n>/<total> OK<, N missing (hard)><, M degraded>
  ✗ <label> — HARD — <why>       → <install hint>
  ! <label> — SOFT — <fallback>
  ? <label> — HARD — <why>       → cannot verify; will fail at <point> if absent
→ <PROCEED|DEGRADE|STOP>: <one-line consequence>
```

| Symbol | Meaning | Printed individually? |
|---|---|---|
| `✓` | verified present | No — rolled into the `n/total` count |
| `✗` | verified absent | Yes |
| `!` | absent or unknown, SOFT | Yes, with its literal declared `fallback` |
| `?` | cannot be verified, HARD | Yes, always — never claim `✓` for an unverifiable dependency |

Verdict is exactly one of:
- `→ PROCEED: all requirements met.`
- `→ DEGRADE: proceeding without <x>. <consequence>.`  (only SOFT missing)
- `→ STOP: <x> is required. Install it and re-run /juel:<skill>.`  (any HARD ✗)

A `?` never blocks — it proceeds with an explicit warning naming the call that will fail.

**Rules**
1. Preflight runs before any mutating call.
2. One preflight per user invocation, not per skill. A skill invoked by another skill suppresses its own block; the parent declares the union and says so in the delegation.
3. Never re-print preflight between phases.
4. A `?` never becomes a `✓`.
5. Every `!` line is the literal `fallback` string from the declaration — never improvised.
6. Budget: 1 line when all-satisfied for a light skill, 5 lines maximum. Satisfied dependencies are never enumerated individually.

**Checking**
- CLI binary: `command -v <bin>`, plus any declared candidate `paths`.
- Coreutils: one batched `test -x` call.
- git repo: `git rev-parse --show-toplevel`; worktree: `--git-common-dir` differs from `--git-dir`.
- open PR: `gh pr view --json number` (check `gh` first).
- **MCP server: no check exists.** Never run `claude mcp list` in preflight — it takes ~4.6s, reports a fresh process's state rather than this session's, has no `--json`, and its registered name does not map to the tool prefix skills call. Render MCP dependencies as `?`, always, naming the tool that will fail.

All checks run as **one batched Bash call**, ~50ms, no network.
