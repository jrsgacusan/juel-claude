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

## The STAR page is a living document

`skills/star/how-it-works.html` is the page at https://claude.ai/artifact/V2Qx9Cm469k1vuJvcjS2fC,
which shows how `juel:star` works. `docs/star-closed-loop.html` is the same page, kept under `docs/`
(the one tracked file there): it is `skills/star/how-it-works.html` without its first line, the
artifact link comment. Both are living documents that change with the STAR flow.

A change under `skills/star/`, or to the parts of `juel:ship-ticket` and `juel:babysit-pr` that STAR
drives (`--unattended`, the gate loop, the hosted reviewer), updates both pages in the same commit:
edit `skills/star/how-it-works.html`, then run
`tail -n +2 skills/star/how-it-works.html > docs/star-closed-loop.html`. Then republish the page to
that link with the Artifact tool (`url` set to the link). `tests/star/how-it-works.test.sh` fails
when the page's stages, states or models no longer match the skill, and when
`docs/star-closed-loop.html` is not the page without its first line. A release sets the status label
to the new version in its own commit, in both pages, before `node scripts/bump-version.mjs`.
