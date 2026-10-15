import { RefreshCw } from "lucide-react"
import type { ReactNode } from "react"
import { ApiError, NetworkError } from "@/api/client"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import { errorMessage } from "@/lib/errors"

type QueryLike = {
  error: unknown
  data: unknown
  isError: boolean
  refetch: () => unknown
}

export const queryFailed = (q: QueryLike) => q.isError && q.data === undefined
export const refreshFailed = (q: QueryLike) => q.isError && q.data !== undefined

export function LoadingState({
  label,
  children,
}: {
  label: string
  children?: ReactNode
}) {
  return (
    <div
      role="status"
      aria-label={`Loading ${label}`}
      data-testid="page-loading"
      className="flex flex-col gap-3 p-4 sm:p-6"
    >
      {children ?? (
        <>
          <Skeleton className="h-6 w-40" />
          <Skeleton className="h-4 w-64" />
          <Skeleton className="h-20 w-full" />
          <Skeleton className="h-20 w-full" />
          <Skeleton className="h-20 w-full" />
        </>
      )}
    </div>
  )
}

export function EmptyState({
  title,
  body,
  action,
}: {
  title: string
  body: string
  action?: ReactNode
}) {
  return (
    <div
      data-testid="page-empty"
      className="mx-auto flex max-w-sm flex-col items-center gap-2 px-4 py-16 text-center"
    >
      <p className="text-sm font-medium">{title}</p>
      <p className="text-sm leading-6 text-muted-foreground">{body}</p>
      {action}
    </div>
  )
}

export function ErrorState({
  what,
  error,
  onRetry,
}: {
  what: string
  error: unknown
  onRetry: () => void
}) {
  const advice =
    error instanceof ApiError && error.status === 401
      ? null
      : error instanceof ApiError && error.status >= 500
        ? "The dashboard server is running but could not read what it needs. Fix what it names, then try again."
        : error instanceof ApiError && error.status === 404
          ? "It may have been removed or renamed. Pick another one."
          : error instanceof NetworkError
            ? "Check that the dashboard server is running (/juel:star dashboard), then try again."
            : "Try again."
  return (
    <div
      role="alert"
      data-testid="page-error"
      className="mx-auto flex max-w-md flex-col items-center gap-2 px-4 py-16 text-center"
    >
      <p className="text-sm font-medium">Couldn't load {what}.</p>
      <p className="text-sm leading-6 text-muted-foreground">
        {errorMessage(error)}
      </p>
      {advice && (
        <p className="text-sm leading-6 text-muted-foreground">{advice}</p>
      )}
      <Button variant="outline" size="sm" onClick={onRetry}>
        <RefreshCw />
        Try again
      </Button>
    </div>
  )
}

/** A background refetch failed: the page keeps what it showed, and says so. */
export function RefreshNotice({
  what,
  error,
  onRetry,
}: {
  what: string
  error: unknown
  onRetry: () => void
}) {
  return (
    <div
      role="status"
      className="flex flex-wrap items-center gap-2 border-b border-wait-line bg-wait-bg px-4 py-2 text-sm text-wait-fg"
    >
      <span className="min-w-0 flex-1 break-words">
        {`Couldn't refresh ${what}: ${errorMessage(error)}. Showing what was loaded before.`}
      </span>
      <Button variant="outline" size="sm" onClick={onRetry}>
        Try again
      </Button>
    </div>
  )
}
