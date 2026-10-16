import assert from 'node:assert/strict'
import { mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import { installedPlugin, loadConfig, pluginIds, readSlackSettings } from './settings.ts'
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

const installed = async (w: World, plugins: unknown): Promise<void> => {
  await mkdir(join(w.root, 'claude-config', 'plugins'), { recursive: true })
  await writeFile(join(w.root, 'claude-config', 'plugins', 'installed_plugins.json'), typeof plugins === 'string' ? plugins : JSON.stringify({ version: 2, plugins }))
}

test('installedPlugin: the first id with that name and an install, under CLAUDE_CONFIG_DIR', async () => {
  const w = await world()
  assert.equal(installedPlugin('slack'), null)
  await installed(w, {
    'superpowers@claude-plugins-official': [{ scope: 'user' }],
    'slack@gone': [],
    'slack@claude-plugins-official': [{ scope: 'user', installPath: '/x', version: '1.4.1' }],
    'linear@claude-plugins-official': [{ scope: 'user' }],
    'slack@later': [{ scope: 'local' }],
  })
  assert.equal(installedPlugin('slack'), 'slack@claude-plugins-official')
  assert.equal(installedPlugin('linear'), 'linear@claude-plugins-official')
  for (const bad of ['{oops', '[]', JSON.stringify({ plugins: [] })]) {
    await installed(w, bad)
    assert.equal(installedPlugin('slack'), null, bad)
  }
  delete process.env.CLAUDE_CONFIG_DIR
  await mkdir(join(w.home, '.claude', 'plugins'), { recursive: true })
  await writeFile(join(w.home, '.claude', 'plugins', 'installed_plugins.json'), JSON.stringify({ version: 2, plugins: { 'slack@home': [{ scope: 'user' }] } }))
  assert.equal(installedPlugin('slack'), 'slack@home', 'no CLAUDE_CONFIG_DIR: ~/.claude')
  await cleanup(w)
})

test('pluginIds: dashboard.json first, then installed_plugins.json, then config.json (#146)', async () => {
  const w = await world()
  const config = loadConfig()
  const none = { plugin: null, linearPlugin: null }
  assert.deepEqual(pluginIds(config, none), { slack: 'slack@anthropic-plugin-directory', linear: 'linear@claude-plugins-official' })
  await installed(w, { 'slack@claude-plugins-official': [{ scope: 'user' }], 'linear@mine': [{ scope: 'user' }] })
  assert.deepEqual(pluginIds(config, none), { slack: 'slack@claude-plugins-official', linear: 'linear@mine' })
  assert.deepEqual(pluginIds(config, { plugin: 'slack@set', linearPlugin: 'linear@set' }), { slack: 'slack@set', linear: 'linear@set' })
  await cleanup(w)
})
