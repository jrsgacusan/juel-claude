// @ts-expect-error Node typings are only enabled for the tooling project, not the browser app.
import { readFileSync } from "node:fs"
// @ts-expect-error Node typings are only enabled for the tooling project, not the browser app.
import { resolve } from "node:path"
import { act, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { afterEach, describe, expect, it, vi } from "vitest"
import { setConnection } from "@/api/events"
import type { Project } from "@/api/types"
import { setDetailOpen } from "@/lib/chrome"
import { server } from "@/mocks/node"
import { mockColorScheme, renderApp } from "@/test/render"

const STOPPED =
  "STAR is stopped for juel-claude. Start it with /juel:star in that project. Your answers wait in its queue."

describe("the app shell", () => {
  it("sends / to the combined Needs you", async () => {
    const { router } = renderApp("/")
    await waitFor(() => expect(router.state.location.pathname).toBe("/needs"))
  })

  it("redirects a project root to its Progress", async () => {
    const { router } = renderApp("/sphere-app")
    await waitFor(() =>
      expect(router.state.location.pathname).toBe("/sphere-app/progress"),
    )
  })

  it("redirects a project's Needs page to the combined one, filtered to it", async () => {
    const { router } = renderApp("/sphere-app/needs?loop=N-41")
    await waitFor(() =>
      expect(router.state.location.pathname).toBe("/needs"),
    )
    expect(router.state.location.search).toBe("?project=sphere-app&loop=N-41")
  })

  it("shows Needs you above the project's pages, with the total, and a count per project", async () => {
    renderApp("/sphere-app/progress")
    const needs = await screen.findByRole("list", { name: "Needs you" })
    expect(within(needs).getByRole("link", { name: /Needs you/ })).toHaveAttribute(
      "href",
      "/needs"
    )
    expect(await within(needs).findByText("10")).toHaveAttribute("data-variant", "count")
    const sections = screen.getByRole("list", { name: "Sections" })
    expect(within(sections).queryByText("Needs you")).not.toBeInTheDocument()
    expect(
      needs.compareDocumentPosition(sections) & Node.DOCUMENT_POSITION_FOLLOWING
    ).toBeTruthy()
    const projects = screen.getByRole("list", { name: "Projects" })
    expect(await within(projects).findByLabelText("9 need you")).toBeInTheDocument()
    expect(within(projects).getByLabelText("1 need you")).toBeInTheDocument()
    expect(within(projects).queryByLabelText("0 need you")).not.toBeInTheDocument()
  })

  it("on the combined page the sidebar says All projects, and keeps the last project's pages", async () => {
    const { router } = renderApp("/sphere-app/progress")
    await screen.findByRole("list", { name: "Sections" })
    await act(() => router.navigate("/needs"))
    expect((await screen.findAllByText("All projects")).length).toBeGreaterThan(0)
    const sections = await screen.findByRole("list", { name: "Sections" })
    expect(screen.getByRole("heading", { name: "sphere-app" })).toBeInTheDocument()
    expect(within(sections).getAllByRole("link").map((link) => link.textContent)).toEqual([
      "Progress",
      "Chat",
      "Slack replies",
      "Briefing",
      "Evidence",
    ])
    expect(within(sections).getByRole("link", { name: "Progress" })).toHaveAttribute("href", "/sphere-app/progress")
    for (const link of within(sections).getAllByRole("link")) expect(link).not.toHaveAttribute("aria-current")
    expect(await screen.findByRole("list", { name: "Projects" })).toBeInTheDocument()
  })

  it("on the combined page with no last project the sidebar uses the first project's pages", async () => {
    renderApp("/needs")
    expect(await screen.findByRole("heading", { name: "sphere-app" })).toBeInTheDocument()
    expect(within(await screen.findByRole("list", { name: "Sections" })).getByRole("link", { name: "Chat" })).toHaveAttribute(
      "href",
      "/sphere-app/chat",
    )
  })

  it("uses the first listed project when none are running", async () => {
    server.use(
      http.get(
        "*/api/projects",
        () =>
          HttpResponse.json([
            { name: "first", repo: "/first", state: "stopped", terminal: null, lastTick: null, needsYou: 0 },
            { name: "second", repo: "/second", state: "idle", terminal: null, lastTick: null, needsYou: 0 },
          ]),
      ),
    )
    const { router } = renderApp("/")
    await waitFor(() => expect(router.state.location.pathname).toBe("/needs"))
  })

  it("lists every project with its state, and switches project on the same page", async () => {
    const { user, router } = renderApp("/sphere-app/progress")
    const projects = await screen.findByRole("list", { name: "Projects" })
    expect(within(projects).getByText("Running")).toHaveClass("sr-only")
    expect(within(projects).getByText("Idle")).not.toHaveClass("sr-only")
    expect(within(projects).getByText("Stopped")).not.toHaveClass("sr-only")
    await user.click(within(projects).getByText("juel-claude"))
    await waitFor(() =>
      expect(router.state.location.pathname).toBe("/juel-claude/progress")
    )
    expect(await screen.findByText(STOPPED)).toBeInTheDocument()
  })

  it("shows the breadcrumb and the Needs you count", async () => {
    renderApp("/sphere-app/progress")
    const crumbs = await screen.findByRole("navigation", {
      name: /breadcrumb/i,
    })
    expect(within(crumbs).getByText("sphere-app")).toBeInTheDocument()
    expect(within(crumbs).getByText("Progress")).toBeInTheDocument()
    const needs = screen.getByRole("list", { name: "Needs you" })
    expect(await within(needs).findByText("10")).toBeInTheDocument()
  })

  it("keeps the theme in localStorage from the theme menu, and System follows the OS", async () => {
    const os = mockColorScheme(false)
    const { user } = renderApp("/sphere-app/progress")
    await user.click(await screen.findByRole("button", { name: "Theme: System" }))
    expect(screen.getAllByRole("menuitemradio").map((r) => r.textContent)).toEqual(["System", "Light", "Dark"])
    await user.click(screen.getByRole("menuitemradio", { name: "Dark" }))
    expect(document.documentElement).toHaveClass("dark")
    expect(localStorage.getItem("star-theme")).toBe("dark")
    expect(screen.getByRole("button", { name: "Theme: Dark" })).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: "Theme: Dark" }))
    await user.click(screen.getByRole("menuitemradio", { name: "Light" }))
    expect(document.documentElement).toHaveClass("light")
    await user.click(screen.getByRole("button", { name: "Theme: Light" }))
    await user.click(screen.getByRole("menuitemradio", { name: "System" }))
    expect(localStorage.getItem("star-theme")).toBe("system")
    expect(document.documentElement).toHaveClass("light")
    act(() => os.set(true))
    expect(document.documentElement).toHaveClass("dark")
  })

  it("marks the selected theme in the menu", async () => {
    mockColorScheme(false)
    const { user } = renderApp("/sphere-app/progress")
    await user.click(await screen.findByRole("button", { name: "Theme: System" }))
    await user.click(screen.getByRole("menuitemradio", { name: "Dark" }))
    await user.click(screen.getByRole("button", { name: "Theme: Dark" }))
    expect(screen.getByRole("menuitemradio", { name: "Dark" })).toHaveAttribute("aria-checked", "true")
    expect(screen.getByRole("menuitemradio", { name: "Light" })).toHaveAttribute("aria-checked", "false")
  })

  it("opens search with Ctrl+K and ⌘K from any page", async () => {
    const { user, router } = renderApp("/sphere-app/progress")
    await screen.findByRole("list", { name: "Projects" })
    await user.keyboard("{Control>}k{/Control}")
    expect(
      await screen.findByPlaceholderText(
        "Search items, decisions, Slack, briefings and evidence"
      )
    ).toBeInTheDocument()
    await user.keyboard("{Escape}")
    await act(() => router.navigate("/sphere-app/evidence"))
    await user.keyboard("{Meta>}k{/Meta}")
    expect(
      await screen.findByPlaceholderText(
        "Search items, decisions, Slack, briefings and evidence"
      )
    ).toBeInTheDocument()
  })

  it("shows the lost-connection banner while the stream is down", async () => {
    renderApp("/sphere-app/progress")
    await screen.findByRole("list", { name: "Projects" })
    act(() => setConnection("lost"))
    expect(
      screen.getByText("Lost the connection to the dashboard server")
    ).toBeInTheDocument()
    act(() => setConnection("open"))
    expect(
      screen.queryByText("Lost the connection to the dashboard server")
    ).not.toBeInTheDocument()
  })

  it("shows the refused-token banner and does not promise a reconnect", async () => {
    renderApp("/sphere-app/progress")
    await screen.findByRole("list", { name: "Projects" })
    act(() => setConnection("refused"))
    expect(
      screen.getAllByText(/^The dashboard server refused the token\./).length
    ).toBeGreaterThan(0)
    expect(
      screen.queryByText("Lost the connection to the dashboard server")
    ).not.toBeInTheDocument()
  })

  it("a 401 says the token was refused", async () => {
    sessionStorage.clear()
    renderApp("/sphere-app/progress")
    expect(
      (await screen.findAllByText(/refused the token/)).length
    ).toBeGreaterThan(0)
  })

  it("says so when there are no projects, or no such project", async () => {
    server.use(http.get("*/api/projects", () => HttpResponse.json([])))
    renderApp("/")
    expect(
      await screen.findByText("No STAR projects on this Mac yet.")
    ).toBeInTheDocument()
  })

  it("names a project that is not on this Mac", async () => {
    renderApp("/nope/progress")
    expect(
      await screen.findByText("No project named nope on this Mac.")
    ).toBeInTheDocument()
  })

  it("a project name that needs encoding works", async () => {
    const odd: Project = {
      name: "a#b c",
      repo: "/r",
      state: "stopped",
      terminal: null,
      lastTick: null,
      needsYou: 0,
    }
    server.use(http.get("*/api/projects", () => HttpResponse.json([odd])))
    renderApp("/a%23b%20c/progress")
    const projects = await screen.findByRole("list", { name: "Projects" })
    expect(within(projects).getByRole("link", { name: /a#b c/ })).toHaveAttribute(
      "href",
      "/a%23b%20c/progress",
    )
    expect(
      await screen.findByText(
        "STAR is stopped for a#b c. Start it with /juel:star in that project. Your answers wait in its queue."
      )
    ).toBeInTheDocument()
  })

  it("answers an unknown path with a way back", async () => {
    renderApp("/sphere-app/nowhere/deeper")
    expect(await screen.findByText(/There is no page at/)).toBeInTheDocument()
    expect(
      screen.getByRole("link", { name: "Go to the dashboard" })
    ).toHaveAttribute("href", "/")
  })

  it("shows a page crash inside the shell", async () => {
    server.use(
      http.get("*/api/loops", () =>
        HttpResponse.json([
          {
            id: "N-1",
            kind: "person",
            project: "sphere-app",
            item: "x",
            title: "t",
            body: null,
            options: [],
            suggestion: null,
            answer: "",
            askedAt: null,
          },
        ])
      )
    )
    vi.spyOn(console, "error").mockImplementation(() => {})
    renderApp("/needs")
    expect(
      await screen.findByText(/This page hit an error/)
    ).toBeInTheDocument()
    expect(screen.getByRole("list", { name: "Projects" })).toBeInTheDocument()
  })
  it("shows the Workers card's squares in the sidebar, without STAR's next note", async () => {
    renderApp("/sphere-app/progress")
    expect(await screen.findByRole("meter", { name: "Building" })).toHaveAttribute("aria-valuetext", "3 of 3 busy")
    expect(screen.getByText("5 busy")).toBeInTheDocument()
    expect(screen.queryByText("Next tick in 3 min")).not.toBeInTheDocument()
    expect(screen.queryByRole("progressbar")).not.toBeInTheDocument()
  })
  it("lists Chat between Progress and Slack replies", async () => {
    renderApp("/sphere-app/chat")
    const sections = await screen.findByRole("list", { name: "Sections" })
    expect(within(sections).getAllByRole("link").map((link) => link.textContent))
      .toEqual(["Progress", "Chat", "Slack replies", "Briefing", "Evidence"])
    const chat = within(sections).getByRole("link", { name: "Chat" })
    expect(chat).toHaveAttribute("href", "/sphere-app/chat")
    expect(chat).toHaveAttribute("aria-current", "page")
  })

  it("lets the page draw under the notch, so the safe-area insets apply", () => {
    const dir = (import.meta as ImportMeta & { dirname: string }).dirname
    const html = readFileSync(resolve(dir, "../../index.html"), "utf8")
    expect(html).toMatch(/<meta name="viewport" content="width=device-width, initial-scale=1\.0, viewport-fit=cover" \/>/)
  })

  it("keeps the header on screen on a phone, below the safe area", async () => {
    const { container } = renderApp("/sphere-app/progress")
    await screen.findByRole("list", { name: "Projects" })
    expect(container.querySelector("header"))
      .toHaveClass("sticky", "top-0", "z-20", "box-content", "bg-background", "pt-[env(safe-area-inset-top)]", "md:static")
    expect(container.querySelector("[data-slot=sidebar-inset]")).toHaveClass("overflow-x-clip")
    const search = screen.getByRole("button", { name: "Search (⌘K)" })
    expect(within(search).getByText("Search")).toHaveClass("hidden", "sm:inline")
  })
})

const setWidth = (value: number) =>
  Object.defineProperty(window, "innerWidth", { configurable: true, writable: true, value })
const phone = () => setWidth(390)

describe("the phone shell", () => {
  afterEach(() => setWidth(1024))

  it("has a Pages nav with four links and no menu button, breadcrumb or theme control", async () => {
    phone()
    renderApp("/sphere-app/progress")
    const nav = await screen.findByRole("navigation", { name: "Pages" })
    const links = within(nav).getAllByRole("link")
    expect(links.map((l) => l.getAttribute("href"))).toEqual([
      "/needs",
      "/sphere-app/progress",
      "/sphere-app/chat",
      "/sphere-app/more",
    ])
    for (const link of links) expect(link).toHaveClass("min-h-11")
    expect(within(links[0]!).getByText("Needs you")).toBeInTheDocument()
    const badge = await within(links[0]!).findByText("10")
    expect(badge).toHaveAttribute("data-variant", "count")
    expect(nav.querySelector("[role=tab]")).toBeNull()
    expect(screen.queryByRole("button", { name: "Open the menu" })).not.toBeInTheDocument()
    expect(screen.queryByRole("navigation", { name: /breadcrumb/i })).not.toBeInTheDocument()
    expect(screen.queryByRole("button", { name: /^Theme/ })).not.toBeInTheDocument()
    expect(screen.queryByLabelText("Dark theme")).not.toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Search (⌘K)" })).toBeInTheDocument()
  })

  it("marks the current page", async () => {
    phone()
    renderApp("/sphere-app/progress")
    const nav = await screen.findByRole("navigation", { name: "Pages" })
    expect(within(nav).getByRole("link", { name: "Progress" })).toHaveAttribute("aria-current", "page")
    expect(within(nav).getByRole("link", { name: "Chat" })).not.toHaveAttribute("aria-current")
  })

  it("on /needs points Progress at the last project, else the first", async () => {
    phone()
    const { router } = renderApp("/needs")
    let nav = await screen.findByRole("navigation", { name: "Pages" })
    await waitFor(() =>
      expect(within(nav).getByRole("link", { name: "Progress" })).toHaveAttribute("href", "/sphere-app/progress"),
    )
    await act(() => router.navigate("/sphere-api/chat"))
    await act(() => router.navigate("/needs"))
    nav = await screen.findByRole("navigation", { name: "Pages" })
    expect(within(nav).getByRole("link", { name: "Progress" })).toHaveAttribute("href", "/sphere-api/progress")
  })

  it("hides the tab bar while a list-detail page shows its detail", async () => {
    phone()
    renderApp("/sphere-app/progress")
    await screen.findByRole("navigation", { name: "Pages" })
    act(() => setDetailOpen(true))
    expect(screen.queryByRole("navigation", { name: "Pages" })).not.toBeInTheDocument()
  })

  it("shows the project switcher, and switching goes to that project's Progress", async () => {
    phone()
    const { user, router } = renderApp("/sphere-app/progress")
    const button = await screen.findByRole("button", { name: "Switch project, now sphere-app" })
    expect(within(button).getByText("sphere-app")).toHaveClass("truncate")
    expect(await within(button).findByText("STAR running")).toBeInTheDocument()
    await user.click(button)
    const dialog = await screen.findByRole("dialog")
    expect(within(dialog).getByRole("link", { name: /All projects/ })).toBeInTheDocument()
    expect(within(dialog).getByRole("link", { name: /sphere-app/ })).toHaveTextContent("9")
    // A project row's count is the pale wait tone; solid amber is for the total and for answering.
    expect(within(dialog).getByLabelText("9 need you")).toHaveAttribute("data-variant", "wait")
    expect(within(within(dialog).getByRole("link", { name: /All projects/ })).getByText("10")).toHaveAttribute("data-variant", "count")
    await user.click(within(dialog).getByRole("link", { name: /sphere-api/ }))
    await waitFor(() => expect(router.state.location.pathname).toBe("/sphere-api/progress"))
    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument())
  })

  it("shows All projects in the switcher on the combined page", async () => {
    phone()
    renderApp("/needs")
    expect(await screen.findByRole("button", { name: "Switch project, now All projects" })).toBeInTheDocument()
  })

  it("keeps the desktop on the sidebar and breadcrumb", async () => {
    renderApp("/sphere-app/progress")
    await screen.findByRole("list", { name: "Projects" })
    expect(screen.queryByRole("navigation", { name: "Pages" })).not.toBeInTheDocument()
    expect(screen.getByRole("navigation", { name: /breadcrumb/i })).toBeInTheDocument()
  })
})
