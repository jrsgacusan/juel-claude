import { act, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it, vi } from "vitest"
import { setConnection } from "@/api/events"
import type { Project } from "@/api/types"
import { server } from "@/mocks/node"
import { mockColorScheme, renderApp } from "@/test/render"

const STOPPED =
  "STAR is stopped for juel-claude. Start it with /juel:star in that project. Your answers wait in its queue."

describe("the app shell", () => {
  it("sends / to the first running project's Needs you", async () => {
    const { router } = renderApp("/")
    await waitFor(() =>
      expect(router.state.location.pathname).toBe("/sphere-app/needs")
    )
  })

  it("redirects a project root to Needs you", async () => {
    const { router } = renderApp("/sphere-app")
    await waitFor(() =>
      expect(router.state.location.pathname).toBe("/sphere-app/needs"),
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
    await waitFor(() => expect(router.state.location.pathname).toBe("/first/needs"))
  })

  it("lists every project with its state, and switches project on the same page", async () => {
    const { user, router } = renderApp("/sphere-app/progress")
    const projects = await screen.findByRole("list", { name: "Projects" })
    expect(within(projects).getByText("Running")).toBeInTheDocument()
    expect(within(projects).getByText("Idle")).toBeInTheDocument()
    expect(within(projects).getByText("Stopped")).toBeInTheDocument()
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
    const sections = screen.getByRole("list", { name: "Sections" })
    expect(await within(sections).findByText("9")).toBeInTheDocument()
  })

  it("keeps the theme in localStorage, and System follows the OS", async () => {
    const os = mockColorScheme(false)
    const { user } = renderApp("/sphere-app/needs")
    await user.click(await screen.findByLabelText("Dark theme"))
    expect(document.documentElement).toHaveClass("dark")
    expect(localStorage.getItem("star-theme")).toBe("dark")
    await user.click(screen.getByLabelText("Light theme"))
    expect(document.documentElement).toHaveClass("light")
    await user.click(screen.getByLabelText("System theme"))
    expect(localStorage.getItem("star-theme")).toBe("system")
    expect(document.documentElement).toHaveClass("light")
    act(() => os.set(true))
    expect(document.documentElement).toHaveClass("dark")
  })

  it("marks the selected theme", async () => {
    mockColorScheme(false)
    const { user } = renderApp("/sphere-app/needs")
    const dark = await screen.findByLabelText("Dark theme")
    await user.click(dark)
    expect(dark).toHaveAttribute("aria-checked", "true")
    expect(dark.className).toMatch(/aria-checked:bg-accent/)
    expect(screen.getByLabelText("Light theme")).toHaveAttribute(
      "aria-checked",
      "false"
    )
  })

  it("opens search with Ctrl+K and ⌘K from any page", async () => {
    const { user, router } = renderApp("/sphere-app/needs")
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
    renderApp("/sphere-app/needs")
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
    renderApp("/sphere-app/needs")
    await screen.findByRole("list", { name: "Projects" })
    act(() => setConnection("refused"))
    expect(
      screen.getByText(
        "The dashboard server refused the token. Open the dashboard again with /juel:star dashboard."
      )
    ).toBeInTheDocument()
    expect(
      screen.queryByText("Lost the connection to the dashboard server")
    ).not.toBeInTheDocument()
  })

  it("a 401 says the token was refused", async () => {
    sessionStorage.clear()
    renderApp("/sphere-app/needs")
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
    renderApp("/nope/needs")
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
      http.get("*/api/projects/:p/loops", () =>
        HttpResponse.json([
          {
            id: "N-1",
            kind: "go-batch",
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
    renderApp("/sphere-app/needs")
    expect(
      await screen.findByText(/This page hit an error/)
    ).toBeInTheDocument()
    expect(screen.getByRole("list", { name: "Projects" })).toBeInTheDocument()
  })
  it("shows the Workers card's squares in the sidebar, without STAR's next note", async () => {
    renderApp("/sphere-app/needs")
    expect(await screen.findByRole("meter", { name: "Building" })).toHaveAttribute("aria-valuetext", "3 of 3 busy")
    expect(screen.getByText("5 busy")).toBeInTheDocument()
    expect(screen.queryByText("Next tick in 3 min")).not.toBeInTheDocument()
    expect(screen.queryByRole("progressbar")).not.toBeInTheDocument()
  })
  it("lists Chat between Progress and Slack replies", async () => {
    renderApp("/sphere-app/chat")
    const sections = await screen.findByRole("list", { name: "Sections" })
    expect(within(sections).getAllByRole("link").map((link) => link.textContent))
      .toEqual(["Needs you", "Progress", "Chat", "Slack replies", "Briefing", "Evidence"])
    const chat = within(sections).getByRole("link", { name: "Chat" })
    expect(chat).toHaveAttribute("href", "/sphere-app/chat")
    expect(chat).toHaveAttribute("aria-current", "page")
  })
})
