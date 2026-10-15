// The juel plugin's $.state contract: the STAR band the coordinator session draws above the prompt.
// Named in .claude-plugin/plugin.json as "types". Self-contained: no import, no reference.

export type StarBand = {
  /** ok: work is moving; attention: something waits on the owner; warn: stale tick or gate down; error: a file did not parse. */
  tone: 'ok' | 'idle' | 'attention' | 'warn' | 'error'
  /** The first row, e.g. "STAR · 3 building · 1 babysitting · 2 need you". */
  line: string
  /** Up to three open queue items, "N-12 go-batch · B-x: go for batch B-x: 3 items". */
  needs: readonly string[]
  /** How many open items are not listed. */
  more: number
}

declare module 'claude-code' {
  interface PluginState {
    juel: { band: StarBand | null }
  }
}
