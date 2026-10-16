// The briefing module (STAR dashboard, part 3): a read-only Claude agent that helps the owner shape
// one piece of work, and the create that turns its draft into a ticket STAR picks up. The server
// imports dashboard/server/modules/*/index.ts and calls register(api).
import { join } from 'node:path'

import { message } from './claude.ts'
import { createTicket, queueCreated } from './create.ts'
import type { CreateOutcome } from './create.ts'
import { briefingDir, createBriefing, isDir, listBriefings, readCreated, readDraft, readTurns, unqueued } from './store.ts'
import { TRACKERS, asTracker, isTracker, resolveTracker, saveTracker } from './tracker.ts'
import { runTurn } from './turn.ts'
import type { ModuleApi, Project, Req, Res } from './types.ts'

type Located = { project: Project; id: string; dir: string }

const answer = (json: unknown, status = 200): Res => ({ status, json })
const refuse = (status: number, error: string, extra: Record<string, unknown> = {}): Res => ({ status, json: { error, ...extra } })
const field = (body: unknown, name: string): unknown => (typeof body === 'object' && body !== null ? (body as Record<string, unknown>)[name] : undefined)
const BAD_TRACKER = `tracker must be one of ${TRACKERS.join(', ')}`

export function register(api: ModuleApi): void {
  // The server's emit and log may throw (a full disk under ~/.juel/dashboard.log, say). A throw from a
  // turn that nothing awaits would end the whole server, so neither ever escapes this module.
  const safely = (what: string, act: () => void): void => {
    try {
      act()
    } catch (err) {
      console.error(`briefing: ${what} failed: ${message(err)}`)
    }
  }
  const emit: ModuleApi['emit'] = event => safely('emit', () => api.emit(event))
  const log = (line: string): void => safely('log', () => api.log(line))

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
    runTurn({ project: project.name, id, repo: project.repo, dir, text, emit, log })
      .catch((err: unknown) => {
        emit({ type: 'briefing', project: project.name, id, error: message(err) })
        log(`briefing ${key}: turn failed: ${message(err)}`)
      })
      .finally(() => busy.delete(key))
    return answer({ accepted: true }, 202)
  })

  /** The create's answer: 201 after the nudge, 500 with `made` when the ticket exists, else 502 (flagged `maybeMade` when it may exist; the briefing then stays marked). */
  async function finish(at: Located, tracker: string, outcome: CreateOutcome): Promise<Res> {
    const key = keyOf(at)
    if (!outcome.ok) {
      log(`briefing ${key}: ${tracker} create failed: ${outcome.error}`)
      // The ticket exists (unrecorded, or recorded but not in STAR's inbox yet): never the 502 that offers to make it again.
      if (outcome.made) return refuse(500, outcome.error, { tracker, made: outcome.made })
      return refuse(502, outcome.error, outcome.maybeMade ? { tracker, maybeMade: true } : { tracker })
    }
    const { ref, specPath, url } = outcome.created
    // A nudge that throws or rejects means STAR was not reached; the ticket stands either way.
    const nudged = await Promise.resolve()
      .then(() => api.nudge(at.project.name))
      .catch((err: unknown) => {
        log(`briefing ${key}: nudge failed: ${message(err)}`)
        return false
      })
    log(`briefing ${key}: created ${ref ?? specPath} via ${tracker}; STAR ${nudged ? 'nudged' : 'not reached'}`)
    return answer(ref ? { ref, url } : { specPath, url }, 201)
  }

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
      // A create that did not finish may have made a ticket: never make another on a guess (D8).
      if (created?.state === 'creating') {
        const where = join(at.dir, 'created.json')
        const items = join(at.project.home, 'items', at.project.name)
        const look = created.tracker === 'none' || created.tracker === 'synapse' ? `check ${items} for its spec item` : `check ${created.tracker} for the ticket, or ${items} for a spec item`
        return refuse(409, `an earlier ${created.tracker} create of this briefing did not finish: ${look} (the dashboard log names anything it made), then remove ${where} to try again`, { created })
      }
      // Made, but not known to be queued: resume it, never a second inbox file (D1, D2).
      if (created && unqueued(created)) {
        return await finish(at, created.tracker, await queueCreated({ home: at.project.home, repo: at.project.repo, dir: at.dir }, created, { resume: true }))
      }
      if (created) return refuse(409, 'this briefing already made a ticket', { created })
      const draft = await readDraft(at.dir)
      if (!draft) return refuse(409, 'no draft yet')
      const config = await resolveTracker(at.project.repo, log)
      const outcome = await createTicket({
        project: at.project.name,
        repo: at.project.repo,
        home: at.project.home,
        dir: at.dir,
        tracker,
        trackerProject: config && asTracker(config.type) === tracker ? config.project : null,
        draft,
        log,
      })
      return await finish(at, tracker, outcome)
    } finally {
      busy.delete(key)
    }
  })

  api.route('GET', '/api/projects/:p/tracker', async req => {
    const project = projectOf(req)
    if (!project) return refuse(404, 'unknown project')
    const found = await resolveTracker(project.repo, log)
    const tracker = found ? asTracker(found.type) : null
    if (found && !tracker) log(`briefing: ${project.name}'s tracker "${found.type}" is not one the dashboard creates in, so the page asks`)
    return answer({ tracker })
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
