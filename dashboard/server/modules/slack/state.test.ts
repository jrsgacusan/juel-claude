import assert from 'node:assert/strict'
import { mkdir, readdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import {
  KEEP_MS,
  StateError,
  prune,
  readEveryMin,
  readRoutes,
  readSeen,
  readStatus,
  readUnrouted,
  slackDir,
  writeRoutes,
  writeSeen,
  writeStatus,
} from './state.ts'
import type { Entry } from './state.ts'
import { cleanup, msg, world, writeState } from './test-helpers.ts'

const NOW = new Date('2026-10-16T12:00:00.000Z')

test('a missing state file is its default, and the folder follows HOME', async () => {
  const w = await world()
  assert.equal(slackDir(), join(w.home, '.juel', 'slack'))
  assert.deepEqual(await readSeen(), {})
  assert.deepEqual(await readRoutes(), {})
  assert.deepEqual(await readUnrouted(), [])
  assert.deepEqual(await readStatus('haiku'), { connected: false, lastCheck: null, error: null, model: 'haiku', workspace: null })
  await cleanup(w)
})

test('a damaged state file is a StateError, never read as empty', async () => {
  const w = await world()
  const cases: [string, string, () => Promise<unknown>, RegExp][] = [
    ['seen.json', '{not json', readSeen, /seen\.json is not JSON/],
    ['seen.json', '[]', readSeen, /seen\.json does not hold/],
    ['seen.json', '{"C1-1.2": {"seenAt": 1}}', readSeen, /seen\.json does not hold/],
    ['routes.json', '{"C1": 3}', readRoutes, /routes\.json does not hold/],
    ['unrouted.json', '{}', readUnrouted, /unrouted\.json does not hold/],
    ['status.json', '[]', () => readStatus('haiku'), /status\.json does not hold/],
  ]
  for (const [name, text, read, why] of cases) {
    await writeState(w, name, text)
    await assert.rejects(read(), (err: unknown) => err instanceof StateError && why.test(err.message))
  }
  await cleanup(w)
})

test('writes are atomic: each file is whole and no temp file is left', async () => {
  const w = await world()
  const entry: Entry = { ...msg(), seenAt: NOW.toISOString(), project: null }
  const status = { connected: true, lastCheck: NOW.toISOString(), error: null, model: 'haiku', workspace: 'Acme' }
  await writeSeen({ 'C1-1700000000.000100': entry })
  await writeRoutes({ C9: 'app' })
  await writeStatus(status)
  assert.deepEqual((await readdir(slackDir())).sort(), ['routes.json', 'seen.json', 'status.json'])
  assert.deepEqual(await readSeen(), { 'C1-1700000000.000100': entry })
  assert.deepEqual(await readRoutes(), { C9: 'app' })
  assert.deepEqual(await readStatus('haiku'), status)
  await cleanup(w)
})

test('prune drops entries first seen more than 30 days ago, and their unrouted ids', () => {
  const at = (ago: number): Entry => ({ ...msg(), seenAt: new Date(NOW.getTime() - ago).toISOString(), project: null })
  const seen = { old: at(KEEP_MS + 1), edge: at(KEEP_MS), fresh: at(0) }
  assert.deepEqual(prune(seen, ['old', 'fresh'], NOW), { seen: { edge: seen.edge, fresh: seen.fresh }, unrouted: ['fresh'], pruned: 1 })
})

test('readEveryMin is slack.everyMin from ~/.juel/dashboard.json, else 5', async () => {
  const w = await world()
  assert.equal(readEveryMin(), 5)
  await mkdir(join(w.home, '.juel'), { recursive: true })
  const cases: [string, number][] = [
    [JSON.stringify({ port: 4767, slack: { everyMin: 2 } }), 2],
    [JSON.stringify({ slack: { everyMin: 0.5 } }), 0.5],
    [JSON.stringify({ port: 4767 }), 5],
    [JSON.stringify({ slack: { everyMin: 0 } }), 5],
    [JSON.stringify({ slack: { everyMin: -1 } }), 5],
    [JSON.stringify({ slack: { everyMin: '2' } }), 5],
    ['null', 5],
    ['{oops', 5],
  ]
  for (const [text, want] of cases) {
    await writeFile(join(w.home, '.juel', 'dashboard.json'), text)
    assert.equal(readEveryMin(), want, text)
  }
  await cleanup(w)
})
