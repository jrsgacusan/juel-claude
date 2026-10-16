import { act, fireEvent, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it, vi } from "vitest"
import { getConnection } from "@/api/events"
import type { ChatMessage } from "@/api/types"
import { chatThread, postStarReply } from "@/mocks/chat"
import { server } from "@/mocks/node"
import { getDb, setScenario } from "@/mocks/state"
import { renderApp } from "@/test/render"

/** A matchMedia whose (pointer: coarse) answer a test picks; every other query is false. */
function mockPointer(coarse: boolean) {
  const noop = () => {}
  vi.spyOn(window, "matchMedia").mockImplementation(
    (query: string) =>
      ({ matches: query === "(pointer: coarse)" ? coarse : false, media: query, onchange: null,
        addEventListener: noop, removeEventListener: noop, addListener: noop, removeListener: noop,
        dispatchEvent: () => false }) as unknown as MediaQueryList
  )
}
const thread = () => screen.getByRole("list", { name: "Chat with STAR" })

describe("Chat", () => {
  it("shows STAR's next note, then the thread oldest first, STAR in Markdown and the owner as typed", async () => {
    renderApp("/sphere-app/chat")
    expect(await screen.findByRole("region", { name: "STAR's next step" })).toHaveTextContent("Next tick in 3 min")
    const list = await screen.findByRole("list", { name: "Chat with STAR" })
    await within(list).findByText("what's in the queue?")
    const rows = Array.from(list.children) as HTMLElement[]
    expect(rows.map((row) => row.dataset.who)).toEqual(["me", "star", "me", "star"])
    expect(within(rows[1]!).getByRole("table")).toBeInTheDocument()
    expect(within(rows[1]!).getByText("SPH-21", { selector: "strong" })).toBeInTheDocument()
    expect(within(rows[2]!).getByText("keep **SPH-12** as is")).toBeInTheDocument()
    expect(rows[2]!.querySelector("strong")).toBeNull()
    expect(rows[3]).toHaveClass("motion-fade-in")
  })

  it("says STAR isn't running when it is stopped", async () => {
    renderApp("/juel-claude/chat")
    expect(await screen.findByText("STAR isn't running. Your message waits in its inbox.")).toBeInTheDocument()
  })

  it("loads earlier messages with before", async () => {
    const older: ChatMessage[] = Array.from({ length: 105 }, (_, i) => ({
      id: `20261001T0${String(Math.floor(i / 60)).padStart(3, "0")}${String(i % 60).padStart(2, "0")}Z-me-${i.toString(16).padStart(4, "0")}`,
      who: "me", at: "2026-10-01T00:00:00Z", replyTo: null, text: `earlier ${i + 1}`,
    }))
    chatThread("sphere-app").unshift(...older)
    const { user } = renderApp("/sphere-app/chat")
    await within(await screen.findByRole("list", { name: "Chat with STAR" })).findByText("earlier 10")
    expect(within(thread()).queryByText("earlier 9")).not.toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: "Load earlier messages" }))
    expect(await within(thread()).findByText("earlier 1")).toBeInTheDocument()
    expect(screen.queryByRole("button", { name: "Load earlier messages" })).not.toBeInTheDocument()
    expect(thread().children[0]).toHaveTextContent("earlier 1")
  })

  it("has loading, empty and error states", async () => {
    setScenario("loading")
    const first = renderApp("/sphere-app/chat")
    expect(await screen.findByTestId("page-loading")).toBeInTheDocument()
    first.unmount()
    setScenario("empty")
    const second = renderApp("/sphere-app/chat")
    expect(await screen.findByText("Talk to STAR the way you would in its terminal. Its replies show here.")).toBeInTheDocument()
    second.unmount()
    setScenario("error")
    renderApp("/sphere-app/chat")
    expect(await screen.findByTestId("page-error")).toHaveTextContent("Couldn't load the chat.")
  })

  it("sends with Enter on a fine pointer and shows STAR is reading until the reply arrives", async () => {
    const { user } = renderApp("/sphere-app/chat")
    const box = await screen.findByLabelText("Message STAR")
    expect(box).toHaveClass("text-base", "md:text-sm")
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.type(box, "how's it going?{Enter}")
    expect(await within(thread()).findByText("how's it going?")).toBeInTheDocument()
    expect(box).toHaveValue("")
    expect(within(thread()).getByText("STAR is reading…")).toBeInTheDocument()
    expect(
      await within(thread()).findByText("Two workers are building:", {}, { timeout: 3000 })
    ).toBeInTheDocument()
    expect(within(thread()).queryByText("STAR is reading…")).not.toBeInTheDocument()
    const sent = chatThread("sphere-app").filter((m) => m.who === "me").at(-1)!
    expect(sent.text).toBe("how's it going?")
    expect(chatThread("sphere-app").at(-1)).toMatchObject({ who: "star", replyTo: sent.id })
  })

  it("makes a newline with Enter on a touch screen and sends with the Send button", async () => {
    mockPointer(true)
    const { user } = renderApp("/sphere-app/chat")
    const box = await screen.findByLabelText("Message STAR")
    const before = chatThread("sphere-app").length
    await user.type(box, "line one{Enter}line two")
    expect(box).toHaveValue("line one\nline two")
    expect(chatThread("sphere-app")).toHaveLength(before)
    const send = screen.getByRole("button", { name: "Send" })
    expect(send).toHaveClass("pointer-coarse:size-11")
    await user.click(send)
    const bubble = await within(thread()).findByText("line one line two")
    expect(bubble.textContent).toBe("line one\nline two")
    expect(chatThread("sphere-app")[before]?.text).toBe("line one\nline two")
  })

  it("makes a newline with Shift+Enter on a fine pointer", async () => {
    const { user } = renderApp("/sphere-app/chat")
    const box = await screen.findByLabelText("Message STAR")
    const before = chatThread("sphere-app").length
    await user.type(box, "a{Shift>}{Enter}{/Shift}b")
    expect(box).toHaveValue("a\nb")
    expect(chatThread("sphere-app")).toHaveLength(before)
  })

  it("keeps a message sent while STAR is stopped waiting, then shows STAR's reply once", async () => {
    const { user } = renderApp("/juel-claude/chat")
    expect(
      await screen.findByText("STAR isn't running. Your message waits in its inbox.")
    ).toBeInTheDocument()
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.type(await screen.findByLabelText("Message STAR"), "are you there?{Enter}")
    expect(await within(thread()).findByText("are you there?")).toBeInTheDocument()
    expect(await within(thread()).findByText("Waits for STAR's next start")).toBeInTheDocument()
    expect(within(thread()).queryByText("STAR is reading…")).not.toBeInTheDocument()
    await new Promise((resolve) => setTimeout(resolve, 900))
    expect(chatThread("juel-claude").filter((m) => m.who === "star")).toHaveLength(0)
    // STAR starts, finds the message in its inbox and answers it.
    const sent = chatThread("juel-claude")[0]!
    getDb().projects.find((p) => p.name === "juel-claude")!.state = "running"
    act(() => {
      postStarReply("juel-claude", sent.id, "Here now. **Nothing** is in flight.")
    })
    expect(await within(thread()).findByText("Nothing")).toBeInTheDocument()
    expect(within(thread()).getAllByText(/Here now\./)).toHaveLength(1)
    expect(within(thread()).queryByText("Waits for STAR's next start")).not.toBeInTheDocument()
    expect(
      screen.queryByText("STAR isn't running. Your message waits in its inbox.")
    ).not.toBeInTheDocument()
  })

  it("scrolls the thread in its own box, stays put while the reader is scrolled up, and leaves the window alone", async () => {
    const intoView = vi.spyOn(Element.prototype, "scrollIntoView")
    const windowScroll = vi.spyOn(window, "scrollTo").mockImplementation(() => {})
    const { user } = renderApp("/sphere-app/chat")
    const box = await screen.findByTestId("chat-scroll")
    let top = 0
    Object.defineProperty(box, "scrollHeight", { configurable: true, get: () => 900 })
    Object.defineProperty(box, "clientHeight", { configurable: true, get: () => 300 })
    Object.defineProperty(box, "scrollTop", { configurable: true, get: () => top, set: (v: number) => { top = v } })
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.type(screen.getByLabelText("Message STAR"), "status?{Enter}")
    await waitFor(() => expect(top).toBe(900))
    top = 100
    fireEvent.scroll(box)
    await within(thread()).findByText("Two workers are building:", {}, { timeout: 3000 })
    expect(top).toBe(100)
    expect(intoView).not.toHaveBeenCalled()
    expect(windowScroll).not.toHaveBeenCalled()
  })

  it("puts the text back and says why when the send fails", async () => {
    server.use(
      http.post("*/api/projects/:p/chat", () =>
        HttpResponse.json({ error: "A chat message is at most 8000 characters" }, { status: 400 })
      )
    )
    const { user } = renderApp("/sphere-app/chat")
    const box = await screen.findByLabelText("Message STAR")
    await user.type(box, "hello{Enter}")
    expect(
      await screen.findByText("Couldn't send it: A chat message is at most 8000 characters")
    ).toBeInTheDocument()
    expect(box).toHaveValue("hello")
    expect(within(thread()).queryByText("hello")).not.toBeInTheDocument()
  })
})
