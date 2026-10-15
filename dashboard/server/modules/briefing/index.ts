// The briefing module (STAR dashboard, part 3): a read-only Claude agent that helps the owner shape
// one piece of work, and the create that turns its draft into a ticket STAR picks up. The server
// imports dashboard/server/modules/*/index.ts and calls register(api).
import { createTicket } from './create.ts'
import { briefingDir, createBriefing, isDir, listBriefings, readCreated, readDraft, readTurns } from './store.ts'
import { TRACKERS, isTracker, resolveTracker, saveTracker } from './tracker.ts'
import { runTurn } from './turn.ts'
import type { ModuleApi, Project, Req, Res } from './types.ts'

type Located = { project: Project; id: string; dir: string }

const answer = (json: unknown, status = 200): Res => ({ status, json })
const refuse = (status: number, error: string, extra: Record<string, unknown> = {}): Res => ({ status, json: { error, ...extra } })
const message = (err: unknown): string => (err instanceof Error ? err.message : String(err))
const field = (body: unknown, name: string): unknown => (typeof body === 'object' && body !== null ? (body as Record<string, unknown>)[name] : undefined)
const BAD_TRACKER = `tracker must be one of ${TRACKERS.join(', ')}`

export function register(api: ModuleApi): void {
  // Briefings with a turn or a create running, as <project>/<id>: one at a time each (B4).
  const busy = new Set<string>()
  const keyOf = (at: Located): string => `${at.project.name}/${at.id}`
  const projectOf = (req: Req): Project | null => api.projects().find(project => project.name === req.params.p) ?? null
  const isLocated = (value: Located | Res): value is Located => 'dir' in value

  async function locate(req: Req): Promise<Located | Res> {
    const project = projectOf(req)
    if (!project) return refuse(404, 'unknown project')
    const id = req.params.id ?? ''
    const dir = briefingDir(project.home, id)
    if (dir === null || !(await isDir(dir))) return refuse(404, 'unknown briefing')
    return { project, id, dir }
  }

  api.route('GET', '/api/projects/:p/briefings', async req => {
    const project = projectOf(req)
    if (!project) return refuse(404, 'unknown project')
    return answer(await listBriefings(project.home))
  })

  api.route('POST', '/api/projects/:p/briefings', async req => {
    const project = projectOf(req)
    if (!project) return refuse(404, 'unknown project')
    return answer({ id: await createBriefing(project.home) }, 201)
  })

  api.route('GET', '/api/projects/:p/briefings/:id', async req => {
    const at = await locate(req)
    if (!isLocated(at)) return at
    const [turns, draft] = await Promise.all([readTurns(at.dir), readDraft(at.dir)])
    return answer({ turns: turns.map(({ who, text, files }) => ({ who, text, files })), draft, busy: busy.has(keyOf(at)) })
  })

  api.route('POST', '/api/projects/:p/briefings/:id/messages', async req => {
    const at = await locate(req)
    if (!isLocated(at)) return at
    const text = field(req.body, 'text')
    if (typeof text !== 'string' || text.trim() === '') return refuse(400, 'text must be a non-empty string')
    const key = keyOf(at)
    if (busy.has(key)) return refuse(409, 'a turn is already running for this briefing')
    busy.add(key)
    const { project, id, dir } = at
    runTurn({ project: project.name, id, repo: project.repo, dir, text, emit: event => api.emit(event), log: line => api.log(line) })
      .catch((err: unknown) => {
        api.emit({ type: 'briefing', project: project.name, id, error: message(err) })
        api.log(`briefing ${key}: turn failed: ${message(err)}`)
      })
      .finally(() => busy.delete(key))
    return answer({ accepted: true }, 202)
  })

  api.route('POST', '/api/projects/:p/briefings/:id/create', async req => {
    const at = await locate(req)
    if (!isLocated(at)) return at
    const tracker = field(req.body, 'tracker')
    if (!isTracker(tracker)) return refuse(400, BAD_TRACKER)
    const key = keyOf(at)
    if (busy.has(key)) return refuse(409, 'this briefing is busy')
    busy.add(key)
    try {
      const created = await readCreated(at.dir)
      if (created) return refuse(409, 'this briefing already made a ticket', { created })
      const draft = await readDraft(at.dir)
      if (!draft) return refuse(409, 'no draft yet')
      const config = await resolveTracker(at.project.repo)
      const outcome = await createTicket({
        project: at.project.name,
        repo: at.project.repo,
        home: at.project.home,
        dir: at.dir,
        tracker,
        trackerProject: config?.type === tracker ? config.project : null,
        draft,
      })
      if (!outcome.ok) {
        api.log(`briefing ${key}: ${tracker} create failed: ${outcome.error}`)
        return refuse(502, outcome.error, { tracker })
      }
      const { ref, specPath, url } = outcome.created
      const nudged = await api.nudge(at.project.name).catch(() => false)
      api.log(`briefing ${key}: created ${ref ?? specPath} via ${tracker}; STAR ${nudged ? 'nudged' : 'not reached'}`)
      return answer(ref ? { ref, url } : { specPath, url }, 201)
    } finally {
      busy.delete(key)
    }
  })

  api.route('GET', '/api/projects/:p/tracker', async req => {
    const project = projectOf(req)
    if (!project) return refuse(404, 'unknown project')
    return answer({ tracker: (await resolveTracker(project.repo))?.type ?? null })
  })

  api.route('PUT', '/api/projects/:p/tracker', async req => {
    const project = projectOf(req)
    if (!project) return refuse(404, 'unknown project')
    const tracker = field(req.body, 'tracker')
    if (!isTracker(tracker)) return refuse(400, BAD_TRACKER)
    const saved = await saveTracker(project.repo, tracker)
    if (!saved.ok) return refuse(409, saved.error)
    return answer({ tracker })
  })
}
