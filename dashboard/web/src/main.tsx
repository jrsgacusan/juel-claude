import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { RouterProvider } from "react-router"
import "./index.css"
import { createQueryClient } from "@/api/queries"
import { captureToken } from "@/api/token"
import { AppProviders } from "@/app"
import { createAppRouter } from "@/router"

// Before the router reads the URL: ?t= goes to sessionStorage and leaves the address bar.
captureToken()

async function enableMocking(): Promise<void> {
  // Development only (brief D3): a production build drops this branch, so msw is never bundled.
  if (!import.meta.env.DEV || import.meta.env.VITE_MOCK === "off") return
  const { startMockWorker } = await import("./mocks/browser")
  await startMockWorker()
}

void enableMocking()
  .then(() => {
    const root = document.getElementById("root")
    if (!root) throw new Error("index.html has no #root")
    createRoot(root).render(
      <StrictMode>
        <AppProviders client={createQueryClient()}>
          <RouterProvider router={createAppRouter()} />
        </AppProviders>
      </StrictMode>
    )
  })
  .catch((error: unknown) => {
    console.error(error)
    document.getElementById("root")?.replaceChildren(
      Object.assign(document.createElement("p"), {
        textContent: `The mock layer failed to start: ${error instanceof Error ? error.message : String(error)}. Run npm run dev.`,
      })
    )
  })
