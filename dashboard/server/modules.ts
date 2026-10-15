import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import type { Handler, Method, Router } from './router.ts'
import type { ModuleApi } from './types.ts'

const METHODS = new Set(['GET', 'POST', 'PUT'])

/**
 * Import every <dir>/<name>/index.ts, in name order, and call its register(api). A module's routes
 * count only once register has returned without throwing (a later route call goes straight in); a
 * module that throws, or has no register, is logged and nothing of it is kept.
 */
export async function loadModules(
  dir: string,
  router: Router,
  base: Pick<ModuleApi, 'emit' | 'projects' | 'nudge'>,
  log: (line: string) => void,
): Promise<string[]> {
  let names: string[]
  try {
    names = fs
      .readdirSync(dir, { withFileTypes: true })
      .filter(d => d.isDirectory())
      .map(d => d.name)
      .sort()
  } catch {
    return []
  }
  const loaded: string[] = []
  for (const name of names) {
    const file = path.join(dir, name, 'index.ts')
    if (!fs.existsSync(file)) continue
    const pending: [Method, string, Handler][] = []
    let state: 'loading' | 'live' | 'dead' = 'loading'
    const api: ModuleApi = {
      route(method, routePath, handler) {
        if (!METHODS.has(method) || !routePath.startsWith('/api/')) {
          log(`[${name}] route ${method} ${routePath} ignored: a module route is GET, POST or PUT under /api/`)
          return
        }
        if (state === 'live') router.add(method, routePath, handler)
        else if (state === 'loading') pending.push([method, routePath, handler])
      },
      emit: e => base.emit(e),
      projects: () => base.projects(),
      nudge: project => base.nudge(project),
      log: line => log(`[${name}] ${line}`),
    }
    try {
      const mod = (await import(pathToFileURL(file).href)) as { register?: unknown }
      if (typeof mod.register !== 'function') throw new Error('index.ts exports no register(api)')
      await (mod.register as (api: ModuleApi) => unknown)(api)
      for (const [m, p, h] of pending) router.add(m, p, h)
      state = 'live'
      loaded.push(name)
      log(`module ${name} loaded`)
    } catch (err) {
      state = 'dead'
      log(`module ${name} skipped: ${err instanceof Error ? err.message : String(err)}`)
    }
  }
  return loaded
}
