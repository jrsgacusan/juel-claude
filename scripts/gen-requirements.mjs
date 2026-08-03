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
// docs/design/research/design-preflight.md §3.1. A context id outside this
// set is treated as unparseable, not silently accepted.
const CONTEXT_VOCAB = new Set([
  'git-repo',
  'git-worktree',
  'worktree-root-cwd',
  'clean-tree',
  'open-pr',
  'plan-file',
  'cmux-session',
  'interactive-user',
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
  simplify: { kind: 'skill', label: 'simplify', install: 'Built-in Claude Code skill' },
  run: { kind: 'skill', label: 'run', install: 'Built-in Claude Code skill' },
  'juel:regression': {
    kind: 'skill',
    label: 'juel:regression',
    install: 'Ships with this plugin (not implemented yet — a later task adds it)',
  },

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
    const m = raw.match(/^(id|hard|why|check|fallback):\s?(.*)$/);
    if (!m) throw new Error(`${skillLabel}: [${group}] unrecognized line in entry: ${JSON.stringify(raw)}`);
    const [, key, rawValue] = m;
    if (key in item) throw new Error(`${skillLabel}: [${group}] duplicate key '${key}' within one entry`);
    item[key] = unquote(rawValue);
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

/** Builds the full requirements.json object in-memory from every skill's SKILL.md. */
export function buildRequirements(root) {
  const skillsDir = join(root, 'skills');
  const names = (
    existsSync(skillsDir)
      ? readdirSync(skillsDir).filter((d) => statSync(join(skillsDir, d)).isDirectory())
      : []
  ).sort();

  const usedIds = new Set();
  const skillsOut = {};

  for (const name of names) {
    const skillLabel = `skills/${name}`;
    const p = join(skillsDir, name, 'SKILL.md');
    if (!existsSync(p)) throw new Error(`${skillLabel}/SKILL.md not found`);
    const text = readFileSync(p, 'utf8');
    const fmMatch = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
    if (!fmMatch) throw new Error(`${skillLabel}/SKILL.md: no YAML frontmatter`);

    const requires = parseRequires(fmMatch[1], skillLabel);
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

function main() {
  const root = resolve(process.argv[2] ?? '.');
  const out = buildRequirements(root);
  const target = join(root, '.claude-plugin', 'requirements.json');
  writeFileSync(target, JSON.stringify(out, null, 2) + '\n');
  console.log(`wrote ${target}`);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
