import { cn } from "cn"
import { railLabel, STAGES, type Rail, type RailTone } from "@/lib/stage"

const CURRENT_BAR: Record<RailTone, string> = {
  run: "bg-run",
  wait: "bg-wait",
  stop: "bg-stop",
  muted: "bg-muted-foreground",
}
const CURRENT_LABEL: Record<RailTone, string> = {
  run: "text-run-fg",
  wait: "text-wait-fg",
  stop: "text-stop-fg",
  muted: "text-muted-foreground",
}

/** Five segments, Brief to Merge; an image to assistive tech, labelled by `railLabel`. */
export function StageRail({
  rail,
  size = "sm",
  className,
}: {
  rail: Rail
  size?: "sm" | "lg"
  className?: string
}) {
  return (
    <div
      role="img"
      aria-label={railLabel(rail)}
      data-slot="stage-rail"
      data-size={size}
      className={cn("flex min-w-0 gap-0.5", size === "sm" && "w-24", size === "lg" && "w-full", className)}
    >
      {STAGES.map((name, index) => {
        const state = index === rail.current ? "current" : index < rail.done ? "done" : "upcoming"
        return (
          <div key={name} className="flex min-w-0 flex-1 flex-col gap-1">
            <div
              data-slot="stage-segment"
              data-state={state}
              data-tone={state === "current" ? rail.tone : undefined}
              className={cn(
                "w-full rounded-[3px]",
                size === "sm" ? "h-[5px]" : "h-1.5",
                state === "done" && "bg-foreground",
                state === "current" && CURRENT_BAR[rail.tone],
                state === "upcoming" && "bg-foreground/15"
              )}
            />
            {size === "lg" && (
              <span
                className={cn(
                  "truncate text-xs",
                  state === "current" ? cn("font-semibold", CURRENT_LABEL[rail.tone]) : "text-muted-foreground"
                )}
              >
                {name}
              </span>
            )}
          </div>
        )
      })}
    </div>
  )
}

/** `total` small squares, `busy` of them filled. */
export function SlotPips({ busy, total, className }: { busy: number; total: number; className?: string }) {
  return (
    <div
      role="img"
      aria-label={`${busy} of ${total} busy`}
      data-slot="slot-pips"
      className={cn("flex gap-1", className)}
    >
      {Array.from({ length: total }, (_, index) => (
        <span
          key={index}
          data-filled={index < busy}
          className={cn("size-2 rounded-[2px]", index < busy ? "bg-foreground" : "bg-foreground/15")}
        />
      ))}
    </div>
  )
}
