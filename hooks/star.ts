// Pure readers of STAR's state files, and the band text built from them. No `$` here: every
// function takes text and returns data, so a test (or a port of ledger.sh / loops.sh rules)
// checks it without a session. The parsing mirrors skills/star/ledger.sh load() and
// skills/star/loops.sh items()/answer_of(): when either script changes its format, this file
// changes in the same commit.

import type { StarBand, StarGauge, StarNeed } from '../types'

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

/**
 * One queue item as loops.sh wrote it: the heading's fields, the body lines between its `kind:`
 * line and its `Answer:` line, and the answer ('' while the item is open).
 */
export type NeedItem = {
  id: string
  kind: string
  project: string
  item: string
  title: string
  body: readonly string[]
  answer: string
}

export type Queue = {
  resume: Readonly<Record<string, string>>
  /** Every item in Needs you, open and answered, in the file's order. */
  needs: readonly NeedItem[]
  /** The lines of Waiting on others. */
  waiting: readonly string[]
}

export type Star = {
  terminal: string | null
  isAway: boolean
  isGateDown: boolean
  progressDeadlineMin: number
  /** The pools' sizes: maxBriefs, maxParallel, maxInReview (4, 3, 3 when absent). */
  maxBriefs: number
  maxParallel: number
  maxInReview: number
  /** project.name, '' when absent. */
  project: string
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
    const rows = lines.slice(i + 1, stop)
    const kindAt = rows.findIndex(l => l.startsWith('kind:'))
    const kind = kindAt >= 0 ? ((rows[kindAt] ?? '').slice(5).trim().split(/\s+/)[0] ?? '') : ''
    const at = rows.findIndex(l => ANSWER_RE.test(l))
    let answer = ''
    if (at >= 0) {
      const parts = [(rows[at] ?? '').replace(ANSWER_RE, '')]
      for (let j = at + 1; j < rows.length && (rows[j] ?? '').trim() && !COMMENT_RE.test(rows[j] ?? ''); j += 1) parts.push(rows[j] ?? '')
      answer = parts.join(' ').replace(/\s+/g, ' ').trim()
    }
    // loops.sh body_of: between the kind line and the Answer line (the first blank line when the
    // user deleted it), so a note the user left under the answer is never read as the body.
    let bodyEnd = at >= 0 ? at : rows.length
    if (at < 0) {
      const blank = rows.findIndex((l, k) => k > kindAt + 1 && !l.trim())
      if (blank >= 0) bodyEnd = blank
    }
    const body = rows
      .slice(0, bodyEnd)
      .filter((l, k) => k !== kindAt && l.trim() && !COMMENT_RE.test(l))
      .map(l => l.trimEnd())
    // Answered items stay listed until STAR closes them, so the owner sees what was sent.
    needs.push({ id, kind, project: m[3] ?? '', item: m[4] ?? '', title: (m[5] ?? '').trimEnd(), body, answer })
    i = stop
  }
  const waitingAt = section(lines, '## Waiting on others')
  const waiting = waitingAt
    ? lines
        .slice(waitingAt[0] + 1, waitingAt[1])
        .map(l => l.trim().replace(/^> /, ''))
        .filter(l => l && !COMMENT_RE.test(l))
    : []
  return { ok: true, value: { resume, needs, waiting } }
}

export function parseStar(text: string): Parsed<Star> {
  let data: unknown
  try { data = JSON.parse(text) } catch (err) { return { ok: false, why: `not JSON (${String(err).slice(0, 80)})` } }
  if (typeof data !== 'object' || data === null || Array.isArray(data)) return { ok: false, why: 'not a JSON object' }
  const d = data as Record<string, unknown>
  const num = (key: string, fallback: number): number => {
    const v = d[key]
    return typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : fallback
  }
  const project = d['project'] as { name?: unknown } | null | undefined
  return {
    ok: true,
    value: {
      terminal: typeof d['terminal'] === 'string' && d['terminal'] ? d['terminal'] : null,
      isAway: d['away'] !== null && d['away'] !== undefined,
      isGateDown: d['gateDown'] !== null && d['gateDown'] !== undefined,
      progressDeadlineMin: num('progressDeadlineMin', 30),
      maxBriefs: num('maxBriefs', 4),
      maxParallel: num('maxParallel', 3),
      maxInReview: num('maxInReview', 3),
      project: project && typeof project.name === 'string' ? project.name : '',
    },
  }
}

// An option that only says "answer in words" ("or say what to change", "answer with your
// decision to run the stage again") is the field's placeholder, not a button.
const IN_WORDS = /^(or\b|answer with\b|tell me\b|say\b)|\byour (decision|answer)\b/i

/**
 * An item's `Options:` line as the band draws it: each option the owner can pick as it is, each
 * template (`go except <items>`) as the words before its placeholder, ready to finish, and the
 * options that only ask for words as the field's placeholder.
 */
export function optionsOf(body: readonly string[]): { options: { label: string; text: string }[]; hint: string } {
  const line = body.find(l => /^options\s*:/i.test(l))
  const options: { label: string; text: string }[] = []
  const hints: string[] = []
  for (const raw of line ? line.replace(/^options\s*:/i, '').split(' / ') : []) {
    const part = raw.trim()
    if (!part) continue
    const open = part.indexOf('<')
    if (open >= 0) {
      const head = part.slice(0, open).trimEnd()
      const close = part.indexOf('>', open)
      const what = part.slice(open + 1, close > open ? close : undefined).trim()
      if (head) options.push({ label: `${head} …`, text: `${head} ` })
      else hints.push(`type ${what || 'the value'}`)
    } else if (IN_WORDS.test(part)) {
      hints.push(part.replace(/^or\s+/i, ''))
    } else {
      options.push({ label: part, text: part })
    }
  }
  return { options, hint: hints.join(', or ') }
}

function ago(ms: number): string {
  if (ms < 60_000) return 'just now'
  if (ms < 3_600_000) return `${Math.round(ms / 60_000)}m ago`
  return `${Math.round(ms / 3_600_000)}h ago`
}

const span = (ms: number): string => (ms < 3_600_000 ? `${Math.max(1, Math.round(ms / 60_000))}m` : `${Math.round(ms / 3_600_000)}h`)

/** One queue item as the band shows it: what it is, what the owner can pick, what is due. */
export function needOf(n: NeedItem, nowMs: number): StarNeed {
  const { options, hint } = optionsOf(n.body)
  const details: { key: string; value: string }[] = []
  const names: string[] = []
  let due: string | null = null
  for (const raw of n.body) {
    const line = raw.replace(/^> /, '')
    if (/^options\s*:/i.test(line)) continue
    const kv = /^([a-z][a-z -]{0,20}):\s*(.*)$/i.exec(line)
    if (!kv) {
      names.push(line.trim())
      continue
    }
    const key = (kv[1] ?? '').trim()
    const value = (kv[2] ?? '').trim()
    if (key === 'msg') continue // the Orca message id STAR replies to: nothing for the owner
    if (key === 'deadline') {
      const at = Date.parse(value)
      if (Number.isFinite(at)) due = at >= nowMs ? `${span(at - nowMs)} left` : `${span(nowMs - at)} overdue`
      continue
    }
    details.push({ key, value })
  }
  return {
    id: n.id,
    kind: n.kind,
    item: n.item,
    title: n.title,
    names,
    details,
    options,
    hint: hint || (options.length ? 'or type an answer in words' : 'type your answer'),
    due,
  }
}

const ORDER = ['briefing', 'building', 'posting', 'babysitting', 'verifying', 'reported', 'escalated', 'failed'] as const

/**
 * The band, from what the three files held. A file that did not parse names itself on the line
 * and the rest still shows; nothing here throws.
 */
export function bandOf(star: Star, ledger: Parsed<LedgerRow[]>, queue: Parsed<Queue>, nowMs: number): StarBand {
  const parts: string[] = []
  const problems: string[] = []
  const count = new Map<string, number>()
  let done = 0
  if (ledger.ok) {
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
  // The pools, live from the ledger: a row counts against a pool while its state is that pool's.
  const inState = (...states: string[]): number => states.reduce((sum, s) => sum + (count.get(s) ?? 0), 0)
  const gauges: StarGauge[] = ledger.ok
    ? [
        { name: 'brief', used: inState('briefing'), max: star.maxBriefs },
        { name: 'build', used: inState('building', 'posting'), max: star.maxParallel },
        { name: 'babysit', used: inState('babysitting'), max: star.maxInReview },
      ]
    : []

  const items = queue.ok ? queue.value.needs : []
  const open = items.filter(i => !i.answer).length
  if (!queue.ok) problems.push(`open-loops.md unreadable: ${queue.why}`)
  if (open) parts.push(`${open} need you`)
  const flags: string[] = []
  if (star.isGateDown) {
    parts.push('gate down')
    flags.push('gate down')
  }

  const resume = queue.ok ? queue.value.resume : {}
  const lastTick = Date.parse(resume['last tick'] ?? '')
  const state = resume['state'] || 'unknown'
  const isStale = state === 'running' && Number.isFinite(lastTick) && nowMs - lastTick > star.progressDeadlineMin * 60_000
  if (isStale) {
    parts.push(`last tick ${ago(nowMs - lastTick)}`)
    flags.push(`last tick ${ago(nowMs - lastTick)}`)
  }
  if (star.isAway) flags.push('away')

  const head = star.isAway ? 'STAR (away)' : 'STAR'
  const isIdle = !parts.length && !problems.length
  const line = problems.length
    ? [head, ...problems, ...parts].join(' · ')
    : isIdle
      ? `${head} idle · ${done} done · nothing needs you`
      : [head, ...parts].join(' · ')
  const tone: StarBand['tone'] = problems.length ? 'error' : isStale || star.isGateDown ? 'warn' : open ? 'attention' : isIdle ? 'idle' : 'ok'
  return {
    tone,
    line,
    project: star.project,
    state,
    tick: Number.isFinite(lastTick) ? ago(Math.max(0, nowMs - lastTick)) : null,
    gauges,
    flags,
    problems,
    open,
    // An answered item is STAR's to act on at its next tick: the band lists open ones only.
    needs: items.filter(i => !i.answer).map(i => needOf(i, nowMs)),
    waiting: queue.ok ? queue.value.waiting : [],
  }
}
