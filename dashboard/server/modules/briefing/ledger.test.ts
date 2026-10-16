import assert from 'node:assert/strict'
import { mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import { ledgerRefs } from './ledger.ts'
import { cleanup, ledgerText, world } from './test-helpers.ts'

test('ledgerRefs is [] when there is no ledger.md', async () => {
  const w = await world()
  try {
    assert.deepEqual(await ledgerRefs(w.home), [])
  } finally {
    await cleanup(w)
  }
})

test("ledgerRefs returns every row's ref, whatever its state", async () => {
  const w = await world()
  try {
    await writeFile(join(w.home, 'ledger.md'), ledgerText([
      { item: 'a', ref: '#42', state: 'done' },
      { item: 'b', ref: '/x/items/proj/retry.md', state: 'dropped' },
      { item: 'c', ref: 'ENG-7', state: 'building' },
    ]))
    assert.deepEqual(await ledgerRefs(w.home), ['#42', '/x/items/proj/retry.md', 'ENG-7'])
  } finally {
    await cleanup(w)
  }
})

test('ledgerRefs reads past a blank line between rows and stops at the first line that is not a row', async () => {
  const w = await world()
  try {
    const table = ledgerText([{ item: 'a', ref: '#1', state: 'done' }, { item: 'b', ref: '#2', state: 'inbox' }])
    const lines = table.split('\n')
    const withBlank = [
      '# STAR ledger',
      '',
      'Some intro.',
      '',
      ...lines.slice(0, 3),
      '',
      lines[3],
      '',
      'Notes after the table.',
      '| not | a | row |',
      '',
    ].join('\n')
    await writeFile(join(w.home, 'ledger.md'), withBlank)
    assert.deepEqual(await ledgerRefs(w.home), ['#1', '#2'])
  } finally {
    await cleanup(w)
  }
})

test('ledgerRefs matches no ref by prefix: it returns the cells as written', async () => {
  const w = await world()
  try {
    await writeFile(join(w.home, 'ledger.md'), ledgerText([{ item: 'a', ref: '#4', state: 'done' }, { item: 'b', ref: '#420', state: 'done' }]))
    const refs = await ledgerRefs(w.home)
    assert.deepEqual(refs, ['#4', '#420'])
    assert.equal(refs.includes('#42'), false)
  } finally {
    await cleanup(w)
  }
})

test("ledgerRefs throws, naming the file, for a ledger.md that is not STAR's ledger table", async () => {
  const cases = [
    '# just notes\n',
    '| item | ref | state |\n|---|---|---|\n',
    ledgerText([]).replace('| item | ref |', '| item | reference |'),
    ledgerText([]) + '| a | #42 | proj | - | done | brief | 0 | - | - | 0 | - | - | - | - | - |\n',
  ]
  for (const text of cases) {
    const w = await world()
    try {
      await writeFile(join(w.home, 'ledger.md'), text)
      await assert.rejects(ledgerRefs(w.home), err => (err as Error).message.includes(join(w.home, 'ledger.md')))
    } finally {
      await cleanup(w)
    }
  }
})

test('ledgerRefs throws, naming the file, when ledger.md cannot be read', async () => {
  const w = await world()
  try {
    await mkdir(join(w.home, 'ledger.md'))
    await assert.rejects(ledgerRefs(w.home), err => (err as Error).message.includes(join(w.home, 'ledger.md')))
  } finally {
    await cleanup(w)
  }
})
