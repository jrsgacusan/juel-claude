import fs from 'node:fs'
import path from 'node:path'

import { parseLedger, parseQueue, parseStar } from '../../../hooks/star.ts'
import type { LedgerRow, Queue, Star } from '../../../hooks/star.ts'
import { Unreadable } from '../http.ts'
import { readText } from './files.ts'

export type StarFile = { star: Star; raw: Record<string, unknown> }

export function readStar(home: string): StarFile {
  const text = readText(home, 'star.json')
  const parsed = parseStar(text)
  if (!parsed.ok) throw new Unreadable('star.json', parsed.why)
  return { star: parsed.value, raw: JSON.parse(text) as Record<string, unknown> }
}

export function readLedger(home: string): LedgerRow[] {
  const parsed = parseLedger(readText(home, 'ledger.md'))
  if (!parsed.ok) throw new Unreadable('ledger.md', parsed.why)
  return parsed.value
}

export function readQueue(home: string): Queue {
  const parsed = parseQueue(readText(home, 'open-loops.md'))
  if (!parsed.ok) throw new Unreadable('open-loops.md', parsed.why)
  return parsed.value
}

/** A Resume value, null for `-` or nothing. */
export const valueOf = (resume: Readonly<Record<string, string>>, key: string): string | null => {
  const v = resume[key]
  return v && v !== '-' ? v : null
}

export const tickOf = (resume: Readonly<Record<string, string>>): string | null => valueOf(resume, 'last tick')

/** The newest `control: away` or `control: back` file still in inbox/ (STAR deletes a control file once it has applied it), else null. */
export function awayPendingOf(home: string): 'away' | 'back' | null {
  const dir = path.join(home, 'inbox')
  let names: string[]
  try {
    names = fs.readdirSync(dir).filter(name => /^[^.].*-control-.*\.md$/.test(name)).sort().reverse()
  } catch {
    return null
  }
  for (const name of names) {
    let text: string
    try {
      text = fs.readFileSync(path.join(dir, name), 'utf8').trim()
    } catch {
      continue
    }
    if (text === 'control: away') return 'away'
    if (text === 'control: back') return 'back'
  }
  return null
}
