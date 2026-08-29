#!/usr/bin/env node
// Links the superpowers skills this plugin hard-depends on into
// ~/.agents/skills/, the shared cross-agent skill root Codex reads directly.
//
// Why this exists: Codex has no cross-marketplace dependency resolution, so
// .claude-plugin/plugin.json's `dependencies` array is ignored on a Codex
// install and superpowers never arrives. Worse, Codex treats each DIRECT
// CHILD of ~/.agents/skills/ as one skill and looks for <child>/SKILL.md — it
// does not recurse. So a single link pointing at superpowers' whole skills/
// directory surfaces NOTHING; each skill must be linked individually.
//
// The link targets live in a version-pinned plugin cache path that moves on
// every superpowers update, so this script is idempotent and re-runnable, and
// `juel:doctor` reports broken or stale links rather than letting a HARD
// dependency fail at invoke time.
//
// Usage: node scripts/link-agent-skills.mjs [--dry-run]

import { existsSync, lstatSync, mkdirSync, readdirSync, readlinkSync, rmSync, symlinkSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const DRY_RUN = process.argv.includes('--dry-run');
const SKILLS = ['brainstorming', 'writing-plans', 'receiving-code-review'];
const agentsSkills = join(homedir(), '.agents', 'skills');

/**
 * Finds the newest superpowers skills/ directory across both known Claude
 * config roots. Versions are semver-named directories, and lexical sort is
 * wrong past single digits (6.10.0 < 6.3.0), so compare numerically.
 */
function findSuperpowersSkills() {
  const roots = [
    join(homedir(), '.claude-personal', 'plugins', 'cache', 'claude-plugins-official', 'superpowers'),
    join(homedir(), '.claude', 'plugins', 'cache', 'claude-plugins-official', 'superpowers'),
  ];
  const candidates = [];
  for (const root of roots) {
    if (!existsSync(root)) continue;
    for (const entry of readdirSync(root)) {
      const m = /^(\d+)\.(\d+)\.(\d+)$/.exec(entry);
      if (!m) continue;
      const skills = join(root, entry, 'skills');
      if (existsSync(skills)) candidates.push({ skills, v: [+m[1], +m[2], +m[3]] });
    }
  }
  candidates.sort((a, b) => b.v[0] - a.v[0] || b.v[1] - a.v[1] || b.v[2] - a.v[2]);
  return candidates[0]?.skills ?? null;
}

const source = findSuperpowersSkills();
if (!source) {
  console.error('error: no superpowers plugin cache found. Install it in Claude Code first:');
  console.error('  /plugin install superpowers@claude-plugins-official');
  process.exit(1);
}
console.log(`superpowers skills: ${source}`);

if (!DRY_RUN) mkdirSync(agentsSkills, { recursive: true });

let changed = 0;
let ok = 0;

// The pre-existing `superpowers` link points at a directory of skills, which
// Codex cannot read (no recursion). Remove it if present so it stops looking
// like the dependency is satisfied.
const legacy = join(agentsSkills, 'superpowers');
let legacyIsLink = false;
try { legacyIsLink = lstatSync(legacy).isSymbolicLink(); } catch { /* absent */ }
if (legacyIsLink) {
  console.log(`remove  superpowers -> ${readlinkSync(legacy)} (points at a directory of skills; Codex does not recurse)`);
  if (!DRY_RUN) rmSync(legacy);
  changed++;
}

for (const name of SKILLS) {
  const target = join(source, name);
  const link = join(agentsSkills, name);

  if (!existsSync(target)) {
    console.error(`error: ${name} not found at ${target}`);
    process.exitCode = 1;
    continue;
  }

  let current = null;
  let isLink = false;
  try {
    isLink = lstatSync(link).isSymbolicLink();
    if (isLink) current = readlinkSync(link);
  } catch { /* absent */ }

  if (current === target) {
    console.log(`ok      ${name}`);
    ok++;
    continue;
  }
  if (!isLink && existsSync(link)) {
    console.error(`error: ${link} exists and is not a symlink — refusing to replace it`);
    process.exitCode = 1;
    continue;
  }
  console.log(`${isLink ? 'relink' : 'link  '}  ${name} -> ${target}`);
  if (!DRY_RUN) {
    if (isLink) rmSync(link);
    symlinkSync(target, link);
  }
  changed++;
}

console.log(`\n${DRY_RUN ? '[dry run] ' : ''}${ok} already correct, ${changed} changed`);
if (!DRY_RUN && changed > 0) console.log('Start a new Codex thread to pick up the new skills.');
