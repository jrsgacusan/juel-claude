import assert from 'node:assert/strict'
import { mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import { readSlackSettings } from './settings.ts'
import { slackDir } from './state.ts'
import { cleanup, world } from './test-helpers.ts'
import type { World } from './test-helpers.ts'

const DEFAULTS = { everyMin: 5, plugin: null, linearPlugin: null, names: [], drafter: { model: 'opus', timeoutMin: 10 } }
const writeDashboard = async (w: World, value: unknown): Promise<void> => {
  await mkdir(join(w.home, '.juel'), { recursive: true })
  await writeFile(join(w.home, '.juel', 'dashboard.json'), typeof value === 'string' ? value : JSON.stringify(value))
}

test('readSlackSettings: the defaults, then each key of slack in dashboard.json (I-12)', async () => {
  const w = await world()
  assert.deepEqual(readSlackSettings(), DEFAULTS)
  await writeDashboard(w, {
    port: 4767,
    slack: { everyMin: 0, plugin: 'slack@claude-plugins-official', linearPlugin: ' linear@mine ', names: ['Jrs', ' ', 'jrs', 'JR', 7], drafter: { model: 'sonnet', timeoutMin: 3 } },
  })
  assert.deepEqual(readSlackSettings(), { everyMin: 0, plugin: 'slack@claude-plugins-official', linearPlugin: 'linear@mine', names: ['Jrs', 'JR'], drafter: { model: 'sonnet', timeoutMin: 3 } })
  await writeDashboard(w, { slack: { plugin: '', names: 'Jrs', drafter: { model: ' ', timeoutMin: 0 } } })
  assert.deepEqual(readSlackSettings(), DEFAULTS)
  await cleanup(w)
})

test('readSlackSettings().everyMin is slack.everyMin from dashboard.json when it is a number >= 0, else 5', async () => {
  const w = await world()
  assert.equal(readSlackSettings().everyMin, 5)
  const cases: [string, number][] = [
    [JSON.stringify({ port: 4767, slack: { everyMin: 2 } }), 2],
    [JSON.stringify({ slack: { everyMin: 0.5 } }), 0.5],
    [JSON.stringify({ port: 4767 }), 5],
    [JSON.stringify({ slack: { everyMin: 0 } }), 0],
    [JSON.stringify({ slack: { everyMin: -1 } }), 5],
    [JSON.stringify({ slack: { everyMin: '2' } }), 5],
    ['null', 5],
    ['{oops', 5],
  ]
  for (const [text, want] of cases) {
    await writeDashboard(w, text)
    assert.equal(readSlackSettings().everyMin, want, text)
  }
  await cleanup(w)
})

test('JUEL_DIR, set and not empty, replaces ~/.juel for dashboard.json and the state files (I-1)', async () => {
  const w = await world()
  const juel = join(w.root, 'juel')
  await mkdir(juel, { recursive: true })
  await writeFile(join(juel, 'dashboard.json'), JSON.stringify({ slack: { everyMin: 0 } }))
  process.env.JUEL_DIR = juel
  assert.equal(slackDir(), join(juel, 'slack'))
  assert.equal(readSlackSettings().everyMin, 0)
  process.env.JUEL_DIR = ''
  assert.equal(slackDir(), join(w.home, '.juel', 'slack'))
  assert.equal(readSlackSettings().everyMin, 5)
  delete process.env.JUEL_DIR
  await cleanup(w)
})
