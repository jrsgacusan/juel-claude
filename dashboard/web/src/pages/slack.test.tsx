import { act, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { afterEach, describe, expect, it, vi } from "vitest"
import { server } from "@/mocks/node"
import { getDb, mockEvents, setScenario } from "@/mocks/state"
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
const MARCO =
  "Yes, it's mine (SPH-12). I'll share the new copy here before it ships."
const setWidth = (value: number) =>
  Object.defineProperty(window, "innerWidth", { configurable: true, writable: true, value })
const phone = () => {
  setWidth(390)
  return vi.spyOn(window, "scrollTo").mockImplementation(() => {})
}
afterEach(() => setWidth(1024))

describe("Slack replies", () => {
  it("shows the watcher's status, the routed and unrouted messages and the first draft", async () => {
    renderApp("/sphere-app/slack")
    expect(
      await screen.findByText("Watching Slack with Haiku. Checked 2 min ago.")
    ).toBeInTheDocument()
    expect(screen.getByText("For sphere-app")).toBeInTheDocument()
    expect(screen.getByText("Unrouted")).toBeInTheDocument()
    const list = await screen.findByRole("region", { name: "Messages" })
    expect(within(list).getAllByRole("button")).toHaveLength(5)
    expect(within(list).getAllByRole("button")[0]).toHaveAttribute(
      "aria-current",
      "true"
    )
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

    const list = await screen.findByRole("region", { name: "Messages" })
    await user.click(
      within(list).getByText("which PR fixes the invoice time zone?")
    )
    await user.click(await screen.findByRole("button", { name: "Shorter" }))
    expect(screen.getByLabelText("Ask STAR to rewrite it")).toHaveValue(
      "shorter"
    )
    await user.click(screen.getByRole("button", { name: /^Rewrite$/ }))
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
    const list = await screen.findByRole("region", { name: "Messages" })
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
    expect(await screen.findByLabelText("Your reply")).toHaveValue(MARCO)
  })

  it("opens the draft a search result names", async () => {
    const path =
      getDb().slack.routed.find((m) => m.from === "Lea")?.draftPath ?? ""
    renderApp(
      `/sphere-app/slack?draft=${encodeURIComponent(path.split("/").pop() ?? "")}`
    )
    expect(await screen.findByLabelText("Your reply")).toHaveValue(
      "None yet. It's SPH-13, being built now. I'll post the PR here once it's open."
    )
  })

  it("falls back to the first message when ?draft= names none", async () => {
    renderApp("/sphere-app/slack?draft=gone.md")
    expect(await screen.findByLabelText("Your reply")).toHaveValue(RIA)
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

  it("does not send before the draft has loaded, or when it failed to load", async () => {
    server.use(
      http.get("*/api/projects/:p/file", () =>
        HttpResponse.json({ error: "drafts/ unreadable" }, { status: 502 })
      )
    )
    renderApp("/sphere-app/slack")
    const reply = await screen.findByRole("region", { name: "Reply" })
    expect(
      await within(reply).findByText(
        /Couldn't load the draft: drafts\/ unreadable/
      )
    ).toBeInTheDocument()
    expect(
      within(reply).getByRole("button", { name: "Send reply" })
    ).toBeDisabled()
    expect(within(reply).getByRole("button", { name: "Skip" })).toBeDisabled()
    expect(
      within(reply).getByRole("button", { name: "Try again" })
    ).toBeInTheDocument()
  })

  it("follows STAR's rewritten draft after an earlier edit was saved", async () => {
    const { user } = renderApp("/sphere-app/slack")
    const box = await screen.findByLabelText("Your reply")
    await waitFor(() => expect(box).toHaveValue(RIA))
    await user.clear(box)
    await user.type(box, "My own words.")
    await user.tab()
    await waitFor(() =>
      expect(draftFile("Ria").endsWith("My own words.")).toBe(true)
    )
    const path =
      getDb().slack.routed.find((m) => m.from === "Ria")?.draftPath ?? ""
    const file = getDb().files[`sphere-app/${path}`]
    if (file) file.body = `${file.body.split("\n")[0]}\nSTAR's shorter rewrite.`
    act(() =>
      mockEvents.emit({ type: "change", project: "sphere-app", what: "drafts" })
    )
    await waitFor(() => expect(box).toHaveValue("STAR's shorter rewrite."))
  })

  it("a chip fills the rewrite box, and Rewrite sends it", async () => {
    const { user } = renderApp("/sphere-app/slack")
    await user.click(await screen.findByRole("button", { name: "Shorter" }))
    expect(screen.getByLabelText("Ask STAR to rewrite it")).toHaveValue(
      "shorter"
    )
    expect(loopAnswer("N-45")).toBe("")
    await user.click(screen.getByRole("button", { name: /^Rewrite$/ }))
    await waitFor(() => expect(loopAnswer("N-45")).toBe("rewrite: shorter"))
    expect(screen.getByLabelText("Ask STAR to rewrite it")).toHaveValue("")
  })

  it("routes a message as not for STAR", async () => {
    const { user } = renderApp("/sphere-app/slack")
    const list = await screen.findByRole("region", { name: "Messages" })
    await user.click(
      await within(list).findByText("who owns the staging deploy this week?")
    )
    await user.click(screen.getByRole("combobox", { name: "Project" }))
    await user.click(
      await screen.findByRole("option", { name: "Not for STAR" })
    )
    await user.click(screen.getByRole("button", { name: "Route it" }))
    expect(
      await screen.findByText("Dropped. STAR will not see it.")
    ).toBeInTheDocument()
    expect(getDb().slack.routed.some((m) => m.from === "Sam")).toBe(false)
  })

  it("shows the conflict banner and no Sent toast on a 409", async () => {
    setScenario("conflict")
    const { user } = renderApp("/sphere-app/slack")
    const box = await screen.findByLabelText("Your reply")
    await waitFor(() => expect(box).toHaveValue(RIA))
    await user.click(screen.getByRole("button", { name: "Send reply" }))
    expect(
      await screen.findByText(
        "open-loops.md has conflict markers. Resolve them, then answer here."
      )
    ).toBeInTheDocument()
    expect(
      within(screen.getByRole("region", { name: "Reply" })).queryByText(
        /^Sent\. STAR posts it/
      )
    ).not.toBeInTheDocument()
  })

  it("says the reply is queued when STAR is not reached", async () => {
    server.use(
      http.post("*/api/projects/:p/loops/:id/answer", () =>
        HttpResponse.json({ recorded: true, nudged: false })
      )
    )
    const { user } = renderApp("/sphere-app/slack")
    const box = await screen.findByLabelText("Your reply")
    await waitFor(() => expect(box).toHaveValue(RIA))
    await user.click(screen.getByRole("button", { name: "Send reply" }))
    expect(
      await screen.findByText(
        "Queued. STAR posts it to #sphere-eng as you when it next runs."
      )
    ).toBeInTheDocument()
  })

  it("on a phone, the messages show first, one opens on its own, and Back returns", async () => {
    phone()
    const { user, router } = renderApp("/sphere-app/slack")
    const list = await screen.findByRole("region", { name: "Messages" })
    expect(screen.queryByRole("region", { name: "Reply" })).not.toBeInTheDocument()
    await user.click(within(list).getByText("which PR fixes the invoice time zone?"))
    const reply = await screen.findByRole("region", { name: "Reply" })
    const lea = getDb().slack.routed.find((m) => m.from === "Lea")?.id ?? ""
    expect(router.state.location.search).toBe(`?${new URLSearchParams({ message: lea })}`)
    expect(router.state.historyAction).toBe("PUSH")
    expect(screen.queryByRole("region", { name: "Messages" })).not.toBeInTheDocument()
    await user.click(within(reply).getByRole("button", { name: "Back to Slack replies" }))
    expect(await screen.findByRole("region", { name: "Messages" })).toBeInTheDocument()
    expect(router.state.location.search).toBe("")
  })

  it("on a phone, a loop sent from Needs you opens its message, and Back stays on the page", async () => {
    phone()
    const { user, router } = renderApp("/sphere-app/slack?loop=N-47")
    expect(await screen.findByLabelText("Your reply")).toHaveValue(MARCO)
    await user.click(screen.getByRole("button", { name: "Back to Slack replies" }))
    expect(await screen.findByRole("region", { name: "Messages" })).toBeInTheDocument()
    expect(router.state.historyAction).toBe("REPLACE")
    expect(router.state.location.search).toBe("")
  })

  it("on a phone, an empty page says so with no Back, and the not-connected banner shows over the list", async () => {
    phone()
    setScenario("empty")
    const first = renderApp("/sphere-app/slack")
    expect(await screen.findByText("No Slack replies waiting.")).toBeInTheDocument()
    expect(screen.queryByRole("button", { name: "Back to Slack replies" })).not.toBeInTheDocument()
    first.unmount()
    setScenario("slack-off")
    renderApp("/sphere-app/slack")
    expect(await screen.findByText("Slack isn't connected")).toBeInTheDocument()
    expect(screen.getByRole("region", { name: "Messages" })).toBeInTheDocument()
  })

  it("a thread line keeps its bullets and its links", async () => {
    renderApp("/sphere-app/slack?loop=N-48")
    const reply = await screen.findByRole("region", { name: "Reply" })
    expect(await within(reply).findByRole("link", { name: "https://github.com/example/sphere-app/pull/207" })).toHaveAttribute("target", "_blank")
    expect(within(reply).getByRole("link", { name: "release notes" })).toHaveAttribute("href", "https://example.com/notes/invoice-rounding")
  })

  it("the reply box is 16 px on a phone and the actions are 44 px on touch", async () => {
    renderApp("/sphere-app/slack")
    const box = await screen.findByLabelText("Your reply")
    expect(box).toHaveClass("text-base", "md:text-sm")
    expect(box).not.toHaveClass("text-[15px]")
    for (const name of ["Skip", "Send reply", "Rewrite", "Shorter", "Add the PR link", "Less formal"])
      expect(screen.getByRole("button", { name })).toHaveClass("pointer-coarse:h-11")
  })
})
