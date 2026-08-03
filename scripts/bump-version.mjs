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
//   5. If either validator fails, OR the process receives SIGINT/SIGTERM,
//      OR an uncaught exception is thrown — any of that, ANY TIME before
//      `git add` succeeds at the start of Step 6 — kill whatever subprocess
//      is currently running, restore plugin.json AND requirements.json to
//      their exact pre-bump bytes, and exit non-zero. Restore is
//      idempotent and safe to call with nothing yet written.
//      Once `git add` succeeds, the script stops rewriting files on
//      failure/interrupt (see the commit-failure branch below) — reverting
//      bytes that are already staged, or worse already committed, would
//      fight git's own history instead of protecting it.
//
//      Subprocesses are run with the ASYNC `child_process.spawn` (awaited),
//      never `spawnSync`, specifically so this all works. `spawnSync`
//      blocks the whole process in a native call — verified by direct
//      experiment: a SIGTERM sent to only this process's PID (not its
//      process group — the realistic shape of an automated `child.kill()`,
//      as opposed to an interactive terminal's whole-group Ctrl-C) while
//      blocked in `spawnSync` does NOT get delivered to a JS signal handler
//      until the ENTIRE remaining synchronous script has run to completion,
//      by which point a happy-path run has already committed and tagged —
//      the kill signal gets silently absorbed and the release completes
//      anyway. Await-based `spawn` keeps the event loop live the whole
//      time a child runs, so a signal handler fires immediately, and the
//      handler kills the in-flight child itself rather than waiting for it.
//
//      Honest scope of the resulting guarantee: SIGINT and SIGTERM are
//      handled; SIGKILL (`kill -9`) and an OOM-kill are not — POSIX gives a
//      process no way to trap those, so a bump killed that way can leave
//      plugin.json bumped and uncommitted. That state is always visible in
//      `git status` (nothing here can push a stray bump silently), but a
//      rerun should check `git status` first rather than assume a clean
//      slate.
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
import { spawn } from 'node:child_process';

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

// Tracks whichever child process is currently running, so a signal handler
// can kill it immediately instead of waiting for it to finish on its own.
// Null whenever no subprocess is in flight.
let currentChild = null;

/**
 * Runs a subprocess ASYNCHRONOUSLY (never spawnSync — see the header
 * comment for why that distinction is load-bearing for signal handling)
 * and resolves true iff it exited with status 0 and was not killed by a
 * signal.
 */
function run(cmd, args) {
  console.log(`\n$ ${cmd} ${args.join(' ')}`);
  return new Promise((resolvePromise) => {
    let child;
    try {
      child = spawn(cmd, args, { cwd: root, stdio: 'inherit' });
    } catch (e) {
      console.error(`error: failed to run ${cmd}: ${e.message}`);
      resolvePromise(false);
      return;
    }
    currentChild = child;
    child.on('error', (err) => {
      console.error(`error: failed to run ${cmd}: ${err.message}`);
      currentChild = null;
      resolvePromise(false);
    });
    child.on('close', (code, signal) => {
      currentChild = null;
      resolvePromise(code === 0 && signal === null);
    });
  });
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

// Flips to false once `git add` succeeds (start of Step 6). Past that
// point, restore() becomes a no-op: files are staged (or, later,
// committed), and rewriting them out from under git — on a failure, a
// signal, or an uncaught exception — would produce an ambiguous mix of
// "staged/committed at the new version, working tree reverted to the old
// one" rather than protecting anything. See the git-add/commit branches
// below.
let restorable = true;

/**
 * Restores plugin.json and requirements.json to their exact pre-bump bytes.
 * Idempotent and safe to call any number of times, including before Step 1
 * has written anything (writing back identical bytes is a no-op) and after
 * `restorable` has flipped to false (a no-op by design — see above).
 */
function restore() {
  if (!restorable) return;
  writeFileSync(pluginPath, originalPluginText);
  if (originalReqText !== null) writeFileSync(reqPath, originalReqText);
  // requirements.json did not exist before the bump — leave it as
  // gen-requirements.mjs left it only if nothing was written at all;
  // since we always ran gen-requirements.mjs in step 2, and it always
  // writes the file, "did not exist before" cannot occur in practice once
  // the plugin is set up correctly. Nothing further to do here.
}

/**
 * Handles SIGINT, SIGTERM, and uncaught exceptions the same way: kill
 * whatever subprocess is currently in flight (best-effort — it may already
 * be exiting on its own), restore (if still in the restorable window), and
 * exit non-zero. A handler that throws on an early Ctrl-C — before
 * originalPluginText etc. are even assigned — is worse than no handler,
 * but restore()'s own guards make that safe: `restorable` defaults true
 * and restore() only ever writes bytes it already captured synchronously
 * above, before this handler could possibly run.
 */
function handleTermination(label, detail) {
  console.error(`\n✘ ${label}${detail ? `: ${detail}` : ''}`);
  if (currentChild) {
    try { currentChild.kill('SIGTERM'); } catch { /* already exiting/exited — nothing to do */ }
  }
  if (restorable) {
    restore();
    console.error('Restored plugin.json and requirements.json to their pre-bump state. Nothing was committed or tagged.');
  } else {
    console.error(
      'This happened after `git add` began the release commit — plugin.json and requirements.json were NOT ' +
        'reverted (they may already be staged or committed at the new version). Run `git status` and `git log -1` ' +
        'to see exactly where this left off before retrying.'
    );
  }
  process.exit(1);
}

process.on('SIGINT', () => handleTermination('Received SIGINT'));
process.on('SIGTERM', () => handleTermination('Received SIGTERM'));
// Genuine bugs in this script should still surface loudly (the stack is
// printed below) — this handler adds cleanup on top of that, it does not
// replace or swallow the error.
process.on('uncaughtException', (err) => {
  handleTermination('Uncaught exception', err && err.stack ? err.stack : String(err));
});

// --- Step 1: bump plugin.json's version, write it -------------------------
console.log(`Bumping plugin.json version: ${fromVersion} -> ${toVersion} (${kind})`);
plugin.version = toVersion;
writeFileSync(pluginPath, JSON.stringify(plugin, null, 2) + '\n');

// --- Step 2: regenerate requirements.json ----------------------------------
const genOk = await run(process.execPath, [join(root, 'scripts', 'gen-requirements.mjs')]);
if (!genOk) {
  console.error('\n✘ gen-requirements.mjs failed — restoring plugin.json and requirements.json, nothing committed.');
  restore();
  process.exit(1);
}

// --- Step 3: node scripts/validate.mjs --------------------------------------
const validateOk = await run(process.execPath, [join(root, 'scripts', 'validate.mjs')]);

// --- Step 4: claude plugin validate . --strict ------------------------------
const claudeValidateOk = validateOk && (await run('claude', ['plugin', 'validate', '.', '--strict']));

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
const addOk = await run('git', ['add', '.claude-plugin/plugin.json', '.claude-plugin/requirements.json']);
if (!addOk) {
  console.error('\n✘ git add failed — restoring plugin.json and requirements.json.');
  restore();
  process.exit(1);
}
// Files are staged now — leave the restorable window. A SIGINT/SIGTERM/
// uncaught-exception or a commit failure past this point must not silently
// rewrite them; see handleTermination() and the commit-failure branch below.
restorable = false;
const commitMessage = `chore: release v${toVersion}`;
const commitOk = await run('git', ['commit', '-m', commitMessage]);
if (!commitOk) {
  console.error(
    '\n✘ git commit failed. plugin.json and requirements.json were staged but the working tree state is now ' +
      'ambiguous (git add already ran) — inspect `git status` and `git diff --cached` before retrying; ' +
      'this script will not attempt to unstage or restore past this point.'
  );
  process.exit(1);
}

// --- Step 7: create the release tag ------------------------------------------
const tagOk = await run('claude', ['plugin', 'tag', '.']);
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
