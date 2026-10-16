// The readers that run commands for the accounts module. The mod's band runs the same commands with
// the same argv behind the engine's `$` (hooks/register.tsx); the server has no engine, so these use
// node:child_process and hand the text to the same pure functions in hooks/cswap.ts.
import { execFile } from 'node:child_process'
import { readFileSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { configDirOf, isCswapProc, normDir } from '../../../../hooks/cswap.ts'
import type { Proc } from '../../../../hooks/cswap.ts'

const MAX_BUFFER = 8 * 1024 * 1024
const OTHER_MS = 10_000
const PS_LINE = /^\s*(\d+)\s+(.*)$/

/** JUEL_DIR when it is set and not empty (master plan I-1), else ~/.juel from $HOME. */
export function juelDir(): string {
  const set = process.env.JUEL_DIR
  return set ? path.resolve(set) : path.join(os.homedir(), '.juel')
}

/**
 * The Claude config folder STAR's login lives in: claudeConfigDir from dashboard.json when it is a
 * non-empty string, else this server's CLAUDE_CONFIG_DIR, else ~/.claude. Read at every reading.
 */
export function claudeConfigDir(home: string): string {
  let chosen = ''
  try {
    const data = JSON.parse(readFileSync(path.join(juelDir(), 'dashboard.json'), 'utf8')) as { claudeConfigDir?: unknown } | null
    if (typeof data?.claudeConfigDir === 'string') chosen = data.claudeConfigDir
  } catch {
    // no dashboard.json yet, or not JSON: the environment decides
  }
  return normDir(chosen || process.env.CLAUDE_CONFIG_DIR || '', home)
}

type Done = { code: number | string | null; stdout: string; timedOut: boolean }

function exec(cmd: string, args: string[], timeout: number, env?: NodeJS.ProcessEnv): Promise<Done> {
  return new Promise(resolve => {
    execFile(cmd, args, { timeout, maxBuffer: MAX_BUFFER, env: env ?? process.env }, (err, stdout) => {
      const e = err as (NodeJS.ErrnoException & { killed?: boolean }) | null
      resolve({ code: e ? (e.code ?? -1) : 0, stdout: String(stdout ?? ''), timedOut: Boolean(e?.killed) })
    })
  })
}

/**
 * `cswap list --json`, first as `cswap` from PATH, then <home>/.local/bin/cswap, under the given
 * Claude config folder. A candidate that cannot be found (ENOENT, or exit 127) is skipped;
 * undefined when neither runs. Never any other cswap argument.
 */
export async function listAccounts(home: string, configDir: string, timeoutMs: number): Promise<{ stdout: string; timedOut: boolean } | undefined> {
  const env = { ...process.env, CLAUDE_CONFIG_DIR: configDir }
  for (const bin of ['cswap', ...(home ? [path.join(home, '.local', 'bin', 'cswap')] : [])]) {
    const done = await exec(bin, ['list', '--json'], timeoutMs, env)
    if (done.code === 'ENOENT' || done.code === 127) continue
    return { stdout: done.stdout, timedOut: done.timedOut }
  }
  return undefined
}

/** The cswap processes (auto loops, the menu bar), each with the Claude config it runs under. */
export async function cswapProcs(): Promise<Proc[]> {
  const all = await exec('ps', ['-Ao', 'pid=,command='], OTHER_MS)
  const found = all.stdout
    .split('\n')
    .map(line => PS_LINE.exec(line))
    .filter((m): m is RegExpExecArray => m !== null && isCswapProc(m[2] ?? ''))
  if (!found.length) return []
  const withEnv = await exec('ps', ['eww', '-o', 'pid=,command=', '-p', found.map(m => m[1] ?? '').join(',')], OTHER_MS)
  const dirs = new Map<string, string>()
  for (const line of withEnv.stdout.split('\n')) {
    const m = PS_LINE.exec(line)
    if (m) dirs.set(m[1] ?? '', configDirOf(m[2] ?? ''))
  }
  return found.map(m => ({ command: m[2] ?? '', configDir: dirs.get(m[1] ?? '') ?? '' }))
}

/** `crontab -l`; '' unless it exits 0. */
export async function crontab(): Promise<string> {
  const done = await exec('crontab', ['-l'], OTHER_MS)
  return done.code === 0 ? done.stdout : ''
}

/** The menu bar's own settings, where its auto-switch toggle lives (macOS, then Linux). */
export function menubarSettings(home: string): string | null {
  if (!home) return null
  const xdg = process.env.XDG_DATA_HOME || path.join(home, '.local', 'share')
  for (const dir of [path.join(home, '.claude-swap-backup'), path.join(xdg, 'claude-swap')]) {
    try {
      return readFileSync(path.join(dir, 'menubar_settings.json'), 'utf8')
    } catch {
      // not there: try the next folder
    }
  }
  return null
}
