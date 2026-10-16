import { useState } from "react"
import { Popover } from "radix-ui"
import { Link } from "react-router"
import {
  activeOf,
  autoText,
  isSkipped,
  leftOf,
  popoverLine,
  problemText,
  useAccounts,
} from "@/api/accounts"
import type { AccountWindow } from "@/api/types"
import { agoText } from "@/lib/format"
import { projectPath } from "@/lib/routes"
import { cn } from "@/lib/utils"
import { Dot } from "./status"

const clampPct = (n: number) => Math.min(100, Math.max(0, n))

export function LimitBar({
  label,
  limit,
  hot = false,
  pace = false,
}: {
  label: string
  limit: AccountWindow
  hot?: boolean
  pace?: boolean
}) {
  return (
    <div
      role="meter"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={Math.round(limit.usedPct)}
      aria-valuetext={`${leftOf(limit)}% left`}
      className="relative h-1.5 rounded-full bg-muted"
    >
      <span
        className={cn(
          "block h-full rounded-full motion-bar",
          hot ? "bg-stop" : "bg-primary"
        )}
        style={{ width: `${clampPct(limit.usedPct)}%` }}
      />
      {pace && limit.expectedPct !== null && (
        <span
          data-slot="pace-tick"
          aria-hidden="true"
          className="absolute -inset-y-[3px] w-0.5 rounded-[1px] bg-wait"
          style={{ left: `${limit.expectedPct}%` }}
        />
      )}
    </div>
  )
}

function Ring({ usedPct, hot }: { usedPct: number | null; hot: boolean }) {
  return (
    <span
      aria-hidden="true"
      className="relative size-[18px] shrink-0 rounded-full after:absolute after:inset-[3.5px] after:rounded-full after:bg-muted"
      style={{
        background:
          usedPct === null
            ? "var(--border)"
            : `conic-gradient(${hot ? "var(--stop)" : "var(--primary)"} ${clampPct(usedPct)}%, var(--border) 0)`,
      }}
    />
  )
}

export function AccountsChip({ project }: { project: string }) {
  const [open, setOpen] = useState(false)
  const accounts = useAccounts().data
  if (!accounts || !accounts.installed || accounts.accounts.length === 0)
    return null
  const active = activeOf(accounts)
  const week = active?.sevenDay ?? null
  const left = leftOf(week)
  const hot = active ? isSkipped(active) : false
  const label = !active
    ? "Claude accounts"
    : left === null
      ? `Claude accounts: ${active.alias}, no week reading`
      : `Claude accounts: ${active.alias}, ${left}% of the week left`
  const problem = problemText(accounts)

  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger asChild>
        <button
          type="button"
          aria-label={label}
          className="relative inline-flex h-8 shrink-0 items-center gap-1.5 rounded-full border bg-muted py-1 pr-2.5 pl-1.5 text-xs font-medium outline-none after:absolute after:inset-x-0 after:-inset-y-1.5 focus-visible:ring-3 focus-visible:ring-ring/50"
        >
          <Ring usedPct={week ? week.usedPct : null} hot={hot} />
          {active ? (
            <>
              <span className="hidden sm:inline">{active.alias}</span>
              <span
                className={cn(
                  "tabular-nums",
                  hot ? "text-stop-fg" : "text-muted-foreground"
                )}
              >
                {left === null ? (
                  "no reading"
                ) : (
                  <>
                    {left}%<span className="hidden sm:inline"> left</span>
                  </>
                )}
              </span>
            </>
          ) : (
            <span>Claude accounts</span>
          )}
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content
          aria-label="Claude accounts"
          align="end"
          sideOffset={8}
          collisionPadding={16}
          className="z-50 grid w-[min(20.5rem,calc(100vw-2rem))] gap-3 rounded-xl border bg-popover p-3 text-popover-foreground shadow-lg outline-hidden motion-fade-in"
        >
          <div className="flex justify-between gap-2 text-[11.5px] text-muted-foreground">
            <b className="text-xs font-medium text-foreground">
              Claude accounts
            </b>
            <span>
              {`auto ${autoText(accounts.auto)}`}
              {accounts.fetchedAt ? ` · ${agoText(accounts.fetchedAt)}` : ""}
            </span>
          </div>
          {problem && <p className="text-xs text-wait-fg">{problem}</p>}
          <ul className="grid gap-2.5">
            {accounts.accounts.map((a) => {
              const skipped = isSkipped(a)
              return (
                <li key={a.number} className="grid gap-1.5 [&+li]:border-t [&+li]:pt-2.5">
                  <div className="flex items-center justify-between gap-2 text-xs">
                    <span className="flex min-w-0 items-center gap-1.5 font-medium">
                      <Dot tone={a.isActive ? "done" : "muted"} />
                      <span className="truncate">
                        {a.alias}
                        {a.isActive ? " · active" : ""}
                        {a.isDisabled ? " · disabled" : ""}
                      </span>
                    </span>
                    {a.sevenDay && (
                      <span
                        className={cn(
                          "font-mono text-[11.5px] tabular-nums",
                          skipped && "text-stop-fg"
                        )}
                      >
                        {leftOf(a.sevenDay)}% left
                      </span>
                    )}
                  </div>
                  {a.sevenDay && (
                    <LimitBar
                      label={`${a.alias}: week`}
                      limit={a.sevenDay}
                      hot={skipped}
                      pace
                    />
                  )}
                  <span className="text-[11.5px] text-muted-foreground">
                    {popoverLine(a)}
                  </span>
                </li>
              )
            })}
          </ul>
          <Link
            to={projectPath(project, "accounts")}
            onClick={() => setOpen(false)}
            className="inline-flex items-center text-xs font-medium underline-offset-4 hover:underline pointer-coarse:min-h-11"
          >
            See every limit
          </Link>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  )
}
