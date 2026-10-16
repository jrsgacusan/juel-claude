import assert from 'node:assert/strict'
import { test } from 'node:test'

import { ID_RE, isId, newId, stamp } from './ids.ts'

test('stamp is UTC YYYYMMDDTHHMMSSZ', () => {
  assert.equal(stamp(new Date('2026-10-16T03:04:05.678Z')), '20261016T030405Z')
})

test('a new id has the inbox form and passes isId', () => {
  const id = newId(new Date('2026-10-16T03:04:05Z'))
  assert.match(id, /^20261016T030405Z-[0-9a-f]{4}$/)
  assert.ok(ID_RE.test(id))
  assert.equal(isId(id), true)
})

test('isId refuses anything that could leave the briefings folder', () => {
  for (const bad of ['', '..', '../x', '20261016T030405Z-zzzz', '20261016T030405Z-abcd/..', 'a/b', null, 42]) {
    assert.equal(isId(bad), false, String(bad))
  }
})
