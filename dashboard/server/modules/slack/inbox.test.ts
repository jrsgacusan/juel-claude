import assert from 'node:assert/strict'
import { readdir, readFile } from 'node:fs/promises'
import { basename, join } from 'node:path'
import { test } from 'node:test'

import { channelLabel, inboxText, stamp, writeInbox } from './inbox.ts'
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

test('writeInbox names the file <UTC>-slack-<4 hex>.md, never overwrites, and leaves no temp file', async () => {
  const w = await world()
  const home = join(w.root, 'star')
  const at = new Date('2026-10-16T05:06:07.123Z')
  const a = await writeInbox(home, 'one\n', at)
  const b = await writeInbox(home, 'two\n', at)
  assert.match(basename(a), /^20261016T050607Z-slack-[0-9a-f]{4}\.md$/)
  assert.match(basename(b), /^20261016T050607Z-slack-[0-9a-f]{4}\.md$/)
  assert.notEqual(a, b)
  assert.equal(await readFile(a, 'utf8'), 'one\n')
  assert.equal(await readFile(b, 'utf8'), 'two\n')
  assert.deepEqual((await readdir(join(home, 'inbox'))).sort(), [basename(a), basename(b)].sort())
  await cleanup(w)
})