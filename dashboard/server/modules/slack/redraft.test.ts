import assert from 'node:assert/strict'
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import { parseRedraft, redraftText } from './redraft.ts'
import { answer, brief, cleanup, drafter, freeGb, msg, play, project, replyQueue, stub, until, world } from './test-helpers.ts'
import type { DraftStub, World } from './test-helpers.ts'
import { createSlack } from './watcher.ts'
import type { SlackOptions } from './watcher.ts'

const NOW = new Date('2026-10-16T12:00:00.000Z')
const HOUR = 3_600_000
const ID = 'C1-1700000000.000100'

async function routed(w: World, d: DraftStub, opts: Partial<SlackOptions> = {}) {
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  const s = stub([app])
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft, ...opts })
  await play(w, [answer([msg({ text: 'is APP-77 landing today?' })])])
  await slack.check()
  const draft = join(app.home, 'drafts', `2026-10-16-app-slack-${ID}.md`)
  return { app, s, slack, draft }
}
const answerOf = async (home: string): Promise<string | undefined> =>
  (await readFile(join(home, 'open-loops.md'), 'utf8')).split('\n').find(line => line.startsWith('Answer:'))
const requests = (home: string): Promise<string[]> => readdir(join(home, 'slack', 'redraft')).catch(() => [])

test('redraftText and parseRedraft: three lines, how on one line', () => {
  const text = redraftText({ draft: '/s/app/drafts/x.md', loop: 'N-48', how: 'shorter\nin Taglish' })
  assert.equal(text, 'draft: /s/app/drafts/x.md\nloop: N-48\nhow: shorter in Taglish\n')
  assert.deepEqual(parseRedraft(text), { draft: '/s/app/drafts/x.md', loop: 'N-48', how: 'shorter in Taglish' })
  assert.deepEqual(parseRedraft('loop: 48\nhow: \n'), { draft: null, loop: null, how: null })
})

test('POST redraft queues a request; the drafter rewrites the reply under the same first line; STAR gets redrafted and a nudge', async () => {
  const w = await world()
  const d = drafter([{ ok: true, text: 'Yes, it lands today.' }, { ok: true, text: 'Oo, today na.' }])
  const { app, s, slack, draft } = await routed(w, d)
  await writeFile(join(app.home, 'open-loops.md'), replyQueue('N-48', draft))
  assert.deepEqual(await s.call('POST', '/api/projects/app/slack/redraft', { loop: 'N-48', how: 'shorter, in Taglish' }), { status: 200, json: { queued: true } })
  await slack.idle()
  assert.equal(await readFile(draft, 'utf8'), 'to: slack C1 1700000000.000100\nOo, today na.\n')
  assert.equal(d.asked[1]?.how, 'shorter, in Taglish')
  assert.equal(d.asked[1]?.previous, 'Yes, it lands today.')
  assert.equal(await answerOf(app.home), 'Answer: redrafted')
  assert.deepEqual(await requests(app.home), [])
  assert.deepEqual(s.nudges, ['app', 'app'])
  await cleanup(w)
})

test('POST redraft: 404 for a project or an item that is not there, 400 for a bad body or a draft that is not a Slack draft', async () => {
  const w = await world()
  const { app, s, draft } = await routed(w, drafter())
  await writeFile(join(app.home, 'open-loops.md'), replyQueue('N-48', draft))
  const url = '/api/projects/app/slack/redraft'
  assert.deepEqual(await s.call('POST', '/api/projects/nope/slack/redraft', { loop: 'N-48', how: 'shorter' }), { status: 404, json: { error: 'no project nope' } })
  for (const body of [null, {}, { loop: '48', how: 'shorter' }, { loop: 'N-48', how: ' \n ' }, { loop: 'N-48', how: 7 }]) {
    assert.equal((await s.call('POST', url, body)).status, 400, JSON.stringify(body))
  }
  assert.deepEqual(await s.call('POST', url, { loop: 'N-49', how: 'shorter' }), { status: 404, json: { error: 'no open slack-reply item N-49' } })
  const notes = join(w.root, 'notes.md')
  await writeFile(join(app.home, 'open-loops.md'), replyQueue('N-48', notes))
  assert.deepEqual(await s.call('POST', url, { loop: 'N-48', how: 'shorter' }), { status: 400, json: { error: `not a Slack draft: ${notes}` } })
  assert.deepEqual(await requests(app.home), [])
  await cleanup(w)
})

test('an item whose drafter had failed (its draft holds only the to line) is drafted again; a legacy draft: - item is found by its message', async () => {
  const w = await world()
  const d = drafter([{ ok: false, why: 'claude exited 1' }, { ok: true, text: 'Oo, today na.' }, { ok: true, text: 'Oo, today na talaga.' }])
  const { app, s, slack, draft } = await routed(w, d)
  assert.equal(await readFile(draft, 'utf8'), 'to: slack C1 1700000000.000100\n')
  await writeFile(join(app.home, 'open-loops.md'), replyQueue('N-48', draft))
  assert.deepEqual(await s.call('POST', '/api/projects/app/slack/redraft', { loop: 'N-48', how: 'try again' }), { status: 200, json: { queued: true } })
  await slack.idle()
  assert.equal(d.asked[1]?.previous, '')
  assert.equal(await readFile(draft, 'utf8'), 'to: slack C1 1700000000.000100\nOo, today na.\n')
  assert.equal(await answerOf(app.home), 'Answer: redrafted')
  await writeFile(join(app.home, 'open-loops.md'), replyQueue('N-49', '-'))
  assert.deepEqual(await s.call('POST', '/api/projects/app/slack/redraft', { loop: 'N-49', how: 'more' }), { status: 200, json: { queued: true } })
  await slack.idle()
  assert.equal(await readFile(draft, 'utf8'), 'to: slack C1 1700000000.000100\nOo, today na talaga.\n')
  await writeFile(join(app.home, 'open-loops.md'), replyQueue('N-50', '-', 'https://acme.slack.com/archives/C1/p1'))
  assert.deepEqual(await s.call('POST', '/api/projects/app/slack/redraft', { loop: 'N-50', how: 'try again' }), {
    status: 409,
    json: { error: 'N-50 has no draft, and its Slack message is not known' },
  })
  await cleanup(w)
})

test("a request STAR wrote (slack-redraft.sh) is found by the module's timer", async () => {
  const w = await world()
  const d = drafter([{ ok: true, text: 'Yes, it lands today.' }, { ok: true, text: 'Yes, PR #12 lands today.' }])
  const { app, slack, draft } = await routed(w, d, { redraftEveryMs: 20 })
  await writeFile(join(app.home, 'open-loops.md'), replyQueue('N-48', draft))
  await mkdir(join(app.home, 'slack', 'redraft'), { recursive: true })
  await writeFile(join(app.home, 'slack', 'redraft', '20261016T120000Z-abcd.md'), redraftText({ draft, loop: 'N-48', how: 'add the PR number' }))
  slack.start()
  await until(async () => (await answerOf(app.home)) === 'Answer: redrafted' && (await requests(app.home)).length === 0)
  slack.stop()
  assert.equal(await readFile(draft, 'utf8'), 'to: slack C1 1700000000.000100\nYes, PR #12 lands today.\n')
  assert.deepEqual(await requests(app.home), [])
  await cleanup(w)
})

test('a request whose draft is outside the drafts folder is refused and the file is never touched', async () => {
  const w = await world()
  const { app, s, slack } = await routed(w, drafter(), { redraftEveryMs: 20 })
  const notes = join(w.root, 'notes.md')
  await writeFile(notes, 'keep me\n')
  await writeFile(join(app.home, 'open-loops.md'), replyQueue('N-48', notes))
  await mkdir(join(app.home, 'slack', 'redraft'), { recursive: true })
  await writeFile(join(app.home, 'slack', 'redraft', '20261016T120000Z-abcd.md'), redraftText({ draft: notes, loop: 'N-48', how: 'shorter' }))
  await writeFile(join(app.home, 'slack', 'redraft', '20261016T120001Z-ef01.md'), 'how: shorter\n')
  slack.start()
  await until(async () => (await requests(app.home)).length === 0)
  slack.stop()
  assert.equal(await readFile(notes, 'utf8'), 'keep me\n')
  assert.equal(await answerOf(app.home), 'Answer: redraft failed: not a Slack draft')
  assert.ok(s.logs.includes('slack: a redraft request with no loop line was removed: 20261016T120001Z-ef01.md'), s.logs.join('\n'))
  await cleanup(w)
})

test('below 3 GB free, a redraft request waits for the next pass (I-12)', async () => {
  const w = await world()
  const d = drafter([{ ok: true, text: 'Yes, it lands today.' }, { ok: true, text: 'Oo, today na.' }])
  const { app, s, slack, draft } = await routed(w, d, { redraftEveryMs: 20 })
  await writeFile(join(app.home, 'open-loops.md'), replyQueue('N-48', draft))
  await freeGb(w, 1)
  assert.equal((await s.call('POST', '/api/projects/app/slack/redraft', { loop: 'N-48', how: 'shorter' })).status, 200)
  await slack.idle()
  assert.equal((await requests(app.home)).length, 1)
  assert.equal(await readFile(draft, 'utf8'), 'to: slack C1 1700000000.000100\nYes, it lands today.\n')
  assert.equal(await answerOf(app.home), 'Answer:')
  assert.equal(d.asked.length, 1)
  await freeGb(w, 4)
  slack.start()
  await until(async () => (await answerOf(app.home)) === 'Answer: redrafted')
  slack.stop()
  await cleanup(w)
})

test('a redraft that fails leaves the draft as it was and records redraft failed: <why>', async () => {
  const w = await world()
  const d = drafter([{ ok: true, text: 'Yes, it lands today.' }, { ok: false, why: 'claude exited 1: Error: rate limited' }])
  const { app, s, slack, draft } = await routed(w, d)
  await writeFile(join(app.home, 'open-loops.md'), replyQueue('N-48', draft))
  assert.equal((await s.call('POST', '/api/projects/app/slack/redraft', { loop: 'N-48', how: 'shorter' })).status, 200)
  await slack.idle()
  assert.equal(await readFile(draft, 'utf8'), 'to: slack C1 1700000000.000100\nYes, it lands today.\n')
  assert.equal(await answerOf(app.home), 'Answer: redraft failed: claude exited 1: Error: rate limited')
  assert.deepEqual(await requests(app.home), [])
  await cleanup(w)
})
