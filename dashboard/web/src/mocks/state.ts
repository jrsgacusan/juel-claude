import type { StarEvent } from "@/api/types"
import { createDb, type MockDb } from "./fixtures"

// The mock layer's mutable state: the db the handlers read and write, the scenario that switches
// them (spec D17), and the hub behind GET /api/events.

export type Scenario =
  | "default"
  | "empty"
  | "error"
  | "loading"
  | "conflict"
  | "stopped"
  | "slack-off"
const SCENARIOS: readonly Scenario[] = [
  "default",
  "empty",
  "error",
  "loading",
  "conflict",
  "stopped",
  "slack-off",
]
export const isScenario = (value: unknown): value is Scenario =>
  typeof value === "string" && (SCENARIOS as readonly string[]).includes(value)

let db: MockDb = createDb()
let scenario: Scenario = "default"

export const getDb = (): MockDb => db
export const getScenario = (): Scenario => scenario
export function setScenario(next: Scenario): void {
  scenario = next
}

/** The scenario Playwright picks before the page loads: localStorage['star-mock']. */
export function readScenario(): Scenario {
  try {
    const value = localStorage.getItem("star-mock")
    return isScenario(value) ? value : "default"
  } catch {
    return "default"
  }
}

const encoder = new TextEncoder()
const clients = new Set<ReadableStreamDefaultController<Uint8Array>>()
const timers = new Set<ReturnType<typeof setTimeout>>()
let dropped = false

export const mockEvents = {
  /** A new event stream; it stays open until drop() or the reader cancels it. */
  open(): ReadableStream<Uint8Array> {
    let mine: ReadableStreamDefaultController<Uint8Array> | null = null
    return new ReadableStream<Uint8Array>({
      start(controller) {
        mine = controller
        clients.add(controller)
        controller.enqueue(encoder.encode(": connected\n\n"))
      },
      cancel() {
        if (mine) clients.delete(mine)
      },
    })
  },
  emit(event: StarEvent): void {
    const frame = encoder.encode(`data: ${JSON.stringify(event)}\n\n`)
    for (const client of clients) {
      try {
        client.enqueue(frame)
      } catch {
        clients.delete(client)
      }
    }
  },
  /** Ends every open stream and fails new ones until restore(). */
  drop(): void {
    dropped = true
    for (const client of clients) {
      try {
        client.close()
      } catch {
        // already closed
      }
    }
    clients.clear()
  },
  restore(): void {
    dropped = false
  },
  get dropped(): boolean {
    return dropped
  },
  /** Runs fn later; resetMockState cancels it. */
  later(ms: number, fn: () => void): void {
    const timer = setTimeout(() => {
      timers.delete(timer)
      fn()
    }, ms)
    timers.add(timer)
  },
}

export function resetMockState(): void {
  timers.forEach(clearTimeout)
  timers.clear()
  mockEvents.drop()
  dropped = false
  db = createDb()
  scenario = "default"
}
