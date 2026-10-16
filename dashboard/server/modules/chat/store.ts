// The chat thread is HOME_DIR/chat/, one file per message, never rewritten (I-2 of the master plan);
// the owner's messages also go to HOME_DIR/inbox/ for STAR (I-3).
import { randomBytes } from 'node:crypto'
import { link, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises'
import { basename, dirname, join } from 'node:path'

export type ChatMessage = { id: string; who: 'me' | 'star'; at: string; replyTo: string | null; text: string }

export const MESSAGE_ID = /^[0-9]{8}T[0-9]{6}Z-(me|star)-[0-9a-f]{4}$/

const hex4 = (): string => randomBytes(2).toString('hex')

export function isoSeconds(at: Date): string {
  return at.toISOString().replace(/\.\d+Z$/, 'Z')
}

export function stamp(at: Date): string {
  return isoSeconds(at).replace(/[-:]/g, '')
}

export function messageText(m: ChatMessage): string {
  return `id: ${m.id}\nwho: ${m.who}\nat: ${m.at}\nreplyTo: ${m.replyTo ?? '-'}\n---\n${m.text}\n`
}

export function parseMessage(name: string, content: string): ChatMessage | null {
  if (!name.endsWith('.md')) return null
  const nameId = name.slice(0, -3)
  if (!MESSAGE_ID.test(nameId)) return null
  const lines = content.split('\n')
  const end = lines.indexOf('---')
  if (end < 0) return null
  const header = lines.slice(0, end)
  if (header.length !== 4) return null
  const fields: Record<string, string> = {}
  for (const [i, key] of ['id', 'who', 'at', 'replyTo'].entries()) {
    const prefix = `${key}: `
    if (!header[i].startsWith(prefix)) return null
    fields[key] = header[i].slice(prefix.length)
  }
  if (fields['id'] !== nameId) return null
  if (fields['who'] !== 'me' && fields['who'] !== 'star') return null
  if (Number.isNaN(Date.parse(fields['at']))) return null
  const replyTo = fields['replyTo']
  if (replyTo !== '-' && !MESSAGE_ID.test(replyTo)) return null
  return {
    id: nameId,
    who: fields['who'],
    at: fields['at'],
    replyTo: replyTo === '-' ? null : replyTo,
    text: lines.slice(end + 1).join('\n').trimEnd(),
  }
}

export function chatInboxText(repo: string, id: string, text: string): string {
  const body = text
    .replace(/\r/g, '')
    .split('\n')
    .map(line => `  ${line}\n`)
    .join('')
  return `repo: ${repo}\nchat: ${id}\ntext: |\n${body}`
}

function errCode(err: unknown): string | undefined {
  return (err as { code?: string }).code
}

/** Writes a file through a temp file and hard link, so STAR never reads half a file and the link never overwrites. */
export async function linkNew(path: string, content: string): Promise<boolean> {
  await mkdir(dirname(path), { recursive: true })
  const tmp = join(dirname(path), `.${basename(path)}.${process.pid}.${hex4()}.tmp`)
  try {
    await writeFile(tmp, content, { flag: 'wx' })
    try {
      await link(tmp, path)
      return true
    } catch (err) {
      if (errCode(err) === 'EEXIST') return false
      throw err
    }
  } finally {
    await rm(tmp, { force: true })
  }
}

export async function writeMine(home: string, text: string, now: Date = new Date()): Promise<ChatMessage> {
  for (let i = 0; i < 20; i++) {
    const m: ChatMessage = { id: `${stamp(now)}-me-${hex4()}`, who: 'me', at: isoSeconds(now), replyTo: null, text }
    if (await linkNew(join(home, 'chat', `${m.id}.md`), messageText(m))) return m
  }
  throw new Error('no free chat file name after 20 tries')
}

export async function writeInbox(home: string, kind: 'chat' | 'control', content: string, now: Date = new Date()): Promise<string> {
  for (let i = 0; i < 20; i++) {
    const name = `${stamp(now)}-${kind}-${hex4()}.md`
    if (await linkNew(join(home, 'inbox', name), content)) return name
  }
  throw new Error('no free inbox file name after 20 tries')
}

export async function readThread(home: string): Promise<ChatMessage[]> {
  const dir = join(home, 'chat')
  let entries
  try {
    entries = await readdir(dir, { withFileTypes: true })
  } catch {
    return []
  }
  const names = entries.filter(e => e.isFile() && e.name.endsWith('.md')).map(e => e.name).sort()
  const out: ChatMessage[] = []
  for (const name of names) {
    let content: string
    try {
      content = await readFile(join(dir, name), 'utf8')
    } catch {
      continue
    }
    const m = parseMessage(name, content)
    if (m) out.push(m)
  }
  return out
}

export function pageOf(thread: readonly ChatMessage[], before: string | null, limit: number): { messages: ChatMessage[]; hasMore: boolean } {
  const older = before ? thread.filter(m => m.id < before) : thread
  const messages = older.slice(-limit)
  return { messages, hasMore: older.length > messages.length }
}

export async function repoOf(home: string, fallback: string): Promise<string> {
  try {
    const raw = JSON.parse(await readFile(join(home, 'star.json'), 'utf8')) as { project?: { repo?: unknown } }
    const repo = raw.project?.repo
    return typeof repo === 'string' && repo !== '' ? repo : fallback
  } catch {
    return fallback
  }
}
