import { Search } from "lucide-react"
import { Link } from "react-router"
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb"
import { Button } from "@/components/ui/button"
import { Kbd } from "@/components/ui/kbd"
import { isPage, PAGE_LABELS, projectPath } from "@/lib/routes"
import { AccountsChip } from "./accounts-chip"
import { useNarrow } from "./list-detail"
import { ProjectSwitcher } from "./project-switcher"
import { ThemeButton } from "./theme-button"

export function SiteHeader({
  project,
  page,
  onSearch,
}: {
  project: string
  page: string
  onSearch: () => void
}) {
  const narrow = useNarrow()
  const frame =
    "sticky top-0 z-20 box-content flex h-14 shrink-0 items-center gap-2 border-b bg-background px-3 pt-[env(safe-area-inset-top)] sm:px-4 md:static"
  if (narrow)
    return (
      <header className={frame}>
        <ProjectSwitcher project={project} />
        <div className="ml-auto flex items-center gap-1.5">
          <AccountsChip project={project} />
          <Button
            variant="ghost"
            size="icon"
            onClick={onSearch}
            aria-label="Search (⌘K)"
            className="size-11"
          >
            <Search />
          </Button>
        </div>
      </header>
    )
  return (
    <header className={frame}>
      <Breadcrumb className="min-w-0">
        <BreadcrumbList className="flex-nowrap">
          <BreadcrumbItem className="hidden sm:inline-flex">
            <BreadcrumbLink asChild>
              {project ? (
                <Link to={projectPath(project, "progress")}>{project}</Link>
              ) : (
                <Link to="/needs">All projects</Link>
              )}
            </BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator className="hidden sm:inline-flex" />
          <BreadcrumbItem className="min-w-0">
            <BreadcrumbPage className="truncate">
              {isPage(page) ? PAGE_LABELS[page] : "Not found"}
            </BreadcrumbPage>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>
      <div className="ml-auto flex items-center gap-1.5">
        <Button
          variant="outline"
          size="sm"
          onClick={onSearch}
          aria-label="Search (⌘K)"
          className="h-8 w-8 pointer-coarse:size-11 sm:pointer-coarse:w-64 justify-center gap-2 px-0 font-normal text-muted-foreground sm:w-64 sm:justify-start sm:px-2.5"
        >
          <Search />
          <span className="hidden flex-1 truncate text-left sm:inline">Search</span>
          <Kbd className="hidden sm:inline-flex">⌘K</Kbd>
        </Button>
        <AccountsChip project={project} />
        <ThemeButton />
      </div>
    </header>
  )
}
