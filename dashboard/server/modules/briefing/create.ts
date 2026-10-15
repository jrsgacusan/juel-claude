// Turns a briefing's draft into a ticket (brief D5, D9, B6-B8): an issue through gh for github, an
// issue through the tracker's MCP create tool in a headless haiku run for linear and jira when that
// tool is connected, else a STAR spec item. Then created.json, and an inbox file so STAR picks it up.
import { mkdir, writeFile } from 'node:fs/promises'
import { basename, join } from 'node:path'

import { runCli } from './claude.ts'
import type { CliEvent } from './claude.ts'
import { hex4, stamp } from './ids.ts'
import { writeCreated } from './store.ts'
import type { Created } from './store.ts'
import type { Ticket } from './ticket.ts'
import type { Tracker } from './tracker.ts'

/**
 * Each tracker's MCP create tool under every prefix it is known by (D5, B6). Linear's prefixes and
 * save_issue: references/work-source.md:110,158,189. Jira: Atlassian's MCP server names its create
 * tool createJiraIssue (github.com/atlassian/atlassian-mcp-server, skills/triage-issue/SKILL.md).
 * Synapse has no MCP yet; adding it is one row.
 */
export const CREATE_TOOLS: Record<'linear' | 'jira' | 'synapse', string[]> = {
  linear: ['mcp__linear__save_issue', 'mcp__plugin_linear_linear__save_issue', 'mcp__claude_ai_Linear__save_issue'],
  jira: ['mcp__atlassian__createJiraIssue', 'mcp__plugin_atlassian_atlassian__createJiraIssue', 'mcp__claude_ai_Atlassian__createJiraIssue'],
  synapse: [],
}

export type CreateContext = {
  /** The project's name: the items/<project>/ folder and the url's path segment. */
  project: string
  repo: string
  /** The project's STAR folder. */
  home: string
  /** The briefing folder, where created.json goes. */
  dir: string
  tracker: Tracker
  /** The tracker's project or team from the repo's config, when it names one. */
  trackerProject: string | null
  draft: Ticket
}
export type CreateOutcome = { ok: true; created: Created } | { ok: false; error: string }
type Made = { ok: true; ref: string; url: string } | { ok: false; error: string }

const errCode = (err: unknown): string | undefined => (err as { code?: string } | null)?.code
const tail = (text: string, lines = 5): string => text.trim().split('\n').slice(-lines).join('\n').trim()

/** The issue body, and the spec item's body under its frontmatter (D9, B7). */
export function ticketBody(draft: Ticket): string {
  const list = (items: string[], prefix: string): string => (items.length > 0 ? items.map(item => `${prefix}${item}`).join('\n') : 'None.')
  const description = draft.description.trim()
  return `${description ? `${description}\n\n` : ''}## Acceptance criteria\n${list(draft.criteria, '- [ ] ')}\n\n## Out of scope\n${list(draft.outOfScope, '- ')}\n`
}

/** The title in kebab case, at most six words (D9). */
export function slugOf(title: string): string {
  const words = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').split('-').filter(Boolean).slice(0, 6)
  return words.length > 0 ? words.join('-') : 'briefing'
}

/** The spec item through the server's file route (B8). */
export function specUrl(project: string, specPath: string): string {
  return `/api/projects/${encodeURIComponent(project)}/file?path=${encodeURIComponent(`items/${project}/${basename(specPath)}`)}`
}

async function writeNew(path: string, content: string): Promise<boolean> {
  try {
    await writeFile(path, content, { flag: 'wx' })
    return true
  } catch (err) {
    if (errCode(err) === 'EEXIST') return false
    throw err
  }
}

/** <STAR folder>/items/<project>/<slug>.md, then -2, -3: never overwrites a spec. */
export async function writeSpecItem(home: string, project: string, draft: Ticket): Promise<string> {
  const dir = join(home, 'items', project)
  await mkdir(dir, { recursive: true })
  const slug = slugOf(draft.title)
  const content = `---\nstatus: todo\ntitle: ${draft.title.replace(/\s+/g, ' ').trim()}\n---\n${ticketBody(draft)}`
  for (let n = 1; n <= 1000; n++) {
    const path = join(dir, n === 1 ? `${slug}.md` : `${slug}-${n}.md`)
    if (await writeNew(path, content)) return path
  }
  throw new Error(`no free spec name for ${slug} in ${dir}`)
}

/** A new STAR inbox file (skills/star/SKILL.md:244-254); another suffix on a clash, never an overwrite. */
export async function writeInbox(home: string, repo: string, ref: string, now: Date = new Date(), suffix: () => string = hex4): Promise<string> {
  const dir = join(home, 'inbox')
  await mkdir(dir, { recursive: true })
  for (let tries = 0; tries < 100; tries++) {
    const path = join(dir, `${stamp(now)}-${suffix()}.md`)
    if (await writeNew(path, `repo: ${repo}\nrefs:\n- ${ref}\n`)) return path
  }
  throw new Error(`no free inbox name in ${dir}`)
}

export function createPrompt(tracker: 'linear' | 'jira', project: string | null, draft: Ticket): string {
  const name = tracker === 'linear' ? 'Linear' : 'Jira'
  const where = tracker === 'linear' ? 'team' : 'project'
  return [
    `Create exactly one ${name} issue with your ${name} create tool, then stop. Do nothing else.`,
    project
      ? `Create it in the ${name} ${where} "${project}".`
      : `If the tool needs a ${where} and nothing here names one, do not guess: report it as the error.`,
    `Title: ${draft.title}`,
    `Description, in Markdown, used as is:\n\n${ticketBody(draft)}`,
    'When the issue exists, end your reply with this one line of JSON and nothing after it:',
    '{"ref": "<the issue identifier, like ENG-123>", "url": "<the issue URL>"}',
    'If you cannot create it, end your reply with this one line of JSON instead:',
    '{"error": "<what went wrong, in one sentence>"}',
  ].join('\n\n')
}

/** The last line of the text that parses as a JSON object. */
export function lastJson(text: string): Record<string, unknown> | null {
  for (const line of text.split('\n').reverse()) {
    const trimmed = line.trim()
    if (!trimmed.startsWith('{')) continue
    try {
      const value: unknown = JSON.parse(trimmed)
      if (typeof value === 'object' && value !== null && !Array.isArray(value)) return value as Record<string, unknown>
    } catch {
      // not JSON: keep looking
    }
  }
  return null
}

async function createGithub(ctx: CreateContext): Promise<Made> {
  const lines: string[] = []
  const exit = await runCli({
    bin: 'gh',
    args: ['issue', 'create', '--title', ctx.draft.title, '--body-file', '-'],
    cwd: ctx.repo,
    input: ticketBody(ctx.draft),
    onLine: line => { lines.push(line.trim()) },
  }).done
  if (exit.spawnError) return { ok: false, error: `gh could not start: ${exit.spawnError}` }
  if (exit.code !== 0) return { ok: false, error: tail(exit.stderr) || `gh exited with ${exit.code ?? exit.signal}` }
  const url = lines.filter(line => line.startsWith('https://')).pop()
  if (!url) return { ok: false, error: 'gh issue create printed no issue URL' }
  const number = /\/issues\/(\d+)/.exec(url)?.[1]
  return { ok: true, ref: number ? `#${number}` : url, url }
}

/** The connected-tracker create (D5); 'absent' when init lists none of the tracker's create tools. */
async function createViaMcp(ctx: CreateContext, tracker: 'linear' | 'jira'): Promise<Made | 'absent'> {
  const tools = CREATE_TOOLS[tracker]
  const texts: string[] = []
  let connected: boolean | null = null
  let result: CliEvent | null = null
  let stop = (): void => {}
  const run = runCli({
    bin: 'claude',
    args: ['-p', '--model', 'haiku', '--output-format', 'stream-json', '--verbose', '--tools', '', '--allowedTools', tools.join(','), '--', createPrompt(tracker, ctx.trackerProject, ctx.draft)],
    cwd: ctx.repo,
    onEvent: event => {
      if (event.type === 'system' && event.subtype === 'init') {
        const listed = Array.isArray(event.tools) ? event.tools : []
        connected = tools.some(tool => listed.includes(tool))
        if (!connected) stop() // not connected is not a failure: the spec path takes it
      } else if (event.type === 'assistant') {
        const content = (event.message as { content?: unknown } | undefined)?.content
        if (!Array.isArray(content)) return
        for (const block of content as Record<string, unknown>[]) {
          if (block?.type === 'text' && typeof block.text === 'string') texts.push(block.text)
        }
      } else if (event.type === 'result') {
        result = event
      }
    },
  })
  stop = run.kill
  const exit = await run.done
  const seen = connected as boolean | null
  const final = result as CliEvent | null
  if (seen === false) return 'absent'
  if (exit.spawnError) return { ok: false, error: `claude could not start: ${exit.spawnError}` }
  if (seen === null) return { ok: false, error: `the ${tracker} create ended before it started: ${tail(exit.stderr) || 'no output'}` }
  const said = lastJson(typeof final?.result === 'string' ? final.result : texts.join('\n'))
  const error = typeof said?.error === 'string' && said.error !== '' ? said.error : null
  if (exit.code !== 0 || !final || final.is_error === true) {
    return { ok: false, error: error ?? (tail(exit.stderr) || `the ${tracker} create failed (exit ${exit.code ?? exit.signal})`) }
  }
  if (typeof said?.ref === 'string' && said.ref !== '' && typeof said.url === 'string' && said.url !== '') return { ok: true, ref: said.ref, url: said.url }
  return { ok: false, error: error ?? `the ${tracker} create did not say whether it made the issue` }
}

/** Makes the ticket, then created.json and the inbox file; a failure writes nothing. */
export async function createTicket(ctx: CreateContext): Promise<CreateOutcome> {
  let made: Made | 'absent' = 'absent'
  if (ctx.tracker === 'github') made = await createGithub(ctx)
  else if (ctx.tracker === 'linear' || ctx.tracker === 'jira') made = await createViaMcp(ctx, ctx.tracker)
  if (made !== 'absent' && !made.ok) return made
  const at = new Date().toISOString()
  let created: Created
  if (made === 'absent') {
    const specPath = await writeSpecItem(ctx.home, ctx.project, ctx.draft)
    created = { tracker: ctx.tracker, ref: null, specPath, url: specUrl(ctx.project, specPath), at }
  } else {
    created = { tracker: ctx.tracker, ref: made.ref, specPath: null, url: made.url, at }
  }
  await writeCreated(ctx.dir, created)
  await writeInbox(ctx.home, ctx.repo, created.ref ?? created.specPath ?? '')
  return { ok: true, created }
}
