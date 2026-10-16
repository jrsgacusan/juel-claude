import assert from 'node:assert/strict'
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { afterEach, beforeEach, test } from 'node:test'

import { cleanup, world } from './test-helpers.ts'
import type { World } from './test-helpers.ts'
import { asTracker, fromWorkSource, isTracker, resolveTracker, saveTracker } from './tracker.ts'

let w: World
beforeEach(async () => {
  w = await world()
})
afterEach(async () => {
  await cleanup(w)
})

const put = async (rel: string, content: unknown): Promise<void> => {
  const path = join(w.repo, rel)
  await mkdir(dirname(path), { recursive: true })
  await writeFile(path, typeof content === 'string' ? content : JSON.stringify(content))
}
const local = async (): Promise<unknown> => JSON.parse(await readFile(join(w.repo, '.claude/workflow.local.json'), 'utf8'))

test('no config anywhere resolves to null', async () => {
  assert.equal(await resolveTracker(w.repo), null)
})

test('workflow.local.json wins over workflow.json and the Work Source block', async () => {
  await put('.claude/workflow.local.json', { tracker: 'github' })
  await put('.claude/workflow.json', { tracker: { type: 'linear' } })
  await put('CLAUDE.md', '## Work Source\n- type: jira\n')
  assert.deepEqual(await resolveTracker(w.repo), { type: 'github', project: null })
})

test('the object form gives tracker.type and tracker.project', async () => {
  await put('.claude/workflow.local.json', { tracker: { type: 'linear', project: 'ENG', statusMap: {} } })
  assert.deepEqual(await resolveTracker(w.repo), { type: 'linear', project: 'ENG' })
})

test('workflow.json is read when the local file names no tracker', async () => {
  await put('.claude/workflow.local.json', { docsRoot: 'docs/x', tracker: { project: 'only' } })
  await put('.claude/workflow.json', { tracker: { type: 'jira' } })
  assert.deepEqual(await resolveTracker(w.repo), { type: 'jira', project: null })
})

test('a local file that is not valid JSON is skipped, not fatal', async () => {
  await put('.claude/workflow.local.json', '{ nope')
  await put('.claude/workflow.json', { tracker: 'linear' })
  assert.deepEqual(await resolveTracker(w.repo), { type: 'linear', project: null })
})

test('the Work Source block in CLAUDE.md, then in AGENTS.md', async () => {
  await put('AGENTS.md', '# Repo\n\n## Work Source\n- type: `github`\n')
  assert.deepEqual(await resolveTracker(w.repo), { type: 'github', project: null })
  await put('CLAUDE.md', '# Repo\n\n## Work Source\n- type: linear\n- project: ENG\n')
  assert.deepEqual(await resolveTracker(w.repo), { type: 'linear', project: 'ENG' })
})

test('the Work Source block ends at the next heading', () => {
  assert.equal(fromWorkSource('## Work Source\n\nSee below.\n\n## Other\n- type: jira\n'), null)
})

test('isTracker takes only the five answers', () => {
  for (const good of ['synapse', 'linear', 'jira', 'github', 'none']) assert.equal(isTracker(good), true)
  for (const bad of ['gitlab', 'file', '', null, 3]) assert.equal(isTracker(bad), false)
})

test('saving into a repo with no local file writes the object form', async () => {
  assert.deepEqual(await saveTracker(w.repo, 'github'), { ok: true })
  assert.deepEqual(await local(), { tracker: { type: 'github' } })
  assert.deepEqual(await resolveTracker(w.repo), { type: 'github', project: null })
})

test("saving keeps every other key, and the tracker object's own keys", async () => {
  await put('.claude/workflow.local.json', { docsRoot: 'docs/x', tracker: { type: 'linear', project: 'ENG', statusMap: { in_review: 'Review' } }, commands: { test: 'make test' } })
  assert.deepEqual(await saveTracker(w.repo, 'jira'), { ok: true })
  assert.deepEqual(await local(), { docsRoot: 'docs/x', tracker: { type: 'jira', project: 'ENG', statusMap: { in_review: 'Review' } }, commands: { test: 'make test' } })
})

test('a string tracker becomes the object form', async () => {
  await put('.claude/workflow.local.json', { tracker: 'github', x: 1 })
  await saveTracker(w.repo, 'none')
  assert.deepEqual(await local(), { tracker: { type: 'none' }, x: 1 })
})

test('a local file that is not a JSON object is refused and left as it was', async () => {
  for (const bad of ['{ nope', '[1, 2]', 'null']) {
    await put('.claude/workflow.local.json', bad)
    const saved = await saveTracker(w.repo, 'github')
    assert.equal(saved.ok, false)
    assert.match(saved.ok ? '' : saved.error, /workflow\.local\.json/)
    assert.equal(await readFile(join(w.repo, '.claude/workflow.local.json'), 'utf8'), bad)
  }
})

test('an empty or whitespace-only local file counts as {} and takes the answer (D14)', async () => {
  for (const blank of ['', '  \n\t\n']) {
    await put('.claude/workflow.local.json', blank)
    assert.deepEqual(await saveTracker(w.repo, 'github'), { ok: true })
    assert.deepEqual(await local(), { tracker: { type: 'github' } })
    assert.deepEqual(await resolveTracker(w.repo), { type: 'github', project: null })
  }
})

test('workflow.json wins over the Work Source block', async () => {
  await put('.claude/workflow.json', { tracker: { type: 'jira' } })
  await put('CLAUDE.md', '## Work Source\n- type: linear\n')
  assert.deepEqual(await resolveTracker(w.repo), { type: 'jira', project: null })
})

test('a CLAUDE.md with no Work Source block falls through to AGENTS.md', async () => {
  await put('CLAUDE.md', '# Repo\n\nNo tracker here.\n')
  await put('AGENTS.md', '## Work Source\n- type: github\n')
  assert.deepEqual(await resolveTracker(w.repo), { type: 'github', project: null })
})

test('a config file that is not valid JSON is skipped with a warning', async () => {
  await put('.claude/workflow.local.json', '{"tracker": "github",}')
  await put('.claude/workflow.json', { tracker: 'linear' })
  const warnings: string[] = []
  assert.deepEqual(await resolveTracker(w.repo, line => { warnings.push(line) }), { type: 'linear', project: null })
  assert.equal(warnings.length, 1)
  assert.match(warnings[0], /workflow\.local\.json: not valid JSON/)
})

test('asTracker ignores case, maps file and inline to none, and refuses the rest', () => {
  assert.equal(asTracker('Linear'), 'linear')
  assert.equal(asTracker('GITHUB'), 'github')
  assert.equal(asTracker('file'), 'none')
  assert.equal(asTracker('inline'), 'none')
  assert.equal(asTracker('gitlab'), null)
})

test('saving leaves no temp file behind', async () => {
  await saveTracker(w.repo, 'github')
  assert.deepEqual(await readdir(join(w.repo, '.claude')), ['workflow.local.json'])
})

test('two saves at once both land, one after the other, and the file holds the second', async () => {
  const [first, second] = await Promise.all([saveTracker(w.repo, 'github'), saveTracker(w.repo, 'linear')])
  assert.deepEqual(first, { ok: true })
  assert.deepEqual(second, { ok: true })
  assert.deepEqual(await local(), { tracker: { type: 'linear' } })
  assert.deepEqual(await readdir(join(w.repo, '.claude')), ['workflow.local.json'])
})

test('an empty local file is skipped without a warning (D14)', async () => {
  await put('.claude/workflow.local.json', '  \n')
  await put('.claude/workflow.json', { tracker: 'linear' })
  const warnings: string[] = []
  assert.deepEqual(await resolveTracker(w.repo, line => { warnings.push(line) }), { type: 'linear', project: null })
  assert.deepEqual(warnings, [])
})
