import type { QueryClient, QueryKey } from "@tanstack/react-query"
import { useSyncExternalStore } from "react"
import { apiHeaders, apiUrl } from "./client"
import { paths } from "./paths"
import type { BriefingEvent, ChangeEvent } from "./types"
export type ConnectionState = "connecting" | "open" | "lost"
let connection: ConnectionState = "connecting"
const connectionListeners = new Set<() => void>()
export const getConnection = (): ConnectionState => connection
export function setConnection(next: ConnectionState): void {
  if (connection === next) return
  connection = next
  connectionListeners.forEach((listener) => listener())
}
export function subscribeConnection(listener: () => void): () => void {
  connectionListeners.add(listener)
  return () => connectionListeners.delete(listener)
}
export const useConnection = (): ConnectionState =>
  useSyncExternalStore(subscribeConnection, getConnection, getConnection)
const briefingListeners = new Set<(event: BriefingEvent) => void>()
export function subscribeBriefing(
  listener: (event: BriefingEvent) => void
): () => void {
  briefingListeners.add(listener)
  return () => briefingListeners.delete(listener)
}
export function parseFrames(buffer: string): {
  events: unknown[]
  rest: string
} {
  const frames = buffer.replace(/\r\n/g, "\n").split("\n\n")
  const rest = frames.pop() ?? ""
  const events: unknown[] = []
  for (const frame of frames) {
    const data = frame
      .split("\n")
      .filter((line) => line.startsWith("data:"))
      .map((line) => line.slice(5).replace(/^ /, ""))
      .join("\n")
    if (!data) continue
    try {
      events.push(JSON.parse(data))
    } catch {}
  }
  return { events, rest }
}
export function keysFor(event: ChangeEvent): QueryKey[] {
  const scoped = (key: string): QueryKey =>
    event.project ? [key, event.project] : [key]
  switch (event.what) {
    case "loops":
      return [scoped("loops"), ["projects"]]
    case "ledger":
    case "progress":
      return [scoped("items"), scoped("item"), scoped("overview"), ["projects"]]
    case "evidence":
      return [scoped("evidence")]
    case "drafts":
    case "slack":
      return [["slack"], ["draft"]]
    case "briefings":
      return [scoped("briefings"), scoped("briefing")]
    default:
      return []
  }
}
function dispatch(client: QueryClient, raw: unknown): void {
  if (!raw || typeof raw !== "object") return
  const event = raw as { type?: unknown }
  if (event.type === "change")
    for (const queryKey of keysFor(raw as ChangeEvent))
      void client.invalidateQueries({ queryKey })
  else if (event.type === "briefing")
    briefingListeners.forEach((listener) => listener(raw as BriefingEvent))
}
function sleep(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms)
    signal.addEventListener(
      "abort",
      () => {
        clearTimeout(timer)
        resolve()
      },
      { once: true }
    )
  })
}
export type EventsOptions = { retryMs?: number; fetchImpl?: typeof fetch }
export function startEvents(
  client: QueryClient,
  options: EventsOptions = {}
): () => void {
  const retryMs = options.retryMs ?? 5000
  const fetchImpl = options.fetchImpl ?? ((input, init) => fetch(input, init))
  const controller = new AbortController()
  let lostOnce = false
  const run = async () => {
    while (!controller.signal.aborted) {
      try {
        const res = await fetchImpl(apiUrl(paths.events()), {
          headers: apiHeaders({ Accept: "text/event-stream" }),
          signal: controller.signal,
        })
        if (!res.ok || !res.body)
          throw new Error(`the event stream answered ${res.status}`)
        setConnection("open")
        if (lostOnce) void client.invalidateQueries()
        const reader = res.body.getReader()
        const decoder = new TextDecoder()
        let buffer = ""
        for (;;) {
          const { value, done } = await reader.read()
          if (done) break
          buffer += decoder.decode(value, { stream: true })
          const parsed = parseFrames(buffer)
          buffer = parsed.rest
          parsed.events.forEach((event) => dispatch(client, event))
        }
        throw new Error("the event stream ended")
      } catch {
        if (controller.signal.aborted) return
        lostOnce = true
        setConnection("lost")
        await sleep(retryMs, controller.signal)
      }
    }
  }
  void run()
  return () => controller.abort()
}
