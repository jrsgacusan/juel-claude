import { screen, within } from "@testing-library/react"
import { afterEach, describe, expect, it } from "vitest"
import { renderApp } from "@/test/render"

const setWidth = (value: number) =>
  Object.defineProperty(window, "innerWidth", { configurable: true, writable: true, value })
afterEach(() => setWidth(1024))

const before = (a: HTMLElement, b: HTMLElement) =>
  Boolean(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING)

describe("More", () => {
  it("lists Away, Workers, the pages, the projects and the theme, in that order", async () => {
    setWidth(390)
    const { user } = renderApp("/sphere-app/more")
    expect(await screen.findByRole("heading", { level: 1, name: "More" })).toBeInTheDocument()
    const away = await screen.findByRole("switch", { name: "Away" })
    const workers = await screen.findByText("Workers")
    expect(await screen.findByText("1 of 4")).toBeInTheDocument()
    const pages = screen.getByRole("navigation", { name: "sphere-app" })
    const links = within(pages).getAllByRole("link")
    expect(links.map((l) => l.getAttribute("href"))).toEqual([
      "/sphere-app/slack",
      "/sphere-app/briefing",
      "/sphere-app/evidence",
      "/sphere-app/accounts",
    ])
    expect(within(links[0]!).getByText("Slack replies")).toBeInTheDocument()
    expect(within(links[0]!).getByText(/^\d+ to route$/)).toBeInTheDocument()
    expect(await within(links[3]!).findByText("main, 54% left")).toBeInTheDocument()
    const projects = screen.getByRole("navigation", { name: "Projects" })
    expect(within(projects).getByRole("link", { name: /sphere-app/ })).toHaveAttribute("href", "/sphere-app/more")
    const system = screen.getByRole("radio", { name: "System theme" })
    expect(screen.getByRole("radio", { name: "Light theme" })).toBeInTheDocument()
    const dark = screen.getByRole("radio", { name: "Dark theme" })
    expect(before(away, workers)).toBe(true)
    expect(before(workers, pages)).toBe(true)
    expect(before(pages, projects)).toBe(true)
    expect(before(projects, system)).toBe(true)
    // On More the three choices read as words, full width, at touch size.
    expect(within(dark).getByText("Dark")).not.toHaveClass("hidden")
    expect(dark).toHaveClass("flex-1", "h-11")
    await user.click(dark)
    expect(localStorage.getItem("star-theme")).toBe("dark")
  })
})
