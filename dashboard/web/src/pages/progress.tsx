import { GitPullRequest, Search } from "lucide-react"
import { useState, useSyncExternalStore } from "react"
import { useParams } from "react-router"
import { useItems, useOverview } from "@/api/queries"
import type { ItemRow } from "@/api/types"
import {
  EmptyState,
  ErrorState,
  LoadingState,
  queryFailed,
  RefreshNotice,
  refreshFailed,
} from "@/components/page-state"
import { CountTabs } from "@/components/count-tabs"
import { Dot, StateBadge } from "@/components/status"
import { Badge } from "@/components/ui/badge"
import { Pager } from "@/components/pager"
import { Button } from "@/components/ui/button"
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
import { age, dayLabel } from "@/lib/format"
import { itemLabel } from "@/lib/items"
import { usePage } from "@/lib/paginate"
import { prLabel, type ProgressTab, stepText, TAB_OF } from "@/lib/status"
import { useSearchParam } from "@/lib/use-search-param"
import { cn } from "@/lib/utils"
import { ItemSheet } from "./progress-sheet"

const TABS: Array<{ id: ProgressTab; label: string }> = [
  { id: "running", label: "Running" },
  { id: "all", label: "All" },
  { id: "needs", label: "Needs you" },
  { id: "merged", label: "Merged" },
]

const matches = (row: ItemRow, q: string) =>
  !q ||
  `${row.ref ?? ""} ${row.item} ${row.title ?? ""}`
    .toLowerCase()
    .includes(q.trim().toLowerCase())

export function ProgressPage() {
  const { project = "" } = useParams()
  const items = useItems(project)
  const overview = useOverview(project)
  const [itemParam, setItemParam] = useSearchParam("item")
  const [tab, setTab] = useState<ProgressTab>("running")
  const [q, setQ] = useState("")
  const open = itemParam
  const setOpen = (item: string | null) =>
    setItemParam(item, { replace: item === null })

  if (items.isPending) {
    return (
      <LoadingState label="the items">
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          {[0, 1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-24" />
          ))}
        </div>
        <Skeleton className="h-72 w-full" />
      </LoadingState>
    )
  }
  if (queryFailed(items))
    return (
      <ErrorState
        what="the items"
        error={items.error}
        onRetry={() => void items.refetch()}
      />
    )
  if (items.data!.length === 0) {
    return (
      <>
        {refreshFailed(items) && (
          <RefreshNotice
            what="the items"
            error={items.error}
            onRetry={() => void items.refetch()}
          />
        )}
        <EmptyState
          title="No items yet."
          body="Items show here once STAR takes work: type /juel:star <brief> in the project."
        />
      </>
    )
  }

  const all = items.data!
  const by = (status: ItemRow["status"]) =>
    all.filter((r) => r.status === status)
  const building = by("building").length
  const inReview = by("in-review").length
  const mergedToday = by("merged").filter(
    (r) => r.updated && dayLabel(r.updated) === "Today"
  )
  const waiting = all.filter((r) => TAB_OF[r.status] === "needs").length
  const overviewFailed = queryFailed(overview) || refreshFailed(overview)
  const [busy, slots] = overview.data?.workers.build ?? [0, 0]
  const count = (t: ProgressTab) =>
    t === "all" ? all.length : all.filter((r) => TAB_OF[r.status] === t).length
  const cards: Array<[label: string, value: string, sub: string]> = [
    [
      "Build slots",
      overviewFailed ? "–" : `${busy} of ${slots}`,
      overviewFailed
        ? "Couldn't load the workers"
        : slots > 0 && busy >= slots
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
    <>
      {refreshFailed(items) && (
        <RefreshNotice
          what="the items"
          error={items.error}
          onRetry={() => void items.refetch()}
        />
      )}
      {refreshFailed(overview) && (
        <RefreshNotice
          what="the workers"
          error={overview.error}
          onRetry={() => void overview.refetch()}
        />
      )}
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
              !overviewFailed &&
              (gateDown ? (
                <Badge variant="stop" wrap>
                  <Dot tone="stop" />
                  Review gate down{gateDown.why ? `: ${gateDown.why}` : ""}
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
            className="grid grid-cols-2 gap-3 lg:grid-cols-4"
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
              <CountTabs
                tabs={TABS}
                value={tab}
                onChange={setTab}
                count={count}
              />
              <div className="relative w-full sm:w-60">
                <Search className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  aria-label="Filter items"
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  placeholder="Filter by ref or title"
                  className="h-8 pl-8 pointer-coarse:h-11"
                />
              </div>
            </div>
            <ItemList
              all={all}
              tab={tab}
              q={q}
              onOpen={setOpen}
              onShowAll={() => setTab("all")}
            />
          </Card>
        </div>
        <ItemSheet
          project={project}
          item={open}
          onClose={() => setOpen(null)}
        />
      </div>
    </>
  )
}

const NONE: ReadonlySet<string> = new Set()

/** The `item` names that appeared or changed status in the latest `all`; empty on the first render and whenever `view` changes. */
function useFreshRows(
  all: readonly ItemRow[],
  view: string
): ReadonlySet<string> {
  const [seen, setSeen] = useState(() => ({ all, view, fresh: NONE }))
  if (seen.all !== all || seen.view !== view) {
    const before = new Map(seen.all.map((r) => [r.item, r.status]))
    const fresh =
      seen.view !== view
        ? NONE
        : new Set(
            all
              .filter((r) => before.get(r.item) !== r.status)
              .map((r) => r.item)
          )
    setSeen({ all, view, fresh })
  }
  return seen.fresh
}

const PHONE = "(max-width: 639px)"

function usePhone(): boolean {
  return useSyncExternalStore(
    (notify) => {
      const mq = window.matchMedia(PHONE)
      mq.addEventListener("change", notify)
      return () => mq.removeEventListener("change", notify)
    },
    () => window.matchMedia(PHONE).matches,
    () => false
  )
}

function PrLabel({ pr }: { pr: string | null }) {
  return pr ? (
    <span className="inline-flex items-center gap-1.5 font-mono text-xs">
      <GitPullRequest className="size-3.5 text-muted-foreground" />
      {pr}
    </span>
  ) : (
    <span className="text-xs text-muted-foreground">None yet</span>
  )
}

function EmptyRows({
  tab,
  q,
  onShowAll,
}: {
  tab: ProgressTab
  q: string
  onShowAll: () => void
}) {
  if (q) return <>{`No items match "${q}".`}</>
  if (tab === "running")
    return (
      <>
        <span>Nothing is running right now.</span>{" "}
        <Button variant="link" className="pointer-coarse:h-11" onClick={onShowAll}>
          Show all items
        </Button>
      </>
    )
  return <>No items in this tab.</>
}

function ItemCards({
  rows,
  fresh,
  onOpen,
}: {
  rows: ItemRow[]
  fresh: ReadonlySet<string>
  onOpen: (item: string) => void
}) {
  return (
    <ul aria-label="Items" className="motion-fade-in divide-y">
      {rows.map((row) => {
        const label = itemLabel(row)
        const title = row.title ?? row.item
        return (
          <li
            key={`${row.item}:${row.status}`}
            className={cn(fresh.has(row.item) && "motion-row-in")}
          >
            <button
              type="button"
              aria-label={`${label} ${title}`}
              onClick={() => onOpen(row.item)}
              className="flex w-full flex-col gap-1.5 px-4 py-3 text-left focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
            >
              <span className="font-mono text-xs break-all text-muted-foreground">
                {label}
              </span>
              <span className="font-medium break-words">{title}</span>
              <span className="flex flex-wrap items-center gap-2">
                <StateBadge status={row.status} />
                <PrLabel pr={prLabel(row)} />
              </span>
            </button>
          </li>
        )
      })}
    </ul>
  )
}

function ItemList({
  all,
  tab,
  q,
  onOpen,
  onShowAll,
}: {
  all: ItemRow[]
  tab: ProgressTab
  q: string
  onOpen: (item: string) => void
  onShowAll: () => void
}) {
  const rows = all.filter(
    (r) => (tab === "all" || TAB_OF[r.status] === tab) && matches(r, q)
  )
  const { page, pageCount, pageItems, setPage } = usePage(rows, {
    resetKey: `${tab}:${q}`,
  })
  const fresh = useFreshRows(all, `${tab}:${q}:${page}`)
  const phone = usePhone()
  const swap = `${tab}:${page}`
  return (
    <>
      {phone ? (
        rows.length === 0 ? (
          <p className="px-4 py-10 text-center text-sm text-muted-foreground">
            <EmptyRows tab={tab} q={q} onShowAll={onShowAll} />
          </p>
        ) : (
          <ItemCards
            key={swap}
            rows={pageItems}
            fresh={fresh}
            onOpen={onOpen}
          />
        )
      ) : (
        <div className="overflow-x-auto">
          <Table className="md:min-w-[720px]">
            <TableHeader>
              <TableRow>
                <TableHead className="px-4">Item</TableHead>
                <TableHead className="px-4">Status</TableHead>
                <TableHead className="px-4">Current step</TableHead>
                <TableHead className="px-4">PR</TableHead>
                <TableHead className="px-4 text-right">Updated</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody key={swap} className="motion-fade-in">
              {pageItems.map((row) => {
                const label = itemLabel(row)
                const title = row.title ?? row.item
                return (
                  <TableRow
                    key={`${row.item}:${row.status}`}
                    className={cn(
                      "cursor-pointer",
                      fresh.has(row.item) && "motion-row-in"
                    )}
                    onClick={() => onOpen(row.item)}
                  >
                    <TableCell className="px-4 py-3">
                      <button
                        type="button"
                        aria-label={`${label} ${title}`}
                        onClick={(e) => {
                          e.stopPropagation()
                          onOpen(row.item)
                        }}
                        className="flex flex-col rounded-sm text-left focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
                      >
                        <span className="font-mono text-xs text-muted-foreground">
                          {label}
                        </span>
                        <span className="font-medium">{title}</span>
                      </button>
                    </TableCell>
                    <TableCell className="px-4 py-3">
                      <StateBadge status={row.status} />
                    </TableCell>
                    <TableCell className="px-4 py-3 break-words text-muted-foreground md:max-w-[280px] md:truncate">
                      {stepText(row.step)}
                    </TableCell>
                    <TableCell className="px-4 py-3">
                      <PrLabel pr={prLabel(row)} />
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
                    <EmptyRows tab={tab} q={q} onShowAll={onShowAll} />
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </div>
      )}
      {pageCount > 1 && (
        <div className="border-t px-3 py-2">
          <Pager
            page={page}
            pageCount={pageCount}
            onPage={setPage}
            label="Item pages"
          />
        </div>
      )}
    </>
  )
}
