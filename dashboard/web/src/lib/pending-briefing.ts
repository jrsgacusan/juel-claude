import { useSyncExternalStore } from "react"

/** The owner's message while its turn runs (briefing D7). `failed` says why the turn stopped;
 * `sentAt` is when the server took the message (the POST's 202), null until then. */
export type PendingBriefing = {
  text: string
  failed: string | null
  sentAt: number | null
}
const pending = new Map<string, PendingBriefing>()
const listeners = new Set<() => void>()
const keyOf = (project: string, id: string) => `${project}\u0000${id}`
const subscribe = (listener: () => void) => {
  listeners.add(listener)
  return () => listeners.delete(listener)
}
const get = (project: string, id: string): PendingBriefing | null =>
  pending.get(keyOf(project, id)) ?? null

export function usePendingBriefing(project: string, id: string | null) {
  return useSyncExternalStore(
    subscribe,
    () => (id ? get(project, id) : null),
    () => (id ? get(project, id) : null)
  )
}

export function getPendingBriefing(
  project: string,
  id: string
): PendingBriefing | null {
  return get(project, id)
}

/** Tests start with no pending messages. */
export function clearPendingBriefings(): void {
  pending.clear()
  listeners.forEach((listener) => listener())
}

export function setPendingBriefing(
  project: string,
  id: string,
  value: PendingBriefing | null
) {
  const key = keyOf(project, id)
  if (value) pending.set(key, value)
  else pending.delete(key)
  listeners.forEach((listener) => listener())
}
