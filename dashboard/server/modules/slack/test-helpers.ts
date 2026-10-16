// Test scaffolding for the Slack module: HOME in a temp folder (so ~/.juel/slack/ is the test's
// own), a fake `claude` first on PATH (PATH is only the fake's folder, /usr/bin and /bin, so the
// real CLI is never reached), STAR project folders, and a stub ModuleApi that records routes,
// events, nudges and log lines.
import { execFileSync } from 'node:child_process'
import { chmod, mkdir, mkdtemp, readdir, readFile, realpath, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import type { Message } from './state.ts'
import type { ModuleApi, Project, Req, Res } from './types.ts'

/** What one fake run prints and how it ends. `wait` holds it, printing nothing, until release(). */
export type Scenario = { stdout?: string; stderr?: string; exit?: number; wait?: boolean }
export type Call = { argv: string[]; cwd: string; stdin: string }
export type World = { root: string; home: string; bin: string; fakes: string }

// The fake records each call, then plays the next scenario; the last one repeats.
const FAKE = String.raw`
const fs = require('node:fs')
const path = require('node:path')
const dir = process.env.FAKE_DIR
let stdin = ''
try { stdin = fs.readFileSync(0, 'utf8') } catch {}
fs.appendFileSync(path.join(dir, 'calls.jsonl'), JSON.stringify({ argv: process.argv.slice(2), cwd: process.cwd(), stdin }) + '\n')
const counter = path.join(dir, 'count')
const n = fs.existsSync(counter) ? Number(fs.readFileSync(counter, 'utf8')) : 0
fs.writeFileSync(counter, String(n + 1))
const list = JSON.parse(fs.readFileSync(path.join(dir, 'scenarios.json'), 'utf8'))
const s = list[Math.min(n, list.length - 1)]
const end = () => {
  process.stdout.write(s.stdout || '')
  process.stderr.write(s.stderr || '')
  process.exitCode = s.exit || 0
}
if (s.wait) {
  // Released by the test. A fake left waiting gives up after 10 s with exit 99, so a regression
  // fails the suite instead of hanging it.
  const giveUp = Date.now() + 10000
  const tick = setInterval(() => {
    if (fs.existsSync(path.join(dir, 'release'))) { clearInterval(tick); end() }
    else if (Date.now() > giveUp) { clearInterval(tick); process.exitCode = 99 }
  }, 10)
} else end()
`

/** The CLI's --output-format json envelope around a result (a string, or a value it JSON-encodes). */
export const envelope = (result: unknown, extra: Record<string, unknown> = {}): string =>
  JSON.stringify({
    type: 'result',
    subtype: 'success',
    is_error: false,
    result: typeof result === 'string' ? result : JSON.stringify(result),
    ...extra,
  })

export const answer = (messages: Message[], workspace = 'Acme'): Scenario => ({ stdout: envelope({ workspace, messages }) })

export const msg = (over: Partial<Message> = {}): Message => ({
  channelId: 'C1',
  channel: '#eng',
  ts: '1700000000.000100',
  threadTs: null,
  from: 'Ria',
  text: 'is the CSV export landing today?',
  permalink: 'https://acme.slack.com/archives/C1/p1700000000000100',
  thread: [],
  ...over,
})

export async function world(): Promise<World> {
  // realpath: the macOS tmpdir is a symlink, and a child's cwd comes back resolved.
  const root = await realpath(await mkdtemp(join(tmpdir(), 'slack-')))
  const w: World = { root, home: join(root, 'home'), bin: join(root, 'bin'), fakes: join(root, 'fakes') }
  for (const dir of [w.home, w.bin, w.fakes]) await mkdir(dir)
  await writeFile(join(w.bin, 'claude'), `#!${process.execPath}\n${FAKE}`)
  await chmod(join(w.bin, 'claude'), 0o755)
  process.env.HOME = w.home
  delete process.env.JUEL_DIR
  process.env.CLAUDE_CONFIG_DIR = join(root, 'claude-config')
  process.env.PATH = `${w.bin}:/usr/bin:/bin`
  process.env.FAKE_DIR = w.fakes
  // git never looks above the temp root, so a project folder there is never read as a parent repo's.
  process.env.GIT_CEILING_DIRECTORIES = root
  await play(w, [answer([])])
  return w
}

export async function cleanup(w: World): Promise<void> {
  await release(w) // let a fake still held end before its folder goes
  await sleep(30)
  await rm(w.root, { recursive: true, force: true })
}

/** The scenarios the next fake runs play, in order; the last one repeats. */
export async function play(w: World, scenarios: Scenario[]): Promise<void> {
  await writeFile(join(w.fakes, 'scenarios.json'), JSON.stringify(scenarios))
  await rm(join(w.fakes, 'count'), { force: true })
  await rm(join(w.fakes, 'release'), { force: true })
}

export const release = (w: World): Promise<void> => writeFile(join(w.fakes, 'release'), '')

export async function calls(w: World): Promise<Call[]> {
  let text = ''
  try {
    text = await readFile(join(w.fakes, 'calls.jsonl'), 'utf8')
  } catch {
    return []
  }
  return text.split('\n').filter(Boolean).map(line => JSON.parse(line) as Call)
}

export const sleep = (ms: number): Promise<void> => new Promise(resolve => setTimeout(resolve, ms))

/** Polls until probe gives a truthy value. */
export async function until<T>(probe: () => T | Promise<T>, ms = 5000): Promise<T> {
  const end = Date.now() + ms
  for (;;) {
    const value = await probe()
    if (value) return value
    if (Date.now() > end) throw new Error('timed out waiting')
    await sleep(10)
  }
}

const LEDGER_HEAD =
  '| item | ref | project | worktree | state | stage | round | task | dispatch | restarts | pr | head | cursor | verify | counters | updated |\n' +
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'

/** A STAR ledger.md with one row per item (hooks/star.ts LEDGER_COLS). */
export const ledger = (rows: { item: string; pr?: string }[]): string =>
  `# Ledger\n\n${LEDGER_HEAD}${rows
    .map(row => `| ${row.item} | - | app | - | building | build | 1 | - | - | 0 | ${row.pr ?? '-'} | - | - | - | - | 2026-10-15T00:00:00Z |`)
    .join('\n')}\n`

/** A STAR brief's front matter and a body line. */
export const brief = (fields: { name: string; ref?: string | null; branch?: string }): string =>
  `---\njuel_brief: 1\nitem:\n  name: ${fields.name}\n  ref: ${fields.ref ?? 'null'}\n  slug: ${fields.name}\n` +
  `branch: ${fields.branch ?? `feat/${fields.name}`}\nbaseBranch: main\n---\n## Work item\n${fields.name}\n`

export type ProjectSpec = { origin?: string; ledger?: string; briefs?: Record<string, string>; repoName?: string }

/** A registered project: a repository folder (a git repo with that origin when given) and a STAR folder. */
export async function project(w: World, name: string, spec: ProjectSpec = {}): Promise<Project> {
  const repo = join(w.root, 'repos', spec.repoName ?? name)
  const home = join(w.root, 'stars', name)
  await mkdir(repo, { recursive: true })
  await mkdir(join(home, 'briefs', name), { recursive: true })
  if (spec.origin) {
    execFileSync('git', ['-C', repo, 'init', '-q'])
    execFileSync('git', ['-C', repo, 'remote', 'add', 'origin', spec.origin])
  }
  if (spec.ledger) await writeFile(join(home, 'ledger.md'), spec.ledger)
  for (const [file, text] of Object.entries(spec.briefs ?? {})) await writeFile(join(home, 'briefs', name, file), text)
  return { name, repo, home, terminal: null, state: 'running' }
}

export async function inboxFiles(p: Project): Promise<string[]> {
  try {
    return (await readdir(join(p.home, 'inbox'))).sort()
  } catch {
    return []
  }
}

export const state = (w: World, name: string): string => join(w.home, '.juel', 'slack', name)
export const readState = async (w: World, name: string): Promise<any> => JSON.parse(await readFile(state(w, name), 'utf8'))
export async function writeState(w: World, name: string, value: unknown): Promise<void> {
  await mkdir(join(w.home, '.juel', 'slack'), { recursive: true })
  await writeFile(state(w, name), typeof value === 'string' ? value : JSON.stringify(value))
}

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
  for (let i = 0; i < want.length; i += 1) {
    const part = want[i] ?? ''
    if (part.startsWith(':')) params[part.slice(1)] = decodeURIComponent(got[i] ?? '')
    else if (part !== got[i]) return null
  }
  return params
}

/** `nudge`: what nudge answers (default true). `throws`: emit and log record, then throw. */
export type StubOptions = { nudge?: (project: string) => Promise<boolean>; throws?: boolean }

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
        if (options.throws) throw new Error('emit is down')
      },
      projects: () => projects,
      async nudge(name) {
        s.nudges.push(name)
        return options.nudge ? options.nudge(name) : true
      },
      log(line) {
        s.logs.push(line)
        if (options.throws) throw new Error('log is down')
      },
    },
    async call(method, url, body) {
      const [pathname = '', search = ''] = url.split('?')
      for (const route of handlers) {
        const params = route.method === method ? match(route.path, pathname) : null
        if (params) return route.handler({ params, query: new URLSearchParams(search), body })
      }
      throw new Error(`no route for ${method} ${url}`)
    },
  }
  return s
}
