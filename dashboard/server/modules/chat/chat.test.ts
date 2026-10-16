import assert from 'node:assert/strict'
import { readFile, readdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { afterEach, beforeEach, mock, test } from 'node:test'

import { register } from './index.ts'
import type { ChatMessage } from './store.ts'
import { MSGS, cleanup, stub, world, writeThread } from './test-helpers.ts'
import type { Stub, World } from './test-helpers.ts'

type State = { messages: ChatMessage[]; hasMore: boolean; starRunning: boolean }
const ROUTES = ['GET /api/projects/:p/chat', 'POST /api/projects/:p/chat']

let w: World
let s: Stub
beforeEach(async () => {
  w = await world()
  s = stub([w.project])
  register(s.api)
})
afterEach(async () => {
  mock.timers.reset()
  await cleanup(w)
})

const state = async (query = ''): Promise<State> => (await s.call('GET', `/api/projects/proj/chat${query}`)).json as State

test('register adds exactly the chat routes', () => {
  assert.deepEqual([...s.routes].sort(), [...ROUTES].sort())
})

test('an unknown project is 404 on every route', async () => {
  for (const route of s.routes) {
    const [method, path] = route.split(' ')
    const res = await s.call(method as 'GET' | 'POST', path.replace(':p', 'nope'), { text: 'x', away: true })
    assert.deepEqual([res.status, res.json], [404, { error: 'unknown project' }], route)
  }
})

test('POST chat writes the me file, then the inbox file, and nudges STAR', async () => {
  mock.timers.enable({ apis: ['Date'], now: new Date('2026-10-17T01:02:03.456Z') })
  const res = await s.call('POST', '/api/projects/proj/chat', { text: '  how is it going?\n\nline two  ' })
  assert.equal(res.status, 200)
  const { id, nudged } = res.json as { id: string; nudged: boolean }
  assert.match(id, /^20261017T010203Z-me-[0-9a-f]{4}$/)
  assert.equal(nudged, true)
  assert.deepEqual(s.nudges, ['proj'])
  assert.equal(
    await readFile(join(w.home, 'chat', `${id}.md`), 'utf8'),
    `id: ${id}\nwho: me\nat: 2026-10-17T01:02:03Z\nreplyTo: -\n---\nhow is it going?\n\nline two\n`,
  )
  const inbox = await readdir(join(w.home, 'inbox'))
  assert.equal(inbox.length, 1)
  assert.match(inbox[0], /^20261017T010203Z-chat-[0-9a-f]{4}\.md$/)
  assert.equal(
    await readFile(join(w.home, 'inbox', inbox[0]), 'utf8'),
    `repo: /w/proj\nchat: ${id}\ntext: |\n  how is it going?\n  \n  line two\n`,
  )
})

test('a stopped STAR still gets both files; the answer says not nudged and the thread says not running', async () => {
  const stopped = await world('stopped')
  try {
    const t = stub([stopped.project], async () => false)
    register(t.api)
    const res = await t.call('POST', '/api/projects/proj/chat', { text: 'are you there?' })
    assert.equal(res.status, 200)
    assert.equal((res.json as { nudged: boolean }).nudged, false)
    assert.equal((await readdir(join(stopped.home, 'chat'))).length, 1)
    assert.equal((await readdir(join(stopped.home, 'inbox'))).length, 1)
    const got = (await t.call('GET', '/api/projects/proj/chat')).json as State
    assert.equal(got.starRunning, false)
    assert.deepEqual(got.messages.map(m => [m.who, m.text, m.replyTo]), [['me', 'are you there?', null]])
  } finally {
    await cleanup(stopped)
  }
})

test('a nudge that rejects is not nudged, and is logged', async () => {
  const t = stub([w.project], async () => {
    throw new Error('orca is down')
  })
  register(t.api)
  const res = await t.call('POST', '/api/projects/proj/chat', { text: 'hello' })
  assert.deepEqual([res.status, (res.json as { nudged: boolean }).nudged], [200, false])
  assert.ok(t.logs.some(line => line === 'chat proj: nudge failed: orca is down'), t.logs.join('\n'))
})

test('text that is empty after trimming, not a string, or over 8000 characters is 400 and writes nothing', async () => {
  for (const body of [{}, { text: '   ' }, { text: 5 }, null, 'hi', { text: 'a'.repeat(8001) }]) {
    const res = await s.call('POST', '/api/projects/proj/chat', body)
    assert.deepEqual([res.status, res.json], [400, { error: 'text must be 1 to 8000 characters' }], JSON.stringify(body).slice(0, 40))
  }
  assert.deepEqual(await readdir(w.home), ['star.json'])
  assert.deepEqual(s.nudges, [])
  assert.equal((await s.call('POST', '/api/projects/proj/chat', { text: ` ${'a'.repeat(8000)} ` })).status, 200)
})

test('GET chat answers the thread oldest first, skips a file that does not parse, and pages with before', async () => {
  assert.deepEqual(await state(), { messages: [], hasMore: false, starRunning: true })
  await writeThread(w.home, MSGS)
  await writeFile(join(w.home, 'chat', '20261017T010006Z-me-0006.md'), 'garbage')
  assert.deepEqual(await state(), { messages: MSGS, hasMore: false, starRunning: true })
  const all = MSGS.map(m => m.id)
  const last = await state('?limit=2')
  assert.deepEqual([last.messages.map(m => m.id), last.hasMore], [all.slice(3), true])
  const middle = await state(`?before=${all[3]}&limit=2`)
  assert.deepEqual([middle.messages.map(m => m.id), middle.hasMore], [all.slice(1, 3), true])
  const first = await state(`?before=${all[1]}&limit=2`)
  assert.deepEqual([first.messages.map(m => m.id), first.hasMore], [all.slice(0, 1), false])
})

test('a bad limit or before is 400', async () => {
  for (const query of ['limit=0', 'limit=201', 'limit=x', 'limit=2.5', 'limit=']) {
    const res = await s.call('GET', `/api/projects/proj/chat?${query}`)
    assert.deepEqual([res.status, res.json], [400, { error: 'limit must be a whole number from 1 to 200' }], query)
  }
  for (const query of ['before=nope', 'before=20261017T010001Z-me-0001.md', 'before=']) {
    const res = await s.call('GET', `/api/projects/proj/chat?${query}`)
    assert.deepEqual([res.status, res.json], [400, { error: 'before must be a message id' }], query)
  }
  assert.equal((await s.call('GET', '/api/projects/proj/chat?limit=200')).status, 200)
})

test('starRunning is true while STAR runs or idles, false when it is stopped', async () => {
  for (const [st, running] of [['running', true], ['idle', true], ['stopped', false]] as const) {
    const t = stub([{ ...w.project, state: st }])
    register(t.api)
    assert.equal(((await t.call('GET', '/api/projects/proj/chat')).json as State).starRunning, running, st)
  }
})
