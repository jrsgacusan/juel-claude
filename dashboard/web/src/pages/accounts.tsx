import { useId, type ReactNode } from "react"
import {
  fiveHourText,
  isSkipped,
  leftOf,
  loginText,
  paceNote,
  problemText,
  resetText,
  useAccounts,
  autoText,
  NEAR_LIMIT,
} from "@/api/accounts"
import type { Account, AccountsState } from "@/api/types"
import { LimitBar } from "@/components/accounts-chip"
import {
  EmptyState,
  ErrorState,
  LoadingState,
  queryFailed,
  RefreshNotice,
  refreshFailed,
} from "@/components/page-state"
import { Dot } from "@/components/status"
import { Badge } from "@/components/ui/badge"
import { agoText } from "@/lib/format"
import { cn } from "@/lib/utils"

function LimitRow({
  name,
  detail,
  children,
}: {
  name: string
  detail: string
  children: ReactNode
}) {
  return (
    <div className="grid gap-1.5 text-xs">
      <div className="flex justify-between gap-2">
        <span>{name}</span>
        <span className="text-right text-muted-foreground tabular-nums">
          {detail}
        </span>
      </div>
      {children}
    </div>
  )
}

function AccountCard({ account: a }: { account: Account }) {
  const headingId = useId()
  const skipped = isSkipped(a)
  const left = leftOf(a.sevenDay)
  const pace = paceNote(a)
  const login = loginText(a)
  const noteBox = "rounded-lg px-2.5 py-2 text-xs"
  return (
    <article
      aria-labelledby={headingId}
      data-disabled={a.isDisabled}
      className={cn(
        "grid min-w-0 content-start gap-3 rounded-xl border p-4",
        a.isActive && "border-done-line",
        a.isDisabled && "opacity-70"
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="grid min-w-0 gap-0.5">
          <h2 id={headingId} className="flex items-center gap-1.5 text-sm font-semibold">
            <Dot tone={a.isActive ? "done" : "muted"} />
            {a.alias}
          </h2>
          <span className="text-xs text-muted-foreground [overflow-wrap:anywhere]">
            {a.email}
          </span>
        </div>
        {a.isActive ? (
          <Badge variant="done">Active</Badge>
        ) : a.isDisabled ? (
          <Badge variant="secondary">Disabled</Badge>
        ) : null}
      </div>
      <div className="flex items-baseline gap-2">
        <span
          className={cn(
            "text-3xl font-semibold tracking-tight tabular-nums",
            skipped && "text-stop-fg"
          )}
        >
          {left === null ? "No reading" : `${left}%`}
        </span>
        {left !== null && (
          <span className="text-sm text-muted-foreground">of the week left</span>
        )}
      </div>
      {a.sevenDay && (
        <LimitRow name="Week" detail={resetText(a.sevenDay)}>
          <LimitBar label="Week" limit={a.sevenDay} hot={skipped} pace />
        </LimitRow>
      )}
      {a.fiveHour && (
        <LimitRow name="5-hour window" detail={fiveHourText(a.fiveHour)}>
          <LimitBar label="5-hour window" limit={a.fiveHour} />
        </LimitRow>
      )}
      {a.scoped.map((w) => (
        <LimitRow key={w.name} name={w.name} detail={`${leftOf(w)}% left`}>
          <LimitBar label={w.name} limit={w} />
        </LimitRow>
      ))}
      {skipped ? (
        <p className={cn(noteBox, "bg-stop-bg text-stop-fg")}>
          Nearly out. Auto-switch skips it until the reset.
        </p>
      ) : (
        pace && <p className={cn(noteBox, "bg-wait-bg text-wait-fg")}>{pace}</p>
      )}
      <div className="grid gap-0.5 text-xs text-muted-foreground">
        {a.status && <span>{`Usage reading: ${a.status}`}</span>}
        {a.isStale && (
          <span>
            {`Last good reading, ${agoText(new Date(Date.now() - (a.usageAgeSeconds ?? 0) * 1000).toISOString())}`}
          </span>
        )}
        {login && (
          <span className={cn(login.expired && "text-stop-fg")}>{login.text}</span>
        )}
      </div>
    </article>
  )
}

function subtitle(s: AccountsState): string {
  const moves = s.auto.state === "on" ? `, moves at ${NEAR_LIMIT}%` : ""
  const refreshed = s.fetchedAt ? ` · refreshed ${agoText(s.fetchedAt)}` : ""
  return `From cswap · auto-switch ${autoText(s.auto)}${moves}${refreshed}`
}

export function AccountsPage() {
  const accounts = useAccounts()
  if (accounts.isPending) return <LoadingState label="the accounts" />
  if (queryFailed(accounts))
    return (
      <ErrorState
        what="the accounts"
        error={accounts.error}
        onRetry={() => void accounts.refetch()}
      />
    )
  const s = accounts.data!
  const refresh = refreshFailed(accounts) && (
    <RefreshNotice
      what="the accounts"
      error={accounts.error}
      onRetry={() => void accounts.refetch()}
    />
  )
  if (!s.installed)
    return (
      <>
        {refresh}
        <EmptyState
          title="cswap is not installed on this Mac."
          body="The dashboard reads your Claude accounts from cswap (claude-swap). Install it to see them here."
        />
      </>
    )
  if (s.accounts.length === 0)
    return (
      <>
        {refresh}
        <EmptyState
          title="cswap lists no accounts."
          body="Accounts you add to cswap show here."
        />
      </>
    )
  const problem = problemText(s)
  return (
    <div className="min-h-0 min-w-0 flex-1 md:overflow-y-auto">
      {refresh}
      <div className="mx-auto flex max-w-6xl flex-col gap-6 p-4 sm:p-6 lg:p-8">
        <div className="grid gap-1">
          <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
            Claude accounts
          </h1>
          <p className="text-sm text-muted-foreground">{subtitle(s)}</p>
        </div>
        {problem && (
          <p
            role="status"
            className="rounded-lg border border-wait-line bg-wait-bg px-3 py-2 text-sm text-wait-fg"
          >
            {problem}
          </p>
        )}
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {s.accounts.map((a) => (
            <AccountCard key={a.number} account={a} />
          ))}
        </div>
      </div>
    </div>
  )
}
