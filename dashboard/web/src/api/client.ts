import type { ApiErrorBody } from "./types"
import { getToken } from "./token"
import { paths } from "./paths"

export class ApiError extends Error {
  readonly status: number
  constructor(status: number, message: string) {
    super(message)
    this.name = "ApiError"
    this.status = status
  }
}
/** A 409 from the answer route that names conflict markers in open-loops.md. The same route
 * also answers 409 for a loop that already has an answer, which is not a conflict. */
export function isConflictMarkers(error: unknown): boolean {
  return (
    error instanceof ApiError &&
    error.status === 409 &&
    /conflict markers/i.test(error.message)
  )
}
/** fetch itself failed: the server is down, unreachable or refused the connection. */
export class NetworkError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "NetworkError"
  }
}
export const apiUrl = (path: string): string =>
  new URL(path, window.location.origin).toString()
export function apiHeaders(extra?: HeadersInit): Headers {
  const headers = new Headers(extra)
  const token = getToken()
  if (token) headers.set("X-Star-Token", token)
  return headers
}
async function bodyMessage(res: Response): Promise<string> {
  const text = await res.text().catch(() => "")
  try {
    const body = JSON.parse(text) as ApiErrorBody
    return (
      body.error ??
      body.message ??
      (text || res.statusText || `HTTP ${res.status}`)
    )
  } catch {
    return text || res.statusText || `HTTP ${res.status}`
  }
}
export async function apiFetch(
  path: string,
  init: RequestInit = {}
): Promise<Response> {
  let res: Response
  try {
    res = await fetch(apiUrl(path), {
      ...init,
      headers: apiHeaders(init.headers),
    })
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError")
      throw error
    throw new NetworkError(
      error instanceof Error ? error.message : String(error)
    )
  }
  if (!res.ok) throw new ApiError(res.status, await bodyMessage(res))
  return res
}
export type TokenCheck = "accepted" | "refused" | "unreachable"
/** Asks the server whether a token passes, storing nothing. */
export async function checkToken(token: string): Promise<TokenCheck> {
  try {
    const res = await fetch(apiUrl(paths.projects()), {
      headers: { "X-Star-Token": token },
    })
    return res.status === 401 ? "refused" : "accepted"
  } catch {
    return "unreachable"
  }
}
export async function apiJson<T>(
  path: string,
  init?: RequestInit,
  options: { allowEmpty?: boolean } = {}
): Promise<T> {
  const response = await apiFetch(path, init)
  const text = await response.text()
  if (!text) {
    if (options.allowEmpty) return null as T
    throw new ApiError(
      response.status,
      `The dashboard server sent an empty answer for ${path}.`
    )
  }
  try {
    return JSON.parse(text) as T
  } catch {
    throw new ApiError(
      response.status,
      `The dashboard server sent something that is not JSON for ${path}.`
    )
  }
}
// keepalive: the request survives the page unloading (a one-tap answer flushed as the tab closes).
export function sendJson<T>(
  method: "POST" | "PUT",
  path: string,
  body: unknown,
  options: { keepalive?: boolean } = {}
): Promise<T> {
  return apiJson<T>(
    path,
    {
      method,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      ...(options.keepalive ? { keepalive: true } : {}),
    },
    { allowEmpty: true }
  )
}
