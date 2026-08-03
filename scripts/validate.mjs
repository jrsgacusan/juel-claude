#!/usr/bin/env node
// Zero-dependency validator for the juel plugin. Node 20+, ESM.
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, resolve, basename } from 'node:path';

const root = resolve(process.argv[2] ?? '.');
const SKIP = new Set((process.env.JUEL_VALIDATE_SKIP ?? '').split(',').filter(Boolean));
const problems = [];
const fail = (check, msg) => problems.push({ sev: 'ERROR', check, msg });
const warn = (check, msg) => problems.push({ sev: 'WARN', check, msg });

const readJson = (p) => {
  try { return JSON.parse(readFileSync(p, 'utf8')); }
  catch (e) { fail('manifest', `${p}: ${e.message}`); return null; }
};

// --- Check 1: manifests -----------------------------------------------------
const pluginPath = join(root, '.claude-plugin', 'plugin.json');
const marketPath = join(root, '.claude-plugin', 'marketplace.json');

let plugin = null;
if (!existsSync(pluginPath)) fail('manifest', 'missing .claude-plugin/plugin.json');
else {
  plugin = readJson(pluginPath);
  if (plugin) {
    if (!plugin.name) fail('manifest', 'plugin.json: name is required');
    if (!plugin.description) fail('manifest', 'plugin.json: description is required');
    if (!/^\d+\.\d+\.\d+$/.test(plugin.version ?? ''))
      fail('manifest', `plugin.json: version must be semver, got ${JSON.stringify(plugin.version)}`);
    if (plugin.dependencies !== undefined && !Array.isArray(plugin.dependencies))
      fail('manifest', 'plugin.json: dependencies must be an ARRAY (object form is a hard error)');
    for (const forbidden of ['requirements', 'metadata', 'x-requirements'])
      if (forbidden in plugin)
        fail('manifest', `plugin.json: '${forbidden}' is not a whitelisted field and fails --strict`);
  }
}

// marketplace.json is optional for fixtures, required for the real plugin
if (existsSync(marketPath)) {
  const market = readJson(marketPath);
  if (market) {
    if (!market.name) fail('manifest', 'marketplace.json: name is required');
    if (!market.owner) fail('manifest', 'marketplace.json: owner is required');
    const entries = market.plugins ?? [];
    if (!entries.length) fail('manifest', 'marketplace.json: plugins[] is empty');
    if (plugin && entries.length && entries[0].name !== plugin.name)
      fail('manifest',
        `marketplace entry name '${entries[0].name}' != plugin.json name '${plugin.name}'`);
    const isCrossMarketplace = (d) => {
      if (typeof d === 'string') return d.includes('@');
      if (d && typeof d === 'object') return Boolean(d.marketplace) || (typeof d.name === 'string' && d.name.includes('@'));
      return false;
    };
    const crossDeps = (Array.isArray(plugin?.dependencies) ? plugin.dependencies : [])
      .filter(isCrossMarketplace)
      .map((d) => (typeof d === 'string' ? d : (d.name ?? JSON.stringify(d))));
    if (crossDeps.length && !(market.allowCrossMarketplaceDependenciesOn ?? []).length)
      fail('manifest',
        'marketplace.json: allowCrossMarketplaceDependenciesOn is required when cross-marketplace ' +
        `dependencies are declared (${crossDeps.join(', ')}) — without it they are refused`);
    for (const e of entries)
      if (e.version !== undefined)
        warn('manifest', `marketplace entry '${e.name}' declares version; plugin.json wins — omit it`);
  }
}

// --- Skill discovery --------------------------------------------------------
const skillsDir = join(root, 'skills');
const skills = existsSync(skillsDir)
  ? readdirSync(skillsDir).filter((d) => statSync(join(skillsDir, d)).isDirectory())
  : [];

const frontmatterOf = (md) => {
  const m = md.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!m) return null;
  const out = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (kv) out[kv[1]] = kv[2];
  }
  return out;
};

const skillBodies = new Map(); // name -> full file text

// --- Check 2: skill frontmatter --------------------------------------------
for (const name of skills) {
  const p = join(skillsDir, name, 'SKILL.md');
  if (!existsSync(p)) { fail('skill', `skills/${name}/ has no SKILL.md`); continue; }
  const text = readFileSync(p, 'utf8');
  skillBodies.set(name, text);
  const fm = frontmatterOf(text);
  if (!fm) { fail('skill', `skills/${name}/SKILL.md: no YAML frontmatter`); continue; }
  if (fm.name !== name)
    fail('skill', `skills/${name}/SKILL.md: frontmatter name '${fm.name}' != directory '${name}'`);
  if (!fm.description || !fm.description.trim())
    fail('skill', `skills/${name}/SKILL.md: description is required`);
}

// --- Check 3: dangling juel: references ------------------------------------
const REF_RE = /(?:Skill\(\s*["']juel:([a-z0-9-]+)["']|\/juel:([a-z0-9-]+))/g;
const known = new Set(skills);
for (const [name, text] of skillBodies) {
  for (const m of text.matchAll(REF_RE)) {
    const target = m[1] ?? m[2];
    if (!known.has(target))
      fail('ref', `skills/${name}/SKILL.md references juel:${target}, which is not a skill`);
  }
}

// --- Check 4: stale juel- prefix -------------------------------------------
for (const [name, text] of skillBodies) {
  const lines = text.split(/\r?\n/);
  lines.forEach((line, i) => {
    if (line.includes('juel-'))
      fail('prefix', `skills/${name}/SKILL.md:${i + 1}: stale 'juel-' prefix — use 'juel:' — ${line.trim().slice(0, 80)}`);
  });
}

// --- Check 5: protocol marker ----------------------------------------------
const PROTOCOL_MARKER = '<!-- juel:protocol v1 -->';
if (!SKIP.has('protocol')) {
  for (const [name, text] of skillBodies) {
    if (!text.includes(PROTOCOL_MARKER))
      fail('protocol', `skills/${name}/SKILL.md: missing ${PROTOCOL_MARKER}`);
  }
}

// --- Report -----------------------------------------------------------------
export { root, skills, skillBodies, problems, fail, warn };

const errors = problems.filter((p) => p.sev === 'ERROR');
for (const p of problems) console.log(`${p.sev} ${p.check}: ${p.msg}`);
console.log(
  errors.length
    ? `\n✘ ${errors.length} error(s), ${problems.length - errors.length} warning(s)`
    : `\n✔ ${skills.length} skill(s) validated, ${problems.length} warning(s)`
);
process.exit(errors.length ? 1 : 0);
