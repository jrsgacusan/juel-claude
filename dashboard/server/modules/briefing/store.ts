// A briefing on disk: <STAR folder>/briefings/<id>/ holding transcript.jsonl, draft.json, session
// and, once a ticket exists, created.json (brief D7, D8).
import { appendFile, mkdir, readFile, readdir, rename, rm, stat, truncate, writeFile } from 'node:fs/promises'
import { basename, dirname, join } from 'node:path'

import { message } from './claude.ts'
import { isId, newId } from './ids.ts'
import { parseTicket } from './ticket.ts'
import type { Ticket } from './ticket.ts'

export type Turn = { who: 'me' | 'agent'; text: string; files: string[]; at: string }
export type Created = {
  tracker: string
  ref: string | null
  specPath: string | null
  url: string | null
  at: string
  /** STAR's inbox file for the ticket; null until it is written. Absent on a record this module could not read. */
  inbox?: string | null
  /**
   * 'creating' is written before anything is made and stays when the made ticket could not be
   * recorded, so a later press never makes a second one (D8); 'made' once the ticket is recorded.
   */
  state?: 'creating' | 'made'
}
export type Summary = { id: string; title: string; updatedAt: string; ref: string | null }

const errCode = (err: unknown): string | undefined => (err as { code?: string } | null)?.code

export function briefingsDir(home: string): string {
  return join(home, 'briefings')
}

/** The folder of briefing `id`, or null for a malformed id: checked before any path is built (D8). */
export function briefingDir(home: string, id: string): string | null {
  return isId(id) ? join(briefingsDir(home), id) : null
}

export async function isDir(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isDirectory()
  } catch {
    return false
  }
}

/** Writes a file that must not exist yet; false when it already did. */
export async function writeNew(path: string, content: string): Promise<boolean> {
  try {
    await writeFile(path, content, { flag: 'wx' })
    return true
  } catch (err) {
    if (errCode(err) === 'EEXIST') return false
    throw err
  }
}

/** Makes a new empty briefing folder and returns its id; an id already taken is drawn again. */
export async function createBriefing(home: string): Promise<string> {
  await mkdir(briefingsDir(home), { recursive: true })
  for (let tries = 0; tries < 100; tries++) {
    const id = newId()
    try {
      await mkdir(join(briefingsDir(home), id))
      return id
    } catch (err) {
      if (errCode(err) !== 'EEXIST') throw err
    }
  }
  throw new Error('no free briefing id after 100 tries')
}

/** The file's text, or null when it does not exist; any other read error is thrown. */
export async function readText(path: string): Promise<string | null> {
  try {
    return await readFile(path, 'utf8')
  } catch (err) {
    if (errCode(err) === 'ENOENT') return null
    throw err
  }
}

const isTurn = (value: unknown): value is Turn => {
  if (typeof value !== 'object' || value === null) return false
  const { who, text, files, at } = value as Record<string, unknown>
  return (who === 'me' || who === 'agent') && typeof text === 'string' && typeof at === 'string' && Array.isArray(files) && files.every(file => typeof file === 'string')
}

export async function readTurns(dir: string): Promise<Turn[]> {
  const turns: Turn[] = []
  for (const line of ((await readText(join(dir, 'transcript.jsonl'))) ?? '').split('\n')) {
    if (!line.trim()) continue
    let value: unknown
    try {
      value = JSON.parse(line)
    } catch {
      continue // a line torn by a crash mid-append
    }
    // A line that is not a turn (a hand edit) is skipped as well, so one bad line never breaks the list.
    if (isTurn(value)) turns.push(value)
  }
  return turns
}

export async function readDraft(dir: string): Promise<Ticket | null> {
  const text = await readText(join(dir, 'draft.json'))
  return text === null ? null : parseTicket(text)
}

export async function readCreated(dir: string): Promise<Created | null> {
  const text = await readText(join(dir, 'created.json'))
  if (text === null) return null
  try {
    const value: unknown = JSON.parse(text)
    if (typeof value === 'object' && value !== null) return value as Created
  } catch {
    // not JSON: counted as created below
  }
  // An unparseable created.json still counts as created: one briefing never makes two tickets.
  return { tracker: 'unknown', ref: null, specPath: null, url: null, at: '' }
}

export async function readSession(dir: string): Promise<string | null> {
  const session = (await readText(join(dir, 'session')))?.trim()
  return session ? session : null
}

export async function writeSession(dir: string, session: string): Promise<void> {
  await writeFile(join(dir, 'session'), `${session}\n`)
}

/** Forgets a session the CLI no longer has, so the next message starts a new one. */
export async function clearSession(dir: string): Promise<void> {
  await rm(join(dir, 'session'), { force: true })
}

/** Replaces a file in one rename, so a reader never sees half of it; the temp file goes on a failure. */
export async function replaceFile(path: string, content: string): Promise<void> {
  const tmp = join(dirname(path), `.${basename(path)}.${process.pid}.tmp`)
  try {
    await writeFile(tmp, content)
    await rename(tmp, path)
  } catch (err) {
    await rm(tmp, { force: true }).catch(() => {}) // the write's own error is the one to report
    throw err
  }
}

/** Replaces draft.json in one rename, so a reader never sees half a draft. */
export async function writeDraft(dir: string, draft: Ticket): Promise<void> {
  await replaceFile(join(dir, 'draft.json'), `${JSON.stringify(draft, null, 2)}\n`)
}

async function sizeOf(path: string): Promise<number | null> {
  try {
    return (await stat(path)).size
  } catch (err) {
    if (errCode(err) === 'ENOENT') return null
    throw err
  }
}

/**
 * Saves a finished turn as one change (D7): both transcript lines and the new draft land together,
 * or neither does. The draft is staged in a temp file, the lines appended, then the draft renamed
 * into place. On any failure the temp file goes and the transcript is cut back to its old length.
 */
export async function saveTurn(dir: string, turns: Turn[], draft: Ticket): Promise<void> {
  const transcript = join(dir, 'transcript.jsonl')
  const staged = join(dir, `.draft.json.${process.pid}.tmp`)
  const before = await sizeOf(transcript)
  try {
    await writeFile(staged, `${JSON.stringify(draft, null, 2)}\n`)
    await appendFile(transcript, turns.map(turn => `${JSON.stringify(turn)}\n`).join(''))
    await rename(staged, join(dir, 'draft.json'))
  } catch (err) {
    await rm(staged, { force: true }).catch(() => {}) // the save's own error is the one to report
    try {
      if ((await sizeOf(transcript)) !== before) {
        if (before === null) await rm(transcript, { force: true })
        else await truncate(transcript, before)
      }
    } catch (undo) {
      throw new Error(`${message(err)}; the transcript could not be put back: ${message(undo)}`)
    }
    throw err
  }
}

/** Writes created.json unless it exists; false when it already did. */
export async function writeCreated(dir: string, created: Created): Promise<boolean> {
  return writeNew(join(dir, 'created.json'), `${JSON.stringify(created, null, 2)}\n`)
}

/** Replaces created.json in one rename, so a reader never sees half a record. */
export async function rewriteCreated(dir: string, created: Created): Promise<void> {
  await replaceFile(join(dir, 'created.json'), `${JSON.stringify(created, null, 2)}\n`)
}

/** The list title (D8): the draft's title, else the owner's first turn cut to 60 characters. */
export function titleOf(draft: Ticket | null, turns: Turn[]): string {
  if (draft) return draft.title
  const first = turns.find(turn => turn.who === 'me')?.text.replace(/\s+/g, ' ').trim()
  return first ? first.slice(0, 60) : 'New briefing'
}

async function newestChange(dir: string): Promise<string | null> {
  try {
    let newest = (await stat(dir)).mtimeMs
    for (const name of await readdir(dir)) {
      try {
        newest = Math.max(newest, (await stat(join(dir, name))).mtimeMs)
      } catch {
        // removed between readdir and stat
      }
    }
    return new Date(newest).toISOString()
  } catch {
    return null
  }
}

/** Every briefing of a STAR folder, the most recently changed first. */
export async function listBriefings(home: string): Promise<Summary[]> {
  let names: string[]
  try {
    names = await readdir(briefingsDir(home))
  } catch (err) {
    if (errCode(err) === 'ENOENT') return []
    throw err
  }
  const summaries: Summary[] = []
  for (const id of names.filter(name => isId(name))) {
    const dir = join(briefingsDir(home), id)
    if (!(await isDir(dir))) continue
    const [draft, created, turns, updatedAt] = await Promise.all([readDraft(dir), readCreated(dir), readTurns(dir), newestChange(dir)])
    if (updatedAt === null) continue
    summaries.push({ id, title: titleOf(draft, turns), updatedAt, ref: created ? (created.ref ?? created.specPath) : null })
  }
  return summaries.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt) || b.id.localeCompare(a.id))
}
