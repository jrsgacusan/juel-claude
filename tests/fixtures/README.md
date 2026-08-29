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
