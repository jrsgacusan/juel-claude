import type { Project } from "@/api/types"
import { projectStateOf } from "@/lib/status"
import { cn } from "@/lib/utils"
import { Dot } from "./status"

/** The dot and "STAR running" / "STAR idle" / "STAR stopped", with " · you're away" when away. */
export function ProjectStateLine({
  project,
  away,
}: {
  project: Project | undefined
  away: boolean
}) {
  if (!project) return null
  const state = projectStateOf(project.state)
  return (
    <span
      className={cn(
        "flex items-center gap-1.5 text-xs",
        away ? "text-wait-fg" : "text-muted-foreground"
      )}
    >
      <Dot tone={away ? "wait" : state.tone} pulse={state.pulse} />
      {`STAR ${state.label.toLowerCase()}${away ? " · you're away" : ""}`}
    </span>
  )
}
