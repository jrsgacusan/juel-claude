import { Images, Inbox, ListChecks, MessageSquare, PenLine } from "lucide-react"
import { Link, NavLink } from "react-router"
import { useOverview, useProjects, useSlack } from "@/api/queries"
import { Progress } from "@/components/ui/progress"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSkeleton,
  SidebarSeparator,
  useSidebar,
} from "@/components/ui/sidebar"
import { type Page, projectPath } from "@/lib/routes"
import { PROJECT_STATE } from "@/lib/status"
import { Dot, StarMark } from "./status"

const NAV: Array<{ page: Page; label: string; icon: typeof Inbox }> = [
  { page: "needs", label: "Needs you", icon: Inbox },
  { page: "progress", label: "Progress", icon: ListChecks },
  { page: "slack", label: "Slack replies", icon: MessageSquare },
  { page: "briefing", label: "Briefing", icon: PenLine },
  { page: "evidence", label: "Evidence", icon: Images },
]

export function AppSidebar({ project, page }: { project: string; page: Page }) {
  const projects = useProjects()
  const overview = useOverview(project)
  const slack = useSlack()
  const { setOpenMobile } = useSidebar()
  const close = () => setOpenMobile(false)
  const current = projects.data?.find((p) => p.name === project)
  const state = current ? PROJECT_STATE[current.state] : null
  const slackCount =
    slack.data?.routed.filter((m) => m.project === project).length ?? 0
  const workers = overview.data?.workers
  const pools = workers
    ? ([
        ["Briefing", workers.brief],
        ["Building", workers.build],
        ["Review", workers.babysit],
      ] as const)
    : []

  return (
    <Sidebar variant="inset">
      <SidebarHeader>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton size="lg" asChild>
              <Link to={projectPath(project, "needs")} onClick={close}>
                <span className="grid size-8 place-items-center rounded-lg bg-primary text-primary-foreground">
                  <StarMark />
                </span>
                <span className="grid min-w-0 flex-1 leading-tight">
                  <span className="truncate text-sm font-semibold">
                    {project}
                  </span>
                  {state && (
                    <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
                      <Dot tone={state.tone} pulse={state.pulse} />
                      STAR {state.label.toLowerCase()}
                    </span>
                  )}
                </span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu aria-label="Sections">
              {NAV.map(({ page: target, label, icon: Icon }) => (
                <SidebarMenuItem key={target}>
                  <SidebarMenuButton asChild isActive={page === target}>
                    <NavLink to={projectPath(project, target)} onClick={close}>
                      <Icon />
                      <span>{label}</span>
                    </NavLink>
                  </SidebarMenuButton>
                  {target === "needs" && current && current.needsYou > 0 && (
                    <SidebarMenuBadge className="rounded-md border border-wait-line bg-wait-bg text-wait-fg">
                      {current.needsYou}
                    </SidebarMenuBadge>
                  )}
                  {target === "slack" && slackCount > 0 && (
                    <SidebarMenuBadge>{slackCount}</SidebarMenuBadge>
                  )}
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
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
                  <SidebarMenuButton asChild isActive={p.name === project}>
                    <Link to={projectPath(p.name, page)} onClick={close}>
                      <Dot tone={PROJECT_STATE[p.state].tone} />
                      <span className="flex-1 truncate">{p.name}</span>
                      <span className="text-xs text-muted-foreground">
                        {PROJECT_STATE[p.state].label}
                      </span>
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
      {pools.length > 0 && (
        <SidebarFooter>
          <div className="flex flex-col gap-3 rounded-lg border bg-background p-3">
            <div className="flex items-center justify-between gap-2">
              <span className="text-xs font-medium">Workers</span>
              {overview.data?.resume.next && (
                <span className="text-xs text-muted-foreground">
                  {overview.data.resume.next}
                </span>
              )}
            </div>
            {pools.map(([label, [n, max]]) => (
              <div key={label} className="flex flex-col gap-1.5">
                <div className="flex justify-between text-xs">
                  <span>{label}</span>
                  <span className="text-muted-foreground tabular-nums">
                    {n} of {max}
                  </span>
                </div>
                <Progress
                  value={max > 0 ? (n / max) * 100 : 0}
                  aria-label={`${label}: ${n} of ${max}`}
                  className="h-1.5"
                />
              </div>
            ))}
          </div>
        </SidebarFooter>
      )}
    </Sidebar>
  )
}
