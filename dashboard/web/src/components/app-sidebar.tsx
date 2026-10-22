import {
  Images,
  Inbox,
  ListChecks,
  MessageCircle,
  PenLine,
  type LucideIcon,
} from "lucide-react"
import { Link, NavLink } from "react-router"
import { useOverview, useProjects } from "@/api/queries"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSkeleton,
  SidebarSeparator,
  useSidebar,
} from "@/components/ui/sidebar"
import { Badge } from "@/components/ui/badge"
import { useLastProject } from "@/lib/last-project"
import { needsPath, PAGE_LABELS, type Page, projectPath } from "@/lib/routes"
import { projectStateOf } from "@/lib/status"
import { cn } from "@/lib/utils"
import { AwaySwitch } from "./away-switch"
import { ProjectStateLine } from "./project-state-line"
import { Dot, StarMark } from "./status"
import { WorkersCard } from "./workers-card"

const NAV: Array<{ page: Page; icon: LucideIcon }> = [
  { page: "progress", icon: ListChecks },
  { page: "chat", icon: MessageCircle },
  { page: "briefing", icon: PenLine },
  { page: "evidence", icon: Images },
]

export function AppSidebar({ project, page }: { project: string; page: Page }) {
  const projects = useProjects()
  const overview = useOverview(project)
  const { setOpenMobile } = useSidebar()
  const close = () => setOpenMobile(false)
  const current = projects.data?.find((p) => p.name === project)
  const away = Boolean(overview.data?.away)
  const combined = project === ""
  const last = useLastProject()
  const names = projects.data?.map((p) => p.name) ?? []
  // On /needs there is no project: keep the last-opened one's pages, else the first project's.
  const sectionsProject = combined
    ? last && names.includes(last)
      ? last
      : (names[0] ?? "")
    : project
  const total = (projects.data ?? []).reduce(
    (sum, p) => sum + (typeof p.needsYou === "number" ? p.needsYou : 0),
    0
  )

  return (
    <Sidebar variant="inset">
      <SidebarHeader>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton size="lg" asChild>
              <Link
                to={combined ? "/needs" : projectPath(project, "progress")}
                onClick={close}
              >
                <span className="grid size-8 place-items-center rounded-lg bg-primary text-primary-foreground">
                  <StarMark />
                </span>
                <span className="grid min-w-0 flex-1 leading-tight">
                  <span className="truncate text-sm font-semibold">
                    {combined ? "All projects" : project}
                  </span>
                  <ProjectStateLine project={current} away={away} />
                </span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu aria-label="Needs you">
              <SidebarMenuItem>
                <SidebarMenuButton asChild isActive={combined}>
                  <NavLink to={needsPath()} onClick={close}>
                    <Inbox />
                    <span>{PAGE_LABELS.needs}</span>
                  </NavLink>
                </SidebarMenuButton>
                {total > 0 && (
                  <Badge
                    variant="count"
                    className="pointer-events-none absolute top-1.5 right-1 h-5 min-w-5 rounded-md px-1"
                  >
                    {total}
                  </Badge>
                )}
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
        {sectionsProject !== "" && (
          <SidebarGroup>
            <SidebarGroupLabel asChild>
              <h2>{sectionsProject}</h2>
            </SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu aria-label="Sections">
                {NAV.map(({ page: target, icon: Icon }) => (
                  <SidebarMenuItem key={target}>
                    <SidebarMenuButton
                      asChild
                      isActive={!combined && page === target}
                    >
                      <NavLink
                        to={projectPath(sectionsProject, target)}
                        onClick={close}
                      >
                        <Icon />
                        <span>{PAGE_LABELS[target]}</span>
                      </NavLink>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
        )}
        <SidebarSeparator />
        <SidebarGroup>
          <SidebarGroupLabel>Projects</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu aria-label={projects.data ? "Projects" : undefined}>
              {projects.isPending &&
                [0, 1, 2].map((i) => (
                  <SidebarMenuItem key={i}>
                    <SidebarMenuSkeleton showIcon />
                  </SidebarMenuItem>
                ))}
              {projects.data?.map((p) => (
                <SidebarMenuItem key={p.name}>
                  <SidebarMenuButton
                    asChild
                    isActive={p.name === project}
                  >
                    <Link
                      to={projectPath(
                        p.name,
                        combined || page === "needs" ? "progress" : page
                      )}
                      onClick={close}
                    >
                      <Dot tone={projectStateOf(p.state).tone} />
                      <span className="flex-1 truncate">{p.name}</span>
                      <span
                        className={cn(
                          "text-xs text-muted-foreground",
                          p.state === "running" && "sr-only"
                        )}
                      >
                        {projectStateOf(p.state).label}
                      </span>
                      {typeof p.needsYou === "number" && p.needsYou > 0 && (
                        <span
                          aria-label={`${p.needsYou} need you`}
                          className="rounded-md border border-wait-line bg-wait-bg px-1.5 text-xs font-medium text-wait-fg tabular-nums"
                        >
                          {p.needsYou}
                        </span>
                      )}
                    </Link>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
            {projects.isError && (
              <p className="px-2 text-xs text-muted-foreground">
                Couldn't load the projects.
              </p>
            )}
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
      {overview.isError && !overview.data ? (
        <SidebarFooter>
          <p className="px-2 text-xs text-muted-foreground">
            Couldn&apos;t load the workers.
          </p>
        </SidebarFooter>
      ) : (
        overview.data && (
          <SidebarFooter>
            <WorkersCard workers={overview.data.workers} />
            <AwaySwitch
              key={project}
              project={project}
              // Only a stopped STAR misses the switch: an idle one wakes on the nudge (I-7), and while the
              // projects still load nothing says it stopped.
              running={current?.state !== "stopped"}
            />
          </SidebarFooter>
        )
      )}
    </Sidebar>
  )
}
