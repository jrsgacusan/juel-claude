// The drafter (spec 3.5, D6, D7): one read-only `claude -p` run in the routed project's repository
// that writes the owner's reply to one Slack message. Nothing here sends anything: the run can use
// the pinned read tools only, and its answer is a {"reply"} that this module writes to a draft file.
// Also the draft file helpers, the one-at-a-time wrapper and the free-memory gate (I-12).
import { randomBytes } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { mkdir, readdir, rename, rm, writeFile } from 'node:fs/promises'
import { freemem } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { errorText, runCli } from './claude.ts'
import { channelLabel } from './inbox.ts'
import { unfence } from './parse.ts'
import { loadConfig, pluginIds, readSlackSettings } from './settings.ts'
import type { Config, PluginIds } from './settings.ts'
import { MINUTE_MS, isObject, oneLine } from './state.ts'
import type { Message } from './state.ts'
import type { Project } from './types.ts'

const HERE = dirname(fileURLToPath(import.meta.url))

export type DraftRequest = { project: Project; message: Message; how?: string; previous?: string }
export type DraftOptions = { bin?: string; model?: string; timeoutMs?: number; plugins?: boolean }
export type DraftResult = { ok: true; text: string } | { ok: false; why: string }
export type Drafter = (req: DraftRequest) => Promise<DraftResult>

/** What a redraft adds to the prompt. */
const REWRITE = `The owner asked for a new version of the reply below: {{how}}
<previous-reply>
{{previous}}
</previous-reply>
Keep what they did not ask to change.
`

/** The read-only run: no Write or Edit, no git, gh reads, the pinned Slack and Linear reads. */
export function draftArgs(model: string, home: string, plugins: PluginIds | null, config: Config): string[] {
  const enabled: Record<string, boolean> = plugins === null ? {} : { [plugins.slack]: true, [plugins.linear]: true }
  const allowed = [...config.drafter.allowedTools, ...(plugins === null ? [] : [...config.allowedTools, ...config.drafter.linearTools])]
  return [
    '-p',
    '--model',
    model,
    '--output-format',
    'json',
    '--restricted',
    '--tools',
    'Read,Grep,Glob,Bash',
    '--settings',
    JSON.stringify({ enabledPlugins: enabled }),
    '--add-dir',
    home,
    '--allowedTools',
    allowed.join(','),
    '--disallowedTools',
    [...config.drafter.disallowedTools, ...config.disallowedTools].join(','),
    '--permission-mode',
    'dontAsk',
    '--no-session-persistence',
  ]
}

const oneLineOf = (text: string): string => text.replace(/\s+/g, ' ').trim()

/** Fills the template in one pass, so text from Slack is never scanned for placeholders. */
export function draftPrompt(template: string, req: DraftRequest): string {
  const m = req.message
  const fields: Record<string, string> = {
    project: req.project.name,
    repo: req.project.repo,
    home: req.project.home,
    from: oneLineOf(m.from),
    channel: oneLineOf(channelLabel(m.channelId, m.channel)),
    permalink: m.permalink,
    text: m.text,
    thread: m.thread.join('\n'),
    rewrite:
      req.how === undefined
        ? ''
        : REWRITE.replace(/\{\{(\w+)\}\}/g, (_all, key: string) => (key === 'how' ? req.how ?? '' : key === 'previous' ? req.previous ?? '' : '')),
  }
  return template.replace(/\{\{(\w+)\}\}/g, (all, key: string) => fields[key] ?? all)
}

const NOT_JSON = "the drafter's answer is not the expected JSON"

export function parseDraft(stdout: string): DraftResult {
  let envelope: unknown
  try {
    envelope = JSON.parse(stdout)
  } catch {
    return { ok: false, why: NOT_JSON }
  }
  if (!isObject(envelope)) return { ok: false, why: NOT_JSON }
  if (envelope.is_error === true) {
    const subtype = typeof envelope.subtype === 'string' ? oneLine(envelope.subtype, 60) : 'is_error'
    return { ok: false, why: `claude reported an error (${subtype})` }
  }
  if (typeof envelope.result !== 'string') return { ok: false, why: NOT_JSON }
  let data: unknown
  try {
    data = JSON.parse(unfence(envelope.result))
  } catch {
    return { ok: false, why: NOT_JSON }
  }
  if (!isObject(data) || typeof data.reply !== 'string') return { ok: false, why: NOT_JSON }
  const text = data.reply.trim()
  return text === '' ? { ok: false, why: 'the drafter wrote an empty reply' } : { ok: true, text }
}

/** Never rejects: every way a draft can fail comes back as a why. */
export async function draftReply(req: DraftRequest, opts: DraftOptions = {}): Promise<DraftResult> {
  try {
    const settings = readSlackSettings()
    const config = loadConfig()
    const model = opts.model ?? settings.drafter.model
    const timeoutMs = opts.timeoutMs ?? settings.drafter.timeoutMin * MINUTE_MS
    const plugins = opts.plugins === false ? null : pluginIds(config, settings)
    const template = readFileSync(join(HERE, 'drafter-prompt.md'), 'utf8')
    const out = await runCli({
      bin: opts.bin ?? 'claude',
      args: draftArgs(model, req.project.home, plugins, config),
      cwd: req.project.repo,
      input: draftPrompt(template, req),
      timeoutMs,
    })
    if (out.spawnError !== null) return { ok: false, why: `claude could not start: ${oneLine(out.spawnError)}` }
    if (out.timedOut) return { ok: false, why: `the drafter did not answer within ${Math.round(timeoutMs / 1000)} s` }
    if (out.tooLarge) return { ok: false, why: 'the drafter printed more than the dashboard reads' }
    if (out.code !== 0) {
      const how = out.code === null ? `on ${out.signal ?? 'a signal'}` : String(out.code)
      const last = oneLine(out.stderr.trim().split('\n').pop() ?? '')
      return { ok: false, why: `claude exited ${how}${out.stderr.trim() ? `: ${last}` : ''}` }
    }
    return parseDraft(out.stdout)
  } catch (err) {
    return { ok: false, why: oneLine(errorText(err)) }
  }
}

/** A promise chain that never rejects: each act runs after the one before it, however that one ended. */
export function serial(): <T>(act: () => Promise<T>) => Promise<T> {
  let chain: Promise<unknown> = Promise.resolve()
  return act => {
    const next = chain.then(act)
    chain = next.catch(() => undefined)
    return next
  }
}

/** The draft file's first line: "to: slack <channelId> <threadTs, or ts>". */
export const toLine = (m: Pick<Message, 'channelId' | 'ts' | 'threadTs'>): string => `to: slack ${m.channelId} ${m.threadTs ?? m.ts}`

/** <UTC YYYY-MM-DD>-<project>-slack-<id>.md */
export const draftName = (project: string, id: string, at: Date): string => `${at.toISOString().slice(0, 10)}-${project}-slack-${id}.md`

/** The `to` line, then the text when it is not blank, written whole: a temp file, then a rename. */
export async function writeDraft(path: string, to: string, text: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  const body = text.trim()
  const tmp = `${path}.${process.pid}.${randomBytes(3).toString('hex')}.tmp`
  try {
    await writeFile(tmp, `${to}\n${body === '' ? '' : `${body}\n`}`)
    await rename(tmp, path)
  } catch (err) {
    await rm(tmp, { force: true })
    throw err
  }
}

/** The newest draft file of a message in <home>/drafts, or null. */
export async function findDraft(home: string, id: string): Promise<string | null> {
  const dir = join(home, 'drafts')
  let names: string[]
  try {
    names = await readdir(dir)
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') return null
    throw err
  }
  const best = names.filter(name => name.endsWith(`-slack-${id}.md`)).sort().at(-1)
  return best === undefined ? null : join(dir, best)
}

export const MIN_FREE_BYTES = 3 * 1024 ** 3

/** (free + inactive pages) x page size from vm_stat's text; null when it does not read. */
export function parseVmStat(text: string): number | null {
  const size = /page size of (\d+) bytes/.exec(text)?.[1]
  const free = /Pages free:\s+(\d+)\./.exec(text)?.[1]
  const inactive = /Pages inactive:\s+(\d+)\./.exec(text)?.[1]
  if (size === undefined || free === undefined || inactive === undefined) return null
  return (Number(free) + Number(inactive)) * Number(size)
}

/** Free memory in bytes: vm_stat on PATH, else os.freemem(). */
export async function freeMemory(): Promise<number> {
  const out = await runCli({ bin: 'vm_stat', args: [], cwd: process.cwd(), input: '', timeoutMs: 5000 })
  const parsed = out.spawnError === null && out.code === 0 ? parseVmStat(out.stdout) : null
  return parsed ?? freemem()
}
