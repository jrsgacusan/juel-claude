import assert from 'node:assert/strict'
import { mkdir, readdir, readFile, rm, symlink, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import { channelLabel, deliver, inboxName, inboxText, place, stamp } from './inbox.ts'
import { idOf } from './state.ts'
import { cleanup, msg, world } from './test-helpers.ts'

test('a thread reply in a channel: the exact block of D1 and D9', () => {
  const m = msg({
    channel: 'eng',
    threadTs: '1699999999.000200',
    text: 'line one\r\n\r\nline three',
    thread: ['Ann: did it ship?', 'Bo: not yet\nsoon'],
  })
  assert.equal(
    inboxText('/r/app', m),
    [
      'repo: /r/app',
      'slack:',
      '  id: C1-1700000000.000100',
      '  channel: #eng',
      '  channelId: C1',
      '  ts: 1700000000.000100',
      '  threadTs: 1699999999.000200',
      '  from: Ria',
      '  permalink: https://acme.slack.com/archives/C1/p1700000000000100',
      '  text: |',
      '    line one',
      '    ',
      '    line three',
      '  thread: |',
      '    Ann: did it ship?',
      '    Bo: not yet',
      '    soon',
      '',
    ].join('\n'),
  )
})

test('a DM: channel "a DM", threadTs "-", and no thread block', () => {
  const text = inboxText('/r/app', msg({ channelId: 'D42', channel: 'Ria' }))
  assert.equal(
    text,
    [
      'repo: /r/app',
      'slack:',
      '  id: D42-1700000000.000100',
      '  channel: a DM',
      '  channelId: D42',
      '  ts: 1700000000.000100',
      '  threadTs: -',
      '  from: Ria',
      '  permalink: https://acme.slack.com/archives/C1/p1700000000000100',
      '  text: |',
      '    is the CSV export landing today?',
      '',
    ].join('\n'),
  )
})

test('channel labels (S2)', () => {
  assert.equal(channelLabel('C1', '#eng'), '#eng')
  assert.equal(channelLabel('C1', 'eng'), '#eng')
  assert.equal(channelLabel('C1', '##eng'), '#eng')
  assert.equal(channelLabel('G7', 'a DM'), 'a DM')
  assert.equal(channelLabel('G7', 'A dm'), 'a DM')
  assert.equal(channelLabel('D1', '#odd'), 'a DM')
})

test('single-line fields stay on one line, so a message cannot add a line to the block', () => {
  const text = inboxText('/r/app', msg({ from: 'Ria\nchannelId: C666', channel: '#eng\nts: 1' }))
  assert.ok(text.includes('  from: Ria channelId: C666\n'))
  assert.ok(text.includes('  channel: #eng ts: 1\n'))
  assert.equal(text.split('\n').filter(line => line.startsWith('  channelId:')).length, 1)
})

test('stamp is the UTC time as YYYYMMDDTHHMMSSZ', () => {
  assert.equal(stamp(new Date('2026-10-16T05:06:07.123Z')), '20261016T050607Z')
})

test('deliver writes the reserved name once, takes a fresh name on a clash, and skips a reply STAR drafted', async () => {
  const w = await world()
  const home = join(w.root, 'star')
  const at = new Date('2026-10-16T05:06:07.123Z')
  assert.match(inboxName(at), /^20261016T050607Z-slack-[0-9a-f]{4}\.md$/)
  const name = '20261016T050607Z-slack-abcd.md'
  assert.equal(await deliver(home, name, 'C1-1.2', 'one\n', at), name)
  assert.equal(await readFile(join(home, 'inbox', name), 'utf8'), 'one\n')
  // Again with the same text, as after a crash before the entry was marked: no second file.
  assert.equal(await deliver(home, name, 'C1-1.2', 'one\n', at), name)
  // Another message's file holds the name: a fresh name.
  const other = await deliver(home, name, 'C1-3.4', 'two\n', at)
  assert.notEqual(other, name)
  assert.match(other, /^20261016T050607Z-slack-[0-9a-f]{4}\.md$/)
  assert.equal(await readFile(join(home, 'inbox', other), 'utf8'), 'two\n')
  assert.deepEqual((await readdir(join(home, 'inbox'))).sort(), [name, other].sort())
  // STAR already drafted the reply (it drafts before it deletes the inbox file): nothing is written.
  await mkdir(join(home, 'drafts'), { recursive: true })
  await writeFile(join(home, 'drafts', '2026-10-16-app-slack-C1-5.6.md'), 'to: slack C1 5.6\nYes.\n')
  assert.equal(await deliver(home, '20261016T050607Z-slack-ffff.md', 'C1-5.6', 'three\n', at), '20261016T050607Z-slack-ffff.md')
  assert.equal((await readdir(join(home, 'inbox'))).length, 2)
  await cleanup(w)
})

test('the reserved file gone between the link and the read: done means handed over, never a fresh name', async () => {
  const w = await world()
  const dir = join(w.root, 'star', 'inbox')
  const name = '20261016T050607Z-slack-abcd.md'
  const at = new Date('2026-10-16T05:06:07.123Z')
  await mkdir(dir, { recursive: true })
  // A dangling symlink holds the name for link() (EEXIST) and is missing for readFile() (ENOENT):
  // the moment STAR consumed the file between the two.
  await symlink(join(w.root, 'gone.md'), join(dir, name))
  let looks = 0
  const drafted = async (): Promise<boolean> => {
    looks += 1
    return true
  }
  assert.equal(await place(dir, 'one\n', name, at, drafted), name)
  assert.equal(looks, 1)
  assert.deepEqual(await readdir(dir), [name], 'no second inbox file')
  // No draft: the name is retried, never swapped for a fresh one; a name that stays held is an error.
  await assert.rejects(place(dir, 'two\n', name, at, async () => false), /no free inbox file name/)
  assert.deepEqual(await readdir(dir), [name], 'no fresh name for a consumed file')
  // Once the name is free, it is the name used.
  await rm(join(dir, name))
  assert.equal(await place(dir, 'three\n', name, at, async () => false), name)
  assert.equal(await readFile(join(dir, name), 'utf8'), 'three\n')
  await cleanup(w)
})

test('a drafts folder that cannot be read is an error, never "no draft"', async () => {
  const w = await world()
  const home = join(w.root, 'star')
  await mkdir(home, { recursive: true })
  await writeFile(join(home, 'drafts'), 'not a folder')
  await assert.rejects(deliver(home, '20261016T050607Z-slack-abcd.md', 'C1-1.2', 'one\n'), /ENOTDIR/)
  await assert.rejects(readdir(join(home, 'inbox')), /ENOENT/)
  await cleanup(w)
})

test('the recovery race: STAR ingests the reserved file and drafts it between the draft check and the link', async () => {
  const w = await world()
  const home = join(w.root, 'star')
  const at = new Date('2026-10-16T05:06:07.123Z')
  const m = msg()
  const id = idOf(m)
  const text = inboxText('/r/app', m)
  const name = '20261016T050607Z-slack-abcd.md'
  const draft = join(home, 'drafts', `2026-10-16-app-slack-${id}.md`)
  const reply = 'to: slack C1 1700000000.000100\nYes.\n'
  // A pending hand-over: a crash left the reserved file in inbox/ before the entry was marked delivered.
  await mkdir(join(home, 'inbox'), { recursive: true })
  await writeFile(join(home, 'inbox', name), text)
  let ran = 0
  const got = await deliver(home, name, id, text, at, async () => {
    ran += 1
    // STAR's tick, after deliver's draft check found no draft and before its link.
    await rm(join(home, 'inbox', name))
    await mkdir(join(home, 'drafts'), { recursive: true })
    await writeFile(draft, reply)
  })
  assert.equal(ran, 1)
  assert.equal(got, name)
  const left = await readdir(join(home, 'inbox'))
  assert.deepEqual(left, [name], 'the link writes the message again under its reserved name: the copy slack-handled.sh drops')
  const body = await readFile(join(home, 'inbox', name), 'utf8')
  assert.equal(body, text)
  assert.ok(body.split('\n').includes(`  id: ${id}`))
  assert.equal(await readFile(draft, 'utf8'), reply, 'the watcher never touches a draft')
  await cleanup(w)
})

test('the seam runs only after a draft check that found no draft', async () => {
  const w = await world()
  const home = join(w.root, 'star')
  const at = new Date('2026-10-16T05:06:07.123Z')
  const m = msg()
  const id = idOf(m)
  const text = inboxText('/r/app', m)
  const name = '20261016T050607Z-slack-abcd.md'
  const draft = join(home, 'drafts', `2026-10-16-app-slack-${id}.md`)
  const reply = 'to: slack C1 1700000000.000100\nYes.\n'
  await mkdir(join(home, 'drafts'), { recursive: true })
  await writeFile(draft, reply)
  let ran = 0
  const got = await deliver(home, name, id, text, at, async () => {
    ran += 1
  })
  assert.equal(got, name)
  assert.equal(ran, 0)
  await assert.rejects(readdir(join(home, 'inbox')), /ENOENT/)
  assert.equal(await readFile(draft, 'utf8'), reply)
  await cleanup(w)
})
