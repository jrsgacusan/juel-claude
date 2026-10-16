import "@testing-library/jest-dom/vitest"
import { cleanup, configure } from "@testing-library/react"
import { setConnection } from "@/api/events"
import { server } from "@/mocks/node"
import { resetMockState } from "@/mocks/state"
import { setConflict } from "@/lib/conflict"
import { clearPendingBriefings } from "@/lib/pending-briefing"
import { afterAll, afterEach, beforeAll, beforeEach, vi } from "vitest"

if (!window.matchMedia) {
  window.matchMedia = (query: string): MediaQueryList =>
    ({
      matches: false,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => false,
    }) as MediaQueryList
}
globalThis.ResizeObserver ??= class {
  observe() {}
  unobserve() {}
  disconnect() {}
}
Element.prototype.scrollIntoView ??= function scrollIntoView() {}
Element.prototype.hasPointerCapture ??= () => false
Element.prototype.releasePointerCapture ??= () => {}
URL.createObjectURL = () => "blob:mock"
URL.revokeObjectURL = () => {}

// The whole suite runs files in parallel; under that load a first render can take longer than
// Testing Library's 1 s default, so findBy and waitFor get 3 s before they fail.
configure({ asyncUtilTimeout: 3_000 })

beforeAll(() => server.listen({ onUnhandledFrame: "error" }))
afterAll(() => server.close())

beforeEach(() => {
  sessionStorage.setItem("star-token", "test-token")
})

afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
  sessionStorage.clear()
  localStorage.clear()
  document.documentElement.className = ""
  setConflict(null)
  clearPendingBriefings()
  setConnection("connecting")
  server.resetHandlers()
  resetMockState()
})
