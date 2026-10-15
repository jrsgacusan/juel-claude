import { run } from './proc.ts'

/** The handles `orca terminal list` shows (result.terminals[].handle), or null when it cannot be read. */
export async function listTerminals(): Promise<Set<string> | null> {
  const r = await run('orca', ['terminal', 'list', '--limit', '500', '--json'])
  if (r.code !== 0) return null
  try {
    const data = JSON.parse(r.stdout) as { result?: { terminals?: { handle?: unknown }[] } }
    const list = data.result?.terminals
    if (!Array.isArray(list)) return null
    return new Set(list.map(t => t.handle).filter((h): h is string => typeof h === 'string'))
  } catch {
    return null
  }
}

/** Wake STAR with `inbox`, as a hand-over does (D5). True only when Orca took it; a terminal it does
 * not list, or none, is false without sending. */
export async function nudge(terminal: string | null): Promise<boolean> {
  if (!terminal) return false
  const listed = await listTerminals()
  if (!listed || !listed.has(terminal)) return false
  const r = await run('orca', ['terminal', 'send', '--terminal', terminal, '--text', 'inbox', '--enter', '--json'])
  return r.code === 0
}
