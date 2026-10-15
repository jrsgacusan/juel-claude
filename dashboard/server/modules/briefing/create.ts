// Turns a briefing's draft into a ticket (brief D5, D9, B6-B8): an issue through gh for github, an
// issue through the tracker's MCP create tool in a headless haiku run for linear and jira when that
// tool is connected, else a STAR spec item. Then created.json, and an inbox file so STAR picks it up.
import { mkdir } from 'node:fs/promises'
import { basename, join } from 'node:path'

import { contentOf, message, parseObject, runCli, tail } from './claude.ts'
import type { CliEvent } from './claude.ts'
import { hex4, stamp } from './ids.ts'
import { rewriteCreated, writeCreated, writeNew } from './store.ts'
import type { Created } from './store.ts'
import type { Ticket } from './ticket.ts'
import type { Tracker } from './tracker.ts'

/**
 * The MCP create tool of linear and jira, under the prefixes tried (D5, B6); a connector under any
 * other prefix sends the item to the spec path. Linear's prefixes and save_issue:
 * references/work-source.md:110,158,189. Jira's tool is createJiraIssue
 * (https://github.com/atlassian/atlassian-mcp-server/blob/main/skills/triage-issue/SKILL.md), under
 * the same prefix pattern. Synapse has no MCP yet: wiring one in takes a row here, a branch in
 * createTicket and its name in createPrompt.
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
  log: (line: string) => void
}
/**
 * A failed create carries `made` when the ticket exists but could not be recorded, so it must not be
 * made again, and `maybeMade` when the tracker's create tool ran but did not say what it made.
 */
export type CreateOutcome = { ok: true; created: Created } | { ok: false; error: string; made?: Created; maybeMade?: boolean }
type Made = { ok: true; ref: string; url: string } | { ok: false; error: string; maybeMade?: boolean }

// A ref is one token, so it stays one line of the inbox file; a url is https with no whitespace.
const REF = /^[A-Za-z0-9][A-Za-z0-9_.#-]*$/
const HTTPS = /^https:\/\/\S+$/

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

/** The last JSON object in the text: a line of its own, or else one spread over several lines. */
export function lastJson(text: string): CliEvent | null {
  for (const line of text.split('\n').reverse()) {
    const value = parseObject(line)
    if (value) return value
  }
  const end = text.lastIndexOf('}')
  let start = end === -1 ? -1 : text.lastIndexOf('{', end)
  while (start !== -1) {
    const value = parseObject(text.slice(start, end + 1))
    if (value) return value
    start = start === 0 ? -1 : text.lastIndexOf('{', start - 1)
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
  if (exit.code !== 0) return { ok: false, error: tail(exit.stderr, 5) || `gh exited with ${exit.code ?? exit.signal}` }
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
  let called = false
  let result: CliEvent | null = null
  let stop = (): void => {}
  const run = runCli({
    bin: 'claude',
    // dontAsk: only the allowed create tools run, whatever default mode the owner's settings give;
    // --tools "" leaves no built-in tool (D5).
    args: ['-p', '--model', 'haiku', '--output-format', 'stream-json', '--verbose', '--permission-mode', 'dontAsk', '--tools', '', '--allowedTools', tools.join(','), '--', createPrompt(tracker, ctx.trackerProject, ctx.draft)],
    cwd: ctx.repo,
    onEvent: event => {
      if (event.type === 'system' && event.subtype === 'init') {
        const listed = Array.isArray(event.tools) ? event.tools : []
        connected = tools.some(tool => listed.includes(tool))
        if (!connected) stop() // not connected is not a failure: the spec path takes it
      } else if (event.type === 'assistant') {
        for (const block of contentOf(event) ?? []) {
          if (block?.type === 'text' && typeof block.text === 'string') texts.push(block.text)
          if (block?.type === 'tool_use' && typeof block.name === 'string' && tools.includes(block.name)) called = true
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
  if (seen === null) return { ok: false, error: `the ${tracker} create ended before it started: ${tail(exit.stderr, 5) || 'no output'}` }
  const reply = typeof final?.result === 'string' ? final.result : texts.join('\n')
  const said = lastJson(reply)
  const finished = exit.code === 0 && final !== null && final.is_error !== true
  if (finished && typeof said?.ref === 'string' && REF.test(said.ref) && typeof said.url === 'string' && HTTPS.test(said.url)) {
    return { ok: true, ref: said.ref, url: said.url }
  }
  ctx.log(`briefing ${ctx.project}/${basename(ctx.dir)}: the ${tracker} create ended with: ${tail(reply, 5) || tail(exit.stderr, 5) || 'no output'}`)
  const error = typeof said?.error === 'string' && said.error !== '' ? said.error : null
  const reason = error ?? (finished ? `the ${tracker} create did not say whether it made the issue` : tail(exit.stderr, 5) || `the ${tracker} create failed (exit ${exit.code ?? exit.signal})`)
  // The create tool ran, so the issue may exist even though the run did not report it.
  if ((called as boolean) && error === null) {
    return { ok: false, error: `${reason} (its create tool ran: check ${tracker} before saving it as a spec)`, maybeMade: true }
  }
  return { ok: false, error: reason }
}

/**
 * Makes the ticket, records it in created.json with `inbox: null`, then sends it to STAR with
 * queueCreated. A tracker failure writes nothing. Once the ticket exists it is logged first, and a
 * failure to record it comes back with `made`.
 */
export async function createTicket(ctx: CreateContext): Promise<CreateOutcome> {
  let made: Made | 'absent' = 'absent'
  if (ctx.tracker === 'github') made = await createGithub(ctx)
  else if (ctx.tracker === 'linear' || ctx.tracker === 'jira') made = await createViaMcp(ctx, ctx.tracker)
  if (made !== 'absent' && !made.ok) return made
  const at = new Date().toISOString()
  let created: Created
  if (made === 'absent') {
    const specPath = await writeSpecItem(ctx.home, ctx.project, ctx.draft)
    created = { tracker: ctx.tracker, ref: null, specPath, url: specUrl(ctx.project, specPath), at, inbox: null }
  } else {
    created = { tracker: ctx.tracker, ref: made.ref, specPath: null, url: made.url, at, inbox: null }
  }
  const name = created.ref ?? created.specPath ?? ''
  ctx.log(`briefing ${ctx.project}/${basename(ctx.dir)}: made ${name} (${created.url})`)
  try {
    if (!(await writeCreated(ctx.dir, created))) {
      return { ok: false, error: `${name} was made, but this briefing already had a ticket`, made: created }
    }
  } catch (err) {
    return { ok: false, error: `${name} was made, but it could not be recorded: ${message(err)}`, made: created }
  }
  return queueCreated(ctx, created)
}

/**
 * Tells STAR about a made ticket: a new inbox file, then created.json rewritten with its path. On a
 * failure created.json keeps `inbox: null`, so pressing Create again runs this again (the create
 * route) instead of answering 409, and no second ticket is made.
 */
export async function queueCreated(ctx: Pick<CreateContext, 'home' | 'repo' | 'dir'>, created: Created): Promise<CreateOutcome> {
  const name = created.ref ?? created.specPath ?? ''
  try {
    const inbox = await writeInbox(ctx.home, ctx.repo, name)
    const queued: Created = { ...created, inbox }
    await rewriteCreated(ctx.dir, queued)
    return { ok: true, created: queued }
  } catch (err) {
    return { ok: false, error: `${name} was made, but STAR's inbox file could not be written: ${message(err)}. Press Create again to send it to STAR.`, made: created }
  }
}
