import { useParams, useSearchParams } from "react-router"
import { useEvidence } from "@/api/queries"
import { EmptyState, ErrorState, LoadingState } from "@/components/page-state"
import { Skeleton } from "@/components/ui/skeleton"
import { age, clock, dayLabel } from "@/lib/format"
import { EvidenceDetailView } from "./evidence-detail"
export function EvidencePage() {
  const { project = "" } = useParams()
  const evidence = useEvidence(project)
  const [params, setParams] = useSearchParams()
  if (evidence.isPending)
    return (
      <LoadingState label="the evidence">
        <div className="grid gap-4 md:grid-cols-[minmax(260px,320px)_minmax(0,1fr)]">
          <Skeleton className="h-96" />
          <Skeleton className="h-96" />
        </div>
      </LoadingState>
    )
  if (evidence.isError)
    return (
      <ErrorState
        what="the evidence"
        error={evidence.error}
        onRetry={() => void evidence.refetch()}
      />
    )
  if (evidence.data.length === 0)
    return (
      <EmptyState
        title="No merged items yet."
        body="After STAR merges an item, its screenshots, recordings and test output show here."
      />
    )
  const selected =
    evidence.data.find((item) => item.item === params.get("item")) ??
    evidence.data[0]
  const select = (item: string) =>
    setParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        next.set("item", item)
        return next
      },
      { replace: true }
    )
  let lastDay = ""
  return (
    <div className="grid min-h-0 flex-1 md:h-full md:grid-cols-[minmax(260px,320px)_minmax(0,1fr)]">
      <section
        aria-label="Merged items"
        className="flex min-h-0 min-w-0 flex-col border-b md:border-r md:border-b-0"
      >
        <div className="p-4 pb-3">
          <h1 className="text-base font-semibold">Evidence</h1>
          <p className="mt-1 text-xs text-muted-foreground">
            Kept in STAR&apos;s folder after each merge
          </p>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto px-2 pb-3">
          {evidence.data.map((item) => {
            const day = dayLabel(item.mergedAt)
            const heading = day !== lastDay ? (lastDay = day) : null
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
                  <span className="flex items-center gap-2 text-xs">
                    <span className="font-mono text-muted-foreground">
                      {item.item}
                    </span>
                    <span className="font-mono text-muted-foreground">
                      {item.pr ?? ""}
                    </span>
                    <span className="ml-auto text-muted-foreground tabular-nums">
                      {clock(item.mergedAt)}
                    </span>
                  </span>
                  <span className="truncate text-sm font-medium">
                    {item.title}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {item.files} {item.files === 1 ? "file" : "files"}
                  </span>
                </button>
              </div>
            )
          })}
        </div>
      </section>
      <section
        aria-label="Evidence detail"
        className="min-h-0 min-w-0 overflow-y-auto"
      >
        <EvidenceDetailView
          key={selected.item}
          project={project}
          item={selected.item}
        />
      </section>
    </div>
  )
}
