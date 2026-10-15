// The watcher's state, plain JSON under ~/.juel/slack/ (from os.homedir() at every call, so a test
// points HOME at a temp folder): seen.json, routes.json, unrouted.json and status.json. A missing
// file is its default; a file that cannot be read or does not hold what the watcher writes is a
// StateError, never read as empty (S6: that would raise every message again). Writes are atomic.
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
/** A seen.json entry (D5): the message, when it was first seen, and its project (null while unrouted, "none" once dropped). */
export type Entry = Message & { seenAt: string; project: string | null }
export type Seen = Record<string, Entry>
/** routes.json: channel id to project name, learned only from the owner's routes (D3). */
export type Routes = Record<string, string>
export type Status = { connected: boolean; lastCheck: string | null; error: string | null; model: string; workspace: string | null }

export const MINUTE_MS = 60_000
export const DAY_MS = 24 * 60 * MINUTE_MS
export const KEEP_MS = 30 * DAY_MS

export class StateError extends Error {}

export const juelDir = (): string => join(homedir(), '.juel')
export const slackDir = (): string => join(juelDir(), 'slack')
export const idOf = (m: { channelId: string; ts: string }): string => `${m.channelId}-${m.ts}`
export const defaultStatus = (model: string): Status => ({ connected: false, lastCheck: null, error: null, model, workspace: null })

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

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
  typeof v.seenAt === 'string' &&
  typeof v.channelId === 'string' &&
  typeof v.ts === 'string' &&
  (v.project === null || typeof v.project === 'string')

export async function readSeen(): Promise<Seen> {
  const data = await readJson('seen.json')
  if (data === undefined) return {}
  if (!isObject(data) || !Object.values(data).every(isEntry)) throw new StateError('seen.json does not hold what the watcher wrote')
  return data as Seen
}
export const writeSeen = (seen: Seen): Promise<void> => writeJson('seen.json', seen)

export async function readRoutes(): Promise<Routes> {
  const data = await readJson('routes.json')
  if (data === undefined) return {}
  if (!isObject(data) || !Object.values(data).every(v => typeof v === 'string')) throw new StateError('routes.json does not hold what the watcher wrote')
  return data as Routes
}
export const writeRoutes = (routes: Routes): Promise<void> => writeJson('routes.json', routes)

export async function readUnrouted(): Promise<string[]> {
  const data = await readJson('unrouted.json')
  if (data === undefined) return []
  if (!Array.isArray(data) || !data.every(v => typeof v === 'string')) throw new StateError('unrouted.json does not hold what the watcher wrote')
  return data as string[]
}
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
