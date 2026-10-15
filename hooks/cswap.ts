// Pure readers for claude-swap (`cswap`), the account switcher: its `list --json` payload
// (schemaVersion 1, the contract its README documents for scripts) and whether its auto-switch
// is running for this session's Claude login, from the processes, the menu bar's own settings and
// the crontab. No `$` here: register.tsx runs the commands and hands their text in.

import type { StarAccount, StarAuto } from '../types'
import type { Parsed } from './star'

type Window = { pct?: unknown; countdown?: unknown } | null | undefined
type Usage = { fiveHour?: Window; sevenDay?: Window } | null | undefined
type Row = {
  number?: unknown
  email?: unknown
  alias?: unknown
  active?: unknown
  disabled?: unknown
  usageStatus?: unknown
  usage?: Usage
  lastGoodUsage?: Usage
}

/** At or past this share of a window, an account shows when that window resets. */
export const NEAR_LIMIT = 90

const pctOf = (w: Window): number | null =>
  w && typeof w.pct === 'number' && Number.isFinite(w.pct) ? Math.round(w.pct) : null

function accountOf(row: Row): StarAccount {
  const number = typeof row.number === 'number' ? row.number : 0
  const email = typeof row.email === 'string' ? row.email : ''
  const alias = typeof row.alias === 'string' && row.alias ? row.alias : email.split('@')[0] || `#${number}`
  // Last-known numbers stand in while a fresh reading is unavailable (cswap's own stale-on-error).
  const usage = row.usage ?? row.lastGoodUsage ?? null
  const fiveHour = pctOf(usage?.fiveHour)
  const sevenDay = pctOf(usage?.sevenDay)
  // The window that keeps the account out is the weekly one when both are spent.
  const spent = [usage?.sevenDay, usage?.fiveHour].find(w => (pctOf(w) ?? 0) >= NEAR_LIMIT)
  const status = typeof row.usageStatus === 'string' ? row.usageStatus : 'unavailable'
  return {
    number,
    alias,
    isActive: row.active === true,
    isDisabled: row.disabled === true,
    fiveHour,
    sevenDay,
    resets: spent && typeof spent.countdown === 'string' ? spent.countdown : null,
    isStale: !row.usage && Boolean(row.lastGoodUsage),
    status: status === 'ok' ? '' : status.replace(/_/g, ' '),
  }
}

/** `cswap list --json`, the active account first, then by slot number. */
export function parseAccounts(text: string): Parsed<StarAccount[]> {
  let data: unknown
  try {
    data = JSON.parse(text)
  } catch {
    return { ok: false, why: 'cswap list --json printed no JSON' }
  }
  if (typeof data !== 'object' || data === null) return { ok: false, why: 'cswap list --json printed no object' }
  const d = data as { schemaVersion?: unknown; accounts?: unknown; error?: { message?: unknown } | null }
  if (d.error) return { ok: false, why: `cswap: ${typeof d.error.message === 'string' ? d.error.message : 'error'}` }
  if (d.schemaVersion !== 1 || !Array.isArray(d.accounts)) return { ok: false, why: 'cswap list --json: an unknown schema' }
  const accounts = (d.accounts as Row[]).map(accountOf)
  accounts.sort((a, b) => Number(b.isActive) - Number(a.isActive) || a.number - b.number)
  return { ok: true, value: accounts }
}

// The cswap program itself, run directly or by Python, as `ps -Ao command` prints it, so a shell
// or a grep that only mentions it does not count: `cswap auto` is the foreground loop (cswap's
// README, "Automatic switching"), `cswap menubar` the menu bar app.
const PROGRAM = String.raw`^\s*(?:\S*[Pp]ython[\d.]*\s+)?(?:\S*/)?cswap\s+`
const LOOP = new RegExp(`${PROGRAM}auto(?:\\s|$)`)
const MENUBAR = new RegExp(`${PROGRAM}menubar(?:\\s|$)`)
const ONE_SHOT = /--(?:install-service|uninstall-service|service-status)\b/
// A crontab line runs it after the schedule's five fields.
const CRON = /(?:^|[\s/])cswap\s+auto(?:\s|$)/
const CONFIG_DIR = /(?:^|\s)CLAUDE_CONFIG_DIR=(\S+)/

/** A running process: its command line, and the CLAUDE_CONFIG_DIR it runs under ('' when unset). */
export type Proc = { command: string; configDir: string }

/** Whether a `ps` command line is cswap's auto loop or its menu bar: the processes whose login matters. */
export const isCswapProc = (command: string): boolean => LOOP.test(command) || MENUBAR.test(command)

/** CLAUDE_CONFIG_DIR from a process's environment as `ps eww` prints it after the command; '' when unset. */
export const configDirOf = (withEnv: string): string => CONFIG_DIR.exec(withEnv)?.[1] ?? ''

/** A Claude config folder in one spelling: unset is ~/.claude (Claude Code's own default), ~ expanded. */
export function normDir(dir: string, home: string): string {
  const d = dir.replace(/^["']|["']$/g, '') || `${home}/.claude`
  return d.replace(/^(?:~|\$HOME|\$\{HOME\})(?=\/|$)/, home).replace(/\/+$/, '')
}

/**
 * Whether cswap's auto-switch runs for this session's Claude login (`mine`, its CLAUDE_CONFIG_DIR),
 * and how: a `cswap auto` loop, the menu bar app with its "Auto-switch accounts" toggle on, or a
 * cron entry running `cswap auto --once`. Each switches only the login it runs under, so one for
 * another config folder does not count. The dashboard's watch page cannot be seen from outside: it
 * opens in dry run and goes live only inside it.
 */
export function autoOf(procs: readonly Proc[], menubarSettings: string | null, crontab: string, mine: string, home: string): StarAuto {
  const here = (dir: string): boolean => normDir(dir, home) === normDir(mine, home)
  const loops = procs.filter(p => LOOP.test(p.command) && !/--once\b/.test(p.command) && here(p.configDir))
  if (loops.some(p => !/--dry-run\b/.test(p.command))) return { state: 'on', via: 'cswap auto' }
  const isMenubar = procs.some(p => MENUBAR.test(p.command) && !ONE_SHOT.test(p.command) && here(p.configDir))
  if (isMenubar && menubarSettings) {
    try {
      if ((JSON.parse(menubarSettings) as { auto_switch_enabled?: unknown }).auto_switch_enabled === true) {
        return { state: 'on', via: 'menu bar' }
      }
    } catch {
      // unreadable settings: the menu bar's toggle is unknown, so it does not count
    }
  }
  // A crontab sets a variable on a line of its own for the jobs under it, or inline on the job.
  let cronDir = ''
  for (const line of crontab.split('\n')) {
    const text = line.trim()
    if (!text || text.startsWith('#')) continue
    const variable = /^CLAUDE_CONFIG_DIR\s*=\s*(.*)$/.exec(text)
    if (variable) {
      cronDir = (variable[1] ?? '').trim()
      continue
    }
    if (CRON.test(text) && /--once\b/.test(text) && !/--dry-run\b/.test(text) && here(configDirOf(text) || cronDir)) {
      return { state: 'on', via: 'cron' }
    }
  }
  if (loops.length) return { state: 'dry run', via: 'cswap auto' }
  return { state: 'off', via: '' }
}
