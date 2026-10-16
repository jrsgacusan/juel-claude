import { RefreshCw } from "lucide-react"
import { useQueryClient } from "@tanstack/react-query"
import {
  type FormEvent,
  type ReactNode,
  useEffect,
  useId,
  useState,
  useSyncExternalStore,
} from "react"
import { ApiError, checkToken, NetworkError } from "@/api/client"
import { reconnectEvents } from "@/api/events"
import { saveToken, tokenFromPaste } from "@/api/token"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
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

type FormSlot = { id: string; place: "page" | "banner" }
const slots: FormSlot[] = []
const slotListeners = new Set<() => void>()
const notifySlots = () => slotListeners.forEach((listener) => listener())
const subscribeSlots = (listener: () => void) => {
  slotListeners.add(listener)
  return () => void slotListeners.delete(listener)
}
const shownSlot = (): string | null =>
  (slots.find((s) => s.place === "page") ?? slots[0])?.id ?? null

const TOKEN_WHERE =
  "On your Mac, run /juel:star dashboard. It prints a link that ends in ?t= and the token."
const TOKEN_HOW =
  "Paste that link here, or only the part after ?t=. This browser keeps the token, so you only do this once."
const TOKEN_REFUSED_PASTE =
  "The dashboard server refused that token. Paste the whole link /juel:star dashboard printed, so nothing is cut off."
const TOKEN_UNREACHABLE =
  "The dashboard server did not answer. Check that it is running on your Mac, then try again."

/** Where to get the token and a field to paste it into. One shows per screen. */
export function TokenForm({ place }: { place: "page" | "banner" }) {
  const id = useId()
  const client = useQueryClient()
  const shown = useSyncExternalStore(subscribeSlots, shownSlot, shownSlot)
  const [value, setValue] = useState("")
  const [checking, setChecking] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  useEffect(() => {
    const slot = { id, place }
    slots.push(slot)
    notifySlots()
    return () => {
      slots.splice(slots.indexOf(slot), 1)
      notifySlots()
    }
  }, [id, place])
  if (shown !== id) return null
  const token = tokenFromPaste(value)
  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!token || checking) return
    setChecking(true)
    setProblem(null)
    const result = await checkToken(token)
    setChecking(false)
    if (result === "accepted") {
      saveToken(token)
      reconnectEvents()
      void client.invalidateQueries()
      setValue("")
    } else {
      setProblem(result === "refused" ? TOKEN_REFUSED_PASTE : TOKEN_UNREACHABLE)
    }
  }
  return (
    <form
      data-testid="token-form"
      onSubmit={submit}
      className="mt-2 flex w-full flex-col gap-2 text-left"
    >
      <p className="text-sm leading-6 opacity-80">{TOKEN_WHERE}</p>
      <p className="text-sm leading-6 opacity-80">{TOKEN_HOW}</p>
      <Label htmlFor={`${id}-token`}>Dashboard token</Label>
      <div className="flex flex-col gap-2 sm:flex-row">
        <Input
          id={`${id}-token`}
          value={value}
          onChange={(e) => {
            setValue(e.target.value)
            setProblem(null)
          }}
          autoComplete="off"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          className="pointer-coarse:h-11"
          aria-invalid={problem !== null}
        />
        <Button
          type="submit"
          className="pointer-coarse:h-11"
          disabled={checking || !token}
        >
          {checking ? "Checking the token…" : "Use this token"}
        </Button>
      </div>
      {problem && (
        <p role="alert" className="text-sm font-medium">
          {problem}
        </p>
      )}
    </form>
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
  const advice = refused
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
      {refused ? (
        <TokenForm place="page" />
      ) : (
        <Button variant="outline" size="sm" onClick={onRetry}>
          <RefreshCw />
          Try again
        </Button>
      )}
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
