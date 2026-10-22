import { ChevronDown } from "lucide-react"
import { useState } from "react"
import { Link } from "react-router"
import { useOverview, useProjects } from "@/api/queries"
import { Badge } from "@/components/ui/badge"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet"
import { needsPath, projectPath } from "@/lib/routes"
import { projectStateOf } from "@/lib/status"
import { cn } from "@/lib/utils"
import { ProjectStateLine } from "./project-state-line"
import { Dot, StarMark } from "./status"

const rowClass =
  "flex min-h-12 items-center gap-2.5 rounded-lg px-3 text-[15px] outline-none hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50"

/** The phone header's project button, and the bottom sheet it opens. */
export function ProjectSwitcher({ project }: { project: string }) {
  const [open, setOpen] = useState(false)
  const projects = useProjects()
  const overview = useOverview(project)
  const current = projects.data?.find((p) => p.name === project)
  const close = () => setOpen(false)
  const name = project || "All projects"
  const total = (projects.data ?? []).reduce(
    (sum, p) => sum + (typeof p.needsYou === "number" ? p.needsYou : 0),
    0
  )
  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <button
          type="button"
          aria-label={`Switch project, now ${name}`}
          className="flex h-11 min-w-0 items-center gap-2.5 rounded-xl pr-2 pl-1 text-left outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
        >
          <span className="grid size-[30px] shrink-0 place-items-center rounded-[9px] bg-primary text-primary-foreground">
            <StarMark />
          </span>
          <span className="grid min-w-0 leading-tight">
            <span className="truncate text-base font-semibold">{name}</span>
            <ProjectStateLine
              project={current}
              away={Boolean(overview.data?.away)}
            />
          </span>
          <ChevronDown aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
        </button>
      </SheetTrigger>
      <SheetContent
        side="bottom"
        className="max-h-[80dvh] gap-2 rounded-t-2xl px-2 pb-[max(1rem,env(safe-area-inset-bottom))]"
      >
        <SheetHeader>
          <SheetTitle>Switch project</SheetTitle>
          <SheetDescription className="sr-only">
            Pick a project, or all of them.
          </SheetDescription>
        </SheetHeader>
        <ul className="flex flex-col overflow-y-auto">
          <li>
            <Link
              to={needsPath()}
              onClick={close}
              aria-current={project === "" ? "page" : undefined}
              className={cn(rowClass, project === "" && "font-semibold")}
            >
              <span className="flex-1 truncate">All projects</span>
              {total > 0 && (
                <Badge variant="count" aria-label={`${total} need you`}>
                  {total}
                </Badge>
              )}
            </Link>
          </li>
          {projects.data?.map((p) => (
            <li key={p.name}>
              <Link
                to={projectPath(p.name, "progress")}
                onClick={close}
                aria-current={p.name === project ? "page" : undefined}
                className={cn(rowClass, p.name === project && "font-semibold")}
              >
                <Dot tone={projectStateOf(p.state).tone} />
                <span className="flex-1 truncate">{p.name}</span>
                <span className="text-sm font-normal text-muted-foreground">
                  {projectStateOf(p.state).label}
                </span>
                {typeof p.needsYou === "number" && p.needsYou > 0 && (
                  <Badge variant="wait" aria-label={`${p.needsYou} need you`}>
                    {p.needsYou}
                  </Badge>
                )}
              </Link>
            </li>
          ))}
        </ul>
      </SheetContent>
    </Sheet>
  )
}
