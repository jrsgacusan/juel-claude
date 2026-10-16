import assert from 'node:assert/strict'
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

import { register } from './index.ts'
import { calls, cleanup, readState, sleep, stub, until, world } from './test-helpers.ts'
import { createSlack } from './watcher.ts'

const HERE = dirname(fileURLToPath(import.meta.url))

test('register starts the watcher: three routes, and a first check at once', async () => {
  const w = await world()
  const s = stub([])
  register(s.api)
  assert.deepEqual(s.routes, ['GET /api/slack', 'POST /api/slack/check', 'POST /api/slack/:id/route'])
  await until(async () => (await calls(w)).length === 1)
  await until(async () => {
    try {
      return (await readState(w, 'status.json')).connected === true
    } catch {
      return false
    }
  })
  await cleanup(w)
})

test('the watcher checks every slack.everyMin minutes of ~/.juel/dashboard.json, 5 when missing, capped for setInterval', async () => {
  const w = await world()
  const every = (): number => createSlack(stub([]).api).everyMs
  assert.equal(every(), 5 * 60_000)
  await mkdir(join(w.home, '.juel'), { recursive: true })
  const write = (value: unknown): Promise<void> => writeFile(join(w.home, '.juel', 'dashboard.json'), JSON.stringify(value))
  await write({ port: 4767, slack: { everyMin: 2 } })
  assert.equal(every(), 2 * 60_000)
  await write({ port: 4767 })
  assert.equal(every(), 5 * 60_000)
  await write({ slack: { everyMin: 1e9 } })
  assert.equal(every(), 2 ** 31 - 1)
  await cleanup(w)
})

test('everyMin 0 turns the watcher off: no check at start, and POST /api/slack/check is 409', async () => {
  const w = await world()
  await mkdir(join(w.home, '.juel'), { recursive: true })
  await writeFile(join(w.home, '.juel', 'dashboard.json'), JSON.stringify({ slack: { everyMin: 0 } }))
  const s = stub([])
  const slack = createSlack(s.api)
  assert.equal(slack.everyMs, 0)
  slack.start()
  await sleep(300)
  assert.deepEqual(await calls(w), [])
  assert.deepEqual(await s.call('POST', '/api/slack/check'), { status: 409, json: { error: 'the Slack watcher is off: slack.everyMin is 0' } })
  assert.ok(s.logs.includes('slack: the watcher is off (slack.everyMin is 0)'), s.logs.join('\n'))
  slack.stop()
  await cleanup(w)
})

test('the module runs on Node alone: node: builtins, its own files and hooks/star.ts, nothing that reaches the network', async () => {
  const files = (await readdir(HERE)).filter(name => name.endsWith('.ts') && !name.endsWith('.test.ts') && name !== 'test-helpers.ts')
  assert.deepEqual(files.sort(), ['claude.ts', 'inbox.ts', 'index.ts', 'parse.ts', 'replies.ts', 'route.ts', 'settings.ts', 'state.ts', 'types.ts', 'watcher.ts'])
  const network = ['node:http', 'node:https', 'node:net', 'node:dgram', 'node:tls']
  for (const file of files) {
    const code = await readFile(join(HERE, file), 'utf8')
    for (const m of code.matchAll(/^import\s[\s\S]*?\sfrom\s+'([^']+)'/gm)) {
      const from = m[1] ?? ''
      const ok = from.startsWith('./') || from === '../../../../hooks/star.ts' || (from.startsWith('node:') && !network.includes(from))
      assert.ok(ok, `${file} imports ${from}`)
    }
    assert.ok(!/\bfetch\(/.test(code), `${file} calls fetch`)
  }
  await assert.rejects(readFile(join(HERE, 'package.json')))
})