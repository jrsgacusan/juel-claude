import { QueryClient } from "@tanstack/react-query"
import { afterEach, describe, expect, it, vi } from "vitest"
import { mockEvents } from "@/mocks/state"
import { keys } from "./queries"
import type { BriefingEvent } from "./types"
import {
  getConnection,
  keysFor,
  parseFrames,
  PING_TIMEOUT_MS,
  reconnectEvents,
  startEvents,
  subscribeBriefing,
  subscribeConnection,
} from "./events"
function stream() {
  let controller!: ReadableStreamDefaultController<Uint8Array>
  const body = new ReadableStream<Uint8Array>({
    start(c) {
      controller = c
    },
  })
  const encoder = new TextEncoder()
  return {
    response: new Response(body, {
      headers: { "Content-Type": "text/event-stream" },
    }),
    send: (event: unknown) =>
      controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`)),
    ping: () => controller.enqueue(encoder.encode(": ping\n\n")),
    end: () => controller.close(),
  }
}
function setVisibility(state: DocumentVisibilityState) {
  Object.defineProperty(document, "visibilityState", { configurable: true, value: state })
  document.dispatchEvent(new Event("visibilitychange"))
}
/** Fake timers and clock only: stream reads keep running on real microtasks. */
const useClock = () => vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "Date"] })
describe("the event stream", () => {
  const stops: Array<() => void> = []
  afterEach(() => {
    stops.splice(0).forEach((stop) => stop())
    Reflect.deleteProperty(document, "visibilityState")
    vi.useRealTimers()
  })
  it("parses data frames and keeps a partial frame for the next chunk", () => {
    expect(parseFrames('data: {"a":1}\n\ndata: {"b"')).toEqual({
      events: [{ a: 1 }],
      rest: 'data: {"b"',
    })
    expect(parseFrames(": connected\n\n").events).toEqual([])
    expect(parseFrames("data: not json\n\n").events).toEqual([])
    expect(parseFrames('data: {"a":2}\r\n\r\n').events).toEqual([{ a: 2 }])
  })
  it("maps each change to the queries it makes stale", () => {
    const p = "sphere-app"
    expect(keysFor({ type: "change", project: p, what: "loops" })).toEqual([
      ["loops", p],
      ["projects"],
      ["slack"],
    ])
    for (const what of ["ledger", "progress"] as const)
      expect(keysFor({ type: "change", project: p, what })).toEqual([
        ["items", p],
        ["item", p],
        ["overview", p],
        ["projects"],
      ])
    expect(keysFor({ type: "change", project: p, what: "evidence" })).toEqual([
      ["evidence", p],
    ])
    expect(keysFor({ type: "change", project: p, what: "drafts" })).toEqual([
      ["slack"],
      ["draft"],
    ])
    expect(keysFor({ type: "change", what: "slack" })).toEqual([
      ["slack"],
      ["draft"],
    ])
    expect(keysFor({ type: "change", project: p, what: "briefings" })).toEqual([
      ["briefings", p],
      ["briefing", p],
    ])
  })
  it("maps a chat change to its thread and an accounts change to the accounts", () => {
    const p = "sphere-app"
    expect(keysFor({ type: "change", project: p, what: "chat" })).toEqual([
      keys.chat(p),
    ])
    expect(keys.chat(p)).toEqual(["chat", p])
    expect(keysFor({ type: "change", what: "accounts" })).toEqual([
      keys.accounts,
    ])
    expect(keys.accounts).toEqual(["accounts"])
  })
  it("sends the token, invalidates on change events and hands briefing events on", async () => {
    sessionStorage.setItem("star-token", "tok")
    const s = stream()
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(s.response)
    const client = new QueryClient()
    const invalidate = vi.spyOn(client, "invalidateQueries")
    const seen: BriefingEvent[] = []
    stops.push(subscribeBriefing((e) => seen.push(e)))
    stops.push(startEvents(client, { fetchImpl, retryMs: 20 }))
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    const init = fetchImpl.mock.calls[0]?.[1]
    expect(new Headers(init?.headers).get("X-Star-Token")).toBe("tok")
    expect(String(fetchImpl.mock.calls[0]?.[0])).toBe(
      `${window.location.origin}/api/events`
    )
    s.send({ type: "change", project: "sphere-app", what: "loops" })
    await vi.waitFor(() =>
      expect(invalidate).toHaveBeenCalledWith({
        queryKey: ["loops", "sphere-app"],
      })
    )
    s.send({
      type: "briefing",
      project: "sphere-app",
      id: "b1",
      turn: { who: "agent", text: "Hi" },
    })
    await vi.waitFor(() =>
      expect(seen).toEqual([
        {
          type: "briefing",
          project: "sphere-app",
          id: "b1",
          turn: { who: "agent", text: "Hi" },
        },
      ])
    )
  })
  it("shows lost when the stream ends, retries, and refetches everything once it is back", async () => {
    const first = stream()
    const second = stream()
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(first.response)
      .mockRejectedValueOnce(new TypeError("Failed to fetch"))
      .mockResolvedValueOnce(second.response)
    const client = new QueryClient()
    const invalidate = vi.spyOn(client, "invalidateQueries")
    const states: string[] = []
    stops.push(subscribeConnection(() => states.push(getConnection())))
    stops.push(startEvents(client, { fetchImpl, retryMs: 20 }))
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    first.end()
    await vi.waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(3))
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    expect(states).toEqual(["open", "lost", "open"])
    expect(invalidate).toHaveBeenCalledWith({
      predicate: expect.any(Function),
    })
  })
  it("waits retryMs between tries", async () => {
    vi.useFakeTimers()
    try {
      const fetchImpl = vi
        .fn<typeof fetch>()
        .mockRejectedValue(new TypeError("Failed to fetch"))
      stops.push(startEvents(new QueryClient(), { fetchImpl }))
      await vi.advanceTimersByTimeAsync(0)
      expect(fetchImpl).toHaveBeenCalledTimes(1)
      expect(getConnection()).toBe("lost")
      await vi.advanceTimersByTimeAsync(4_999)
      expect(fetchImpl).toHaveBeenCalledTimes(1)
      await vi.advanceTimersByTimeAsync(1)
      expect(fetchImpl).toHaveBeenCalledTimes(2)
    } finally {
      vi.useRealTimers()
    }
  })
  it("a refused token stops the retries", async () => {
    vi.useFakeTimers()
    try {
      const fetchImpl = vi
        .fn<typeof fetch>()
        .mockResolvedValue(new Response(null, { status: 401 }))
      stops.push(startEvents(new QueryClient(), { fetchImpl }))
      await vi.advanceTimersByTimeAsync(0)
      expect(getConnection()).toBe("refused")
      await vi.advanceTimersByTimeAsync(20_000)
      expect(fetchImpl).toHaveBeenCalledTimes(1)
    } finally {
      vi.useRealTimers()
    }
  })

  it("never shows lost when it is stopped on purpose", async () => {
    const states: string[] = []
    stops.push(subscribeConnection(() => states.push(getConnection())))
    const fetchImpl = vi.fn<typeof fetch>(
      (_input, init) =>
        new Promise((_resolve, reject) =>
          init?.signal?.addEventListener("abort", () =>
            reject(new DOMException("aborted", "AbortError"))
          )
        )
    )
    const stop = startEvents(new QueryClient(), { fetchImpl, retryMs: 10 })
    stop()
    await new Promise((r) => setTimeout(r, 30))
    expect(states).not.toContain("lost")
  })

  it("does not refetch evidence files on reconnect", async () => {
    const first = stream()
    const second = stream()
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(first.response)
      .mockResolvedValueOnce(second.response)
    const client = new QueryClient()
    const invalidate = vi.spyOn(client, "invalidateQueries")
    stops.push(startEvents(client, { fetchImpl, retryMs: 10 }))
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    first.end()
    await vi.waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(2))
    await vi.waitFor(() => expect(invalidate).toHaveBeenCalled())
    const call = invalidate.mock.calls.at(-1)?.[0] as {
      predicate?: (q: { queryKey: readonly unknown[] }) => boolean
    }
    expect(call?.predicate?.({ queryKey: ["file", "/x"] })).toBe(false)
    expect(call?.predicate?.({ queryKey: ["loops", "p"] })).toBe(true)
  })
  it("a reconnect that never answers leaves open, reaches lost, and a later answer brings it back", async () => {
    useClock()
    const s = stream()
    const never = () => new Promise<Response>(() => {})
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockImplementationOnce(never)
      .mockImplementationOnce(never)
      .mockResolvedValue(s.response)
    const states: string[] = []
    stops.push(subscribeConnection(() => states.push(getConnection())))
    stops.push(startEvents(new QueryClient(), { fetchImpl, pingTimeoutMs: 10_000 }))
    await vi.advanceTimersByTimeAsync(0)
    expect(fetchImpl).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(10_000)
    expect(fetchImpl).toHaveBeenCalledTimes(2)
    expect(getConnection()).toBe("connecting")
    await vi.advanceTimersByTimeAsync(10_000)
    await vi.waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(3))
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    expect(states.slice(-2)).toEqual(["lost", "open"])
  })
  it("a restart from an open stream shows connecting until the new stream answers", async () => {
    useClock()
    const [first, second] = [stream(), stream()]
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValueOnce(first.response).mockResolvedValueOnce(second.response)
    stops.push(startEvents(new QueryClient(), { fetchImpl, pingTimeoutMs: 10_000 }))
    await vi.advanceTimersByTimeAsync(0)
    expect(getConnection()).toBe("open")
    const states: string[] = []
    stops.push(subscribeConnection(() => states.push(getConnection())))
    await vi.advanceTimersByTimeAsync(10_000)
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    expect(states).toEqual(["connecting", "open"])
  })
  it("reconnects at once, without showing lost, after 35 s with no ping", async () => {
    useClock()
    const [first, second] = [stream(), stream()]
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValueOnce(first.response).mockResolvedValueOnce(second.response)
    const states: string[] = []
    stops.push(subscribeConnection(() => states.push(getConnection())))
    stops.push(startEvents(new QueryClient(), { fetchImpl }))
    await vi.advanceTimersByTimeAsync(0)
    expect(getConnection()).toBe("open")
    await vi.advanceTimersByTimeAsync(30_000)
    first.ping()
    await vi.advanceTimersByTimeAsync(0)
    await vi.advanceTimersByTimeAsync(34_999)
    expect(fetchImpl).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(1)
    await vi.waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(2))
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    expect(states).toEqual(["open", "connecting", "open"])
    expect(PING_TIMEOUT_MS).toBe(35_000)
  })
  it("becoming visible with the stream lost reconnects at once and refetches when it is back", async () => {
    useClock()
    const start = Date.now()
    const s = stream()
    const fetchImpl = vi.fn<typeof fetch>().mockRejectedValueOnce(new TypeError("Failed to fetch")).mockResolvedValueOnce(s.response)
    const client = new QueryClient()
    const invalidate = vi.spyOn(client, "invalidateQueries")
    stops.push(startEvents(client, { fetchImpl }))
    await vi.advanceTimersByTimeAsync(0)
    expect(getConnection()).toBe("lost")
    setVisibility("hidden")
    expect(fetchImpl).toHaveBeenCalledTimes(1)
    setVisibility("visible")
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    expect(fetchImpl).toHaveBeenCalledTimes(2)
    expect(Date.now() - start).toBeLessThan(5000)
    expect(invalidate).toHaveBeenCalledTimes(1)
  })
  it("becoming visible with the stream open keeps it and refetches the queries once, until stopped", async () => {
    const s = stream()
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(s.response)
    const client = new QueryClient()
    const invalidate = vi.spyOn(client, "invalidateQueries")
    const stop = startEvents(client, { fetchImpl })
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    setVisibility("hidden")
    expect(invalidate).not.toHaveBeenCalled()
    setVisibility("visible")
    expect(invalidate).toHaveBeenCalledTimes(1)
    const { predicate } = invalidate.mock.calls[0]?.[0] as { predicate: (q: { queryKey: readonly unknown[] }) => boolean }
    expect(predicate({ queryKey: ["file", "/x"] })).toBe(false)
    expect(predicate({ queryKey: ["chat", "sphere-app"] })).toBe(true)
    stop()
    setVisibility("visible")
    reconnectEvents()
    await new Promise((r) => setTimeout(r, 20))
    expect(invalidate).toHaveBeenCalledTimes(1)
    expect(fetchImpl).toHaveBeenCalledTimes(1)
  })
  it("becoming visible after a sleep longer than the ping timeout restarts the stream", async () => {
    useClock()
    const [first, second] = [stream(), stream()]
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValueOnce(first.response).mockResolvedValueOnce(second.response)
    const client = new QueryClient()
    const invalidate = vi.spyOn(client, "invalidateQueries")
    stops.push(startEvents(client, { fetchImpl }))
    await vi.advanceTimersByTimeAsync(0)
    expect(getConnection()).toBe("open")
    vi.setSystemTime(Date.now() + 40_000) // the phone slept: the clock moved and no timer ran
    setVisibility("visible")
    await vi.waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(2))
    await vi.waitFor(() => expect(invalidate).toHaveBeenCalledTimes(1))
  })
  it("reconnectEvents retries a refused stream with the token stored since", async () => {
    const s = stream()
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValueOnce(new Response(null, { status: 401 })).mockResolvedValueOnce(s.response)
    stops.push(startEvents(new QueryClient(), { fetchImpl }))
    await vi.waitFor(() => expect(getConnection()).toBe("refused"))
    localStorage.setItem("star-token", "pasted")
    reconnectEvents()
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    expect(new Headers(fetchImpl.mock.calls[1]?.[1]?.headers).get("X-Star-Token")).toBe("pasted")
  })
  it("the mock stream pings every 25 s like the server, and drop() stops it", async () => {
    vi.useFakeTimers({ toFake: ["setInterval", "clearInterval"] })
    const reader = mockEvents.open().getReader()
    const next = async () => new TextDecoder().decode((await reader.read()).value)
    expect(await next()).toBe(": connected\n\n")
    vi.advanceTimersByTime(24_999)
    mockEvents.emit({ type: "change", project: "p", what: "loops" })
    expect(await next()).toBe('data: {"type":"change","project":"p","what":"loops"}\n\n')
    vi.advanceTimersByTime(1)
    expect(await next()).toBe(": ping\n\n")
    mockEvents.drop()
    expect((await reader.read()).done).toBe(true)
    expect(vi.getTimerCount()).toBe(0)
  })
})
