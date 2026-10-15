// The juel plugin's $.state contract: the STAR band the coordinator session draws above the prompt,
// and what the owner has picked and typed in it. Named in .claude-plugin/plugin.json as "types".
// Self-contained: no import, no reference.

/** One pool's slots: rows in its worker states, out of its size in star.json. */
export type StarGauge = {
  /** brief, build or babysit */
  name: string
  used: number
  max: number
}

/** One `key: value` line of a queue item's body, e.g. brief: <path>, step: 2. */
export type StarDetail = {
  key: string
  value: string
}

/** A pick from the item's `Options:` line: the button's label, and the text it puts in the field. */
export type StarOption = {
  label: string
  text: string
}

/** One Needs-you item as the band shows it. */
export type StarNeed = {
  /** N-12 */
  id: string
  /** go-batch, person, question, escalation, ... (loops.sh --kind) */
  kind: string
  item: string
  title: string
  /** Body lines that are not `key: value`, e.g. a batch's item names. */
  names: readonly string[]
  details: readonly StarDetail[]
  options: readonly StarOption[]
  /** The field's placeholder: the options that ask for words, or a plain prompt. */
  hint: string
  /** For a worker's question: "23m left" or "5m overdue"; null otherwise. */
  due: string | null
}

export type StarBand = {
  /** ok: work is moving; attention: something waits on the owner; warn: stale tick or gate down; error: a file did not parse. */
  tone: 'ok' | 'idle' | 'attention' | 'warn' | 'error'
  /** The whole state in one line, e.g. "STAR · 3 building · 1 babysitting · 2 need you". */
  line: string
  /** project.name from star.json, '' when absent. */
  project: string
  /** The Resume block's state: running, idle, stopped. */
  state: string
  /** When the last tick was, "just now" or "12m ago"; null when the queue has none. */
  tick: string | null
  gauges: readonly StarGauge[]
  /** away, gate down, a stale tick */
  flags: readonly string[]
  /** A file that did not parse, with why. */
  problems: readonly string[]
  /** How many items wait on the owner (open, not yet answered). */
  open: number
  /** The open items, in the queue's order. An answered one is left out: STAR acts on it next. */
  needs: readonly StarNeed[]
  /** The Waiting on others lines. */
  waiting: readonly string[]
}

/** One account claude-swap (cswap) manages, as the band shows it. */
export type StarAccount = {
  /** cswap's slot number */
  number: number
  /** cswap's alias; the email's name, or #<slot>, when it has none */
  alias: string
  /** the account Claude Code uses now */
  isActive: boolean
  /** held out of auto-rotation with cswap disable */
  isDisabled: boolean
  /** share of the 5-hour window used, 0 to 100; null when unknown */
  fiveHour: number | null
  /** share of the 7-day window used, 0 to 100; null when unknown */
  sevenDay: number | null
  /** for an account at or past 90% of a window: when that window resets, e.g. "1d 23h" */
  resets: string | null
  /** the numbers are cswap's last-known ones: a fresh reading is unavailable */
  isStale: boolean
  /** '' when cswap reads the usage fine; else its usageStatus in words, e.g. "token expired" */
  status: string
}

/** Whether cswap's auto-switch is running, and through what. */
export type StarAuto = {
  state: 'on' | 'off' | 'dry run'
  /** cswap auto, menu bar or cron; '' when off */
  via: string
}

export type StarAccounts = StarAuto & {
  accounts: readonly StarAccount[]
  /** why the last read failed, '' when it did not; the accounts are then the last ones read */
  problem: string
}

declare module 'claude-code' {
  interface PluginState {
    juel: {
      band: StarBand | null
      /** The item the owner is answering, by id; null picks the first open one. */
      selected: string | null
      /** What the owner has typed for each item, by id, kept until it is sent. */
      drafts: Readonly<Record<string, string>>
      /** The accounts cswap manages, when cswap is installed; null otherwise. */
      accounts: StarAccounts | null
    }
  }
}
