# Validator fixtures

Each directory here is a miniature plugin root passed to the validator directly:

    node scripts/validate.mjs tests/fixtures/<name>

A fixture is expected to FAIL (exit 1) with a specific error. That is the test.

## Why these are copied into the installed plugin cache

Both Claude Code and Codex copy the whole repo into their plugin cache on install, so these
`SKILL.md` files travel with a release. They are never surfaced to a model — skill discovery only
globs `skills/*/SKILL.md` at the plugin root, and these are three levels deeper.

Renaming them to avoid the copy was considered and rejected: they exist to exercise the real
discovery path, and a fixture that no longer looks like a real skill no longer tests it. The few KB
of dead weight in the cache is the cheaper trade.

## `orca-driver` fixtures

The `orca-*` skills drive a CLI that is not on `PATH`, so check 15 polices two mistakes. One
fixture per mistake, each otherwise a valid skill:

- `orca-hardcoded-path` — inlines `/Applications/Orca.app/Contents/Resources/bin/orca` into an
  executable line instead of passing it as a `resolve_bin` candidate. Fails `orca-driver`.
- `orca-names-cmux` — an `orca-*` skill invoking `"$CMUX"`, i.e. a copy-paste from the cmux flow
  that would drive the wrong tool. Fails `orca-driver`.

Both also report the three errors inherent to any fixture root (missing `requirements.json`,
`references/harness-codex.md`, and the vendored plan executor). The `orca-driver` line is the
assertion; those three are noise every fixture here shares.

Note the check matches shell *usage* (`$CMUX`, or `cmux` in command position at the start of a
line), not the bare word anywhere on the line. Two real failures shaped this: the strict protocol
block copied byte-for-byte into every skill names "a CMUX prompt" in prose, and `orca-ship-tickets`
legitimately names the cmux flow when explaining why it does not use it.
