import { useEffect, useSyncExternalStore, type ReactNode } from "react"
import { ChevronLeft } from "lucide-react"
import { useLocation, useNavigate } from "react-router"
import { Button } from "@/components/ui/button"
import { useSearchParam } from "@/lib/use-search-param"
import { cn } from "@/lib/utils"

const subscribe = (notify: () => void) => {
  window.addEventListener("resize", notify)
  return () => window.removeEventListener("resize", notify)
}

/** Below md (768 px). Read synchronously on the first render, so a phone never flashes the wide layout. */
export function useNarrow() {
  return useSyncExternalStore(
    subscribe,
    () => window.innerWidth < 768,
    () => false
  )
}

/** The selected item's URL param. On a phone, selecting pushes history so the browser's Back returns to the list. */
export function useListSelection(
  name: string,
  aliases: readonly string[] = []
) {
  const [value, set] = useSearchParam(name)
  const narrow = useNarrow()
  const location = useLocation()
  const navigate = useNavigate()
  const select = (next: string) => {
    if (narrow)
      set(next, { replace: false, clear: aliases, state: { listDetail: true } })
    else set(next, { clear: aliases })
  }
  const back = () => {
    if (
      (location.state as { listDetail?: unknown } | null)?.listDetail === true
    )
      navigate(-1)
    else set(null, { clear: aliases })
  }
  return { value, select, back }
}

export function ListDetail({
  showDetail,
  onBack,
  backLabel,
  listLabel,
  detailLabel,
  columns,
  list,
  detail,
  detailClassName,
}: {
  showDetail: boolean
  onBack?: () => void
  backLabel: string
  listLabel: string
  detailLabel: string
  columns: string
  list: ReactNode
  detail: ReactNode
  detailClassName?: string
}) {
  const narrow = useNarrow()
  useEffect(() => {
    if (narrow && showDetail) window.scrollTo(0, 0)
  }, [narrow, showDetail])
  return (
    <div className={cn("grid min-h-0 flex-1 md:h-full", columns)}>
      <section
        aria-label={listLabel}
        hidden={narrow && showDetail}
        className="flex min-h-0 min-w-0 flex-col border-b md:border-r md:border-b-0"
      >
        {list}
      </section>
      {(!narrow || showDetail) && (
        <section
          aria-label={detailLabel}
          className={cn(
            "min-h-0 min-w-0 md:overflow-y-auto",
            narrow && "motion-fade-in",
            detailClassName
          )}
        >
          {narrow && onBack && (
            <div className="border-b px-2 py-1.5">
              <Button
                variant="ghost"
                size="sm"
                onClick={onBack}
                aria-label={`Back to ${backLabel}`}
                className="pointer-coarse:h-11"
              >
                <ChevronLeft />
                {backLabel}
              </Button>
            </div>
          )}
          {detail}
        </section>
      )}
    </div>
  )
}
