import { useId } from "react"
import { useAway, useAwayState } from "@/api/control"
import { Switch } from "@/components/ui/switch"
import { errorMessage } from "@/lib/errors"
import { cn } from "@/lib/utils"

export function AwaySwitch({
  project,
  running,
}: {
  project: string
  running: boolean
}) {
  const switchId = useId()
  const noteId = useId()
  const overview = useAwayState(project).data
  const away = useAway(project)
  if (!overview) return null

  const recorded = Boolean(overview.away)
  const pending = overview.awayPending ?? null
  const checked = pending ? pending === "away" : recorded
  const waiting = pending !== null && (pending === "away") !== recorded

  const note = away.isError
    ? {
        text: `Couldn't tell STAR: ${errorMessage(away.error)}`,
        error: true,
      }
    : {
        text: !running
          ? "Waits for STAR's next start"
          : waiting
            ? `Waiting for STAR to mark you ${checked ? "away" : "back"}`
            : "STAR keeps going and saves a summary",
        error: false,
      }

  return (
    <label
      htmlFor={switchId}
      data-slot="away-row"
      className="flex min-h-11 cursor-pointer items-center justify-between gap-2.5 rounded-lg border bg-background px-2.5 py-2"
    >
      <span className="grid min-w-0">
        <span className="text-xs font-medium">Away</span>
        <span
          id={noteId}
          aria-live="polite"
          className={cn(
            "text-[11px] leading-snug",
            note.error ? "text-stop-fg" : "text-muted-foreground"
          )}
        >
          {note.text}
        </span>
      </span>
      <Switch
        id={switchId}
        aria-label="Away"
        aria-describedby={noteId}
        checked={checked}
        onCheckedChange={(next) => away.mutate({ away: next })}
        disabled={away.isPending}
        data-waiting={waiting}
        className="data-checked:bg-wait data-[waiting=true]:opacity-60"
      />
    </label>
  )
}
