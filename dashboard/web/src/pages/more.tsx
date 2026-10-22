import {
  ChevronRight,
  Images,
  MessageSquare,
  PenLine,
} from "lucide-react"
import type { ComponentType, ReactNode } from "react"
import { Link, useParams } from "react-router"
import { activeOf, leftOf, useAccounts } from "@/api/accounts"
import { useOverview, useProjects, useSlack } from "@/api/queries"
import { AwaySwitch } from "@/components/away-switch"
import { Badge } from "@/components/ui/badge"
import { Dot } from "@/components/status"
import { ThemeSwitch } from "@/components/theme-switch"
import { WorkersCard } from "@/components/workers-card"
import { projectPath } from "@/lib/routes"
import { projectStateOf } from "@/lib/status"
import { cn } from "@/lib/utils"

const groupClass = "divide-y overflow-hidden rounded-xl border bg-card px-4"
const rowClass =
  "flex min-h-13 items-center gap-3 text-[15px] outline-none focus-visible:bg-muted"

function Section({
  id,
  title,
  children,
}: {
  id: string
  title: string
  children: ReactNode
}) {
  return (
    <section aria-labelledby={id} className="flex flex-col gap-2">
      <h2 id={id} className="mx-1 text-[15px] font-semibold">
        {title}
      </h2>
      {children}
    </section>
  )
}

function PageLink({
  to,
  icon: Icon,
  label,
  note,
}: {
  to: string
  icon: ComponentType<{ className?: string }>
  label: string
  note?: string
}) {
  return (
    <li>
      <Link to={to} className={rowClass}>
        <Icon className="size-[19px] shrink-0" />
        <span className="flex-1">{label}</span>
        {note && <span className="text-sm text-muted-foreground">{note}</span>}
        <ChevronRight aria-hidden="true" className="size-[18px] shrink-0 text-muted-foreground" />
      </Link>
    </li>
  )
}

/** The phone's last tab: Away, Workers, the project's other pages, the projects and the theme. */
export function MorePage() {
  const { project = "" } = useParams()
  const projects = useProjects()
  const overview = useOverview(project)
  const slack = useSlack()
  const accounts = useAccounts().data
  const current = projects.data?.find((p) => p.name === project)

  const unrouted = slack.data?.unrouted.length ?? 0
  const active = accounts?.installed ? activeOf(accounts) : null
  const left = active ? leftOf(active.sevenDay) : null
  const accountsNote = active
    ? left === null
      ? `${active.alias}, no week reading`
      : `${active.alias}, ${left}% left`
    : undefined

  return (
    <div className="flex min-w-0 flex-col gap-5 p-4 pt-1">
      <h1 className="text-3xl leading-tight font-semibold tracking-tight">More</h1>
      <AwaySwitch
        key={project}
        project={project}
        running={current?.state !== "stopped"}
      />
      {overview.data && <WorkersCard workers={overview.data.workers} />}
      <nav aria-labelledby="more-pages" className="flex flex-col gap-2">
        <h2 id="more-pages" className="mx-1 truncate text-[15px] font-semibold">
          {project}
        </h2>
        <ul className={groupClass}>
          <PageLink
            to={projectPath(project, "slack")}
            icon={MessageSquare}
            label="Slack replies"
            note={unrouted > 0 ? `${unrouted} to route` : undefined}
          />
          <PageLink to={projectPath(project, "briefing")} icon={PenLine} label="Briefing" />
          <PageLink to={projectPath(project, "evidence")} icon={Images} label="Evidence" />
          <PageLink
            to={projectPath(project, "accounts")}
            icon={AccountRing}
            label="Claude accounts"
            note={accountsNote}
          />
        </ul>
      </nav>
      <nav aria-labelledby="more-projects" className="flex flex-col gap-2">
        <h2 id="more-projects" className="mx-1 text-[15px] font-semibold">
          Projects
        </h2>
        <ul className={groupClass}>
          {projects.data?.map((p) => (
            <li key={p.name}>
              <Link
                to={projectPath(p.name, "more")}
                aria-current={p.name === project ? "page" : undefined}
                className={cn(rowClass, "gap-2.5")}
              >
                <Dot tone={projectStateOf(p.state).tone} />
                <span
                  className={cn(
                    "flex-1 truncate",
                    p.name === project && "font-semibold"
                  )}
                >
                  {p.name}
                </span>
                <span
                  className={cn(
                    "text-sm text-muted-foreground",
                    p.state === "stopped" && "font-medium text-stop-fg"
                  )}
                >
                  {projectStateOf(p.state).label}
                </span>
                {typeof p.needsYou === "number" && p.needsYou > 0 && (
                  <Badge variant="count" aria-label={`${p.needsYou} need you`}>
                    {p.needsYou}
                  </Badge>
                )}
              </Link>
            </li>
          ))}
        </ul>
      </nav>
      <Section id="more-appearance" title="Appearance">
        <div role="group" aria-labelledby="more-appearance">
          <ThemeSwitch />
        </div>
      </Section>
    </div>
  )
}

function AccountRing({ className }: { className?: string }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 18 18" className={className}>
      <circle cx="9" cy="9" r="7" fill="none" stroke="var(--border)" strokeWidth="2.5" />
      <circle
        cx="9"
        cy="9"
        r="7"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
        strokeDasharray="23.8 44"
        transform="rotate(-90 9 9)"
      />
    </svg>
  )
}
