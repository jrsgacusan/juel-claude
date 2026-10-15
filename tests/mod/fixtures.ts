// A STAR folder as files: what star-home.sh init and STAR's own writes leave behind.
import { LEDGER_COLS } from '../../hooks/star'

export const ROOT = '/w/app'
export const HOME = `${ROOT}/docs/superpowers/context/star`

export const STAR = (terminal: string | null): string =>
  JSON.stringify({ schema: 2, terminal, away: null, gateDown: null, progressDeadlineMin: 30, project: { name: 'app', repo: ROOT } })

export function ledger(rows: readonly (readonly [item: string, state: string, worktree: string])[]): string {
  const head = `| ${LEDGER_COLS.join(' | ')} |`
  const rule = `|${'---|'.repeat(LEDGER_COLS.length)}`
  const body = rows.map(([item, state, worktree]) =>
    `| ${item} | #${item.slice(6)} | app | ${worktree} | ${state} | build | 1 | t-${item} | d-${item} | 0 | - | - | - | - | - | 2026-10-15T08:00:00Z |`)
  return ['# Ledger', '', head, rule, ...body, ''].join('\n')
}

export const LEDGER = ledger([
  ['issue-1', 'building', '/w/app-issue-1'],
  ['issue-2', 'building', '/w/app-issue-2'],
  ['issue-3', 'babysitting', '/w/app-issue-3'],
  ['issue-4', 'brief-ready', '-'],
  ['issue-5', 'escalated', '/w/app-issue-5'],
  ['issue-6', 'verifying', '/w/app-issue-6'],
  ['issue-7', 'done', '-'],
  ['issue-8', 'queued', '-'],
])

export const QUEUE = [
  '# Open loops',
  '',
  '## Resume',
  'state: running',
  'run: r-1',
  'last tick: 2026-10-15T08:00:00Z',
  'pools: brief 0/4 · build 2/3 · babysit 1/3',
  'next: -',
  '',
  '## Needs you',
  '<!-- Answer on an item\'s "Answer:" line. -->',
  '',
  '### N-12 · app · B-1 · go for batch B-1: 3 items',
  'kind: go-batch',
  'issue-1',
  'Options: go / go except <items> / drop <item>',
  'Answer:',
  '',
  '### N-13 · app · issue-4 · add the Stripe test key to .env.local',
  'kind: person',
  'Options: done / can\'t now',
  'Answer: done',
  '',
  '### N-14 · app · issue-5 · NOT-SAFE again after a re-scope',
  'kind: escalation',
  'Options: answer with your decision / drop',
  'Answer:',
  '',
  '## Waiting on others',
  '',
].join('\n')

// `cswap list --json` (claude-swap's schemaVersion 1): the active account, one near its weekly limit,
// a disabled one with only last-known usage and no alias, and one whose token expired.
export const CSWAP_LIST = JSON.stringify({
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
