// D7: what counts as the expected JSON. The CLI's --output-format json envelope must not be
// is_error and must carry a result string; the result (one json code fence stripped) is an array of
// messages, {"workspace", "messages"} (D8) or {"connected": false, "why"}. One invalid element fails
// the whole answer. Error texts never quote the answer, which holds message text: they are fixed
// words, plus the envelope's subtype when claude reports an error.
import { isObject, messageProblem, oneLine } from './state.ts'
import type { Message, Owner } from './state.ts'

export type Parsed =
  | { kind: 'messages'; workspace: string | null; messages: Message[]; owner: Owner | null }
  | { kind: 'disconnected'; why: string }
  | { kind: 'error'; error: string; cli: boolean }

const FENCE = /^\s*```(?:json)?[ \t]*\n([\s\S]*?)\n?[ \t]*```\s*$/

const bad = (why: string): Parsed => ({ kind: 'error', error: `the answer is not the expected JSON: ${why}`, cli: false })

export function parseEnvelope(stdout: string): Parsed {
  let envelope: unknown
  try {
    envelope = JSON.parse(stdout)
  } catch {
    return bad('the CLI output is not JSON')
  }
  if (!isObject(envelope)) return bad('the CLI output is not a JSON object')
  if (envelope.is_error === true) {
    const subtype = typeof envelope.subtype === 'string' ? oneLine(envelope.subtype, 60) : 'is_error'
    return { kind: 'error', error: `claude reported an error (${subtype})`, cli: true }
  }
  if (typeof envelope.result !== 'string') return bad('the CLI output has no result text')
  return parseResult(envelope.result)
}

export function parseResult(text: string): Parsed {
  const fenced = FENCE.exec(text)
  let data: unknown
  try {
    data = JSON.parse(fenced ? (fenced[1] ?? '') : text)
  } catch {
    return bad('the result is not JSON')
  }
  let workspace: string | null = null
  let owner: Owner | null = null
  let list: unknown[]
  if (Array.isArray(data)) {
    list = data
  } else if (isObject(data)) {
    if (data.connected === false) {
      return { kind: 'disconnected', why: typeof data.why === 'string' && data.why.trim() ? oneLine(data.why, 200) : 'no reason given' }
    }
    if (!Array.isArray(data.messages)) return bad('the result has no messages array')
    if (data.workspace !== undefined && data.workspace !== null && typeof data.workspace !== 'string') return bad('workspace is not a string')
    workspace = typeof data.workspace === 'string' && data.workspace.trim() ? oneLine(data.workspace, 100) : null
    if (data.owner !== undefined && data.owner !== null) {
      const o = data.owner
      if (!isObject(o) || typeof o.id !== 'string' || o.id.trim() === '' || typeof o.displayName !== 'string' || typeof o.realName !== 'string') {
        return bad('owner is not {id, displayName, realName}')
      }
      owner = { id: oneLine(o.id, 100), displayName: oneLine(o.displayName, 100), realName: oneLine(o.realName, 100) }
    }
    list = data.messages
  } else {
    return bad('the result is not an array or an object')
  }
  const messages: Message[] = []
  for (const [i, item] of list.entries()) {
    const why = messageProblem(item)
    if (why) return bad(`message ${i + 1}: ${why}`)
    const m = item as Message
    if (m.why !== 'dm' && m.why !== 'mention' && m.why !== 'asks') return bad(`message ${i + 1}: why is not dm, mention or asks`)
    messages.push({
      channelId: m.channelId,
      channel: m.channel,
      ts: m.ts,
      threadTs: m.threadTs,
      from: m.from,
      text: m.text,
      permalink: m.permalink,
      thread: [...m.thread],
      why: m.why,
    })
  }
  return { kind: 'messages', workspace, messages, owner }
}
