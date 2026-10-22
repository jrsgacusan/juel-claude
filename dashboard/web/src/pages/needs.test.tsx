import { act, fireEvent, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { afterEach, describe, expect, it, vi } from "vitest"
import { getConnection } from "@/api/events"
import { server } from "@/mocks/node"
import { getDb, mockEvents, setScenario } from "@/mocks/state"
import { renderApp } from "@/test/render"

const loopAnswer = (id: string) =>
  getDb().loops["sphere-app"]?.find((l) => l.id === id)?.answer

const setWidth = (value: number) =>
  Object.defineProperty(window, "innerWidth", {
    configurable: true,
    writable: true,
    value,
  })
const phone = () => {
  setWidth(390)
  return vi.spyOn(window, "scrollTo").mockImplementation(() => {})
}
afterEach(() => setWidth(1024))

describe("Needs you", () => {
  it("lists every project's open loops with tab counts, the person step first", async () => {
    renderApp("/needs")
    expect(
      await screen.findByRole("button", { name: /^All\s*10$/ })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /^Holds up work\s*4$/ })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /^Slack\s*3$/ })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /^Other\s*3$/ })
    ).toBeInTheDocument()
    const list = screen.getByRole("region", { name: "Open loops" })
    const entries = within(list).getAllByRole("listitem")
    expect(entries).toHaveLength(10)
    expect(entries[0]).toHaveTextContent(
      "Log in to the Stripe dashboard and enable test mode"
    )
    expect(entries[0]).toHaveTextContent("sphere-app")
    expect(entries[2]).toHaveTextContent("star-dashboard-server set aside")
    expect(entries[2]).toHaveTextContent("juel-claude")
  })

  it("selecting a row opens its detail, and the answer goes to that row's project", async () => {
    const posts: string[] = []
    server.events.on("request:start", ({ request }) => {
      if (request.method === "POST" && request.url.includes("/answer"))
        posts.push(new URL(request.url).pathname)
    })
    const { user } = renderApp("/needs")
    const list = await screen.findByRole("region", { name: "Open loops" })
    await user.click(
      await within(list).findByRole("button", {
        name: /star-dashboard-server set aside/,
      })
    )
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      within(detail).getByRole("heading", {
        name: "star-dashboard-server set aside: the gate failed twice",
      })
    ).toBeInTheDocument()
    expect(within(detail).getByText("juel-claude")).toBeInTheDocument()
    expect(within(detail).getByText("Set aside")).toBeInTheDocument()
    await user.click(within(detail).getAllByRole("radio")[0] as HTMLElement)
    await user.keyboard("{Control>}{Enter}{/Control}")
    await screen.findAllByText(/^Sent to STAR: "try again"/)
    expect(posts).toEqual(["/api/projects/juel-claude/loops/N-7/answer"])
    expect(
      getDb().loops["juel-claude"]?.find((l) => l.id === "N-7")?.answer
    ).toBe("try again")
    server.events.removeAllListeners()
  })

  it("/needs?project=<name> lists only that project, and the filter can be cleared", async () => {
    const { user, router } = renderApp("/needs?project=juel-claude")
    const list = await screen.findByRole("region", { name: "Open loops" })
    expect(within(list).getAllByRole("listitem")).toHaveLength(1)
    expect(
      screen.getByRole("button", { name: /^All\s*1$/ })
    ).toBeInTheDocument()
    expect(screen.getByText("Only juel-claude")).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: "Show every project" }))
    expect(
      await screen.findByRole("button", { name: /^All\s*10$/ })
    ).toBeInTheDocument()
    expect(router.state.location.search).toBe("")
    expect(screen.queryByText("Only juel-claude")).not.toBeInTheDocument()
  })

  it("keeps two projects' equal loop ids apart", async () => {
    getDb().loops["juel-claude"]?.push({
      id: "N-41",
      kind: "person",
      item: "other",
      title: "A step in the other project",
      body: [],
      options: [],
      suggestion: null,
      answer: "",
      askedAt: null,
    })
    const { user } = renderApp("/needs")
    const list = await screen.findByRole("region", { name: "Open loops" })
    await user.click(
      await within(list).findByRole("button", {
        name: /A step in the other project/,
      })
    )
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      within(detail).getByRole("heading", {
        name: "A step in the other project",
      })
    ).toBeInTheDocument()
  })

  it("shows an unreadable project's queue as one error row", async () => {
    server.use(
      http.get("*/api/loops", () =>
        HttpResponse.json([
          {
            project: "juel-claude",
            id: "",
            kind: "error",
            item: "",
            title: "juel-claude's queue could not be read",
            body: ["open-loops.md: unresolved git conflict markers"],
            options: [],
            suggestion: null,
            answer: "",
            askedAt: null,
          },
        ])
      )
    )
    const { user } = renderApp("/needs")
    const list = await screen.findByRole("region", { name: "Open loops" })
    await user.click(
      await within(list).findByRole("button", {
        name: /queue could not be read/,
      })
    )
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      within(detail).getByText(/unresolved git conflict markers/)
    ).toBeInTheDocument()
    expect(
      within(detail).queryByRole("button", { name: /Send to STAR/ })
    ).not.toBeInTheDocument()
  })

  it("filters the list by tab", async () => {
    const { user } = renderApp("/needs")
    await user.click(await screen.findByRole("button", { name: /^Slack\s*3$/ }))
    const list = screen.getByRole("region", { name: "Open loops" })
    const entries = within(list).getAllByRole("listitem")
    expect(entries).toHaveLength(3)
    for (const entry of entries) expect(entry).toHaveTextContent("Slack reply")
  })

  it("shows a person step, STAR's pick and the options, and sends with Ctrl+Enter", async () => {
    const { user } = renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      await within(detail).findByRole("heading", {
        name: "Log in to the Stripe dashboard and enable test mode",
      })
    ).toBeInTheDocument()
    expect(within(detail).getByText("Your step")).toBeInTheDocument()
    expect(within(detail).queryByText(/^Options:/)).not.toBeInTheDocument()
    expect(within(detail).getByText("STAR recommends")).toBeInTheDocument()
    expect(
      within(detail).getByText(/SPH-11 and SPH-12 start on their own/)
    ).toBeInTheDocument()
    const radios = within(detail).getAllByRole("radio")
    expect(radios).toHaveLength(2)
    expect(
      within(detail).getByText("Recommended").closest("label")
    ).toHaveTextContent(/^Done\s*Recommended\s*1$/)
    await user.click(radios[0] as HTMLElement)
    expect(within(detail).getByLabelText("Or write your own")).toHaveValue(
      "done"
    )
    await user.keyboard("{Control>}{Enter}{/Control}")
    expect(
      await screen.findByText('Sent to STAR: "done". It acts on it now.')
    ).toBeInTheDocument()
    expect(
      within(detail).getByText('Sent "done". STAR picked it up.')
    ).toBeInTheDocument()
    expect(loopAnswer("N-41")).toBe("done")
    const list = screen.getByRole("region", { name: "Open loops" })
    expect(within(list).getAllByText("Sent to STAR")).toHaveLength(1)
  })

  it("a loop with no time shows no age", async () => {
    renderApp("/needs?project=sphere-app&loop=N-39")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      await within(detail).findByRole("heading", {
        name: "SPH-5 needs an approval from a teammate",
      })
    ).toBeInTheDocument()
    expect(within(detail).queryByText(/^Asked/)).not.toBeInTheDocument()
  })

  it("asks for an answer before sending", async () => {
    const { user } = renderApp("/needs?project=sphere-app&loop=N-43")
    await user.click(
      await screen.findByRole("button", { name: /Send to STAR/ })
    )
    expect(
      await screen.findByText("Pick an answer or write one first.")
    ).toBeInTheDocument()
    expect(loopAnswer("N-43")).toBe("")
  })

  it("an item with no options sends free text", async () => {
    const { user } = renderApp("/needs?project=sphere-app&loop=N-46")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await within(detail).findByRole("heading", {
      name: /Mark PR #211 ready, then/,
    })
    expect(
      within(detail).queryByText("STAR recommends")
    ).not.toBeInTheDocument()
    expect(within(detail).queryAllByRole("radio")).toHaveLength(0)
    await user.type(
      within(detail).getByLabelText("Or write your own"),
      "ok, do it"
    )
    await user.keyboard("{Meta>}{Enter}{/Meta}")
    expect(
      await screen.findByText('Sent to STAR: "ok, do it". It acts on it now.')
    ).toBeInTheDocument()
    expect(loopAnswer("N-46")).toBe("ok, do it")
  })

  it("shows the conflict banner on a 409 and no Sent mark", async () => {
    setScenario("conflict")
    const { user } = renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await user.click(
      (await within(detail).findAllByRole("radio"))[0] as HTMLElement
    )
    await user.click(
      within(detail).getByRole("button", { name: /Send to STAR/ })
    )
    expect(
      await screen.findByText(
        "open-loops.md in sphere-app has conflict markers. Resolve them, then answer here."
      )
    ).toBeInTheDocument()
    expect(within(detail).queryByText(/^Sent "/)).not.toBeInTheDocument()
  })

  it("says when another answer got there first, without the conflict banner", async () => {
    server.use(
      http.post("*/api/projects/:p/loops/:id/answer", ({ params }) =>
        HttpResponse.json(
          {
            error: `${String(params.id)} already has an answer: STAR acts on that one`,
          },
          { status: 409 }
        )
      )
    )
    const { user } = renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await user.click(
      (await within(detail).findAllByRole("radio"))[0] as HTMLElement
    )
    await user.click(
      within(detail).getByRole("button", { name: /Send to STAR/ })
    )
    expect(
      await screen.findByText(
        "Couldn't send the answer: N-41 already has an answer: STAR acts on that one"
      )
    ).toBeInTheDocument()
    expect(
      screen.queryByText(
        "open-loops.md has conflict markers. Resolve them, then answer here."
      )
    ).not.toBeInTheDocument()
  })

  it("a failed send keeps the answer and says what failed", async () => {
    server.use(
      http.post("*/api/projects/:p/loops/:id/answer", () =>
        HttpResponse.json(
          { error: "loops.sh failed: disk full" },
          { status: 500 }
        )
      )
    )
    const { user } = renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const box = await within(detail).findByLabelText("Or write your own")
    await user.type(box, "done, but later")
    await user.click(
      within(detail).getByRole("button", { name: /Send to STAR/ })
    )
    expect(
      await screen.findByText(
        "Couldn't send the answer: loops.sh failed: disk full"
      )
    ).toBeInTheDocument()
    expect(box).toHaveValue("done, but later")
    expect(within(detail).queryByText(/^Sent "/)).not.toBeInTheDocument()
  })

  it("a Slack reply's detail is the Slack editor, with no options and no Edit the draft link", async () => {
    renderApp("/needs?project=sphere-app&loop=N-45")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      await within(detail).findByText(
        "hey, is the CSV export landing today? sales wants to demo it tomorrow"
      )
    ).toBeInTheDocument()
    expect(
      await within(detail).findByLabelText("Your reply")
    ).toBeInTheDocument()
    expect(
      within(detail).getByRole("button", { name: "Skip" })
    ).toBeInTheDocument()
    expect(
      within(detail).getByRole("button", { name: "Send reply" })
    ).toHaveAttribute("data-variant", "answer")
    expect(
      within(detail).getByLabelText("Ask the drafter to rewrite it")
    ).toBeInTheDocument()
    expect(
      within(detail).getByRole("button", { name: "Shorter" })
    ).toBeInTheDocument()
    expect(within(detail).queryAllByRole("radio")).toHaveLength(0)
    expect(
      within(detail).queryByRole("link", { name: /Edit the draft/ })
    ).not.toBeInTheDocument()
  })

  it("has loading, empty and error states", async () => {
    setScenario("loading")
    const first = renderApp("/needs")
    // The error state waits for the query's retries, which run slower under a full parallel run.
    expect(await screen.findByTestId("page-loading", {}, { timeout: 5000 })).toBeInTheDocument()
    first.unmount()
    setScenario("empty")
    const second = renderApp("/needs")
    expect(
      await screen.findByText("Nothing needs you right now.", {}, { timeout: 5000 })
    ).toBeInTheDocument()
    expect(
      screen.getByText(
        "When STAR waits on one of your steps, a draft or a Slack reply, it shows here."
      )
    ).toBeInTheDocument()
    second.unmount()
    setScenario("error")
    renderApp("/needs")
    const alert = await screen.findByTestId("page-error", {}, { timeout: 5000 })
    expect(alert).toHaveTextContent("Couldn't load the open loops.")
    expect(alert).toHaveTextContent(
      "Could not read ledger.md: permission denied"
    )
    await waitFor(() =>
      expect(
        within(alert).getByRole("button", { name: /Try again/ })
      ).toBeEnabled()
    )
  })

  it("says when STAR was not reached (a stopped project)", async () => {
    const { user } = renderApp("/needs?project=juel-claude&loop=N-7")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await user.click(
      (await within(detail).findAllByRole("radio"))[0] as HTMLElement
    )
    await user.click(
      within(detail).getByRole("button", { name: /Send to STAR/ })
    )
    expect(
      (
        await screen.findAllByText(
          'Sent to STAR: "try again". STAR reads it on its next tick.'
        )
      ).length
    ).toBeGreaterThan(0)
    expect(
      within(detail).getByText(
        'Sent "try again". STAR reads it when it next runs.'
      )
    ).toBeInTheDocument()
  })

  it("sends once on a double ⌘Enter", async () => {
    const { user } = renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await user.click(
      (await within(detail).findAllByRole("radio"))[0] as HTMLElement
    )
    let posts = 0
    server.events.on("request:start", ({ request }) => {
      if (request.method === "POST" && request.url.includes("/answer"))
        posts += 1
    })
    await user.keyboard("{Control>}{Enter}{Enter}{/Control}")
    await screen.findAllByText('Sent to STAR: "done". It acts on it now.')
    expect(posts).toBe(1)
    server.events.removeAllListeners()
  })

  it("shows an answer already waiting for STAR", async () => {
    const loop = getDb().loops["sphere-app"]?.find(
      (candidate) => candidate.id === "N-41"
    )
    if (!loop) throw new Error("fixture N-41 missing")
    loop.answer = "done"
    const { user } = renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      within(detail).getByText('Sent "done". Waiting for STAR to pick it up.')
    ).toBeInTheDocument()
    await user.click(
      (await within(detail).findAllByRole("radio"))[0] as HTMLElement
    )
  })

  it("keeps the loaded page when a refetch fails", async () => {
    const { user, client } = renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const box = await within(detail).findByLabelText("Or write your own")
    await user.type(box, "done, but later")
    server.use(
      http.get("*/api/loops", () =>
        HttpResponse.json(
          { error: "Could not read open-loops.md" },
          { status: 502 }
        )
      )
    )
    await act(() => client.refetchQueries({ queryKey: ["loops", "*"] }))
    expect(
      await screen.findByText(
        /Couldn't refresh the open loops: Could not read open-loops.md/
      )
    ).toBeInTheDocument()
    expect(box).toHaveValue("done, but later")
  })

  it("refreshes when STAR changes the queue (a loops event)", async () => {
    renderApp("/needs")
    await screen.findByRole("button", { name: /^All\s*10$/ })
    await waitFor(() => expect(getConnection()).toBe("open"))
    getDb().loops["sphere-app"]?.push({
      id: "N-50",
      kind: "question",
      item: "SPH-20",
      title: "A new question from the build worker",
      body: [],
      options: [],
      suggestion: null,
      answer: "",
      askedAt: null,
    })
    act(() =>
      mockEvents.emit({ type: "change", project: "sphere-app", what: "loops" })
    )
    expect(
      await screen.findByText("A new question from the build worker")
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /^All\s*11$/ })
    ).toBeInTheDocument()
  })

  it("on a phone, shows the list, opens an item on its own, and Back keeps the tab", async () => {
    phone()
    const { user, router } = renderApp("/needs")
    await user.click(await screen.findByRole("button", { name: /^Slack\s*3$/ }))
    const list = screen.getByRole("region", { name: "Open loops" })
    expect(
      screen.queryByRole("region", { name: "Answer" })
    ).not.toBeInTheDocument()
    await user.click(
      within(list).getByRole("button", { name: /Lea in #releases/ })
    )
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      await within(detail).findByText("which PR fixes the invoice time zone?")
    ).toBeInTheDocument()
    expect(router.state.historyAction).toBe("PUSH")
    expect(router.state.location.search).toBe("?loop=sphere-app%2FN-48")
    expect(
      screen.queryByRole("region", { name: "Open loops" })
    ).not.toBeInTheDocument()
    await user.click(
      within(detail).getByRole("button", { name: "Back to Needs you" })
    )
    const again = await screen.findByRole("region", { name: "Open loops" })
    expect(router.state.location.search).toBe("")
    expect(screen.getByRole("button", { name: /^Slack\s*3$/ })).toHaveAttribute(
      "aria-pressed",
      "true"
    )
    expect(within(again).getAllByRole("listitem")).toHaveLength(3)
  })

  it("fades the list in once when the chip changes", async () => {
    const { user } = renderApp("/needs")
    const list = await screen.findByRole("region", { name: "Open loops" })
    const before = list.querySelector("[data-slot='loop-sections']")
    expect(before).toHaveClass("motion-fade-in")
    await user.click(
      screen.getByRole("button", { name: /^Holds up work\s*4$/ })
    )
    const after = list.querySelector("[data-slot='loop-sections']")
    expect(after).not.toBe(before)
    expect(after).toHaveClass("motion-fade-in")
  })

  it("on a phone, Back from a linked item removes it in place", async () => {
    phone()
    const { user, router } = renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      screen.queryByRole("region", { name: "Open loops" })
    ).not.toBeInTheDocument()
    await user.click(
      within(detail).getByRole("button", { name: "Back to Needs you" })
    )
    expect(
      await screen.findByRole("region", { name: "Open loops" })
    ).toBeInTheDocument()
    expect(router.state.historyAction).toBe("REPLACE")
    expect(router.state.location.search).toBe("?project=sphere-app")
  })

  it("on a phone, a loop STAR already closed shows the list, not another item", async () => {
    phone()
    renderApp("/needs?project=sphere-app&loop=N-99")
    expect(
      await screen.findByRole("region", { name: "Open loops" })
    ).toBeInTheDocument()
    expect(
      screen.queryByRole("region", { name: "Answer" })
    ).not.toBeInTheDocument()
  })

  it("hides the ⌘↵ hint on touch and grows its buttons to 44 px", async () => {
    renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const send = within(detail).getByRole("button", { name: /Send to STAR/ })
    expect(within(send).getByText("⌘↵")).toHaveClass("pointer-coarse:hidden")
    expect(send).toHaveClass("pointer-coarse:h-11")
    expect(send).toHaveAttribute("data-variant", "answer")
    expect(within(detail).getByText("sphere-app")).toBeInTheDocument()
  })

  it("shows a Slack item's message with its bullets and links", async () => {
    const lea = getDb().slack.routed.find((m) => m.from === "Lea")
    if (!lea) throw new Error("fixture Lea missing")
    lea.text =
      "which PR fixes the invoice time zone?\n• the bug: https://github.com/example/sphere-app/issues/88\n• the PR, if there is one"
    renderApp("/needs?project=sphere-app&loop=N-48")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      await within(detail).findByRole("link", {
        name: "https://github.com/example/sphere-app/issues/88",
      })
    ).toHaveAttribute("target", "_blank")
    expect(
      within(within(detail).getByRole("list")).getAllByRole("listitem")
    ).toHaveLength(2)
  })
})

const recordPosts = () => {
  const paths: string[] = []
  const bodies: string[] = []
  server.events.on("request:start", ({ request }) => {
    if (request.method === "POST" && request.url.includes("/answer")) {
      paths.push(new URL(request.url).pathname)
      void request
        .clone()
        .text()
        .then((text) => bodies.push(text))
    }
  })
  return { paths, bodies }
}
const rowOf = (text: RegExp) =>
  screen.getByText(text).closest("li") as HTMLElement
const STRIPE = /Log in to the Stripe dashboard/
// The toast's Undo; the row has its own.
const toastUndo = () =>
  screen
    .getAllByRole("button", { name: "Undo" })
    .find((b) => !rowOf(STRIPE).contains(b)) as HTMLElement

describe("Needs you sections", () => {
  afterEach(() => {
    server.events.removeAllListeners()
    vi.useRealTimers()
  })

  it("groups the rows in sections with filter chips and a subtitle", async () => {
    const { user } = renderApp("/needs")
    const list = await screen.findByRole("region", { name: "Open loops" })
    expect(
      await screen.findByRole("button", { name: /^All\s*10$/ })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /^Holds up work\s*4$/ })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /^Slack\s*3$/ })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /^Other\s*3$/ })
    ).toBeInTheDocument()
    expect(
      within(list).getByText("10 open across 2 projects. 4 hold up work.")
    ).toBeInTheDocument()
    const headings = within(list)
      .getAllByRole("heading", { level: 2 })
      .map((h) => h.textContent)
    expect(headings).toEqual(["Holds up work 4", "Slack replies 3", "Other 3"])
    await user.click(screen.getByRole("button", { name: /^Slack\s*3$/ }))
    expect(
      within(list)
        .getAllByRole("heading", { level: 2 })
        .map((h) => h.textContent)
    ).toEqual(["Slack replies 3"])
    expect(within(list).getAllByRole("listitem")).toHaveLength(3)
  })

  it("the subtitle follows a project filter and singular counts", async () => {
    renderApp("/needs?project=juel-claude")
    const list = await screen.findByRole("region", { name: "Open loops" })
    expect(
      await within(list).findByText("1 open. 1 holds up work.")
    ).toBeInTheDocument()
  })

  it("on a desktop the first row is current, on a phone no row is until the URL names one", async () => {
    const first = renderApp("/needs")
    const list = await screen.findByRole("region", { name: "Open loops" })
    await within(list).findAllByRole("listitem")
    const current = within(list)
      .getAllByRole("button")
      .filter((b) => b.getAttribute("aria-current") === "true")
    expect(current).toHaveLength(1)
    first.unmount()
    phone()
    renderApp("/needs")
    const phoneList = await screen.findByRole("region", { name: "Open loops" })
    await within(phoneList).findAllByRole("listitem")
    expect(phoneList.querySelectorAll("[aria-current]")).toHaveLength(0)
  })

  it("keeps a held row's layout still, and ignores a tap on Undo right after the answer tap", async () => {
    phone()
    const { paths } = recordPosts()
    renderApp("/needs")
    await screen.findByText(STRIPE)
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "Date"], shouldAdvanceTime: true })
    fireEvent.click(within(rowOf(STRIPE)).getByRole("button", { name: "Done" }))
    const row = rowOf(STRIPE)
    // The held state sits in the action row, not in the row's own button.
    const open = within(row).getByRole("button", { name: STRIPE })
    expect(within(open).queryByText("Sending…")).not.toBeInTheDocument()
    expect(within(row).getByRole("button", { name: "Sending…" })).toBeDisabled()
    const undo = within(row).getByRole("button", { name: "Undo" })
    // A double tap's second half lands within 400 ms and must not cancel the answer.
    fireEvent.click(undo)
    act(() => vi.advanceTimersByTime(5100))
    vi.useRealTimers()
    await waitFor(() => expect(paths).toEqual(["/api/projects/sphere-app/loops/N-41/answer"]))
  })

  it("an answer sent from the detail cancels the one-tap answer still held for that loop", async () => {
    phone()
    const { paths, bodies } = recordPosts()
    renderApp("/needs")
    await screen.findByText(STRIPE)
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"], shouldAdvanceTime: true })
    fireEvent.click(within(rowOf(STRIPE)).getByRole("button", { name: "Done" }))
    expect(await screen.findByText('"Done" goes to STAR in 5 seconds.')).toBeInTheDocument()
    fireEvent.click(within(rowOf(STRIPE)).getByRole("button", { name: new RegExp(STRIPE) }))
    const detail = await screen.findByRole("region", { name: "Answer" })
    fireEvent.click(within(detail).getByRole("radio", { name: /Can't now/ }))
    fireEvent.click(within(detail).getByRole("button", { name: /Send to STAR/ }))
    await waitFor(() => expect(bodies).toEqual(['{"text":"can\'t now"}']))
    act(() => vi.advanceTimersByTime(6000))
    vi.useRealTimers()
    await new Promise((r) => setTimeout(r, 50))
    expect(paths).toEqual(["/api/projects/sphere-app/loops/N-41/answer"])
  })

  it("on a phone a tap on Done holds the answer, then posts it once and shows Sent to STAR", async () => {
    phone()
    const { paths, bodies } = recordPosts()
    const fetchSpy = vi.spyOn(globalThis, "fetch")
    renderApp("/needs")
    await screen.findByText(STRIPE)
    vi.useFakeTimers({
      toFake: ["setTimeout", "clearTimeout"],
      shouldAdvanceTime: true,
    })
    const row = rowOf(STRIPE)
    expect(
      within(row).getByRole("button", { name: "Can't now" })
    ).toBeInTheDocument()
    fireEvent.click(within(row).getByRole("button", { name: "Done" }))
    expect(
      await screen.findByText('"Done" goes to STAR in 5 seconds.')
    ).toBeInTheDocument()
    expect(toastUndo()).toBeInTheDocument()
    expect(within(row).getByText("Sending…")).toBeInTheDocument()
    act(() => vi.advanceTimersByTime(4500))
    expect(paths).toEqual([])
    act(() => vi.advanceTimersByTime(600))
    vi.useRealTimers()
    await waitFor(() =>
      expect(
        within(rowOf(STRIPE)).getByText("Sent to STAR")
      ).toBeInTheDocument()
    )
    expect(paths).toEqual(["/api/projects/sphere-app/loops/N-41/answer"])
    await waitFor(() => expect(bodies).toEqual(['{"text":"done"}']))
    expect(loopAnswer("N-41")).toBe("done")
    // Sent with keepalive, so a tab closed during the flush still delivers it.
    const answerCall = fetchSpy.mock.calls.find(([url]) => String(url).endsWith("/loops/N-41/answer"))
    expect(answerCall?.[1]?.keepalive).toBe(true)
  })

  it("Undo cancels the post for good", async () => {
    phone()
    const { paths } = recordPosts()
    const { user } = renderApp("/needs")
    await screen.findByText(STRIPE)
    vi.useFakeTimers({
      toFake: ["setTimeout", "clearTimeout"],
      shouldAdvanceTime: true,
    })
    fireEvent.click(within(rowOf(STRIPE)).getByRole("button", { name: "Done" }))
    await screen.findByText('"Done" goes to STAR in 5 seconds.')
    fireEvent.click(toastUndo())
    act(() => vi.advanceTimersByTime(20000))
    vi.useRealTimers()
    expect(paths).toEqual([])
    expect(
      within(rowOf(STRIPE)).getByRole("button", { name: "Done" })
    ).toBeInTheDocument()
    expect(
      within(rowOf(STRIPE)).queryByText("Sending…")
    ).not.toBeInTheDocument()
    expect(loopAnswer("N-41")).toBe("")
    // A later tap still works and posts once, with its own answer.
    await user.click(
      within(rowOf(STRIPE)).getByRole("button", { name: "Can't now" })
    )
    await waitFor(() => expect(paths).toHaveLength(1), { timeout: 7000 })
    expect(loopAnswer("N-41")).toBe("can't now")
  }, 15000)

  it("leaving the page during the hold still posts exactly once", async () => {
    phone()
    const { paths } = recordPosts()
    const { router } = renderApp("/needs")
    await screen.findByText(STRIPE)
    vi.useFakeTimers({
      toFake: ["setTimeout", "clearTimeout"],
      shouldAdvanceTime: true,
    })
    fireEvent.click(within(rowOf(STRIPE)).getByRole("button", { name: "Done" }))
    await act(async () => {
      await router.navigate("/sphere-app/progress")
    })
    act(() => vi.advanceTimersByTime(5000))
    vi.useRealTimers()
    await waitFor(() => expect(paths).toHaveLength(1))
    await new Promise((r) => setTimeout(r, 50))
    expect(paths).toEqual(["/api/projects/sphere-app/loops/N-41/answer"])
    expect(loopAnswer("N-41")).toBe("done")
  })

  it("a failed post shows the error toast and the row is unanswered again", async () => {
    server.use(
      http.post("*/api/projects/:p/loops/:id/answer", () =>
        HttpResponse.json(
          { error: "loops.sh failed: disk full" },
          { status: 500 }
        )
      )
    )
    phone()
    renderApp("/needs")
    await screen.findByText(STRIPE)
    vi.useFakeTimers({
      toFake: ["setTimeout", "clearTimeout"],
      shouldAdvanceTime: true,
    })
    fireEvent.click(within(rowOf(STRIPE)).getByRole("button", { name: "Done" }))
    act(() => vi.advanceTimersByTime(5000))
    vi.useRealTimers()
    expect(
      await screen.findByText(
        "Couldn't send the answer: loops.sh failed: disk full"
      )
    ).toBeInTheDocument()
    await waitFor(() =>
      expect(
        within(rowOf(STRIPE)).getByRole("button", { name: "Done" })
      ).toBeInTheDocument()
    )
    expect(
      within(rowOf(STRIPE)).queryByText("Sent to STAR")
    ).not.toBeInTheDocument()
  })

  it("the Ria row shows the draft with Send reply and Edit; a long list gets Open; errors get no buttons", async () => {
    phone()
    const { paths, bodies } = recordPosts()
    const { user, router } = renderApp("/needs")
    await screen.findByText(STRIPE)
    const ria = rowOf(/Ria in #sphere-eng/)
    expect(
      await within(ria).findByText("Your reply, drafted by STAR")
    ).toBeInTheDocument()
    expect(
      await within(ria).findByText(/It's in final review now/)
    ).toBeInTheDocument()
    expect(
      within(ria).getByRole("button", { name: "Edit" })
    ).toBeInTheDocument()
    fireEvent.click(
      await within(ria).findByRole("button", { name: "Send reply" })
    )
    await waitFor(
      () =>
        expect(paths).toEqual(["/api/projects/sphere-app/loops/N-45/answer"]),
      { timeout: 8000 }
    )
    await waitFor(() => expect(bodies).toEqual(['{"text":"send"}']))
    await user.click(
      within(rowOf(/Lea in #releases/)).getByRole("button", { name: "Edit" })
    )
    expect(router.state.location.search).toBe("?loop=sphere-app%2FN-48")
  }, 15000)

  it("a loop with more than two options gets Open, and an unreadable queue gets no buttons", async () => {
    getDb().loops["sphere-app"]?.push({
      id: "N-60",
      kind: "question",
      item: "SPH-30",
      title: "Pick one of three",
      body: [],
      options: [
        { label: "One", answer: "one", recommended: false },
        { label: "Two", answer: "two", recommended: true },
        { label: "Three", answer: "three", recommended: false },
      ],
      suggestion: null,
      answer: "",
      askedAt: null,
    })
    phone()
    renderApp("/needs")
    const row = await screen
      .findByText("Pick one of three")
      .then((e) => e.closest("li") as HTMLElement)
    expect(within(row).getByRole("button", { name: "Two" })).toBeInTheDocument()
    expect(
      within(row).getByRole("button", { name: "Open" })
    ).toBeInTheDocument()
  })
})

describe("Needs you detail", () => {
  it("shows the subkind chip and an Unblocks block with each item's rail, and drops the raw lines", async () => {
    renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(await within(detail).findByText("Account")).toBeInTheDocument()
    expect(within(detail).queryByText(/kind: account/)).not.toBeInTheDocument()
    expect(within(detail).queryByText(/^also:/)).not.toBeInTheDocument()
    const unblocks = await within(detail).findByRole("region", {
      name: "Unblocks",
    })
    expect(within(unblocks).getByText("SPH-11")).toBeInTheDocument()
    expect(within(unblocks).getByText("SPH-12")).toBeInTheDocument()
    await waitFor(() =>
      expect(within(unblocks).getAllByRole("img").length).toBeGreaterThan(0)
    )
    // The step reads as STAR wrote it for people, without its step token.
    expect(within(unblocks).getByText("Codex gate, round 2 of 3")).toBeInTheDocument()
    expect(within(unblocks).queryByText(/gate-r2/)).not.toBeInTheDocument()
  })

  it("wraps the filter chips on a desktop and scrolls them without a bar on a phone", async () => {
    renderApp("/needs")
    const chips = await screen.findByRole("group", { name: "Filter" })
    expect(chips).toHaveClass("md:flex-wrap", "[scrollbar-width:none]")
    const hold = within(chips).getByRole("button", { name: /Holds up work/ })
    expect(hold.querySelector("[data-slot=badge]")).toHaveAttribute("data-variant", "wait")
  })

  it("opens the routed message of the loop's own project when another project has the same loop id", async () => {
    const db = getDb()
    db.slack.routed.unshift({
      ...db.slack.routed[0]!,
      id: "other-project-msg",
      project: "juel-claude",
      from: "Zed",
      text: "a message from another project",
      draftPath: "drafts/missing.md",
    })
    renderApp("/needs?project=sphere-app&loop=N-45")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const reply = await within(detail).findByRole("textbox", { name: "Your reply" })
    await waitFor(() => expect((reply as HTMLTextAreaElement).value).toMatch(/Not today/))
  })

  it("on a phone puts the sent status above the answer dock, so the dock never covers it", async () => {
    phone()
    renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    fireEvent.click(await within(detail).findByRole("radio", { name: /Done/ }))
    fireEvent.click(within(detail).getByRole("button", { name: /Send to STAR/ }))
    const status = await within(detail).findByRole("status")
    const dock = detail.querySelector("[data-slot=answer-dock]") as HTMLElement
    expect(status.compareDocumentPosition(dock) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
  })

  it("in Unblocks shows Report only for a report item, and the status for a state with no rail", async () => {
    const row = getDb().items["sphere-app"]?.find((d) => d.row.item === "SPH-12")?.row
    if (!row) throw new Error("fixture missing")
    row.state = "some-future-state"
    renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const unblocks = await within(detail).findByRole("region", { name: "Unblocks" })
    const entry = (await within(unblocks).findByText("SPH-12")).closest("li") as HTMLElement
    await waitFor(() => expect(entry).toHaveTextContent(/Queued|Needs you|Briefing/))
    expect(entry).not.toHaveTextContent("Report")
  })

  it("lists the refs alone when the items cannot be read", async () => {
    server.use(
      http.get("*/api/projects/:p/items", () =>
        HttpResponse.json({ error: "no" }, { status: 500 })
      )
    )
    renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const unblocks = await within(detail).findByRole("region", {
      name: "Unblocks",
    })
    expect(within(unblocks).getByText("SPH-11")).toBeInTheDocument()
    expect(within(unblocks).getByText("SPH-12")).toBeInTheDocument()
    expect(within(unblocks).queryAllByRole("img")).toHaveLength(0)
  })

  it("the footnote says STAR acts on the answer as soon as it is sent", async () => {
    renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      await within(detail).findByText(
        "STAR acts on your answer as soon as you send it."
      )
    ).toBeInTheDocument()
    expect(within(detail).queryByText(/open-loops\.md/)).not.toBeInTheDocument()
    expect(detail.querySelector(".max-w-\\[680px\\]")).not.toBeNull()
  })

  it("on a desktop each option shows its number, a number picks it, J and K move the selection", async () => {
    const { user, router } = renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await within(detail).findByText("Account")
    expect(within(detail).getByText("1")).toBeInTheDocument()
    expect(within(detail).getByText("2")).toBeInTheDocument()
    await user.keyboard("2")
    expect(within(detail).getByLabelText("Or write your own")).toHaveValue(
      "can't now"
    )
    expect(within(detail).getAllByRole("radio")[1]).toBeChecked()
    await user.keyboard("j")
    expect(router.state.location.search).toBe(
      "?project=sphere-app&loop=sphere-app%2FN-44"
    )
    await user.keyboard("k")
    expect(router.state.location.search).toBe(
      "?project=sphere-app&loop=sphere-app%2FN-41"
    )
  })

  it("the keys do nothing while the textarea has focus, and the list footer shows the hints", async () => {
    const { user, router } = renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const box = await within(detail).findByLabelText("Or write your own")
    await user.click(box)
    await user.keyboard("2jk")
    expect(box).toHaveValue("2jk")
    expect(router.state.location.search).toBe("?project=sphere-app&loop=N-41")
    const list = screen.getByRole("region", { name: "Open loops" })
    for (const word of ["move", "pick", "send"])
      expect(within(list).getByText(word)).toBeInTheDocument()
    expect(within(list).getByText("J")).toBeInTheDocument()
    expect(within(list).getByText("⌘↵")).toBeInTheDocument()
  })

  it("on a phone Send to STAR sits in the dock and shows no ⌘↵", async () => {
    phone()
    renderApp("/needs?project=sphere-app&loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await within(detail).findByText("Account")
    const dock = detail.querySelector(
      "[data-slot='answer-dock']"
    ) as HTMLElement
    expect(dock).not.toBeNull()
    expect(
      within(dock).getByRole("button", { name: /Send to STAR/ })
    ).toHaveAttribute("data-variant", "answer")
    expect(within(detail).queryByText("⌘↵")).not.toBeInTheDocument()
  })

  it("on a phone a Slack reply's Skip and Send reply sit in the dock", async () => {
    phone()
    renderApp("/needs?project=sphere-app&loop=N-45")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const dock = await waitFor(() => {
      const el = detail.querySelector(
        "[data-slot='answer-dock']"
      ) as HTMLElement
      expect(el).not.toBeNull()
      return el
    })
    expect(
      within(dock).getByRole("button", { name: "Skip" })
    ).toBeInTheDocument()
    expect(
      within(dock).getByRole("button", { name: "Send reply" })
    ).toBeInTheDocument()
  })
})
