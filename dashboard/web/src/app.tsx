import { type QueryClient, QueryClientProvider } from "@tanstack/react-query"
import type { ReactNode } from "react"
import { ThemeProvider } from "@/components/theme-provider"
import { Toaster } from "@/components/ui/sonner"
import { TooltipProvider } from "@/components/ui/tooltip"
import { useNarrow } from "@/components/list-detail"

/** Bottom centre above the tab bar on a phone, bottom right on a desktop. */
function AppToaster() {
  const narrow = useNarrow()
  const offset = "calc(var(--tab-bar-h) + 0.5rem)"
  return narrow ? (
    <Toaster position="bottom-center" offset={{ bottom: offset }} mobileOffset={{ bottom: offset }} />
  ) : (
    <Toaster position="bottom-right" />
  )
}

export function AppProviders({
  client,
  children,
}: {
  client: QueryClient
  children: ReactNode
}) {
  return (
    <ThemeProvider defaultTheme="system" storageKey="star-theme">
      <QueryClientProvider client={client}>
        <TooltipProvider>
          {children}
          <AppToaster />
        </TooltipProvider>
      </QueryClientProvider>
    </ThemeProvider>
  )
}
