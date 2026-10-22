import { CircleCheck, GitPullRequest, Search } from "lucide-react"
import { useState, useSyncExternalStore } from "react"
import { Link, useParams } from "react-router"
import { useItems, useLoops, useOverview } from "@/api/queries"
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
import { SlotPips, StageRail } from "@/components/stage-rail"
import { Dot } from "@/components/status"
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
import { age, clock, dayLabel } from "@/lib/format"
import { itemLabel } from "@/lib/items"
import { isAnswered } from "@/lib/loops"
import { usePage } from "@/lib/paginate"
import { needsPath, projectPath } from "@/lib/routes"
import { railOf } from "@/lib/stage"
import {
  prLabel,
  type ProgressTab,
  statusOf,
  stepText,
  TAB_OF,
} from "@/lib/status"
import { useSearchParam } from "@/lib/use-search-param"
import { cn } from "@/lib/utils"
import { ItemSheet } from "./progress-sheet"

const TABS: Array<{ id: ProgressTab; label: string }> = [
  { id: "running", label: "Running" },
  { id: "needs", label: "Blocked" },
  { id: "merged", label: "Merged" },
  { id: "all", label: "All" },
]

const matches = (row: ItemRow, q: string) =>
  !q ||
  `${row.ref ?? ""} ${row.item} ${row.title ?? ""}`
    .toLowerCase()
    .includes(q.trim().toLowerCase())

const updatedAt = (row: ItemRow) => Date.parse(row.updated ?? "") || 0
const mergedAtMs = (row: ItemRow) => Date.parse(row.mergedAt ?? "") || 0

/** What a row's step column says when the row has no step text of its own. */
const FALLBACK: Partial<Record<ItemRow["status"], string>> = {
  queued: "Queued for a build slot",
  merged: "Merged",
  stopped: "Set aside",
  dropped: "Dropped",
}

export function ProgressPage() {
  const { project = "" } = useParams()
  const items = useItems(project)
  const overview = useOverview(project)
  const loops = useLoops(project)
  const [itemParam, setItemParam] = useSearchParam("item")
  const [tab, setTab] = useState<ProgressTab>("running")
  const [q, setQ] = useState("")
  const open = itemParam
  const setOpen = (item: string | null) =>
    setItemParam(item, { replace: item === null })

  if (items.isPending) {
    return (
      <LoadingState label="the items">
        <Skeleton className="h-6 w-80 max-w-full" />
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
  const inReview = by("in-review").length
  const mergedToday = by("merged")
    .filter((r) => dayLabel(r.mergedAt) === "Today")
    .sort((a, b) => mergedAtMs(b) - mergedAtMs(a))
  const overviewFailed = queryFailed(overview) || refreshFailed(overview)
  const [busy, slots] = overview.data?.workers.build ?? [0, 0]
  const count = (t: ProgressTab) =>
    t === "all" ? all.length : all.filter((r) => TAB_OF[r.status] === t).length
  const waiting = (loops.data ?? []).filter((l) => !isAnswered(l))
  const first = waiting[0]
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
          <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
            Progress
          </h1>
          <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-sm">
            {overviewFailed ? (
              <span className="text-muted-foreground">
                Couldn't load the workers.
              </span>
            ) : (
              overview.data && (
                <span className="flex items-center gap-2">
                  <SlotPips busy={busy} total={slots} />
                  <span>{`${busy} of ${slots} build slots busy.`}</span>
                </span>
              )
            )}
            <span className="text-muted-foreground">{`${inReview} in review, ${mergedToday.length} merged today.`}</span>
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
          {first && (
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-wait-line bg-wait-bg px-4 py-3 text-sm">
              <p className="min-w-0 break-words">
                {`${first.item} waits on you: ${first.title}.`}
                {waiting.length > 1 &&
                  ` ${waiting.length - 1} more wait on you.`}
              </p>
              <Button variant="answer" asChild>
                <Link to={needsPath(project)}>Open Needs you</Link>
              </Button>
            </div>
          )}
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
          {tab !== "merged" && mergedToday.length > 0 && (
            <MergedToday project={project} rows={mergedToday} />
          )}
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
  ) : null
}

/** The stage rail and the step text. A row without a rail says "Report" (a report item) or its status label. */
function StageCell({ row }: { row: ItemRow }) {
  const rail = railOf(row)
  const text = stepText(row.step) || FALLBACK[row.status] || ""
  const label = rail
    ? null
    : row.stage === "post"
      ? "Report"
      : statusOf(row.status).label
  return (
    <div className="flex min-w-0 flex-col gap-1.5">
      {rail ? (
        <StageRail rail={rail} />
      ) : (
        <span className="text-xs font-medium">{label}</span>
      )}
      {text && (
        <span
          title={text}
          className={cn(
            "text-sm break-words",
            row.status === "needs-you"
              ? "text-wait-fg"
              : "text-muted-foreground"
          )}
        >
          {text}
        </span>
      )}
    </div>
  )
}

function MergedToday({ project, rows }: { project: string; rows: ItemRow[] }) {
  return (
    <section className="flex flex-col gap-2">
      <h2 className="text-sm font-medium">Merged today</h2>
      <Card className="gap-0 p-0">
        <ul aria-label="Merged today" className="divide-y">
          {rows.map((row) => {
            const pr = prLabel(row)
            return (
              <li
                key={row.item}
                className="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-3 text-sm"
              >
                <CircleCheck
                  className="size-4 shrink-0 text-done"
                  aria-hidden="true"
                />
                <span className="font-mono text-xs text-muted-foreground">
                  {itemLabel(row)}
                </span>
                <span className="min-w-0 flex-1 font-medium break-words">
                  {row.title ?? row.item}
                </span>
                {row.prUrl && pr && (
                  <a
                    href={row.prUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="font-mono text-xs underline-offset-4 hover:underline"
                  >
                    {pr}
                  </a>
                )}
                <span className="text-xs text-muted-foreground tabular-nums">
                  {clock(row.mergedAt)}
                </span>
                <Link
                  to={projectPath(project, "evidence", { item: row.item })}
                  className="text-xs underline underline-offset-4 pointer-coarse:inline-flex pointer-coarse:min-h-11 pointer-coarse:items-center"
                >
                  Evidence
                </Link>
              </li>
            )
          })}
        </ul>
      </Card>
    </section>
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
        <Button
          variant="link"
          className="pointer-coarse:h-11"
          onClick={onShowAll}
        >
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
              <span className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                <span className="font-mono break-all">{label}</span>
                <PrLabel pr={prLabel(row)} />
                <span className="tabular-nums">{age(row.updated)}</span>
              </span>
              <span className="font-medium break-words">{title}</span>
              <StageCell row={row} />
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
  const rows = all
    .filter((r) => (tab === "all" || TAB_OF[r.status] === tab) && matches(r, q))
    .sort((a, b) => updatedAt(b) - updatedAt(a))
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
        <Table className="table-fixed">
          <TableHeader>
            <TableRow>
              <TableHead className="px-4">Item</TableHead>
              <TableHead className="w-[34%] px-4">Stage</TableHead>
              <TableHead className="w-24 px-4">PR</TableHead>
              <TableHead className="w-24 px-4 text-right">Updated</TableHead>
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
                  <TableCell className="px-4 py-3 md:whitespace-normal">
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
                      <span className="font-medium break-words">{title}</span>
                    </button>
                  </TableCell>
                  <TableCell className="px-4 py-3 md:whitespace-normal">
                    <StageCell row={row} />
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
                  colSpan={4}
                  className="px-4 py-10 text-center text-sm text-muted-foreground"
                >
                  <EmptyRows tab={tab} q={q} onShowAll={onShowAll} />
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
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
