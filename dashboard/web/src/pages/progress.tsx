import { GitPullRequest, Search } from "lucide-react"
import { useState } from "react"
import { useParams, useSearchParams } from "react-router"
import { useItems, useOverview } from "@/api/queries"
import type { ItemRow } from "@/api/types"
import { EmptyState, ErrorState, LoadingState } from "@/components/page-state"
import { Dot, StateBadge } from "@/components/status"
import { Badge } from "@/components/ui/badge"
import { Card } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Skeleton } from "@/components/ui/skeleton"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { age, dayLabel } from "@/lib/format"
import { prLabel, type ProgressTab, stepText, TAB_OF } from "@/lib/status"
import { ItemSheet } from "./progress-sheet"

const TABS: Array<{ id: ProgressTab; label: string }> = [
  { id: "all", label: "All" },
  { id: "needs", label: "Needs you" },
  { id: "running", label: "Running" },
  { id: "merged", label: "Merged" },
]

const matches = (row: ItemRow, q: string) =>
  !q ||
  `${row.ref ?? ""} ${row.item} ${row.title}`
    .toLowerCase()
    .includes(q.trim().toLowerCase())

export function ProgressPage() {
  const { project = "" } = useParams()
  const items = useItems(project)
  const overview = useOverview(project)
  const [params, setParams] = useSearchParams()
  const [tab, setTab] = useState<ProgressTab>("all")
  const [q, setQ] = useState("")
  const open = params.get("item")
  const setOpen = (item: string | null) =>
    setParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        if (item) next.set("item", item)
        else next.delete("item")
        return next
      },
      { replace: item === null }
    )

  if (items.isPending) {
    return (
      <LoadingState label="the items">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {[0, 1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-24" />
          ))}
        </div>
        <Skeleton className="h-72 w-full" />
      </LoadingState>
    )
  }
  if (items.isError)
    return (
      <ErrorState
        what="the items"
        error={items.error}
        onRetry={() => void items.refetch()}
      />
    )
  if (items.data.length === 0) {
    return (
      <EmptyState
        title="No items yet."
        body="Items show here once STAR takes work: type /juel:star <brief> in the project."
      />
    )
  }

  const all = items.data
  const by = (status: ItemRow["status"]) =>
    all.filter((r) => r.status === status)
  const building = by("building").length
  const inReview = by("in-review").length
  const mergedToday = by("merged").filter(
    (r) => r.updated && dayLabel(r.updated) === "Today"
  )
  const waiting = all.filter((r) => TAB_OF[r.status] === "needs").length
  const [busy, slots] = overview.data?.workers.build ?? [0, 0]
  const count = (t: ProgressTab) =>
    t === "all" ? all.length : all.filter((r) => TAB_OF[r.status] === t).length
  const rows = all.filter(
    (r) => (tab === "all" || TAB_OF[r.status] === tab) && matches(r, q)
  )
  const cards: Array<[label: string, value: string, sub: string]> = [
    [
      "Build slots",
      `${busy} of ${slots}`,
      slots > 0 && busy >= slots
        ? "All busy"
        : `${Math.max(0, slots - busy)} free`,
    ],
    ["Waiting on you", String(waiting), "Answers, approvals and stops"],
    ["In review", String(inReview), "Hosted review or an approval"],
    [
      "Merged today",
      String(mergedToday.length),
      mergedToday
        .map((r) => prLabel(r))
        .filter(Boolean)
        .join(", ") || "None yet",
    ],
  ]
  const gateDown = overview.data?.gateDown

  return (
    <div className="min-h-0 min-w-0 flex-1 md:overflow-y-auto">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 p-4 sm:p-6 lg:p-8">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
              Progress
            </h1>
            <p className="text-sm text-muted-foreground">{`${building} building, ${inReview} in review, ${mergedToday.length} merged today`}</p>
          </div>
          {overview.data &&
            (gateDown ? (
              <Badge variant="stop">
                <Dot tone="stop" />
                Review gate down: {gateDown.why}
              </Badge>
            ) : (
              <Badge variant="outline">
                <Dot tone="done" />
                Review gate up
              </Badge>
            ))}
        </div>
        <section
          aria-label="Summary"
          className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
        >
          {cards.map(([label, value, sub]) => (
            <Card key={label} className="gap-1 p-4">
              <span className="text-sm text-muted-foreground">{label}</span>
              <span className="text-2xl font-semibold tracking-tight tabular-nums">
                {value}
              </span>
              <span className="text-xs text-muted-foreground">{sub}</span>
            </Card>
          ))}
        </section>
        <Card className="gap-0 overflow-hidden p-0">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b p-3">
            <Tabs value={tab} onValueChange={(v) => setTab(v as ProgressTab)}>
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
            <div className="relative w-full sm:w-60">
              <Search className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                aria-label="Filter items"
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="Filter by ref or title"
                className="h-8 pl-8"
              />
            </div>
          </div>
          <div className="overflow-x-auto">
            <Table className="min-w-[720px]">
              <TableHeader>
                <TableRow>
                  <TableHead className="px-4">Item</TableHead>
                  <TableHead className="px-4">Status</TableHead>
                  <TableHead className="px-4">Current step</TableHead>
                  <TableHead className="px-4">PR</TableHead>
                  <TableHead className="px-4 text-right">Updated</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((row) => {
                  const pr = prLabel(row)
                  return (
                    <TableRow
                      key={row.item}
                      className="cursor-pointer"
                      onClick={() => setOpen(row.item)}
                    >
                      <TableCell className="px-4 py-3">
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation()
                            setOpen(row.item)
                          }}
                          className="flex flex-col rounded-sm text-left focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
                        >
                          <span className="font-mono text-xs text-muted-foreground">
                            {row.ref ?? row.item}
                          </span>
                          <span className="font-medium">{row.title}</span>
                        </button>
                      </TableCell>
                      <TableCell className="px-4 py-3">
                        <StateBadge status={row.status} />
                      </TableCell>
                      <TableCell className="max-w-[280px] truncate px-4 py-3 text-muted-foreground">
                        {stepText(row.step)}
                      </TableCell>
                      <TableCell className="px-4 py-3">
                        {pr ? (
                          <span className="inline-flex items-center gap-1.5 font-mono text-xs">
                            <GitPullRequest className="size-3.5 text-muted-foreground" />
                            {pr}
                          </span>
                        ) : (
                          <span className="text-xs text-muted-foreground">
                            None yet
                          </span>
                        )}
                      </TableCell>
                      <TableCell className="px-4 py-3 text-right text-muted-foreground tabular-nums">
                        {age(row.updated)}
                      </TableCell>
                    </TableRow>
                  )
                })}
                {rows.length === 0 && (
                  <TableRow>
                    <TableCell
                      colSpan={5}
                      className="px-4 py-10 text-center text-sm text-muted-foreground"
                    >
                      {q ? `No items match "${q}".` : "No items in this tab."}
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </Card>
      </div>
      <ItemSheet project={project} item={open} onClose={() => setOpen(null)} />
    </div>
  )
}
