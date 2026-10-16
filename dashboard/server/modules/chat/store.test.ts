import assert from 'node:assert/strict'
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

import { chatInboxText, isoSeconds, linkNew, messageText, pageOf, parseMessage, readThread, repoOf, stamp, writeInbox, writeMine } from './store.ts'
import type { ChatMessage } from './store.ts'
import { MSGS, cleanup, world, writeThread } from './test-helpers.ts'

const AT = new Date('2026-10-17T01:02:03.456Z')
const GOOD = 'id: 20261017T010203Z-me-ab12\nwho: me\nat: 2026-10-17T01:02:03Z\nreplyTo: -\n---\nhi\n'

test('stamp and isoSeconds drop the milliseconds', () => {
  assert.equal(stamp(AT), '20261017T010203Z')
  assert.equal(isoSeconds(AT), '2026-10-17T01:02:03Z')
})

test('a message file is the I-2 header, a --- line, then the text, and it reads back', () => {
  const m: ChatMessage = { id: '20261017T010203Z-me-ab12', who: 'me', at: '2026-10-17T01:02:03Z', replyTo: null, text: 'how is it going?\n\n- one' }
  assert.equal(messageText(m), 'id: 20261017T010203Z-me-ab12\nwho: me\nat: 2026-10-17T01:02:03Z\nreplyTo: -\n---\nhow is it going?\n\n- one\n')
  assert.deepEqual(parseMessage('20261017T010203Z-me-ab12.md', messageText(m)), m)
  const reply: ChatMessage = { id: '20261017T010210Z-star-cd34', who: 'star', at: '2026-10-17T01:02:10Z', replyTo: m.id, text: 'Two rows run.\n---\nMore below.' }
  assert.deepEqual(parseMessage(`${reply.id}.md`, messageText(reply)), reply)
  assert.equal(parseMessage('20261017T010203Z-me-ab12.md', GOOD.replace('hi\n', 'hi\n\n\n'))?.text, 'hi')
})

test('a file that does not parse is null', () => {
  const cases: [string, string][] = [
    ['20261017T010203Z-me-ab12.md', 'hello'],
    ['20261017T010203Z-me-ab12.md', GOOD.replace('who: me', 'who: bot')],
    ['20261017T010203Z-me-ab12.md', GOOD.replace('at: 2026-10-17T01:02:03Z', 'at: soon')],
    ['20261017T010203Z-me-ab12.md', GOOD.replace('replyTo: -', 'replyTo: N-12')],
    ['20261017T010203Z-me-ab12.md', GOOD.replace('\n---\n', '\n')],
    ['20261017T010203Z-me-ab12.md', GOOD.replace('who: me\n', '')],
    ['20261017T010203Z-me-ffff.md', GOOD],
    ['20261017T010203Z-me-ab12.txt', GOOD],
    ['notes.md', GOOD],
  ]
  for (const [name, content] of cases) assert.equal(parseMessage(name, content), null, `${name}: ${content}`)
})

test('the inbox file is repo, chat, then the text with every line indented two spaces', () => {
  assert.equal(
    chatInboxText('/w/proj', '20261017T010203Z-me-ab12', 'line one\n\nline three'),
    'repo: /w/proj\nchat: 20261017T010203Z-me-ab12\ntext: |\n  line one\n  \n  line three\n',
  )
})

test('linkNew makes the folder, never overwrites, and leaves no temp file', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chat-link-'))
  try {
    await writeFile(join(dir, 'a.md'), 'first')
    assert.equal(await linkNew(join(dir, 'a.md'), 'second'), false)
    assert.equal(await readFile(join(dir, 'a.md'), 'utf8'), 'first')
    assert.deepEqual(await readdir(dir), ['a.md'])
    assert.equal(await linkNew(join(dir, 'sub', 'b.md'), 'x'), true)
    assert.deepEqual(await readdir(join(dir, 'sub')), ['b.md'])
  } finally {
    await rm(dir, { recursive: true, force: true })
  }
})

test('writeMine and writeInbox make their folders and write the exact files', async () => {
  const w = await world()
  try {
    const m = await writeMine(w.home, 'hi there', AT)
    assert.match(m.id, /^20261017T010203Z-me-[0-9a-f]{4}$/)
    assert.deepEqual({ ...m, id: 'x' }, { id: 'x', who: 'me', at: '2026-10-17T01:02:03Z', replyTo: null, text: 'hi there' })
    assert.deepEqual(await readdir(join(w.home, 'chat')), [`${m.id}.md`])
    assert.equal(await readFile(join(w.home, 'chat', `${m.id}.md`), 'utf8'), messageText(m))
    const name = await writeInbox(w.home, 'control', 'control: away\n', AT)
    assert.match(name, /^20261017T010203Z-control-[0-9a-f]{4}\.md$/)
    assert.deepEqual(await readdir(join(w.home, 'inbox')), [name])
    assert.equal(await readFile(join(w.home, 'inbox', name), 'utf8'), 'control: away\n')
  } finally {
    await cleanup(w)
  }
})

test('readThread sorts by name and skips what does not parse; pageOf pages back from the newest', async () => {
  const w = await world()
  try {
    assert.deepEqual(await readThread(w.home), [])
    await writeThread(w.home, MSGS)
    await writeFile(join(w.home, 'chat', '20261017T010006Z-me-0006.md'), 'garbage')
    await writeFile(join(w.home, 'chat', '.20261017T010007Z-me-0007.md.1.abcd.tmp'), GOOD)
    await mkdir(join(w.home, 'chat', 'old'))
    const thread = await readThread(w.home)
    assert.deepEqual(thread, MSGS)
    const ids = (page: { messages: ChatMessage[] }): string[] => page.messages.map(m => m.id)
    const all = MSGS.map(m => m.id)
    assert.deepEqual(pageOf(thread, null, 100), { messages: MSGS, hasMore: false })
    const last = pageOf(thread, null, 2)
    assert.deepEqual([ids(last), last.hasMore], [all.slice(3), true])
    const middle = pageOf(thread, all[3], 2)
    assert.deepEqual([ids(middle), middle.hasMore], [all.slice(1, 3), true])
    const first = pageOf(thread, all[1], 2)
    assert.deepEqual([ids(first), first.hasMore], [all.slice(0, 1), false])
  } finally {
    await cleanup(w)
  }
})

test('repoOf reads project.repo from star.json, else the fallback', async () => {
  const w = await world()
  try {
    assert.equal(await repoOf(w.home, '/fallback'), '/w/proj')
    await writeFile(join(w.home, 'star.json'), 'not json')
    assert.equal(await repoOf(w.home, '/fallback'), '/fallback')
    await rm(join(w.home, 'star.json'))
    assert.equal(await repoOf(w.home, '/fallback'), '/fallback')
  } finally {
    await cleanup(w)
  }
})
