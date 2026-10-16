// The watcher's state, plain JSON under ~/.juel/slack/ (from os.homedir() at every call, so a test
// points HOME at a temp folder): seen.json, routes.json, unrouted.json and status.json. A missing
// file is its default. A file that cannot be read, is not JSON, or does not hold what the watcher
// writes (every seen.json entry a whole message) is a StateError, never read as empty (S6: that
// would raise every message again). status.json fields of the wrong type read as their defaults.
// Writes are atomic: a temp file, then a rename.
import { randomBytes } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'

/** One message as the check's answer gives it (the item's step 2). */
export type Message = {
  channelId: string
  channel: string
  ts: string
  threadTs: string | null
  from: string
  text: string
  permalink: string
  thread: string[]
}
/**
 * A seen.json entry (D5): the message, when it was first seen, and its project (null while unrouted,
 * "none" once dropped). A routed entry also holds the inbox file name it reserved (`inbox`) and
 * whether that hand-over finished (`delivered`); an entry without them counts as delivered.
 */
export type Entry = Message & { seenAt: string; project: string | null; inbox?: string; delivered?: boolean }
export type Seen = Record<string, Entry>
/** routes.json: channel id to project name, learned only from the owner's routes (D3). */
export type Routes = Record<string, string>
export type Status = { connected: boolean; lastCheck: string | null; error: string | null; model: string; workspace: string | null }

export const MINUTE_MS = 60_000
export const DAY_MS = 24 * 60 * MINUTE_MS
export const KEEP_MS = 30 * DAY_MS

export class StateError extends Error {}

const juelDir = (): string => join(homedir(), '.juel')
export const slackDir = (): string => join(juelDir(), 'slack')
export const idOf = (m: { channelId: string; ts: string }): string => `${m.channelId}-${m.ts}`
export const defaultStatus = (model: string): Status => ({ connected: false, lastCheck: null, error: null, model, workspace: null })
export const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
export const oneLine = (text: string, max = 200): string => text.replace(/\s+/g, ' ').trim().slice(0, max)
/** The message is still waiting for a project: neither routed nor dropped. */
export const isUnrouted = (seen: Seen, id: string): boolean => Object.hasOwn(seen, id) && seen[id]?.project === null
/** An inbox file name the watcher writes: <UTC YYYYMMDDTHHMMSSZ>-slack-<4 hex>.md. */
export const INBOX_NAME = /^\d{8}T\d{6}Z-slack-[0-9a-f]{4}\.md$/
/** A routed entry whose inbox file is reserved but not yet known to be written. */
export const isPending = (entry: Entry): boolean =>
  typeof entry.project === 'string' && entry.project !== 'none' && typeof entry.inbox === 'string' && entry.delivered === false
/** The entry back to waiting for a project, without a reservation. */
export function unroute(entry: Entry): Entry {
  const { inbox: _inbox, delivered: _delivered, ...rest } = entry
  return { ...rest, project: null }
}

const CHANNEL_ID = /^[A-Z0-9]+$/i
const TS = /^\d+\.\d+$/
const STRINGS = ['channelId', 'channel', 'ts', 'from', 'text', 'permalink']

/** Why a value is not a message of the item's step 2 (with S10's path-safe ids), else null. */
export function messageProblem(item: unknown): string | null {
  if (!isObject(item)) return 'not an object'
  for (const key of STRINGS) if (typeof item[key] !== 'string') return `${key} is not a string`
  if (!CHANNEL_ID.test(item.channelId as string)) return 'channelId is not a Slack id'
  if (!TS.test(item.ts as string)) return 'ts is not a Slack ts'
  if (item.threadTs !== null && !(typeof item.threadTs === 'string' && TS.test(item.threadTs))) return 'threadTs is not a Slack ts or null'
  if (!(item.permalink as string).startsWith('https://')) return 'permalink is not an https link'
  if (!Array.isArray(item.thread) || item.thread.length > 5 || !item.thread.every(line => typeof line === 'string')) {
    return 'thread is not at most 5 strings'
  }
  return null
}

/** The file's JSON, undefined when it does not exist. */
async function readJson(name: string): Promise<unknown> {
  let text: string
  try {
    text = await readFile(join(slackDir(), name), 'utf8')
  } catch (err) {
    const code = (err as { code?: unknown }).code
    if (code === 'ENOENT') return undefined
    throw new StateError(`${name} is not readable (${String(code ?? err)})`)
  }
  try {
    return JSON.parse(text) as unknown
  } catch {
    throw new StateError(`${name} is not JSON`)
  }
}

/** The file's JSON when `valid` accepts it; `empty` when the file does not exist. */
async function readValid<T>(name: string, empty: T, valid: (data: unknown) => boolean): Promise<T> {
  const data = await readJson(name)
  if (data === undefined) return empty
  if (!valid(data)) throw new StateError(`${name} does not hold what the watcher wrote`)
  return data as T
}

async function writeJson(name: string, value: unknown): Promise<void> {
  const dir = slackDir()
  await mkdir(dir, { recursive: true })
  const file = join(dir, name)
  const tmp = `${file}.${process.pid}.${randomBytes(3).toString('hex')}.tmp`
  try {
    await writeFile(tmp, `${JSON.stringify(value, null, 2)}\n`)
    await rename(tmp, file)
  } catch (err) {
    await rm(tmp, { force: true })
    throw err
  }
}

const isEntry = (v: unknown): boolean =>
  isObject(v) &&
  messageProblem(v) === null &&
  typeof v.seenAt === 'string' &&
  (v.project === null || typeof v.project === 'string') &&
  (v.inbox === undefined || (typeof v.inbox === 'string' && INBOX_NAME.test(v.inbox))) &&
  (v.delivered === undefined || typeof v.delivered === 'boolean')

export const readSeen = (): Promise<Seen> => readValid<Seen>('seen.json', {}, data => isObject(data) && Object.values(data).every(isEntry))
export const writeSeen = (seen: Seen): Promise<void> => writeJson('seen.json', seen)

export const readRoutes = (): Promise<Routes> =>
  readValid<Routes>('routes.json', {}, data => isObject(data) && Object.values(data).every(v => typeof v === 'string'))
export const writeRoutes = (routes: Routes): Promise<void> => writeJson('routes.json', routes)

export const readUnrouted = (): Promise<string[]> =>
  readValid<string[]>('unrouted.json', [], data => Array.isArray(data) && data.every(v => typeof v === 'string'))
export const writeUnrouted = (ids: string[]): Promise<void> => writeJson('unrouted.json', ids)

/** status.json (D8); `model` is always the configured one. */
export async function readStatus(model: string): Promise<Status> {
  const data = await readJson('status.json')
  if (data === undefined) return defaultStatus(model)
  if (!isObject(data)) throw new StateError('status.json does not hold what the watcher wrote')
  return {
    connected: data.connected === true,
    lastCheck: typeof data.lastCheck === 'string' ? data.lastCheck : null,
    error: typeof data.error === 'string' ? data.error : null,
    model,
    workspace: typeof data.workspace === 'string' ? data.workspace : null,
  }
}
export const writeStatus = (status: Status): Promise<void> => writeJson('status.json', status)

/** Drops the entries first seen more than 30 days before `now`, and their ids from the unrouted list. */
export function prune(seen: Seen, unrouted: string[], now: Date): { seen: Seen; unrouted: string[]; pruned: number } {
  const kept: Seen = {}
  let pruned = 0
  for (const [id, entry] of Object.entries(seen)) {
    const at = Date.parse(entry.seenAt)
    if (Number.isFinite(at) && now.getTime() - at > KEEP_MS) pruned += 1
    else kept[id] = entry
  }
  return { seen: kept, unrouted: unrouted.filter(id => Object.hasOwn(kept, id)), pruned }
}

/** ~/.juel/dashboard.json's slack.everyMin when it is a positive number, else 5. */
export function readEveryMin(): number {
  try {
    const data = JSON.parse(readFileSync(join(juelDir(), 'dashboard.json'), 'utf8')) as unknown
    const slack = isObject(data) ? data.slack : undefined
    const every = isObject(slack) ? slack.everyMin : undefined
    return typeof every === 'number' && Number.isFinite(every) && every > 0 ? every : 5
  } catch {
    return 5
  }
}
