import crypto from 'node:crypto'
import http from 'node:http'
import fs from 'node:fs'
import { Hub, watchHomes } from './events.ts'
import type { WatchFn } from './events.ts'
import { HttpError, Unreadable, readJson, sendJson } from './http.ts'
import { loadModules } from './modules.ts'
import { nudge } from './orca.ts'
import { LOOPS_SH, MODULES_DIR, WEB_DIST } from './paths.ts'
import { Registry } from './registry.ts'
import { readStar } from './readers/star.ts'
import { Router } from './router.ts'
import { loopRoutes } from './routes/loops.ts'
import { projectRoutes } from './routes/projects.ts'
import { evidenceRoutes } from './routes/evidence.ts'
import { itemRoutes } from './routes/items.ts'
import { serveStatic } from './static.ts'
import type { Project } from './types.ts'

export type AppOptions = { port: number; token: string; juelDir: string; log: (line: string) => void; webDist?: string; modulesDir?: string; loopsSh?: string; watch?: WatchFn; pollMs?: number; rescanMs?: number }
export type Ctx = { registry: Registry; log: (line: string) => void; loopsSh: string; nudge(project: Project): Promise<boolean> }
export type App = { port: number; server: http.Server; registry: Registry; hub: Hub; close(): Promise<void> }

const tokenOk = (got: string | string[] | undefined, want: string): boolean => {
  if (typeof got !== 'string') return false
  const a = Buffer.from(got); const b = Buffer.from(want)
  return a.length === b.length && crypto.timingSafeEqual(a, b)
}

async function nudgeProject(project: Project): Promise<boolean> {
  try { return await nudge(readStar(project.home).star.terminal) } catch { return false }
}

export async function startApp(opts: AppOptions): Promise<App> {
  const log = opts.log
  const registry = new Registry(opts.juelDir, log)
  await registry.refresh()
  const hub = new Hub()
  const router = new Router()
  const ctx: Ctx = { registry, log, loopsSh: opts.loopsSh ?? LOOPS_SH, nudge: nudgeProject }
  projectRoutes(router, ctx)
  loopRoutes(router, ctx)
  itemRoutes(router, ctx)
  evidenceRoutes(router, ctx)
  const dist = opts.webDist ?? WEB_DIST

  async function handle(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    const url = new URL(req.url ?? '/', 'http://127.0.0.1')
    if (url.pathname !== '/api' && !url.pathname.startsWith('/api/')) { serveStatic(req, res, dist); return }
    if (!tokenOk(req.headers['x-star-token'], opts.token)) { sendJson(res, 401, { error: 'missing or wrong X-Star-Token' }); return }
    if (url.pathname === '/api/events') {
      if (req.method !== 'GET') sendJson(res, 405, { error: 'GET only' }); else hub.attach(req, res)
      return
    }
    const found = router.match(req.method ?? 'GET', url.pathname)
    if (found === undefined) { sendJson(res, 404, { error: `no route ${url.pathname}` }); return }
    if (found === 'method') { sendJson(res, 405, { error: `${req.method ?? ''} is not allowed on ${url.pathname}` }); return }
    const body = req.method === 'GET' ? undefined : await readJson(req)
    const out = await found.handler({ params: found.params, query: url.searchParams, body })
    if (out.file) {
      res.writeHead(out.status ?? 200, { 'content-type': out.file.type, 'content-length': out.file.size, 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'content-security-policy': 'sandbox' })
      fs.createReadStream(out.file.path).on('error', () => res.destroy()).pipe(res)
      return
    }
    sendJson(res, out.status ?? 200, out.json)
  }

  const server = http.createServer((req, res) => {
    handle(req, res).catch((err: unknown) => {
      if (res.headersSent) { res.destroy(); return }
      if (err instanceof HttpError) sendJson(res, err.status, { error: err.message })
      else if (err instanceof Unreadable) sendJson(res, 502, { error: `${err.file}: ${err.why}` })
      else { log(`error on ${req.method ?? ''} ${req.url ?? ''}: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}`); sendJson(res, 500, { error: err instanceof Error ? err.message : String(err) }) }
    })
  })
  try {
    await new Promise<void>((resolve, reject) => {
      server.once('error', reject)
      server.listen(opts.port, '127.0.0.1', () => { server.off('error', reject); resolve() })
    })
  } catch (err) { hub.close(); throw err }
  await loadModules(opts.modulesDir ?? MODULES_DIR, router, { emit: e => hub.emit(e), projects: () => registry.snapshot(), nudge: async name => { const p = (await registry.current()).find(x => x.name === name); return p ? nudgeProject(p) : false } }, log)
  const watcher = watchHomes(() => registry.entries(), e => hub.emit(e), log, { watch: opts.watch, pollMs: opts.pollMs ?? 5000, rescanMs: opts.rescanMs })
  const address = server.address()
  const port = typeof address === 'object' && address ? address.port : opts.port
  return { port, server, registry, hub, close: () => new Promise<void>(resolve => { watcher.close(); hub.close(); server.close(() => resolve()); server.closeAllConnections() }) }
}
