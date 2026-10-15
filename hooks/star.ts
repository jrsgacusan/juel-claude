// Pure readers of STAR's state files, and the band text built from them. No `$` here: every
// function takes text and returns data, so a test (or a port of ledger.sh / loops.sh rules)
// checks it without a session. The parsing mirrors skills/star/ledger.sh load() and
// skills/star/loops.sh items()/answer_of(): when either script changes its format, this file
// changes in the same commit.

import type { StarBand } from '../types'

// ledger.sh COLS, in order: the header must match exactly or the ledger is "broken".
export const LEDGER_COLS = [
  'item', 'ref', 'project', 'worktree', 'state', 'stage', 'round', 'task', 'dispatch',
  'restarts', 'pr', 'head', 'cursor', 'verify', 'counters', 'updated',
] as const

// merge.sh / step-check.sh WORKER_STATES: a live worker owns the row.
export const WORKER_STATES = ['briefing', 'building', 'babysitting', 'posting'] as const
// Each stage's waiting state (SKILL.md "Each stage has a waiting state").
export const WAITING_STATES = ['inbox', 'brief-ready', 'queued', 'babysit-queued', 'post-queued'] as const

export type LedgerRow = {
  item: string
  state: string
  stage: string
  worktree: string
  pr: string
}

export type NeedItem = { id: string; kind: string; project: string; item: string; title: string }

export type Queue = {
  resume: Readonly<Record<string, string>>
  needs: readonly NeedItem[]
}

export type Star = {
  terminal: string | null
  isAway: boolean
  isGateDown: boolean
  progressDeadlineMin: number
}

export type Parsed<T> = { ok: true; value: T } | { ok: false; why: string }

const cells = (line: string): string[] => line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(c => c.trim())

export function parseLedger(text: string): Parsed<LedgerRow[]> {
  const lines = text.split('\n')
  const head = lines.findIndex(l => l.trim().startsWith('| item |'))
  if (head < 0 || !(lines[head + 1] ?? '').trim().startsWith('|---')) return { ok: false, why: 'no ledger table' }
  const header = cells(lines[head] ?? '')
  if (header.join('|') !== LEDGER_COLS.join('|')) return { ok: false, why: "the header is not STAR's ledger header" }
  const rows: LedgerRow[] = []
  for (let i = head + 2; i < lines.length; i += 1) {
    const line = (lines[i] ?? '').trim()
    if (!line) continue
    if (!line.startsWith('|')) break
    const c = line.endsWith('|') ? cells(line) : []
    if (c.length !== LEDGER_COLS.length) return { ok: false, why: `line ${i + 1} has ${c.length} cells, not ${LEDGER_COLS.length}` }
    rows.push({ item: c[0] ?? '', worktree: c[3] ?? '-', state: c[4] ?? '', stage: c[5] ?? '', pr: c[10] ?? '-' })
  }
  return { ok: true, value: rows }
}

// loops.sh ITEM_RE, ANSWER_RE, COMMENT_RE and SECTIONS, as the same text: tests/star/mod.test.sh
// compares them with the script's.
const ITEM_RE = /^### (N-(\d+)) · (.*?) · (.*?) · (.*)$/
const ANSWER_RE = /^\s{0,3}(?:[-*+]\s+)?(?:\[[ xX]\]\s*)?[*_]{0,2}answer\s*[:：][*_]{0,2}/i
const COMMENT_RE = /^\s*<!--.*-->\s*$/
const SECTIONS = ['## Resume', '## Needs you', '## Waiting on others']
const CONFLICT_RE = /^(<<<<<<<|>>>>>>>|=======|\|\|\|\|\|\|\|)( .*)?$/

function section(lines: readonly string[], title: string): [number, number] | undefined {
  const start = lines.findIndex(l => l.trim() === title)
  if (start < 0) return undefined
  let end = lines.length
  for (let i = start + 1; i < lines.length; i += 1) {
    if (SECTIONS.includes((lines[i] ?? '').trim())) { end = i; break }
  }
  return [start, end]
}

export function parseQueue(text: string): Parsed<Queue> {
  const lines = text.replace(/^﻿/, '').split('\n')
  if (lines.some(l => CONFLICT_RE.test(l))) return { ok: false, why: 'unresolved git conflict markers' }
  for (const title of SECTIONS) {
    if (lines.filter(l => l.trim() === title).length > 1) return { ok: false, why: `'${title}' appears twice` }
  }
  const needsAt = section(lines, '## Needs you')
  if (!needsAt) return { ok: false, why: "no '## Needs you' section" }
  const resume: Record<string, string> = {}
  const resumeAt = section(lines, '## Resume')
  if (resumeAt) {
    for (const l of lines.slice(resumeAt[0] + 1, resumeAt[1])) {
      const at = l.indexOf(':')
      if (at > 0) resume[l.slice(0, at).trim()] = l.slice(at + 1).trim()
    }
  }
  const [start, end] = needsAt
  const needs: NeedItem[] = []
  const seen = new Set<string>()
  let i = start + 1
  while (i < end) {
    const m = ITEM_RE.exec(lines[i] ?? '')
    if (!m) { i += 1; continue }
    let stop = end
    for (let k = i + 1; k < end; k += 1) if (ITEM_RE.test(lines[k] ?? '')) { stop = k; break }
    const id = m[1] ?? ''
    if (seen.has(id)) return { ok: false, why: `${id} appears twice in the queue` }
    seen.add(id)
    const body = lines.slice(i + 1, stop)
    const kindLine = body.find(l => l.startsWith('kind:'))
    const kind = kindLine ? (kindLine.slice(5).trim().split(/\s+/)[0] ?? '') : ''
    const at = body.findIndex(l => ANSWER_RE.test(l))
    let answer = ''
    if (at >= 0) {
      const parts = [(body[at] ?? '').replace(ANSWER_RE, '')]
      for (let j = at + 1; j < body.length && (body[j] ?? '').trim() && !COMMENT_RE.test(body[j] ?? ''); j += 1) parts.push(body[j] ?? '')
      answer = parts.join(' ').replace(/\s+/g, ' ').trim()
    }
    // An answered item is STAR's to act on next tick; only an open one needs the owner.
    if (!answer) needs.push({ id, kind, project: m[3] ?? '', item: m[4] ?? '', title: (m[5] ?? '').trimEnd() })
    i = stop
  }
  return { ok: true, value: { resume, needs } }
}

export function parseStar(text: string): Parsed<Star> {
  let data: unknown
  try { data = JSON.parse(text) } catch (err) { return { ok: false, why: `not JSON (${String(err).slice(0, 80)})` } }
  if (typeof data !== 'object' || data === null || Array.isArray(data)) return { ok: false, why: 'not a JSON object' }
  const d = data as Record<string, unknown>
  const deadline = typeof d['progressDeadlineMin'] === 'number' ? d['progressDeadlineMin'] : 30
  return {
    ok: true,
    value: {
      terminal: typeof d['terminal'] === 'string' && d['terminal'] ? d['terminal'] : null,
      isAway: d['away'] !== null && d['away'] !== undefined,
      isGateDown: d['gateDown'] !== null && d['gateDown'] !== undefined,
      progressDeadlineMin: deadline,
    },
  }
}

const ORDER = ['briefing', 'building', 'posting', 'babysitting', 'verifying', 'reported', 'escalated', 'failed'] as const

const ago = (ms: number): string => (ms < 3_600_000 ? `${Math.round(ms / 60_000)}m` : `${Math.round(ms / 3_600_000)}h`)

/**
 * The band, from what the three files held. A file that did not parse names itself on the line
 * and the rest still shows; nothing here throws.
 */
export function bandOf(star: Star, ledger: Parsed<LedgerRow[]>, queue: Parsed<Queue>, nowMs: number): StarBand {
  const parts: string[] = []
  const problems: string[] = []
  let done = 0
  if (ledger.ok) {
    const count = new Map<string, number>()
    for (const row of ledger.value) count.set(row.state, (count.get(row.state) ?? 0) + 1)
    for (const state of ORDER) {
      const n = count.get(state) ?? 0
      if (n) parts.push(`${n} ${state}`)
    }
    const waiting = WAITING_STATES.reduce((n, s) => n + (count.get(s) ?? 0), 0)
    if (waiting) parts.push(`${waiting} waiting`)
    done = count.get('done') ?? 0
  } else {
    problems.push(`ledger.md unreadable: ${ledger.why}`)
  }
  const needs = queue.ok ? queue.value.needs : []
  if (!queue.ok) problems.push(`open-loops.md unreadable: ${queue.why}`)
  if (needs.length) parts.push(`${needs.length} need you`)
  if (star.isGateDown) parts.push('gate down')

  const resume = queue.ok ? queue.value.resume : {}
  const lastTick = Date.parse(resume['last tick'] ?? '')
  const isRunning = resume['state'] === 'running'
  const isStale = isRunning && Number.isFinite(lastTick) && nowMs - lastTick > star.progressDeadlineMin * 60_000
  if (isStale) parts.push(`last tick ${ago(nowMs - lastTick)} ago`)

  const head = star.isAway ? 'STAR (away)' : 'STAR'
  const isIdle = !parts.length && !problems.length
  const line = problems.length
    ? [head, ...problems, ...parts].join(' · ')
    : isIdle
      ? `${head} idle · ${done} done · nothing needs you`
      : [head, ...parts].join(' · ')
  const tone: StarBand['tone'] = problems.length ? 'error' : isStale || star.isGateDown ? 'warn' : needs.length ? 'attention' : isIdle ? 'idle' : 'ok'
  return {
    tone,
    line,
    needs: needs.slice(0, 3).map(n => `${n.id} ${n.kind || '?'} · ${n.item}: ${n.title}`),
    more: Math.max(0, needs.length - 3),
  }
}
