// The chat module (spec 3.1): the owner's messages to the running STAR through its inbox, the thread
// paged back to the web app, and the away switch's control file. The server imports modules/*/index.ts
// and calls register(api).
import { chatInboxText, MESSAGE_ID, pageOf, readThread, repoOf, writeInbox, writeMine } from './store.ts'
import type { ModuleApi, Project, Req, Res } from './types.ts'

const answer = (json: unknown, status = 200): Res => ({ status, json })
const refuse = (status: number, error: string): Res => ({ status, json: { error } })
const field = (body: unknown, name: string): unknown => (typeof body === 'object' && body !== null ? (body as Record<string, unknown>)[name] : undefined)

export function register(api: ModuleApi): void {
  const projectOf = (req: Req): Project | null => api.projects().find(project => project.name === req.params.p) ?? null

  // A nudge that rejects counts as not nudged: the files are written, STAR reads them at its next look.
  const nudge = async (project: Project): Promise<boolean> => {
    try {
      return await Promise.resolve().then(() => api.nudge(project.name))
    } catch (err) {
      api.log(`chat ${project.name}: nudge failed: ${err instanceof Error ? err.message : String(err)}`)
      return false
    }
  }

  api.route('GET', '/api/projects/:p/chat', async req => {
    const project = projectOf(req)
    if (!project) return refuse(404, 'unknown project')
    const rawLimit = req.query.get('limit')
    let limit = 100
    if (rawLimit !== null) {
      limit = /^[0-9]+$/.test(rawLimit) ? Number(rawLimit) : 0
      if (limit < 1 || limit > 200) return refuse(400, 'limit must be a whole number from 1 to 200')
    }
    const before = req.query.get('before')
    if (before !== null && !MESSAGE_ID.test(before)) return refuse(400, 'before must be a message id')
    return answer({ ...pageOf(await readThread(project.home), before, limit), starRunning: project.state !== 'stopped' })
  })

  api.route('POST', '/api/projects/:p/chat', async req => {
    const project = projectOf(req)
    if (!project) return refuse(404, 'unknown project')
    const raw = field(req.body, 'text')
    const text = typeof raw === 'string' ? raw.trim() : ''
    if (text.length < 1 || text.length > 8000) return refuse(400, 'text must be 1 to 8000 characters')
    const repo = await repoOf(project.home, project.repo)
    const m = await writeMine(project.home, text)
    await writeInbox(project.home, 'chat', chatInboxText(repo, m.id, m.text))
    return answer({ id: m.id, nudged: await nudge(project) })
  })

  api.route('POST', '/api/projects/:p/away', async req => {
    const project = projectOf(req)
    if (!project) return refuse(404, 'unknown project')
    const body = req.body
    const keys = typeof body === 'object' && body !== null && !Array.isArray(body) ? Object.keys(body) : []
    const away = field(body, 'away')
    if (keys.length !== 1 || keys[0] !== 'away' || typeof away !== 'boolean') return refuse(400, 'body must be {"away": true} or {"away": false}')
    await writeInbox(project.home, 'control', away ? 'control: away\n' : 'control: back\n')
    return answer({ recorded: true, nudged: await nudge(project) })
  })
}
