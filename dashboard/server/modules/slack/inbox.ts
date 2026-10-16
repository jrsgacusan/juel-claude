// D1 and D9: the slack: inbox file STAR reads, <UTC YYYYMMDDTHHMMSSZ>-slack-<4 hex>.md in
// <home>/inbox/. The text goes to a temp file (not *.md, so STAR never reads it) and is hard-linked
// in under its name: STAR never reads half a file, and the link fails rather than overwrite one.
// deliver() hands one message over exactly once under the name seen.json reserved for it (S4).
import { randomBytes } from 'node:crypto'
import { link, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

import { idOf } from './state.ts'
import type { Message } from './state.ts'

const flat = (text: string): string => text.replace(/\r/g, '').replace(/\n/g, ' ')
const block = (text: string): string[] =>
  text
    .replace(/\r/g, '')
    .split('\n')
    .map(line => `    ${line}`)

/** S2: "a DM" when the id is a DM's (D...) or the model said "a DM" (how a group DM arrives), else "#<name>". */
export function channelLabel(channelId: string, channel: string): string {
  const name = flat(channel).trim()
  if (channelId.startsWith('D') || /^a dm$/i.test(name)) return 'a DM'
  return `#${name.replace(/^#+/, '')}`
}

export function inboxText(repo: string, m: Message): string {
  const lines = [
    `repo: ${flat(repo)}`,
    'slack:',
    `  id: ${idOf(m)}`,
    `  channel: ${channelLabel(m.channelId, m.channel)}`,
    `  channelId: ${m.channelId}`,
    `  ts: ${m.ts}`,
    `  threadTs: ${m.threadTs ?? '-'}`,
    `  from: ${flat(m.from)}`,
    `  permalink: ${flat(m.permalink)}`,
    '  text: |',
    ...block(m.text),
  ]
  if (m.thread.length > 0) lines.push('  thread: |', ...m.thread.flatMap(block))
  return `${lines.join('\n')}\n`
}

/** 2026-10-16T05:06:07.123Z as 20261016T050607Z. */
export const stamp = (at: Date): string => at.toISOString().replace(/\.\d{3}Z$/, 'Z').replace(/[-:]/g, '')

/** A fresh inbox file name for this time. */
export const inboxName = (at: Date): string => `${stamp(at)}-slack-${randomBytes(2).toString('hex')}.md`

/**
 * Links the text into `dir` under `first`. When a file with this exact text already holds the name,
 * that file is this hand-over (a crash came before the entry was marked delivered); a file with other
 * text gets the text a fresh name. Returns the name the file has.
 */
async function place(dir: string, text: string, first: string, at: Date): Promise<string> {
  await mkdir(dir, { recursive: true })
  const tmp = join(dir, `.slack-${process.pid}-${randomBytes(4).toString('hex')}.tmp`)
  await writeFile(tmp, text, { flag: 'wx' })
  try {
    let name = first
    for (let i = 0; i < 20; i += 1) {
      try {
        await link(tmp, join(dir, name))
        return name
      } catch (err) {
        if ((err as { code?: unknown }).code !== 'EEXIST') throw err
        if ((await readFile(join(dir, name), 'utf8').catch(() => null)) === text) return name
        name = inboxName(at)
      }
    }
    throw new Error('no free inbox file name after 20 tries')
  } finally {
    await rm(tmp, { force: true })
  }
}

/**
 * Hands message `id` to the STAR folder `home` as the inbox file `name`, exactly once: a reply STAR
 * already drafted for it (STAR writes the draft before it deletes the inbox file) means it was
 * handed over and nothing is written. Returns the inbox file's name.
 */
export async function deliver(home: string, name: string, id: string, text: string, at: Date = new Date()): Promise<string> {
  const drafts = await readdir(join(home, 'drafts')).catch((): string[] => [])
  if (drafts.some(draft => draft.endsWith(`-slack-${id}.md`))) return name
  return place(join(home, 'inbox'), text, name, at)
}
