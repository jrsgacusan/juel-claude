import { render } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { createMemoryRouter, RouterProvider } from "react-router"
import { vi } from "vitest"
import { createQueryClient } from "@/api/queries"
import { AppProviders } from "@/app"
import { routes } from "@/router"

/** The whole app at `path`, against the MSW mock layer, with no retries. */
export function renderApp(path: string) {
  const client = createQueryClient()
  client.setDefaultOptions({
    queries: { ...client.getDefaultOptions().queries, retry: false },
    mutations: { retry: false },
  })
  const router = createMemoryRouter(routes, { initialEntries: [path] })
  const user = userEvent.setup()
  const view = render(
    <AppProviders client={client}>
      <RouterProvider router={router} />
    </AppProviders>
  )
  return { ...view, user, router, client }
}

/** A matchMedia whose prefers-color-scheme answer a test can flip. */
export function mockColorScheme(dark: boolean) {
  let isDark = dark
  const listeners = new Set<(event: MediaQueryListEvent) => void>()
  vi.spyOn(window, "matchMedia").mockImplementation(
    (query: string) =>
      ({
        get matches() {
          return query.includes("dark") ? isDark : !isDark
        },
        media: query,
        onchange: null,
        addEventListener: (
          _type: string,
          listener: (event: MediaQueryListEvent) => void
        ) => listeners.add(listener),
        removeEventListener: (
          _type: string,
          listener: (event: MediaQueryListEvent) => void
        ) => listeners.delete(listener),
        addListener: () => {},
        removeListener: () => {},
        dispatchEvent: () => false,
      }) as unknown as MediaQueryList
  )
  return {
    set(next: boolean) {
      isDark = next
      listeners.forEach((listener) =>
        listener({ matches: next } as MediaQueryListEvent)
      )
    },
  }
}
