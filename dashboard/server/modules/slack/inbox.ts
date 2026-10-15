// D1 and D9: the slack: inbox file STAR reads. Its name is <UTC YYYYMMDDTHHMMSSZ>-slack-<4 hex>.md
// in <home>/inbox/, never an existing name. The text goes to a temp file (not *.md, so STAR never
// reads it) and is hard-linked in under its name: STAR never reads half a file, and the link fails
// rather than overwrite one.
import { randomBytes } from 'node:crypto'
import { link, mkdir, rm, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

import type { Message } from './state.ts'

const flat = (text: string): string => text.replace(/\r/g, '').replace(/\n/g, ' ')
const block = (text: string): string[] =>
  text
    .replace(/\r/g, '')
    .split('\n')
    .map(line => `    ${line}`)

/** S2: "a DM" for a DM or a group DM, else "#<name>". */
export function channelLabel(channelId: string, channel: string): string {
  const name = flat(channel).trim()
  if (channelId.startsWith('D') || /^a dm$/i.test(name)) return 'a DM'
  return `#${name.replace(/^#+/, '')}`
}

export function inboxText(repo: string, m: Message): string {
  const lines = [
    `repo: ${flat(repo)}`,
    'slack:',
    `  id: ${m.channelId}-${m.ts}`,
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

export async function writeInbox(home: string, text: string, at: Date = new Date()): Promise<string> {
  const dir = join(home, 'inbox')
  await mkdir(dir, { recursive: true })
  const tmp = join(dir, `.slack-${process.pid}-${randomBytes(4).toString('hex')}.tmp`)
  await writeFile(tmp, text, { flag: 'wx' })
  try {
    for (let i = 0; i < 20; i += 1) {
      const file = join(dir, `${stamp(at)}-slack-${randomBytes(2).toString('hex')}.md`)
      try {
        await link(tmp, file)
        return file
      } catch (err) {
        if ((err as { code?: unknown }).code !== 'EEXIST') throw err
      }
    }
    throw new Error('no free inbox file name after 20 tries')
  } finally {
    await rm(tmp, { force: true })
  }
}