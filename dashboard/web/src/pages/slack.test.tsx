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
const LEA =
  "None yet. It's SPH-13, being built now. I'll post the PR here once it's open."
const MARCO =
  "Yes, it's mine (SPH-12). I'll share the new copy here before it ships."
const setWidth = (value: number) =>
  Object.defineProperty(window, "innerWidth", { configurable: true, writable: true, value })
const phone = () => {
  setWidth(390)
  return vi.spyOn(window, "scrollTo").mockImplementation(() => {})
}
afterEach(() => setWidth(1024))

const captureRedrafts = () => {
  const asked: unknown[] = []
  server.use(
    http.post("*/api/projects/:p/slack/redraft", async ({ request }) => {
      asked.push(await request.json())
      return HttpResponse.json({ queued: true })
    })
  )
  return asked
}

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

    const asked = captureRedrafts()
    const list = await screen.findByRole("region", { name: "Messages" })
    await user.click(
      within(list).getByText(
        "can you look at the invite email copy before it goes out?"
      )
    )
    await waitFor(() =>
      expect(screen.getByLabelText("Your reply")).toHaveValue(MARCO)
    )
    await user.click(screen.getByRole("button", { name: /^Rewrite$/ }))
    expect(await screen.findByText("Say what to change first.")).toBeInTheDocument()
    await user.type(
      screen.getByLabelText("Ask the drafter to rewrite it"),
      "add the PR link"
    )
    await user.click(screen.getByRole("button", { name: /^Rewrite$/ }))
    await waitFor(() =>
      expect(asked).toEqual([{ loop: "N-47", how: "add the PR link" }])
    )
    expect(loopAnswer("N-47")).toBe("")
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
        "Routed to sphere-api."
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

  it("saves an edit, then a chip and Rewrite ask the drafter, not STAR", async () => {
    const asked = captureRedrafts()
    const { user } = renderApp("/sphere-app/slack")
    const box = await screen.findByLabelText("Your reply")
    await waitFor(() => expect(box).toHaveValue(RIA))
    await user.type(box, " Thanks!")
    await user.click(screen.getByRole("button", { name: "Shorter" }))
    expect(screen.getByLabelText("Ask the drafter to rewrite it")).toHaveValue("shorter")
    await user.click(screen.getByRole("button", { name: /^Rewrite$/ }))
    const reply = screen.getByRole("region", { name: "Reply" })
    expect(await within(reply).findByText("Rewriting…")).toBeInTheDocument()
    expect(draftFile("Ria").endsWith(`${RIA} Thanks!`)).toBe(true)
    expect(asked).toEqual([{ loop: "N-45", how: "shorter" }])
    expect(loopAnswer("N-45")).toBe("")
    expect(screen.getByLabelText("Ask the drafter to rewrite it")).toHaveValue("")
    expect(box).toHaveAttribute("readonly")
    expect(within(reply).getByRole("button", { name: "Send reply" })).toBeDisabled()
    expect(within(reply).getByRole("button", { name: "Skip" })).toBeDisabled()
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

  it("on a phone with nothing waiting, the list still shows the watcher's status and its error", async () => {
    phone()
    server.use(
      http.get("*/api/slack", () =>
        HttpResponse.json({
          status: { connected: true, workspace: "Acme", model: "haiku", lastCheck: null, error: "rate limited" },
          routed: [],
          unrouted: [],
        })
      )
    )
    renderApp("/sphere-app/slack")
    expect(await screen.findByText(/rate limited/)).toBeVisible()
    expect(screen.getByText(/The last check failed: rate limited/)).toBeVisible()
    expect(screen.getByText(/Watching Acme/)).toBeVisible()
    expect(screen.getByText("No Slack replies waiting.")).toBeVisible()
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

  it("Rewriting… lasts through the gap and ends when STAR adds the item again", async () => {
    captureRedrafts()
    const { user, client } = renderApp("/sphere-app/slack")
    await waitFor(() => expect(screen.getByLabelText("Your reply")).toHaveValue(RIA))
    await user.type(screen.getByLabelText("Ask the drafter to rewrite it"), "shorter")
    await user.click(screen.getByRole("button", { name: /^Rewrite$/ }))
    expect(await screen.findByText("Rewriting…")).toBeInTheDocument()
    const db = getDb()
    const ria = db.slack.routed.find((m) => m.from === "Ria")!
    const loops = db.loops["sphere-app"]!
    const index = loops.findIndex((l) => l.id === "N-45")
    const file = db.files[`sphere-app/${ria.draftPath}`]!
    file.body = `${file.body.split("\n")[0]}\nNot today. Tomorrow morning, before the demo.`
    // The drafter answered "redrafted": the server drops the finished reply until STAR adds it again.
    loops.splice(index, 1, { ...loops[index]!, answer: "redrafted" })
    db.slack.routed = db.slack.routed.filter((m) => m !== ria)
    await act(() => client.invalidateQueries())
    await waitFor(() =>
      expect(screen.queryByText(/^hey, is the CSV export landing today\?/)).not.toBeInTheDocument()
    )
    const suggestion = 'Send: "Not today. Tomorrow morning, before the demo."'
    loops.splice(index, 1, { ...loops[index]!, id: "N-49", answer: "", suggestion })
    db.slack.routed.unshift({ ...ria, loopId: "N-49" })
    await act(() => client.invalidateQueries())
    await waitFor(() =>
      expect(screen.getByLabelText("Your reply")).toHaveValue("Not today. Tomorrow morning, before the demo.")
    )
    expect(screen.queryByText("Rewriting…")).not.toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Send reply" })).toBeEnabled()
  })

  it("says why when the drafter could not rewrite it", async () => {
    captureRedrafts()
    const { user, client } = renderApp("/sphere-app/slack")
    await waitFor(() => expect(screen.getByLabelText("Your reply")).toHaveValue(RIA))
    await user.click(screen.getByRole("button", { name: "Shorter" }))
    await user.click(screen.getByRole("button", { name: /^Rewrite$/ }))
    expect(await screen.findByText("Rewriting…")).toBeInTheDocument()
    const loops = getDb().loops["sphere-app"]!
    const index = loops.findIndex((l) => l.id === "N-45")
    const title = `${loops[index]!.title} (redraft failed: claude timed out after 10 min)`
    loops.splice(index, 1, { ...loops[index]!, id: "N-49", title })
    getDb().slack.routed.find((m) => m.from === "Ria")!.loopId = "N-49"
    await act(() => client.invalidateQueries())
    expect(await screen.findByText("Couldn't rewrite it: claude timed out after 10 min")).toBeInTheDocument()
    expect(screen.queryByText("Rewriting…")).not.toBeInTheDocument()
    expect(screen.getByLabelText("Your reply")).toHaveValue(RIA)
  })

  it("the mock drafter rewrites it, and a page opened from a loop stays on the message", async () => {
    const { user, router } = renderApp("/sphere-app/slack?loop=N-48")
    await waitFor(() => expect(screen.getByLabelText("Your reply")).toHaveValue(LEA))
    await user.click(screen.getByRole("button", { name: "Shorter" }))
    await user.click(screen.getByRole("button", { name: /^Rewrite$/ }))
    expect(await screen.findByText("Rewriting…")).toBeInTheDocument()
    const lea = getDb().slack.routed.find((m) => m.from === "Lea")?.id ?? ""
    expect(router.state.location.search).toBe(`?${new URLSearchParams({ message: lea })}`)
    await waitFor(
      () => expect(screen.getByLabelText("Your reply")).toHaveValue(`Rewritten (shorter): ${LEA}`),
      { timeout: 3000 }
    )
    expect(screen.queryByText("Rewriting…")).not.toBeInTheDocument()
    const next = getDb().loops["sphere-app"]?.find((l) => l.id === "N-49")
    expect(next?.suggestion).toBe(`Send: "Rewritten (shorter): ${LEA}"`)
  })

  it("a draft the drafter could not write says why, offers a rewrite, and has no Send", async () => {
    const asked = captureRedrafts()
    const marco = getDb().slack.routed.find((m) => m.from === "Marco")!
    const file = getDb().files[`sphere-app/${marco.draftPath}`]!
    file.body = file.body.split("\n")[0]!
    const loop = getDb().loops["sphere-app"]!.find((l) => l.id === "N-47")!
    loop.suggestion = "no draft: claude timed out after 10 min"
    loop.options = loop.options.filter((o) => o.answer !== "send")
    const { user } = renderApp("/sphere-app/slack?loop=N-47")
    const reply = await screen.findByRole("region", { name: "Reply" })
    expect(await within(reply).findByText("No draft yet: claude timed out after 10 min")).toBeInTheDocument()
    expect(within(reply).queryByLabelText("Your reply")).not.toBeInTheDocument()
    expect(within(reply).queryByRole("button", { name: "Send reply" })).not.toBeInTheDocument()
    expect(within(reply).queryByText("Drafted for you")).not.toBeInTheDocument()
    expect(within(reply).getByRole("button", { name: "Skip" })).toBeEnabled()
    await user.click(within(reply).getByRole("button", { name: "Shorter" }))
    await user.click(within(reply).getByRole("button", { name: /^Rewrite$/ }))
    await waitFor(() => expect(asked).toEqual([{ loop: "N-47", how: "shorter" }]))
  })

  it("says why when the server refuses the rewrite", async () => {
    server.use(
      http.post("*/api/projects/:p/slack/redraft", () =>
        HttpResponse.json({ error: "No open slack-reply item N-45" }, { status: 404 })
      )
    )
    const { user } = renderApp("/sphere-app/slack")
    await waitFor(() => expect(screen.getByLabelText("Your reply")).toHaveValue(RIA))
    await user.click(screen.getByRole("button", { name: "Shorter" }))
    await user.click(screen.getByRole("button", { name: /^Rewrite$/ }))
    expect(
      await screen.findByText("Couldn't ask for a rewrite: No open slack-reply item N-45")
    ).toBeInTheDocument()
    expect(screen.queryByText("Rewriting…")).not.toBeInTheDocument()
  })

  it("names the drafter, not STAR, as the writer of drafts", async () => {
    renderApp("/sphere-app/slack")
    expect(await screen.findByText("Drafted for you")).toBeInTheDocument()
    expect(screen.queryByText("Drafted by STAR")).not.toBeInTheDocument()
  })

  it("reads Paused in the wait colour, with the switch off, when the server holds a pause", async () => {
    getDb().slack.paused = true
    renderApp("/sphere-app/slack")
    expect(
      await screen.findByText("Paused. Slack is not checked until you turn it back on.")
    ).toHaveClass("text-wait-fg")
    expect(screen.getByRole("switch", { name: "Check Slack" })).toHaveAttribute("aria-checked", "false")
    expect(screen.queryByText(/^Watching/)).not.toBeInTheDocument()
  })
})
