// Turns a briefing's draft into a ticket (brief D5, D8, D9, follow-up D1, B6-B8): an issue through gh for
// github, an issue through the tracker's MCP create tool in a headless haiku run for linear and jira
// when that tool is connected, else a STAR spec item. created.json marks the create before anything is
// made (D8), then records the made ticket's inbox path before its file is written; the file reaches STAR
// exactly once (follow-up D1).
import { lstat, mkdir, rm } from 'node:fs/promises'
import { basename, dirname, join } from 'node:path'

import { contentOf, message, parseObject, runCli, tail } from './claude.ts'
import type { CliEvent } from './claude.ts'
import { hex4, stamp } from './ids.ts'
import { ledgerRefs } from './ledger.ts'
import { readText, rewriteCreated, writeCreated, writeNew, linkNew } from './store.ts'
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
 * A failed create carries `made` when the ticket exists but could not be recorded, sent to STAR's
 * inbox, or sent but not recorded as queued, so it must not be made again, and `maybeMade` when it
 * may exist (the tracker's create tool ran, or gh succeeded, without saying what it made); the
 * briefing then stays marked.
 */
export type CreateOutcome = { ok: true; created: Created } | { ok: false; error: string; made?: Created; maybeMade?: boolean }
type Made = { ok: true; ref: string; url: string } | { ok: false; error: string; maybeMade?: boolean }

// A ref is one token, so it stays one line of the inbox file; a url is https with no whitespace.
const REF = /^[A-Za-z0-9][A-Za-z0-9_.#-]*$/
const HTTPS = /^https:\/\/\S+$/
const INBOX_NAME = /^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}\.md$/

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

/** STAR's inbox format (skills/star/SKILL.md:245-255). */
export function inboxContent(repo: string, ref: string): string {
  return `repo: ${repo}\nrefs:\n- ${ref}\n`
}

/** Picks a free STAR inbox path and creates the folder, writing nothing; the caller's link is what never overwrites. */
export async function drawInbox(home: string, now: Date = new Date(), suffix: () => string = hex4): Promise<string> {
  const dir = join(home, 'inbox')
  await mkdir(dir, { recursive: true })
  for (let tries = 0; tries < 100; tries++) {
    const path = join(dir, `${stamp(now)}-${suffix()}.md`)
    try {
      await lstat(path)
    } catch (err) {
      if ((err as { code?: string }).code === 'ENOENT') return path
      throw err
    }
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

/** The last line that is a JSON object; when no line is, the last object spread over several lines. */
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
  // gh exits 0 only once the issue exists, so an answer with no https URL may still have made one.
  if (!url) return { ok: false, error: `gh issue create exited 0 but printed no issue URL (${tail(lines.join('\n'), 3) || 'no output'})`, maybeMade: true }
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
    // dontAsk: nothing waits on a prompt, and a tool runs only when --allowedTools, the owner's own
    // allow rules or a hook approve it; --tools "" leaves no built-in tool (D5).
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
    return { ok: false, error: `${reason} (its create tool ran, so the issue may exist)`, maybeMade: true }
  }
  return { ok: false, error: reason }
}

/** A create that made nothing clears its mark, so the owner can try again or save it as a spec. */
async function unmark(dir: string, failed: { ok: false; error: string; maybeMade?: boolean }): Promise<CreateOutcome> {
  try {
    await rm(join(dir, 'created.json'), { force: true })
  } catch (err) {
    return { ...failed, error: `${failed.error}; the create's mark could not be cleared either: ${message(err)}` }
  }
  return failed
}

/**
 * Makes the ticket and sends it to STAR (D8: one ticket per briefing). created.json is written as
 * `state: 'creating'` before anything is made; a create that made nothing clears it, and a made
 * ticket rewrites it as `state: 'made'`. When the ticket may exist (`maybeMade`), or that rewrite
 * fails, the mark stays, so the next press answers 409 instead of making a second ticket; a made
 * ticket is logged first either way.
 */
export async function createTicket(ctx: CreateContext): Promise<CreateOutcome> {
  const at = new Date().toISOString()
  const mark: Created = { tracker: ctx.tracker, ref: null, specPath: null, url: null, at, state: 'creating', inbox: null }
  try {
    if (!(await writeCreated(ctx.dir, mark))) return { ok: false, error: 'this briefing already has a create, running or done' }
  } catch (err) {
    return { ok: false, error: `the create could not start: ${message(err)}` }
  }
  let made: Made | 'absent' = 'absent'
  if (ctx.tracker === 'github') made = await createGithub(ctx)
  else if (ctx.tracker === 'linear' || ctx.tracker === 'jira') made = await createViaMcp(ctx, ctx.tracker)
  if (made !== 'absent' && !made.ok) {
    if (!made.maybeMade) return unmark(ctx.dir, made)
    return { ok: false, error: `${made.error}. The briefing stays marked, so no second ticket is made: check ${ctx.tracker} for the issue, then remove ${join(ctx.dir, 'created.json')} to try again or to save it as a spec`, maybeMade: true }
  }
  let created: Created
  if (made === 'absent') {
    let specPath: string
    try {
      specPath = await writeSpecItem(ctx.home, ctx.project, ctx.draft)
    } catch (err) {
      return unmark(ctx.dir, { ok: false, error: `the spec item could not be written: ${message(err)}` })
    }
    created = { tracker: ctx.tracker, ref: null, specPath, url: specUrl(ctx.project, specPath), at, state: 'made', inbox: null, queued: false }
  } else {
    created = { tracker: ctx.tracker, ref: made.ref, specPath: null, url: made.url, at, state: 'made', inbox: null, queued: false }
  }
  const name = created.ref ?? created.specPath ?? ''
  ctx.log(`briefing ${ctx.project}/${basename(ctx.dir)}: made ${name} (${created.url})`)
  try {
    await rewriteCreated(ctx.dir, created)
  } catch (err) {
    return { ok: false, error: `${name} was made, but it could not be recorded: ${message(err)}. The briefing stays marked, so no second ticket is made`, made: created }
  }
  return queueCreated(ctx, created, { fresh: true })
}

/**
 * Tells STAR about a made ticket exactly once (follow-up D1): record a path before writing its inbox
 * file, then settle the record as queued. The file is read before STAR's ledger because STAR writes
 * its ledger row before deleting an inbox file, so an absent file with no row was never written.
 * `fresh` skips the ledger only for a ticket made in the same call; a resume always reads it.
 */
export async function queueCreated(ctx: Pick<CreateContext, 'project' | 'home' | 'repo' | 'dir' | 'log'>, created: Created, options: { fresh?: boolean } = {}): Promise<CreateOutcome> {
  const name = created.ref ?? created.specPath ?? ''
  const content = inboxContent(ctx.repo, name)
  const inbox = join(ctx.home, 'inbox')
  const trusted = (value: string | null | undefined): string | null => {
    if (typeof value !== 'string' || dirname(value) !== inbox || !INBOX_NAME.test(basename(value))) return null
    return value
  }
  let record = created
  let path = trusted(created.inbox)
  if (typeof created.inbox === 'string' && path === null) {
    ctx.log(`briefing ${ctx.project}/${basename(ctx.dir)}: the record names ${created.inbox}, outside STAR's inbox ${inbox}: drawing a new inbox path`)
  }
  const settle = async (how: 'file' | 'ledger', found = false): Promise<CreateOutcome> => {
    const settled: Created = { ...record, queued: true }
    try {
      await rewriteCreated(ctx.dir, settled)
    } catch (err) {
      if (how === 'ledger') {
        return { ok: false, error: `STAR's ledger already has ${name}, but created.json could not record it: ${message(err)}. Press Create again to record it; no inbox file is written.`, made: record }
      }
      return { ok: false, error: `${name} is in STAR's inbox (${path}), but created.json could not record it: ${message(err)}. Press Create again to record it; no second inbox file is written.`, made: record }
    }
    if (how === 'ledger' && !options.fresh) ctx.log(`briefing ${ctx.project}/${basename(ctx.dir)}: STAR's ledger already has ${name}: recorded as queued, no inbox file written`)
    if (how === 'file' && found) ctx.log(`briefing ${ctx.project}/${basename(ctx.dir)}: ${name} is already in STAR's inbox (${path}): recorded as queued`)
    return { ok: true, created: settled }
  }
  for (let round = 0; round < 100; round++) {
    if (path === null) {
      let drawn: string
      try {
        drawn = await drawInbox(ctx.home)
      } catch (err) {
        return { ok: false, error: `${name} was made, but STAR's inbox file could not be written: ${message(err)}. Press Create again to send it to STAR.`, made: record }
      }
      const ahead: Created = { ...record, inbox: drawn, queued: false }
      try {
        await rewriteCreated(ctx.dir, ahead)
      } catch (err) {
        return { ok: false, error: `${name} was made, but created.json could not record its inbox path: ${message(err)}. No inbox file was written; press Create again to send it to STAR.`, made: record }
      }
      record = ahead
      path = drawn
    }
    let existing: string | null
    try {
      existing = await readText(path)
    } catch (err) {
      return { ok: false, error: `${name} was made, but its recorded inbox path ${path} could not be read: ${message(err)}. Nothing was written; move whatever is at that path aside, then press Create again.`, made: record }
    }
    if (existing === content) {
      return settle('file', true)
    } else if (existing === null) {
      if (!options.fresh) {
        let ledger: string[]
        try {
          ledger = await ledgerRefs(ctx.home)
        } catch (err) {
          return { ok: false, error: `${name} was made, but STAR's ledger could not be checked for it, so no inbox file was written: ${message(err)}. Press Create again once the dashboard can read STAR's ledger.`, made: record }
        }
        if (ledger.includes(name)) {
          return settle('ledger')
        }
      }
      try {
        if (!await linkNew(path, content)) continue
      } catch (err) {
        return { ok: false, error: `${name} was made, but STAR's inbox file could not be written: ${message(err)}. Press Create again to send it to STAR.`, made: record }
      }
      return settle('file')
    } else {
      ctx.log(`briefing ${ctx.project}/${basename(ctx.dir)}: ${path} holds another file, so ${name} gets a new inbox path`)
      path = null
      continue
    }
  }
  return { ok: false, error: `${name} was made, but STAR's inbox file could not be written: no free inbox name in ${inbox}. Press Create again to send it to STAR.`, made: record }
}
