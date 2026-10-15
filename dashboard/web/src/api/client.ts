import type { ApiErrorBody } from "./types"
import { getToken } from "./token"

export class ApiError extends Error {
  readonly status: number
  constructor(status: number, message: string) {
    super(message)
    this.name = "ApiError"
    this.status = status
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
async function errorMessage(res: Response): Promise<string> {
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
  const res = await fetch(apiUrl(path), {
    ...init,
    headers: apiHeaders(init.headers),
  })
  if (!res.ok) throw new ApiError(res.status, await errorMessage(res))
  return res
}
export async function apiJson<T>(path: string, init?: RequestInit): Promise<T> {
  const text = await (await apiFetch(path, init)).text()
  return (text ? JSON.parse(text) : null) as T
}
export function sendJson<T>(
  method: "POST" | "PUT",
  path: string,
  body: unknown
): Promise<T> {
  return apiJson<T>(path, {
    method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  })
}
