import { useRouteError } from "react-router"
import { Button } from "@/components/ui/button"

/** A render error in a page: the shell stays, and the page says what broke. */
export function RouteError() {
  const error = useRouteError()
  console.error("[dashboard] page error", error)
  const message = error instanceof Error ? error.message : String(error)
  return (
    <div
      role="alert"
      data-testid="page-crash"
      className="mx-auto flex max-w-md flex-col items-center gap-2 px-4 py-16 text-center"
    >
      <p className="text-sm font-medium">{`This page hit an error: ${message}.`}</p>
      <p className="text-sm text-muted-foreground">
        Reload the page. If it keeps happening, the browser console has the
        details.
      </p>
      <Button
        variant="outline"
        size="sm"
        onClick={() => window.location.reload()}
      >
        Reload
      </Button>
    </div>
  )
}
