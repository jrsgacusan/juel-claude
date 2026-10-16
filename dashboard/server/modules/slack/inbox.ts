// D1 and D9: the slack: inbox file STAR reads, <UTC YYYYMMDDTHHMMSSZ>-slack-<4 hex>.md in
// <home>/inbox/. The text goes to a temp file (not *.md, so STAR never reads it) and is hard-linked
// in under its name: STAR never reads half a file, and the link fails rather than overwrite one.
// deliver() hands one message over, at least once, under the name seen.json reserved for it (S4):
// STAR's slack-handled.sh drops a repeat. The drafts folder is never read here (I-11).
import { randomBytes } from 'node:crypto'
import { link, mkdir, readFile, rm, writeFile } from 'node:fs/promises'
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

/** I-11: `draft` is the absolute path of the draft file written before the hand-over; `drafterError` why the drafter failed. */
export function inboxText(repo: string, m: Message, draft: string, drafterError: string | null): string {
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
    `  draft: ${flat(draft)}`,
    ...(drafterError === null ? [] : [`  drafterError: ${flat(drafterError)}`]),
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

const codeOf = (err: unknown): unknown => (err as { code?: unknown }).code

/**
 * Links the text into `dir` under `first`. A file with this exact text already there is this
 * hand-over (a crash came before the entry was marked delivered). A file there when the link runs
 * and gone when it is read was consumed by STAR in between: the same name is tried again. Only a
 * file with other text gives the text a fresh name. Returns the name the file has.
 */
export async function place(dir: string, text: string, first: string, at: Date): Promise<string> {
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
        if (codeOf(err) !== 'EEXIST') throw err
      }
      let held: string | null
      try {
        held = await readFile(join(dir, name), 'utf8')
      } catch (err) {
        if (codeOf(err) !== 'ENOENT') throw err
        held = null
      }
      if (held === text) return name
      if (held === null) continue
      name = inboxName(at)
    }
    throw new Error('no free inbox file name after 20 tries')
  } finally {
    await rm(tmp, { force: true })
  }
}

/**
 * Hands a message to the STAR folder `home` as the inbox file `name`. This is at least once, not
 * exactly once: when STAR ingested a pending hand-over's file already, the name is free again and
 * the link writes the message a second time; STAR's `skills/star/slack-handled.sh` drops that copy.
 * Returns the inbox file's name.
 */
export const deliver = (home: string, name: string, text: string, at: Date = new Date()): Promise<string> => place(join(home, 'inbox'), text, name, at)
