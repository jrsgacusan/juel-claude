// D5 for GET /api/slack: a routed message's reply is the project's drafts/*-slack-*.md file whose
// first line is `to: slack <channelId> <threadTs, or ts>`, and its loop the open slack-reply item of
// open-loops.md (read through hooks/star.ts) whose body names that draft. A draft with no open item
// is a finished reply.
import { readdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'

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

export function replyOf(message: Message, id: string, drafts: Draft[], loops: OpenReply[] | null): Reply {
  const to = `to: slack ${message.channelId} ${message.threadTs ?? message.ts}`
  const matching = drafts.filter(draft => draft.to === to)
  const draft = matching.find(d => d.name.endsWith(`-slack-${id}.md`)) ?? matching[matching.length - 1]
  if (!draft) return { draftPath: null, loopId: null, finished: false }
  const draftPath = `drafts/${draft.name}`
  if (loops === null) return { draftPath, loopId: null, finished: false }
  const open = loops.filter(loop => loop.body.some(line => line.includes(draft.name)))
  const loop = open[open.length - 1]
  return loop ? { draftPath, loopId: loop.id, finished: false } : { draftPath, loopId: null, finished: true }
}