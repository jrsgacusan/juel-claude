# Resolution reference — authoring source of truth

This file is **not** read at runtime, for the same reason as `references/strict-protocol.md`,
`references/preflight.md` and `references/work-source.md`: no `SKILL.md` links to it, and
progressive disclosure (a sibling file loaded only if the model chooses to) cannot deliver an
"always resolve this way" guarantee. It exists so that Tasks 15–20 share one canonical precedence
chain, one config schema, one cache spec, and one copy of the `resolve_bin` / `copy_untracked` /
`detect_ref` shell helpers, instead of six skills re-deriving (and silently disagreeing on) their
own versions of each.

**This is the file that makes the plugin portable to a repo it was not written for.** Every rule
below exists to satisfy one constraint: a repo with no config, no tracker, and an unfamiliar
toolchain must never cause a skill to guess wrong or abort. It must either detect correctly, ask
once, or skip the affected gate with a visible note — never invent a plausible-looking answer.

---

## 1. The one precedence chain — `PRECEDENCE_CHAIN`

Applies to every resolvable value (a command, a branch name, a path, a tracker type — anything a
skill would otherwise hardcode or re-derive per phase). Stop at the first hit.

```
1. Explicit skill argument
2. <repo>/.claude/workflow.local.json      (untracked, personal)
3. <repo>/.claude/workflow.json            (committed, team)
4. CLAUDE.md / AGENTS.md declarations
5. Repo evidence (manifests, git history, .github templates)
6. Ask the user ONCE, offer to persist
7. Documented default — or, for commands, SKIP THE GATE with a note
```

**Rule 7 is the important one: a missing test command is not an error.** It resolves to `null`, the
phase reports "no test command resolved — test gate skipped", and the run continues. Never invent
`npm test` for a repo with no `test` script. **No config-related condition ever aborts a skill.**
This is the single rule every other portability change in this file is downstream of — when in
doubt about how to handle an absent or ambiguous value, this is the rule to re-derive the answer
from.

Step 6 ("ask the user ONCE, offer to persist") means: ask, and if the user's answer should live in
`.claude/workflow.json` for next time, offer to write it there — but never write config without the
user agreeing, and never ask the same question twice in one session (cache the answer per §3).

---

## 2. Config schema — `.claude/workflow.json`

`<repo-root>/.claude/workflow.json`, with `.claude/workflow.local.json` deep-merged over it (local
wins key-by-key, not whole-file). Every field is optional; **absent config must be indistinguishable
from a well-configured repo, for any repo whose conventions are actually discoverable** — a skill
run against a repo with zero config files should behave the same as one run against a repo whose
maintainer filled every field in by hand, wherever discovery is possible at all.

```jsonc
{
  "commands": {
    "install": null, "test": null, "lint": null,
    "typecheck": null, "format": null, "run": null
  },
  "baseBranch": null,          // default: §2 behavior table, "baseBranch" row
  "remote": null,              // default: sole remote, else "origin"
  "branchPattern": null,       // default: modal pattern from last 60 remote branches
  "commitStyle": null,         // conventional-ticket | conventional | freeform
  "worktreeRoot": null,        // default: <main-root>/.worktrees
  "docsRoot": null,            // default: docs/.superpowers/ or docs/superpowers/ — see below
  "worktreeCopy": [],          // EXTRA untracked glob patterns; secrets are opt-in here, never default
  "tracker": {
    "type": null,              // linear | jira | github | file | inline | none
    "project": null,
    "statusMap": null,
    "refPattern": null
  },
  "executor": null             // codex | inline
}
```

`.claude/` is chosen as the config location because `daily-worktrees` already copies it into every
worktree, so config follows the work with no new plumbing.

**Error handling — none of these ever abort a skill:**

| Condition | Behavior |
|---|---|
| Malformed JSON (either file) | Warn once, ignore the file entirely, fall through to the next precedence step as if it were absent |
| Unknown top-level or nested key | Ignored silently, for forward compatibility with newer schema versions |
| A configured command whose binary does not resolve (`command -v`, or `-x` for a `./`-relative path) | Warn, treat that command as unresolved — falls through the rest of the precedence chain for that key, same as if it had never been configured |

**Backwards compatibility:** when neither `workflow.json` nor `workflow.local.json` exists, the
legacy `## Linear Worktrees Config` markdown block in `CLAUDE.md` is still read, as a documented
deprecated fallback (precedence step 4).

### Absent-config behavior table

What each key resolves to when `.claude/workflow.json` does not exist at all — i.e., precedence
steps 5–7 for every field:

| Key | Resolves to, with zero config |
|---|---|
| `commands.install` / `.test` / `.lint` / `.typecheck` / `.format` / `.run` | Each resolved **independently**: Tier A project-authored task runners (`Makefile`, `justfile`, `Taskfile.yml`, `mise.toml` — emit `make <target>` only for targets that exist) → Tier B language manifests (`package.json`+lockfile, `pyproject.toml`, `Cargo.toml`, `go.mod`, `mix.exs`, `Gemfile`, Gradle, `pom.xml`, `composer.json`, `*.csproj`) → Tier C `.github/workflows/*.yml` `run:` steps, treated as a suggestion and confirmed with the user, never run blind. **Tier B carries the same existence gate as Tier A, per key, not just per manifest:** a manifest may only propose a command for `test`/`lint`/`typecheck`/`format`/`run` when that key's own evidence is present — a `scripts.<key>` entry (`package.json`), a tool config section or listed dependency (`pyproject.toml`'s `[tool.ruff]`/`[tool.mypy]`/etc.), a configured plugin (Gradle/Maven), and so on. `install` is the **sole exception** — it is a package-manager primitive (`npm install`, `uv sync`, `cargo fetch`, …) that needs no script to exist. This existence gate is a precondition, checked *before* the head-binary verification, not a substitute for it: a repo with `package.json`+a lockfile and no `scripts.test` must resolve `test` to `null`, never to `npm test`, even though `npm` itself resolves on `PATH` — the full per-manifest, per-key command table lives in `skills/ship-ticket/SKILL.md`'s "Toolchain commands" section (kept there, not duplicated here, since this file is never read at runtime). If nothing in any tier resolves and verifies (existence gate satisfied, head binary must resolve; for `make`/`just`/`task` the target must exist): **`null` — the corresponding gate is skipped with a one-line note, not an error** |
| `baseBranch` | `git config --get claude.baseBranch` → `git symbolic-ref refs/remotes/<remote>/HEAD` → `gh repo view --json defaultBranchRef` → first existing of `main`/`master`/`develop`/`dev`/`trunk` → ask once. (Gitflow caveat: if a `develop`/`dev` branch exists and ≥70% of its last 30 merges came from `feat/*`-shaped branches, prefer it as the *integration* branch and say so — default branch and integration branch are not always the same thing.) |
| `remote` | The repo's sole remote; if there is more than one, `origin` |
| `branchPattern` | Modal pattern sampled from the last 60 remote branches (classified into `type-slash` / `type-slash-noticket` / `ticket-first` / `user-slash` / `flat`); with no branch history, `{type}/{ticket-lower}-{slug}` |
| `commitStyle` | Sampled from the last 60 subjects: ≥60% conventional → `conventional`; of those, ≥50% with a ticket-shaped scope → `conventional-ticket`; else `freeform` (mirror the repo's tone, never impose a format). Trailers: count `Co-Authored-By:` in the last 100 messages — zero → omit. Default when ambiguous is omit, not include |
| `worktreeRoot` | `<main-root>/.worktrees` (accepts absolute, `~`-prefixed, or relative-to-main-root values when configured) |
| `docsRoot` | `<CWD_ROOT>/docs/.superpowers/` if it already exists and is non-empty (keeps an existing repo's prior specs/plans/context on the dotted path); otherwise `<CWD_ROOT>/docs/superpowers/` for a brand-new repo. Resolved **once** and reused — a skill must never pick between the two variants ad hoc |
| `worktreeCopy` | `[]` — only the built-in default untracked patterns are copied (`.env`, `.env.*`, `*.local`, `.envrc`, `.npmrc`, `.tool-versions`); no extra globs, no secrets beyond that default set |
| `tracker.type` | Shape-inferred from the bare argument (`SAVI-1162`-shaped → a tracker provider; `#412` → `github`; `./spec.md` → `file`; multi-line prose → `inline`), else capability auto-detect from what's connected, else ask (interactive sessions only — headless CMUX-spawned sessions fall through to `file`/`inline` rather than blocking) |
| `tracker.project` | Not resolved from evidence — left to the provider's own default scope, or asked if a call genuinely requires it |
| `tracker.statusMap` | Not needed for `linear`/`github`/`file`; **required** for `jira` specifically, since Jira workflow states are project-specific with no fixed vocabulary — degrades per §5 of `references/work-source.md` if absent there |
| `tracker.refPattern` | Absent → `detect_ref`'s generic anchored-segment + denylist heuristic (§5 below) applies unfiltered. Present → applied as an *additional* intersecting filter, making detection exact for a known tenant's prefix |
| `executor` | §7.10-style resolution: `codex` if on `PATH` **and** `~/.codex/prompts/claude-plan-executor.md` exists → `codex` with the executor instructions inlined if the prompt file is missing → `inline` (`superpowers:executing-plans` in-session) |

---

## 3. Cache — `CACHE_SPEC`

Resolve every value in §1/§2 **once per repo, per session**, not once per phase. Re-deriving "the
project's lint/test commands" at every phase (the `ship-ticket:100`/`:109` pattern this replaces) is
wasted work and a source of drift if the answer changes mid-run.

**Location:**

```sh
RAW=$(git rev-parse --git-common-dir)
CACHE_DIR=$(cd "$(dirname "$RAW")" && pwd -P)/$(basename "$RAW")/claude
CACHE_FILE="$CACHE_DIR/workflow-cache.json"
```

i.e. `$(git rev-parse --git-common-dir)/claude/workflow-cache.json`, normalized. Chosen over
`--show-toplevel` for two reasons:

1. It lives inside `.git/` — never committed, needs no `.gitignore` entry, and is never copied by
   `git worktree add`.
2. It resolves to the **main** repo's `.git` even when the command runs from inside a *linked*
   worktree, so every worktree of a repo shares one cache instead of re-resolving independently.

**`git rev-parse --git-common-dir` can return a relative path** (confirmed empirically: from a main
repo's own root it prints the bare relative string `.git`, not an absolute path) — never treat its
raw output as cache-file-ready. Normalize with `cd "$(dirname "$RAW")" && pwd -P` before appending
`claude/workflow-cache.json`, exactly as shown above; `pwd -P` also resolves any symlink in the
`.git` path so worktrees reached through a symlinked checkout still land on the one real cache file.

**Invalidation is a fingerprint, not a TTL:** `sha1` over `<path>:<size>:<mtime>` for every config
file, manifest and lockfile that actually exists in the repo (`.claude/workflow.json`,
`.claude/workflow.local.json`, `package.json` + its lockfile, `pyproject.toml`, `Cargo.toml`,
`go.mod`, etc. — whichever of these are present). Any mismatch against the cached fingerprint
invalidates the entire cache entry and triggers a full re-resolve; there is no time-based expiry.

**In-session reuse:** after resolving, emit exactly one `<workflow-resolved .../>` block into the
transcript. Every later phase in the same session reads that block instead of touching the
filesystem or re-running detection. **Re-running detection mid-session — instead of reading the
already-emitted block — is a Common Mistake**, not a harmless redundancy: it risks a different
answer mid-run (e.g. if the user edited `workflow.json` between phases) that the rest of the run
never reconciles against.

---

## 4. Shell helpers

Both helpers are POSIX `sh`-compatible and were sanity-tested against `bash`, `zsh`, and `dash`
(macOS's actual `/bin/sh` is `bash` in POSIX mode, not `dash` — both were tested explicitly) with
identical results in all three.

### 4.1 `resolve_bin`

```sh
# resolve_bin NAME [candidate...] — PATH first, then explicit candidates.
resolve_bin() {
  n=$1; shift
  p=$(command -v "$n" 2>/dev/null) && { printf '%s' "$p"; return 0; }
  for c in "$@"; do [ -x "$c" ] && { printf '%s' "$c"; return 0; }; done
  return 1
}
```

Candidates (e.g. the macOS GUI Homebrew paths) are exactly that — labelled fallbacks tried in order
after `PATH`, never the sole source of truth. `resolve_bin` prints nothing and returns 1 when
nothing resolves; callers must treat that as "unresolved", never substitute a guessed path.

**Persisting across Bash tool calls:** each Bash tool call is an independent non-login shell, so a
binary resolved in call N is gone by call N+1. Persist resolved paths to
`$GIT_COMMON/claude/bins.env` (`GIT_COMMON` per §3's normalized `git-common-dir`) and
`. "$BINS"` at the top of every subsequent call that needs them, rather than re-resolving or — worse
— assuming the previous call's `PATH` still applies.

### 4.2 `copy_untracked`

```sh
# copy_untracked SRC DST — portable, untracked-only, no glob-abort.
copy_untracked() {
  find "$1" -maxdepth 1 \( \
        -name '.env' -o -name '.env.*' -o -name '*.local' \
     -o -name '.envrc' -o -name '.npmrc' -o -name '.tool-versions' \
     $EXTRA_PATTERNS \) -type f -print | while IFS= read -r f; do
    git -C "$1" ls-files --error-unmatch "${f#"$1"/}" >/dev/null 2>&1 && continue
    cp -p "$f" "$2/"
  done
}
```

`find` is used rather than a glob because it never fails on no-match — no `setopt NULL_GLOB` /
`shopt -s nullglob` is needed, and the same code works unmodified in `sh`, `bash` and `zsh`. This
fixes a real bug where bare globs abort the whole script under zsh's default (non-`nullglob`)
behavior.

**Rules — verified by test in §6, "copy_untracked":**

- **Untracked-only.** Every candidate is checked against `git ls-files --error-unmatch` and skipped
  if tracked — copying a tracked file would clobber the branch's own version of it in the
  destination worktree.
- **Secrets are opt-in, never default.** The hardcoded pattern list is deliberately narrow
  (`.env`-family, `.npmrc`, `.tool-versions`). Anything wider — `*.pem`, `*.key`, custom secret
  files — is supplied per-repo via `config.worktreeCopy` → `EXTRA_PATTERNS`, never copied
  automatically.
- **Never copy dependency or build artifacts** — `venv`, `.venv`, `node_modules`, `target`,
  `_build`, `vendor`, `.next`, `dist`. These are excluded by construction (the pattern list never
  names them, and `-maxdepth 1` alone would not exclude a large tracked or untracked directory tree
  even if it were named) — the correct move is to run the resolved `commands.install` instead of
  copying build output.

**A real portability caveat found while testing `EXTRA_PATTERNS`, not present in the base pattern
list:** `EXTRA_PATTERNS` is expanded unquoted so its words become separate `find` arguments — e.g.
`EXTRA_PATTERNS="-o -name *.pem"`. This depends on the shell performing word-splitting on an
unquoted parameter expansion. **bash and POSIX `sh`/`dash` do this by default; interactive-mode zsh
does not** — zsh passes the whole `EXTRA_PATTERNS` value as one literal argument to `find`, which
then fails loudly (`find: -o -name *.pem: unknown primary or operator`) and, because the failure is
upstream of the `| while read` pipe, **the entire copy — including the always-on `.env`/`.npmrc`
defaults — silently copies nothing**, with only a stderr line as evidence. Confirmed by direct test
(§6). Fix: any skill that sets `EXTRA_PATTERNS` under zsh must first run
`[ -n "$ZSH_VERSION" ] && setopt SH_WORD_SPLIT` (harmless no-op under bash/sh) — verified to restore
identical behavior across all three shells. Skills inlining `copy_untracked` from this file must
carry that guard alongside it whenever `config.worktreeCopy` is non-empty.

---

## 5. `detect_ref`

Anchored to whole `/`-delimited segments, with a denylist of branch-type words — not a free-floating
substring match anywhere in the string. This is what kills the current false positives:
`chore/bump-2fa-lib` no longer yields `BUMP-2` (the ticket-shaped substring `bump-2` was inside a
larger segment, `bump-2fa-lib`, that doesn't match end-to-end) and `release/v2-1` no longer yields
`V2-1` (`v2` is not a pure-letter prefix, so it never qualifies as a tracker key regardless of the
denylist).

```sh
# Anchored to whole '/'-delimited segments, with a branch-word denylist.
DENY='^(feat|fix|chore|refactor|docs|test|hotfix|release|wip|perf|build|ci|style|v|part|step|pr|review)$'

# _ref_from_segment SEGMENT — classifies one path segment. Prints the
# candidate ref and returns 0 on a match, prints nothing and returns 1
# otherwise. Not meant to be called directly; detect_ref drives it.
_ref_from_segment() {
  seg=$1
  case "$seg" in
    *-*) : ;;
    *) return 1 ;;                     # no dash at all -> not ticket-shaped
  esac
  prefix=${seg%%-*}
  rest=${seg#*-}
  case "$rest" in
    *-*) num=${rest%%-*} ;;            # PREFIX-NUM-slug: slug drops out
    *)   num=$rest ;;                  # PREFIX-NUM, nothing trailing
  esac
  lc_prefix=$(printf '%s' "$prefix" | tr 'A-Z' 'a-z')
  case "$lc_prefix" in
    issue|issues)                      # GitHub-issue shape renders as #NUM,
      case "$num" in                   # never as ISSUE-NUM
        ''|*[!0-9]*) return 1 ;;
      esac
      printf '#%s\n' "$num"
      return 0
      ;;
  esac
  case "$prefix" in
    *[!A-Za-z]*) return 1 ;;           # prefix must be PURE letters (kills "v2")
  esac
  [ "${#prefix}" -ge 2 ] || return 1   # single-letter prefixes never qualify
  case "$num" in
    ''|*[!0-9]*) return 1 ;;           # number must be pure digits
  esac
  if printf '%s\n' "$lc_prefix" | grep -Eq "$DENY"; then
    return 1                           # branch-word prefix -> not a ticket
  fi
  uc_prefix=$(printf '%s' "$prefix" | tr 'a-z' 'A-Z')
  printf '%s-%s\n' "$uc_prefix" "$num"
  return 0
}

# detect_ref STRING [refPattern] — STRING is typically a branch name,
# worktree dirname, or PR title. refPattern, when non-empty, is an
# additional grep -E filter the candidate ref must also satisfy (from
# config.tracker.refPattern) — for exactness once a tenant's prefix is known.
# Prints the ref (already uppercased, or "#NUM" for a GitHub-issue shape)
# and returns 0. Finds nothing -> prints nothing, returns 1.
# "No ref" is a VALID, EXPECTED outcome — never treat rc=1 as an error.
detect_ref() {
  str=$1; pat=${2:-}
  result=$(printf '%s\n' "$str" | tr '/' '\n' | while IFS= read -r seg; do
    if ref=$(_ref_from_segment "$seg") && [ -n "$ref" ]; then
      if [ -n "$pat" ]; then
        printf '%s\n' "$ref" | grep -Eq "$pat" || continue
      fi
      printf '%s\n' "$ref"
      break
    fi
  done)
  [ -n "$result" ] && { printf '%s\n' "$result"; return 0; }
  return 1
}
```

The tracker-key uppercasing (`uc_prefix=$(printf '%s' "$prefix" | tr 'a-z' 'A-Z')`) is generic over
**any** prefix that survives the denylist and shape checks — `SAVI`, `MSTR`, `ASW`, a brand-new
tenant's prefix never seen before — never a hardcoded `savi` special case. `refPattern`, when
configured, is applied as an *additional* intersecting filter on top of this generic heuristic
(§2's absent-config table, `tracker.refPattern` row) — it narrows, it never substitutes for the
generic rule.

### The no-ref path

**"No ref" returns 1 and that is a valid outcome, not an error.** Replaces the current
`start:14-24`-style "ask the user for the ticket ID," which wrongly assumes a ticket always exists.
When `detect_ref` returns 1, offer exactly these four options, never fewer, never silently pick one:

1. **Pick from open items** — only offered when the resolved provider supports `list` (§3 of
   `references/work-source.md`'s capability table). Omit this option entirely for a provider that
   can't list (`file` pointed at a single path, `inline`) rather than offering it and failing.
2. **Point at a requirements file** — a local spec/plan path.
3. **Paste requirements inline** — "I'll paste the requirements here"; per `references/work-source.md`
   §4.5, this auto-promotes to `file` on first write so status/update calls keep working afterward.
4. **No ticket — just brainstorm** — the explicit "there is no ref and there will not be one"
   option. This is not a failure state to route around; it is a first-class answer.

### The ref-optional naming table

When `ref` is null, the segment it would have contributed **drops out entirely** — never a
placeholder like `none`, `NOREF`, or an empty pair of dashes. `compact-context` already implements
this correctly ("if no ticket, drop this segment") and is the template every other naming site
follows:

| Site | With ref (`SAVI-1162`) | Without ref |
|---|---|---|
| Worktree directory | `.worktrees/savi-1162` | `.worktrees/add-user-authentication` |
| Branch name | `feat/savi-1162-add-user-authentication` | `feat/add-user-authentication` |
| Spec filename | `docs/.superpowers/specs/2026-08-01-savi-1162-add-auth.md` | `docs/.superpowers/specs/2026-08-01-add-auth.md` |
| Plan filename | `docs/.superpowers/plans/2026-08-01-savi-1162-add-auth.md` | `docs/.superpowers/plans/2026-08-01-add-auth.md` |
| PR title | `[SAVI-1162] Add user authentication` | `Add user authentication` |
| Commit scope | `feat(SAVI-1162): add login endpoint` | `feat: add login endpoint` |
| Context file (`compact-context`) | `2026-08-01-savi-1162-auth-refactor-session.md` | `2026-08-01-auth-refactor-session.md` |
| Workspace title (`cmux rename-workspace`) | `SAVI-1162` | a short descriptive title, e.g. `add-user-authentication` |

---

## 6. Sanity-test results (not part of the runtime contract — recorded for the record)

All three helpers were run against real inputs in an isolated scratch directory (a throwaway git
repo, never this repo, never `~/.claude/skills/`), across `bash`, `zsh`, and POSIX `dash`.

**`detect_ref`** — the six cases specified for this task, identical results in all three shells:

| Input | Output | rc |
|---|---|---|
| `.worktrees/savi-1162` | `SAVI-1162` | 0 |
| `chore/bump-2fa-lib` | (none) | 1 |
| `release/v2-1` | (none) | 1 |
| `feat/mstr-3034-thing` | `MSTR-3034` | 0 |
| `issue-412` | `#412` | 0 |
| `main` | (none) | 1 |

Additional edge cases, also identical across shells: `fix-123` / `part-2` / `step-3` / `review-2` →
no ref (denylist prefixes correctly rejected even though the shape matches); `ASW-123` and
`.worktrees/ASW-999` → `ASW-123` / `ASW-999` (a brand-new prefix, never hardcoded, resolves
correctly); `feat/savi-1162-add-auth` → `SAVI-1162` (trailing slug correctly dropped);
`issues-88` → `#88`, `ISSUE-77` → `#77` (case-insensitive, both singular and plural); with
`refPattern="^SAVI-"` configured, `feat/mstr-3034-thing` correctly flips to no-ref while
`feat/savi-1162-thing` still resolves.

**`resolve_bin`** — `resolve_bin git` returned the real `PATH` hit; a nonexistent name with no
candidates returned rc=1 and printed nothing; a nonexistent name with one executable candidate
returned the candidate path; a nonexistent name with one non-executable candidate correctly
returned rc=1 rather than the unusable path.

**`copy_untracked`** — a scratch repo with a **tracked** `.env`, three **untracked** matching files
(`.env.local`, `.npmrc`, `.tool-versions`), one untracked non-matching file (`notes.txt`), and one
untracked secret (`id_rsa.pem`, not opted in): the tracked `.env` was correctly excluded (never
clobbers the branch's own version), `notes.txt` was correctly excluded (no pattern match), the
opt-out-by-default secret was correctly excluded, and exactly the three intended untracked files
were copied. With `EXTRA_PATTERNS="-o -name *.pem"` added, the `.pem` file was correctly included
too — **in bash and dash**. Under zsh with no further guard, the same `EXTRA_PATTERNS` value made
`find` fail outright and the whole copy silently produced zero files; adding
`setopt SH_WORD_SPLIT` before sourcing (harmless under bash/dash) restored identical, correct
behavior across all three shells. See §4.2 for the caveat this produced in the reference itself.

**Cache location normalization** — `git rev-parse --git-common-dir` was confirmed to return a
*relative* path (`.git`) when run from a main repo's own root, and an *absolute* path when run from
a linked worktree in this environment; the `cd "$(dirname "$RAW")" && pwd -P` normalization produced
the identical, correct, absolute main-repo `.git` path in both cases, confirming worktrees share one
cache file.
