#!/usr/bin/env node
// Bumps `.claude-plugin/plugin.json`'s version, regenerates and validates
// the plugin, commits, and creates the release tag. Zero-dependency ESM,
// Node 20+, `node:*` only.
//
// Order of operations (do not reorder — validation must happen BEFORE the
// commit exists, and the commit must exist BEFORE tagging):
//   1. Bump plugin.json's version in memory, write it to disk.
//   2. Regenerate .claude-plugin/requirements.json
//      (`node scripts/gen-requirements.mjs`).
//   3. Run `node scripts/validate.mjs`.
//   4. Run `claude plugin validate . --strict`.
//   5. If either validator fails: restore plugin.json AND
//      requirements.json to their exact pre-bump bytes and exit non-zero.
//      No half-applied state is left behind — a bumper that corrupts
//      version state on failure is worse than no bumper.
//   6. Commit `chore: release vX.Y.Z`.
//   7. Shell out to `claude plugin tag .` (creates the annotated tag
//      locally — does not push it).
//   8. Print (never run) the `git push --follow-tags` command — pushing a
//      tag is the point of no return and must be a deliberate keystroke.
//
// Why the bump matters operationally: the installed plugin cache is
// VERSION-GATED, not commit-gated (…/plugins/cache/juel-claude/juel/<version>/,
// named after plugin.json's semver). Pushing commits without bumping the
// version leaves `claude plugin marketplace update` serving stale content
// until an explicit uninstall/reinstall. The bump is not bookkeeping — it
// is what actually delivers new content to a machine. See the printed
// summary at the end of a successful run.
//
// Usage: node scripts/bump-version.mjs <patch|minor|major>

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const pluginPath = join(root, '.claude-plugin', 'plugin.json');
const reqPath = join(root, '.claude-plugin', 'requirements.json');

const BUMP_KINDS = new Set(['patch', 'minor', 'major']);

function usageError(msg) {
  console.error(`error: ${msg}`);
  console.error('usage: node scripts/bump-version.mjs <patch|minor|major>');
  process.exit(1);
}

const kind = process.argv[2];
if (!BUMP_KINDS.has(kind)) usageError(`bump kind must be one of patch|minor|major, got ${JSON.stringify(kind)}`);

function bumpSemver(version, kind) {
  const m = /^(\d+)\.(\d+)\.(\d+)$/.exec(version ?? '');
  if (!m) throw new Error(`plugin.json version is not semver: ${JSON.stringify(version)}`);
  let [major, minor, patch] = [Number(m[1]), Number(m[2]), Number(m[3])];
  if (kind === 'major') { major += 1; minor = 0; patch = 0; }
  else if (kind === 'minor') { minor += 1; patch = 0; }
  else { patch += 1; }
  return `${major}.${minor}.${patch}`;
}

/** Runs a subprocess, streaming its output, and returns true iff it succeeded. */
function run(cmd, args) {
  console.log(`\n$ ${cmd} ${args.join(' ')}`);
  const result = spawnSync(cmd, args, { cwd: root, stdio: 'inherit' });
  if (result.error) {
    console.error(`error: failed to run ${cmd}: ${result.error.message}`);
    return false;
  }
  return result.status === 0;
}

// --- Step 0: snapshot pre-bump bytes for exact restoration on failure ------
if (!existsSync(pluginPath)) {
  console.error(`error: ${pluginPath} does not exist`);
  process.exit(1);
}
const originalPluginText = readFileSync(pluginPath, 'utf8');
const originalReqText = existsSync(reqPath) ? readFileSync(reqPath, 'utf8') : null;

let plugin;
try {
  plugin = JSON.parse(originalPluginText);
} catch (e) {
  console.error(`error: plugin.json is not valid JSON: ${e.message}`);
  process.exit(1);
}

const fromVersion = plugin.version;
let toVersion;
try {
  toVersion = bumpSemver(fromVersion, kind);
} catch (e) {
  console.error(`error: ${e.message}`);
  process.exit(1);
}

/** Restores plugin.json and requirements.json to their exact pre-bump bytes. */
function restore() {
  writeFileSync(pluginPath, originalPluginText);
  if (originalReqText !== null) writeFileSync(reqPath, originalReqText);
  // requirements.json did not exist before the bump — leave it as
  // gen-requirements.mjs left it only if nothing was written at all;
  // since we always ran gen-requirements.mjs in step 2, and it always
  // writes the file, "did not exist before" cannot occur in practice once
  // the plugin is set up correctly. Nothing further to do here.
}

// --- Step 1: bump plugin.json's version, write it -------------------------
console.log(`Bumping plugin.json version: ${fromVersion} -> ${toVersion} (${kind})`);
plugin.version = toVersion;
writeFileSync(pluginPath, JSON.stringify(plugin, null, 2) + '\n');

// --- Step 2: regenerate requirements.json ----------------------------------
const genOk = run(process.execPath, [join(root, 'scripts', 'gen-requirements.mjs')]);
if (!genOk) {
  console.error('\n✘ gen-requirements.mjs failed — restoring plugin.json and requirements.json, nothing committed.');
  restore();
  process.exit(1);
}

// --- Step 3: node scripts/validate.mjs --------------------------------------
const validateOk = run(process.execPath, [join(root, 'scripts', 'validate.mjs')]);

// --- Step 4: claude plugin validate . --strict ------------------------------
const claudeValidateOk = validateOk && run('claude', ['plugin', 'validate', '.', '--strict']);

// --- Step 5: abort without writing anything on any validation failure ------
if (!validateOk || !claudeValidateOk) {
  console.error(
    `\n✘ Validation failed (${!validateOk ? 'node scripts/validate.mjs' : 'claude plugin validate . --strict'})` +
      ' — restoring plugin.json and requirements.json to their pre-bump state. Nothing committed, nothing tagged.'
  );
  restore();
  process.exit(1);
}

// --- Step 6: commit ----------------------------------------------------------
const addOk = run('git', ['add', '.claude-plugin/plugin.json', '.claude-plugin/requirements.json']);
if (!addOk) {
  console.error('\n✘ git add failed — restoring plugin.json and requirements.json.');
  restore();
  process.exit(1);
}
const commitMessage = `chore: release v${toVersion}`;
const commitOk = run('git', ['commit', '-m', commitMessage]);
if (!commitOk) {
  console.error(
    '\n✘ git commit failed. plugin.json and requirements.json were staged but the working tree state is now ' +
      'ambiguous (git add already ran) — inspect `git status` and `git diff --cached` before retrying; ' +
      'this script will not attempt to unstage or restore past this point.'
  );
  process.exit(1);
}

// --- Step 7: create the release tag ------------------------------------------
const tagOk = run('claude', ['plugin', 'tag', '.']);
if (!tagOk) {
  console.error(
    '\n✘ claude plugin tag . failed. The version-bump commit was already created ' +
      `(chore: release v${toVersion}) — no tag exists yet, so nothing has been pushed. Fix the tagging ` +
      'problem and re-run `claude plugin tag .` directly rather than re-running this script.'
  );
  process.exit(1);
}

// --- Step 8: print (never run) the push command ------------------------------
console.log(`\n✔ Committed and tagged v${toVersion}.`);
console.log(
  '\nThe installed plugin cache is version-gated (…/plugins/cache/juel-claude/juel/<version>/), not ' +
    "commit-gated: nothing before the tag you are about to push changes what 'claude plugin marketplace " +
    `update' reaches for. Pushing the v${toVersion} tag below is what actually makes this release land on a ` +
    'machine that updates.'
);
console.log('\nPushing a tag is the point of no return — run this yourself when ready:\n');
console.log('  git push --follow-tags');
