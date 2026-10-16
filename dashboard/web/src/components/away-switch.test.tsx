import { screen, waitFor } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it } from "vitest"
import { server } from "@/mocks/node"
import { getDb } from "@/mocks/state"
import { renderApp } from "@/test/render"

const overviewOf = (p: string) => {
  const overview = getDb().overview[p]
  if (!overview) throw new Error(`no overview for ${p}`)
  return overview
}
const awaySwitch = () => screen.findByRole("switch", { name: "Away" })

describe("the away switch", () => {
  it("shows the state STAR recorded, and reads you're away in the wait colour", async () => {
    const first = renderApp("/sphere-app/needs")
    const sw = await awaySwitch()
    expect(sw).toHaveAttribute("aria-checked", "false")
    expect(sw).toHaveAccessibleDescription("STAR keeps going and saves a summary")
    expect(screen.getByText("STAR running")).toHaveClass("text-muted-foreground")
    first.unmount()
    overviewOf("sphere-app").away = "2026-10-17T01:00:00Z"
    renderApp("/sphere-app/needs")
    expect(await awaySwitch()).toHaveAttribute("aria-checked", "true")
    expect(screen.getByText("STAR running · you're away")).toHaveClass("text-wait-fg")
  })

  it("sends away, waits for STAR, then shows what STAR recorded", async () => {
    const bodies: unknown[] = []
    server.use(http.post("*/api/projects/:p/away", async ({ request }) => { bodies.push(await request.clone().json()) }))
    const { user } = renderApp("/sphere-app/needs")
    await user.click(await awaySwitch())
    expect(
      await screen.findByRole("switch", { name: "Away", description: "Waiting for STAR to mark you away" })
    ).toHaveAttribute("aria-checked", "true")
    expect(bodies).toEqual([{ away: true }])
    // STAR's change reaches the page by the event stream or, failing that, the 5 s poll while a change is pending,
    // so this does not depend on the mocked stream staying up across tests.
    expect(await screen.findByText("STAR running · you're away", undefined, { timeout: 8_000 })).toBeInTheDocument()
    expect(screen.getByRole("switch", { name: "Away" })).toHaveAccessibleDescription("STAR keeps going and saves a summary")
  }, 15_000)

  it("shows a change STAR has not applied yet, and none when it changes nothing", async () => {
    const overview = Object.assign(overviewOf("sphere-app"), { away: "2026-10-17T01:00:00Z", awayPending: "back" as const })
    const first = renderApp("/sphere-app/needs")
    const sw = await awaySwitch()
    expect(sw).toHaveAttribute("aria-checked", "false")
    expect(sw).toHaveAccessibleDescription("Waiting for STAR to mark you back")
    expect(screen.getByText("STAR running · you're away")).toBeInTheDocument()
    first.unmount()
    Object.assign(overview, { awayPending: "away" as const })
    renderApp("/sphere-app/needs")
    const again = await awaySwitch()
    expect(again).toHaveAttribute("aria-checked", "true")
    expect(again).toHaveAccessibleDescription("STAR keeps going and saves a summary")
  })

  it("says the change waits for STAR's next start when STAR is not running", async () => {
    const { user } = renderApp("/juel-claude/needs")
    const sw = await awaySwitch()
    expect(sw).toHaveAccessibleDescription("Waits for STAR's next start")
    await user.click(sw)
    await waitFor(() => expect(screen.getByRole("switch", { name: "Away" })).toHaveAttribute("aria-checked", "true"))
    expect(overviewOf("juel-claude").awayPending).toBe("away")
    expect(overviewOf("juel-claude").away).toBeNull()
    expect(screen.getByRole("switch", { name: "Away" })).toHaveAccessibleDescription("Waits for STAR's next start")
  })

  it("treats an idle STAR as one that hears the switch, since the nudge wakes it", async () => {
    const project = getDb().projects.find((p) => p.name === "sphere-app")
    if (!project) throw new Error("no sphere-app project")
    project.state = "idle"
    renderApp("/sphere-app/needs")
    await screen.findByRole("list", { name: "Projects" })
    await waitFor(() =>
      expect(screen.getByRole("switch", { name: "Away" })).toHaveAccessibleDescription("STAR keeps going and saves a summary")
    )
    expect(screen.queryByText("Waits for STAR's next start")).not.toBeInTheDocument()
  })

  it("says why when the dashboard could not record it", async () => {
    const why = "Could not write inbox/20261017T020000Z-control-ab12.md: read-only file system"
    server.use(http.post("*/api/projects/:p/away", () => HttpResponse.json({ error: why }, { status: 500 })))
    const { user } = renderApp("/sphere-app/needs")
    await user.click(await awaySwitch())
    expect(await screen.findByText(`Couldn't tell STAR: ${why}`)).toHaveClass("text-stop-fg")
    expect(screen.getByRole("switch", { name: "Away" })).toHaveAttribute("aria-checked", "false")
  })
})
