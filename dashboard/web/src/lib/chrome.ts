import { useSyncExternalStore } from "react"

/** Whether a phone list-detail page is showing its detail; the tab bar hides then. */
let detailOpen = false
const listeners = new Set<() => void>()
const subscribe = (listener: () => void) => {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function setDetailOpen(open: boolean): void {
  if (detailOpen === open) return
  detailOpen = open
  listeners.forEach((listener) => listener())
}

export function useDetailOpen(): boolean {
  return useSyncExternalStore(subscribe, () => detailOpen, () => detailOpen)
}

/** Tests start with the tab bar showing. */
export function resetChrome(): void {
  setDetailOpen(false)
}
