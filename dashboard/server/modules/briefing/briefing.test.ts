import assert from 'node:assert/strict'
import { mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { afterEach, beforeEach, test } from 'node:test'

import { ID_RE } from './ids.ts'
import { register } from './index.ts'
import { briefingDir, writeDraft } from './store.ts'
import { block, calls, cleanup, done, init, play, release, say, stub, until, world } from './test-helpers.ts'
import type { Stub, World } from './test-helpers.ts'

const T = { title: 'Retry the sync', description: 'The sync drops on a flaky network.', criteria: ['A failed sync retries once'], outOfScope: ['Backoff tuning'] }
const REPLY = `Which screen shows the failure?\n\n${block(T)}`
const OK = { lines: [init('S1'), say(REPLY), done(REPLY)] }
const ROUTES = [
  'GET /api/projects/:p/briefings',
  'POST /api/projects/:p/briefings',
  'GET /api/projects/:p/briefings/:id',
  'POST /api/projects/:p/briefings/:id/messages',
  'POST /api/projects/:p/briefings/:id/create',
  'GET /api/projects/:p/tracker',
  'PUT /api/projects/:p/tracker',
]

let w: World
let s: Stub
beforeEach(async () => {
  w = await world()
  s = stub([w.project])
  register(s.api)
})
afterEach(async () => {
  await cleanup(w)
})

const json = (res: { json?: unknown }): Record<string, unknown> => res.json as Record<string, unknown>
async function newBriefing(): Promise<string> {
  const res = await s.call('POST', '/api/projects/proj/briefings')
  return String(json(res).id)
}
/** Waits until briefing `id` has emitted `n` finished turns or errors. */
const settled = (id: string, n = 1) =>
  until(() => s.events.filter(event => event.id === id && ('error' in event || (event.turn as { done?: boolean } | undefined)?.done === true)).length >= n)
const withDraft = async (id: string): Promise<void> => {
  await writeDraft(briefingDir(w.home, id)!, T)
}

test('register adds exactly the seven routes', () => {
  assert.deepEqual([...s.routes].sort(), [...ROUTES].sort())
})

test('an unknown project is 404 on every route', async () => {
  for (const route of ROUTES) {
    const [method, path] = route.split(' ')
    const url = path.replace(':p', 'nope').replace(':id', '20261016T030405Z-abcd')
    const res = await s.call(method as 'GET' | 'POST' | 'PUT', url, { text: 'x', tracker: 'none' })
    assert.equal(res.status, 404, route)
    assert.equal(json(res).error, 'unknown project')
  }
})

test('POST briefings makes briefings/<id>/ in the STAR folder and returns its id', async () => {
  const res = await s.call('POST', '/api/projects/proj/briefings')
  assert.equal(res.status, 201)
  const id = String(json(res).id)
  assert.match(id, ID_RE)
  assert.equal((await stat(join(w.home, 'briefings', id))).isDirectory(), true)
})

test('an unknown or malformed briefing id is 404 and touches nothing', async () => {
  for (const id of ['20261016T030405Z-abcd', '..%2F..%2Fetc', '%2E%2E']) {
    for (const [method, suffix] of [['GET', ''], ['POST', '/messages'], ['POST', '/create']] as const) {
      const res = await s.call(method, `/api/projects/proj/briefings/${id}${suffix}`, { text: 'x', tracker: 'none' })
      assert.equal(res.status, 404, `${method} ${id}${suffix}`)
      assert.equal(json(res).error, 'unknown briefing')
    }
  }
  assert.deepEqual(await calls(w), [])
  assert.deepEqual(await readdir(w.home), [])
})

test('a new briefing has no turns, no draft and is not busy', async () => {
  const id = await newBriefing()
  const res = await s.call('GET', `/api/projects/proj/briefings/${id}`)
  assert.equal(res.status, 200)
  assert.deepEqual(res.json, { turns: [], draft: null, busy: false })
})

test('a message is 202, its turn streams as briefing events, and GET shows the finished turns', async () => {
  await play(w, 'claude', [OK, OK])
  const id = await newBriefing()
  const res = await s.call('POST', `/api/projects/proj/briefings/${id}/messages`, { text: 'Add a retry' })
  assert.equal(res.status, 202)
  await settled(id)
  assert.ok(s.events.every(event => event.type === 'briefing' && event.project === 'proj' && event.id === id))
  const got = await s.call('GET', `/api/projects/proj/briefings/${id}`)
  assert.deepEqual(got.json, {
    turns: [
      { who: 'me', text: 'Add a retry', files: [] },
      { who: 'agent', text: 'Which screen shows the failure?', files: [] },
    ],
    draft: T,
    busy: false,
  })
  await s.call('POST', `/api/projects/proj/briefings/${id}/messages`, { text: 'The sync page' })
  await settled(id, 2)
  const [first, second] = await calls(w, 'claude')
  assert.equal(first.cwd, w.repo)
  assert.deepEqual(second.argv.slice(-4), ['--resume', 'S1', '--', 'The sync page'])
})

test('a message with no text is 400', async () => {
  const id = await newBriefing()
  for (const body of [{}, { text: '  ' }, { text: 5 }, null, 'text']) {
    const res = await s.call('POST', `/api/projects/proj/briefings/${id}/messages`, body)
    assert.equal(res.status, 400, JSON.stringify(body))
  }
  assert.deepEqual(await calls(w), [])
})

test('a second message while a turn runs is 409, and GET shows busy', async () => {
  await play(w, 'claude', [{ lines: [init('S1'), say(REPLY), done(REPLY)], wait: true }])
  const id = await newBriefing()
  assert.equal((await s.call('POST', `/api/projects/proj/briefings/${id}/messages`, { text: 'one' })).status, 202)
  await until(async () => (await calls(w, 'claude')).length === 1)
  assert.equal(json(await s.call('GET', `/api/projects/proj/briefings/${id}`)).busy, true)
  const second = await s.call('POST', `/api/projects/proj/briefings/${id}/messages`, { text: 'two' })
  assert.equal(second.status, 409)
  await release(w)
  await settled(id)
  assert.equal(json(await s.call('GET', `/api/projects/proj/briefings/${id}`)).busy, false)
  assert.equal((await calls(w, 'claude')).length, 1)
})

test('GET briefings lists title, updatedAt and ref, newest first', async () => {
  await play(w, 'gh', [{ stdout: 'https://github.com/o/r/issues/42\n' }])
  const empty = await newBriefing()
  const drafted = await newBriefing()
  await withDraft(drafted)
  await s.call('POST', `/api/projects/proj/briefings/${drafted}/create`, { tracker: 'github' })
  const res = await s.call('GET', '/api/projects/proj/briefings')
  assert.equal(res.status, 200)
  const list = res.json as Record<string, unknown>[]
  assert.deepEqual(list.map(item => Object.keys(item).sort()), [['id', 'ref', 'title', 'updatedAt'], ['id', 'ref', 'title', 'updatedAt']])
  const byId = new Map(list.map(item => [item.id, item]))
  assert.deepEqual({ ...byId.get(drafted), updatedAt: 'x' }, { id: drafted, title: 'Retry the sync', updatedAt: 'x', ref: '#42' })
  assert.deepEqual({ ...byId.get(empty), updatedAt: 'x' }, { id: empty, title: 'New briefing', updatedAt: 'x', ref: null })
  assert.ok(list.every(item => !Number.isNaN(Date.parse(String(item.updatedAt)))))
  assert.ok(String(list[0].updatedAt) >= String(list[1].updatedAt))
})

test('create with github answers {ref, url}, nudges STAR once, and a second create is 409', async () => {
  await play(w, 'gh', [{ stdout: 'https://github.com/o/r/issues/42\n' }])
  const id = await newBriefing()
  await withDraft(id)
  const res = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })
  assert.equal(res.status, 201)
  assert.deepEqual(res.json, { ref: '#42', url: 'https://github.com/o/r/issues/42' })
  assert.deepEqual(s.nudges, ['proj'])
  assert.equal((await readdir(join(w.home, 'inbox'))).length, 1)
  const again = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })
  assert.equal(again.status, 409)
  assert.equal((json(again).created as Record<string, unknown>).ref, '#42')
  assert.deepEqual(s.nudges, ['proj'])
  assert.equal((await calls(w, 'gh')).length, 1)
})

test("a failed create is 502 with the tracker's error, and Save as a spec instead works", async () => {
  await play(w, 'gh', [{ stderr: 'HTTP 401: Bad credentials\n', exit: 1 }])
  const id = await newBriefing()
  await withDraft(id)
  const res = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })
  assert.equal(res.status, 502)
  assert.deepEqual(res.json, { error: 'HTTP 401: Bad credentials', tracker: 'github' })
  assert.deepEqual(s.nudges, [])
  const spec = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'none' })
  assert.equal(spec.status, 201)
  assert.deepEqual(spec.json, { specPath: join(w.home, 'items', 'proj', 'retry-the-sync.md'), url: '/api/projects/proj/file?path=items%2Fproj%2Fretry-the-sync.md' })
  assert.deepEqual(s.nudges, ['proj'])
})

test('create with a bad tracker is 400, and with no draft yet is 409', async () => {
  const id = await newBriefing()
  assert.equal((await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'gitlab' })).status, 400)
  const res = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'none' })
  assert.equal(res.status, 409)
  assert.equal(json(res).error, 'no draft yet')
})

test('a second press on Create while the first runs is 409, and one ticket is made', async () => {
  await play(w, 'gh', [{ stdout: 'https://github.com/o/r/issues/42\n', wait: true }])
  const id = await newBriefing()
  await withDraft(id)
  const first = s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })
  await until(async () => (await calls(w, 'gh')).length === 1)
  assert.equal((await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })).status, 409)
  assert.equal((await s.call('POST', `/api/projects/proj/briefings/${id}/messages`, { text: 'more' })).status, 409)
  await release(w)
  assert.equal((await first).status, 201)
  assert.equal((await calls(w, 'gh')).length, 1)
})

test("create for a connected tracker uses the repo's configured team", async () => {
  await mkdir(join(w.repo, '.claude'), { recursive: true })
  await writeFile(join(w.repo, '.claude', 'workflow.json'), JSON.stringify({ tracker: { type: 'linear', project: 'ENG' } }))
  const answer = '{"ref": "ENG-7", "url": "https://linear.app/acme/issue/ENG-7"}'
  await play(w, 'claude', [{ lines: [init('C1', ['mcp__linear__save_issue']), say(answer), done(answer)] }])
  const id = await newBriefing()
  await withDraft(id)
  const res = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'linear' })
  assert.equal(res.status, 201)
  assert.deepEqual(res.json, { ref: 'ENG-7', url: 'https://linear.app/acme/issue/ENG-7' })
  assert.ok((await calls(w, 'claude'))[0].argv.at(-1)!.includes('"ENG"'))
})

test('GET tracker is null until PUT saves an answer, and PUT takes only the five', async () => {
  assert.deepEqual((await s.call('GET', '/api/projects/proj/tracker')).json, { tracker: null })
  const put = await s.call('PUT', '/api/projects/proj/tracker', { tracker: 'github' })
  assert.equal(put.status, 200)
  assert.deepEqual(put.json, { tracker: 'github' })
  assert.deepEqual((await s.call('GET', '/api/projects/proj/tracker')).json, { tracker: 'github' })
  assert.deepEqual(JSON.parse(await readFile(join(w.repo, '.claude', 'workflow.local.json'), 'utf8')), { tracker: { type: 'github' } })
  for (const bad of [{ tracker: 'gitlab' }, {}, null]) {
    assert.equal((await s.call('PUT', '/api/projects/proj/tracker', bad)).status, 400, JSON.stringify(bad))
  }
})

test('PUT tracker refuses a local file it cannot parse, naming it', async () => {
  await mkdir(join(w.repo, '.claude'), { recursive: true })
  await writeFile(join(w.repo, '.claude', 'workflow.local.json'), '{ nope')
  const res = await s.call('PUT', '/api/projects/proj/tracker', { tracker: 'jira' })
  assert.equal(res.status, 409)
  assert.match(String(json(res).error), /workflow\.local\.json/)
  assert.equal(await readFile(join(w.repo, '.claude/workflow.local.json'), 'utf8'), '{ nope')
})

test('two messages sent at once: one runs, the other is 409', async () => {
  await play(w, 'claude', [OK])
  const id = await newBriefing()
  const answers = await Promise.all([
    s.call('POST', `/api/projects/proj/briefings/${id}/messages`, { text: 'one' }),
    s.call('POST', `/api/projects/proj/briefings/${id}/messages`, { text: 'two' }),
  ])
  assert.deepEqual(answers.map(res => res.status).sort(), [202, 409])
  await settled(id)
  assert.equal((await calls(w, 'claude')).length, 1)
})

test('an emit that throws never takes the server down, and the briefing is freed', async () => {
  const loud = stub([w.project], { emitThrows: true })
  register(loud.api)
  await play(w, 'claude', [OK])
  const id = String(json(await loud.call('POST', '/api/projects/proj/briefings')).id)
  assert.equal((await loud.call('POST', `/api/projects/proj/briefings/${id}/messages`, { text: 'one' })).status, 202)
  await until(() => loud.events.some(event => 'error' in event || (event.turn as { done?: boolean } | undefined)?.done === true))
  await until(async () => json(await loud.call('GET', `/api/projects/proj/briefings/${id}`)).busy === false)
})

test('a turn that throws is reported as a briefing error and frees the briefing', async () => {
  const id = await newBriefing()
  await mkdir(join(briefingDir(w.home, id)!, 'session')) // a folder where the session file goes: reading it throws
  assert.equal((await s.call('POST', `/api/projects/proj/briefings/${id}/messages`, { text: 'one' })).status, 202)
  await settled(id)
  assert.match(String(s.events.at(-1)!.error), /EISDIR/)
  assert.equal(json(await s.call('GET', `/api/projects/proj/briefings/${id}`)).busy, false)
})

test('a nudge that fails still answers 201, and the log says STAR was not reached', async () => {
  const quiet = stub([w.project], { nudge: async () => { throw new Error('no terminal') } })
  register(quiet.api)
  await play(w, 'gh', [{ stdout: 'https://github.com/o/r/issues/42\n' }])
  const id = String(json(await quiet.call('POST', '/api/projects/proj/briefings')).id)
  await withDraft(id)
  const res = await quiet.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })
  assert.equal(res.status, 201)
  assert.ok(quiet.logs.some(line => line.includes('nudge failed: no terminal')))
  assert.ok(quiet.logs.some(line => line.includes('not reached')))
})

test('create while a turn runs is 409', async () => {
  await play(w, 'claude', [{ ...OK, wait: true }])
  const id = await newBriefing()
  await withDraft(id)
  await s.call('POST', `/api/projects/proj/briefings/${id}/messages`, { text: 'one' })
  await until(async () => (await calls(w, 'claude')).length === 1)
  assert.equal((await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'none' })).status, 409)
  await release(w)
  await settled(id)
})

test('GET tracker answers one of the five or null, and logs a value it cannot use', async () => {
  await mkdir(join(w.repo, '.claude'), { recursive: true })
  const cases: [unknown, string | null][] = [[{ type: 'file' }, 'none'], ['Linear', 'linear'], [{ type: 'gitlab' }, null]]
  for (const [tracker, want] of cases) {
    await writeFile(join(w.repo, '.claude', 'workflow.json'), JSON.stringify({ tracker }))
    assert.deepEqual((await s.call('GET', '/api/projects/proj/tracker')).json, { tracker: want }, JSON.stringify(tracker))
  }
  assert.ok(s.logs.some(line => line.includes('"gitlab"')))
})

test("a configured team is passed only to its own tracker's create", async () => {
  await mkdir(join(w.repo, '.claude'), { recursive: true })
  await writeFile(join(w.repo, '.claude', 'workflow.json'), JSON.stringify({ tracker: { type: 'linear', project: 'ENG' } }))
  const answer = '{"error": "no project key"}'
  await play(w, 'claude', [{ lines: [init('C1', ['mcp__atlassian__createJiraIssue']), say(answer), done(answer)] }])
  const id = await newBriefing()
  await withDraft(id)
  assert.equal((await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'jira' })).status, 502)
  assert.equal((await calls(w, 'claude'))[0].argv.at(-1)!.includes('"ENG"'), false)
})

test('a transcript line that is not a turn is skipped, and the list still answers', async () => {
  const id = await newBriefing()
  const good = { who: 'me', text: 'Add a retry', files: [], at: '2026-10-16T00:00:00.000Z' }
  await writeFile(join(briefingDir(w.home, id)!, 'transcript.jsonl'), `null\n{"who":"me"}\n${JSON.stringify(good)}\n`)
  const list = await s.call('GET', '/api/projects/proj/briefings')
  assert.equal(list.status, 200)
  assert.equal((list.json as Record<string, unknown>[])[0].title, 'Add a retry')
  assert.deepEqual(json(await s.call('GET', `/api/projects/proj/briefings/${id}`)).turns, [{ who: 'me', text: 'Add a retry', files: [] }])
})

test('a ticket made but not recorded is 500 with made, never the 502 that offers to make it again', async () => {
  await play(w, 'gh', [{ stdout: 'https://github.com/o/r/issues/42\n' }])
  const id = await newBriefing()
  await withDraft(id)
  await writeFile(join(w.home, 'inbox'), 'not a folder')
  const res = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })
  assert.equal(res.status, 500)
  assert.equal((json(res).made as Record<string, unknown>).ref, '#42')
  assert.deepEqual(s.nudges, [])
})

test('pressing Create again after a failed inbox write queues the same ticket, then a third press is 409', async () => {
  await play(w, 'gh', [{ stdout: 'https://github.com/o/r/issues/42\n' }])
  const id = await newBriefing()
  await withDraft(id)
  await writeFile(join(w.home, 'inbox'), 'not a folder')
  assert.equal((await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })).status, 500)
  assert.deepEqual(s.nudges, [])
  await rm(join(w.home, 'inbox'))
  const again = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })
  assert.equal(again.status, 201)
  assert.deepEqual(again.json, { ref: '#42', url: 'https://github.com/o/r/issues/42' })
  assert.deepEqual(s.nudges, ['proj'])
  assert.equal((await readdir(join(w.home, 'inbox'))).length, 1)
  assert.equal((await calls(w, 'gh')).length, 1)
  const third = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })
  assert.equal(third.status, 409)
  assert.deepEqual(s.nudges, ['proj'])
})

test('a briefing whose create did not finish answers 409 and makes nothing', async () => {
  await play(w, 'gh', [{ stdout: 'https://github.com/o/r/issues/42\n' }])
  const id = await newBriefing()
  await withDraft(id)
  const mark = { tracker: 'github', ref: null, specPath: null, url: null, at: '2026-10-16T00:00:00.000Z', state: 'creating', inbox: null }
  await writeFile(join(briefingDir(w.home, id)!, 'created.json'), JSON.stringify(mark))
  for (const tracker of ['github', 'none']) {
    const res = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker })
    assert.equal(res.status, 409, tracker)
    assert.match(String(json(res).error), /did not finish/)
  }
  assert.deepEqual(await calls(w, 'gh'), [])
  assert.deepEqual(s.nudges, [])
})

test('a ticket made but not recorded is 500 with made, and the next press is 409, not a second ticket', async () => {
  await play(w, 'gh', [{ stdout: 'https://github.com/o/r/issues/42\n' }])
  const id = await newBriefing()
  await withDraft(id)
  await mkdir(join(briefingDir(w.home, id)!, `.created.json.${process.pid}.tmp`)) // the record's rewrite cannot write its temp file
  const first = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })
  assert.equal(first.status, 500)
  assert.equal((json(first).made as Record<string, unknown>).ref, '#42')
  const second = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'github' })
  assert.equal(second.status, 409)
  assert.match(String(json(second).error), /did not finish/)
  assert.equal((await calls(w, 'gh')).length, 1)
})


test('a create that may have made an issue is 502 with maybeMade, and every later press is 409, not a second issue', async () => {
  const toolUse = { type: 'assistant', message: { content: [{ type: 'tool_use', name: 'mcp__linear__save_issue', input: {} }] } }
  await play(w, 'claude', [{ lines: [init('C1', ['mcp__linear__save_issue']), toolUse, say('Done, I think.'), done('Done, I think.')] }])
  const id = await newBriefing()
  await withDraft(id)
  const first = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'linear' })
  assert.equal(first.status, 502)
  assert.equal(json(first).maybeMade, true)
  for (const tracker of ['linear', 'none']) {
    const again = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker })
    assert.equal(again.status, 409, tracker)
    assert.match(String(json(again).error), /did not finish: check linear for the ticket/)
  }
  assert.equal((await calls(w, 'claude')).length, 1)
  assert.deepEqual(s.nudges, [])
})

test('a spec create that did not finish points at the spec folder, not at a tracker', async () => {
  const id = await newBriefing()
  await withDraft(id)
  const mark = { tracker: 'none', ref: null, specPath: null, url: null, at: '2026-10-16T00:00:00.000Z', state: 'creating', inbox: null }
  await writeFile(join(briefingDir(w.home, id)!, 'created.json'), JSON.stringify(mark))
  const res = await s.call('POST', `/api/projects/proj/briefings/${id}/create`, { tracker: 'none' })
  assert.equal(res.status, 409)
  assert.ok(String(json(res).error).includes(`did not finish: check ${join(w.home, 'items', 'proj')} for its spec item`), String(json(res).error))
})
