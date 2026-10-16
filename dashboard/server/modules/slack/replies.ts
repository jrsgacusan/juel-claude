// D5 for GET /api/slack: a routed message's reply is the project's drafts/*-slack-*.md file whose
// first line is `to: slack <channelId> <threadTs, or ts>`, and its loop the last open slack-reply
// item of open-loops.md (read through hooks/star.ts) whose `draft:` body line names that draft (by its file name). Every message in
// a thread shares that first line, so a draft named after another message's id is never this
// message's. A draft with no open item is a finished reply; when open-loops.md is missing or does
// not parse, a draft counts as open (loopId null).
import { readdir, readFile } from 'node:fs/promises'
import { basename, join } from 'node:path'

import { parseQueue } from '../../../../hooks/star.ts'
import type { Message } from './state.ts'

export type Draft = { name: string; to: string }
export type OpenReply = { id: string; body: readonly string[] }
export type Reply = { draftPath: string | null; loopId: string | null; finished: boolean }

export async function readDrafts(home: string): Promise<Draft[]> {
  let names: string[]
  try {
    names = (await readdir(join(home, 'drafts'))).filter(name => /-slack-.+\.md$/.test(name)).sort()
  } catch {
    return []
  }
  const drafts: Draft[] = []
  for (const name of names) {
    try {
      const text = await readFile(join(home, 'drafts', name), 'utf8')
      drafts.push({ name, to: (text.split('\n')[0] ?? '').trim().replace(/\s+/g, ' ') })
    } catch {
      // A draft that cannot be read matches nothing.
    }
  }
  return drafts
}

/** The open (unanswered) slack-reply items, or null when open-loops.md is missing or does not parse. */
export async function readOpenReplies(home: string): Promise<OpenReply[] | null> {
  let text: string
  try {
    text = await readFile(join(home, 'open-loops.md'), 'utf8')
  } catch {
    return null
  }
  const queue = parseQueue(text)
  if (!queue.ok) return null
  return queue.value.needs.filter(need => need.kind === 'slack-reply' && need.answer === '').map(need => ({ id: need.id, body: need.body }))
}

/** A draft STAR named after one message: <date>-<project>-slack-<channelId>-<ts>.md. */
const NAMED = /-slack-[A-Za-z0-9]+-\d+\.\d+\.md$/

/** The draft file name an open item's `draft: <path>` body line names, else null. */
const draftOf = (line: string): string | null => {
  const value = /^draft:\s*(.+)$/.exec(line.trim())?.[1]
  return value === undefined ? null : basename(value.trim())
}

export function replyOf(message: Message, id: string, drafts: Draft[], loops: OpenReply[] | null): Reply {
  const to = `to: slack ${message.channelId} ${message.threadTs ?? message.ts}`
  const matching = drafts.filter(draft => draft.to === to)
  const draft = matching.find(d => d.name.endsWith(`-slack-${id}.md`)) ?? matching.filter(d => !NAMED.test(d.name)).at(-1)
  if (!draft) return { draftPath: null, loopId: null, finished: false }
  const draftPath = `drafts/${draft.name}`
  if (loops === null) return { draftPath, loopId: null, finished: false }
  const loop = loops.findLast(open => open.body.some(line => draftOf(line) === draft.name))
  return loop ? { draftPath, loopId: loop.id, finished: false } : { draftPath, loopId: null, finished: true }
}
