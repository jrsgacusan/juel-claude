// Where a repo's tickets live (brief D4, B5): read from .claude/workflow.local.json, then
// .claude/workflow.json, then a `## Work Source` block in CLAUDE.md or AGENTS.md, the order
// references/resolution.md gives; saved as tracker.type in .claude/workflow.local.json, the form
// every juel skill reads.
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

export const TRACKERS = ['synapse', 'linear', 'jira', 'github', 'none'] as const
export type Tracker = (typeof TRACKERS)[number]
export type ResolvedTracker = { type: string; project: string | null }
export type SaveResult = { ok: true } | { ok: false; error: string }

export function isTracker(value: unknown): value is Tracker {
  return typeof value === 'string' && (TRACKERS as readonly string[]).includes(value)
}

const text = (value: unknown): string | null => (typeof value === 'string' && value.trim() !== '' ? value.trim() : null)
const errCode = (err: unknown): string | undefined => (err as { code?: string } | null)?.code

/** The tracker a workflow file's JSON names: `tracker` as a string, or an object's `type`. */
export function fromConfig(config: unknown): ResolvedTracker | null {
  if (typeof config !== 'object' || config === null) return null
  const tracker = (config as Record<string, unknown>).tracker
  const named = text(tracker)
  if (named) return { type: named, project: null }
  if (typeof tracker !== 'object' || tracker === null) return null
  const { type, project } = tracker as Record<string, unknown>
  const kind = text(type)
  return kind ? { type: kind, project: text(project) } : null
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

async function readConfig(path: string): Promise<unknown> {
  try {
    return JSON.parse(await readFile(path, 'utf8'))
  } catch {
    return undefined // missing or not valid JSON: skipped, as references/resolution.md:79-80 says (B5)
  }
}

export async function resolveTracker(repo: string): Promise<ResolvedTracker | null> {
  for (const name of ['workflow.local.json', 'workflow.json']) {
    const found = fromConfig(await readConfig(join(repo, '.claude', name)))
    if (found) return found
  }
  for (const name of ['CLAUDE.md', 'AGENTS.md']) {
    let markdown: string
    try {
      markdown = await readFile(join(repo, name), 'utf8')
    } catch {
      continue
    }
    const found = fromWorkSource(markdown)
    if (found) return found
  }
  return null
}

/** Sets tracker.type in .claude/workflow.local.json, keeping every other key; never overwrites a file it cannot parse. */
export async function saveTracker(repo: string, value: Tracker): Promise<SaveResult> {
  const dir = join(repo, '.claude')
  const path = join(dir, 'workflow.local.json')
  let config: Record<string, unknown> = {}
  let raw: string | null = null
  try {
    raw = await readFile(path, 'utf8')
  } catch (err) {
    if (errCode(err) !== 'ENOENT') throw err
  }
  if (raw !== null && raw.trim() !== '') {
    let parsed: unknown
    try {
      parsed = JSON.parse(raw)
    } catch {
      return { ok: false, error: `${path} is not valid JSON: fix it by hand, then answer again` }
    }
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      return { ok: false, error: `${path} is not a JSON object: fix it by hand, then answer again` }
    }
    config = parsed as Record<string, unknown>
  }
  const current = config.tracker
  const tracker = typeof current === 'object' && current !== null && !Array.isArray(current) ? { ...(current as Record<string, unknown>), type: value } : { type: value }
  await mkdir(dir, { recursive: true })
  await writeFile(path, `${JSON.stringify({ ...config, tracker }, null, 2)}\n`)
  return { ok: true }
}
