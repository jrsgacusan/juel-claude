#!/usr/bin/env node
// Generates .claude-plugin/requirements.json from every skill's
// `metadata.requires` frontmatter block. Zero-dependency, Node 20+, ESM.
//
// `requirements.json` is a rollup, never a source of truth: the inline
// `## Preflight` table in each SKILL.md is what the model reads and acts on
// at invoke time (frontmatter may not survive into the model's context —
// see references/preflight.md §2.3). `metadata.requires` mirrors that table
// for TOOLING (this generator, `scripts/validate.mjs` check 6, future
// `/juel:doctor`). The two must never drift, which is exactly what check 6
// in validate.mjs enforces by regenerating this file in-memory and diffing.
//
// The YAML subset parsed here is intentionally tiny and strict: two-space
// indentation, `- ` list items, flat `key: value` scalars only. No anchors,
// no flow style, no multi-line scalars. It THROWS on anything it does not
// understand — a wrong requirements.json is worse than none, and a silent
// misparse is worse than a crash.

import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const GROUPS = ['mcp', 'cli', 'skills', 'context', 'perms'];

// Groups whose entries may carry a `check:` field (a literal, or descriptive,
// verification hint). `skills` and `perms` entries never do — per the schema
// in docs/design/research/design-preflight.md §3.1, those two groups are
// `{ id, hard, why, fallback? }` only.
const GROUPS_WITH_CHECK = new Set(['mcp', 'cli', 'context']);

// `context` ids are a closed vocabulary — see task-12-brief.md and
// docs/design/research/design-preflight.md §3.1, extended per the Task 12
// review (round 1, finding 3) with `writable-cwd`, `work-source-list-capable`
// and `github-remote` — each replaces a prior overloaded mapping that either
// conflated a location claim with a permission claim, conflated a
// provider-capability check with human presence, or produced a false pass
// (a GitLab remote would satisfy `git-repo` while failing a real HARD
// GitHub-remote requirement). A context id outside this set is treated as
// unparseable, not silently accepted.
// `app-url` and `verification-criteria` added for Task 23 (`regression`) — a
// resolved-target claim and a criteria-source claim, neither of which any
// prior context id already covers (they are not a location, a permission, a
// provider capability, or a human-presence check).
const CONTEXT_VOCAB = new Set([
  'git-repo',
  'git-worktree',
  'worktree-root-cwd',
  'clean-tree',
  'open-pr',
  'plan-file',
  'cmux-session',
  'interactive-user',
  'writable-cwd',
  'work-source-list-capable',
  'github-remote',
  'app-url',
  'verification-criteria',
]);

// id -> { kind, label, install, paths? }. Every id referenced by any skill's
// metadata.requires block must have an entry here (check 6 / this generator
// throw otherwise) so requirements.json can always render an install hint.
const DEFINITIONS = {
  // --- mcp ---------------------------------------------------------------
  linear: {
    kind: 'mcp',
    label: 'Linear MCP',
    install: 'Ships as a plugin dependency; authorize the connector, then restart the session',
  },
  playwright: {
    kind: 'mcp',
    label: 'Playwright MCP',
    install: 'Ships as a plugin dependency',
  },
  context7: {
    kind: 'mcp',
    label: 'Context7 MCP',
    install: 'Ships as a plugin dependency',
  },

  // --- cli -----------------------------------------------------------------
  cmux: {
    kind: 'cli',
    label: 'cmux',
    install: 'https://github.com/manaflow-ai/cmux',
    paths: ['/Applications/cmux.app/Contents/Resources/bin/cmux'],
  },
  claude: {
    kind: 'cli',
    label: 'Claude Code CLI',
    install: 'https://claude.com/claude-code',
    paths: ['/Applications/cmux.app/Contents/Resources/bin/claude'],
  },
  codex: {
    kind: 'cli',
    label: 'Codex CLI',
    install: 'npm i -g @openai/codex',
  },
  gh: {
    kind: 'cli',
    label: 'GitHub CLI',
    install: 'brew install gh && gh auth login',
  },
  git: {
    kind: 'cli',
    label: 'git (>= 2.5)',
    install: 'brew install git',
  },
  coreutils: {
    kind: 'cli',
    label: 'coreutils',
    install: 'preinstalled on macOS and Linux',
  },
  'resolved-install-command': {
    kind: 'cli',
    label: 'project install command',
    install:
      "Resolved at runtime from the repo's own install/resolution layer (e.g. `make install`); " +
      'there is no fixed install step — install project dependencies yourself if none resolves',
  },

  // --- skills ----------------------------------------------------------------
  'pr-review-toolkit': {
    kind: 'skill',
    label: 'pr-review-toolkit',
    install: 'Ships as a plugin dependency',
  },
  superpowers: {
    kind: 'skill',
    label: 'superpowers',
    install: '/plugin install superpowers@claude-plugins-official',
  },
  'superpowers:brainstorming': {
    kind: 'skill',
    label: 'superpowers:brainstorming',
    install: 'Ships as part of the superpowers plugin dependency',
  },
  'juel:start': { kind: 'skill', label: 'juel:start', install: 'Ships with this plugin' },
  'juel:review-pr': { kind: 'skill', label: 'juel:review-pr', install: 'Ships with this plugin' },
  'juel:review-and-execute': {
    kind: 'skill',
    label: 'juel:review-and-execute',
    install: 'Ships with this plugin',
  },
  'juel:daily-worktrees': {
    kind: 'skill',
    label: 'juel:daily-worktrees',
    install: 'Ships with this plugin',
  },
  'juel:ship-ticket': {
    kind: 'skill',
    label: 'juel:ship-ticket',
    install: 'Ships with this plugin',
  },
  'code-simplifier': {
    kind: 'skill',
    label: 'code-simplifier',
    install: 'Ships as a plugin dependency',
  },
  run: { kind: 'skill', label: 'run', install: 'Built-in Claude Code skill' },
  'juel:verify': { kind: 'skill', label: 'juel:verify', install: 'Ships with this plugin' },

  // --- context (closed vocabulary — every member documented even if unused) --
  'git-repo': {
    kind: 'context',
    label: 'git repository',
    install: 'Run from inside a git repository',
  },
  'git-worktree': {
    kind: 'context',
    label: 'git worktree',
    install: 'Run from inside a git worktree',
  },
  'worktree-root-cwd': {
    kind: 'context',
    label: 'cwd at worktree root',
    install: 'Run with the working directory set to the worktree root',
  },
  'clean-tree': {
    kind: 'context',
    label: 'clean working tree',
    install: 'Commit or stash outstanding changes first',
  },
  'open-pr': {
    kind: 'context',
    label: 'open PR',
    install: 'The current branch needs an open pull request (`gh pr view`)',
  },
  'plan-file': {
    kind: 'context',
    label: 'plan file',
    install: 'An implementation plan must exist under docs/.superpowers/plans/',
  },
  'cmux-session': {
    kind: 'context',
    label: 'cmux workspace',
    install: 'Run with at least one active cmux workspace',
  },
  'interactive-user': {
    kind: 'context',
    label: 'interactive user',
    install: 'Requires an interactive session (AskUserQuestion); unavailable headless',
  },
  'writable-cwd': {
    kind: 'context',
    label: 'writable cwd',
    install: 'Run somewhere the current directory is writable (`test -w .`) — a permission claim, not a location claim',
  },
  'work-source-list-capable': {
    kind: 'context',
    label: 'work-source provider with list capability',
    install: 'Configure a work-item provider that supports listing (e.g. Linear MCP), or paste refs / point at a spec directory',
  },
  'github-remote': {
    kind: 'context',
    label: 'GitHub-hosted remote',
    install: 'The repo remote must resolve to github.com — a GitLab or Bitbucket remote does not satisfy this',
  },
  'app-url': {
    kind: 'context',
    label: 'resolved app URL',
    install: 'Pass an explicit URL argument, or ensure commands.run resolves and can be started in the foreground; otherwise this skill asks where the app is running',
  },
  'verification-criteria': {
    kind: 'context',
    label: 'acceptance criteria to verify',
    install: 'Provide acceptance criteria via the work item or the spec file, or answer when this skill asks for concrete verification steps',
  },

  // --- perms -----------------------------------------------------------------
  'permission-mode-auto': {
    kind: 'perm',
    label: '--permission-mode auto',
    install:
      'Relaunch with --permission-mode acceptEdits if auto is rejected (never bypassPermissions)',
  },
  'cmux-notification-hooks': {
    kind: 'perm',
    label: 'cmux Notification+Stop hooks',
    install: 'Add async Notification and Stop hooks running `cmux wait-for` to ~/.claude/settings.json',
  },
};

/** Strip one layer of matching '...' or "..." quoting. No escape handling. */
function unquote(raw) {
  if (raw.length >= 2) {
    const first = raw[0];
    const last = raw[raw.length - 1];
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return raw.slice(1, -1);
    }
  }
  return raw;
}

function parseItem(rawLines, skillLabel, group) {
  const item = {};
  for (const raw of rawLines) {
    const m = raw.match(/^(id|hard|why|check|fallback):(.*)$/);
    if (!m) throw new Error(`${skillLabel}: [${group}] unrecognized line in entry: ${JSON.stringify(raw)}`);
    const [, key, rest] = m;
    // Exactly one space must separate the colon from the value, and the
    // value itself must carry no leading/trailing whitespace. A stray
    // double-space or trailing space is a malformed-spacing error, not
    // something to silently absorb into the stored string (round-1 review
    // finding: this exact class of drift previously parsed without error).
    if (rest.length === 0)
      throw new Error(`${skillLabel}: [${group}] key '${key}' has no value: ${JSON.stringify(raw)}`);
    if (rest[0] !== ' ')
      throw new Error(`${skillLabel}: [${group}] key '${key}' must have exactly one space after the colon: ${JSON.stringify(raw)}`);
    const rawValue = rest.slice(1);
    if (rawValue.length === 0 || /^\s/.test(rawValue) || /\s$/.test(rawValue))
      throw new Error(`${skillLabel}: [${group}] key '${key}' has malformed spacing around its value: ${JSON.stringify(raw)}`);
    const value = unquote(rawValue);
    // Re-check after unquoting: padding *inside* the quotes (e.g. `check: "
    // command -v git"`) is invisible to the outer check above.
    if (value.length === 0 || /^\s/.test(value) || /\s$/.test(value))
      throw new Error(`${skillLabel}: [${group}] key '${key}' has malformed spacing inside its quoted value: ${JSON.stringify(raw)}`);
    if (key in item) throw new Error(`${skillLabel}: [${group}] duplicate key '${key}' within one entry`);
    item[key] = value;
  }
  if (!item.id) throw new Error(`${skillLabel}: [${group}] entry missing required 'id'`);
  if (item.hard !== 'true' && item.hard !== 'false')
    throw new Error(
      `${skillLabel}: [${group}] entry '${item.id}' has hard=${JSON.stringify(item.hard)}, must be literal true/false`
    );
  item.hard = item.hard === 'true';
  if (!item.why) throw new Error(`${skillLabel}: [${group}] entry '${item.id}' missing required 'why'`);
  if (!item.hard && !item.fallback)
    throw new Error(
      `${skillLabel}: [${group}] entry '${item.id}' is hard:false but has no 'fallback' (mandatory whenever hard:false)`
    );
  if ('check' in item && !GROUPS_WITH_CHECK.has(group))
    throw new Error(`${skillLabel}: [${group}] entry '${item.id}' has a 'check' field — not allowed for this group`);
  if (group === 'context' && !CONTEXT_VOCAB.has(item.id))
    throw new Error(
      `${skillLabel}: [context] id '${item.id}' is not in the closed vocabulary (${[...CONTEXT_VOCAB].join(', ')})`
    );
  return item;
}

/**
 * Parses the `metadata.requires` subtree out of a SKILL.md frontmatter body
 * (the text between the `---` fences, fences excluded).
 *
 * Returns {} if the skill has no `metadata:` key at all (no requirements
 * declared — a legal, if degenerate, state). Throws on anything under
 * `metadata.requires` it does not understand.
 */
export function parseRequires(frontmatterText, skillLabel) {
  const lines = frontmatterText.replace(/\r\n/g, '\n').split('\n');
  const metaIdx = lines.findIndex((l) => l === 'metadata:');
  if (metaIdx === -1) return {};

  let i = metaIdx + 1;
  if (i >= lines.length || lines[i] !== '  requires:')
    throw new Error(
      `${skillLabel}: expected '  requires:' immediately after 'metadata:' at frontmatter line ${i + 1}, got ${JSON.stringify(lines[i] ?? '<eof>')}`
    );
  i++;

  const result = {};
  while (i < lines.length) {
    const line = lines[i];
    const groupMatch = line.match(/^ {4}(mcp|cli|skills|context|perms):$/);
    if (!groupMatch) {
      if (/^\S/.test(line)) break; // back to a top-level frontmatter key — done
      throw new Error(`${skillLabel}: unrecognized line under metadata.requires at line ${i + 1}: ${JSON.stringify(line)}`);
    }
    const group = groupMatch[1];
    if (result[group]) throw new Error(`${skillLabel}: duplicate group '${group}' under metadata.requires`);
    i++;

    const items = [];
    while (i < lines.length && /^ {6}- \S/.test(lines[i])) {
      const itemLines = [lines[i].slice(8)]; // strip "      - "
      i++;
      while (i < lines.length && /^ {8}\S/.test(lines[i])) {
        itemLines.push(lines[i].slice(8)); // strip 8-space continuation indent
        i++;
      }
      items.push(parseItem(itemLines, skillLabel, group));
    }
    if (items.length === 0) throw new Error(`${skillLabel}: group '${group}' has no entries`);
    result[group] = items;
  }
  return result;
}

/** List every `skills/*` directory name, sorted, for deterministic iteration. */
function listSkillNames(root) {
  const skillsDir = join(root, 'skills');
  return (
    existsSync(skillsDir)
      ? readdirSync(skillsDir).filter((d) => statSync(join(skillsDir, d)).isDirectory())
      : []
  ).sort();
}

/**
 * Reads one skill's SKILL.md and parses its `metadata.requires` frontmatter.
 * Shared by buildRequirements() (frontmatter -> requirements.json) and
 * checkPreflightAgreement() (frontmatter <-> inline table), so both walk the
 * exact same parse of the exact same file — no second, divergent code path.
 */
function loadSkill(root, name) {
  const skillLabel = `skills/${name}`;
  const p = join(root, 'skills', name, 'SKILL.md');
  if (!existsSync(p)) throw new Error(`${skillLabel}/SKILL.md not found`);
  const text = readFileSync(p, 'utf8');
  const fmMatch = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!fmMatch) throw new Error(`${skillLabel}/SKILL.md: no YAML frontmatter`);
  const requires = parseRequires(fmMatch[1], skillLabel);
  return { name, skillLabel, text, requires };
}

/** Builds the full requirements.json object in-memory from every skill's SKILL.md. */
export function buildRequirements(root) {
  const names = listSkillNames(root);
  const usedIds = new Set();
  const skillsOut = {};

  for (const name of names) {
    const { requires } = loadSkill(root, name);
    const hard = new Set();
    const soft = new Set();
    for (const group of GROUPS) {
      for (const item of requires[group] ?? []) {
        usedIds.add(item.id);
        (item.hard ? hard : soft).add(item.id);
      }
    }
    skillsOut[name] = { hard: [...hard].sort(), soft: [...soft].sort() };
  }

  const definitions = {};
  for (const id of [...usedIds].sort()) {
    const def = DEFINITIONS[id];
    if (!def)
      throw new Error(
        `no DEFINITIONS entry for id '${id}' (referenced by at least one skill's metadata.requires) — add one to scripts/gen-requirements.mjs`
      );
    definitions[id] = def;
  }

  return {
    $schema: 'https://github.com/jrsgacusan/juel-claude/blob/main/schema/requirements.schema.json',
    version: 1,
    definitions,
    skills: skillsOut,
  };
}

// --- Inline `## Preflight` table parsing (Task 12 review, round 1) ---------
//
// requirements.json is generated FROM frontmatter, so a diff between the two
// (buildRequirements() vs the committed file, done in validate.mjs check 6)
// only proves frontmatter and requirements.json agree with EACH OTHER. It
// says nothing about whether the inline `## Preflight` table — the
// representation the model actually reads at invoke time, per this file's
// header comment — still agrees with either. That is a real, independent
// drift surface: someone could edit the table (the thing that governs model
// behavior) without touching frontmatter (the thing tooling reads), and
// nothing would notice. This section closes that gap directly: it parses
// the table and diffs it against frontmatter, position by position within
// each dependency group. Combined with the existing frontmatter<->generated
// diff, any single-representation edit among the three is now caught by at
// least one of the two comparisons (transitivity covers the third pair).

const TYPE_TO_GROUP = { mcp: 'mcp', cli: 'cli', skill: 'skills', context: 'context', perm: 'perms' };
const TABLE_HEADER = ['Dep', 'Type', 'H/S', 'Check', 'If missing'];

/** Strips pure-markdown decoration (code spans, bold) and collapses whitespace, for comparison. */
function normalizeProse(s) {
  return s.replace(/`/g, '').replace(/\*\*/g, '').replace(/\s+/g, ' ').trim();
}

// A Dep cell's comma can mean two unrelated things: a genuine multi-id list
// ("juel:daily-worktrees, juel:ship-ticket" — two skill ids) or a single
// dependency described in prose that happens to contain a comma ("git
// worktree, cwd = root" — one context dependency). Blanket-splitting on
// every comma silently over-splits the second case (confirmed: it produced
// a spurious extra `context` row for `ship-ticket` and broke the table<->
// frontmatter count). The distinguishing signal used here: a genuine id list
// is comma-separated BARE IDENTIFIERS with no internal whitespace; prose
// contains spaces. Only split when EVERY resulting segment is bare-identifier
// shaped — otherwise treat the whole cell as one label.
const looksLikeId = (s) => /^[A-Za-z0-9][A-Za-z0-9:_./-]*$/.test(s);

function splitDepCell(depCell) {
  const raw = normalizeProse(depCell);
  const candidates = raw.split(',').map((s) => s.trim()).filter(Boolean);
  return candidates.length > 1 && candidates.every(looksLikeId) ? candidates : [raw];
}

function splitTableRow(line, skillLabel) {
  const trimmed = line.trim();
  if (!trimmed.startsWith('|') || !trimmed.endsWith('|'))
    throw new Error(`${skillLabel}: Preflight table row must start and end with '|': ${JSON.stringify(line)}`);
  return trimmed.slice(1, -1).split('|').map((c) => c.trim());
}

/**
 * Parses a skill's inline `## Preflight` markdown table into an ordered list
 * of rows: { label, group, hard, ifMissing }. A row whose Dep cell lists
 * several comma-separated ids (e.g. "juel:a, juel:b") expands to one entry
 * per id, in order, all sharing that row's group/hard/ifMissing — mirroring
 * how such a row was hand-expanded into separate frontmatter entries.
 *
 * Throws on any shape it does not recognize. A skill silently exempted from
 * the table<->frontmatter comparison is worse than no comparison at all.
 */
export function parsePreflightTable(skillMdText, skillLabel) {
  const lines = skillMdText.replace(/\r\n/g, '\n').split('\n');
  const headingIdx = lines.findIndex((l) => l.trim() === '## Preflight');
  if (headingIdx === -1) throw new Error(`${skillLabel}: no '## Preflight' heading found`);

  let i = headingIdx + 1;
  while (i < lines.length && !lines[i].startsWith('|')) {
    if (/^## /.test(lines[i])) throw new Error(`${skillLabel}: no Preflight table found before the next '## ' heading`);
    i++;
  }
  if (i >= lines.length) throw new Error(`${skillLabel}: no Preflight table found under '## Preflight'`);

  const header = splitTableRow(lines[i], skillLabel);
  if (header.length !== TABLE_HEADER.length || header.some((c, idx) => c !== TABLE_HEADER[idx]))
    throw new Error(`${skillLabel}: Preflight table header must be exactly ${JSON.stringify(TABLE_HEADER)}, got ${JSON.stringify(header)}`);
  i++;

  if (i >= lines.length) throw new Error(`${skillLabel}: Preflight table has a header but no separator row`);
  const sep = splitTableRow(lines[i], skillLabel);
  if (sep.length !== TABLE_HEADER.length || sep.some((c) => !/^:?-+:?$/.test(c)))
    throw new Error(`${skillLabel}: Preflight table separator row is malformed: ${JSON.stringify(lines[i])}`);
  i++;

  const rows = [];
  while (i < lines.length && lines[i].trim().startsWith('|')) {
    const cells = splitTableRow(lines[i], skillLabel);
    if (cells.length !== TABLE_HEADER.length)
      throw new Error(
        `${skillLabel}: Preflight table row has ${cells.length} cell(s), expected ${TABLE_HEADER.length}: ${JSON.stringify(lines[i])}`
      );
    const [depCell, typeCell, hsCell, , ifMissingCell] = cells;
    const group = TYPE_TO_GROUP[typeCell];
    if (!group)
      throw new Error(
        `${skillLabel}: Preflight table row has unknown Type '${typeCell}' (expected one of ${Object.keys(TYPE_TO_GROUP).join(', ')}): ${JSON.stringify(lines[i])}`
      );
    let hard;
    if (hsCell === 'HARD') hard = true;
    else if (hsCell === 'SOFT') hard = false;
    else
      throw new Error(`${skillLabel}: Preflight table row has unrecognized H/S '${hsCell}' (expected HARD or SOFT): ${JSON.stringify(lines[i])}`);
    const labels = splitDepCell(depCell);
    if (labels.length === 0 || labels.some((l) => l.length === 0))
      throw new Error(`${skillLabel}: Preflight table row has an empty Dep cell: ${JSON.stringify(lines[i])}`);
    for (const label of labels) rows.push({ label, group, hard, ifMissing: normalizeProse(ifMissingCell) });
    i++;
  }
  if (rows.length === 0) throw new Error(`${skillLabel}: Preflight table has a header row but no data rows`);
  return rows;
}

/**
 * Diffs a skill's inline Preflight table rows against its frontmatter
 * `requires`, group by group, POSITIONALLY: the frontmatter was hand-authored
 * in table order within each group (verified for all 11 skills — see
 * task-12-report.md), so entry N of a group's table rows must correspond to
 * entry N of that group's frontmatter array. This catches count drift
 * (row added/removed in only one place), HARD/SOFT flips, and — for SOFT
 * rows, where the table's "If missing" text is the frontmatter `fallback`
 * verbatim by construction — fallback-text drift.
 *
 * Returns an array of human-readable disagreement messages (empty = agree).
 * Never throws on disagreement (that is the caller's decision); parsing
 * failures upstream in parsePreflightTable() still throw.
 */
export function diffTableAndFrontmatter(skillLabel, tableRows, requires) {
  const issues = [];
  for (const group of GROUPS) {
    const tRows = tableRows.filter((r) => r.group === group);
    const fEntries = requires[group] ?? [];
    if (tRows.length !== fEntries.length) {
      issues.push(
        `${skillLabel} [${group}]: table<->frontmatter disagree on entry count — table has ${tRows.length} row(s), frontmatter has ${fEntries.length} entry(ies)`
      );
      continue; // positional comparison below is meaningless once lengths differ
    }
    for (let idx = 0; idx < tRows.length; idx++) {
      const t = tRows[idx];
      const f = fEntries[idx];
      if (t.hard !== f.hard) {
        issues.push(
          `${skillLabel} [${group}] position ${idx + 1} ('${t.label}' / frontmatter id '${f.id}'): table<->frontmatter disagree on HARD/SOFT — table says ${t.hard ? 'HARD' : 'SOFT'}, frontmatter says ${f.hard ? 'HARD' : 'SOFT'}`
        );
        continue;
      }
      if (!t.hard) {
        const fFallback = normalizeProse(f.fallback ?? '');
        if (t.ifMissing !== fFallback) {
          issues.push(
            `${skillLabel} [${group}] position ${idx + 1} (id '${f.id}'): table<->frontmatter disagree on the SOFT fallback text — table 'If missing' is ${JSON.stringify(t.ifMissing)}, frontmatter 'fallback' is ${JSON.stringify(fFallback)}`
          );
        }
      }
    }
  }
  return issues;
}

/**
 * Runs diffTableAndFrontmatter() for every skill in the plugin. Throws
 * immediately (does not skip) if any skill's table is not in the expected
 * shape — see parsePreflightTable(). Returns the combined issues array
 * (empty = every skill's table and frontmatter agree).
 */
export function checkPreflightAgreement(root) {
  const issues = [];
  for (const name of listSkillNames(root)) {
    const { skillLabel, text, requires } = loadSkill(root, name);
    const tableRows = parsePreflightTable(text, skillLabel);
    issues.push(...diffTableAndFrontmatter(skillLabel, tableRows, requires));
  }
  return issues;
}

function main() {
  const root = resolve(process.argv[2] ?? '.');
  const out = buildRequirements(root);
  const target = join(root, '.claude-plugin', 'requirements.json');
  writeFileSync(target, JSON.stringify(out, null, 2) + '\n');
  console.log(`wrote ${target}`);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
