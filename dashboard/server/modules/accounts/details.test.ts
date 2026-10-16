import assert from 'node:assert/strict'
import { test } from 'node:test'

import { parseAccountDetails, parseAccounts } from '../../../../hooks/cswap.ts'
import { CSWAP_BASE, CSWAP_FULL } from './fixtures.ts'

const W = { resetsAt: null, countdown: null, expectedPct: null, aheadOfPace: false, projectedExhaustionAt: null, willLastToReset: null }

test("parseAccounts reads cswap's full payload exactly as the band's own fixture", () => {
  assert.deepEqual(parseAccounts(CSWAP_FULL), parseAccounts(CSWAP_BASE))
  const parsed = parseAccounts(CSWAP_FULL)
  if (!parsed.ok) throw new Error(parsed.why)
  // the values tests/mod/rules.test.ts:334-339 pins for the band
  assert.deepEqual(parsed.value.map(a => [a.alias, a.isActive, a.fiveHour, a.sevenDay, a.resets]), [
    ['personal', true, 5, 64, null],
    ['sphere', false, 0, 98, '1d 23h'],
    ['carol', false, 24, 7, null],
    ['old', false, null, null, null],
  ])
})

test('parseAccountDetails keeps both windows, the scoped limits, the login expiry and the age', () => {
  const parsed = parseAccountDetails(CSWAP_FULL)
  if (!parsed.ok) throw new Error(parsed.why)
  const [personal, sphere, carol, old] = parsed.value
  assert.deepEqual(personal, {
    number: 2, alias: 'personal', email: 'b@example.com', isActive: true, isDisabled: false, status: '',
    fiveHour: { ...W, usedPct: 5, resetsAt: '2026-10-16T22:09:59.572340+00:00', countdown: '4h 36m' },
    sevenDay: { usedPct: 64, resetsAt: '2026-10-19T18:59:59.648616+00:00', countdown: '4d 3h', expectedPct: 57,
      aheadOfPace: true, projectedExhaustionAt: '2026-10-18T06:17:11Z', willLastToReset: false },
    scoped: [], loginExpiresAt: '2026-11-13T14:17:12Z', usageAgeSeconds: 463.8, isStale: false,
  })
  assert.deepEqual(sphere?.fiveHour, { ...W, usedPct: 0 })
  // the entry with no name and the one with no share are left out
  assert.deepEqual(sphere?.scoped, [{ name: 'Fable', usedPct: 53, resetsAt: '2026-10-17T14:59:59.686317+00:00', countdown: '1d 23h',
    expectedPct: 88, aheadOfPace: false, projectedExhaustionAt: '2026-10-22T06:04:42Z', willLastToReset: true }])
  assert.deepEqual([carol?.alias, carol?.isDisabled, carol?.isStale, carol?.status, carol?.fiveHour?.usedPct, carol?.sevenDay?.usedPct, carol?.usageAgeSeconds, carol?.loginExpiresAt],
    ['carol', true, true, 'unavailable', 24, 7, null, '2026-11-13T19:59:46Z'])
  assert.deepEqual([old?.alias, old?.status, old?.fiveHour, old?.sevenDay, old?.scoped, old?.loginExpiresAt, old?.isStale],
    ['old', 'token expired', null, null, [], null, false])
})

test('parseAccountDetails says why a payload cannot be read, in parseAccounts words', () => {
  assert.deepEqual(parseAccountDetails('not json'), { ok: false, why: 'cswap list --json printed no JSON' })
  assert.deepEqual(parseAccountDetails(JSON.stringify({ schemaVersion: 1, error: { message: 'no accounts file' } })), { ok: false, why: 'cswap: no accounts file' })
  assert.deepEqual(parseAccountDetails(JSON.stringify({ schemaVersion: 2, accounts: [] })), { ok: false, why: 'cswap list --json: an unknown schema' })
})
