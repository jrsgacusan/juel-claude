import { act, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it } from "vitest"
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

  it("opens the briefing a search result names", async () => {
    renderApp("/sphere-app/briefing?id=b0")
    expect(
      await screen.findByRole("combobox", { name: "Briefing" })
    ).toHaveTextContent("Export reports as CSV")
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
    await user.click(
      within(draft).getByRole("button", { name: "Save as a spec instead" })
    )
    expect(
      await screen.findByText("Saved as a spec file. STAR is briefing it now.")
    ).toBeInTheDocument()
  })

  it("starts a new briefing", async () => {
    const { user, router } = renderApp("/sphere-app/briefing")
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
    ).toBeInTheDocument()
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
})
