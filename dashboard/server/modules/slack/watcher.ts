// The Slack watcher (STAR dashboard, part 4): one check at a time, at start and then every
// everyMin minutes. A check is one read-only `claude -p` run (D6 with S1) whose answer is checked
// (D7), deduped against seen.json, routed (D2) and handed to the routed project's STAR as a slack:
// inbox file (D9), then a nudge. Also the module's three routes. Nothing here sends anything to
// Slack: the run can use the pinned read tools only.
import { readFileSync } from 'node:fs'
import { mkdir, stat } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { errorText, runCli } from './claude.ts'
import { MIN_FREE_BYTES, draftName, draftReply, findDraft, freeMemory, serial, toLine, writeDraft } from './drafter.ts'
import type { Drafter } from './drafter.ts'
import { channelLabel, deliver, inboxName, inboxText } from './inbox.ts'
import { parseEnvelope } from './parse.ts'
import { readDrafts, readOpenReplies, replyOf } from './replies.ts'
import type { Draft, OpenReply } from './replies.ts'
import { routeMessage, signalsOf } from './route.ts'
import { keeps, ownerNames } from './filter.ts'
import { loadConfig, pluginIds, readSlackSettings } from './settings.ts'
import type { Config } from './settings.ts'
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

export { loadConfig } from './settings.ts'
const loadPrompt = (): string => readFileSync(join(HERE, 'prompt.md'), 'utf8')

/** The read-only run: D6, with S1's --settings, --setting-sources and --permission-mode. */
function argsOf(config: Config, plugin: string): string[] {
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
    JSON.stringify({ enabledPlugins: { [plugin]: true } }),
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

function fillPrompt(template: string, since: Date, now: Date, names: string[]): string {
  const unix = (at: Date): string => String(Math.floor(at.getTime() / 1000))
  return template
    .replaceAll('{{since_ts}}', unix(since))
    .replaceAll('{{since_iso}}', since.toISOString())
    .replaceAll('{{now_ts}}', unix(now))
    .replaceAll('{{now_iso}}', now.toISOString())
    .replaceAll('{{names}}', names.length > 0 ? names.join(', ') : 'none')
}

const lastLine = (text: string): string => oneLine(text.trim().split('\n').pop() ?? '')

/** The last n non-blank lines of text, joined with a newline; null when there are none. */
function lastLines(text: string, n: number): string | null {
  const lines = text.replaceAll('\r', '').split('\n').map(line => line.trimEnd()).filter(line => line.trim() !== '')
  return lines.length === 0 ? null : lines.slice(-n).join('\n')
}

/** Newest Slack ts first. */
function byTsDesc(a: { ts: string }, b: { ts: string }): number {
  const [ai = '0', af = ''] = a.ts.split('.')
  const [bi = '0', bf = ''] = b.ts.split('.')
  return Number(bi) - Number(ai) || bf.padEnd(6, '0').localeCompare(af.padEnd(6, '0'))
}

export type SlackOptions = { bin?: string; everyMs?: number; timeoutMs?: number; now?: () => Date; draft?: Drafter }
export type CheckOutcome = { ok: boolean; routed: number; unrouted: number }
export type Slack = {
  /** Runs a check now and answers when it ends; null when one is already running. */
  check(): Promise<CheckOutcome | null>
  /** A check at once, then one every everyMs (S5); a tick while a check runs is skipped. */
  start(): void
  stop(): void
  /** Resolves once no hand-over or redraft runs in the background. */
  idle(): Promise<void>
  readonly everyMs: number
}

/** One routed message to hand over: `fresh` was reserved just now, `learn` teaches its channel (D3) after the hand-over. */
type Job = { project: Project; id: string; entry: Entry; fresh: boolean; learn: boolean }
type Committed = { jobs: Job[]; added: number; pruned: number; statusMoved: boolean }
type HandedOver = 'delivered' | 'unrouted' | 'waiting'

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
type RouteDone = { res: Res } | { project: string } | { job: Job; at: Date }

export function createSlack(api: ModuleApi, opts: SlackOptions = {}): Slack {
  const config = loadConfig()
  const template = loadPrompt()
  const bin = opts.bin ?? 'claude'
  const now = opts.now ?? ((): Date => new Date())
  const everyMs = Math.min(opts.everyMs ?? readSlackSettings().everyMin * MINUTE_MS, MAX_DELAY_MS)
  const timeoutMs = opts.timeoutMs ?? config.timeoutMin * MINUTE_MS
  const draft: Drafter = opts.draft ?? (req => draftReply(req, { bin }))
  // One drafter at a time, for a check, a route by hand and a redraft alike.
  const oneDraft = serial()
  // Ids whose hand-over runs now, so a later check does not start it twice.
  const inFlight = new Set<string>()
  const background = new Set<Promise<unknown>>()
  const inBackground = (work: Promise<unknown>): void => {
    const tracked = work.catch(() => undefined).finally(() => background.delete(tracked))
    background.add(tracked)
  }
  const idle = async (): Promise<void> => {
    while (background.size > 0) await Promise.allSettled([...background])
  }

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
  let offLogged = false
  let timer: ReturnType<typeof setInterval> | null = null

  /** A failed check: status.json gets the error (and connected, when Slack said so); nothing else changes. */
  async function fail(kind: string, error: string, connected?: boolean, stderr: string | null = null): Promise<CheckOutcome> {
    log(`slack check failed: ${kind}`)
    let moved = false
    try {
      moved = await locked(async () => {
        const before = await readStatus(config.model).catch(() => defaultStatus(config.model))
        // D8: when Slack is not connected, no workspace is known.
        const after: Status = { ...before, connected: connected ?? before.connected, error, stderr, ...(connected === false ? { workspace: null } : {}) }
        await writeStatus(after)
        return after.connected !== before.connected || after.error !== before.error || after.stderr !== before.stderr
      })
    } catch (err) {
      log(`slack: status.json could not be written: ${errorText(err)}`)
    }
    if (moved) emitChange()
    return { ok: false, routed: 0, unrouted: 0 }
  }

  /**
   * S4, the commit: under the lock, the lists first, with each routed entry reserving its inbox file
   * name (delivered false), then status.json. Pending hand-overs an earlier run left (a crash, a
   * drafter waiting for memory) come back as jobs too, unless one is running now. The drafts and the
   * inbox files follow, one job at a time (`handOver`). The workspace is this answer's (D8).
   */
  async function commit(messages: Message[], workspace: string | null, start: Date): Promise<Committed> {
    const projects = routable()
    const signals = await Promise.all(projects.map(p => signalsOf(p)))
    return locked(async (): Promise<Committed> => {
      const before = await readStatus(config.model)
      const kept = prune(await readSeen(), await readUnrouted(), start)
      const routes = await readRoutes()
      const seen: Seen = kept.seen
      // An id whose entry is gone (a crash between two writes) or was routed by hand leaves the list.
      const unrouted = [...new Set(kept.unrouted)].filter(id => isUnrouted(seen, id))
      const jobs: Job[] = []
      for (const [id, entry] of Object.entries(seen)) {
        const project = isPending(entry) && !inFlight.has(id) ? projects.find(p => p.name === entry.project) : undefined
        if (project) jobs.push({ project, id, entry, fresh: false, learn: false })
      }
      let added = 0
      for (const m of messages) {
        const id = idOf(m)
        if (Object.hasOwn(seen, id)) continue
        const decision = routeMessage(m, signals, routes)
        const project = decision.project === null ? undefined : projects.find(p => p.name === decision.project)
        if (project) {
          const entry: Entry = { ...m, seenAt: start.toISOString(), project: project.name, inbox: inboxName(start), delivered: false }
          seen[id] = entry
          jobs.push({ project, id, entry, fresh: true, learn: false })
        } else {
          seen[id] = { ...m, seenAt: start.toISOString(), project: null }
          unrouted.push(id)
          added += 1
        }
      }
      await writeUnrouted(unrouted)
      await writeSeen(seen)
      await writeStatus({ connected: true, lastCheck: start.toISOString(), error: null, model: config.model, workspace, stderr: null })
      return { jobs, added, pruned: kept.pruned, statusMoved: !before.connected || before.error !== null }
    })
  }

  /**
   * I-11: the draft first (a draft already there is used, else the drafter writes one, below 3 GB
   * free memory it waits), always written to drafts/ even when the drafter failed, then the inbox
   * file that names it, then the entry marked delivered and, for a route by hand, the learned channel.
   * A fresh hand-over that fails goes back to the unrouted list, where the owner can route it by
   * hand; a pending one that fails stays pending for the next check.
   */
  async function handOver(job: Job, at: Date): Promise<HandedOver> {
    const { project, id, entry } = job
    inFlight.add(id)
    try {
      const home = project.home
      let path = await findDraft(home, id)
      let drafterError: string | null = null
      if (path === null) {
        const made = await oneDraft(async () => {
          const free = await freeMemory()
          if (free < MIN_FREE_BYTES) return { free }
          const result = await draft({ project, message: entry }).catch((err: unknown) => ({ ok: false as const, why: errorText(err) }))
          const written = join(home, 'drafts', draftName(project.name, id, at))
          await writeDraft(written, toLine(entry), result.ok ? result.text : '')
          return { written, error: result.ok ? null : oneLine(result.why) }
        })
        if ('free' in made) {
          log(`slack: a hand-over waits for free memory: ${(made.free / 1024 ** 3).toFixed(1)} GB free, ${MIN_FREE_BYTES / 1024 ** 3} GB needed`)
          return 'waiting'
        }
        path = made.written
        drafterError = made.error
      }
      const text = inboxText(project.repo, entry, path, drafterError)
      await locked(async () => {
        const inbox = await deliver(home, entry.inbox as string, text, at)
        const seen = await readSeen()
        await writeSeen({ ...seen, [id]: { ...(seen[id] ?? entry), inbox, delivered: true } })
        if (job.learn) {
          // D3: the owner's route teaches the channel. The route stands if this write fails.
          try {
            await writeRoutes({ ...(await readRoutes()), [entry.channelId]: project.name })
          } catch (err) {
            log(`slack: routes.json could not be written, so the channel was not learned: ${errorText(err)}`)
          }
        }
      })
      return 'delivered'
    } catch (err) {
      if (!job.fresh) {
        // An earlier run may have written its file: sending it back to unrouted could hand it over twice.
        log(`slack: a pending hand-over could not be finished, so the next check tries again: ${errorText(err)}`)
        return 'waiting'
      }
      log(`slack: an inbox file could not be written, so its message waits in unrouted: ${errorText(err)}`)
      try {
        await locked(async () => {
          const seen = await readSeen()
          const ids = await readUnrouted()
          await writeSeen({ ...seen, [id]: unroute(seen[id] ?? entry) })
          await writeUnrouted([...new Set([...ids, id])])
        })
      } catch (undo) {
        log(`slack: a failed hand-over could not be put back in unrouted: ${errorText(undo)}`)
      }
      return 'unrouted'
    } finally {
      inFlight.delete(id)
    }
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
    const settings = readSlackSettings()
    const out = await runCli({ bin, args: argsOf(config, pluginIds(config, settings).slack), cwd: slackDir(), input: fillPrompt(template, since, start, settings.names), timeoutMs })
    const stderr = lastLines(out.stderr, 5)
    if (out.spawnError !== null) return fail('spawn', `claude could not start: ${oneLine(out.spawnError)}`)
    if (out.timedOut) return fail('timeout', `claude did not answer within ${Math.round(timeoutMs / 1000)} s`, undefined, stderr)
    if (out.tooLarge) return fail('output-too-large', 'claude printed more than the watcher reads', undefined, stderr)
    if (out.code !== 0) {
      const how = out.code === null ? `on ${out.signal ?? 'a signal'}` : String(out.code)
      return fail(`exit ${how}`, `claude exited ${how}${out.stderr.trim() ? `: ${lastLine(out.stderr)}` : ''}`, undefined, stderr)
    }
    const parsed = parseEnvelope(out.stdout)
    if (parsed.kind === 'disconnected') return fail('not-connected', `Slack is not connected: ${parsed.why}`, false, stderr)
    if (parsed.kind === 'error') return fail(parsed.cli ? 'cli-error' : 'bad-json', parsed.error, undefined, stderr)
    const names = ownerNames(parsed.owner, settings.names)
    const kept = parsed.messages.filter(m => keeps(m, parsed.owner?.id ?? null, names))
    let committed: Committed
    try {
      committed = await commit(kept, parsed.workspace, start)
    } catch (err) {
      return fail('state', errorText(err))
    }
    const files = new Map<string, number>()
    let routed = 0
    let unrouted = committed.added
    for (const job of committed.jobs) {
      const done = await handOver(job, start)
      if (done === 'delivered') {
        routed += 1
        files.set(job.project.name, (files.get(job.project.name) ?? 0) + 1)
      } else if (done === 'unrouted') {
        unrouted += 1
      }
    }
    for (const [project, count] of files) {
      if (!(await nudge(project))) log(`slack: STAR was not reached: ${count} inbox file(s) wait for its next tick`)
    }
    if (parsed.messages.length > kept.length) log(`slack check: ${parsed.messages.length - kept.length} dropped by the filter`)
    log(`slack check: ${parsed.messages.length} found, ${routed} routed, ${unrouted} unrouted, ${committed.pruned} pruned`)
    if (routed + unrouted + committed.pruned > 0 || committed.statusMoved) emitChange()
    return { ok: true, routed, unrouted }
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
    if (everyMs === 0) {
      if (!offLogged) log('slack: the watcher is off (slack.everyMin is 0)')
      offLogged = true
      return
    }
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

  /** STAR has not read the hand-over yet: its inbox file is still there. */
  const inboxHeld = (home: string, name: string | undefined): Promise<boolean> =>
    name === undefined ? Promise.resolve(false) : stat(join(home, 'inbox', name)).then(() => true, () => false)

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
      if (reply.finished && entry.delivered !== false && !(await inboxHeld(project.home, entry.inbox))) continue
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
   * reserves), then the answer: 200 {project, drafting: true}. The draft, the inbox file, the
   * learned channel (D3) and the nudge follow in the background (`handOver`). A crash after the
   * commit leaves a pending hand-over the next check finishes (S4).
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
        inFlight.add(id)
        await dropFromUnrouted()
        return { job: { project, id, entry: routed, fresh: true, learn: true }, at }
      })
    } catch (err) {
      log(`slack: a route failed: ${errorText(err)}`)
      return { status: 500, json: { error: errorText(err) } }
    }
    if ('res' in done) return done.res
    emitChange()
    if ('project' in done) {
      log('slack: 1 message dropped by hand')
      return { status: 200, json: { project: DROPPED } }
    }
    const { job, at } = done
    inBackground(
      (async (): Promise<void> => {
        const result = await handOver(job, at)
        if (result === 'delivered') {
          const nudged = await nudge(job.project.name)
          log(`slack: 1 message routed by hand${nudged ? '' : '; STAR was not reached'}`)
        }
        emitChange()
      })(),
    )
    return { status: 200, json: { project: job.project.name, drafting: true } }
  }

  api.route('GET', '/api/slack', async () => ({ status: 200, json: await listing() }))
  api.route('POST', '/api/slack/check', async () => {
    if (everyMs === 0) return { status: 409, json: { error: 'the Slack watcher is off: slack.everyMin is 0' } }
    const outcome = await check()
    if (outcome === null) return { status: 409, json: { error: 'a check is already running' } }
    return { status: 200, json: { ...outcome, status: await statusOrDefault() } }
  })
  api.route('POST', '/api/slack/:id/route', routeOne)

  return { check, start, stop, idle, everyMs }
}
