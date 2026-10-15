// juel's hooks module: STAR's band and guards in the coordinator session, the merge guard and the
// #114 rm/rmdir rewrite in STAR's worker sessions. Lives inside the juel plugin so it can run
// skills/star/star-home.sh (the one place that knows where a project's STAR folder is) from
// $.plugin.root.
//
// Who is who, decided from files and the environment, never from chat:
//   coordinator  ORCA_TERMINAL_HANDLE is set and equals star.json's "terminal" (as hooks/star-session.sh)
//   worker       ORCA_TERMINAL_HANDLE is set, STAR is running (terminal set, not this one), and the
//                session's root is the worktree of a ledger row in a worker state
//   anything else: every hook here passes the event on untouched. Without ORCA_TERMINAL_HANDLE the
//                session is never either, so nothing is looked up at all.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { StarBand } from '../types'
import { fallbackDeny, guardRmVars, judge, protectedWhy } from './guards'
import type { Protect, Verdict } from './guards'
import { WORKER_STATES, bandOf, parseLedger, parseQueue, parseStar } from './star'
import type { LedgerRow, Parsed, Queue, Star } from './star'

type Api = EngineInterface

const band = atom({ plugin: 'juel', key: 'band' } as const, null)
const TICK_MS = 5_000
const ROLE_TTL_MS = 60_000

type Place = {
  home: string
  protect: Protect
  handle: string
  /** realpath of the session's root, to match a ledger row's worktree */
  root: string
}

// Module state: lost on a reload, and session.start runs again in the fresh copy and rebuilds it.
let place: Place | null = null
let lastBand = 'null'
const cache = new Map<string, { mtimeMs: number; value: unknown }>()
let workerAt = 0
let isWorkerCached = false

async function realOf($: Api, path: string): Promise<string | undefined> {
  return $.fs.stat(path, { resolve: true }).then(s => s.realPath).catch(() => undefined)
}

async function readStar($: Api, home: string): Promise<Parsed<Star & { repo: string }>> {
  try {
    const text = await $.fs.read(`${home}/star.json`)
    const star = parseStar(text)
    if (!star.ok) return star
    const project = (JSON.parse(text) as { project?: { repo?: unknown } }).project
    return { ok: true, value: { ...star.value, repo: typeof project?.repo === 'string' ? project.repo : '' } }
  } catch {
    return { ok: false, why: 'star.json missing' }
  }
}

/** A file parsed again only when its mtime moved; a file that cannot be read is a parse failure. */
async function parsedFile<T>($: Api, path: string, parse: (text: string) => Parsed<T>): Promise<Parsed<T>> {
  try {
    const { mtimeMs } = await $.fs.stat(path)
    const hit = cache.get(path)
    if (hit && hit.mtimeMs === mtimeMs) return hit.value as Parsed<T>
    const value = parse(await $.fs.read(path))
    cache.set(path, { mtimeMs, value })
    return value
  } catch {
    return { ok: false, why: 'cannot be read' }
  }
}

async function lookUp($: Api, cwd: string, handle: string): Promise<Place | null> {
  const run = await $.process
    .run(['sh', `${$.plugin.root}/skills/star/star-home.sh`, '--cwd', cwd, 'path'], { timeoutMs: 10_000 })
    .catch(() => undefined)
  const home = run && run.exitCode === 0 ? run.stdout.trim() : ''
  if (!home) return null
  const real = await realOf($, home)
  const star = await readStar($, home)
  const docsRoot = home.replace(/\/context\/star$/, '')
  const repo = star.ok ? star.value.repo : ''
  const docsRel = repo && docsRoot.startsWith(`${repo}/`) ? docsRoot.slice(repo.length + 1) : 'docs/superpowers'
  const root = (await realOf($, await $.session.root())) ?? cwd
  return { home, handle, root, protect: { homes: real && real !== home ? [home, real] : [home], docsRel, cwd } }
}

/** Read fresh at the moment a guard would refuse: STAR may have been claimed or stopped since the last tick. */
async function isCoordinator($: Api, p: Place): Promise<boolean> {
  if (!p.handle) return false
  const star = await readStar($, p.home)
  return star.ok && star.value.terminal === p.handle
}

async function isWorker($: Api, p: Place): Promise<boolean> {
  const now = await $.clock.now()
  if (now - workerAt < ROLE_TTL_MS) return isWorkerCached
  workerAt = now
  isWorkerCached = false
  const star = await readStar($, p.home)
  if (!p.handle || !star.ok || !star.value.terminal || star.value.terminal === p.handle) return false
  const ledger = await parsedFile<LedgerRow[]>($, `${p.home}/ledger.md`, parseLedger)
  if (!ledger.ok) return false
  for (const row of ledger.value) {
    if (!(WORKER_STATES as readonly string[]).includes(row.state) || row.worktree === '-') continue
    const real = (await realOf($, row.worktree)) ?? row.worktree
    if (real === p.root) { isWorkerCached = true; break }
  }
  return isWorkerCached
}

async function refresh($: Api): Promise<void> {
  const p = place
  let next: StarBand | null = null
  if (p) {
    const star = await readStar($, p.home)
    if (star.ok && p.handle && star.value.terminal === p.handle) {
      const ledger = await parsedFile<LedgerRow[]>($, `${p.home}/ledger.md`, parseLedger)
      const queue = await parsedFile<Queue>($, `${p.home}/open-loops.md`, parseQueue)
      next = bandOf(star.value, ledger, queue, await $.clock.now())
    }
  }
  const text = JSON.stringify(next)
  if (text === lastBand) return // no write, so no redraw
  lastBand = text
  await update($, band, () => next)
}

/** The deny text a STAR worker gets for a direct merge: only STAR merges, through merge.sh. */
function workerMergeText(how: string): string {
  return (
    `juel STAR guard: a direct merge (${how}) is refused here: a STAR worker never merges a PR. ` +
    `Leave the PR open and say so in your report; STAR merges it through merge.sh once the merge ` +
    `gate passes on its head and the owner has said go.`
  )
}

function denyText(v: Verdict, p: Place, root: string): string {
  if (v.kind === 'merge') {
    return (
      `juel STAR guard: a direct merge (${v.how}) is refused in the STAR coordinator. STAR merges only ` +
      `through merge.sh, on the exact head pr-verify.sh --merge-gate passed, under the item's grant: ` +
      `sh ${root}/skills/star/merge.sh <pr url> --head <sha> --grant <grant file> --home ${p.home} --item <item>. ` +
      `If the merge gate has not passed, run it first; without the owner's go, queue a go-merge item.`
    )
  }
  return (
    `juel STAR guard: ${v.path} is ${v.why}, and the STAR coordinator never reads review, evidence or ` +
    `log content into its session. Use the script that reads it and prints one line (done-check.sh, ` +
    `pr-verify.sh --merge-gate, step-check.sh), or count with grep -c, grep -q or wc -l. ` +
    `If the owner needs it, give them the path.`
  )
}

const commandOfCall = (e: { tool: string; command?: unknown }): string =>
  typeof e.command === 'string' ? e.command : ''

export const register: Register = (on, options) => {
  const isBandOn = options['star_band'] !== false
  const isGuardOn = options['star_guards'] !== false
  const isRmOn = options['star_rm_guard'] === true

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    // Never hold the first prompt for a git and python3 call: look the folder up in the background.
    void (async () => {
      // STAR's coordinator and its workers each run in an Orca terminal. A session without a
      // handle is neither: it looks nothing up, and every hook below passes its events through.
      const handle = (await $.env.get('ORCA_TERMINAL_HANDLE')) ?? ''
      if (!handle) return
      place = await lookUp($, e.cwd, handle).catch(() => null)
      if (!place || !isBandOn) return
      await refresh($).catch(() => undefined)
      $.clock.every(TICK_MS, () => {
        void refresh($).catch(() => undefined)
      })
    })()
    return started
  })

  // The band: only while this session is the coordinator; a survey always wins the band.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const value = await read($, band)
    if (value === null || e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const color = { ok: 'success', idle: 'subtle', attention: 'warning', warn: 'warning', error: 'error' }[value.tone]
    return (
      <Box key="star" flexDirection="column" width={e.props.bodyColumns}>
        <Text color={color} wrap="truncate-end">
          {value.line}
        </Text>
        {value.needs.map(line => (
          <Text dimColor wrap="truncate-end">
            {'  '}
            {line}
          </Text>
        ))}
        {value.more > 0 && <Text dimColor>{`  +${value.more} more in open-loops.md`}</Text>}
      </Box>
    )
  })

  // Guard 1 and 2 for shell commands: a direct merge (the coordinator and STAR's workers), and a
  // review, evidence or log file read in (the coordinator only). It judges the text first (pure,
  // cheap) and reads STAR's files only for a command it would refuse.
  on('tool.call', { tool: ['Bash', 'Monitor'] }, async ($, e, next) => {
    const p = place
    if (!isGuardOn || !p) return next(e)
    const command = commandOfCall(e)
    const verdict = judge(command, p.protect)
    if (!verdict) return next(e)
    if (await isCoordinator($, p)) return { deny: denyText(verdict, p, $.plugin.root) }
    // A worker may read what it likes; judged with no protected paths, only a merge is left.
    const merge = verdict.kind === 'merge' ? verdict : judge(command, undefined)
    if (merge?.kind === 'merge' && (await isWorker($, p))) return { deny: workerMergeText(merge.how) }
    return next(e)
  }).catch(($, e, next) => {
    // The guard failed (threw, timed out) or was asked again beneath its own $ call, so the role is
    // unknown. Refuse only a merge, which every guarded role forbids; a read passes (the session may
    // be a worker or a person's own), and the SessionStart prose rule stays the backstop for it.
    if (next.called) return next(e)
    const p = place
    const verdict = fallbackDeny(e)
    return verdict && p ? { deny: `${denyText(verdict, p, $.plugin.root)} (the guard could not confirm the session's role, so it refused)` } : next(e)
  })

  // Guard 2 for the Read tool. The realpath catches a link or a `..` spelling of a protected path.
  on('tool.call', { tool: 'Read' }, async ($, e, next) => {
    const p = place
    if (!isGuardOn || !p) return next(e)
    const real = await realOf($, e.file_path)
    const why = protectedWhy(e.file_path, p.protect) ?? (real ? protectedWhy(real, p.protect) : undefined)
    if (!why || !(await isCoordinator($, p))) return next(e)
    return { deny: denyText({ kind: 'read', path: e.file_path, why }, p, $.plugin.root) }
  }).catch(($, e, next) => {
    // The guard failed, so the role is unknown. The read guard is the coordinator's only, and a Read
    // is never a merge (fallbackDeny: a merge is all a failed guard refuses), so it always passes.
    return next(e)
  })

  // #114 spike, off unless star_rm_guard is set: in a STAR worker (and its subagents, whose calls
  // raise tool.call too), rm/rmdir/unlink on a bare $VAR becomes ${VAR:?}. Not a gate: a failure
  // here leaves the command as the model wrote it.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const p = place
    if (!isRmOn || !p) return next(e)
    const guarded = guardRmVars(e.command)
    if (!guarded || !(await isWorker($, p))) return next(e)
    $.ui.log(`rm/rmdir variables written as \${NAME:?} (#114): ${guarded.slice(0, 200)}`, { to: 'debug' })
    return next({ ...e, command: guarded })
  })
}
