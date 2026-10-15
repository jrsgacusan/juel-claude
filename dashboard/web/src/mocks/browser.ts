import { setupWorker } from "msw/browser"
import type { StarEvent } from "@/api/types"
import { handlers } from "./handlers"
import {
  mockEvents,
  readScenario,
  resetMockState,
  setScenario,
  type Scenario,
} from "./state"

// Development only (main.tsx imports this behind import.meta.env.DEV, spec D3).
// window.__starMock lets Playwright drop the event stream and switch scenarios (spec D17).
declare global {
  interface Window {
    __starMock?: {
      events: { drop(): void; restore(): void; emit(event: StarEvent): void }
      use(scenario: Scenario): void
      reset(): void
    }
  }
}

export async function startMockWorker(): Promise<void> {
  setScenario(readScenario())
  window.__starMock = {
    events: {
      drop: () => mockEvents.drop(),
      restore: () => mockEvents.restore(),
      emit: (event) => mockEvents.emit(event),
    },
    use: setScenario,
    reset: resetMockState,
  }
  await setupWorker(...handlers).start({
    onUnhandledRequest: "bypass",
    quiet: true,
  })
}
