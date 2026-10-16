// GET /api/accounts: cswap's accounts for the dashboard's Accounts page, read-only. It never runs any
// cswap command but `list --json`. It reads under STAR's own Claude login (claudeConfigDir in
// dashboard.json, else the server's CLAUDE_CONFIG_DIR, else ~/.claude; spec 3.12, "Which login is
// active"), since cswap marks the active account per config folder and the auto-switch counts only for
// that login. One reading runs at a time, once a minute; fetchedAt is the last reading that parsed.
import os from 'node:os'

import { autoOf, parseAccountDetails } from '../../../../hooks/cswap.ts'
import type { AccountDetail, StarAuto } from '../../../../types/index.d.ts'
import { claudeConfigDir, crontab, cswapProcs, listAccounts, menubarSettings } from './read.ts'
import type { ModuleApi } from './types.ts'

export type AccountsState = { installed: boolean; auto: StarAuto; fetchedAt: string | null; problem: string; accounts: AccountDetail[] }
export const EVERY_MS = 60_000
export const CSWAP_TIMEOUT_MS = 20_000
export type AccountsOptions = { everyMs?: number; timeoutMs?: number; now?: () => Date }
export type Accounts = { everyMs: number; read(): Promise<AccountsState>; start(): void; stop(): void }

const NOT_INSTALLED: AccountsState = { installed: false, auto: { state: 'off', via: '' }, fetchedAt: null, problem: '', accounts: [] }

const errorText = (err: unknown): string => (err instanceof Error ? err.message : String(err))

export function createAccounts(api: ModuleApi, opts: AccountsOptions = {}): Accounts {
  const everyMs = opts.everyMs ?? EVERY_MS
  const timeoutMs = opts.timeoutMs ?? CSWAP_TIMEOUT_MS
  const now = opts.now ?? ((): Date => new Date())
  let last: AccountsState | undefined
  let lastKey = ''
  let running: Promise<AccountsState> | undefined
  let timer: ReturnType<typeof setInterval> | undefined

  // The server's emit may throw. Nothing a timer or a route started may end the server.
  const emitChange = (): void => {
    try {
      api.emit({ type: 'change', what: 'accounts' })
    } catch (err) {
      console.error(`accounts: emit failed: ${errorText(err)}`)
    }
  }

  // What a change is: the reading without fetchedAt and without each account's usageAgeSeconds.
  const keyOf = (s: AccountsState): string =>
    JSON.stringify({ ...s, fetchedAt: null, accounts: s.accounts.map(a => ({ ...a, usageAgeSeconds: null })) })

  async function reading(): Promise<AccountsState> {
    const home = os.homedir()
    const configDir = claudeConfigDir(home)
    const listed = await listAccounts(home, configDir, timeoutMs)
    if (listed === undefined) return NOT_INSTALLED
    const [procs, cron] = await Promise.all([cswapProcs().catch(() => []), crontab().catch(() => '')])
    const auto = autoOf(procs, menubarSettings(home), cron, configDir, home)
    const parsed = parseAccountDetails(listed.stdout)
    if (parsed.ok && !listed.timedOut) {
      return { installed: true, auto, fetchedAt: now().toISOString(), problem: '', accounts: parsed.value }
    }
    const problem = listed.timedOut ? `cswap list --json timed out after ${timeoutMs / 1000}s` : parsed.ok ? '' : parsed.why
    return { installed: true, auto, fetchedAt: last?.fetchedAt ?? null, problem, accounts: last?.accounts ?? [] }
  }

  function read(): Promise<AccountsState> {
    running ??= reading()
      .catch((err: unknown): AccountsState => ({ ...(last ?? NOT_INSTALLED), installed: true, problem: errorText(err) }))
      .then(state => {
        last = state
        const key = keyOf(state)
        if (key !== lastKey) {
          lastKey = key
          emitChange()
        }
        return state
      })
      .finally(() => {
        running = undefined
      })
    return running
  }

  api.route('GET', '/api/accounts', async () => ({ status: 200, json: last ?? (await read()) }))

  return {
    everyMs,
    read,
    start() {
      void read()
      timer = setInterval(() => void read(), everyMs)
      timer.unref()
    },
    stop() {
      if (timer) clearInterval(timer)
      timer = undefined
    },
  }
}
