// Fixtures for the accounts module's tests. CSWAP_BASE is a verbatim copy of tests/mod/fixtures.ts (CSWAP_LIST):
// Node cannot import that file, since its ../../hooks/star import has no extension.
export const CSWAP_BASE = JSON.stringify({
  schemaVersion: 1,
  activeAccountNumber: 2,
  accounts: [
    { number: 1, email: 'a@example.com', alias: 'sphere', active: false, usageStatus: 'ok',
      usage: { fiveHour: { pct: 0.0 }, sevenDay: { pct: 98.0, countdown: '1d 23h' } } },
    { number: 2, email: 'b@example.com', alias: 'personal', active: true, usageStatus: 'ok',
      usage: { fiveHour: { pct: 5.0, countdown: '4h 36m' }, sevenDay: { pct: 64.4, countdown: '4d 3h' } } },
    { number: 3, email: 'carol@example.com', active: false, disabled: true, usageStatus: 'unavailable', usage: null,
      lastGoodUsage: { fiveHour: { pct: 24.0 }, sevenDay: { pct: 7.0 } } },
    { number: 4, email: 'd@example.com', alias: 'old', active: false, usageStatus: 'token_expired', usage: null },
  ],
})

export const CSWAP_FULL = JSON.stringify({
  schemaVersion: 1,
  activeAccountNumber: 2,
  accounts: [
    { number: 1, email: 'a@example.com', alias: 'sphere', organizationName: "a@example.com's Organization", isOrganization: true,
      active: false, usageStatus: 'ok',
      usage: {
        fiveHour: { pct: 0.0 },
        sevenDay: { pct: 98.0, resetsAt: '2026-10-17T14:59:59.686165+00:00', countdown: '1d 23h', clock: '22:59', expectedPct: 88.0,
          aheadOfPace: false, projectedExhaustionAt: '2026-10-16T21:55:48Z', willLastToReset: false },
        scoped: [
          { pct: 53.0, resetsAt: '2026-10-17T14:59:59.686317+00:00', countdown: '1d 23h', clock: '22:59', expectedPct: 88.0,
            aheadOfPace: false, projectedExhaustionAt: '2026-10-22T06:04:42Z', willLastToReset: true, name: 'Fable' },
          { pct: 10.0 },
          { name: 'Haiku' },
        ],
      },
      loginExpiresAt: '2026-11-10T05:20:45Z', usageFetchedAt: '2026-10-16T18:54:41Z', usageAgeSeconds: 202.7 },
    { number: 2, email: 'b@example.com', alias: 'personal', active: true, usageStatus: 'ok',
      usage: {
        fiveHour: { pct: 5.0, resetsAt: '2026-10-16T22:09:59.572340+00:00', countdown: '4h 36m', clock: '06:09' },
        sevenDay: { pct: 64.4, resetsAt: '2026-10-19T18:59:59.648616+00:00', countdown: '4d 3h', clock: 'Oct 20 02:59', expectedPct: 57.0,
          aheadOfPace: true, projectedExhaustionAt: '2026-10-18T06:17:11Z', willLastToReset: false },
        scoped: [],
      },
      loginExpiresAt: '2026-11-13T14:17:12Z', usageFetchedAt: '2026-10-16T18:50:20Z', usageAgeSeconds: 463.8 },
    { number: 3, email: 'carol@example.com', active: false, disabled: true, usageStatus: 'unavailable', usage: null,
      lastGoodUsage: { fiveHour: { pct: 24.0 }, sevenDay: { pct: 7.0 } }, loginExpiresAt: '2026-11-13T19:59:46Z' },
    { number: 4, email: 'd@example.com', alias: 'old', active: false, usageStatus: 'token_expired', usage: null },
  ],
  unclaimedCredentials: ['20261015T214918-adde39fed788-b4269d'],
})
