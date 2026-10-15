import type { ItemStatus } from "@/api/types"
import { Badge } from "@/components/ui/badge"
import { statusOf, type Tone } from "@/lib/status"
import { cn } from "@/lib/utils"

/** STAR's mark (star-dashboard-mock.html:124-126). */
export function StarMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      fill="currentColor"
      className={cn("size-4 shrink-0", className)}
    >
      <path d="M12 1.5c.7 5.6 3 8.4 10.5 10.5C15 14.1 12.7 16.9 12 22.5 11.3 16.9 9 14.1 1.5 12 9 9.9 11.3 7.1 12 1.5z" />
    </svg>
  )
}

const DOT: Record<Tone, string> = {
  wait: "bg-wait",
  run: "bg-run",
  done: "bg-done",
  stop: "bg-stop",
  muted: "bg-muted-foreground",
}

export function Dot({ tone, pulse = false }: { tone: Tone; pulse?: boolean }) {
  return (
    <span className="relative inline-flex size-2 shrink-0" aria-hidden="true">
      {pulse && (
        <span
          className={cn(
            "absolute inline-flex size-full animate-ping rounded-full opacity-50 motion-reduce:animate-none",
            DOT[tone]
          )}
        />
      )}
      <span
        className={cn("relative inline-flex size-2 rounded-full", DOT[tone])}
      />
    </span>
  )
}

export function StateBadge({ status }: { status: ItemStatus }) {
  const { label, tone } = statusOf(status)
  return (
    <Badge variant={tone === "muted" ? "secondary" : tone}>
      {tone !== "muted" && <Dot tone={tone} pulse={tone === "run"} />}
      {label}
    </Badge>
  )
}
