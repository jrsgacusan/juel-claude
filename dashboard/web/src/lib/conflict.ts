import { useSyncExternalStore } from "react"
let conflictProject: string | null = null
const listeners = new Set<() => void>()
export function setConflict(project: string | null): void {
  if (conflictProject === project) return
  conflictProject = project
  listeners.forEach((listener) => listener())
}
export const getConflict = (): string | null => conflictProject
function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}
export const useConflict = (): string | null =>
  useSyncExternalStore(subscribe, getConflict, getConflict)
