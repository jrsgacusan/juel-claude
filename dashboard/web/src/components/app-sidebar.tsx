import {
  Images,
  Inbox,
  ListChecks,
  MessageCircle,
  MessageSquare,
  PenLine,
  type LucideIcon,
} from "lucide-react"
import { Link, NavLink } from "react-router"
import { useOverview, useProjects, useSlack } from "@/api/queries"
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
import { needsPath, PAGE_LABELS, type Page, projectPath } from "@/lib/routes"
import { projectStateOf } from "@/lib/status"
import { cn } from "@/lib/utils"
import { AwaySwitch } from "./away-switch"
import { Dot, StarMark } from "./status"
import { WorkersCard } from "./workers-card"

const NAV: Array<{ page: Page; icon: LucideIcon }> = [
  { page: "progress", icon: ListChecks },
  { page: "chat", icon: MessageCircle },
  { page: "slack", icon: MessageSquare },
  { page: "briefing", icon: PenLine },
  { page: "evidence", icon: Images },
]

export function AppSidebar({ project, page }: { project: string; page: Page }) {
  const projects = useProjects()
  const overview = useOverview(project)
  const slack = useSlack()
  const { setOpenMobile } = useSidebar()
  const close = () => setOpenMobile(false)
  const current = projects.data?.find((p) => p.name === project)
  const state = current ? projectStateOf(current.state) : null
  const away = Boolean(overview.data?.away)
  const slackCount =
    slack.data?.routed.filter((m) => m.project === project).length ?? 0
  const combined = project === ""
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
                  {state && (
                    <span
                      className={cn(
                        "flex items-center gap-1.5 text-xs",
                        away ? "text-wait-fg" : "text-muted-foreground"
                      )}
                    >
                      <Dot tone={away ? "wait" : state.tone} pulse={state.pulse} />
                      {`STAR ${state.label.toLowerCase()}${away ? " · you're away" : ""}`}
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
            <SidebarMenu aria-label="Needs you">
              <SidebarMenuItem>
                <SidebarMenuButton asChild isActive={combined}>
                  <NavLink to={needsPath()} onClick={close}>
                    <Inbox />
                    <span>{PAGE_LABELS.needs}</span>
                  </NavLink>
                </SidebarMenuButton>
                {total > 0 && (
                  <SidebarMenuBadge className="rounded-md border border-wait-line bg-wait-bg text-wait-fg">
                    {total}
                  </SidebarMenuBadge>
                )}
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
        {!combined && (
          <SidebarGroup>
            <SidebarGroupContent>
              <SidebarMenu aria-label="Sections">
                {NAV.map(({ page: target, icon: Icon }) => (
                  <SidebarMenuItem key={target}>
                    <SidebarMenuButton asChild isActive={page === target}>
                      <NavLink
                        to={projectPath(project, target)}
                        onClick={close}
                      >
                        <Icon />
                        <span>{PAGE_LABELS[target]}</span>
                      </NavLink>
                    </SidebarMenuButton>
                    {target === "slack" && slackCount > 0 && (
                      <SidebarMenuBadge>{slackCount}</SidebarMenuBadge>
                    )}
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
                      <span className="text-xs text-muted-foreground">
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
