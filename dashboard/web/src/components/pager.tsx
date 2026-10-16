import { ChevronLeft, ChevronRight } from "lucide-react"
import { Button } from "@/components/ui/button"

export function Pager({
  page,
  pageCount,
  onPage,
  label,
}: {
  page: number
  pageCount: number
  onPage: (page: number) => void
  label: string
}) {
  if (pageCount <= 1) return null
  return (
    <nav aria-label={label} className="flex items-center justify-between gap-2">
      <Button
        variant="outline"
        size="sm"
        className="pointer-coarse:h-11"
        aria-label="Previous page"
        disabled={page <= 1}
        onClick={() => onPage(page - 1)}
      >
        <ChevronLeft />
        Previous
      </Button>
      <span className="text-sm text-muted-foreground tabular-nums">
        Page {page} of {pageCount}
      </span>
      <Button
        variant="outline"
        size="sm"
        className="pointer-coarse:h-11"
        aria-label="Next page"
        disabled={page >= pageCount}
        onClick={() => onPage(page + 1)}
      >
        Next
        <ChevronRight />
      </Button>
    </nav>
  )
}
