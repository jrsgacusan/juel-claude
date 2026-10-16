import { screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { afterEach, describe, expect, it, vi } from "vitest"
import { server } from "@/mocks/node"
import { getDb } from "@/mocks/state"
import { renderApp } from "@/test/render"

const checkSwitch = () => screen.findByRole("switch", { name: "Check Slack" })
const capturePuts = () => {
  const bodies: unknown[] = []
  server.use(
    http.put("*/api/slack/paused", async ({ request }) => {
      const body = (await request.clone().json()) as { paused: boolean }
      bodies.push(body)
      getDb().slack.paused = body.paused
      return HttpResponse.json({ paused: body.paused })
    })
  )
  return bodies
}
const setWidth = (value: number) =>
  Object.defineProperty(window, "innerWidth", { configurable: true, writable: true, value })
afterEach(() => setWidth(1024))

describe("the Check Slack switch", () => {
  it("is on by default, with its note under the label", async () => {
    renderApp("/sphere-app/slack")
    const sw = await checkSwitch()
    expect(sw).toHaveAttribute("aria-checked", "true")
    expect(sw).toHaveAccessibleDescription("Checks Slack every few minutes")
  })

  it("turns off by sending paused: true, then reads Paused in the wait colour, and back on", async () => {
    const bodies = capturePuts()
    const { user } = renderApp("/sphere-app/slack")
    await user.click(await checkSwitch())
    await waitFor(() => expect(screen.getByRole("switch", { name: "Check Slack" })).toHaveAttribute("aria-checked", "false"))
    expect(bodies).toEqual([{ paused: true }])
    expect(screen.getByRole("switch", { name: "Check Slack" })).toHaveAccessibleDescription("Paused")
    expect(
      await screen.findByText("Paused. Slack is not checked until you turn it back on.")
    ).toHaveClass("text-wait-fg")
    await user.click(screen.getByRole("switch", { name: "Check Slack" }))
    expect(await screen.findByText("Watching Slack with Haiku. Checked 2 min ago.")).toBeInTheDocument()
    expect(bodies).toEqual([{ paused: true }, { paused: false }])
    expect(screen.getByRole("switch", { name: "Check Slack" })).toHaveAttribute("aria-checked", "true")
  })

  it.each([400, 500])("shows a %i from the server in the stop colour and keeps what the server holds", async (status) => {
    server.use(http.put("*/api/slack/paused", () => HttpResponse.json({ error: "no way" }, { status })))
    const { user } = renderApp("/sphere-app/slack")
    await user.click(await checkSwitch())
    const note = await screen.findByText("Couldn't change it: no way")
    expect(note).toHaveClass("text-stop-fg")
    expect(screen.getByRole("switch", { name: "Check Slack" })).toHaveAttribute("aria-checked", "true")
  })

  it("is a row at least 44 px tall on touch, and shows in the list at phone width", async () => {
    setWidth(390)
    vi.spyOn(window, "scrollTo").mockImplementation(() => {})
    renderApp("/sphere-app/slack")
    const sw = await checkSwitch()
    const list = screen.getByRole("region", { name: "Messages" })
    expect(within(list).getByRole("switch", { name: "Check Slack" })).toBe(sw)
    expect(sw.closest("label")).toHaveClass("min-h-11")
  })
})
