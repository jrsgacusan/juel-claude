# juel-claude

## Releases are tag-driven, not version-driven

`.github/workflows/release.yml` only fires on `push: tags: ['juel--v*']`. Bumping
`version` in `.claude-plugin/plugin.json` does **nothing** by itself — no tag,
no release, no matter how many commits landed on `main`.

Whenever `.claude-plugin/plugin.json`'s `version` field changes (in the PR that
bumps it, or immediately after merging it to `main`):

1. Confirm the bumped version isn't already tagged: `git tag -l 'juel--v*' | tail -5`
2. Tag it: `git tag -a juel--vX.Y.Z -m "juel vX.Y.Z"`
3. Push the tag: `git push origin juel--vX.Y.Z`
4. Confirm the release landed: `gh release view juel--vX.Y.Z`

If a version bump merges to `main` without a matching tag getting pushed in the
same sitting, it's easy to forget — check `git tag -l 'juel--v*' | tail -1` vs
`.claude-plugin/plugin.json`'s `version` any time you're about to say a release
is "done" or are asked why a release is missing.
