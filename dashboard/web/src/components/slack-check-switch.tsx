import { useId } from "react"
import { useSlackPaused } from "@/api/slack"
import { Switch } from "@/components/ui/switch"
import { errorMessage } from "@/lib/errors"
import { cn } from "@/lib/utils"

/** The "Check Slack" switch (spec 3.14): off, the dashboard runs no scheduled Slack check. */
export function SlackCheckSwitch({ paused }: { paused: boolean }) {
  const switchId = useId()
  const noteId = useId()
  const change = useSlackPaused()
  const note = change.isError
    ? { text: `Couldn't change it: ${errorMessage(change.error)}`, error: true }
    : {
        text: paused ? "Paused" : "Checks Slack every few minutes",
        error: false,
      }
  return (
    <label
      htmlFor={switchId}
      data-slot="slack-check-row"
      className="flex min-h-11 cursor-pointer items-center justify-between gap-2.5 rounded-lg border bg-background px-2.5 py-2"
    >
      <span className="grid min-w-0">
        <span className="text-xs font-medium">Check Slack</span>
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
        aria-label="Check Slack"
        aria-describedby={noteId}
        checked={!paused}
        onCheckedChange={(next) => change.mutate({ paused: !next })}
        disabled={change.isPending}
      />
    </label>
  )
}
