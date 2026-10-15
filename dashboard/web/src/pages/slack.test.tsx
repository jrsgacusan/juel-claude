import { screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it } from "vitest"
import { server } from "@/mocks/node"
import { getDb, setScenario } from "@/mocks/state"
import { renderApp } from "@/test/render"

const loopAnswer = (id: string) =>
  getDb().loops["sphere-app"]?.find((l) => l.id === id)?.answer
const draftFile = (from: string) => {
  const path =
    getDb().slack.routed.find((m) => m.from === from)?.draftPath ?? ""
  return getDb().files[`sphere-app/${path}`]?.body ?? ""
}
const RIA =
  "Not today. It's in final review now, and I expect it merged tomorrow morning, before the demo."

describe("Slack replies", () => {
  it("shows the watcher's status, the routed and unrouted messages and the first draft", async () => {
    renderApp("/sphere-app/slack")
    expect(
      await screen.findByText("Watching Slack with Haiku. Checked 2 min ago.")
    ).toBeInTheDocument()
    expect(screen.getByText("For sphere-app")).toBeInTheDocument()
    expect(screen.getByText("Unrouted")).toBeInTheDocument()
    const list = screen.getByRole("region", { name: "Messages" })
    expect(within(list).getAllByRole("button")).toHaveLength(5)
    expect(await screen.findByLabelText("Your reply")).toHaveValue(RIA)
    const reply = screen.getByRole("region", { name: "Reply" })
    expect(
      within(reply).getByText(
        "hey, is the CSV export landing today? sales wants to demo it tomorrow"
      )
    ).toBeInTheDocument()
  })

  it("names the workspace in the watcher line when the server knows it", async () => {
    getDb().slack.status.workspace = "Sphere Technology"
    renderApp("/sphere-app/slack")
    expect(
      await screen.findByText(
        "Watching Sphere Technology with Haiku. Checked 2 min ago."
      )
    ).toBeInTheDocument()
  })

  it("saves an edited draft on blur, then Send reply answers the loop with send", async () => {
    const { user } = renderApp("/sphere-app/slack")
    const box = await screen.findByLabelText("Your reply")
    await waitFor(() => expect(box).toHaveValue(RIA))
    await user.clear(box)
    await user.type(box, "Not today, tomorrow morning.")
    await user.tab()
    await waitFor(() =>
      expect(draftFile("Ria").split("\n").slice(1).join("\n")).toBe(
        "Not today, tomorrow morning."
      )
    )
    expect(draftFile("Ria").split("\n")[0]).toMatch(/^to: slack C0SPHERE /)
    await user.click(screen.getByRole("button", { name: "Send reply" }))
    expect(
      await screen.findByText("Sent. STAR posts it to #sphere-eng as you.")
    ).toBeInTheDocument()
    expect(loopAnswer("N-45")).toBe("send")
  })

  it("does not send when the draft could not be saved", async () => {
    server.use(
      http.put("*/api/projects/:p/drafts/:name", () =>
        HttpResponse.json({ error: "drafts/ is read-only" }, { status: 502 })
      )
    )
    const { user } = renderApp("/sphere-app/slack")
    const box = await screen.findByLabelText("Your reply")
    await waitFor(() => expect(box).toHaveValue(RIA))
    await user.type(box, " Thanks!")
    await user.click(screen.getByRole("button", { name: "Send reply" }))
    expect(
      await screen.findByText("Couldn't save the draft: drafts/ is read-only")
    ).toBeInTheDocument()
    expect(loopAnswer("N-45")).toBe("")
  })

  it("skips, and asks for a rewrite with a chip or in words", async () => {
    const { user } = renderApp("/sphere-app/slack")
    await user.click(await screen.findByRole("button", { name: "Skip" }))
    expect(
      await screen.findByText("Skipped. The watcher will not raise it again.")
    ).toBeInTheDocument()
    expect(loopAnswer("N-45")).toBe("skip")

    const list = screen.getByRole("region", { name: "Messages" })
    await user.click(
      within(list).getByText("which PR fixes the invoice time zone?")
    )
    await user.click(await screen.findByRole("button", { name: "Shorter" }))
    expect(
      await screen.findByText('STAR is rewriting it: "shorter".')
    ).toBeInTheDocument()
    expect(loopAnswer("N-48")).toBe("rewrite: shorter")

    await user.click(
      within(list).getByText(
        "can you look at the invite email copy before it goes out?"
      )
    )
    await user.click(await screen.findByRole("button", { name: /^Rewrite$/ }))
    expect(
      await screen.findByText("Tell STAR what to change first.")
    ).toBeInTheDocument()
    await user.type(
      screen.getByLabelText("Ask STAR to rewrite it"),
      "add the PR link"
    )
    await user.click(screen.getByRole("button", { name: /^Rewrite$/ }))
    await waitFor(() =>
      expect(loopAnswer("N-47")).toBe("rewrite: add the PR link")
    )
  })

  it("routes an unrouted message to a project", async () => {
    const { user } = renderApp("/sphere-app/slack")
    const list = screen.getByRole("region", { name: "Messages" })
    await user.click(
      await within(list).findByText("who owns the staging deploy this week?")
    )
    expect(
      await screen.findByText(
        "The watcher could not tell which project this is for"
      )
    ).toBeInTheDocument()
    await user.click(screen.getByRole("combobox", { name: "Project" }))
    await user.click(await screen.findByRole("option", { name: "sphere-api" }))
    await user.click(screen.getByRole("button", { name: "Route it" }))
    expect(
      await screen.findByText(
        "Routed. That STAR drafts a reply on its next tick."
      )
    ).toBeInTheDocument()
    expect(getDb().slack.unrouted.map((m) => m.from)).toEqual(["Ana"])
    expect(getDb().slack.routed.find((m) => m.from === "Sam")?.project).toBe(
      "sphere-api"
    )
  })

  it("opens the message of a loop sent from Needs you", async () => {
    renderApp("/sphere-app/slack?loop=N-47")
    expect(await screen.findByLabelText("Your reply")).toHaveValue(
      "Yes, it's mine (SPH-12). I'll share the new copy here before it ships."
    )
  })

  it("says when Slack isn't connected", async () => {
    setScenario("slack-off")
    renderApp("/sphere-app/slack")
    expect(await screen.findByText("Slack isn't connected")).toBeInTheDocument()
  })

  it("has loading, empty and error states", async () => {
    setScenario("loading")
    const first = renderApp("/sphere-app/slack")
    expect(await screen.findByTestId("page-loading")).toBeInTheDocument()
    first.unmount()
    setScenario("empty")
    const second = renderApp("/sphere-app/slack")
    expect(
      await screen.findByText("No Slack replies waiting.")
    ).toBeInTheDocument()
    second.unmount()
    setScenario("error")
    renderApp("/sphere-app/slack")
    expect(await screen.findByTestId("page-error")).toHaveTextContent(
      "Couldn't load the Slack replies."
    )
  })
})
