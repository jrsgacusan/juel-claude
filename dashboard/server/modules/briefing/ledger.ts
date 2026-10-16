// Read STAR's ledger the same way ledger.sh load() and hooks/star.ts parseLedger do. This module
// only reads it (D3); if STAR changes the format, a resume fails loudly instead of guessing.
import { join } from 'node:path'

import { message } from './claude.ts'
import { readText } from './store.ts'

const COLS = ['item', 'ref', 'project', 'worktree', 'state', 'stage', 'round', 'task', 'dispatch', 'restarts', 'pr', 'head', 'cursor', 'verify', 'counters', 'updated']

/** Returns every ledger row's ref in file order, or [] when STAR has not made a ledger yet. */
export async function ledgerRefs(home: string): Promise<string[]> {
  const path = join(home, 'ledger.md')
  let text: string | null
  try {
    text = await readText(path)
  } catch (err) {
    throw new Error(`${path} could not be read: ${message(err)}`)
  }
  if (text === null) return []

  const lines = text.split('\n')
  const head = lines.findIndex(line => line.trim().startsWith('| item |'))
  if (head < 0 || head + 1 >= lines.length || !lines[head + 1].trim().startsWith('|---')) {
    throw new Error(`${path} has no ledger table`)
  }
  const header = lines[head].trim().slice(1, -1).split('|').map(cell => cell.trim())
  if (header.length !== COLS.length || header.some((cell, i) => cell !== COLS[i])) {
    throw new Error(`${path}: the header is not STAR's ledger header`)
  }

  const refs: string[] = []
  for (let i = head + 2; i < lines.length; i++) {
    const line = lines[i].trim()
    if (!line) continue
    if (!line.startsWith('|')) break
    const cells = line.endsWith('|') ? line.slice(1, -1).split('|').map(cell => cell.trim()) : []
    if (cells.length !== COLS.length) throw new Error(`${path}:${i + 1}: a row has ${cells.length} cells, not 16`)
    refs.push(cells[1])
  }
  return refs
}
