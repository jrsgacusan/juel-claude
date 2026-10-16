import type { IncomingMessage, ServerResponse } from 'node:http'

/** An error the client caused or asked for: its status and a one-line message go back as JSON. */
export class HttpError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

/** A STAR file that could not be read or parsed: its endpoint answers 502 naming it, the others keep working. */
export class Unreadable extends Error {
  file: string
  why: string
  constructor(file: string, why: string) {
    super(`${file}: ${why}`)
    this.file = file
    this.why = why
  }
}

/** A filesystem error in a few words. */
export function whyOf(err: unknown): string {
  const e = err as { code?: unknown; message?: unknown }
  if (e.code === 'ENOENT') return 'not found'
  if (e.code === 'EACCES' || e.code === 'EPERM') return 'permission denied'
  if (e.code === 'EISDIR') return 'is a folder'
  return typeof e.message === 'string' ? e.message : String(err)
}

export function sendJson(res: ServerResponse, status: number, body: unknown): void {
  const text = JSON.stringify(body === undefined ? null : body)
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'content-length': Buffer.byteLength(text),
  })
  res.end(text)
}

const LIMIT = 1024 * 1024

/** The request's JSON body; undefined when it has none. Larger than 1 MB is 413, not JSON is 400. */
export async function readJson(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = []
  let size = 0
  for await (const chunk of req) {
    const buf = chunk as Buffer
    size += buf.length
    if (size > LIMIT) throw new HttpError(413, 'the body is larger than 1 MB')
    chunks.push(buf)
  }
  const text = Buffer.concat(chunks).toString('utf8').trim()
  if (!text) return undefined
  try {
    return JSON.parse(text) as unknown
  } catch {
    throw new HttpError(400, 'the body is not JSON')
  }
}
