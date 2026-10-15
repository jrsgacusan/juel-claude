// The mod as the engine loads it: the test answers the world beneath it (env, process, files,
// clock) and acts as a session does (session.start, a tool call, drawing the band).
import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'

import { HOME, LEDGER, QUEUE, ROOT, STAR, ledger } from './fixtures'

const SHA = 'b'.repeat(40)
const BAND_PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 12,
  bodyColumns: 100,
  scroll: { offset: 0, bodyRows: 11 },
  view: {},
}

type World = { files: Map<string, string>; mtimes: Map<string, number>; ran: string[]; looked: (readonly string[])[] }

function world(on: On, handle: string, root = ROOT): { clock: ReturnType<typeof mock.clock>; w: World } {
  const w: World = {
    files: new Map([
      [`${HOME}/star.json`, STAR('term_A')],
      [`${HOME}/ledger.md`, LEDGER],
      [`${HOME}/open-loops.md`, QUEUE],
    ]),
    mtimes: new Map(),
    ran: [],
    looked: [],
  }
  // An empty handle stands for a session outside Orca: the variable is unset.
  mock.env(on, handle ? { ORCA_TERMINAL_HANDLE: handle } : {})
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  // The engine's own band, which a plugin that passes leaves in place.
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return h(Text, {}, 'engine band') as RenderElement
  })
  const clock = mock.clock(on, { now: Date.parse('2026-10-15T08:05:00Z') })
  on('process.run', ($, e) => {
    w.looked.push(e.argv)
    return { value: { exitCode: 0, stdout: `${HOME}\n`, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.root', () => ({ value: root }))
  on('fs.read', ($, e) => {
    const text = w.files.get(e.path)
    return text === undefined ? { deny: `ENOENT ${e.path}` } : { value: text }
  })
  on('fs.stat', ($, e) => ({
    value: { kind: 'file' as const, size: 1, mtimeMs: w.mtimes.get(e.path) ?? 1, isLink: false, realPath: e.path },
  }))
  // The bottom of the tool chain: the "tool" records what it was asked to run.
  on('tool.call', ($, e) => {
    w.ran.push('command' in e && typeof e.command === 'string' ? e.command : String(e.tool))
    return { result: { stdout: '', stderr: '', interrupted: false } }
  })
  return { clock, w }
}

async function start($: Engine): Promise<void> {
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
}

test('the coordinator gets the band, and it follows the ledger', async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  const line = await ui.find({ type: 'Text', text: /^STAR/ })
  expect(line?.text).toBe('STAR · 2 building · 1 babysitting · 1 verifying · 1 escalated · 2 waiting · 2 need you')
  expect(await ui.find({ type: 'Text', text: /N-12 go-batch/ })).toBeDefined()

  w.files.set(`${HOME}/ledger.md`, ledger([['issue-1', 'building', '/w/app-issue-1']]))
  w.mtimes.set(`${HOME}/ledger.md`, 2)
  await clock.advance(5_000)
  const after = await ui.find({ type: 'Text', text: /^STAR/ })
  expect(after?.text).toBe('STAR · 1 building · 2 need you')
  await ui.unmount()
})

test('another terminal in the same project gets no band and no guard', async ($, on) => {
  const { clock, w } = world(on, 'term_B')
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  expect(await ui.find({ type: 'Text', text: /^STAR/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'engine band' })).toBeDefined()
  await ui.unmount()
  const merged = await $.tool.call({ tool: 'Bash', command: 'gh pr merge 12 --squash' })
  expect(merged.deny).toBeUndefined()
  const read = await $.tool.call({ tool: 'Read', file_path: `${HOME}/reviews/app/issue-1-r1.md` })
  expect(read.deny).toBeUndefined()
  expect(w.ran).toEqual(['gh pr merge 12 --squash', 'Read'])
})

test('the coordinator cannot merge directly or read a review in', async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  await start($)
  await clock.settle()
  const merged = await $.tool.call({ tool: 'Bash', command: 'gh pr merge 12 --squash' })
  expect(merged.deny).toContain('merge.sh')
  const read = await $.tool.call({ tool: 'Read', file_path: `${HOME}/reviews/app/issue-1-r1.md` })
  expect(read.deny).toContain('a review file')
  const tailed = await $.tool.call({ tool: 'Bash', command: `tail -n 20 ${HOME}/progress/issue-1.log` })
  expect(tailed.deny).toContain('a log file')
  const viaScript = `sh /p/skills/star/merge.sh https://github.com/o/r/pull/12 --head ${SHA} --grant g.md`
  const ok = await $.tool.call({ tool: 'Bash', command: viaScript })
  expect(ok.deny).toBeUndefined()
  expect(w.ran).toEqual([viaScript])
})

test('#114: a worker of a running STAR gets ${NAME:?} in rm paths, when switched on', { options: { star_rm_guard: true } }, async ($, on) => {
  const { clock, w } = world(on, 'term_W', '/w/app-issue-1')
  await start($)
  await clock.settle()
  await $.tool.call({ tool: 'Bash', command: 'rmdir $S/$v' })
  await $.tool.call({ tool: 'Bash', command: 'ls $S' })
  expect(w.ran).toEqual(['rmdir ${S:?}/${v:?}', 'ls $S'])
})

test('#114: off by default', async ($, on) => {
  const { clock, w } = world(on, 'term_W', '/w/app-issue-1')
  await start($)
  await clock.settle()
  await $.tool.call({ tool: 'Bash', command: 'rmdir $S/$v' })
  expect(w.ran).toEqual(['rmdir $S/$v'])
})

test('a session outside an Orca terminal looks nothing up and passes everything', async ($, on) => {
  const { clock, w } = world(on, '')
  await start($)
  await clock.settle()
  expect(w.looked).toEqual([])
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  expect(await ui.find({ type: 'Text', text: /^STAR/ })).toBeUndefined()
  await ui.unmount()
  const merged = await $.tool.call({ tool: 'Bash', command: 'gh pr merge 12 --squash' })
  expect(merged.deny).toBeUndefined()
  const read = await $.tool.call({ tool: 'Read', file_path: `${HOME}/reviews/app/issue-1-r1.md` })
  expect(read.deny).toBeUndefined()
  expect(w.ran).toEqual(['gh pr merge 12 --squash', 'Read'])
})

test('a session in an Orca terminal looks the STAR folder up once, with star-home.sh', async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  await start($)
  await clock.settle()
  expect(w.looked.length).toBe(1)
  expect(w.looked[0]?.[1]?.endsWith('/skills/star/star-home.sh')).toBe(true)
  expect(w.looked[0]?.slice(2)).toEqual(['--cwd', ROOT, 'path'])
})

test('a STAR worker cannot merge directly, and reads what it likes', async ($, on) => {
  const { clock, w } = world(on, 'term_W', '/w/app-issue-1')
  await start($)
  await clock.settle()
  const merged = await $.tool.call({ tool: 'Bash', command: 'gh pr merge 12 --squash' })
  expect(merged.deny).toContain('a STAR worker never merges a PR')
  const hidden = await $.tool.call({ tool: 'Bash', command: `cat ${HOME}/reviews/app/issue-1-r1.md && gh pr merge 12` })
  expect(hidden.deny).toContain('a STAR worker never merges a PR')
  const read = await $.tool.call({ tool: 'Read', file_path: `${HOME}/reviews/app/issue-1-r1.md` })
  expect(read.deny).toBeUndefined()
  const tailed = `tail -n 20 ${HOME}/progress/issue-1.log`
  const tail = await $.tool.call({ tool: 'Bash', command: tailed })
  expect(tail.deny).toBeUndefined()
  expect(w.ran).toEqual(['Read', tailed])
})

test('a session whose worktree is no running row is not a worker, and may merge', async ($, on) => {
  const { clock, w } = world(on, 'term_W', '/w/app-issue-7')
  await start($)
  await clock.settle()
  const merged = await $.tool.call({ tool: 'Bash', command: 'gh pr merge 12 --squash' })
  expect(merged.deny).toBeUndefined()
  expect(w.ran).toEqual(['gh pr merge 12 --squash'])
})
