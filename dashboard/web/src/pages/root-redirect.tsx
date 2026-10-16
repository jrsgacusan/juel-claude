import type { ReactNode } from "react"
import { Navigate } from "react-router"
import { useProjects } from "@/api/queries"
import { EmptyState, ErrorState, LoadingState } from "@/components/page-state"
import { projectPath } from "@/lib/routes"

/** "/": the first running project's Needs you, else the first listed (brief D1). */
export function RootRedirect() {
  const projects = useProjects()
  const frame = (child: ReactNode) => (
    <main className="grid min-h-svh place-items-center bg-sidebar p-4">
      {child}
    </main>
  )
  if (projects.isPending) return frame(<LoadingState label="the projects" />)
  if (projects.isError)
    return frame(
      <ErrorState
        what="the projects"
        error={projects.error}
        onRetry={() => void projects.refetch()}
      />
    )
  const first =
    projects.data.find((p) => p.state === "running") ?? projects.data[0]
  if (!first)
    return frame(
      <EmptyState
        title="No STAR projects on this Mac yet."
        body="Run /juel:star in a project, and it shows here."
      />
    )
  return <Navigate to={projectPath(first.name, "needs")} replace />
}
