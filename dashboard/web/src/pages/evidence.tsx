import { useParams } from "react-router"
import { useEvidence } from "@/api/queries"
import {
  EmptyState,
  ErrorState,
  LoadingState,
  queryFailed,
  RefreshNotice,
  refreshFailed,
} from "@/components/page-state"
import { ListDetail, useListSelection } from "@/components/list-detail"
import { Pager } from "@/components/pager"
import { Skeleton } from "@/components/ui/skeleton"
import { clock, dayLabel } from "@/lib/format"
import { usePage } from "@/lib/paginate"
import { prLabel } from "@/lib/status"
import { EvidenceDetailView } from "./evidence-detail"
export function EvidencePage() {
  const { project = "" } = useParams()
  const evidence = useEvidence(project)
  const { value: itemParam, select, back } = useListSelection("item")
  const items = evidence.data ?? []
  const namedIndex = items.findIndex((entry) => entry.item === itemParam)
  const { page, pageCount, pageItems, setPage } = usePage(items, {
    focusIndex: namedIndex >= 0 ? namedIndex : null,
  })
  if (evidence.isPending)
    return (
      <LoadingState label="the evidence">
        <div className="grid gap-4 md:grid-cols-[minmax(260px,320px)_minmax(0,1fr)]">
          <Skeleton className="h-96" />
          <Skeleton className="h-96" />
        </div>
      </LoadingState>
    )
  if (queryFailed(evidence))
    return (
      <ErrorState
        what="the evidence"
        error={evidence.error}
        onRetry={() => void evidence.refetch()}
      />
    )
  if (evidence.data!.length === 0)
    return (
      <>
        {refreshFailed(evidence) && (
          <RefreshNotice
            what="the evidence"
            error={evidence.error}
            onRetry={() => void evidence.refetch()}
          />
        )}
        <EmptyState
          title="No merged items yet."
          body="After STAR merges an item, its screenshots, recordings and test output show here."
        />
      </>
    )
  const selected = items[namedIndex] ?? items[0]!
  return (
    <>
      {refreshFailed(evidence) && (
        <RefreshNotice
          what="the evidence"
          error={evidence.error}
          onRetry={() => void evidence.refetch()}
        />
      )}
      <ListDetail
        showDetail={namedIndex >= 0}
        onBack={back}
        backLabel="Evidence"
        listLabel="Merged items"
        detailLabel="Evidence detail"
        columns="md:grid-cols-[minmax(260px,320px)_minmax(0,1fr)]"
        detailClassName="overflow-y-auto"
        list={
          <>
            <div className="p-4 pb-3">
              <h1 className="text-base font-semibold">Evidence</h1>
              <p className="mt-1 text-xs text-muted-foreground">
                Kept in STAR&apos;s folder after each merge
              </p>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto px-2 pb-3">
              <div key={page} className="motion-fade-in">
                {pageItems.map((item, index) => {
                  const day =
                    item.mergedAt === null ? "Unknown" : dayLabel(item.mergedAt)
                  const previous = pageItems[index - 1]
                  const previousDay = previous
                    ? previous.mergedAt === null
                      ? "Unknown"
                      : dayLabel(previous.mergedAt)
                    : null
                  const heading = !previous || previousDay !== day ? day : null
                  return (
                    <div key={item.item}>
                      {heading && (
                        <h2 className="px-2 pt-3 pb-1 text-xs font-medium text-muted-foreground">
                          {heading}
                        </h2>
                      )}
                      <button
                        type="button"
                        onClick={() => select(item.item)}
                        aria-current={
                          selected.item === item.item ? "true" : undefined
                        }
                        className="flex w-full min-w-0 flex-col gap-1 rounded-lg border border-transparent px-3 py-2.5 text-left hover:bg-muted"
                      >
                        <span className="flex min-w-0 items-center gap-2 text-xs">
                          <span
                            className="min-w-0 truncate font-mono text-muted-foreground"
                            title={item.item}
                          >
                            {item.item}
                          </span>
                          <span className="shrink-0 font-mono text-muted-foreground">
                            {prLabel({ pr: "-", prUrl: item.pr }) ?? ""}
                          </span>
                          <span className="ml-auto shrink-0 text-muted-foreground tabular-nums">
                            {clock(item.mergedAt)}
                          </span>
                        </span>
                        <span className="truncate text-sm font-medium">
                          {item.title ?? item.item}
                        </span>
                        <span className="text-xs text-muted-foreground">
                          {item.files} {item.files === 1 ? "file" : "files"}
                        </span>
                      </button>
                    </div>
                  )
                })}
              </div>
              <div className="px-2 pt-3">
                <Pager
                  page={page}
                  pageCount={pageCount}
                  onPage={setPage}
                  label="Evidence pages"
                />
              </div>
            </div>
          </>
        }
        detail={
          <EvidenceDetailView
            key={selected.item}
            project={project}
            item={selected.item}
          />
        }
      />
    </>
  )
}
