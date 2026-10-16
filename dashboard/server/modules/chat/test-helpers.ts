// Test scaffolding for the chat module: a throwaway STAR home and a thread written straight to disk.
import { mkdir, mkdtemp, realpath, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { messageText } from './store.ts'
import type { ChatMessage } from './store.ts'
import type { ModuleApi, Project, Req, Res } from './types.ts'

export type World = { root: string; home: string; project: Project }

export async function world(state: Project['state'] = 'running'): Promise<World> {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'chat-')))
  const home = join(root, 'star')
  await mkdir(home)
  await writeFile(join(home, 'star.json'), JSON.stringify({ project: { name: 'proj', repo: '/w/proj' }, terminal: 'term_proj' }))
  return { root, home, project: { name: 'proj', repo: join(root, 'repo'), home, terminal: 'term_proj', state } }
}

export async function cleanup(w: World): Promise<void> {
  await rm(w.root, { recursive: true, force: true })
}

export const MSGS: ChatMessage[] = [
  { id: '20261017T010001Z-me-0001', who: 'me', at: '2026-10-17T01:00:01Z', replyTo: null, text: 'how is it going?' },
  { id: '20261017T010002Z-star-0002', who: 'star', at: '2026-10-17T01:00:02Z', replyTo: '20261017T010001Z-me-0001', text: 'Two rows **run**:\n\n- N-12\n- N-13' },
  { id: '20261017T010003Z-me-0003', who: 'me', at: '2026-10-17T01:00:03Z', replyTo: null, text: 'drop N-13' },
  { id: '20261017T010004Z-star-0004', who: 'star', at: '2026-10-17T01:00:04Z', replyTo: '20261017T010003Z-me-0003', text: 'Dropped N-13.' },
  { id: '20261017T010005Z-me-0005', who: 'me', at: '2026-10-17T01:00:05Z', replyTo: null, text: 'thanks' },
]

export async function writeThread(home: string, messages: readonly ChatMessage[]): Promise<void> {
  await mkdir(join(home, 'chat'), { recursive: true })
  for (const m of messages) await writeFile(join(home, 'chat', `${m.id}.md`), messageText(m))
}

export type Stub = {
  api: ModuleApi
  routes: string[]
  nudges: string[]
  logs: string[]
  call: (method: 'GET' | 'POST' | 'PUT' | 'DELETE', url: string, body?: unknown) => Promise<Res>
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

/** A ModuleApi that records routes, nudges and logs, and `call` to run a registered handler as the server would. */
export function stub(projects: Project[], nudge?: (project: string) => Promise<boolean>): Stub {
  const handlers: { method: string; path: string; handler: (req: Req) => Promise<Res> }[] = []
  const s: Stub = {
    routes: [],
    nudges: [],
    logs: [],
    api: {
      route(method, path, handler) {
        s.routes.push(`${method} ${path}`)
        handlers.push({ method, path, handler })
      },
      emit() {},
      projects: () => projects,
      async nudge(project) {
        s.nudges.push(project)
        return nudge ? nudge(project) : true
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
