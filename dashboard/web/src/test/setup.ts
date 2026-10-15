import "@testing-library/jest-dom/vitest"
import { cleanup } from "@testing-library/react"
import { setConnection } from "@/api/events"
import { server } from "@/mocks/node"
import { resetMockState } from "@/mocks/state"
import { setConflict } from "@/lib/conflict"
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
  setConnection("connecting")
  server.resetHandlers()
  resetMockState()
})
