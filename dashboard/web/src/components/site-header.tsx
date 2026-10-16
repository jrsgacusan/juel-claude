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
import { Separator } from "@/components/ui/separator"
import { SidebarTrigger } from "@/components/ui/sidebar"
import { isPage, PAGE_LABELS, projectPath } from "@/lib/routes"
import { ThemeSwitch } from "./theme-switch"

export function SiteHeader({
  project,
  page,
  onSearch,
}: {
  project: string
  page: string
  onSearch: () => void
}) {
  return (
    <header className="flex h-14 shrink-0 items-center gap-2 border-b px-3 sm:px-4">
      <SidebarTrigger className="md:hidden" aria-label="Open the menu" />
      <Separator
        orientation="vertical"
        className="mr-1 data-[orientation=vertical]:h-4 md:hidden"
      />
      <Breadcrumb className="min-w-0">
        <BreadcrumbList className="flex-nowrap">
          <BreadcrumbItem className="hidden sm:inline-flex">
            <BreadcrumbLink asChild>
              <Link to={projectPath(project, "needs")}>{project}</Link>
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
          className="h-8 w-28 justify-start gap-2 px-2.5 font-normal text-muted-foreground sm:w-64"
        >
          <Search />
          <span className="flex-1 truncate text-left">Search</span>
          <Kbd className="hidden sm:inline-flex">⌘K</Kbd>
        </Button>
        <ThemeSwitch />
      </div>
    </header>
  )
}
