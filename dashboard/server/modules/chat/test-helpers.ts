// Test scaffolding for the chat module: a throwaway STAR home and a thread written straight to disk.
import { mkdir, mkdtemp, realpath, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { messageText } from './store.ts'
import type { ChatMessage } from './store.ts'
import type { Project } from './types.ts'

export type World = { root: string; home: string; project: Project }

export async function world(state: Project['state'] = 'running'): Promise<World> {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'chat-')))
  const home = join(root, 'star')
  await mkdir(home)
  await writeFile(join(home, 'star.json'), JSON.stringify({ project: { name: 'proj', repo: '/w/proj' }, terminal: 'term_proj' }))
  return { root, home, project: { name: 'proj', repo: join(root, 'repo'), home, terminal: 'term_proj', state } }
}

export async function cleanup(w: World): Promise<void> {
  await rm(w.root, { recursive: true, force: true })
}

export const MSGS: ChatMessage[] = [
  { id: '20261017T010001Z-me-0001', who: 'me', at: '2026-10-17T01:00:01Z', replyTo: null, text: 'how is it going?' },
  { id: '20261017T010002Z-star-0002', who: 'star', at: '2026-10-17T01:00:02Z', replyTo: '20261017T010001Z-me-0001', text: 'Two rows **run**:\n\n- N-12\n- N-13' },
  { id: '20261017T010003Z-me-0003', who: 'me', at: '2026-10-17T01:00:03Z', replyTo: null, text: 'drop N-13' },
  { id: '20261017T010004Z-star-0004', who: 'star', at: '2026-10-17T01:00:04Z', replyTo: '20261017T010003Z-me-0003', text: 'Dropped N-13.' },
  { id: '20261017T010005Z-me-0005', who: 'me', at: '2026-10-17T01:00:05Z', replyTo: null, text: 'thanks' },
]

export async function writeThread(home: string, messages: readonly ChatMessage[]): Promise<void> {
  await mkdir(join(home, 'chat'), { recursive: true })
  for (const m of messages) await writeFile(join(home, 'chat', `${m.id}.md`), messageText(m))
}
