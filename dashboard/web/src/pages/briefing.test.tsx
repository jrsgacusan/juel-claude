import { act, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it, vi } from "vitest"
import { getConnection } from "@/api/events"
import { server } from "@/mocks/node"
import {
  failNextBriefingTurn,
  getDb,
  mockEvents,
  setScenario,
} from "@/mocks/state"
import { renderApp } from "@/test/render"

const b1 = () =>
  getDb().briefings["sphere-app"]?.find((b) => b.summary.id === "b1")

async function pickTracker(
  user: ReturnType<typeof renderApp>["user"],
  name: string
) {
  const draft = screen.getByRole("region", { name: "Ticket draft" })
  await user.click(within(draft).getByRole("combobox", { name: "Tracker" }))
  await user.click(await screen.findByRole("option", { name }))
}

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

describe("Briefing", () => {
  it("shows the chat, the files the agent read, and the ticket draft", async () => {
    renderApp("/sphere-app/briefing")
    const chat = await screen.findByRole("region", { name: "Conversation" })
    expect(
      await within(chat).findByText(
        /Admins keep asking to pause someone's seat/
      )
    ).toBeInTheDocument()
    expect(
      within(chat).getByText("Read apps/api/src/billing/seats.ts")
    ).toBeInTheDocument()
    expect(
      within(chat).getByText("Reads sphere-app, changes nothing")
    ).toBeInTheDocument()
    const draft = screen.getByRole("region", { name: "Ticket draft" })
    expect(
      within(draft).getByText("Let admins pause a member's seat")
    ).toBeInTheDocument()
    expect(
      within(draft).getByText("A paused member can't sign in until resumed")
    ).toBeInTheDocument()
    expect(
      within(draft).getByText(
        "Pausing the whole team. Emails to the paused member."
      )
    ).toBeInTheDocument()
    expect(
      within(draft).getByText("Where do sphere-app's tickets live?")
    ).toBeInTheDocument()
    expect(
      within(draft).getByRole("button", {
        name: "Pick where the ticket goes first",
      })
    ).toBeDisabled()
  })

  it("streams the agent's turn from briefing events", async () => {
    const { user } = renderApp("/sphere-app/briefing")
    const box = await screen.findByLabelText("Message the briefing agent")
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.type(box, "Also log who paused it{Enter}")
    const chat = screen.getByRole("region", { name: "Conversation" })
    expect(
      await within(chat).findByText("Also log who paused it")
    ).toBeInTheDocument()
    // A partial turn (text so far, briefing D10) shows while the agent answers, and no
    // "stopped" row shows in between.
    await waitFor(
      () =>
        expect(within(chat).getByTestId("agent-streaming")).toHaveTextContent(
          "Noted: Also log"
        ),
      { timeout: 3000 }
    )
    expect(
      within(chat).queryByText(/The briefing agent stopped/)
    ).not.toBeInTheDocument()
    expect(
      await within(chat).findByText(
        /^Noted: Also log who paused it\. I added it/,
        {},
        { timeout: 3000 }
      )
    ).toBeInTheDocument()
    await waitFor(
      () =>
        expect(
          within(chat).queryByTestId("agent-streaming")
        ).not.toBeInTheDocument(),
      { timeout: 3000 }
    )
    expect(box).toHaveValue("")
    expect(b1()?.briefing.busy).toBe(false)
    expect(
      within(chat).queryByText(/The briefing agent stopped/)
    ).not.toBeInTheDocument()
  })

  it("opens the briefing a search result names", async () => {
    renderApp("/sphere-app/briefing?id=b0")
    expect(
      await screen.findByRole("combobox", { name: "Briefing" })
    ).toHaveTextContent("Export reports as CSV")
  })

  it("holds a second message until the agent has answered", async () => {
    const { user } = renderApp("/sphere-app/briefing")
    const box = await screen.findByLabelText("Message the briefing agent")
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.type(box, "Also log who paused it{Enter}")
    const chat = screen.getByRole("region", { name: "Conversation" })
    expect(
      await within(chat).findByText("Also log who paused it")
    ).toBeInTheDocument()
    await waitFor(() => expect(box).toHaveValue(""))
    await user.type(box, "And who resumed it{Enter}")
    expect(box).toHaveValue("And who resumed it")
    expect(screen.getByRole("button", { name: "Send" })).toBeDisabled()
    expect(
      await within(chat).findByText(
        /^Noted: Also log who paused it\./,
        {},
        { timeout: 3000 }
      )
    ).toBeInTheDocument()
    expect(
      b1()?.briefing.turns.some((t) => t.text === "And who resumed it")
    ).toBe(false)
    await waitFor(
      () => expect(screen.getByRole("button", { name: "Send" })).toBeEnabled(),
      { timeout: 3000 }
    )
  })

  it("offers Try again when one briefing cannot be read", async () => {
    let failing = true
    server.use(
      http.get("*/api/projects/:p/briefings/:id", () =>
        failing
          ? HttpResponse.json(
              { error: "transcript.jsonl is not readable" },
              { status: 502 }
            )
          : undefined
      )
    )
    const { user } = renderApp("/sphere-app/briefing")
    const chat = await screen.findByRole("region", { name: "Conversation" })
    expect(
      await within(chat).findByText(
        /^Couldn't load this briefing: transcript\.jsonl is not readable/
      )
    ).toBeInTheDocument()
    failing = false
    expect(within(chat).getByRole("button", { name: "Try again" })).toHaveClass("pointer-coarse:h-11")
    await user.click(within(chat).getByRole("button", { name: "Try again" }))
    expect(
      await within(chat).findByText(/^Admins keep asking to pause/)
    ).toBeInTheDocument()
  })

  it("saves the tracker answer, warns when it is not connected, and creates the ticket", async () => {
    const { user } = renderApp("/sphere-app/briefing")
    const draft = await screen.findByRole("region", { name: "Ticket draft" })
    await within(draft).findByText("Let admins pause a member's seat")
    await pickTracker(user, "Synapse")
    expect(
      await within(draft).findByText(
        "Synapse isn't connected yet. Connect it in Claude Code to create the ticket there. Until then, this becomes a spec file STAR keeps."
      )
    ).toBeInTheDocument()
    expect(getDb().trackers["sphere-app"]?.tracker).toBe("synapse")
    expect(
      within(draft).getByRole("button", {
        name: "Save as a spec and hand to STAR",
      })
    ).toBeEnabled()
    await pickTracker(user, "GitHub Issues")
    await user.click(
      await within(draft).findByRole("button", {
        name: "Create in GitHub Issues and hand to STAR",
      })
    )
    expect(
      await screen.findByText(
        "#88 created in GitHub Issues. STAR is briefing it now."
      )
    ).toBeInTheDocument()
    expect(b1()?.summary.ref).toBe("#88")
  })

  it("says Linear or Jira may become a spec, and says so when it did", async () => {
    const { user } = renderApp("/sphere-app/briefing")
    const draft = await screen.findByRole("region", { name: "Ticket draft" })
    await within(draft).findByText("Let admins pause a member's seat")
    await pickTracker(user, "Jira")
    expect(
      await within(draft).findByText(
        "Jira is used when its connector is connected in Claude Code. If it isn't, this becomes a spec file STAR keeps."
      )
    ).toBeInTheDocument()
    await user.click(
      within(draft).getByRole("button", {
        name: "Create in Jira and hand to STAR",
      })
    )
    expect(
      await screen.findByText(
        "Jira isn't connected in Claude Code, so it was saved as a spec file. STAR is briefing it now."
      )
    ).toBeInTheDocument()
  })

  it("shows no connector note for GitHub Issues", async () => {
    const { user } = renderApp("/sphere-app/briefing")
    const draft = await screen.findByRole("region", { name: "Ticket draft" })
    await within(draft).findByText("Let admins pause a member's seat")
    await pickTracker(user, "GitHub Issues")
    expect(
      within(draft).queryByText(/connected in Claude Code/)
    ).not.toBeInTheDocument()
  })

  it("offers to save as a spec when the tracker fails", async () => {
    server.use(
      http.post(
        "*/api/projects/:p/briefings/:id/create",
        async ({ request }) => {
          const { tracker } = (await request.json()) as { tracker: string }
          return tracker === "none"
            ? HttpResponse.json({
                specPath: "items/sphere-app/let-admins-pause-a-members-seat.md",
                url: null,
              })
            : HttpResponse.json(
                { error: "Linear's create tool failed: team SPH not found" },
                { status: 502 }
              )
        }
      )
    )
    const { user } = renderApp("/sphere-app/briefing")
    const draft = await screen.findByRole("region", { name: "Ticket draft" })
    await within(draft).findByText("Let admins pause a member's seat")
    await pickTracker(user, "Linear")
    await user.click(
      await within(draft).findByRole("button", {
        name: "Create in Linear and hand to STAR",
      })
    )
    expect(
      await within(draft).findByText(
        "Couldn't create the ticket: Linear's create tool failed: team SPH not found"
      )
    ).toBeInTheDocument()
    expect(
      within(draft).getByRole("button", { name: "Save as a spec instead" })
    ).toHaveClass("pointer-coarse:h-11")
    await user.click(
      within(draft).getByRole("button", { name: "Save as a spec instead" })
    )
    expect(
      await screen.findByText("Saved as a spec file. STAR is briefing it now.")
    ).toBeInTheDocument()
  })

  it("starts a new briefing", async () => {
    const { user, router } = renderApp("/sphere-app/briefing")
    expect(
      await screen.findByRole("button", { name: /New briefing/ })
    ).toHaveClass("pointer-coarse:h-11")
    await user.click(
      await screen.findByRole("button", { name: /New briefing/ })
    )
    await waitFor(() =>
      expect(router.state.location.search).toMatch(/^\?briefing=b\d+$/)
    )
    expect(
      await screen.findByText(
        "The draft shows here once the agent has enough to propose a ticket."
      )
    ).toBeInTheDocument()
  })

  it("keeps the pending message and retries it", async () => {
    const { user } = renderApp("/sphere-app/briefing")
    const box = await screen.findByLabelText("Message the briefing agent")
    await waitFor(() => expect(getConnection()).toBe("open"))
    failNextBriefingTurn()
    await user.type(box, "Also log who paused it{Enter}")
    const chat = screen.getByRole("region", { name: "Conversation" })
    expect(
      await within(chat).findByText("Also log who paused it")
    ).toBeInTheDocument()
    expect(
      await within(chat).findByText(
        "The briefing agent stopped: claude exited 1.",
        {},
        { timeout: 3000 }
      )
    ).toBeInTheDocument()
    expect(
      b1()?.briefing.turns.some((t) => t.text === "Also log who paused it")
    ).toBe(false)
    await user.click(within(chat).getByRole("button", { name: "Retry" }))
    expect(
      await within(chat).findByText(
        /^Noted: Also log who paused it\./,
        {},
        { timeout: 3000 }
      )
    ).toBeInTheDocument()
    await waitFor(() =>
      expect(
        b1()?.briefing.turns.filter((t) => t.text === "Also log who paused it")
      ).toHaveLength(1)
    )
  })

  it("clears a finished turn after a reconnect lost its done event", async () => {
    const { user } = renderApp("/sphere-app/briefing")
    const box = await screen.findByLabelText("Message the briefing agent")
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.type(box, "Also log who paused it{Enter}")
    act(() => mockEvents.drop())
    await waitFor(() => expect(b1()?.briefing.busy).toBe(false), {
      timeout: 3000,
    })
    act(() => mockEvents.restore())
    const chat = screen.getByRole("region", { name: "Conversation" })
    await waitFor(
      () =>
        expect(
          within(chat).queryByTestId("agent-streaming")
        ).not.toBeInTheDocument(),
      { timeout: 8000 }
    )
    expect(within(chat).getAllByText("Also log who paused it")).toHaveLength(1)
  }, 15_000)

  it("puts the text back in the box when the server refuses the message", async () => {
    server.use(
      http.post("*/api/projects/:p/briefings/:id/messages", () =>
        HttpResponse.json(
          { error: "The agent is still answering" },
          { status: 409 }
        )
      )
    )
    const { user } = renderApp("/sphere-app/briefing")
    const box = await screen.findByLabelText("Message the briefing agent")
    await user.type(box, "Also log who paused it{Enter}")
    expect(
      await screen.findByText(
        "The agent is still answering. Wait for its reply, then send."
      )
    ).toBeInTheDocument()
    expect(box).toHaveValue("Also log who paused it")
    const chat = screen.getByRole("region", { name: "Conversation" })
    expect(
      within(chat).queryByText("Also log who paused it", { selector: "li" })
    ).not.toBeInTheDocument()
    expect(
      within(chat).queryByText(/The briefing agent stopped/)
    ).not.toBeInTheDocument()
  })

  it("does not bring back a message the done event already cleared", async () => {
    // The POST answers after the whole turn has streamed: the done event clears the pending
    // message first, and the late answer must not store it again.
    server.use(
      http.post(
        "*/api/projects/:p/briefings/:id/messages",
        async ({ params, request }) => {
          const { text } = (await request.json()) as { text: string }
          const entry = b1()
          if (entry) {
            entry.briefing.turns.push({ who: "me", text })
            entry.briefing.turns.push({
              who: "agent",
              text: "Done already.",
              done: true,
            })
          }
          mockEvents.emit({
            type: "briefing",
            project: String(params.p),
            id: String(params.id),
            turn: { who: "agent", text: "Done already.", done: true },
          })
          await new Promise((resolve) => setTimeout(resolve, 100))
          return new HttpResponse(null, { status: 202 })
        }
      )
    )
    const { user } = renderApp("/sphere-app/briefing")
    const box = await screen.findByLabelText("Message the briefing agent")
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.type(box, "Also log who paused it{Enter}")
    const chat = screen.getByRole("region", { name: "Conversation" })
    expect(
      await within(chat).findByText("Done already.", {}, { timeout: 3000 })
    ).toBeInTheDocument()
    await waitFor(() => expect(box).toHaveValue(""))
    expect(within(chat).getAllByText("Also log who paused it")).toHaveLength(1)
    expect(
      within(chat).queryByText(/The briefing agent stopped/)
    ).not.toBeInTheDocument()
  })

  it("does not create a second ticket from the same briefing", async () => {
    const { user } = renderApp("/sphere-app/briefing")
    const draft = await screen.findByRole("region", { name: "Ticket draft" })
    await within(draft).findByText("Let admins pause a member's seat")
    await pickTracker(user, "GitHub Issues")
    await user.click(
      await within(draft).findByRole("button", {
        name: "Create in GitHub Issues and hand to STAR",
      })
    )
    expect(
      await screen.findAllByText(
        "#88 created in GitHub Issues. STAR is briefing it now."
      )
    ).not.toHaveLength(0)
    expect(
      await within(draft).findByRole("button", { name: "Created #88" })
    ).toBeDisabled()
  })

  it("says when it could not read where the tickets live", async () => {
    server.use(
      http.get("*/api/projects/:p/tracker", () =>
        HttpResponse.json(
          { error: "workflow.local.json is not JSON" },
          { status: 502 }
        )
      )
    )
    renderApp("/sphere-app/briefing")
    const draft = await screen.findByRole("region", { name: "Ticket draft" })
    expect(
      await within(draft).findByText(
        "Couldn't read where sphere-app's tickets live: workflow.local.json is not JSON"
      )
    ).toBeInTheDocument()
    expect(
      within(draft).getByRole("button", { name: "Try again" })
    ).toHaveClass("pointer-coarse:h-11")
    expect(
      within(draft).queryByRole("combobox", { name: "Tracker" })
    ).not.toBeInTheDocument()
  })

  it("has loading, empty and error states", async () => {
    setScenario("loading")
    const first = renderApp("/sphere-app/briefing")
    expect(await screen.findByTestId("page-loading")).toBeInTheDocument()
    first.unmount()
    setScenario("empty")
    const second = renderApp("/sphere-app/briefing")
    expect(await screen.findByText("No briefings yet.")).toBeInTheDocument()
    expect(
      await screen.findByText(
        "Start one to shape a piece of work with the briefing agent; it ends in a ticket STAR picks up."
      )
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /New briefing/ })
    ).toBeInTheDocument()
    second.unmount()
    setScenario("error")
    renderApp("/sphere-app/briefing")
    expect(await screen.findByTestId("page-error")).toHaveTextContent(
      "Couldn't load the briefings."
    )
  })

  it("renders the agent's turns as Markdown and the owner's as typed", async () => {
    server.use(
      http.get("*/api/projects/:p/briefings/:id", () =>
        HttpResponse.json({
          busy: false,
          draft: null,
          turns: [
            { who: "me", text: "pause **one** seat" },
            { who: "agent", text: "## Plan\n\n- pause\n- resume\n\nSee `seats.ts`." },
          ],
        })
      )
    )
    renderApp("/sphere-app/briefing")
    const chat = await screen.findByRole("region", { name: "Conversation" })
    expect(await within(chat).findByRole("heading", { level: 2, name: "Plan" })).toBeInTheDocument()
    expect(within(chat).getByText("seats.ts").tagName).toBe("CODE")
    expect(within(chat).getByText("pause **one** seat")).toBeInTheDocument()
  })

  it("makes a newline with Enter on a touch screen and sends with the Send button", async () => {
    mockPointer(true)
    const { user } = renderApp("/sphere-app/briefing")
    const box = await screen.findByLabelText("Message the briefing agent")
    expect(box).toHaveClass("text-base", "md:text-sm")
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.type(box, "Also log it{Enter}with the time")
    expect(box).toHaveValue("Also log it\nwith the time")
    expect(b1()?.briefing.busy).toBe(false)
    await user.click(screen.getByRole("button", { name: "Send" }))
    const chat = screen.getByRole("region", { name: "Conversation" })
    const mine = await within(chat).findByText("Also log it with the time")
    expect(mine.textContent).toBe("Also log it\nwith the time")
  })

  it("scrolls the conversation in its own box, never the window", async () => {
    const intoView = vi.spyOn(Element.prototype, "scrollIntoView")
    const { user } = renderApp("/sphere-app/briefing")
    const box = await screen.findByTestId("briefing-scroll")
    let top = 0
    Object.defineProperty(box, "scrollHeight", { configurable: true, get: () => 900 })
    Object.defineProperty(box, "clientHeight", { configurable: true, get: () => 300 })
    Object.defineProperty(box, "scrollTop", { configurable: true, get: () => top, set: (v: number) => { top = v } })
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.type(screen.getByLabelText("Message the briefing agent"), "Also log who paused it{Enter}")
    await waitFor(() => expect(top).toBe(900))
    const chat = screen.getByRole("region", { name: "Conversation" })
    await within(chat).findByText(/^Noted: Also log who paused it\./, {}, { timeout: 3000 })
    expect(intoView).not.toHaveBeenCalled()
  })

  it("shows Chat and Draft as tabs below md", async () => {
    const { user } = renderApp("/sphere-app/briefing")
    expect(await screen.findByRole("tab", { name: "Chat" })).toHaveAttribute("aria-selected", "true")
    const chat = screen.getByRole("region", { name: "Conversation" })
    const draft = screen.getByRole("region", { name: "Ticket draft" })
    expect(chat).not.toHaveClass("max-md:hidden")
    expect(draft).toHaveClass("max-md:hidden")
    await user.click(screen.getByRole("tab", { name: "Draft" }))
    expect(chat).toHaveClass("max-md:hidden")
    expect(draft).not.toHaveClass("max-md:hidden")
  })

  it("shows Delete only when the briefing is deletable", async () => {
    const first = renderApp("/sphere-app/briefing")
    const chat = await screen.findByRole("region", { name: "Conversation" })
    expect(await within(chat).findByRole("button", { name: "Delete" })).toBeInTheDocument()
    first.unmount()
    server.use(
      http.get("*/api/projects/:p/briefings", () =>
        HttpResponse.json([
          { id: "b1", title: "Pause a member's seat", updatedAt: new Date().toISOString(), ref: null, deletable: false },
        ])
      )
    )
    renderApp("/sphere-app/briefing")
    const again = await screen.findByRole("region", { name: "Conversation" })
    await within(again).findByText(/^Admins keep asking to pause/)
    expect(within(again).queryByRole("button", { name: "Delete" })).not.toBeInTheDocument()
  })

  it("deletes a briefing after a confirmation in the page", async () => {
    const confirm = vi.spyOn(window, "confirm")
    const { user, router } = renderApp("/sphere-app/briefing?briefing=b1")
    const chat = await screen.findByRole("region", { name: "Conversation" })
    await user.click(await within(chat).findByRole("button", { name: "Delete" }))
    const ask = within(chat).getByRole("group", { name: "Delete this briefing" })
    expect(ask).toHaveTextContent(
      `Delete "Pause a member's seat"? This removes its chat and draft. Tickets, inbox files and STAR's rows stay.`
    )
    await user.click(within(ask).getByRole("button", { name: "Keep it" }))
    expect(within(chat).queryByRole("group", { name: "Delete this briefing" })).not.toBeInTheDocument()
    expect(b1()).toBeDefined()
    await user.click(within(chat).getByRole("button", { name: "Delete" }))
    await user.click(within(chat).getByRole("button", { name: "Delete briefing" }))
    expect(
      await screen.findByText(`Deleted "Pause a member's seat".`, undefined, { timeout: 5_000 })
    ).toBeInTheDocument()
    await waitFor(() => expect(b1()).toBeUndefined())
    await waitFor(() => expect(router.state.location.search).toBe(""))
    await waitFor(
      () => expect(screen.getByRole("combobox", { name: "Briefing" })).toHaveTextContent("Export reports as CSV"),
      { timeout: 5_000 }
    )
    expect(confirm).not.toHaveBeenCalled()
  })

  it("says why the server refused to delete, and keeps the briefing", async () => {
    server.use(
      http.delete("*/api/projects/:p/briefings/:id", () =>
        HttpResponse.json({ error: "its ticket is still being created" }, { status: 409 })
      )
    )
    const { user } = renderApp("/sphere-app/briefing")
    const chat = await screen.findByRole("region", { name: "Conversation" })
    await user.click(await within(chat).findByRole("button", { name: "Delete" }))
    await user.click(within(chat).getByRole("button", { name: "Delete briefing" }))
    expect(
      await within(chat).findByText("Couldn't delete this briefing: its ticket is still being created")
    ).toBeInTheDocument()
    expect(b1()).toBeDefined()
  })
})
