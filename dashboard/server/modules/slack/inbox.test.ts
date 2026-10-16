import assert from 'node:assert/strict'
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import { channelLabel, deliver, inboxName, inboxText, stamp } from './inbox.ts'
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
