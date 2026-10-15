import { act, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it } from "vitest"
import { getConnection } from "@/api/events"
import { server } from "@/mocks/node"
import { getDb, mockEvents, setScenario } from "@/mocks/state"
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

  it("streams the agent's turn from briefing events", async () => {
    const { user } = renderApp("/sphere-app/briefing")
    const box = await screen.findByLabelText("Message the briefing agent")
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.type(box, "Also log who paused it{Enter}")
    const chat = screen.getByRole("region", { name: "Conversation" })
    expect(
      await within(chat).findByText("Also log who paused it")
    ).toBeInTheDocument()
    expect(
      await within(chat).findByTestId("agent-streaming")
    ).toBeInTheDocument()
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

  it("shows Retry when a turn fails", async () => {
    renderApp("/sphere-app/briefing")
    await screen.findByLabelText("Message the briefing agent")
    await waitFor(() => expect(getConnection()).toBe("open"))
    act(() =>
      mockEvents.emit({
        type: "briefing",
        project: "sphere-app",
        id: "b1",
        error: "claude exited 1",
      })
    )
    const chat = screen.getByRole("region", { name: "Conversation" })
    expect(
      await within(chat).findByText(
        "The briefing agent stopped: claude exited 1."
      )
    ).toBeInTheDocument()
    expect(
      within(chat).getByRole("button", { name: "Retry" })
    ).toBeInTheDocument()
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
