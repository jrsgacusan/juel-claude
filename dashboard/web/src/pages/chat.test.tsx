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
})
