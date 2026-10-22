import { useState } from "react"
import type { Overview } from "@/api/types"
import { cn } from "@/lib/utils"

function Slot({ filled }: { filled: boolean }) {
  const [prev, setPrev] = useState(filled)
  const [popped, setPopped] = useState(false)
  if (filled !== prev) {
    setPrev(filled)
    setPopped(filled)
  }
  return (
    <span
      data-slot="worker-slot"
      data-filled={filled}
      aria-hidden="true"
      className={cn(
        "size-[9px] rounded-[2.5px] border",
        filled ? "border-primary bg-primary motion-breathe" : "border-border",
        popped && filled && "motion-pop"
      )}
    />
  )
}

export function WorkersCard({ workers }: { workers: Overview["workers"] }) {
  const pools = [
    ["Briefing", workers.brief],
    ["Building", workers.build],
    ["Review", workers.babysit],
  ] as const
  const busy = pools.reduce((sum, [, [n]]) => sum + n, 0)
  return (
    <div className="flex flex-col gap-2.5 rounded-lg border bg-background p-2.5">
      <div className="flex items-baseline justify-between gap-2 text-xs">
        <span className="font-medium">Workers</span>
        <span className="text-muted-foreground">{busy > 0 ? `${busy} busy` : "all free"}</span>
      </div>
      {pools.map(([name, [n, max]]) => (
        <div key={name} className="grid grid-cols-[3.75rem_minmax(0,1fr)_2.75rem] items-center gap-2 text-xs">
          <span>{name}</span>
          <div
            role="meter"
            aria-label={name}
            aria-valuemin={0}
            aria-valuemax={max}
            aria-valuenow={n}
            aria-valuetext={`${n} of ${max} busy`}
            className="flex flex-wrap gap-[3px]"
          >
            {Array.from({ length: max }, (_, i) => (
              <Slot key={i} filled={i < n} />
            ))}
          </div>
          <span
            className={cn(
              "text-right font-mono text-[11px] tabular-nums",
              n > 0 ? "text-foreground" : "text-muted-foreground"
            )}
          >
            {`${n} of ${max}`}
          </span>
        </div>
      ))}
    </div>
  )
}
