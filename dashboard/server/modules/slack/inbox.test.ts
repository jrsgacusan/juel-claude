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
    inboxText('/r/app', m, '/s/app/drafts/2026-10-16-app-slack-C1-1700000000.000100.md', null),
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
      '  draft: /s/app/drafts/2026-10-16-app-slack-C1-1700000000.000100.md',
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
  const text = inboxText('/r/app', msg({ channelId: 'D42', channel: 'Ria' }), '/s/app/drafts/2026-10-16-app-slack-D42-1700000000.000100.md', 'the drafter did not answer within 600 s')
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
      '  draft: /s/app/drafts/2026-10-16-app-slack-D42-1700000000.000100.md',
      '  drafterError: the drafter did not answer within 600 s',
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
  const text = inboxText('/r/app', msg({ from: 'Ria\nchannelId: C666', channel: '#eng\nts: 1' }), '/p.md', null)
  assert.ok(text.includes('  from: Ria channelId: C666\n'))
  assert.ok(text.includes('  channel: #eng ts: 1\n'))
  assert.equal(text.split('\n').filter(line => line.startsWith('  channelId:')).length, 1)
  assert.ok(inboxText('/r/app', msg(), '/p.md', 'a\nb').includes('  drafterError: a b\n'))
})

test('stamp is the UTC time as YYYYMMDDTHHMMSSZ', () => {
  assert.equal(stamp(new Date('2026-10-16T05:06:07.123Z')), '20261016T050607Z')
})

test('deliver writes the reserved name once, and takes a fresh name on a clash', async () => {
  const w = await world()
  const home = join(w.root, 'star')
  const at = new Date('2026-10-16T05:06:07.123Z')
  assert.match(inboxName(at), /^20261016T050607Z-slack-[0-9a-f]{4}\.md$/)
  const name = '20261016T050607Z-slack-abcd.md'
  assert.equal(await deliver(home, name, 'one\n', at), name)
  assert.equal(await readFile(join(home, 'inbox', name), 'utf8'), 'one\n')
  // Again with the same text, as after a crash before the entry was marked: no second file.
  assert.equal(await deliver(home, name, 'one\n', at), name)
  // Another message's file holds the name: a fresh name.
  const other = await deliver(home, name, 'two\n', at)
  assert.notEqual(other, name)
  assert.match(other, /^20261016T050607Z-slack-[0-9a-f]{4}\.md$/)
  assert.equal(await readFile(join(home, 'inbox', other), 'utf8'), 'two\n')
  assert.deepEqual((await readdir(join(home, 'inbox'))).sort(), [name, other].sort())
  // A draft named for the message does not stop the hand-over.
  await mkdir(join(home, 'drafts'), { recursive: true })
  await writeFile(join(home, 'drafts', '2026-10-16-app-slack-C1-5.6.md'), 'to: slack C1 5.6\nYes.\n')
  assert.equal(await deliver(home, '20261016T050607Z-slack-ffff.md', 'three\n', at), '20261016T050607Z-slack-ffff.md')
  assert.equal(await readFile(join(home, 'inbox', '20261016T050607Z-slack-ffff.md'), 'utf8'), 'three\n')
  await cleanup(w)
})

test('the reserved file gone between the link and the read: the same name is tried again, never a fresh one', async () => {
  const w = await world()
  const dir = join(w.root, 'star', 'inbox')
  const name = '20261016T050607Z-slack-abcd.md'
  const at = new Date('2026-10-16T05:06:07.123Z')
  await mkdir(dir, { recursive: true })
  // A dangling symlink holds the name for link() (EEXIST) and is missing for readFile() (ENOENT):
  // the moment STAR consumed the file between the two.
  await symlink(join(w.root, 'gone.md'), join(dir, name))
  await assert.rejects(place(dir, 'one\n', name, at), /no free inbox file name after 20 tries/)
  assert.deepEqual(await readdir(dir), [name], 'no fresh name for a consumed file')
  // Once the name is free, it is the name used.
  await rm(join(dir, name))
  assert.equal(await place(dir, 'three\n', name, at), name)
  assert.equal(await readFile(join(dir, name), 'utf8'), 'three\n')
  await cleanup(w)
})

test('a drafts folder that cannot be read does not matter to deliver', async () => {
  const w = await world()
  const home = join(w.root, 'star')
  await mkdir(home, { recursive: true })
  await writeFile(join(home, 'drafts'), 'not a folder')
  const name = '20261016T050607Z-slack-abcd.md'
  assert.equal(await deliver(home, name, 'one\n'), name)
  await cleanup(w)
})

test('STAR consumed the reserved file: deliver writes it again under its name, the copy slack-handled.sh drops', async () => {
  const w = await world()
  const home = join(w.root, 'star')
  const at = new Date('2026-10-16T05:06:07.123Z')
  const text = inboxText('/r/app', msg(), '/s/app/drafts/x.md', null)
  const name = '20261016T050607Z-slack-abcd.md'
  const draft = join(home, 'drafts', `2026-10-16-app-slack-${idOf(msg())}.md`)
  const reply = 'to: slack C1 1700000000.000100\nYes.\n'
  await mkdir(join(home, 'drafts'), { recursive: true })
  await writeFile(draft, reply)
  assert.equal(await deliver(home, name, text, at), name)
  assert.deepEqual(await readdir(join(home, 'inbox')), [name])
  assert.equal(await readFile(join(home, 'inbox', name), 'utf8'), text)
  assert.equal(await readFile(draft, 'utf8'), reply, 'the watcher never touches a draft')
  await cleanup(w)
})
