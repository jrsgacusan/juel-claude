// D7: what counts as the expected JSON. The CLI's --output-format json envelope must not be
// is_error and must carry a result string; the result (one json code fence stripped) is an array of
// messages, {"workspace", "messages"} (D8) or {"connected": false, "why"}. One invalid element fails
// the whole answer. Error texts are fixed words: they never quote the answer, which holds message
// text.
import type { Message } from './state.ts'

export type Parsed =
  | { kind: 'messages'; workspace: string | null; messages: Message[] }
  | { kind: 'disconnected'; why: string }
  | { kind: 'error'; error: string; cli: boolean }

const FENCE = /^\s*```(?:json)?[ \t]*\n([\s\S]*?)\n?[ \t]*```\s*$/
const CHANNEL_ID = /^[A-Z0-9]+$/i
const TS = /^\d+\.\d+$/
const STRINGS = ['channelId', 'channel', 'ts', 'from', 'text', 'permalink']

const bad = (why: string): Parsed => ({ kind: 'error', error: `the answer is not the expected JSON: ${why}`, cli: false })
const oneLine = (text: string, max: number): string => text.replace(/\s+/g, ' ').trim().slice(0, max)
const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

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
    list = data.messages
  } else {
    return bad('the result is not an array or an object')
  }
  const messages: Message[] = []
  for (const [i, item] of list.entries()) {
    const why = invalid(item)
    if (why) return bad(`message ${i + 1}: ${why}`)
    const m = item as Message
    messages.push({
      channelId: m.channelId,
      channel: m.channel,
      ts: m.ts,
      threadTs: m.threadTs,
      from: m.from,
      text: m.text,
      permalink: m.permalink,
      thread: [...m.thread],
    })
  }
  return { kind: 'messages', workspace, messages }
}

/** Why one element is not a message of the item's step 2 (with S10's path-safe ids), else null. */
function invalid(item: unknown): string | null {
  if (!isObject(item)) return 'not an object'
  for (const key of STRINGS) if (typeof item[key] !== 'string') return `${key} is not a string`
  if (!CHANNEL_ID.test(item.channelId as string)) return 'channelId is not a Slack id'
  if (!TS.test(item.ts as string)) return 'ts is not a Slack ts'
  if (item.threadTs !== null && !(typeof item.threadTs === 'string' && TS.test(item.threadTs))) return 'threadTs is not a Slack ts or null'
  if (!(item.permalink as string).startsWith('https://')) return 'permalink is not an https link'
  if (!Array.isArray(item.thread) || item.thread.length > 5 || !item.thread.every(line => typeof line === 'string')) {
    return 'thread is not at most 5 strings'
  }
  return null
}