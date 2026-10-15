// STAR's band: what the coordinator session draws above its prompt. A view only: it draws the
// band's model (hooks/star.ts bandOf) with what the owner picked and typed, and every effect goes
// through the actions register.tsx hands in. One quiet line while nothing runs, two while work
// moves, and the queue the owner answers in place once something needs them.

import type { ElementTable, RenderElement } from 'claude-code'

import type { StarAccount, StarAccounts, StarBand, StarGauge, StarNeed } from '../types'
import { NEAR_LIMIT } from './cswap'

export type Ui = Pick<ElementTable<'terminal' | 'desktop'>, 'Box' | 'Text' | 'Button' | 'Input'>

export type BandActions = {
  /** Answer this item next: it becomes the card, and the reply field takes the focus. */
  select: (id: string) => void
  /** Put an option's text in the item's reply field, ready to send or finish. */
  stage: (id: string, text: string) => void
  /** The field's text changed. */
  type: (id: string, text: string) => void
  /** Enter in the field: record the answer through loops.sh and wake STAR. */
  send: (id: string, text: string) => void
}

export type BandView = {
  band: StarBand
  /** cswap's accounts, null when cswap is not installed */
  accounts: StarAccounts | null
  selected: string | null
  drafts: Readonly<Record<string, string>>
  /** e.props.bodyColumns */
  columns: number
}

// Each kind of ask has a color of its own: a chip on the card being answered, a colored word on
// the rows after it, so the queue reads at a glance without shouting.
const KINDS: Readonly<Record<string, { label: string; color: string }>> = {
  'go-batch': { label: 'go', color: 'success' },
  'go-merge': { label: 'merge', color: 'merged' },
  person: { label: 'step', color: 'warning' },
  question: { label: 'ask', color: 'permission' },
  escalation: { label: 'blocked', color: 'error' },
  'accept-report': { label: 'report', color: 'suggestion' },
  'restart-or-drop': { label: 'restart', color: 'warning' },
  draft: { label: 'draft', color: 'ide' },
  held: { label: 'held', color: 'subtle' },
}
const KIND_WIDTH = 8 // 'restart' and 'blocked', plus a space
/** The items the band shows at once: the one being answered, then the next ones, in queue order. */
const MAX_ROWS = 3

const kindOf = (kind: string): { label: string; color: string } =>
  KINDS[kind] ?? { label: (kind || 'item').slice(0, KIND_WIDTH - 1), color: 'subtle' }

const STATES: Readonly<Record<string, { dot: string; color: string }>> = {
  running: { dot: '●', color: 'success' },
  idle: { dot: '○', color: 'subtle' },
  stopped: { dot: '■', color: 'inactive' },
}

// An option that drops or refuses is never drawn as the main action.
const REFUSING = /^(drop|no|not merging|can't now)\b/i

/** Cut a text to `room` cells with an ellipsis. */
export function fit(text: string, room: number): string {
  if (room <= 0) return ''
  return text.length <= room ? text : `${text.slice(0, Math.max(0, room - 1))}…`
}

// A batch id (B-20261015T081200Z-a3f9) is unique by its last four: rows and titles show B-…a3f9.
const BATCH = /\bB-\d{8}T\d{6}Z-([0-9a-f]{4})\b/g
const short = (text: string): string => text.replace(BATCH, 'B-…$1')

function header(ui: Ui, band: StarBand): RenderElement {
  const { Box, Text } = ui
  const st = STATES[band.state] ?? { dot: '◌', color: 'subtle' }
  return (
    <Box flexDirection="row" justifyContent="space-between">
      <Text wrap="truncate-end">
        <Text color="warning">★</Text>
        <Text weight="bold"> STAR</Text>
        {band.project ? <Text dimColor>{`  ${band.project}`}</Text> : ''}
        {'   '}
        <Text color={st.color}>{st.dot}</Text>
        {` ${band.state}`}
        {band.tick ? <Text dimColor>{`, ticked ${band.tick}`}</Text> : ''}
        {band.flags.map(flag =>
          flag === 'away' ? (
            <Text color="permission">{'   ☾ away'}</Text>
          ) : (
            <Text color="warning" weight="bold">{`   ▲ ${flag}`}</Text>
          ),
        )}
      </Text>
      {needsYou(ui, band)}
    </Box>
  )
}

/** The header's right end: how many items wait on the owner, or that none do. */
function needsYou(ui: Ui, band: StarBand): RenderElement | string {
  const { Text } = ui
  if (band.open > 0) {
    return (
      <Text color="warning" weight="bold">
        {` ⚑ ${band.open} need${band.open === 1 ? 's' : ''} you`}
      </Text>
    )
  }
  // A file that did not parse is named on its own line: "nothing needs you" could be wrong then.
  if (band.problems.length) return ''
  return (
    <Text color="success" dimColor>
      {' ✓ nothing needs you'}
    </Text>
  )
}

/** A question's time left in amber, red once it is overdue. */
const dueColor = (due: string): string => (due.endsWith('overdue') ? 'error' : 'warning')

function gauge(ui: Ui, g: StarGauge, isFirst: boolean): RenderElement {
  const { Text } = ui
  // A pool wider than eight slots reads better as a number than as a bar.
  const bar = g.max <= 8
  return (
    <Text>
      {isFirst ? '' : '   '}
      <Text dimColor>{`${g.name} `}</Text>
      {bar ? <Text>{'▰'.repeat(Math.min(g.used, g.max))}</Text> : ''}
      {bar ? <Text dimColor>{'▱'.repeat(Math.max(0, g.max - g.used))}</Text> : ''}
      <Text dimColor={g.used === 0}>{`${bar ? ' ' : ''}${g.used}/${g.max}`}</Text>
    </Text>
  )
}

function pools(ui: Ui, band: StarBand): RenderElement {
  const { Text } = ui
  return <Text wrap="truncate-end">{band.gauges.map((g, k) => gauge(ui, g, k === 0))}</Text>
}

/** Red near the limit, amber from 70%, '' (plain) below that or for last-known numbers. */
function usageColor(pct: number | null, isStale: boolean): string {
  if (pct === null || isStale) return ''
  if (pct >= NEAR_LIMIT) return 'error'
  if (pct >= 70) return 'warning'
  return ''
}

/** A window's share used, as `5h 42%`. */
function used(ui: Ui, label: string, pct: number | null, isStale: boolean): RenderElement {
  const { Text } = ui
  const value = pct === null ? '–' : `${pct}%`
  const color = usageColor(pct, isStale)
  return (
    <Text>
      <Text dimColor>{` ${label} `}</Text>
      {color ? <Text color={color}>{value}</Text> : <Text dimColor={isStale}>{value}</Text>}
    </Text>
  )
}

function account(ui: Ui, a: StarAccount, isFirst: boolean): RenderElement {
  const { Text } = ui
  const isUnread = a.status !== '' && a.fiveHour === null && a.sevenDay === null
  return (
    <Text>
      {isFirst ? '' : '    '}
      {a.isActive ? <Text color="success">{'● '}</Text> : ''}
      <Text weight={a.isActive ? 'bold' : 'regular'} dimColor={!a.isActive}>
        {a.alias}
      </Text>
      {a.isDisabled ? <Text dimColor>{' (disabled)'}</Text> : ''}
      {isUnread ? <Text color="warning">{` ${a.status}`}</Text> : used(ui, '5h', a.fiveHour, a.isStale)}
      {isUnread ? '' : used(ui, '7d', a.sevenDay, a.isStale)}
      {a.resets ? <Text dimColor>{` ↺ ${a.resets}`}</Text> : ''}
    </Text>
  )
}

/** Whether cswap's auto-switch runs for this session's login, and through what. */
function autoBadge(ui: Ui, acc: StarAccounts): RenderElement {
  const { Text } = ui
  switch (acc.state) {
    case 'on':
      return <Text color="success">{` auto on${acc.via ? ` (${acc.via})` : ''}`}</Text>
    case 'dry run':
      return <Text color="warning">{' auto in dry run'}</Text>
    default:
      return <Text dimColor>{' auto off'}</Text>
  }
}

/** cswap's accounts on one row, the one in use first, and its auto-switch on the right. */
function accounts(ui: Ui, acc: StarAccounts): RenderElement {
  const { Box, Text } = ui
  return (
    <Box flexDirection="row" justifyContent="space-between">
      <Text wrap="truncate-end">
        {/* cswap reads the login of this session's Claude config (CLAUDE_CONFIG_DIR): one it does not manage has none in use */}
        {acc.accounts.length && !acc.accounts.some(a => a.isActive) ? <Text dimColor>{'○ none in use here    '}</Text> : ''}
        {acc.accounts.length ? acc.accounts.map((a, k) => account(ui, a, k === 0)) : <Text dimColor>no accounts in cswap</Text>}
        {acc.problem ? <Text color="warning">{`    ${acc.problem}`}</Text> : ''}
      </Text>
      {autoBadge(ui, acc)}
    </Box>
  )
}

/** One of the items after the card: a Button that makes it the card. */
function row(ui: Ui, need: StarNeed, itemWidth: number, columns: number, actions: BandActions): RenderElement {
  const { Button, Text } = ui
  const k = kindOf(need.kind)
  const due = need.due ? `   ${need.due}` : ''
  const room = columns - 2 - KIND_WIDTH - (itemWidth + 2) - due.length
  return (
    <Button key={`row:${need.id}`} plain onPress={() => actions.select(need.id)}>
      {'  '}
      <Text color={k.color}>{k.label.padEnd(KIND_WIDTH)}</Text>
      <Text dimColor>{fit(short(need.item), itemWidth).padEnd(itemWidth + 2)}</Text>
      {fit(short(need.title), room)}
      {need.due ? <Text color={dueColor(need.due)}>{due}</Text> : ''}
    </Button>
  )
}

/** The item being answered: what it says, its options, and the reply field. */
function card(ui: Ui, need: StarNeed, draft: string, columns: number, actions: BandActions): RenderElement {
  const { Box, Button, Input, Text } = ui
  const k = kindOf(need.kind)
  const title = short(need.title)
  // A batch's body is its item names: one line of them reads better than a column.
  const names =
    need.kind === 'go-batch' && need.names.length
      ? [{ key: 'items', value: need.names.join(', ') }]
      : need.names.map(text => ({ key: '', value: text }))
  const lines = [...names, ...need.details]
  const shown = lines.slice(0, 4)
  const keyWidth = Math.min(10, Math.max(0, ...shown.map(l => l.key.length)))
  // The work item, when the title does not already name it, and the time a question has left.
  const item = title.includes(short(need.item)) ? '' : short(need.item)
  return (
    <Box key={`card:${need.id}`} flexDirection="column" borderStyle="round" borderColor={k.color} paddingX={1} width={columns}>
      <Box flexDirection="row" justifyContent="space-between">
        <Text wrap="truncate-end">
          <Text backgroundColor={k.color} color="inverseText" weight="bold">{` ${k.label} `}</Text>
          <Text weight="bold">{` ${title}`}</Text>
        </Text>
        <Text dimColor>
          {item ? ` ${item}` : ''}
          {need.due ? <Text color={dueColor(need.due)}>{`   ${need.due}`}</Text> : ''}
          {`   ${need.id}`}
        </Text>
      </Box>
      {shown.map(l =>
        l.key ? (
          <Text wrap="truncate-middle">
            <Text dimColor>{`${l.key.padEnd(keyWidth)}  `}</Text>
            {l.value}
          </Text>
        ) : (
          // A path or a URL is one word: cut in the middle, it keeps its file name on one row.
          <Text wrap={/\s/.test(l.value) ? 'wrap' : 'truncate-middle'}>{l.value}</Text>
        ),
      )}
      {lines.length > shown.length ? <Text dimColor>{`${lines.length - shown.length} more lines in open-loops.md`}</Text> : ''}
      {need.options.length ? (
        <Box flexDirection="row" flexWrap="wrap" columnGap={1} marginTop={1}>
          {need.options.map((o, n) =>
            n === 0 && !REFUSING.test(o.label) ? (
              <Button key={`opt:${need.id}:${n}`} label={o.label} variant="primary" onPress={() => actions.stage(need.id, o.text)} />
            ) : (
              <Button key={`opt:${need.id}:${n}`} label={o.label} onPress={() => actions.stage(need.id, o.text)} />
            ),
          )}
        </Box>
      ) : (
        ''
      )}
      <Box marginTop={need.options.length ? 0 : 1}>
        <Input
          key={`answer:${need.id}`}
          label="reply"
          placeholder={need.hint}
          value={draft}
          submitLabel="send to STAR"
          autoFocus
          onInput={text => actions.type(need.id, text)}
          onSubmit={text => actions.send(need.id, text)}
        />
      </Box>
    </Box>
  )
}

export function drawBand(ui: Ui, view: BandView, actions: BandActions): RenderElement {
  const { Box, Text } = ui
  const { band, columns } = view
  const problems = band.problems.map(p => (
    <Text color="error" wrap="truncate-end">
      {`✖ ${p}`}
    </Text>
  ))
  const others = band.waiting.length - 1
  const waiting = band.waiting.length ? (
    <Text dimColor wrap="truncate-end">
      {`↻ waiting on others: ${band.waiting[0]}${others ? ` (and ${others} more)` : ''}`}
    </Text>
  ) : (
    ''
  )
  const isQuiet = band.state !== 'running' && !band.problems.length
  const swap = view.accounts ? accounts(ui, view.accounts) : ''

  // Nothing for the owner: one line while STAR is quiet, the pools under it while work moves.
  if (!band.needs.length) {
    return (
      <Box key="star" flexDirection="column" width={columns}>
        {header(ui, band)}
        {isQuiet ? '' : pools(ui, band)}
        {swap}
        {problems}
        {waiting}
      </Box>
    )
  }

  // Something needs the owner. Status on top; under it the one item being answered, as a card in
  // its kind's color, and the next ones to answer as quiet rows. A sent item leaves at once, and
  // the next one moves up.
  const shown = band.needs.slice(0, MAX_ROWS)
  const current = shown.find(n => n.id === view.selected) ?? shown[0]
  const next = shown.filter(n => n.id !== current?.id)
  const itemWidth = Math.min(16, Math.max(6, ...next.map(n => short(n.item).length)))
  const more = band.needs.length - shown.length
  return (
    <Box key="star" flexDirection="column" width={columns}>
      {header(ui, band)}
      {pools(ui, band)}
      {swap}
      {waiting}
      {problems}
      <Box flexDirection="column" marginTop={1}>
        {current ? card(ui, current, view.drafts[current.id] ?? '', columns, actions) : ''}
        {next.map(n => row(ui, n, itemWidth, columns, actions))}
        {more ? <Text dimColor>{`  ${more} more after these`}</Text> : ''}
        <Text dimColor wrap="truncate-end">
          {'  ctrl+x tab to reply, tab to move between items, esc to go back'}
        </Text>
      </Box>
    </Box>
  )
}
