import { screen, waitFor, within } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { setScenario } from "@/mocks/state"
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
      await within(sheet).findByText("feat/sph-9-remove-export-modal")
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
})
