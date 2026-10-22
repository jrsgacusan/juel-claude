import { Inbox, ListChecks, MessageCircle, Ellipsis, type LucideIcon } from "lucide-react"
import { Link } from "react-router"
import { useProjects } from "@/api/queries"
import { Badge } from "@/components/ui/badge"
import { useDetailOpen } from "@/lib/chrome"
import { useLastProject } from "@/lib/last-project"
import { needsPath, type Page, projectPath } from "@/lib/routes"
import { cn } from "@/lib/utils"

const linkClass =
  "relative flex min-h-11 flex-col items-center justify-center gap-0.5 rounded-2xl text-xs font-medium text-muted-foreground outline-none focus-visible:ring-3 focus-visible:ring-ring/50 aria-[current=page]:bg-muted aria-[current=page]:font-semibold aria-[current=page]:text-foreground"

/** The phone's floating page bar: links in a nav, never tabs. Hidden while a list-detail page shows its detail. */
export function TabBar({ project, page }: { project: string; page: string }) {
  const projects = useProjects()
  const last = useLastProject()
  const detailOpen = useDetailOpen()
  if (detailOpen) return null
  const names = projects.data?.map((p) => p.name) ?? []
  // On /needs there is no project: use the last-opened one, else the first.
  const target =
    project ||
    (last && names.includes(last) ? last : (names[0] ?? ""))
  const total = (projects.data ?? []).reduce(
    (sum, p) => sum + (typeof p.needsYou === "number" ? p.needsYou : 0),
    0
  )
  const to = (next: Page) => (target ? projectPath(target, next) : needsPath())
  const items: Array<{ page: Page; label: string; icon: LucideIcon; href: string }> = [
    { page: "needs", label: "Needs you", icon: Inbox, href: needsPath() },
    { page: "progress", label: "Progress", icon: ListChecks, href: to("progress") },
    { page: "chat", label: "Chat", icon: MessageCircle, href: to("chat") },
    { page: "more", label: "More", icon: Ellipsis, href: to("more") },
  ]
  return (
    <nav
      aria-label="Pages"
      data-slot="tab-bar"
      className="fixed inset-x-3 bottom-[calc(1.25rem+env(safe-area-inset-bottom))] z-30 grid h-16 grid-cols-4 gap-1 rounded-[22px] border bg-card p-1.5 shadow-lg"
    >
      {items.map(({ page: item, label, icon: Icon, href }) => (
        <Link
          key={item}
          to={href}
          aria-current={page === item ? "page" : undefined}
          className={cn(linkClass)}
        >
          <Icon aria-hidden="true" className="size-[22px]" />
          {label}
          {item === "needs" && total > 0 && (
            <Badge
              variant="count"
              className="absolute top-1 left-[calc(50%+6px)] h-5 min-w-5 px-1.5 font-bold"
            >
              {total}
            </Badge>
          )}
        </Link>
      ))}
    </nav>
  )
}
