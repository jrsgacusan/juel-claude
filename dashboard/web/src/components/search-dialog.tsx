import type { LucideIcon } from "lucide-react"
import {
  GitPullRequest,
  Image,
  Inbox,
  MessageSquare,
  PenLine,
  Scale,
  Search,
} from "lucide-react"
import { useState } from "react"
import { useNavigate } from "react-router"
import { useSearch } from "@/api/queries"
import type { SearchResult } from "@/api/types"
import {
  Command,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "@/components/ui/dialog"
import { Kbd } from "@/components/ui/kbd"
import { Switch } from "@/components/ui/switch"
import { errorMessage } from "@/lib/errors"
import { useDebounced } from "@/lib/use-debounced"
import { Highlight } from "./highlight"
const GROUP_ICONS: Record<string, LucideIcon> = {
  Items: GitPullRequest,
  "Needs you": Inbox,
  Decisions: Scale,
  Slack: MessageSquare,
  Briefings: PenLine,
  Evidence: Image,
}
export function resultPath(result: SearchResult): string {
  return result.route.startsWith("/")
    ? result.route
    : `/${encodeURIComponent(result.project)}/${result.route}`
}
export function SearchDialog({
  open,
  onOpenChange,
  project,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  project: string
}) {
  const [query, setQuery] = useState("")
  const [all, setAll] = useState(false)
  const q = useDebounced(query, 150).trim()
  const search = useSearch(q, all, project)
  const navigate = useNavigate()
  const results = q ? (search.data ?? []) : []
  const groups = [...new Set(results.map((r) => r.group))]
  const openResult = (result: SearchResult) => {
    onOpenChange(false)
    void navigate(resultPath(result))
  }
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className="top-[6dvh] translate-y-0 overflow-hidden p-0 sm:max-w-xl md:top-[12dvh]"
        showCloseButton={false}
      >
        <DialogTitle className="sr-only">Search</DialogTitle>
        <DialogDescription className="sr-only">
          Search items, decisions, Slack, briefings and evidence
        </DialogDescription>
        {/* cmdk would filter again what the server already matched (brief D8). */}
        <Command shouldFilter={false} className="rounded-none">
          <CommandInput
            value={query}
            onValueChange={setQuery}
            placeholder="Search items, decisions, Slack, briefings and evidence"
          />
          <div className="flex justify-end border-b px-3 py-1.5 text-xs text-muted-foreground">
            <label className="flex items-center gap-2 pointer-coarse:min-h-11">
              Every project
              <Switch
                checked={all}
                onCheckedChange={setAll}
                aria-label="Search every project"
              />
            </label>
          </div>
          <CommandList className="max-h-[40dvh] md:max-h-[52dvh]">
            {!q && (
              <p className="px-3 py-8 text-center text-sm text-muted-foreground">
                Type to search {all ? "every project" : project}.
              </p>
            )}
            {q && search.isError && (
              <p
                role="alert"
                className="px-3 py-8 text-center text-sm text-stop-fg"
              >
                Search failed: {errorMessage(search.error)}
              </p>
            )}
            {q && search.isSuccess && results.length === 0 && (
              <p className="px-3 py-8 text-center text-sm text-muted-foreground">
                Nothing matches "{q}". Try a ref like SPH-11 or part of a file
                name.
              </p>
            )}
            {groups.map((group) => {
              const Icon = GROUP_ICONS[group] ?? Search
              return (
                <CommandGroup key={group} heading={group}>
                  {results
                    .filter((r) => r.group === group)
                    .map((r) => {
                      const value = `${r.project}\u0000${r.group}\u0000${r.ref}\u0000${r.title}`
                      return (
                        <CommandItem
                          key={value}
                          value={value}
                          onSelect={() => openResult(r)}
                        >
                          <Icon className="text-muted-foreground" />
                          <span className="flex min-w-0 flex-1 flex-col">
                            <span className="truncate">
                              <Highlight text={r.title} query={q} />
                            </span>
                            <span className="truncate text-xs text-muted-foreground">
                              <Highlight text={r.sub} query={q} />
                              {r.project !== project ? `, in ${r.project}` : ""}
                            </span>
                          </span>
                          <span className="font-mono text-xs text-muted-foreground">
                            {r.ref}
                          </span>
                        </CommandItem>
                      )
                    })}
                </CommandGroup>
              )
            })}
          </CommandList>
          <div
            data-slot="search-hints"
            className="flex items-center gap-3 border-t px-3 py-2 text-xs text-muted-foreground pointer-coarse:hidden"
          >
            <span className="flex items-center gap-1">
              <Kbd>↑</Kbd>
              <Kbd>↓</Kbd>Move
            </span>
            <span className="flex items-center gap-1">
              <Kbd>↵</Kbd>Open
            </span>
          </div>
        </Command>
      </DialogContent>
    </Dialog>
  )
}
