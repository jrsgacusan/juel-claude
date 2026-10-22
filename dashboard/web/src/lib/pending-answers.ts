import { useSyncExternalStore } from "react"

/** How long a one-tap answer waits, so Undo can cancel it. */
export const HOLD_MS = 5000
export type PendingState = "held" | "sending" | null

type Entry = { send: () => Promise<unknown>; timer: ReturnType<typeof setTimeout> | null; state: "held" | "sending" }
const entries = new Map<string, Entry>()
const listeners = new Set<() => void>()
const notify = () => listeners.forEach((listener) => listener())
const subscribe = (listener: () => void) => {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

let listening = false
function listen() {
  if (listening) return
  listening = true
  // A locked phone or a closed tab must not lose a tap: post the held answers now.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") flushAnswers()
  })
  window.addEventListener("pagehide", flushAnswers)
}

function run(key: string, entry: Entry) {
  if (entry.state !== "held") return
  if (entry.timer) clearTimeout(entry.timer)
  entry.timer = null
  entry.state = "sending"
  notify()
  const settle = () => {
    // A newer answer under the same key stays.
    if (entries.get(key) === entry) entries.delete(key)
    notify()
  }
  let sent: Promise<unknown>
  try {
    sent = Promise.resolve(entry.send())
  } catch (error) {
    sent = Promise.reject(error)
  }
  sent.then(settle, settle)
}

/** Holds an answer for HOLD_MS, then sends it; a second hold under the same key replaces a held one. */
export function holdAnswer(key: string, send: () => Promise<unknown>): void {
  listen()
  const old = entries.get(key)
  if (old?.state === "held" && old.timer) clearTimeout(old.timer)
  const entry: Entry = { send, timer: null, state: "held" }
  entry.timer = setTimeout(() => run(key, entry), HOLD_MS)
  entries.set(key, entry)
  notify()
}

/** True when it cancelled a held answer. */
export function undoAnswer(key: string): boolean {
  const entry = entries.get(key)
  if (!entry || entry.state !== "held") return false
  if (entry.timer) clearTimeout(entry.timer)
  entries.delete(key)
  notify()
  return true
}

/** Sends every held answer now. */
export function flushAnswers(): void {
  for (const [key, entry] of [...entries]) run(key, entry)
}

export function usePending(key: string): PendingState {
  const get = () => entries.get(key)?.state ?? null
  return useSyncExternalStore(subscribe, get, () => null)
}

/** Tests start with nothing held. */
export function resetPendingAnswers(): void {
  entries.forEach((entry) => entry.timer && clearTimeout(entry.timer))
  entries.clear()
  notify()
}
