// Where a repo's tickets live (brief D4, D14, B5): read from .claude/workflow.local.json, then
// .claude/workflow.json, then a `## Work Source` block in CLAUDE.md or AGENTS.md, the order
// references/resolution.md gives. Unlike resolution.md's key-by-key merge of the two JSON files, the
// first of them that names a tracker wins. Saved as tracker.type in .claude/workflow.local.json, the
// form every juel skill reads.
import { mkdir } from 'node:fs/promises'
import { join } from 'node:path'

import { message } from './claude.ts'
import { readText, replaceFile } from './store.ts'

export const TRACKERS = ['synapse', 'linear', 'jira', 'github', 'none'] as const
export type Tracker = (typeof TRACKERS)[number]
export type ResolvedTracker = { type: string; project: string | null }
export type SaveResult = { ok: true } | { ok: false; error: string }

export function isTracker(value: unknown): value is Tracker {
  return typeof value === 'string' && (TRACKERS as readonly string[]).includes(value)
}

/**
 * A resolved tracker type as one of the five answers. Case is ignored; juel's `file` and `inline`
 * (references/resolution.md:68) keep tickets as local specs, so they are `none`; anything else is null.
 */
export function asTracker(type: string): Tracker | null {
  const value = type.toLowerCase()
  if (isTracker(value)) return value
  return value === 'file' || value === 'inline' ? 'none' : null
}

const text = (value: unknown): string | null => (typeof value === 'string' && value.trim() !== '' ? value.trim() : null)
const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value)

/** The tracker a workflow file's JSON names: `tracker` as a string, or an object's `type`. */
export function fromConfig(config: unknown): ResolvedTracker | null {
  if (!isRecord(config)) return null
  const named = text(config.tracker)
  if (named) return { type: named, project: null }
  if (!isRecord(config.tracker)) return null
  const kind = text(config.tracker.type)
  return kind ? { type: kind, project: text(config.tracker.project) } : null
}

/** The `- type:` and `- project:` lines of a `## Work Source` block, up to the next heading. */
export function fromWorkSource(markdown: string): ResolvedTracker | null {
  const lines = markdown.split(/\r?\n/)
  const start = lines.findIndex(line => /^##\s+Work Source\s*$/.test(line))
  if (start === -1) return null
  let type: string | null = null
  let project: string | null = null
  for (const line of lines.slice(start + 1)) {
    if (/^#{1,6}\s/.test(line)) break
    const field = /^\s*[-*]\s*(type|project)\s*:\s*(.+?)\s*$/.exec(line)
    if (!field) continue
    const value = text(field[2].replace(/^`(.*)`$/, '$1'))
    if (field[1] === 'type') type = value
    else project = value
  }
  return type ? { type, project } : null
}

/** A file's text; null when it is missing, and, with a warning, when it cannot be read. */
async function readOrWarn(path: string, warn: (line: string) => void): Promise<string | null> {
  try {
    return await readText(path)
  } catch (err) {
    warn(`tracker: skipped ${path}: ${message(err)}`)
    return null
  }
}

/**
 * A workflow file's JSON, or undefined; an empty or whitespace-only file holds nothing, like a missing
 * one (D14), and a malformed one is warned about and ignored (resolution.md:84, B5).
 */
async function readConfig(path: string, warn: (line: string) => void): Promise<unknown> {
  const raw = await readOrWarn(path, warn)
  if (raw === null || raw.trim() === '') return undefined
  try {
    return JSON.parse(raw)
  } catch {
    warn(`tracker: skipped ${path}: not valid JSON`)
    return undefined
  }
}

export async function resolveTracker(repo: string, warn: (line: string) => void = () => {}): Promise<ResolvedTracker | null> {
  for (const name of ['workflow.local.json', 'workflow.json']) {
    const found = fromConfig(await readConfig(join(repo, '.claude', name), warn))
    if (found) return found
  }
  for (const name of ['CLAUDE.md', 'AGENTS.md']) {
    const markdown = await readOrWarn(join(repo, name), warn)
    const found = markdown === null ? null : fromWorkSource(markdown)
    if (found) return found
  }
  return null
}

// The save running for each repo. Saves to one repo run one after another, since each reads the
// file and then replaces it through the same temp name.
const saving = new Map<string, Promise<unknown>>()

/**
 * Sets tracker.type in .claude/workflow.local.json, keeping every other key. A file that does not
 * parse to a JSON object is refused and left as it is; an empty or whitespace-only one counts as {}
 * (D14). The new text replaces the old in one rename, so a failed write never truncates the owner's
 * config, and two saves to one repo never overlap.
 */
export function saveTracker(repo: string, value: Tracker): Promise<SaveResult> {
  const next = (saving.get(repo) ?? Promise.resolve()).then(() => saveNow(repo, value))
  const settled = next.catch(() => {})
  saving.set(repo, settled)
  void settled.then(() => {
    if (saving.get(repo) === settled) saving.delete(repo)
  })
  return next
}

async function saveNow(repo: string, value: Tracker): Promise<SaveResult> {
  const dir = join(repo, '.claude')
  const path = join(dir, 'workflow.local.json')
  const raw = await readText(path)
  let config: Record<string, unknown> = {}
  if (raw !== null && raw.trim() !== '') {
    let parsed: unknown
    try {
      parsed = JSON.parse(raw)
    } catch {
      return { ok: false, error: `${path} is not valid JSON: fix it by hand, then answer again` }
    }
    if (!isRecord(parsed)) return { ok: false, error: `${path} is not a JSON object: fix it by hand, then answer again` }
    config = parsed
  }
  const tracker = isRecord(config.tracker) ? { ...config.tracker, type: value } : { type: value }
  await mkdir(dir, { recursive: true })
  await replaceFile(path, `${JSON.stringify({ ...config, tracker }, null, 2)}\n`)
  return { ok: true }
}
