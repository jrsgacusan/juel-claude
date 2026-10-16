import { http, HttpResponse } from "msw/http"
import { delay } from "msw/utils/delay"
import type { HttpHandler } from "msw/http"
import type { ChatMessage } from "@/api/types"
import { ago, type MockDb } from "./fixtures"
import { getDb, getScenario, mockEvents } from "./state"

export const MOCK_REPLY = "Two workers are building:\n\n- **SPH-12**\n- **SPH-14**"

const threads = new WeakMap<MockDb, Record<string, ChatMessage[]>>()
let counter = 0

function messageId(who: "me" | "star", at: string): string {
  counter += 1
  const stamp = at.replace(/[-:]/g, "").replace(/\.\d+/, "")
  return `${stamp}-${who}-${counter.toString(16).padStart(4, "0")}`
}

function make(who: "me" | "star", minutes: number, replyTo: string | null, text: string): ChatMessage {
  const at = ago(minutes)
  return { id: messageId(who, at), who, at, replyTo, text }
}

function seed(): ChatMessage[] {
  const one = make("me", 40, null, "what's in the queue?")
  const two = make(
    "star",
    39,
    one.id,
    "Three items are queued. **SPH-21** starts when a build slot frees up.\n\n| Item | State |\n|---|---|\n| SPH-21 | queued |\n| SPH-22 | queued |\n| SPH-23 | queued |\n\nThe last run's log: https://github.com/owner/sphere-app/actions/runs/1234567890/job/9876543210?check_suite_focus=true&pr=412"
  )
  const three = make("me", 10, null, "keep **SPH-12** as is")
  const four = make("star", 9, three.id, "Done. SPH-12 stays as it is.")
  return [one, two, three, four]
}

/** The live, mutable thread of one project. */
export function chatThread(p: string): ChatMessage[] {
  const db = getDb()
  let all = threads.get(db)
  if (!all) {
    all = {}
    threads.set(db, all)
  }
  all[p] ??= p === "sphere-app" ? seed() : []
  return all[p]
}

const running = (p: string): boolean =>
  getScenario() !== "stopped" && getDb().projects.find((x) => x.name === p)?.state === "running"

export function postStarReply(p: string, replyTo: string | null, text: string): ChatMessage {
  const at = new Date().toISOString()
  const message: ChatMessage = { id: messageId("star", at), who: "star", at, replyTo, text }
  chatThread(p).push(message)
  mockEvents.emit({ type: "change", project: p, what: "chat" })
  return message
}

const fail = (status: number, error: string) => HttpResponse.json({ error }, { status })

export const chatHandlers: HttpHandler[] = [
  http.get("*/api/projects/:p/chat", async ({ params, request }) => {
    const p = String(params.p)
    const scenario = getScenario()
    if (scenario === "loading") await delay("infinite")
    if (scenario === "error") return fail(502, "Could not read chat/: permission denied")
    if (!getDb().projects.some((x) => x.name === p)) return fail(404, `No project named ${p}`)
    const url = new URL(request.url)
    const before = url.searchParams.get("before")
    const asked = Number(url.searchParams.get("limit") ?? 100)
    const limit = Number.isInteger(asked) && asked >= 1 && asked <= 200 ? asked : 100
    const all = scenario === "empty" ? [] : chatThread(p)
    const older = before ? all.filter((m) => m.id < before) : all
    return HttpResponse.json({
      messages: older.slice(-limit),
      hasMore: older.length > limit,
      starRunning: running(p),
    })
  }),
  http.post("*/api/projects/:p/chat", async ({ params, request }) => {
    const p = String(params.p)
    if (!getDb().projects.some((x) => x.name === p)) return fail(404, `No project named ${p}`)
    const body = (await request.json()) as { text?: unknown }
    const text = typeof body.text === "string" ? body.text.trim() : ""
    if (!text) return fail(400, "A chat message needs text")
    if (text.length > 8000) return fail(400, "A chat message is at most 8000 characters")
    const at = new Date().toISOString()
    const message: ChatMessage = { id: messageId("me", at), who: "me", at, replyTo: null, text }
    chatThread(p).push(message)
    mockEvents.later(50, () => mockEvents.emit({ type: "change", project: p, what: "chat" }))
    const nudged = running(p)
    if (nudged) mockEvents.later(600, () => postStarReply(p, message.id, MOCK_REPLY))
    return HttpResponse.json({ id: message.id, nudged })
  }),
]
