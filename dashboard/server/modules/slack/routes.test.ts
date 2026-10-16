import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import { inboxText } from './inbox.ts'
import { createSlack } from './watcher.ts'
import {
  answer,
  brief,
  calls,
  cleanup,
  envelope,
  inboxFiles,
  msg,
  play,
  project,
  readState,
  release,
  sleep,
  state,
  stub,
  until,
  world,
  writeState,
} from './test-helpers.ts'

const NOW = new Date('2026-10-16T12:00:00.000Z')
const HOUR = 3_600_000
const DEFAULT_STATUS = { connected: false, lastCheck: null, error: null, model: 'haiku', workspace: null, stderr: null }
type Listing = { status: unknown; routed: Record<string, unknown>[]; unrouted: Record<string, unknown>[] }

test('the module registers three routes; GET before any check has the default status and empty lists', async () => {
  const w = await world()
  const s = stub([])
  createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  assert.deepEqual(s.routes, ['GET /api/slack', 'POST /api/slack/check', 'POST /api/slack/:id/route'])
  assert.deepEqual(await s.call('GET', '/api/slack'), { status: 200, json: { status: DEFAULT_STATUS, routed: [], unrouted: [] } })
  await cleanup(w)
})

test('GET lists the routed replies still open (D5) and the unrouted messages, newest first', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  const s = stub([app])
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  const drafted = msg({ ts: '1700000001.000000', text: 'APP-77 today?', thread: ['Ann: any news?'] })
  const sent = msg({ ts: '1700000002.000000', text: 'APP-77 done?' })
  const fresh = msg({ ts: '1700000003.000000', text: 'APP-77 blocked?' })
  const lost = msg({ ts: '1700000004.000000', channelId: 'D5', channel: 'Bo', text: 'lunch?' })
  await play(w, [answer([drafted, sent, fresh, lost])])
  await slack.check()
  await mkdir(join(app.home, 'drafts'), { recursive: true })
  await writeFile(join(app.home, 'drafts', '2026-10-16-app-slack-C1-1700000001.000000.md'), 'to: slack C1 1700000001.000000\nToday, yes.\n')
  await writeFile(join(app.home, 'drafts', '2026-10-16-app-slack-C1-1700000002.000000.md'), 'to: slack C1 1700000002.000000\nDone.\n')
  await writeFile(
    join(app.home, 'open-loops.md'),
    '# Open loops\n\n## Needs you\n\n### N-4 · app · slack · Ria in #eng: APP-77 today?\nkind: slack-reply\n' +
      'draft: drafts/2026-10-16-app-slack-C1-1700000001.000000.md\nOptions: send (recommended) / rewrite: <how> / skip\nAnswer:\n\n## Waiting on others\n',
  )
  const res = await s.call('GET', '/api/slack')
  assert.equal(res.status, 200)
  const json = res.json as Listing
  assert.deepEqual(json.routed, [
    { id: 'C1-1700000003.000000', project: 'app', from: 'Ria', channel: '#eng', text: 'APP-77 blocked?', permalink: fresh.permalink, thread: [], draftPath: null, loopId: null },
    {
      id: 'C1-1700000001.000000',
      project: 'app',
      from: 'Ria',
      channel: '#eng',
      text: 'APP-77 today?',
      permalink: drafted.permalink,
      thread: ['Ann: any news?'],
      draftPath: 'drafts/2026-10-16-app-slack-C1-1700000001.000000.md',
      loopId: 'N-4',
    },
  ])
  assert.deepEqual(json.unrouted, [{ id: 'D5-1700000004.000000', from: 'Ria', channel: 'a DM', text: 'lunch?', permalink: lost.permalink }])
  await cleanup(w)
})

test('GET leaves out a project that is no longer registered, and an unrouted id with no seen entry', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  const registered = [app]
  const s = stub(registered)
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  await play(w, [answer([msg({ text: 'APP-77?' })])])
  await slack.check()
  await writeState(w, 'unrouted.json', ['C1-1600000000.000000'])
  registered.length = 0
  assert.deepEqual((await s.call('GET', '/api/slack')).json, { status: await readState(w, 'status.json'), routed: [], unrouted: [] })
  await play(w, [answer([])])
  await slack.check()
  assert.deepEqual(await readState(w, 'unrouted.json'), [])
  await cleanup(w)
})

test('POST route sends an unrouted message to a project, learns its channel, and the next message there follows it', async () => {
  const w = await world()
  const app = await project(w, 'app')
  const web = await project(w, 'web')
  const s = stub([app, web])
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  const m = msg({ channelId: 'C9', ts: '1700000001.000000', text: 'lunch?' })
  await play(w, [answer([m])])
  await slack.check()
  s.events.length = 0
  assert.deepEqual(await s.call('POST', '/api/slack/C9-1700000001.000000/route', { project: 'web' }), { status: 200, json: { project: 'web', nudged: true } })
  const files = await inboxFiles(web)
  assert.equal(files.length, 1)
  assert.equal(await readFile(join(web.home, 'inbox', files[0] ?? ''), 'utf8'), inboxText(web.repo, m))
  assert.deepEqual(await inboxFiles(app), [])
  assert.deepEqual(s.nudges, ['web'])
  assert.deepEqual(await readState(w, 'routes.json'), { C9: 'web' })
  assert.deepEqual(await readState(w, 'unrouted.json'), [])
  assert.equal((await readState(w, 'seen.json'))['C9-1700000001.000000'].project, 'web')
  assert.deepEqual(s.events, [{ type: 'change', what: 'slack' }])
  assert.equal(((await s.call('GET', '/api/slack')).json as Listing).routed[0]?.id, 'C9-1700000001.000000')
  // Rule 5: a new message in that channel, naming nothing, goes to web.
  await play(w, [answer([msg({ channelId: 'C9', ts: '1700000002.000000', text: 'and dinner?' })])])
  assert.deepEqual(await slack.check(), { ok: true, routed: 1, unrouted: 0 })
  assert.equal((await inboxFiles(web)).length, 2)
  // It is no longer unrouted: routing it again is a 404.
  assert.equal((await s.call('POST', '/api/slack/C9-1700000001.000000/route', { project: 'web' })).status, 404)
  await cleanup(w)
})

test('POST route with "none" drops it without learning; an unknown id is 404 and an unknown project 400', async () => {
  const w = await world()
  const app = await project(w, 'app')
  const s = stub([app])
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  const m = msg({ channelId: 'C9', ts: '1700000001.000000', text: 'lunch?' })
  const url = '/api/slack/C9-1700000001.000000/route'
  await play(w, [answer([m])])
  await slack.check()
  assert.equal((await s.call('POST', '/api/slack/C9-1700000009.000000/route', { project: 'app' })).status, 404)
  assert.equal((await s.call('POST', url, { project: 'nope' })).status, 400)
  assert.equal((await s.call('POST', url, {})).status, 400)
  assert.equal((await s.call('POST', url, null)).status, 400)
  assert.deepEqual(await inboxFiles(app), [])
  assert.deepEqual(await s.call('POST', url, { project: 'none' }), { status: 200, json: { project: 'none' } })
  assert.equal((await readState(w, 'seen.json'))['C9-1700000001.000000'].project, 'none')
  assert.deepEqual(await readState(w, 'unrouted.json'), [])
  assert.equal(existsSync(state(w, 'routes.json')), false)
  assert.deepEqual(s.nudges, [])
  assert.deepEqual(((await s.call('GET', '/api/slack')).json as Listing).unrouted, [])
  assert.deepEqual(((await s.call('GET', '/api/slack')).json as Listing).routed, [])
  // The same message in a later answer stays dropped.
  assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 0 })
  await cleanup(w)
})

test('a route while a check runs keeps both: the check writes what it reads under the lock', async () => {
  const w = await world()
  const app = await project(w, 'app')
  const web = await project(w, 'web')
  const s = stub([app, web])
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  const first = msg({ channelId: 'C9', ts: '1700000001.000000', text: 'lunch?' })
  const second = msg({ channelId: 'C8', ts: '1700000002.000000', text: 'dinner?' })
  await play(w, [answer([first]), { wait: true, stdout: envelope({ workspace: 'Acme', messages: [second] }) }])
  await slack.check()
  const running = slack.check()
  await until(async () => (await calls(w)).length === 2)
  assert.equal((await s.call('POST', '/api/slack/C9-1700000001.000000/route', { project: 'web' })).status, 200)
  await release(w)
  assert.deepEqual(await running, { ok: true, routed: 0, unrouted: 1 })
  assert.deepEqual(await readState(w, 'unrouted.json'), ['C8-1700000002.000000'])
  const seen = await readState(w, 'seen.json')
  assert.equal(seen['C9-1700000001.000000'].project, 'web')
  assert.equal(seen['C8-1700000002.000000'].project, null)
  await cleanup(w)
})

test('POST /api/slack/check answers when the check ends, and 409 while one runs', async () => {
  const w = await world()
  const s = stub([])
  createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  await play(w, [{ wait: true, stdout: envelope({ workspace: 'Acme', messages: [] }) }])
  let answered = false
  const first = s.call('POST', '/api/slack/check').then(res => {
    answered = true
    return res
  })
  await until(async () => (await calls(w)).length === 1)
  assert.deepEqual(await s.call('POST', '/api/slack/check'), { status: 409, json: { error: 'a check is already running' } })
  await sleep(50)
  assert.equal(answered, false, 'it answers when the check ends')
  await release(w)
  assert.deepEqual(await first, {
    status: 200,
    json: { ok: true, routed: 0, unrouted: 0, status: { connected: true, lastCheck: NOW.toISOString(), error: null, model: 'haiku', workspace: 'Acme', stderr: null } },
  })
  await cleanup(w)
})

test('two routes of one message at once: one wins, one inbox file, one nudge', async () => {
  const w = await world()
  const web = await project(w, 'web')
  const s = stub([web])
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  await play(w, [answer([msg({ channelId: 'C9', ts: '1700000001.000000', text: 'lunch?' })])])
  await slack.check()
  const url = '/api/slack/C9-1700000001.000000/route'
  const results = await Promise.all([s.call('POST', url, { project: 'web' }), s.call('POST', url, { project: 'web' })])
  assert.deepEqual(results.map(res => res.status).sort(), [200, 404])
  assert.equal((await inboxFiles(web)).length, 1)
  assert.deepEqual(s.nudges, ['web'])
  await cleanup(w)
})

test('a route whose inbox file cannot be written is a 500 that changes nothing, and can be tried again', async () => {
  const w = await world()
  const web = await project(w, 'web')
  const s = stub([web])
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  await play(w, [answer([msg({ channelId: 'C9', ts: '1700000001.000000', text: 'lunch?' })])])
  await slack.check()
  const seen = await readFile(state(w, 'seen.json'), 'utf8')
  await writeFile(join(web.home, 'inbox'), 'not a folder')
  const url = '/api/slack/C9-1700000001.000000/route'
  assert.equal((await s.call('POST', url, { project: 'web' })).status, 500)
  assert.equal(await readFile(state(w, 'seen.json'), 'utf8'), seen)
  assert.deepEqual(await readState(w, 'unrouted.json'), ['C9-1700000001.000000'])
  assert.equal(existsSync(state(w, 'routes.json')), false)
  assert.deepEqual(s.nudges, [])
  await rm(join(web.home, 'inbox'))
  assert.equal((await s.call('POST', url, { project: 'web' })).status, 200)
  assert.equal((await inboxFiles(web)).length, 1)
  assert.deepEqual(await readState(w, 'routes.json'), { C9: 'web' })
  await cleanup(w)
})

test('GET with a damaged seen.json lists nothing and says why in its status', async () => {
  const w = await world()
  const s = stub([])
  createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  await writeState(w, 'seen.json', '{not json')
  const json = (await s.call('GET', '/api/slack')).json as Listing & { status: { error: string } }
  assert.deepEqual(json.routed, [])
  assert.deepEqual(json.unrouted, [])
  assert.match(json.status.error, /seen\.json is not JSON/)
  await cleanup(w)
})
