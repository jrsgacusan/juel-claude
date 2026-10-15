import assert from 'node:assert/strict'
import { mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import { readDrafts, readOpenReplies, replyOf } from './replies.ts'
import { cleanup, msg, world } from './test-helpers.ts'

const ID = 'C1-1700000000.000100'
const NAME = '2026-10-16-app-slack-C1-1700000000.000100.md'
const DRAFT = { name: NAME, to: 'to: slack C1 1700000000.000100' }

const item = (id: string, draft: string, answer = ''): string =>
  `### ${id} · app · slack · Ria in #eng: is it landing?\nkind: slack-reply\ndraft: drafts/${draft}\n` +
  `message: https://acme.slack.com/x\nOptions: send (recommended) / rewrite: <how> / skip\nAnswer:${answer ? ` ${answer}` : ''}\n`
const queue = (items: string): string => `# Open loops\n\n## Needs you\n\n${items}\n## Waiting on others\n`

test('no draft yet: listed, with null draftPath and loopId', () => {
  assert.deepEqual(replyOf(msg(), ID, [], []), { draftPath: null, loopId: null, finished: false })
})

test("a draft and its open slack-reply item: listed with both; no open item: finished", () => {
  const open = [{ id: 'N-4', body: [`draft: drafts/${NAME}`] }]
  assert.deepEqual(replyOf(msg(), ID, [DRAFT], open), { draftPath: `drafts/${NAME}`, loopId: 'N-4', finished: false })
  assert.deepEqual(replyOf(msg(), ID, [DRAFT], []), { draftPath: `drafts/${NAME}`, loopId: null, finished: true })
  assert.deepEqual(replyOf(msg(), ID, [DRAFT], null), { draftPath: `drafts/${NAME}`, loopId: null, finished: false })
})

test('a rewrite re-adds the item: the last open one is the loop', () => {
  const open = [
    { id: 'N-4', body: [`draft: drafts/${NAME}`] },
    { id: 'N-9', body: [`draft: drafts/${NAME}`] },
  ]
  assert.equal(replyOf(msg(), ID, [DRAFT], open).loopId, 'N-9')
})

test('a thread reply matches the draft addressed to its thread', () => {
  const reply = msg({ ts: '1700000005.000000', threadTs: '1700000000.000100' })
  assert.equal(replyOf(reply, 'C1-1700000005.000000', [DRAFT], null).draftPath, `drafts/${NAME}`)
  assert.equal(replyOf(msg({ channelId: 'C2' }), 'C2-1700000000.000100', [DRAFT], null).draftPath, null)
})

test('readDrafts and readOpenReplies read the STAR folder', async () => {
  const w = await world()
  const home = join(w.root, 'star')
  assert.deepEqual(await readDrafts(home), [])
  assert.equal(await readOpenReplies(home), null)
  await mkdir(join(home, 'drafts'), { recursive: true })
  await writeFile(join(home, 'drafts', NAME), 'to: slack  C1 1700000000.000100 \nNot today.\n')
  await writeFile(join(home, 'drafts', '2026-10-16-app-issue-4-release.md'), 'release notes\n')
  assert.deepEqual(await readDrafts(home), [DRAFT])
  await writeFile(join(home, 'open-loops.md'), queue(`${item('N-4', NAME)}\n${item('N-5', NAME, 'send')}`))
  assert.deepEqual((await readOpenReplies(home))?.map(loop => loop.id), ['N-4'])
  await writeFile(join(home, 'open-loops.md'), '# Open loops\n\nno sections\n')
  assert.equal(await readOpenReplies(home), null)
  await cleanup(w)
})