import { RefreshCw } from "lucide-react"
import type { ReactNode } from "react"
import { ApiError } from "@/api/client"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import { errorMessage } from "@/lib/errors"

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
  const refused = error instanceof ApiError && error.status === 401
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
      {!refused && (
        <p className="text-sm leading-6 text-muted-foreground">
          Check that the dashboard server is running (/juel:star dashboard),
          then try again.
        </p>
      )}
      <Button variant="outline" size="sm" onClick={onRetry}>
        <RefreshCw />
        Try again
      </Button>
    </div>
  )
}
