import assert from 'node:assert/strict'
import { chmod, mkdir, mkdtemp, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { afterEach, test } from 'node:test'

import { CSWAP_FULL } from './fixtures.ts'
import { createAccounts } from './accounts.ts'
import type { AccountsState } from './accounts.ts'
import { register } from './index.ts'
import type { ModuleApi, Req, Res } from './types.ts'

const HERE = import.meta.dirname
const NOW = new Date('2026-10-17T08:00:00Z')
const SAVED = { HOME: process.env.HOME, PATH: process.env.PATH, JUEL_DIR: process.env.JUEL_DIR, FAKE_DIR: process.env.FAKE_DIR, CLAUDE_CONFIG_DIR: process.env.CLAUDE_CONFIG_DIR, XDG_DATA_HOME: process.env.XDG_DATA_HOME }
const roots: string[] = []

afterEach(async () => {
  for (const [k, v] of Object.entries(SAVED)) {
    if (v === undefined) delete process.env[k]
    else process.env[k] = v
  }
  for (const r of roots.splice(0)) await rm(r, { recursive: true, force: true })
})

type World = { root: string; home: string; fakes: string; juel: string; configDir: string }

async function script(path: string, body: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  await writeFile(path, `#!/bin/sh\n${body}\n`)
  await chmod(path, 0o755)
}

/** A temporary HOME, PATH and JUEL_DIR with fake cswap, ps and crontab: nothing here reaches the real ones. */
async function world(where: 'path' | 'local' | 'none' = 'path'): Promise<World> {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'star-accounts-')))
  roots.push(root)
  const w = { root, home: join(root, 'home'), fakes: join(root, 'fakes'), juel: join(root, 'juel'), configDir: join(root, 'home', '.claude-star') }
  for (const d of [w.home, join(root, 'bin'), w.fakes, w.juel]) await mkdir(d, { recursive: true })
  process.env.HOME = w.home
  process.env.PATH = `${join(root, 'bin')}:/usr/bin:/bin`
  process.env.JUEL_DIR = w.juel
  process.env.FAKE_DIR = w.fakes
  delete process.env.CLAUDE_CONFIG_DIR
  delete process.env.XDG_DATA_HOME
  await writeFile(join(w.fakes, 'cswap.out'), CSWAP_FULL)
  await writeFile(join(w.juel, 'dashboard.json'), JSON.stringify({ claudeConfigDir: '~/.claude-star' }))
  const cswap = [
    'echo "$*|${CLAUDE_CONFIG_DIR-}" >> "$FAKE_DIR/cswap.calls"',
    '[ -f "$FAKE_DIR/cswap.sleep" ] && exec sleep "$(cat "$FAKE_DIR/cswap.sleep")"',
    'cat "$FAKE_DIR/cswap.out"',
    'exit "$(cat "$FAKE_DIR/cswap.exit" 2>/dev/null || echo 0)"',
  ].join('\n')
  if (where === 'path') await script(join(root, 'bin', 'cswap'), cswap)
  if (where === 'local') await script(join(w.home, '.local', 'bin', 'cswap'), cswap)
  await script(join(root, 'bin', 'ps'), 'echo "$*" >> "$FAKE_DIR/ps.calls"\nif [ "$1" = eww ]; then cat "$FAKE_DIR/ps-env.out" 2>/dev/null; else cat "$FAKE_DIR/ps.out" 2>/dev/null; fi\nexit 0')
  await script(join(root, 'bin', 'crontab'), 'cat "$FAKE_DIR/crontab.out" 2>/dev/null || exit 1')
  return w
}

const calls = async (w: World, name: string): Promise<string[]> =>
  (await readFile(join(w.fakes, `${name}.calls`), 'utf8').catch(() => '')).split('\n').filter(Boolean)

function stub(): { api: ModuleApi; routes: string[]; events: unknown[]; logs: string[]; get(path: string): Promise<Res> } {
  const routes: string[] = []
  const handlers = new Map<string, (req: Req) => Promise<Res>>()
  const events: unknown[] = []
  const logs: string[] = []
  const api: ModuleApi = {
    route: (method, path, handler) => {
      routes.push(`${method} ${path}`)
      handlers.set(`${method} ${path}`, handler)
    },
    emit: e => void events.push(e),
    projects: () => [],
    nudge: async () => false,
    log: line => void logs.push(line),
  }
  return { api, routes, events, logs, get: path => handlers.get(`GET ${path}`)?.({ params: {}, query: new URLSearchParams(), body: undefined }) ?? Promise.reject(new Error('no route')) }
}

async function until<T>(probe: () => T | Promise<T>, ms = 5000): Promise<T> {
  const end = Date.now() + ms
  for (;;) {
    const value = await probe()
    if (value) return value
    if (Date.now() > end) throw new Error('timed out waiting')
    await new Promise(resolve => setTimeout(resolve, 10))
  }
}

test('register adds GET /api/accounts, reads cswap at once, and then every 60 s', async () => {
  const w = await world()
  const s = stub()
  register(s.api)
  assert.deepEqual(s.routes, ['GET /api/accounts'])
  await until(() => s.events.length === 1)
  assert.equal((await calls(w, 'cswap')).length, 1)
  assert.equal(createAccounts(stub().api).everyMs, 60_000)
})

test("a reading runs cswap list --json under STAR's Claude login, and answers AccountsState field for field", async () => {
  const w = await world()
  const s = stub()
  createAccounts(s.api, { now: () => NOW })
  const state = (await s.get('/api/accounts')).json as AccountsState
  assert.deepEqual(await calls(w, 'cswap'), [`list --json|${w.configDir}`])
  assert.deepEqual(Object.keys(state).sort(), ['accounts', 'auto', 'fetchedAt', 'installed', 'problem'])
  assert.deepEqual([state.installed, state.auto, state.fetchedAt, state.problem], [true, { state: 'off', via: '' }, '2026-10-17T08:00:00.000Z', ''])
  assert.deepEqual(state.accounts.map(a => a.alias), ['personal', 'sphere', 'carol', 'old'])
  assert.deepEqual(Object.keys(state.accounts[0] ?? {}).sort(), ['alias', 'email', 'fiveHour', 'isActive', 'isDisabled', 'isStale',
    'loginExpiresAt', 'number', 'scoped', 'sevenDay', 'status', 'usageAgeSeconds'])
  assert.deepEqual(Object.keys(state.accounts[0]?.sevenDay ?? {}).sort(), ['aheadOfPace', 'countdown', 'expectedPct',
    'projectedExhaustionAt', 'resetsAt', 'usedPct', 'willLastToReset'])
})

test("without claudeConfigDir it is the server's CLAUDE_CONFIG_DIR, then ~/.claude; with JUEL_DIR unset, ~/.juel/dashboard.json", async () => {
  const w = await world()
  const seen = async (): Promise<string> => {
    await rm(join(w.fakes, 'cswap.calls'), { force: true })
    await createAccounts(stub().api).read()
    return (await calls(w, 'cswap'))[0] ?? ''
  }
  delete process.env.JUEL_DIR
  await mkdir(join(w.home, '.juel'))
  await writeFile(join(w.home, '.juel', 'dashboard.json'), JSON.stringify({ claudeConfigDir: '/Users/me/.claude-sphere' }))
  assert.equal(await seen(), 'list --json|/Users/me/.claude-sphere')
  await writeFile(join(w.home, '.juel', 'dashboard.json'), JSON.stringify({ slack: {} }))
  process.env.CLAUDE_CONFIG_DIR = '/Users/me/.claude-env'
  assert.equal(await seen(), 'list --json|/Users/me/.claude-env')
  delete process.env.CLAUDE_CONFIG_DIR
  assert.equal(await seen(), `list --json|${w.home}/.claude`)
})

test('cswap from ~/.local/bin is found; without it anywhere: installed false and nothing else runs', async () => {
  const local = await world('local')
  const s = stub()
  const state = await createAccounts(s.api).read()
  assert.equal(state.installed, true)
  assert.equal((await calls(local, 'cswap')).length, 1)

  const none = await world('none')
  const t = stub()
  const absent = (await (createAccounts(t.api), t.get('/api/accounts'))).json
  assert.deepEqual(absent, { installed: false, auto: { state: 'off', via: '' }, fetchedAt: null, problem: '', accounts: [] })
  assert.deepEqual(await calls(none, 'ps'), [])
})

test('a failed read keeps the last accounts and fetchedAt, and says why', async () => {
  const w = await world()
  const s = stub()
  let at = NOW
  const a = createAccounts(s.api, { now: () => at, timeoutMs: 1500 })
  await a.read()
  at = new Date('2026-10-17T08:01:00Z')
  await writeFile(join(w.fakes, 'cswap.out'), 'not json')
  let state = await a.read()
  assert.deepEqual([state.problem, state.fetchedAt, state.accounts.length], ['cswap list --json printed no JSON', '2026-10-17T08:00:00.000Z', 4])
  await writeFile(join(w.fakes, 'cswap.out'), JSON.stringify({ schemaVersion: 1, error: { message: 'no accounts file' } }))
  await writeFile(join(w.fakes, 'cswap.exit'), '1')
  state = await a.read()
  assert.equal(state.problem, 'cswap: no accounts file')
  await writeFile(join(w.fakes, 'cswap.sleep'), '5')
  state = await a.read()
  assert.deepEqual([state.problem, state.accounts.length], ['cswap list --json timed out after 1.5s', 4])
})

test('a reading that changed emits one change event; a new usageAgeSeconds alone does not', async () => {
  const w = await world()
  const s = stub()
  const a = createAccounts(s.api, { now: () => NOW })
  await a.read()
  await a.read()
  assert.deepEqual(s.events, [{ type: 'change', what: 'accounts' }])
  const full = JSON.parse(CSWAP_FULL)
  full.accounts[1].usageAgeSeconds = 500
  await writeFile(join(w.fakes, 'cswap.out'), JSON.stringify(full))
  await a.read()
  assert.equal(s.events.length, 1)
  full.accounts[1].usage.sevenDay.pct = 70
  await writeFile(join(w.fakes, 'cswap.out'), JSON.stringify(full))
  await a.read()
  assert.deepEqual(s.events, [{ type: 'change', what: 'accounts' }, { type: 'change', what: 'accounts' }])
})

test("auto-switch is autoOf over ps, the crontab and the menu bar, for STAR's login only", async () => {
  const w = await world()
  const auto = async (): Promise<unknown> => (await createAccounts(stub().api).read()).auto
  const loop = '/Users/me/.local/bin/cswap auto --threshold 80'
  await writeFile(join(w.fakes, 'ps.out'), `101 ${loop}\n`)
  await writeFile(join(w.fakes, 'ps-env.out'), `101 ${loop} CLAUDE_CONFIG_DIR=${w.configDir}\n`)
  assert.deepEqual(await auto(), { state: 'on', via: 'cswap auto' })

  await writeFile(join(w.fakes, 'ps-env.out'), `101 ${loop} CLAUDE_CONFIG_DIR=/Users/me/.claude-other\n`)
  await writeFile(join(w.fakes, 'crontab.out'), `CLAUDE_CONFIG_DIR=${w.configDir}\n*/5 * * * * cswap auto --once\n`)
  assert.deepEqual(await auto(), { state: 'on', via: 'cron' })

  await rm(join(w.fakes, 'crontab.out'))
  await writeFile(join(w.fakes, 'ps.out'), '103 /Users/me/.local/bin/cswap menubar\n')
  await writeFile(join(w.fakes, 'ps-env.out'), `103 /Users/me/.local/bin/cswap menubar CLAUDE_CONFIG_DIR=${w.configDir}\n`)
  await mkdir(join(w.home, '.claude-swap-backup'))
  await writeFile(join(w.home, '.claude-swap-backup', 'menubar_settings.json'), '{"auto_switch_enabled": true}')
  assert.deepEqual(await auto(), { state: 'on', via: 'menu bar' })
})

test('only cswap list --json is ever run, and a GET after the first reading reads nothing more', async () => {
  const w = await world()
  const s = stub()
  const a = createAccounts(s.api)
  await s.get('/api/accounts')
  await s.get('/api/accounts')
  assert.equal((await calls(w, 'cswap')).length, 1)
  await a.read()
  await a.read()
  const all = await calls(w, 'cswap')
  assert.equal(all.length, 3)
  for (const line of all) assert.ok(line.startsWith('list --json|'), line)
})

test('the module runs on Node alone: node: builtins, its own files, hooks/cswap.ts and types/index.d.ts', async () => {
  const files = (await readdir(HERE)).filter(name => name.endsWith('.ts') && !name.endsWith('.test.ts') && name !== 'fixtures.ts')
  assert.deepEqual(files.sort(), ['accounts.ts', 'index.ts', 'read.ts', 'types.ts'])
  const network = ['node:http', 'node:https', 'node:net', 'node:dgram', 'node:tls']
  for (const file of files) {
    const code = await readFile(join(HERE, file), 'utf8')
    for (const m of code.matchAll(/^import\s[\s\S]*?\sfrom\s+'([^']+)'/gm)) {
      const from = m[1] ?? ''
      const isTypes = from === '../../../../types/index.d.ts'
      const ok = from.startsWith('./') || from === '../../../../hooks/cswap.ts' || isTypes || (from.startsWith('node:') && !network.includes(from))
      assert.ok(ok, `${file} imports ${from}`)
      if (isTypes) assert.ok(/^import type\s/.test(m[0]), `${file} must import types with import type`)
    }
    assert.ok(!/\bfetch\(/.test(code), `${file} calls fetch`)
  }
  await assert.rejects(readFile(join(HERE, 'package.json')))
})
