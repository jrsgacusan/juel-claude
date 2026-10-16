// The Slack watcher (STAR dashboard, part 4): one check at a time, at start and then every
// everyMin minutes. A check is one read-only `claude -p` run (D6 with S1) whose answer is checked
// (D7), deduped against seen.json, routed (D2) and handed to the routed project's STAR as a slack:
// inbox file (D9), then a nudge. Also the module's three routes. Nothing here sends anything to
// Slack: the run can use the pinned read tools only.
import { readFileSync } from 'node:fs'
import { mkdir } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { errorText, runCli } from './claude.ts'
import { channelLabel, deliver, inboxName, inboxText } from './inbox.ts'
import { parseEnvelope } from './parse.ts'
import { readDrafts, readOpenReplies, replyOf } from './replies.ts'
import type { Draft, OpenReply } from './replies.ts'
import { routeMessage, signalsOf } from './route.ts'
import {
  DAY_MS,
  MINUTE_MS,
  defaultStatus,
  idOf,
  isObject,
  isPending,
  isUnrouted,
  unroute,
  oneLine,
  prune,
  readEveryMin,
  readRoutes,
  readSeen,
  readStatus,
  readUnrouted,
  slackDir,
  writeRoutes,
  writeSeen,
  writeStatus,
  writeUnrouted,
} from './state.ts'
import type { Entry, Message, Seen, Status } from './state.ts'
import type { ModuleApi, Project, Req, Res } from './types.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
/** setInterval's longest delay: a longer one fires at once. */
const MAX_DELAY_MS = 2 ** 31 - 1
/** D5's mark for a message the owner dropped. A project by this name is never routed to. */
const DROPPED = 'none'

export type Config = { plugin: string; model: string; timeoutMin: number; allowedTools: string[]; disallowedTools: string[] }
export const loadConfig = (): Config => JSON.parse(readFileSync(join(HERE, 'config.json'), 'utf8')) as Config
const loadPrompt = (): string => readFileSync(join(HERE, 'prompt.md'), 'utf8')

/** The read-only run: D6, with S1's --settings, --setting-sources and --permission-mode. */
function argsOf(config: Config): string[] {
  return [
    '-p',
    '--model',
    config.model,
    '--output-format',
    'json',
    '--tools',
    '',
    '--setting-sources',
    '',
    '--settings',
    JSON.stringify({ enabledPlugins: { [config.plugin]: true } }),
    '--allowedTools',
    config.allowedTools.join(','),
    '--disallowedTools',
    config.disallowedTools.join(','),
    '--permission-mode',
    'dontAsk',
    '--no-session-persistence',
  ]
}

/** D4: from max(lastCheck minus 2 minutes, now minus 24 hours), and never later than now minus 2 minutes. */
export function windowStart(lastCheck: string | null, now: Date): Date {
  const floor = now.getTime() - DAY_MS
  const last = lastCheck === null ? Number.NaN : Date.parse(lastCheck)
  const start = Number.isFinite(last) ? Math.max(last - 2 * MINUTE_MS, floor) : floor
  return new Date(Math.min(start, now.getTime() - 2 * MINUTE_MS))
}

function fillPrompt(template: string, since: Date, now: Date): string {
  const unix = (at: Date): string => String(Math.floor(at.getTime() / 1000))
  return template
    .replaceAll('{{since_ts}}', unix(since))
    .replaceAll('{{since_iso}}', since.toISOString())
    .replaceAll('{{now_ts}}', unix(now))
    .replaceAll('{{now_iso}}', now.toISOString())
}

const lastLine = (text: string): string => oneLine(text.trim().split('\n').pop() ?? '')

/** Newest Slack ts first. */
function byTsDesc(a: { ts: string }, b: { ts: string }): number {
  const [ai = '0', af = ''] = a.ts.split('.')
  const [bi = '0', bf = ''] = b.ts.split('.')
  return Number(bi) - Number(ai) || bf.padEnd(6, '0').localeCompare(af.padEnd(6, '0'))
}

export type SlackOptions = { bin?: string; everyMs?: number; timeoutMs?: number; now?: () => Date }
export type CheckOutcome = { ok: boolean; routed: number; unrouted: number }
export type Slack = {
  /** Runs a check now and answers when it ends; null when one is already running. */
  check(): Promise<CheckOutcome | null>
  /** A check at once, then one every everyMs (S5); a tick while a check runs is skipped. */
  start(): void
  stop(): void
  readonly everyMs: number
}

type Applied = { routed: number; unrouted: number; pruned: number; statusMoved: boolean; files: Map<string, number> }

type Listed = {
  id: string
  project: string
  from: string
  channel: string
  text: string
  permalink: string
  thread: string[]
  draftPath: string | null
  loopId: string | null
}
type RouteDone = { res: Res } | { project: string }

export function createSlack(api: ModuleApi, opts: SlackOptions = {}): Slack {
  const config = loadConfig()
  const template = loadPrompt()
  const bin = opts.bin ?? 'claude'
  const now = opts.now ?? ((): Date => new Date())
  const everyMs = Math.min(opts.everyMs ?? readEveryMin() * MINUTE_MS, MAX_DELAY_MS)
  const timeoutMs = opts.timeoutMs ?? config.timeoutMin * MINUTE_MS

  // The server's emit and log may throw. Nothing a timer or a route started may end the server.
  const safely = (what: string, act: () => void): void => {
    try {
      act()
    } catch (err) {
      console.error(`slack: ${what} failed: ${errorText(err)}`)
    }
  }
  const emitChange = (): void => safely('emit', () => api.emit({ type: 'change', what: 'slack' }))
  // Counts and errors only: never a message's text, a person's name or a channel.
  const log = (line: string): void => safely('log', () => api.log(line))
  const nudge = async (project: string): Promise<boolean> => {
    try {
      return await api.nudge(project)
    } catch (err) {
      log(`slack: a nudge failed: ${errorText(err)}`)
      return false
    }
  }
  /** The registered projects a message can go to: never one named like D5's dropped mark. */
  const routable = (): Project[] => api.projects().filter(p => p.name !== DROPPED)

  // One writer of the state files at a time: a check's writes and a route never interleave.
  // `chain` never rejects, so each step runs after the one before it, however that one ended.
  let chain: Promise<unknown> = Promise.resolve()
  function locked<T>(act: () => Promise<T>): Promise<T> {
    const next = chain.then(act)
    chain = next.catch(() => undefined)
    return next
  }

  let running = false
  let timer: ReturnType<typeof setInterval> | null = null

  /** A failed check: status.json gets the error (and connected, when Slack said so); nothing else changes. */
  async function fail(kind: string, error: string, connected?: boolean): Promise<CheckOutcome> {
    log(`slack check failed: ${kind}`)
    let moved = false
    try {
      moved = await locked(async () => {
        const before = await readStatus(config.model).catch(() => defaultStatus(config.model))
        // D8: when Slack is not connected, no workspace is known.
        const after: Status = { ...before, connected: connected ?? before.connected, error, ...(connected === false ? { workspace: null } : {}) }
        await writeStatus(after)
        return after.connected !== before.connected || after.error !== before.error
      })
    } catch (err) {
      log(`slack: status.json could not be written: ${errorText(err)}`)
    }
    if (moved) emitChange()
    return { ok: false, routed: 0, unrouted: 0 }
  }

  /**
   * S4: under the lock, the lists first, with each routed entry reserving its inbox file name
   * (delivered false), then the inbox files, then the entries marked delivered, then status.json.
   * Hand-overs an earlier run left pending (a crash between its commit and its mark) are finished
   * here too, exactly once (`deliver`). A fresh hand-over that fails goes back to the unrouted list, where the owner can route it by hand;
   * a pending one that fails stays pending for the next check. The workspace is this answer's (D8).
   */
  async function apply(messages: Message[], workspace: string | null, start: Date): Promise<Applied> {
    const projects = routable()
    const signals = await Promise.all(projects.map(p => signalsOf(p)))
    return locked(async (): Promise<Applied> => {
      const before = await readStatus(config.model)
      const kept = prune(await readSeen(), await readUnrouted(), start)
      const routes = await readRoutes()
      const seen: Seen = kept.seen
      // An id whose entry is gone (a crash between two writes) or was routed by hand leaves the list.
      const unrouted = [...new Set(kept.unrouted)].filter(id => isUnrouted(seen, id))
      // fresh: reserved by this check, so nothing of it can be written yet.
      const handOver: { project: Project; id: string; fresh: boolean }[] = []
      for (const [id, entry] of Object.entries(seen)) {
        const project = isPending(entry) ? projects.find(p => p.name === entry.project) : undefined
        if (project) handOver.push({ project, id, fresh: false })
      }
      let added = 0
      for (const m of messages) {
        const id = idOf(m)
        if (Object.hasOwn(seen, id)) continue
        const decision = routeMessage(m, signals, routes)
        const project = decision.project === null ? undefined : projects.find(p => p.name === decision.project)
        if (project) {
          seen[id] = { ...m, seenAt: start.toISOString(), project: project.name, inbox: inboxName(start), delivered: false }
          handOver.push({ project, id, fresh: true })
        } else {
          seen[id] = { ...m, seenAt: start.toISOString(), project: null }
          unrouted.push(id)
          added += 1
        }
      }
      await writeUnrouted(unrouted)
      await writeSeen(seen)
      const files = new Map<string, number>()
      let failed = 0
      let waiting = 0
      for (const { project, id, fresh } of handOver) {
        const entry = seen[id] as Entry
        try {
          const inbox = await deliver(project.home, entry.inbox as string, id, inboxText(project.repo, entry), start)
          seen[id] = { ...entry, inbox, delivered: true }
          files.set(project.name, (files.get(project.name) ?? 0) + 1)
        } catch (err) {
          if (fresh) {
            log(`slack: an inbox file could not be written, so its message waits in unrouted: ${errorText(err)}`)
            seen[id] = unroute(entry)
            unrouted.push(id)
            failed += 1
          } else {
            // An earlier run may have written its file: sending it back to unrouted could hand it over twice.
            log(`slack: a pending hand-over could not be finished, so the next check tries again: ${errorText(err)}`)
            waiting += 1
          }
        }
      }
      if (handOver.length > 0) {
        await writeUnrouted(unrouted)
        await writeSeen(seen)
      }
      await writeStatus({ connected: true, lastCheck: start.toISOString(), error: null, model: config.model, workspace })
      return {
        routed: handOver.length - failed - waiting,
        unrouted: added + failed,
        pruned: kept.pruned,
        statusMoved: !before.connected || before.error !== null,
        files,
      }
    })
  }

  async function run(): Promise<CheckOutcome> {
    const start = now()
    let lastCheck: string | null
    try {
      // Every state file is read before the model runs: a damaged one fails the check (S6).
      const [status] = await locked(() => Promise.all([readStatus(config.model), readSeen(), readUnrouted(), readRoutes()]))
      lastCheck = status.lastCheck
      await mkdir(slackDir(), { recursive: true })
    } catch (err) {
      return fail('state', errorText(err))
    }
    const since = windowStart(lastCheck, start)
    const out = await runCli({ bin, args: argsOf(config), cwd: slackDir(), input: fillPrompt(template, since, start), timeoutMs })
    if (out.spawnError !== null) return fail('spawn', `claude could not start: ${oneLine(out.spawnError)}`)
    if (out.timedOut) return fail('timeout', `claude did not answer within ${Math.round(timeoutMs / 1000)} s`)
    if (out.tooLarge) return fail('output-too-large', 'claude printed more than the watcher reads')
    if (out.code !== 0) {
      const how = out.code === null ? `on ${out.signal ?? 'a signal'}` : String(out.code)
      return fail(`exit ${how}`, `claude exited ${how}${out.stderr.trim() ? `: ${lastLine(out.stderr)}` : ''}`)
    }
    const parsed = parseEnvelope(out.stdout)
    if (parsed.kind === 'disconnected') return fail('not-connected', `Slack is not connected: ${parsed.why}`, false)
    if (parsed.kind === 'error') return fail(parsed.cli ? 'cli-error' : 'bad-json', parsed.error)
    let applied: Applied
    try {
      applied = await apply(parsed.messages, parsed.workspace, start)
    } catch (err) {
      return fail('state', errorText(err))
    }
    for (const [project, count] of applied.files) {
      if (!(await nudge(project))) log(`slack: STAR was not reached: ${count} inbox file(s) wait for its next tick`)
    }
    log(`slack check: ${parsed.messages.length} found, ${applied.routed} routed, ${applied.unrouted} unrouted, ${applied.pruned} pruned`)
    if (applied.routed + applied.unrouted + applied.pruned > 0 || applied.statusMoved) emitChange()
    return { ok: true, routed: applied.routed, unrouted: applied.unrouted }
  }

  async function check(): Promise<CheckOutcome | null> {
    if (running) return null
    running = true
    try {
      return await run()
    } catch (err) {
      return await fail('internal', errorText(err))
    } finally {
      running = false
    }
  }

  const tick = (): void => {
    void check().catch(err => log(`slack check failed: ${errorText(err)}`))
  }

  function start(): void {
    if (timer !== null) return
    timer = setInterval(tick, everyMs)
    timer.unref()
    tick()
  }

  function stop(): void {
    if (timer !== null) clearInterval(timer)
    timer = null
  }

  const statusOrDefault = (): Promise<Status> =>
    readStatus(config.model).catch((err: unknown) => ({ ...defaultStatus(config.model), error: errorText(err) }))

  /** GET /api/slack: {status, routed, unrouted}; routed follows D5 and S7, both newest first. */
  async function listing(): Promise<{ status: Status; routed: Listed[]; unrouted: Record<string, string>[] }> {
    const status = await statusOrDefault()
    // S6: an unreadable file lists as empty, and the status says why.
    const problems: string[] = []
    const seen = await readSeen().catch((err: unknown): Seen => {
      problems.push(errorText(err))
      return {}
    })
    const ids = await readUnrouted().catch((err: unknown): string[] => {
      problems.push(errorText(err))
      return []
    })
    if (problems.length > 0) status.error = [status.error, ...problems].filter(Boolean).join('; ')
    const projects = api.projects()
    const replies = new Map<string, { drafts: Draft[]; loops: OpenReply[] | null }>()
    const routed: Listed[] = []
    for (const [id, entry] of Object.entries(seen).sort(([, a], [, b]) => byTsDesc(a, b))) {
      const project = entry.project === null || entry.project === DROPPED ? undefined : projects.find(p => p.name === entry.project)
      if (!project) continue
      let found = replies.get(project.name)
      if (!found) {
        found = { drafts: await readDrafts(project.home), loops: await readOpenReplies(project.home) }
        replies.set(project.name, found)
      }
      const reply = replyOf(entry, id, found.drafts, found.loops)
      if (reply.finished) continue
      routed.push({
        id,
        project: project.name,
        from: entry.from,
        channel: channelLabel(entry.channelId, entry.channel),
        text: entry.text,
        permalink: entry.permalink,
        thread: entry.thread,
        draftPath: reply.draftPath,
        loopId: reply.loopId,
      })
    }
    const unrouted = [...new Set(ids)]
      .filter(id => isUnrouted(seen, id))
      .map(id => ({ id, entry: seen[id] as Entry }))
      .sort((a, b) => byTsDesc(a.entry, b.entry))
      .map(({ id, entry }) => ({ id, from: entry.from, channel: channelLabel(entry.channelId, entry.channel), text: entry.text, permalink: entry.permalink }))
    return { status, routed, unrouted }
  }

  /**
   * POST /api/slack/:id/route {project} (S8): seen.json first (the commit, with the inbox name it
   * reserves), then the inbox file, then the entry marked delivered, the learned channel (D3) and the
   * unrouted list. A failed inbox write puts seen.json back and is a 500, so the route can be tried
   * again as it is. A crash after the commit leaves a pending hand-over the next check finishes,
   * exactly once (S4).
   */
  async function routeOne(req: Req): Promise<Res> {
    const id = req.params.id ?? ''
    const want = isObject(req.body) ? req.body.project : undefined
    let done: RouteDone
    try {
      done = await locked(async (): Promise<RouteDone> => {
        const seen = await readSeen()
        const ids = await readUnrouted()
        const entry = ids.includes(id) && isUnrouted(seen, id) ? (seen[id] as Entry) : null
        if (entry === null) return { res: { status: 404, json: { error: `no unrouted message ${id}` } } }
        if (typeof want !== 'string' || want === '') return { res: { status: 400, json: { error: 'project must be a project name or "none"' } } }
        const dropFromUnrouted = async (): Promise<void> => {
          try {
            await writeUnrouted(ids.filter(other => other !== id))
          } catch (err) {
            log(`slack: unrouted.json could not be written: ${errorText(err)}`)
          }
        }
        if (want === DROPPED) {
          await writeSeen({ ...seen, [id]: { ...entry, project: DROPPED } })
          await dropFromUnrouted()
          return { project: DROPPED }
        }
        const project = routable().find(p => p.name === want)
        if (!project) return { res: { status: 400, json: { error: `unknown project ${want}` } } }
        const at = now()
        const routed: Entry = { ...entry, project: project.name, inbox: inboxName(at), delivered: false }
        // The commit: from here a crash leaves a pending hand-over, which the next check finishes.
        await writeSeen({ ...seen, [id]: routed })
        let inbox: string
        try {
          inbox = await deliver(project.home, routed.inbox as string, id, inboxText(project.repo, routed), at)
        } catch (err) {
          await writeSeen(seen).catch((undo: unknown) => log(`slack: seen.json could not be put back after a failed route: ${errorText(undo)}`))
          throw err
        }
        try {
          await writeSeen({ ...seen, [id]: { ...routed, inbox, delivered: true } })
        } catch (err) {
          log(`slack: seen.json could not mark a hand-over delivered; the next check will: ${errorText(err)}`)
        }
        // D3: the owner's route teaches the channel. The route stands if this write fails.
        try {
          await writeRoutes({ ...(await readRoutes()), [entry.channelId]: project.name })
        } catch (err) {
          log(`slack: routes.json could not be written, so the channel was not learned: ${errorText(err)}`)
        }
        await dropFromUnrouted()
        return { project: project.name }
      })
    } catch (err) {
      log(`slack: a route failed: ${errorText(err)}`)
      return { status: 500, json: { error: errorText(err) } }
    }
    if ('res' in done) return done.res
    emitChange()
    if (done.project === DROPPED) {
      log('slack: 1 message dropped by hand')
      return { status: 200, json: { project: DROPPED } }
    }
    const nudged = await nudge(done.project)
    log(`slack: 1 message routed by hand${nudged ? '' : '; STAR was not reached'}`)
    return { status: 200, json: { project: done.project, nudged } }
  }

  api.route('GET', '/api/slack', async () => ({ status: 200, json: await listing() }))
  api.route('POST', '/api/slack/check', async () => {
    const outcome = await check()
    if (outcome === null) return { status: 409, json: { error: 'a check is already running' } }
    return { status: 200, json: { ...outcome, status: await statusOrDefault() } }
  })
  api.route('POST', '/api/slack/:id/route', routeOne)

  return { check, start, stop, everyMs }
}
