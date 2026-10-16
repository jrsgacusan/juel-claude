import path from 'node:path'
import { readOptional } from './files.ts'

export type Step = { time: string | null; text: string }

/** progress/<item>.log as [{time, text}]: `<iso> <step> <words>` lines; a line with no time keeps time null. */
export function readProgress(home: string, item: string): Step[] {
  const text = readOptional(home, path.join('progress', `${item}.log`))
  if (text === undefined) return []
  return text
    .split('\n')
    .filter(l => l.trim())
    .map(l => {
      const m = /^(\d{4}-\d\d-\d\dT[\d:.]+Z)\s+(.*)$/.exec(l.trim())
      return m ? { time: m[1] ?? null, text: (m[2] ?? '').trim() } : { time: null, text: l.trim() }
    })
}
