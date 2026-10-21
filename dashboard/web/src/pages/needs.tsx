import { Check } from "lucide-react"
import { useState } from "react"
import { useSearchParams } from "react-router"
import { useAllLoops } from "@/api/queries"
import type { ProjectLoop } from "@/api/types"
import {
  EmptyState,
  ErrorState,
  LoadingState,
  queryFailed,
  RefreshNotice,
  refreshFailed,
} from "@/components/page-state"
import { CountTabs } from "@/components/count-tabs"
import { ListDetail, useListSelection } from "@/components/list-detail"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import { age } from "@/lib/format"
import { groupOf, isAnswered, kindOf, type LoopGroup } from "@/lib/loops"
import { cn } from "@/lib/utils"
import { LoopDetail } from "./needs-detail"

type Tab = "all" | LoopGroup
const TABS: Array<{ id: Tab; label: string }> = [
  { id: "all", label: "All" },
  { id: "blocked", label: "Blocked" },
  { id: "slack", label: "Slack" },
  { id: "others", label: "Others" },
]

const keyOf = (loop: ProjectLoop) => `${loop.project}/${loop.id}`

export function NeedsPage() {
  const [params, setParams] = useSearchParams()
  const project = params.get("project") ?? ""
  const all = useAllLoops()
  const { value: loopParam, select, back } = useListSelection("loop")
  const [tab, setTab] = useState<Tab>("all")
  // Answers sent from this page, by loop id, until STAR closes the item.
  const [sent, setSent] = useState<
    Record<string, { text: string; nudged: boolean }>
  >({})

  if (all.isPending) {
    return (
      <LoadingState label="the open loops">
        <div className="grid gap-4 md:grid-cols-[minmax(300px,380px)_minmax(0,1fr)]">
          <div className="flex flex-col gap-2">
            <Skeleton className="h-9 w-64" />
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} className="h-16 w-full" />
            ))}
          </div>
          <div className="flex flex-col gap-4">
            <Skeleton className="h-8 w-3/4" />
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-32 w-full" />
          </div>
        </div>
      </LoadingState>
    )
  }
  if (queryFailed(all)) {
    return (
      <ErrorState
        what="the open loops"
        error={all.error}
        onRetry={() => void all.refetch()}
      />
    )
  }
  if (all.data!.length === 0) {
    return (
      <>
        {refreshFailed(all) && (
          <RefreshNotice
            what="the open loops"
            error={all.error}
            onRetry={() => void all.refetch()}
          />
        )}
        <EmptyState
          title="Nothing needs you right now."
          body="When STAR waits on one of your steps, a draft or a Slack reply, it shows here."
        />
      </>
    )
  }

  const scoped = all.data!.filter((l) => !project || l.project === project)
  const count = (t: Tab) =>
    t === "all" ? scoped.length : scoped.filter((l) => groupOf(l.kind) === t).length
  const list = scoped.filter((l) => tab === "all" || groupOf(l.kind) === tab)
  // A link may name a bare loop id (a search result, the progress sheet): it means the filtered project's.
  const named =
    scoped.find((l) => keyOf(l) === loopParam) ??
    (project ? scoped.find((l) => l.id === loopParam) : undefined)
  const selected = named ?? list[0] ?? scoped[0]
  const showDetail = named !== undefined
  const sentOf = (loop: ProjectLoop) =>
    sent[keyOf(loop)]?.text ?? (isAnswered(loop) ? loop.answer : null)
  const clearFilter = () =>
    setParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        next.delete("project")
        return next
      },
      { replace: true }
    )

  return (
    <>
      {refreshFailed(all) && (
        <RefreshNotice
          what="the open loops"
          error={all.error}
          onRetry={() => void all.refetch()}
        />
      )}
      <ListDetail
        showDetail={showDetail}
        onBack={back}
        backLabel="Needs you"
        listLabel="Open loops"
        detailLabel="Answer"
        columns="md:grid-cols-[minmax(300px,380px)_minmax(0,1fr)]"
        list={
          <>
            <div className="flex flex-col gap-3 p-4 pb-3">
              <div className="flex items-baseline justify-between gap-2">
                <h1 className="text-base font-semibold">Needs you</h1>
                <span className="text-xs text-muted-foreground">
                  Blocked work first
                </span>
              </div>
              {project && (
                <div className="flex items-center justify-between gap-2 text-xs text-muted-foreground">
                  <span className="min-w-0 truncate">
                    Only {project}
                  </span>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-7 px-2 pointer-coarse:h-11"
                    onClick={clearFilter}
                  >
                    Show every project
                  </Button>
                </div>
              )}
              <CountTabs
                tabs={TABS}
                value={tab}
                onChange={setTab}
                count={count}
              />
            </div>
            <ScrollArea className="min-h-0 flex-1">
              {list.length === 0 && (
                <p className="px-4 py-6 text-center text-sm text-muted-foreground">
                  Nothing here.
                </p>
              )}
              <ul
                key={tab}
                className="motion-fade-in flex flex-col gap-1 px-2 pb-3"
              >
                {list.map((loop) => {
                  const { label, icon: Icon } = kindOf(loop.kind)
                  const on = selected !== undefined && keyOf(loop) === keyOf(selected)
                  return (
                    <li key={keyOf(loop)}>
                      <button
                        type="button"
                        onClick={() => select(keyOf(loop))}
                        aria-current={on ? "true" : undefined}
                        className={cn(
                          "flex w-full min-w-0 flex-col gap-1.5 rounded-lg border px-3 py-2.5 text-left transition-colors",
                          on
                            ? "border-border bg-card shadow-sm"
                            : "border-transparent hover:bg-muted"
                        )}
                      >
                        <span className="flex min-w-0 items-center gap-2 text-xs text-muted-foreground">
                          <Icon className="size-3.5 shrink-0" />
                          <span className="shrink-0">{label}</span>
                          <Badge variant="outline" className="shrink-0">
                            {loop.project}
                          </Badge>
                          <span
                            className={cn(
                              "truncate font-mono",
                              loop.askedAt === null && "ml-auto"
                            )}
                          >
                            {loop.item}
                          </span>
                          {loop.askedAt !== null && (
                            <span className="ml-auto shrink-0 tabular-nums">
                              {age(loop.askedAt)}
                            </span>
                          )}
                        </span>
                        <span className="line-clamp-2 text-sm leading-snug font-medium break-words">
                          {loop.title}
                        </span>
                        {sentOf(loop) && (
                          <Badge variant="done">
                            <Check className="size-3" />
                            Sent to STAR
                          </Badge>
                        )}
                      </button>
                    </li>
                  )
                })}
              </ul>
            </ScrollArea>
          </>
        }
        detail={
          selected && (
            <LoopDetail
              key={keyOf(selected)}
              project={selected.project}
              loop={selected}
              sentText={sent[keyOf(selected)]?.text ?? null}
              sentNudged={sent[keyOf(selected)]?.nudged}
              serverAnswer={sent[keyOf(selected)] ? null : selected.answer}
              onSent={(text, nudged) =>
                setSent((s) => ({ ...s, [keyOf(selected)]: { text, nudged } }))
              }
            />
          )
        }
      />
    </>
  )
}
