// One briefing turn (brief D2, D3, D6, D7, D10): runs the read-only agent on the owner's text,
// streams its reply as briefing events and, only when the turn succeeds, saves the draft and appends
// both turns to the transcript. A turn the CLI fails writes nothing but the session id its init event
// gave; a disk error while saving can still leave the new draft without its turns.
import { readFile } from 'node:fs/promises'
import { isAbsolute, relative, sep } from 'node:path'

import { contentOf, message, runCli, tail } from './claude.ts'
import type { CliEvent } from './claude.ts'
import { appendTurns, clearSession, readSession, writeDraft, writeSession } from './store.ts'
import { extractTicket, stripTickets } from './ticket.ts'
import type { Ticket } from './ticket.ts'
import type { ModuleApi } from './types.ts'

/** The only tools a turn has, and the ones it may use without asking (D2). */
export const TURN_TOOLS = 'Read,Grep,Glob'
export const PROMPT_URL = new URL('./prompt.md', import.meta.url)
// What the CLI prints on stderr when --resume names a session it no longer has (claude 2.1.301,
// checked 2026-10-16): it exits 1 before any init line.
const GONE = /No conversation found with session ID/

export type TurnContext = {
  project: string
  id: string
  repo: string
  dir: string
  text: string
  emit: ModuleApi['emit']
  log: ModuleApi['log']
}
export type TurnResult = { ok: true; text: string; files: string[]; draft: Ticket } | { ok: false; error: string }

/** The turn's argv. The owner's text comes after `--`, so no text is ever read as a flag (B3). */
export function turnArgs(prompt: string, session: string | null, text: string): string[] {
  return [
    '-p', '--model', 'opus', '--output-format', 'stream-json', '--verbose',
    '--tools', TURN_TOOLS, '--strict-mcp-config', '--allowedTools', TURN_TOOLS,
    '--append-system-prompt', prompt,
    ...(session ? ['--resume', session] : []),
    '--', text,
  ]
}

/** A Read path as the transcript keeps it: relative to the repo when inside it, else as given (D7). */
export function repoPath(repo: string, file: string): string {
  if (!isAbsolute(file)) return file
  const rel = relative(repo, file)
  return rel === '' || rel === '..' || rel.startsWith(`..${sep}`) || isAbsolute(rel) ? file : rel
}

export async function runTurn(ctx: TurnContext): Promise<TurnResult> {
  const send = (fields: Record<string, unknown>): void => ctx.emit({ type: 'briefing', project: ctx.project, id: ctx.id, ...fields })
  const fail = (error: string): TurnResult => {
    send({ error })
    ctx.log(`briefing ${ctx.project}/${ctx.id}: turn failed: ${error}`)
    return { ok: false, error }
  }
  let prompt: string
  try {
    prompt = await readFile(PROMPT_URL, 'utf8')
  } catch (err) {
    return fail(`prompt.md could not be read: ${message(err)}`)
  }
  const stored = await readSession(ctx.dir)
  const texts: string[] = []
  const files: string[] = []
  let sawInit = false
  let result: CliEvent | null = null
  // Resolves to the error message, or null; caught at once so a failed write never goes unhandled.
  let sessionSaved: Promise<string | null> = Promise.resolve(null)

  const onEvent = (event: CliEvent): void => {
    if (event.type === 'system' && event.subtype === 'init') {
      // Hook lines come before init, the first line that carries the session id (D3).
      sawInit = true
      const session = event.session_id
      if (typeof session === 'string' && session !== '' && session !== stored) {
        sessionSaved = writeSession(ctx.dir, session).then(() => null, message)
      }
      return
    }
    if (event.type === 'result') {
      result = event
      return
    }
    if (event.type !== 'assistant') return
    const blocks = contentOf(event)
    if (!blocks) return
    for (const block of blocks) {
      if (block?.type === 'text' && typeof block.text === 'string') texts.push(block.text)
      if (block?.type === 'tool_use' && block.name === 'Read') {
        const path = (block.input as { file_path?: unknown } | undefined)?.file_path
        const file = typeof path === 'string' ? repoPath(ctx.repo, path) : null
        if (file !== null && !files.includes(file)) files.push(file)
      }
    }
    send({ turn: { who: 'agent', text: stripTickets(texts.join('\n\n')), files: [...files], done: false } })
  }

  const exit = await runCli({ bin: 'claude', args: turnArgs(prompt, stored, ctx.text), cwd: ctx.repo, onEvent }).done
  const sessionError = await sessionSaved
  if (exit.spawnError) return fail(`claude could not start: ${exit.spawnError}`)
  if (exit.handlerError) return fail(`the turn's output could not be handled: ${exit.handlerError}`)
  if (sessionError) return fail(`the session id could not be saved: ${sessionError}`)
  const final = result as CliEvent | null
  const resultText = typeof final?.result === 'string' ? final.result : ''
  if (stored && !(sawInit as boolean) && GONE.test(exit.stderr)) {
    try {
      await clearSession(ctx.dir)
    } catch (err) {
      return fail(`the saved session ${stored} is gone, and it could not be forgotten: ${message(err)}`)
    }
    return fail(`the saved session ${stored} is gone: send the message again to start a new one`)
  }
  if (exit.code !== 0) return fail(`claude exited with ${exit.code ?? exit.signal}: ${tail(exit.stderr) || tail(resultText) || 'no output'}`)
  if (!final || final.is_error === true) return fail(`claude reported an error: ${tail(resultText) || 'no result line'}`)
  const { shown, ticket } = extractTicket(texts.length > 0 ? texts.join('\n\n') : resultText)
  if (!ticket) return fail('the reply had no valid ticket block')
  const at = new Date().toISOString()
  try {
    await writeDraft(ctx.dir, ticket)
    await appendTurns(ctx.dir, [{ who: 'me', text: ctx.text, files: [], at }, { who: 'agent', text: shown, files, at }])
  } catch (err) {
    return fail(`the turn could not be saved: ${message(err)}`)
  }
  send({ turn: { who: 'agent', text: shown, files, done: true, draft: ticket } })
  return { ok: true, text: shown, files, draft: ticket }
}
