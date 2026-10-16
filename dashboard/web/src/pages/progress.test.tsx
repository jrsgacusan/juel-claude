import { act, render, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it, vi } from "vitest"
import { getConnection } from "@/api/events"
import type { ItemDetail, ItemStatus } from "@/api/types"
import { Dot, StateBadge } from "@/components/status"
import { server } from "@/mocks/node"
import { getDb, mockEvents, setScenario } from "@/mocks/state"
import { renderApp } from "@/test/render"

const rows = () => screen.getAllByRole("row")
const pager = () => screen.getByRole("navigation", { name: "Item pages" })
const next = () => within(pager()).getByRole("button", { name: "Next page" })
const previous = () =>
  within(pager()).getByRole("button", { name: "Previous page" })

// 25 ledger rows for the paging tests (lane I owns mocks/fixtures.ts). By default R-01 to R-22
// are building (Running), R-23 and R-24 need you, R-25 is merged. Odd rows are "Export batch n",
// even rows "Import batch n". Every fifth row has PR #(300 + n).
function twentyFive(
  statusOf: (n: number) => ItemStatus = (n) =>
    n <= 22 ? "building" : n <= 24 ? "needs-you" : "merged"
): ItemDetail[] {
  return Array.from({ length: 25 }, (_, i) => {
    const n = i + 1
    const id = `R-${String(n).padStart(2, "0")}`
    const pr = n % 5 === 0 ? 300 + n : null
    return {
      row: {
        item: id,
        ref: id,
        state: "building",
        stage: "build",
        worktree: `/Users/owner/code/sphere-app/.worktrees/sphere-app/${id.toLowerCase()}-a-branch-name-long-enough-to-wrap`,
        pr: pr ? String(pr) : "-",
        head: null,
        updated: new Date().toISOString(),
        title: `${n % 2 ? "Export" : "Import"} batch ${n}`,
        status: statusOf(n),
        step: null,
        prUrl: pr ? `https://github.com/example/sphere-app/pull/${pr}` : null,
      },
      progress: [],
      criteria: [],
      decisions: [],
    }
  })
}
const use25 = (statusOf?: (n: number) => ItemStatus) => {
  getDb().items["sphere-app"] = twentyFive(statusOf)
}

// The repo's matchMedia spy (test/render.tsx mockColorScheme), true only for the phone query.
function mockPhone() {
  vi.spyOn(window, "matchMedia").mockImplementation(
    (query: string) =>
      ({
        matches: query === "(max-width: 639px)",
        media: query,
        onchange: null,
        addEventListener: () => {},
        removeEventListener: () => {},
        addListener: () => {},
        removeListener: () => {},
        dispatchEvent: () => false,
      }) as unknown as MediaQueryList
  )
}

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
    expect(rows()).toHaveLength(7)
    expect(
      screen.queryByRole("navigation", { name: "Item pages" })
    ).not.toBeInTheDocument()
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
    await user.click(
      await screen.findByRole("tab", { name: /^Needs you\s*3$/ })
    )
    await user.click(screen.getByText("Remove the old export modal"))
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

  it("names an item by its ledger name, with only a tracker ref beside it (integration brief D5)", async () => {
    const items = getDb().items["sphere-app"] ?? []
    const rowOf = (item: string) => {
      const found = items.find((d) => d.row.item === item)
      if (!found) throw new Error(`fixture ${item} missing`)
      return found.row
    }
    rowOf("SPH-13").ref = "/Users/owner/star/items/sphere-app/sph-13.md"
    rowOf("SPH-13").title = null
    rowOf("SPH-14").ref = "-"
    rowOf("SPH-12").ref = "#41"
    const { user } = renderApp("/sphere-app/progress")
    const sph13 = await screen.findByRole("button", { name: /^SPH-13 SPH-13$/ })
    expect(screen.getByRole("button", { name: /^SPH-14 / })).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /^SPH-12 · #41 / })
    ).toBeInTheDocument()
    expect(
      within(screen.getByRole("button", { name: /^SPH-12 · #41 / })).getByText(
        "SPH-12 · #41"
      )
    ).toBeInTheDocument()
    expect(screen.queryByText(/sph-13\.md/)).not.toBeInTheDocument()
    await user.click(sph13)
    const sheet = await screen.findByRole("dialog")
    expect(
      within(sheet).getByRole("heading", { name: "SPH-13" })
    ).toBeInTheDocument()
    expect(within(sheet).queryByText(/sph-13\.md/)).not.toBeInTheDocument()
  })

  it("the sheet header shows the item name and its tracker ref (integration brief D5)", async () => {
    const row = getDb().items["sphere-app"]?.find(
      (d) => d.row.item === "SPH-12"
    )?.row
    if (!row) throw new Error("fixture SPH-12 missing")
    row.ref = "#41"
    renderApp("/sphere-app/progress?item=SPH-12")
    const sheet = await screen.findByRole("dialog")
    expect(await within(sheet).findByText("SPH-12 · #41")).toBeInTheDocument()
  })

  it("links an item waiting in a go-batch to that batch", async () => {
    const row = getDb().items["sphere-app"]?.find(
      (d) => d.row.item === "SPH-12"
    )?.row
    if (row) row.status = "needs-you"
    const { user, router } = renderApp("/sphere-app/progress?item=SPH-12")
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

  it("links an item with its own open loop to that loop, not its batch", async () => {
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
      ).toBe("/sphere-app/needs?loop=N-44")
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

describe("Progress pages", () => {
  it("opens on Running, with Running first, ten rows a page", async () => {
    use25()
    const { user } = renderApp("/sphere-app/progress")
    const running = await screen.findByRole("tab", { name: /^Running\s*22$/ })
    expect(running).toHaveAttribute("aria-selected", "true")
    expect(screen.getAllByRole("tab").map((t) => t.textContent)).toEqual([
      "Running 22",
      "All 25",
      "Needs you 2",
      "Merged 1",
    ])
    expect(rows()).toHaveLength(11)
    expect(pager()).toHaveTextContent("Page 1 of 3")
    expect(screen.getByRole("button", { name: /^R-01 / })).toBeInTheDocument()
    expect(
      screen.queryByRole("button", { name: /^R-11 / })
    ).not.toBeInTheDocument()
    await user.click(next())
    expect(pager()).toHaveTextContent("Page 2 of 3")
    expect(screen.getByRole("button", { name: /^R-11 / })).toBeInTheDocument()
    expect(
      screen.queryByRole("button", { name: /^R-01 / })
    ).not.toBeInTheDocument()
    await user.click(next())
    expect(pager()).toHaveTextContent("Page 3 of 3")
    expect(rows()).toHaveLength(3)
    await user.click(previous())
    expect(pager()).toHaveTextContent("Page 2 of 3")
  })

  it("filters every row of the tab first, then pages the result", async () => {
    use25()
    const { user } = renderApp("/sphere-app/progress")
    await screen.findByRole("tab", { name: /^Running\s*22$/ })
    await user.type(screen.getByLabelText("Filter items"), "export")
    expect(pager()).toHaveTextContent("Page 1 of 2")
    expect(rows()).toHaveLength(11)
    expect(
      screen.queryByRole("button", { name: /Import batch/ })
    ).not.toBeInTheDocument()
    await user.click(next())
    expect(rows()).toHaveLength(2)
    expect(
      screen.getByRole("button", { name: "R-21 Export batch 21" })
    ).toBeInTheDocument()
  })

  it("goes back to page 1 when the tab or the filter changes", async () => {
    use25()
    const { user } = renderApp("/sphere-app/progress")
    await screen.findByRole("tab", { name: /^Running\s*22$/ })
    await user.click(next())
    expect(pager()).toHaveTextContent("Page 2 of 3")
    await user.click(screen.getByRole("tab", { name: /^All\s*25$/ }))
    expect(pager()).toHaveTextContent("Page 1 of 3")
    await user.click(next())
    expect(pager()).toHaveTextContent("Page 2 of 3")
    await user.type(screen.getByLabelText("Filter items"), "batch")
    expect(pager()).toHaveTextContent("Page 1 of 3")
  })

  it("clamps to the last page when rows leave the tab", async () => {
    use25()
    const { user } = renderApp("/sphere-app/progress")
    await screen.findByRole("tab", { name: /^Running\s*22$/ })
    await waitFor(() => expect(getConnection()).toBe("open"))
    await user.click(next())
    await user.click(next())
    expect(pager()).toHaveTextContent("Page 3 of 3")
    for (const detail of getDb().items["sphere-app"] ?? [])
      if (["R-21", "R-22"].includes(detail.row.item))
        detail.row.status = "merged"
    act(() =>
      mockEvents.emit({ type: "change", project: "sphere-app", what: "ledger" })
    )
    await waitFor(() => expect(pager()).toHaveTextContent("Page 2 of 2"))
    expect(rows()).toHaveLength(11)
  })

  it("says nothing is running and links to All when Running is empty", async () => {
    use25(() => "merged")
    const { user } = renderApp("/sphere-app/progress")
    expect(
      await screen.findByText("Nothing is running right now.")
    ).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: "Show all items" }))
    expect(screen.getByRole("tab", { name: /^All\s*25$/ })).toHaveAttribute(
      "aria-selected",
      "true"
    )
    expect(pager()).toHaveTextContent("Page 1 of 3")
  })

  it("shows cards below sm, with the same pages and the same sheet", async () => {
    mockPhone()
    use25()
    const { user, router } = renderApp("/sphere-app/progress")
    const list = await screen.findByRole("list", { name: "Items" })
    expect(screen.queryByRole("table")).not.toBeInTheDocument()
    expect(within(list).getAllByRole("listitem")).toHaveLength(10)
    const first = within(list).getByRole("button", {
      name: "R-01 Export batch 1",
    })
    expect(first).toHaveTextContent("R-01")
    expect(first).toHaveTextContent("Export batch 1")
    expect(first).toHaveTextContent("Building")
    expect(first).toHaveTextContent("None yet")
    expect(
      within(list).getByRole("button", { name: "R-05 Export batch 5" })
    ).toHaveTextContent("#305")
    expect(pager()).toHaveTextContent("Page 1 of 3")
    await user.click(next())
    await user.click(
      screen.getByRole("button", { name: "R-11 Export batch 11" })
    )
    const sheet = await screen.findByRole("dialog")
    expect(
      within(sheet).getByRole("heading", { name: "Export batch 11" })
    ).toBeInTheDocument()
    expect(router.state.location.search).toBe("?item=R-11")
  })

  it("shows the table from sm, its cells wrapping until md", async () => {
    use25()
    renderApp("/sphere-app/progress")
    const table = await screen.findByRole("table")
    expect(
      screen.queryByRole("list", { name: "Items" })
    ).not.toBeInTheDocument()
    expect(table).toHaveClass("md:min-w-[720px]")
    expect(table).not.toHaveClass("min-w-[720px]")
    const cell = within(table).getAllByRole("cell")[0] as HTMLElement
    expect(cell).toHaveClass("md:whitespace-nowrap")
    expect(cell).not.toHaveClass("whitespace-nowrap")
  })

  it("lets the tabs scroll and puts the stat cards in two columns", async () => {
    renderApp("/sphere-app/progress")
    const summary = await screen.findByRole("region", { name: "Summary" })
    expect(summary).toHaveClass("grid-cols-2")
    expect(summary).toHaveClass("lg:grid-cols-4")
    expect(screen.getByRole("tablist").parentElement).toHaveClass(
      "overflow-x-auto"
    )
    expect(screen.getByLabelText("Filter items")).toHaveClass(
      "pointer-coarse:h-11"
    )
  })

  it("wraps a long gate-down reason, and only that badge", async () => {
    const overview = getDb().overview["sphere-app"]
    if (!overview) throw new Error("fixture overview missing")
    overview.gateDown = {
      since: null,
      why: "codex usage limit reached until 14:00 and the hosted reviewer has not answered",
    }
    renderApp("/sphere-app/progress")
    const badge = await screen.findByText(
      "Review gate down: codex usage limit reached until 14:00 and the hosted reviewer has not answered"
    )
    expect(badge).toHaveClass("whitespace-normal")
    expect(badge).not.toHaveClass("whitespace-nowrap")
    expect(badge).not.toHaveClass("h-5")
    const building = within(screen.getByRole("table")).getAllByText(
      "Building"
    )[0]
    expect(building).toHaveClass("whitespace-nowrap")
  })

  it("keeps the sheet's title clear of the close button and its worktree path readable", async () => {
    renderApp("/sphere-app/progress?item=SPH-9")
    const sheet = await screen.findByRole("dialog")
    const path = await within(sheet).findByText(".worktrees/sphere-app/sph-9")
    expect(path).toHaveClass("break-all", "select-all")
    expect(path).not.toHaveClass("truncate")
    expect(sheet.querySelector('[data-slot="sheet-header"]')).toHaveClass(
      "pr-12"
    )
  })

  it("eases in a row that changes state, once, and not after a page turn", async () => {
    use25()
    const { user } = renderApp("/sphere-app/progress")
    await screen.findByRole("button", { name: "R-03 Export batch 3" })
    await waitFor(() => expect(getConnection()).toBe("open"))
    expect(document.querySelector(".motion-row-in")).toBeNull()
    const r03 = getDb().items["sphere-app"]?.find((d) => d.row.item === "R-03")
    if (!r03) throw new Error("row R-03 missing")
    r03.row.status = "in-review"
    act(() =>
      mockEvents.emit({ type: "change", project: "sphere-app", what: "ledger" })
    )
    const badge = await within(screen.getByRole("table")).findByText(
      "In review"
    )
    expect(badge.closest("tr")).toHaveClass("motion-row-in")
    expect(document.querySelectorAll(".motion-row-in")).toHaveLength(1)
    await user.click(next())
    expect(document.querySelector(".motion-row-in")).toBeNull()
    await user.click(previous())
    expect(document.querySelector(".motion-row-in")).toBeNull()
  })

  it("eases in a card that changes state on a phone", async () => {
    mockPhone()
    use25()
    renderApp("/sphere-app/progress")
    const list = await screen.findByRole("list", { name: "Items" })
    await waitFor(() => expect(getConnection()).toBe("open"))
    const r04 = getDb().items["sphere-app"]?.find((d) => d.row.item === "R-04")
    if (!r04) throw new Error("row R-04 missing")
    r04.row.status = "in-review"
    act(() =>
      mockEvents.emit({ type: "change", project: "sphere-app", what: "ledger" })
    )
    const badge = await within(list).findByText("In review")
    expect(badge.closest("li")).toHaveClass("motion-row-in")
    expect(list).toHaveClass("motion-fade-in")
  })

  it("cross-fades the rows on a page or tab change, and not on a data refresh", async () => {
    use25()
    const { user } = renderApp("/sphere-app/progress")
    await screen.findByRole("button", { name: "R-02 Import batch 2" })
    await waitFor(() => expect(getConnection()).toBe("open"))
    const body = () => document.querySelector('[data-slot="table-body"]')
    const first = body()
    expect(first).toHaveClass("motion-fade-in")
    const r02 = getDb().items["sphere-app"]?.find((d) => d.row.item === "R-02")
    if (!r02) throw new Error("row R-02 missing")
    r02.row.title = "Import batch 2, renamed"
    act(() =>
      mockEvents.emit({ type: "change", project: "sphere-app", what: "ledger" })
    )
    await screen.findByRole("button", { name: "R-02 Import batch 2, renamed" })
    expect(body()).toBe(first)
    await user.click(next())
    const second = body()
    expect(second).not.toBe(first)
    expect(second).toHaveClass("motion-fade-in")
    await user.click(screen.getByRole("tab", { name: /^All\s*25$/ }))
    expect(body()).not.toBe(second)
    expect(body()).toHaveClass("motion-fade-in")
  })
})

describe("status marks", () => {
  it("pulses the status dot with motion-ping, and never a row's state badge", () => {
    const dot = render(<Dot tone="done" pulse />)
    expect(dot.container.querySelector(".motion-ping")).not.toBeNull()
    expect(dot.container.querySelector(".animate-ping")).toBeNull()
    dot.unmount()
    const badge = render(<StateBadge status="building" />)
    expect(badge.container.querySelector(".motion-ping")).toBeNull()
    expect(badge.container.querySelector(".animate-ping")).toBeNull()
  })
})
