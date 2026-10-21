import { screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it } from "vitest"
import { accountsFixture } from "@/mocks/accounts"
import { server } from "@/mocks/node"
import { renderApp } from "@/test/render"

const CHIP = "Claude accounts: main, 54% of the week left"
const nth = (rows: HTMLElement[], i: number) => {
  const row = rows[i]
  if (!row) throw new Error(`no row ${i}`)
  return row
}

describe("the accounts chip", () => {
  it("shows the active account's week left, and opens every account with its week, pace tick, reset and 5-hour window", async () => {
    const { user } = renderApp("/sphere-app/progress")
    const chip = await screen.findByRole("button", { name: CHIP })
    expect(chip).toHaveTextContent("54% left")
    expect(within(chip).getByText("main")).toHaveClass("hidden", "sm:inline")
    await user.click(chip)
    const pop = await screen.findByRole("dialog", { name: "Claude accounts" })
    expect(within(pop).getByText("auto on (cswap auto) · 1 min ago")).toBeInTheDocument()
    const rows = within(pop).getAllByRole("listitem")
    expect(rows).toHaveLength(3)
    expect(nth(rows, 0)).toHaveTextContent("main · active")
    expect(within(nth(rows, 0)).getByText("54% left")).toBeInTheDocument()
    expect(within(nth(rows, 0)).getByText("Week resets in 5d 23h · 5-hour window 95% left")).toBeInTheDocument()
    expect(within(nth(rows, 1)).getByText("2% left")).toHaveClass("text-stop-fg")
    expect(within(nth(rows, 1)).getByText("Week resets in 20h 49m · auto-switch skips it")).toBeInTheDocument()
    expect(within(nth(rows, 2)).getByText("Week resets in 3d 0h · auto-switch skips it")).toBeInTheDocument()
    const week = within(nth(rows, 0)).getByRole("meter", { name: "main: week" })
    expect(week).toHaveAttribute("aria-valuenow", "46")
    expect(week).toHaveAttribute("aria-valuetext", "54% left")
    expect(week.querySelector("[data-slot=pace-tick]")).toHaveStyle({ left: "14.4%" })
  })

  it("links to the accounts page and closes", async () => {
    const { user, router } = renderApp("/sphere-app/progress")
    await user.click(await screen.findByRole("button", { name: CHIP }))
    await user.click(await screen.findByRole("link", { name: "See every limit" }))
    await waitFor(() => expect(router.state.location.pathname).toBe("/sphere-app/accounts"))
    expect(screen.queryByRole("dialog", { name: "Claude accounts" })).not.toBeInTheDocument()
  })

  it("names a dry run and a failed read", async () => {
    const state = { ...accountsFixture(), auto: { state: "dry run", via: "cswap auto" }, problem: "cswap: timed out after 20 s" }
    server.use(http.get("*/api/accounts", () => HttpResponse.json(state)))
    const { user } = renderApp("/sphere-app/progress")
    await user.click(await screen.findByRole("button", { name: CHIP }))
    const pop = await screen.findByRole("dialog", { name: "Claude accounts" })
    expect(within(pop).getByText("auto in dry run (cswap auto) · 1 min ago")).toBeInTheDocument()
    expect(
      within(pop).getByText("The last read failed: cswap: timed out after 20 s. Showing the reading from 1 min ago.")
    ).toBeInTheDocument()
  })

  it("is hidden when cswap is not installed", async () => {
    const state = { installed: false, auto: { state: "off", via: "" }, fetchedAt: null, problem: "", accounts: [] }
    server.use(http.get("*/api/accounts", () => HttpResponse.json(state)))
    const { client } = renderApp("/sphere-app/progress")
    await waitFor(() => expect(client.getQueryState(["accounts"])?.status).toBe("success"))
    expect(screen.getByRole("button", { name: "Search (⌘K)" })).toBeInTheDocument()
    expect(screen.queryByRole("button", { name: /^Claude accounts/ })).not.toBeInTheDocument()
  })
})
