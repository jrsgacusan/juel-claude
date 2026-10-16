import { useQueryClient } from "@tanstack/react-query"
import { useEffect, useState } from "react"
import { Link, Outlet, useLocation, useParams } from "react-router"
import { startEvents } from "@/api/events"
import { useProjects } from "@/api/queries"
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar"
import { cn } from "@/lib/utils"
import { isPage, projectPath } from "@/lib/routes"
import { AppSidebar } from "./app-sidebar"
import { ConflictBanner, ConnectionBanner, StoppedBanner } from "./banners"
import {
  EmptyState,
  ErrorState,
  queryFailed,
  RefreshNotice,
  refreshFailed,
} from "./page-state"
import { SearchDialog } from "./search-dialog"
import { SiteHeader } from "./site-header"

export function AppLayout() {
  const { project = "" } = useParams()
  const segment = useLocation().pathname.split("/")[2] ?? ""
  const page = isPage(segment) ? segment : "needs"
  const [searchOpen, setSearchOpen] = useState(false)
  const queryClient = useQueryClient()
  const projects = useProjects()

  useEffect(() => startEvents(queryClient), [queryClient])

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault()
        setSearchOpen((open) => !open)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [])

  // Chat and Briefing scroll in their own box, so below md their column is exactly the screen tall.
  const fills = segment === "chat" || segment === "briefing"

  const unknown =
    projects.isSuccess && !projects.data.some((p) => p.name === project)

  return (
    <SidebarProvider>
      <AppSidebar project={project} page={page} />
      <SidebarInset
        className={cn(
          "min-w-0 overflow-x-clip md:h-[calc(100svh-1rem)] md:overflow-hidden",
          fills && "max-md:h-dvh"
        )}
      >
        <SiteHeader
          project={project}
          page={segment}
          onSearch={() => setSearchOpen(true)}
        />
        <StoppedBanner project={project} />
        <ConflictBanner project={project} />
        <ConnectionBanner />
        <div className="flex min-h-0 min-w-0 flex-1 flex-col md:overflow-hidden">
          {refreshFailed(projects) && (
            <RefreshNotice
              what="the projects"
              error={projects.error}
              onRetry={() => void projects.refetch()}
            />
          )}
          {queryFailed(projects) ? (
            <ErrorState
              what="the projects"
              error={projects.error}
              onRetry={() => void projects.refetch()}
            />
          ) : unknown ? (
            <EmptyState
              title={`No project named ${project} on this Mac.`}
              body="Pick one of the projects in the sidebar."
              action={
                <ul className="flex flex-col gap-1 text-sm">
                  {projects.data.map((p) => (
                    <li key={p.name}>
                      <Link
                        className="underline underline-offset-4"
                        to={projectPath(p.name, "needs")}
                      >
                        {p.name}
                      </Link>
                    </li>
                  ))}
                </ul>
              }
            />
          ) : (
            <Outlet key={project} />
          )}
        </div>
      </SidebarInset>
      <SearchDialog
        open={searchOpen}
        onOpenChange={setSearchOpen}
        project={project}
      />
    </SidebarProvider>
  )
}
