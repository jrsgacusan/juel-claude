// Test scaffolding for the briefing module: a temp repo and STAR folder, fake `claude` and `gh`
// binaries first on PATH (PATH is only the fake bin, /usr/bin and /bin, so the real ones are never
// reached), and a stub ModuleApi that records routes, events, nudges and log lines.
import { appendFile, chmod, mkdir, mkdtemp, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import type { ModuleApi, Project, Req, Res } from './types.ts'

/** What one fake call prints and how it ends. `wait` holds it, after printing, until release(). */
export type Scenario = { lines?: unknown[]; stdout?: string; stderr?: string; exit?: number; wait?: boolean }
export type Call = { bin: string; argv: string[]; cwd: string; stdin: string }
export type World = { root: string; repo: string; home: string; bin: string; fakes: string; project: Project }

// One fake for both names: it records the call, then plays the next scenario written for its name.
const FAKE = String.raw`
const fs = require('node:fs')
const path = require('node:path')
const name = path.basename(process.argv[1])
const dir = process.env.FAKE_DIR
let stdin = ''
try { stdin = fs.readFileSync(0, 'utf8') } catch {}
fs.appendFileSync(path.join(dir, 'calls.jsonl'), JSON.stringify({ bin: name, argv: process.argv.slice(2), cwd: process.cwd(), stdin }) + '\n')
const counter = path.join(dir, name + '.count')
const n = fs.existsSync(counter) ? Number(fs.readFileSync(counter, 'utf8')) : 0
fs.writeFileSync(counter, String(n + 1))
const list = JSON.parse(fs.readFileSync(path.join(dir, name + '.json'), 'utf8'))
const s = list[Math.min(n, list.length - 1)]
process.stdout.write((s.lines || []).map(l => JSON.stringify(l) + '\n').join('') + (s.stdout || ''))
process.stderr.write(s.stderr || '')
const end = () => { process.exitCode = s.exit || 0 }
if (s.wait) {
  // Released by the test. A fake left waiting (a regression, or its folder already removed) gives
  // up after 10 s with exit 99, so the suite fails instead of hanging and no process outlives it.
  const giveUp = Date.now() + 10000
  const tick = setInterval(() => {
    if (fs.existsSync(path.join(dir, 'release'))) { clearInterval(tick); end() }
    else if (Date.now() > giveUp) { clearInterval(tick); process.exitCode = 99 }
  }, 10)
} else end()
`

export async function world(name = 'proj'): Promise<World> {
  // realpath: macOS tmpdir is a symlink, and a child's cwd comes back resolved
  const root = await realpath(await mkdtemp(join(tmpdir(), 'briefing-')))
  const repo = join(root, 'repo')
  const home = join(root, 'star')
  const bin = join(root, 'bin')
  const fakes = join(root, 'fakes')
  for (const dir of [repo, home, bin, fakes]) await mkdir(dir)
  for (const fake of ['claude', 'gh']) {
    await writeFile(join(bin, fake), `#!${process.execPath}\n${FAKE}`)
    await chmod(join(bin, fake), 0o755)
  }
  process.env.PATH = `${bin}:/usr/bin:/bin`
  process.env.FAKE_DIR = fakes
  return { root, repo, home, bin, fakes, project: { name, repo, home, terminal: null, state: 'running' } }
}

export async function cleanup(w: World): Promise<void> {
  await release(w) // let a fake still held end before its folder goes
  await new Promise(resolve => setTimeout(resolve, 30))
  await rm(w.root, { recursive: true, force: true })
}

/** The scenarios the next calls of `bin` play, in order; the last one repeats. */
export async function play(w: World, bin: 'claude' | 'gh', scenarios: Scenario[]): Promise<void> {
  await writeFile(join(w.fakes, `${bin}.json`), JSON.stringify(scenarios))
  await rm(join(w.fakes, `${bin}.count`), { force: true })
}

export async function release(w: World): Promise<void> {
  await writeFile(join(w.fakes, 'release'), '')
}

export async function calls(w: World, bin?: string): Promise<Call[]> {
  let text = ''
  try {
    text = await readFile(join(w.fakes, 'calls.jsonl'), 'utf8')
  } catch {
    return []
  }
  return text.split('\n').filter(Boolean).map(line => JSON.parse(line) as Call).filter(call => !bin || call.bin === bin)
}

/** Polls until probe gives a truthy value. */
export async function until<T>(probe: () => T | Promise<T>, ms = 5000): Promise<NonNullable<T>> {
  const end = Date.now() + ms
  for (;;) {
    const value = await probe()
    if (value) return value as NonNullable<T>
    if (Date.now() > end) throw new Error('timed out waiting')
    await new Promise(resolve => setTimeout(resolve, 10))
  }
}

/** STAR's ledger table as skills/star/ledger.sh save() writes it. */
export function ledgerText(rows: { item: string; ref: string; state: string }[]): string {
  const header = '| item | ref | project | worktree | state | stage | round | task | dispatch | restarts | pr | head | cursor | verify | counters | updated |\n'
  const separator = '|' + '---|'.repeat(16) + '\n'
  const lines = rows.map(({ item, ref, state }) => `| ${item} | ${ref} | proj | - | ${state} | brief | 0 | - | - | 0 | - | - | - | - | - | 2026-10-16T00:00:00Z |\n`)
  return header + separator + lines.join('')
}

/** Ingests inbox files the way STAR's Inbox step does, appending ledger rows then deleting files. */
export async function ingest(home: string, state = 'done'): Promise<string[]> {
  const dir = join(home, 'inbox')
  let names: string[]
  try {
    names = (await readdir(dir)).filter(name => name.endsWith('.md')).sort()
  } catch {
    return []
  }
  const ledger = join(home, 'ledger.md')
  try {
    await readFile(ledger, 'utf8')
  } catch (err) {
    if ((err as { code?: string }).code !== 'ENOENT') throw err
    await writeFile(ledger, ledgerText([]))
  }
  const refs: string[] = []
  for (const name of names) {
    const path = join(dir, name)
    const text = await readFile(path, 'utf8')
    const fileRefs = text.split('\n').filter(line => line.startsWith('- ')).map(line => line.slice(2))
    for (const ref of fileRefs) {
      refs.push(ref)
      const n = refs.length
      await appendFile(ledger, ledgerText([{ item: `i${n}`, ref, state }]).split('\n').slice(2).join('\n'))
    }
    await rm(path)
  }
  return refs
}

// The stream-json fields the module reads, from lines the real CLI printed (claude 2.1.301, checked 2026-10-16).
export const hook = { type: 'system', subtype: 'hook_started' }
export const init = (session: string, tools: string[] = ['Glob', 'Grep', 'Read']) => ({ type: 'system', subtype: 'init', session_id: session, tools, mcp_servers: [] })
export const say = (text: string) => ({ type: 'assistant', message: { content: [{ type: 'text', text }] } })
export const reads = (...paths: string[]) => ({ type: 'assistant', message: { content: paths.map(file_path => ({ type: 'tool_use', name: 'Read', input: { file_path } })) } })
export const done = (text: string, isError = false) => ({ type: 'result', subtype: isError ? 'error_during_execution' : 'success', is_error: isError, result: text })
export const block = (ticket: unknown): string => '```ticket\n' + JSON.stringify(ticket) + '\n```'

export type Stub = {
  api: ModuleApi
  routes: string[]
  events: Record<string, unknown>[]
  nudges: string[]
  logs: string[]
  call: (method: 'GET' | 'POST' | 'PUT', url: string, body?: unknown) => Promise<Res>
}

function match(pattern: string, path: string): Record<string, string> | null {
  const want = pattern.split('/')
  const got = path.split('/')
  if (want.length !== got.length) return null
  const params: Record<string, string> = {}
  for (let i = 0; i < want.length; i++) {
    if (want[i].startsWith(':')) params[want[i].slice(1)] = decodeURIComponent(got[i])
    else if (want[i] !== got[i]) return null
  }
  return params
}

/** `emitThrows`: emit records the event, then throws. `nudge`: what nudge answers (default true). */
export type StubOptions = { emitThrows?: boolean; nudge?: (project: string) => Promise<boolean> }

/** A ModuleApi that records everything, and `call` to run a registered handler as the server would. */
export function stub(projects: Project[], options: StubOptions = {}): Stub {
  const handlers: { method: string; path: string; handler: (req: Req) => Promise<Res> }[] = []
  const s: Stub = {
    routes: [],
    events: [],
    nudges: [],
    logs: [],
    api: {
      route(method, path, handler) {
        s.routes.push(`${method} ${path}`)
        handlers.push({ method, path, handler })
      },
      emit(event) {
        s.events.push(event)
        if (options.emitThrows) throw new Error('emit is down')
      },
      projects: () => projects,
      async nudge(project) {
        s.nudges.push(project)
        return options.nudge ? options.nudge(project) : true
      },
      log(line) {
        s.logs.push(line)
      },
    },
    async call(method, url, body) {
      const [pathname, search = ''] = url.split('?')
      for (const route of handlers) {
        const params = route.method === method ? match(route.path, pathname) : null
        if (params) return route.handler({ params, query: new URLSearchParams(search), body })
      }
      throw new Error(`no route for ${method} ${url}`)
    },
  }
  return s
}
