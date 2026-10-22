import { useSyncExternalStore } from "react"

const KEY = "star-last-project"
// undefined: not read from storage yet.
let current: string | null | undefined
const listeners = new Set<() => void>()
const subscribe = (listener: () => void) => {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function lastProject(): string | null {
  if (current === undefined) {
    try {
      current = localStorage.getItem(KEY)
    } catch {
      current = null
    }
  }
  return current
}

export function rememberProject(name: string): void {
  if (lastProject() === name) return
  current = name
  try {
    localStorage.setItem(KEY, name)
  } catch {
    // Storage is blocked: the choice lasts for this session only.
  }
  listeners.forEach((listener) => listener())
}

export function useLastProject(): string | null {
  return useSyncExternalStore(subscribe, lastProject, () => null)
}

/** Tests start with nothing remembered. */
export function resetLastProject(): void {
  current = undefined
  listeners.forEach((listener) => listener())
}
