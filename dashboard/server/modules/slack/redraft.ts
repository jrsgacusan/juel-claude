// I-10: redrafting a Slack reply. A request is a file in <home>/slack/redraft/ (the dashboard's route
// writes it, and STAR's slack-redraft.sh does too): `draft:` the draft's path, `loop:` the open
// item's id (N-<n>) and `how:` what to change. The consumer runs the drafter again with the old
// reply and the how, writes the new reply under the draft's first line, records `redrafted` (or
// `redraft failed: <why>`) as the item's answer through STAR's loops.sh, deletes the request and
// nudges STAR. Logs never carry message text.
import { randomBytes } from 'node:crypto'
import { link, lstat, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { basename, dirname, join, resolve } from 'node:path'

import { errorText, runCli } from './claude.ts'
import { MIN_FREE_BYTES, freeMemory, toLine, writeDraft } from './drafter.ts'
import type { Drafter } from './drafter.ts'
import { stamp } from './inbox.ts'
import { oneLine, readSeen } from './state.ts'
import type { Project } from './types.ts'

export type RedraftRequest = { draft: string; loop: string; how: string }

const REQUEST = /^\d{8}T\d{6}Z-[0-9a-f]{4}\.md$/
const SLACK_DRAFT = /-slack-([A-Za-z0-9]+-\d+\.\d+)\.md$/
const flat = (text: string): string => text.replace(/\s+/g, ' ').trim()

export const redraftText = (r: RedraftRequest): string => `draft: ${flat(r.draft)}\nloop: ${flat(r.loop)}\nhow: ${flat(r.how)}\n`

export function parseRedraft(text: string): { draft: string | null; loop: string | null; how: string | null } {
  const field = (name: string): string | null => {
    const line = text.split('\n').find(l => l.startsWith(`${name}:`))
    const value = line === undefined ? '' : line.slice(name.length + 1).trim()
    return value === '' ? null : value
  }
  const loop = field('loop')
  return { draft: field('draft'), loop: loop !== null && /^N-\d+$/.test(loop) ? loop : null, how: field('how') }
}

/** The draft file path is directly in <home>/drafts and named like a Slack draft. */
export const isSlackDraft = (home: string, draft: string): boolean => dirname(resolve(draft)) === join(home, 'drafts') && SLACK_DRAFT.test(basename(draft))

/** The message id (<channelId>-<ts>) a Slack draft is named for. */
export const draftIdOf = (draft: string): string | null => SLACK_DRAFT.exec(basename(draft))?.[1] ?? null

/** Writes a request: a temp file that does not end in .md, then a hard link to its final name. Returns the name. */
export async function writeRedraft(home: string, r: RedraftRequest, at: Date): Promise<string> {
  const dir = join(home, 'slack', 'redraft')
  await mkdir(dir, { recursive: true })
  const tmp = join(dir, `.redraft-${process.pid}-${randomBytes(4).toString('hex')}.tmp`)
  await writeFile(tmp, redraftText(r), { flag: 'wx' })
  try {
    for (let i = 0; i < 20; i += 1) {
      const name = `${stamp(at)}-${randomBytes(2).toString('hex')}.md`
      try {
        await link(tmp, join(dir, name))
        return name
      } catch (err) {
        if ((err as { code?: unknown }).code !== 'EEXIST') throw err
      }
    }
    throw new Error('no free redraft file name after 20 tries')
  } finally {
    await rm(tmp, { force: true })
  }
}

export type RedraftDeps = {
  projects(): Project[]
  draft: Drafter
  loopsSh: string
  nudge(project: string): Promise<boolean>
  changed(): void
  log(line: string): void
}

type Outcome = 'done' | 'waiting'

export function createRedrafter(deps: RedraftDeps): { pass(): Promise<void>; start(everyMs: number): void; stop(): void } {
  let running = false
  let again = false
  let timer: ReturnType<typeof setInterval> | null = null

  /** Records the answer in the open item, deletes the request, nudges STAR when the answer was set. */
  async function finish(project: Project, file: string, loop: string, answer: string): Promise<void> {
    let set = false
    const out = await runCli({
      bin: 'sh',
      args: [deps.loopsSh, '--file', join(project.home, 'open-loops.md'), 'set-answer', loop, answer],
      cwd: project.home,
      input: '',
      timeoutMs: 30_000,
    })
    const said = out.stdout.trim()
    if (out.spawnError === null && out.code === 0 && said === 'set') {
      set = true
    } else {
      const why = oneLine(said || out.stderr.trim().split('\n').pop() || out.spawnError || '')
      deps.log(`slack: a redraft's answer was not recorded: ${loop} ${why}`)
    }
    await rm(join(project.home, 'slack', 'redraft', file), { force: true })
    if (set) await deps.nudge(project.name)
    deps.changed()
  }

  async function one(project: Project, file: string): Promise<Outcome> {
    const home = project.home
    let text: string
    try {
      text = await readFile(join(home, 'slack', 'redraft', file), 'utf8')
    } catch {
      return 'done'
    }
    const { draft, loop, how } = parseRedraft(text)
    if (loop === null) {
      deps.log(`slack: a redraft request with no loop line was removed: ${file}`)
      await rm(join(home, 'slack', 'redraft', file), { force: true })
      return 'done'
    }
    const fail = async (why: string): Promise<Outcome> => {
      await finish(project, file, loop, `redraft failed: ${oneLine(why)}`)
      return 'done'
    }
    if (draft === null || how === null) return fail('the request has no draft or how line')
    const path = resolve(draft)
    if (!isSlackDraft(home, path)) return fail('not a Slack draft')
    const id = draftIdOf(path) as string
    let entry
    try {
      entry = (await readSeen())[id]
    } catch (err) {
      return fail(errorText(err))
    }
    if (entry === undefined) return fail('the Slack message is no longer in seen.json')
    let first = toLine(entry)
    let previous = ''
    try {
      const lines = (await readFile(path, 'utf8')).split('\n')
      first = lines[0] ?? first
      previous = lines.slice(1).join('\n').trim()
    } catch {
      // no draft file yet: the reply starts from the message's own to line
    }
    if ((await freeMemory()) < MIN_FREE_BYTES) {
      deps.log('slack: a redraft waits for free memory')
      return 'waiting'
    }
    const result = await deps.draft({ project, message: entry, how, previous }).catch((err: unknown) => ({ ok: false as const, why: errorText(err) }))
    if (!result.ok) return fail(result.why)
    try {
      await writeDraft(path, first, result.text)
    } catch (err) {
      return fail(`the draft could not be written: ${errorText(err)}`)
    }
    await finish(project, file, loop, 'redrafted')
    return 'done'
  }

  async function files(project: Project): Promise<string[]> {
    const dir = join(project.home, 'slack', 'redraft')
    let names: string[]
    try {
      names = await readdir(dir)
    } catch {
      return []
    }
    const found: string[] = []
    for (const name of names.filter(n => REQUEST.test(n)).sort()) {
      try {
        if ((await lstat(join(dir, name))).isFile()) found.push(name)
      } catch {
        // gone already
      }
    }
    return found
  }

  async function once(): Promise<void> {
    for (const project of deps.projects()) {
      for (const file of await files(project)) {
        try {
          if ((await one(project, file)) === 'waiting') return
        } catch (err) {
          deps.log(`slack: a redraft request failed: ${errorText(err)}`)
        }
      }
    }
  }

  /** Passes never overlap: one asked for while another runs makes one more when it ends. */
  async function pass(): Promise<void> {
    if (running) {
      again = true
      return
    }
    running = true
    try {
      do {
        again = false
        await once()
      } while (again)
    } finally {
      running = false
    }
  }

  const tick = (): void => {
    void pass().catch(err => deps.log(`slack: a redraft pass failed: ${errorText(err)}`))
  }
  return {
    pass,
    start(everyMs) {
      if (timer !== null) return
      timer = setInterval(tick, everyMs)
      timer.unref()
    },
    stop() {
      if (timer !== null) clearInterval(timer)
      timer = null
    },
  }
}
