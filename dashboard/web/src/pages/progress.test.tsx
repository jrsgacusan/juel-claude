import { act, render, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it, vi } from "vitest"
import { getConnection } from "@/api/events"
import type { ItemDetail, ItemStatus } from "@/api/types"
import { Dot, StateBadge } from "@/components/status"
import { UPCOMING } from "@/lib/stage"
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
  const updated = new Date().toISOString()
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
        updated,
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
  it("shows one summary line and the item table with a Stage column", async () => {
    renderApp("/sphere-app/progress")
    expect(
      await screen.findByText("3 of 3 build slots busy.")
    ).toBeInTheDocument()
    expect(
      screen.queryByRole("region", { name: "Summary" })
    ).not.toBeInTheDocument()
    expect(screen.getByRole("img", { name: "3 of 3 busy" })).toBeInTheDocument()
    expect(screen.getByText("1 in review, 2 merged today.")).toBeInTheDocument()
    expect(screen.getByText("Review gate up")).toBeInTheDocument()
    for (const name of ["Item", "Stage", "PR", "Updated"]) {
      expect(screen.getByRole("columnheader", { name })).toBeInTheDocument()
    }
    expect(
      screen.queryByRole("columnheader", { name: "Status" })
    ).not.toBeInTheDocument()
    expect(rows()).toHaveLength(7)
    expect(
      screen.queryByRole("navigation", { name: "Item pages" })
    ).not.toBeInTheDocument()
    const sph11 = rows().find((r) =>
      within(r).queryByText("Codex gate, round 2 of 3")
    )
    expect(sph11).toBeDefined()
    expect(
      within(sph11!).getByRole("img", { name: /^Stage 3 of 5, Gate/ })
    ).toBeInTheDocument()
    expect(screen.getByText("#214")).toBeInTheDocument()
    expect(screen.queryByText("None yet")).not.toBeInTheDocument()
  })

  it("says Couldn't load the workers when the overview fails", async () => {
    server.use(
      http.get("*/api/projects/:p/overview", () =>
        HttpResponse.json(
          { error: "Could not read star.json" },
          { status: 502 }
        )
      )
    )
    renderApp("/sphere-app/progress")
    expect(
      await screen.findByText("Couldn't load the workers.")
    ).toBeInTheDocument()
    expect(screen.queryByRole("img", { name: /busy$/ })).not.toBeInTheDocument()
    expect(screen.queryByText(/build slots busy/)).not.toBeInTheDocument()
  })

  it("calls out the loop that blocks most, with a link to Needs you, and only when one waits", async () => {
    const { user, router } = renderApp("/sphere-app/progress")
    const callout = await screen.findByText(/^SPH-7 waits on you: /)
    expect(callout).toHaveTextContent(
      "SPH-7 waits on you: The merge gate failed twice on e3f1a92. 8 more wait on you."
    )
    const link = screen.getByRole("link", { name: "Open Needs you" })
    expect(link).toHaveClass("pointer-coarse:h-11")
    expect(link).toHaveAttribute("data-variant", "answer")
    expect(link).toHaveAttribute("href", "/needs?project=sphere-app")
    await user.click(link)
    await waitFor(() =>
      expect(
        router.state.location.pathname + router.state.location.search
      ).toBe("/needs?project=sphere-app")
    )
  })

  it("has no callout when the project has no unanswered loops", async () => {
    getDb().loops["sphere-app"] = []
    renderApp("/sphere-app/progress")
    await screen.findByText("3 of 3 build slots busy.")
    expect(screen.queryByText(/waits? on you/)).not.toBeInTheDocument()
    expect(
      screen.queryByRole("link", { name: "Open Needs you" })
    ).not.toBeInTheDocument()
  })

  it("puts a needs-you row's step text in the wait tone", async () => {
    const { user } = renderApp("/sphere-app/progress")
    await user.click(await screen.findByRole("tab", { name: /^Blocked\s*3$/ }))
    expect(
      screen.getByText("Asked: widen the scope to the public API?")
    ).toHaveClass("text-wait-fg")
  })

  it("reads a queued row with no step as waiting for a slot", async () => {
    const row = getDb().items["sphere-app"]?.find(
      (d) => d.row.item === "SPH-14"
    )
    if (!row) throw new Error("fixture missing")
    row.row.step = null
    row.row.state = "queued"
    renderApp("/sphere-app/progress")
    expect(
      await screen.findByText("Queued for a build slot")
    ).toBeInTheDocument()
  })

  it("shows Report and no rail for a report item, and the status label for an unknown state", async () => {
    const items = getDb().items["sphere-app"]!
    const report = items.find((d) => d.row.item === "SPH-13")!
    report.row.stage = "post"
    report.row.state = "posting"
    const odd = items.find((d) => d.row.item === "SPH-15")!
    odd.row.state = "mystery"
    odd.row.step = null
    renderApp("/sphere-app/progress")
    const reportRow = (
      await screen.findByRole("button", { name: /^SPH-13 / })
    ).closest("tr")!
    expect(within(reportRow).getByText("Report")).toBeInTheDocument()
    expect(
      within(reportRow).getByText("Executor writing the code")
    ).toBeInTheDocument()
    expect(within(reportRow).queryByRole("img")).not.toBeInTheDocument()
    const oddRow = screen
      .getByRole("button", { name: /^SPH-15 / })
      .closest("tr")!
    expect(within(oddRow).queryByRole("img")).not.toBeInTheDocument()
    expect(within(oddRow).getByText("Briefing")).toBeInTheDocument()
  })

  it("shows Dropped for a dropped row", async () => {
    const row = getDb().items["sphere-app"]?.find(
      (d) => d.row.item === "SPH-13"
    )
    if (!row) throw new Error("fixture missing")
    row.row.state = "dropped"
    row.row.status = "dropped"
    row.row.step = null
    const { user } = renderApp("/sphere-app/progress")
    await user.click(await screen.findByRole("tab", { name: /^All\s*11$/ }))
    const tr = screen.getByRole("button", { name: /^SPH-13 / }).closest("tr")!
    expect(within(tr).getByText("Dropped")).toBeInTheDocument()
  })

  it("lists what merged today by mergedAt, under the table, hidden on the Merged tab", async () => {
    const { user } = renderApp("/sphere-app/progress")
    const list = await screen.findByRole("list", { name: "Merged today" })
    expect(within(list).getAllByRole("listitem")).toHaveLength(2)
    expect(list.closest("table")).toBeNull()
    for (const ref of ["SPH-8", "SPH-4"]) {
      const li = within(list).getByText(ref).closest("li")!
      expect(
        within(li).getByRole("link", { name: "Evidence" })
      ).toHaveAttribute("href", `/sphere-app/evidence?item=${ref}`)
    }
    const sph8 = within(list).getByText("SPH-8").closest("li")!
    expect(within(sph8).getByRole("link", { name: /#207/ })).toHaveAttribute(
      "href",
      "https://github.com/example/sphere-app/pull/207"
    )
    expect(within(sph8).getByText("Fix invoice rounding")).toBeInTheDocument()
    await user.click(screen.getByRole("tab", { name: /^Merged\s*2$/ }))
    expect(
      screen.queryByRole("list", { name: "Merged today" })
    ).not.toBeInTheDocument()
  })

  it("does not count a row merged yesterday but updated today as merged today", async () => {
    const row = getDb().items["sphere-app"]?.find((d) => d.row.item === "SPH-4")
    if (!row) throw new Error("fixture missing")
    row.row.mergedAt = new Date(Date.now() - 48 * 3600_000).toISOString()
    row.row.updated = new Date().toISOString()
    renderApp("/sphere-app/progress")
    expect(
      await screen.findByText("1 in review, 1 merged today.")
    ).toBeInTheDocument()
    const list = screen.getByRole("list", { name: "Merged today" })
    expect(within(list).getAllByRole("listitem")).toHaveLength(1)
    expect(within(list).queryByText("SPH-4")).not.toBeInTheDocument()
  })

  it("does not count a merged row with no mergedAt", async () => {
    for (const d of getDb().items["sphere-app"] ?? [])
      if (d.row.status === "merged") d.row.mergedAt = null
    renderApp("/sphere-app/progress")
    expect(
      await screen.findByText("1 in review, 0 merged today.")
    ).toBeInTheDocument()
    expect(
      screen.queryByRole("list", { name: "Merged today" })
    ).not.toBeInTheDocument()
  })

  it("filters by tab and by ref or title", async () => {
    const { user } = renderApp("/sphere-app/progress")
    await user.click(await screen.findByRole("tab", { name: /^Blocked\s*3$/ }))
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
    await user.click(await screen.findByRole("tab", { name: /^Blocked\s*3$/ }))
    await user.click(screen.getByText("Remove the old export modal"))
    const sheet = await screen.findByRole("dialog")
    expect(router.state.location.search).toBe("?item=SPH-9")
    expect(
      await within(sheet).findByText(".worktrees/sphere-app/sph-9")
    ).toBeInTheDocument()
    expect(within(sheet).getByText("#213")).toBeInTheDocument()
    expect(within(sheet).getByText("Plan written, 4 tasks")).toBeInTheDocument()
    expect(
      within(sheet).getAllByText("Asked: widen the scope to the public API?")
    ).toHaveLength(2)
    expect(
      within(sheet).getByRole("link", { name: /Open PR #213/ })
    ).toHaveAttribute("href", "https://github.com/example/sphere-app/pull/213")
    await user.click(
      within(sheet).getByRole("link", { name: "Answer in Needs you" })
    )
    await waitFor(() =>
      expect(
        router.state.location.pathname + router.state.location.search
      ).toBe("/needs?project=sphere-app&loop=N-43")
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

  it("links an item with no loop of its own to its project's Needs you", async () => {
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
      ).toBe("/needs?project=sphere-app")
    )
  })

  it("links an item with its own open loop to that loop", async () => {
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
      ).toBe("/needs?project=sphere-app&loop=N-44")
    )
  })

  it("links a merged item to its evidence, and opens from the URL", async () => {
    const { user, router } = renderApp("/sphere-app/progress?item=SPH-8")
    const sheet = await screen.findByRole("dialog")
    expect(
      (
        await within(sheet).findAllByText("Merged after the merge gate passed")
      )[0]
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

  it("heads the sheet with ref, PR and age on one line, then the title, a large rail and Now", async () => {
    renderApp("/sphere-app/progress?item=SPH-11")
    const sheet = await screen.findByRole("dialog")
    const head = await within(sheet).findByText(/^updated /)
    expect(head.parentElement).toHaveTextContent(/^SPH-11\s*#214\s*updated /)
    expect(
      within(sheet).getByRole("heading", { name: "Export reports as CSV" })
    ).toBeInTheDocument()
    const rail = within(sheet).getByRole("img", { name: /^Stage 3 of 5, Gate/ })
    expect(rail).toHaveAttribute("data-size", "lg")
    for (const name of ["Brief", "Build", "Gate", "Review", "Merge"])
      expect(within(rail).getByText(name)).toBeInTheDocument()
    expect(within(sheet).getByText("Now")).toBeInTheDocument()
    expect(within(sheet).getAllByText("Codex gate, round 2 of 3")).toHaveLength(
      2
    )
    expect(within(sheet).getByText("Worktree")).toBeInTheDocument()
    expect(within(sheet).getByText(".worktrees/sphere-app/sph-11")).toHaveClass(
      "truncate",
      "select-all"
    )
  })

  it("says Not created yet for an item with no worktree", async () => {
    renderApp("/sphere-app/progress?item=SPH-15")
    const sheet = await screen.findByRole("dialog")
    expect(await within(sheet).findByText("Not created yet")).toHaveClass(
      "select-all"
    )
  })

  it("lists the stages still to come as muted lines after the progress", async () => {
    renderApp("/sphere-app/progress?item=SPH-11")
    const sheet = await screen.findByRole("dialog")
    const review = await within(sheet).findByText(UPCOMING.Review)
    const merge = within(sheet).getByText(UPCOMING.Merge)
    expect(review).toHaveClass("text-muted-foreground")
    expect(merge.textContent).toBe("STAR merges it once every gate holds")
    expect(within(sheet).queryByText(UPCOMING.Build)).not.toBeInTheDocument()
    expect(within(sheet).queryByText(UPCOMING.Gate)).not.toBeInTheDocument()
    const last = within(sheet).getAllByText("Codex gate, round 2 of 3").at(-1)!
    expect(
      last.compareDocumentPosition(review) & Node.DOCUMENT_POSITION_FOLLOWING
    ).toBeTruthy()
  })

  it("lists no steps to come for a merged item", async () => {
    renderApp("/sphere-app/progress?item=SPH-8")
    const sheet = await screen.findByRole("dialog")
    await within(sheet).findAllByText("Merged after the merge gate passed")
    expect(within(sheet).queryByText(UPCOMING.Merge)).not.toBeInTheDocument()
  })

  it("uses the answer variant for Answer in Needs you, and links Ask STAR about it to Chat", async () => {
    const row = getDb().items["sphere-app"]?.find(
      (d) => d.row.item === "SPH-14"
    )
    if (!row) throw new Error("fixture missing")
    row.row.status = "needs-you"
    renderApp("/sphere-app/progress?item=SPH-14")
    const sheet = await screen.findByRole("dialog")
    expect(
      await within(sheet).findByRole("link", { name: "Answer in Needs you" })
    ).toHaveAttribute("data-variant", "answer")
    expect(
      within(sheet).getByRole("link", { name: "Ask STAR about it" })
    ).toHaveAttribute("href", "/sphere-app/chat?draft=About%20SPH-14%3A%20")
    // Touch size on a phone, as every other button in the app.
    for (const name of ["Answer in Needs you", "Ask STAR about it"])
      expect(within(sheet).getByRole("link", { name })).toHaveClass("pointer-coarse:h-11")
  })

  it("opens from the bottom on a phone and from the right wider", async () => {
    mockPhone()
    const phone = renderApp("/sphere-app/progress?item=SPH-11")
    expect(await screen.findByRole("dialog")).toHaveAttribute(
      "data-side",
      "bottom"
    )
    phone.unmount()
    vi.restoreAllMocks()
    renderApp("/sphere-app/progress?item=SPH-11")
    expect(await screen.findByRole("dialog")).toHaveAttribute(
      "data-side",
      "right"
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
      within(sheet).getAllByText("Executor writing the code")[0]
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
      "Blocked 2",
      "Merged 1",
      "All 25",
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
    expect(screen.getByRole("button", { name: "Show all items" })).toHaveClass(
      "pointer-coarse:h-11"
    )
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
    expect(first).not.toHaveTextContent("Building")
    expect(first).not.toHaveTextContent("None yet")
    expect(
      within(first).getByRole("img", { name: /^Stage 2 of 5, Build/ })
    ).toBeInTheDocument()
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

  it("shows the table from sm, fixed to its width with the title wrapping", async () => {
    use25()
    renderApp("/sphere-app/progress")
    const table = await screen.findByRole("table")
    expect(
      screen.queryByRole("list", { name: "Items" })
    ).not.toBeInTheDocument()
    expect(table).toHaveClass("table-fixed")
    expect(table.className).not.toMatch(/min-w-/)
    const cell = within(table).getAllByRole("cell")[0] as HTMLElement
    expect(cell).toHaveClass("md:whitespace-normal")
    expect(cell).not.toHaveClass("md:whitespace-nowrap")
  })

  it("lists the latest update first", async () => {
    use25((n) => (n <= 3 ? "merged" : "building"))
    const items = getDb().items["sphere-app"]!
    items[0]!.row.updated = "2026-01-01T00:00:00Z"
    items[1]!.row.updated = "2026-03-01T00:00:00Z"
    items[2]!.row.updated = "2026-02-01T00:00:00Z"
    const { user } = renderApp("/sphere-app/progress")
    await user.click(await screen.findByRole("tab", { name: /^Merged/ }))
    expect(
      rows()
        .slice(1)
        .map((r) => within(r).getByRole("button").getAttribute("aria-label"))
    ).toEqual([
      "R-02 Import batch 2",
      "R-03 Export batch 3",
      "R-01 Export batch 1",
    ])
  })

  it("lets the tabs scroll", async () => {
    renderApp("/sphere-app/progress")
    await screen.findByRole("tablist")
    expect(screen.getByRole("tablist").parentElement).toHaveClass(
      "overflow-x-auto",
      "overflow-y-hidden"
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
  })

  it("keeps the sheet's title clear of the close button and its worktree path readable", async () => {
    renderApp("/sphere-app/progress?item=SPH-9")
    const sheet = await screen.findByRole("dialog")
    const path = await within(sheet).findByText(".worktrees/sphere-app/sph-9")
    expect(path).toHaveClass("truncate", "select-all")
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
    await waitFor(() =>
      expect(
        screen
          .getByRole("button", { name: "R-03 Export batch 3" })
          .closest("tr")
      ).toHaveClass("motion-row-in")
    )
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
    await waitFor(() =>
      expect(
        within(list)
          .getByRole("button", { name: "R-04 Import batch 4" })
          .closest("li")
      ).toHaveClass("motion-row-in")
    )
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
