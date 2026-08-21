#!/usr/bin/env node
// Zero-dependency validator for the juel plugin. Node 20+, ESM.
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, resolve, basename } from 'node:path';
import { buildRequirements, checkPreflightAgreement } from './gen-requirements.mjs';

const root = resolve(process.argv[2] ?? '.');
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
const PROTOCOL_MARKER = '<!-- juel:protocol v5 -->';
for (const [name, text] of skillBodies) {
  if (!text.includes(PROTOCOL_MARKER))
    fail('protocol', `skills/${name}/SKILL.md: missing ${PROTOCOL_MARKER}`);
}

// --- Check 6: declaration agreement -----------------------------------------
// A real 3-way check across all three representations of a skill's
// requirements: the inline `## Preflight` markdown table (what the model
// reads at invoke time), the frontmatter `metadata.requires` block (tooling
// source), and the generated `.claude-plugin/requirements.json` (tooling
// rollup). Every id used in a frontmatter block must also have a
// `definitions` entry with an install hint.
//
// Two independent comparisons together guarantee all three pairs agree
// (equality is transitive — if A=B and B=C then A=C):
//   1. table <-> frontmatter, position-by-position within each dependency
//      group (checkPreflightAgreement, in gen-requirements.mjs).
//   2. frontmatter <-> generated file, by regenerating requirements.json
//      in memory (buildRequirements, which walks the same frontmatter this
//      comparison also reads) and diffing it against the committed file.
// A skill whose table is not in the expected shape makes
// checkPreflightAgreement THROW rather than silently skip that skill.
{
  const reqPath = join(root, '.claude-plugin', 'requirements.json');
  try {
    // 1. table <-> frontmatter, per skill, per group, positionally.
    for (const issue of checkPreflightAgreement(root)) fail('requirements', issue);

    // 2. frontmatter <-> generated file, by exact regenerate-and-diff.
    const generated = buildRequirements(root);
    if (!existsSync(reqPath)) {
      fail('requirements', '.claude-plugin/requirements.json is missing — run `node scripts/gen-requirements.mjs`');
    } else {
      let committed;
      try {
        committed = JSON.parse(readFileSync(reqPath, 'utf8'));
      } catch (e) {
        fail('requirements', `.claude-plugin/requirements.json: invalid JSON — ${e.message}`);
      }
      if (committed !== undefined && JSON.stringify(committed) !== JSON.stringify(generated)) {
        fail(
          'requirements',
          '.claude-plugin/requirements.json is stale (disagrees with frontmatter metadata.requires) — run `node scripts/gen-requirements.mjs` to regenerate'
        );
      }
    }
  } catch (e) {
    fail('requirements', `metadata.requires / Preflight table: ${e.message}`);
  }
}

// --- Check 7: docsRoot write sites must state a no-overwrite rule ----------
// User's rule, from memory: plans, specs, findings reports and context files
// under docsRoot are NEVER overwritten — on a name collision, the next
// available `-vN` suffix is used instead. v1.2.0 shipped two violations of
// that rule: `ship-ticket` writes a spec and a plan under docsRoot and says
// nothing about collisions at either site; `review-pr` said the opposite
// ("Overwrite it") for its findings report. Both slipped through because the
// rule was restated independently per skill instead of living somewhere a
// check can verify. This check turns both defect classes into a hard
// validation failure.
//
// A "write site" is a line where this skill itself (not a delegated skill it
// invokes) names a concrete path under `${docsRoot}` with a specific
// specs/plans/context/findings subdirectory, either as an imperative
// ("Write the report to `${docsRoot}/findings/...`", "write to
// `${docsRoot}/plans/...`") or as a labeled path bullet ("- Path:
// `${docsRoot}/specs/...`", "- Plan path: `${docsRoot}/plans/...`"). A
// mention that only reads (`ls`, "newest ${docsRoot}/plans/*.md", a plan
// argument example) never matches this shape — this is what correctly
// excludes `execute`, which only reads plans, without hardcoding its name.
// A mention that explicitly delegates the write ("...lives in
// `juel:review-pr`, not here") is excluded too — this is what correctly
// excludes `cmux-review-pr`, whose overview prose happens to name the exact
// path `juel:review-pr` itself writes.
//
// For every write-capable skill, the whole file (again excluding lines that
// describe a DELEGATED skill's write, e.g. "`superpowers:writing-plans` →
// writes to ... review-plan.md" — a real decoy found in `ship-ticket` that
// names a *different* file than the ones actually missing the rule) must
// contain either an explicit `-v2`/`-vN` collision suffix, or "overwrite"
// used as a PROHIBITION (immediately preceded by never/don't/do not/must
// not/cannot/can't). An "overwrite" mention that is not a prohibition is a
// contradiction and fails immediately, regardless of anything else in the
// file — this is what catches `review-pr`'s "Overwrite it" edge-case row.
// A skill whose write sites are found here always enters this check; none
// are silently exempted — a write-capable skill with no rule fails loudly,
// naming the skill and the line(s) that need one.
{
  const DOCSROOT_SUBDIR_RE = /\$\{?docsRoot\}?\/(specs|plans|context|findings)\//;
  const WRITE_VERB_RE = /(?<![-\w])(write|writes|writing|written)(?![-\w])/i;
  const PATH_LABEL_RE = /^\s*-?\s*\**(spec |plan )?path\**:\s*`?\$\{?docsRoot\}?\/(specs|plans|context|findings)\//i;
  const DELEGATION_DISCLAIMER_RE = /\b(lives in `juel:|does not resolve|does not write|not here)\b/i;
  const DELEGATED_WRITE_LINE_RE = /`\/?(?:juel|superpowers|pr-review-toolkit):[a-z0-9-]+`[^\n]*\bwrites?\b/i;
  const OVERWRITE_TOKEN_RE = /overwrit\w*/gi;
  const VERSIONING_TOKEN_RE = /-v(2|N)\b/;
  const NEGATION_TAIL_RE = /\b(never|don't|do not|must not|cannot|can't|not)\b\s*$/i;

  for (const [name, text] of skillBodies) {
    const lines = text.split(/\r?\n/);

    // Locate write sites: category A (write verb + concrete docsRoot path,
    // same line, no delegation disclaimer) or category B (a Path:/Plan
    // path:/Spec path: label naming a concrete docsRoot path).
    const writeSiteLines = [];
    lines.forEach((line, i) => {
      if (DELEGATION_DISCLAIMER_RE.test(line) || DELEGATED_WRITE_LINE_RE.test(line)) return;
      if (DOCSROOT_SUBDIR_RE.test(line) && WRITE_VERB_RE.test(line)) { writeSiteLines.push(i + 1); return; }
      if (PATH_LABEL_RE.test(line)) writeSiteLines.push(i + 1);
    });
    if (writeSiteLines.length === 0) continue; // read-only, or no docsRoot write at all

    // Whole-file scan for a stated rule, excluding lines that describe a
    // DELEGATED skill's own write (a decoy naming a different file).
    let hasProhibition = false;
    let hasVersioning = false;
    const contradictions = [];

    lines.forEach((line, i) => {
      if (DELEGATED_WRITE_LINE_RE.test(line)) return;

      if (VERSIONING_TOKEN_RE.test(line)) hasVersioning = true;

      OVERWRITE_TOKEN_RE.lastIndex = 0;
      let m;
      while ((m = OVERWRITE_TOKEN_RE.exec(line))) {
        const trimmed = line.trim();
        const isTableRow = trimmed.startsWith('|') && trimmed.endsWith('|');
        if (isTableRow) {
          const cells = trimmed.slice(1, -1).split('|').map((c) => c.trim()).filter(Boolean);
          const lastCell = cells[cells.length - 1] ?? '';
          const idx = lastCell.toLowerCase().indexOf('overwrit');
          if (idx === -1) continue; // named only as the mistake label, not the instruction cell
          if (NEGATION_TAIL_RE.test(lastCell.slice(0, idx))) hasProhibition = true;
          else contradictions.push({ line: i + 1, text: trimmed });
        } else {
          if (NEGATION_TAIL_RE.test(line.slice(Math.max(0, m.index - 30), m.index))) hasProhibition = true;
          else contradictions.push({ line: i + 1, text: line.trim() });
        }
      }
    });

    if (contradictions.length) {
      for (const c of contradictions)
        fail('docsroot',
          `skills/${name}/SKILL.md:${c.line}: instructs OVERWRITING a file under docsRoot instead of ` +
          `versioning it (never overwrite; append -v2, then -v3, ... on collision) — "${c.text.slice(0, 110)}"`);
    } else if (!hasProhibition && !hasVersioning) {
      fail('docsroot',
        `skills/${name}/SKILL.md: writes under docsRoot (line ${writeSiteLines.join(', ')}) but states no ` +
        'no-overwrite/-vN versioning rule anywhere in the file — add one (never overwrite; append -v2, ' +
        'then -v3, ... on collision)');
    }
  }
}

// --- Check 8: codex exec sites must background, wait, and report outcome --
// Root-caused defect (v1.2.1): rule 4 said `codex exec` was FOREGROUND-ONLY,
// but the Bash tool's own spec caps `timeout` at 600000ms (10 minutes) — a
// real `codex exec` run applying a plan routinely exceeds that, so the
// harness silently DETACHES it at the cap regardless of what the skill
// says. That detach is uncontrolled: nothing is watching, nothing reads the
// output, and the skill proceeds as if the phase had ended. The fix
// separates two properties rule 4 had conflated — WATCHED (what the user
// actually wants: visibility into progress) and BLOCKING (the property with
// the 600s ceiling). Backgrounding while leaving output un-redirected gives
// the first without the second. `pr-review-toolkit:review-pr` and
// `code-simplifier` are unaffected — they run through the Skill/Agent tool,
// which carries no such cap — so ONLY codex sites must flip.
//
// A "codex exec invocation site" is a line that, trimmed, starts with the
// literal `codex exec --sandbox` — the actual dispatch command, not a `dot`
// graph label or a Common-Mistakes-table mention of the phrase. For each
// site this check reads the surrounding section — from the nearest
// preceding markdown heading through the next one — and requires that
// section to state:
//   1. `run_in_background: true` present. `run_in_background: false`
//      anywhere in the section is an immediate, unconditional failure — it
//      is the exact defect this check exists to catch, not merely one more
//      missing item.
//   2. A wait-for-exit phrase ("wait for it/codex to exit/complete/finish")
//      — backgrounding must never become fire-and-forget.
//   3. An outcome-reporting phrase (exit status / files changed) — the
//      phase is marked done from the *outcome*, not a printed transcript.
//   4. `< /dev/null` on the invocation line itself. Root-caused defect
//      (v1.4.1, reproduced live): `codex exec --help` states that if stdin
//      is piped and a prompt is also given as an argument, stdin is
//      appended as a `<stdin>` block — and the Bash tool pipes stdin and
//      never closes it. Every real site omitted stdin redirection, so
//      `codex exec 'prompt'` printed "Reading additional input from
//      stdin..." and hung forever waiting for an EOF that never arrives —
//      the prompt argument is never processed. It looks exactly like a
//      working executor running quietly, which is what makes it dangerous.
//      `< /dev/null` gives codex an immediate EOF so it proceeds instead.
// A site whose section shows none of this — no true, no false, no wait, no
// outcome language, no `< /dev/null` — is a FAIL, not a skip: a codex site
// this check cannot positively confirm as backgrounded-and-waited-on-and-
// unblocked-on-stdin is exactly the silently-exempted-site failure mode
// this plugin keeps producing (eleven confirmed instances across prior
// checks). There is no "can't tell, pass it" branch here.
//
// Like check 7, this is a closed-set heuristic tuned to the phrasing this
// codebase currently uses ("Run this in the **background**
// (`run_in_background: true`)", "wait for it to exit", "state the exit
// status and files changed", "< /dev/null"). A future rewrite that says the
// same thing in different words can defeat it; a human touching rule 4's
// prose again is expected to re-tune these patterns, not trust them
// blindly.
{
  const CODEX_EXEC_LINE_RE = /^codex exec\s+--sandbox\b/;
  const HEADING_RE = /^#{1,6}\s/;
  const BG_TRUE_RE = /run_in_background:\s*true/i;
  const BG_FALSE_RE = /run_in_background:\s*false/i;
  const WAIT_EXIT_RE = /\bwait(?:ing)?\s+for\s+(?:it|codex)\s+to\s+(?:exit|complete|finish)\b/i;
  const OUTCOME_RE = /\b(exit status|files changed)\b/i;
  const DEVNULL_STDIN_RE = /<\s*\/dev\/null\b/;

  for (const [name, text] of skillBodies) {
    const lines = text.split(/\r?\n/);
    lines.forEach((line, i) => {
      if (!CODEX_EXEC_LINE_RE.test(line.trim())) return;

      let sectionStart = i;
      while (sectionStart > 0 && !HEADING_RE.test(lines[sectionStart - 1])) sectionStart--;
      let sectionEnd = i + 1;
      while (sectionEnd < lines.length && !HEADING_RE.test(lines[sectionEnd])) sectionEnd++;
      const section = lines.slice(sectionStart, sectionEnd).join('\n');
      const lineNo = i + 1;

      if (BG_FALSE_RE.test(section)) {
        fail('codex-bg',
          `skills/${name}/SKILL.md:${lineNo}: codex exec site declares run_in_background: false — codex ` +
          'exec runs through the Bash tool (600s timeout cap), so it must always background ' +
          '(run_in_background: true), wait for exit, then report the outcome — see rule 4');
        return;
      }
      if (!BG_TRUE_RE.test(section)) {
        fail('codex-bg',
          `skills/${name}/SKILL.md:${lineNo}: codex exec site does not state run_in_background: true — ` +
          'backgrounding must be explicit at the invocation site, not implied by the shared protocol block alone');
        return;
      }
      if (!WAIT_EXIT_RE.test(section)) {
        fail('codex-bg',
          `skills/${name}/SKILL.md:${lineNo}: codex exec site backgrounds but states no wait-for-exit step — ` +
          'add "wait for it to exit" so backgrounding does not become fire-and-forget');
      }
      if (!OUTCOME_RE.test(section)) {
        fail('codex-bg',
          `skills/${name}/SKILL.md:${lineNo}: codex exec site does not state outcome reporting (exit status / ` +
          'files changed) — report the outcome at exit, not a transcript');
      }
      if (!DEVNULL_STDIN_RE.test(line)) {
        fail('codex-bg',
          `skills/${name}/SKILL.md:${lineNo}: codex exec invocation is missing '< /dev/null' — the Bash tool ` +
          'pipes stdin and never closes it, and codex appends piped stdin (waiting for EOF) when a prompt is ' +
          'also given as an argument, so without this redirect codex hangs forever and the prompt is never ' +
          'processed — see rule 4');
      }
    });
  }
}

// --- Check 9: Phases section must be a plain numbered list mapped to TaskCreate --
// Root-caused defect (v1.4.1): v1.1.0 rewrote the shared protocol block's
// rules 1-3 from "print a phase checklist" to "create one task per phase via
// TaskCreate, update status via TaskUpdate, never re-print the checklist as
// text" — but the 12 per-skill `## Phases` sections were never updated to
// match. They still read as literal `[ ] N. ...` markdown checkboxes, which
// reads as an instruction to render the list as text, not to enumerate it
// into TaskCreate calls — and printing wins. TaskCreate itself appeared only
// in the shared protocol block, never once in a skill's own Phases text.
// This check enforces the agreed replacement shape: a plain numbered list,
// with one line directly under the heading stating the TaskCreate mapping,
// byte-identical across every skill — like the protocol and docsRoot blocks.
//
// Like checks 7 and 8, this is a closed-set heuristic tuned to the current
// phrasing of the Phases section and the mapping line, not a general
// markdown/task parser. A future rewrite of the mapping sentence must update
// TASKCREATE_MAPPING_LINE here too, in lockstep with all 12 skills.
//
// Same strictness as checks 7 and 8: a Phases section this check cannot
// positively confirm as a clean numbered list with the mapping line present
// is a FAIL, not a skip — a silently-exempted skill is this plugin's most
// recurrent defect class (eleven confirmed instances before this one).
{
  const PHASES_HEADING_RE = /^## Phases\s*$/;
  const HEADING_RE = /^#{1,6}\s/;
  const CHECKBOX_RE = /\[[ xX-]\]/;
  const NUMBERED_ITEM_RE = /^\s*\d+\.\s+\S/;
  const TASKCREATE_MAPPING_LINE =
    'This list is the source for `TaskCreate`: one task per phase, `subject` is the phase name, `activeForm` is its present-continuous form, all created before any other work.';

  for (const [name, text] of skillBodies) {
    const lines = text.split(/\r?\n/);
    const headingIdx = lines.findIndex((l) => PHASES_HEADING_RE.test(l));
    if (headingIdx === -1) {
      fail('phases', `skills/${name}/SKILL.md: no '## Phases' section found`);
      continue;
    }
    let sectionEnd = headingIdx + 1;
    while (sectionEnd < lines.length && !HEADING_RE.test(lines[sectionEnd])) sectionEnd++;
    const section = lines.slice(headingIdx + 1, sectionEnd);

    // Checkbox syntax anywhere in the section — including inline/backticked
    // examples, not just list-item starts — is an immediate fail.
    section.forEach((line, i) => {
      if (CHECKBOX_RE.test(line))
        fail('phases',
          `skills/${name}/SKILL.md:${headingIdx + 2 + i}: Phases section still has checkbox syntax ` +
          '([ ]/[x]/[-]) — convert to a plain numbered list; TaskCreate/TaskUpdate is the checklist now, ' +
          `not printed text — "${line.trim().slice(0, 100)}"`);
    });

    // The TaskCreate-mapping line must be the first non-blank line under the
    // heading, and byte-identical to the canonical text.
    const firstContentIdx = section.findIndex((l) => l.trim() !== '');
    if (firstContentIdx === -1 || section[firstContentIdx] !== TASKCREATE_MAPPING_LINE) {
      fail('phases',
        `skills/${name}/SKILL.md: '## Phases' section is missing the TaskCreate-mapping line, or it is not ` +
        `byte-identical to the canonical text — it must read exactly: "${TASKCREATE_MAPPING_LINE}"`);
    }

    // Confidence check: a real numbered list must be present, or this check
    // cannot confirm the shape and fails rather than silently passing.
    const numberedLines = section.filter((l) => NUMBERED_ITEM_RE.test(l));
    if (numberedLines.length === 0) {
      fail('phases',
        `skills/${name}/SKILL.md: '## Phases' section has no parsable numbered list (expected '1. ...', ` +
        `'2. ...' lines) — cannot confirm shape, failing rather than silently passing`);
    }
  }
}

// --- Check 10: rule 6 (Idling verification) must be present in the shared
// protocol block --------------------------------------------------------
// Root-caused defect (this task): a background subagent dispatch (this
// plugin's `pr-review-toolkit:review-pr`/`code-simplifier`) can sit at an
// `Idling` status that looks identical whether the agent is still working or
// has already finished and is simply waiting to be read — three separate
// Anthropic-acknowledged, closed-as-not-planned bugs (GitHub #21048, #17011,
// #54323) confirm this is a real, unfixed gap in the harness's own
// notification pipeline, not a hypothetical. Rule 6 fixes this by requiring
// a `ListAgents` check before a skill concludes "no output" or re-dispatches
// — but since the shared protocol block is duplicated by hand across all 12
// skills with no automated identity check (see Task 1's Global Constraints),
// rule 6 could silently go missing from one skill on a future edit exactly
// like the eleven prior instances of this defect class (see checks 8 and 9's
// own comments). This check closes that gap for rule 6 specifically: every
// skill must carry both the v5 marker and rule 6's canonical lead sentence,
// byte-identical.
{
  const PROTOCOL_MARKER_V5 = '<!-- juel:protocol v5 -->';
  const RULE6_LEAD =
    '**6. `Idling` is a status, not a verdict — never read it as "returned nothing."**';

  for (const [name, text] of skillBodies) {
    if (!text.includes(PROTOCOL_MARKER_V5))
      fail('protocol-v5', `skills/${name}/SKILL.md: missing ${PROTOCOL_MARKER_V5} — rule 6 requires the v5 marker`);
    if (!text.includes(RULE6_LEAD))
      fail('protocol-v5', `skills/${name}/SKILL.md: missing rule 6's canonical lead sentence — it must read exactly: ${RULE6_LEAD}`);
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
