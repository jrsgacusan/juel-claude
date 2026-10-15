import { Check } from "lucide-react"
import { useState } from "react"
import { useParams, useSearchParams } from "react-router"
import { useLoops } from "@/api/queries"
import type { Loop } from "@/api/types"
import { EmptyState, ErrorState, LoadingState } from "@/components/page-state"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Skeleton } from "@/components/ui/skeleton"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
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

export function NeedsPage() {
  const { project = "" } = useParams()
  const loops = useLoops(project)
  const [params, setParams] = useSearchParams()
  const [tab, setTab] = useState<Tab>("all")
  // Answers sent from this page, by loop id, until STAR closes the item.
  const [sent, setSent] = useState<Record<string, string>>({})

  if (loops.isPending) {
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
  if (loops.isError) {
    return (
      <ErrorState
        what="the open loops"
        error={loops.error}
        onRetry={() => void loops.refetch()}
      />
    )
  }
  if (loops.data.length === 0) {
    return (
      <EmptyState
        title="Nothing needs you right now."
        body="When STAR waits on an answer, a go or one of your steps, it shows here."
      />
    )
  }

  const count = (t: Tab) =>
    t === "all"
      ? loops.data.length
      : loops.data.filter((l) => groupOf(l.kind) === t).length
  const list = loops.data.filter(
    (l) => tab === "all" || groupOf(l.kind) === tab
  )
  const selected =
    loops.data.find((l) => l.id === params.get("loop")) ??
    list[0] ??
    loops.data[0]
  const select = (id: string) =>
    setParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        next.set("loop", id)
        return next
      },
      { replace: true }
    )
  const sentOf = (loop: Loop) =>
    sent[loop.id] ?? (isAnswered(loop) ? loop.answer : null)

  return (
    <div className="grid min-h-0 flex-1 md:h-full md:grid-cols-[minmax(300px,380px)_minmax(0,1fr)]">
      <section
        aria-label="Open loops"
        className="flex min-h-0 min-w-0 flex-col border-b md:border-r md:border-b-0"
      >
        <div className="flex flex-col gap-3 p-4 pb-3">
          <div className="flex items-baseline justify-between gap-2">
            <h1 className="text-base font-semibold">Needs you</h1>
            <span className="text-xs text-muted-foreground">
              Blocked work first
            </span>
          </div>
          <Tabs value={tab} onValueChange={(value) => setTab(value as Tab)}>
            <TabsList>
              {TABS.map((t) => (
                <TabsTrigger key={t.id} value={t.id} className="gap-1.5">
                  {t.label}{" "}
                  <span className="text-muted-foreground tabular-nums">
                    {count(t.id)}
                  </span>
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
        </div>
        <ScrollArea className="min-h-0 flex-1">
          <ul className="flex flex-col gap-1 px-2 pb-3">
            {list.map((loop) => {
              const { label, icon: Icon } = kindOf(loop.kind)
              const on = loop.id === selected?.id
              return (
                <li key={loop.id}>
                  <button
                    type="button"
                    onClick={() => select(loop.id)}
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
      </section>
      <section
        aria-label="Answer"
        className="min-h-0 min-w-0 md:overflow-y-auto"
      >
        {selected && (
          <LoopDetail
            key={selected.id}
            project={project}
            loop={selected}
            sentText={sentOf(selected)}
            onSent={(text) => setSent((s) => ({ ...s, [selected.id]: text }))}
          />
        )}
      </section>
    </div>
  )
}
