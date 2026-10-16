import { act, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it } from "vitest"
import { getConnection } from "@/api/events"
import { server } from "@/mocks/node"
import { getDb, mockEvents, setScenario } from "@/mocks/state"
import { renderApp } from "@/test/render"

const rows = () => screen.getAllByRole("row")

describe("Progress", () => {
  it("shows four summary cards and the item table", async () => {
    renderApp("/sphere-app/progress")
    const summary = await screen.findByRole("region", { name: "Summary" })
    expect(within(summary).getByText("Build slots")).toBeInTheDocument()
    expect(within(summary).getByText("3 of 3")).toBeInTheDocument()
    expect(within(summary).getByText("Waiting on you")).toBeInTheDocument()
    expect(within(summary).getByText("3")).toBeInTheDocument()
    expect(within(summary).getByText("In review")).toBeInTheDocument()
    expect(within(summary).getByText("Merged today")).toBeInTheDocument()
    expect(
      screen.getByText(/^2 building, 1 in review, \d merged today$/)
    ).toBeInTheDocument()
    expect(screen.getByText("Review gate up")).toBeInTheDocument()
    for (const name of ["Item", "Status", "Current step", "PR", "Updated"]) {
      expect(screen.getByRole("columnheader", { name })).toBeInTheDocument()
    }
    expect(rows()).toHaveLength(12)
    expect(screen.getByText("Codex gate, round 2 of 3")).toBeInTheDocument()
    expect(screen.getByText("#214")).toBeInTheDocument()
    expect(screen.getAllByText("None yet").length).toBeGreaterThan(0)
  })

  it("filters by tab and by ref or title", async () => {
    const { user } = renderApp("/sphere-app/progress")
    await user.click(
      await screen.findByRole("tab", { name: /^Needs you\s*3$/ })
    )
    expect(rows()).toHaveLength(4)
    await user.click(screen.getByRole("tab", { name: /^Merged\s*2$/ }))
    expect(rows()).toHaveLength(3)
    await user.click(screen.getByRole("tab", { name: /^All\s*11$/ }))
    await user.type(screen.getByLabelText("Filter items"), "invoice")
    expect(rows()).toHaveLength(3)
    await user.clear(screen.getByLabelText("Filter items"))
    await user.type(screen.getByLabelText("Filter items"), "zzz")
    expect(screen.getByText('No items match "zzz".')).toBeInTheDocument()
  })

  it("opens a row's sheet with its branch, PR and step log, and links to Needs you", async () => {
    const { user, router } = renderApp("/sphere-app/progress")
    await user.click(await screen.findByText("Remove the old export modal"))
    const sheet = await screen.findByRole("dialog")
    expect(router.state.location.search).toBe("?item=SPH-9")
    expect(
      await within(sheet).findByText(".worktrees/sphere-app/sph-9")
    ).toBeInTheDocument()
    expect(within(sheet).getByText("#213")).toBeInTheDocument()
    expect(within(sheet).getByText("Plan written, 4 tasks")).toBeInTheDocument()
    expect(
      within(sheet).getByText("Asked: widen the scope to the public API?")
    ).toBeInTheDocument()
    expect(
      within(sheet).getByRole("link", { name: /Open PR #213/ })
    ).toHaveAttribute("href", "https://github.com/example/sphere-app/pull/213")
    await user.click(
      within(sheet).getByRole("link", { name: "Answer in Needs you" })
    )
    await waitFor(() =>
      expect(
        router.state.location.pathname + router.state.location.search
      ).toBe("/sphere-app/needs?loop=N-43")
    )
  })

  it("links an item waiting in a go-batch to that batch", async () => {
    const row = getDb().items["sphere-app"]?.find(
      (d) => d.row.item === "SPH-14"
    )?.row
    if (row) row.status = "needs-you"
    const { user, router } = renderApp("/sphere-app/progress?item=SPH-14")
    const sheet = await screen.findByRole("dialog")
    await user.click(
      await within(sheet).findByRole("link", { name: "Answer in Needs you" })
    )
    await waitFor(() =>
      expect(
        router.state.location.pathname + router.state.location.search
      ).toBe("/sphere-app/needs?loop=N-41")
    )
  })

  it("links a merged item to its evidence, and opens from the URL", async () => {
    const { user, router } = renderApp("/sphere-app/progress?item=SPH-8")
    const sheet = await screen.findByRole("dialog")
    expect(
      await within(sheet).findByText("Merged under your go of Oct 15")
    ).toBeInTheDocument()
    expect(
      within(sheet).queryByRole("link", { name: "Answer in Needs you" })
    ).not.toBeInTheDocument()
    await user.click(within(sheet).getByRole("link", { name: /Evidence/ }))
    await waitFor(() =>
      expect(
        router.state.location.pathname + router.state.location.search
      ).toBe("/sphere-app/evidence?item=SPH-8")
    )
  })

  it("closes the sheet and drops ?item", async () => {
    const { user, router } = renderApp("/sphere-app/progress?item=SPH-11")
    await screen.findByRole("dialog")
    await user.keyboard("{Escape}")
    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument()
    )
    expect(router.state.location.search).toBe("")
  })

  it("has loading, empty and error states", async () => {
    setScenario("loading")
    const first = renderApp("/sphere-app/progress")
    expect(await screen.findByTestId("page-loading")).toBeInTheDocument()
    first.unmount()
    setScenario("empty")
    const second = renderApp("/sphere-app/progress")
    expect(await screen.findByText("No items yet.")).toBeInTheDocument()
    second.unmount()
    setScenario("error")
    renderApp("/sphere-app/progress")
    expect(await screen.findByTestId("page-error")).toHaveTextContent(
      "Couldn't load the items."
    )
  })

  it("renders null server values with fallbacks", async () => {
    const row = getDb().items["sphere-app"]?.find(
      (d) => d.row.item === "SPH-13"
    )
    if (!row) throw new Error("fixture SPH-13 missing")
    row.row.title = null
    row.progress = [{ time: null, text: "executor Executor writing the code" }]
    const { user } = renderApp("/sphere-app/progress")
    await user.click(
      (
        await screen.findAllByRole("button", { name: /SPH-13/ })
      )[0] as HTMLElement
    )
    const sheet = await screen.findByRole("dialog")
    expect(
      within(sheet).getByRole("heading", { name: "SPH-13" })
    ).toBeInTheDocument()
    expect(
      within(sheet).getByText("Executor writing the code")
    ).toBeInTheDocument()
    expect(within(sheet).queryByText(/null/)).not.toBeInTheDocument()
    expect(
      within(sheet).getByText(".worktrees/sphere-app/sph-13")
    ).toBeInTheDocument()
  })

  it("refreshes when STAR changes the ledger", async () => {
    renderApp("/sphere-app/progress")
    await screen.findByRole("tab", { name: /^All\s*11$/ })
    await waitFor(() => expect(getConnection()).toBe("open"))
    const sph13 = getDb().items["sphere-app"]?.find(
      (d) => d.row.item === "SPH-13"
    )
    if (!sph13) throw new Error("fixture SPH-13 missing")
    sph13.row.status = "merged"
    act(() =>
      mockEvents.emit({ type: "change", project: "sphere-app", what: "ledger" })
    )
    expect(
      await screen.findByRole("tab", { name: /^Merged\s*3$/ })
    ).toBeInTheDocument()
  })

  it("shows a dash, not 0 of 0, when the workers could not be read", async () => {
    server.use(
      http.get("*/api/projects/:p/overview", () =>
        HttpResponse.json(
          { error: "Could not read star.json" },
          { status: 502 }
        )
      )
    )
    renderApp("/sphere-app/progress")
    const summary = await screen.findByRole("region", { name: "Summary" })
    expect(within(summary).getByText("–")).toBeInTheDocument()
    expect(
      within(summary).getByText("Couldn't load the workers")
    ).toBeInTheDocument()
    expect(within(summary).queryByText("0 of 0")).not.toBeInTheDocument()
  })

  it("closes a sheet for an item that is gone with a clear message", async () => {
    renderApp("/sphere-app/progress?item=SPH-99")
    const sheet = await screen.findByRole("dialog")
    expect(
      await within(sheet).findByText(
        "It may have been removed or renamed. Pick another one."
      )
    ).toBeInTheDocument()
  })

  it("says the empty state's how", async () => {
    setScenario("empty")
    renderApp("/sphere-app/progress")
    expect(
      await screen.findByText(
        "Items show here once STAR takes work: type /juel:star <brief> in the project."
      )
    ).toBeInTheDocument()
  })
})
