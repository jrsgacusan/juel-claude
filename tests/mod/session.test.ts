// The mod as the engine loads it: the test answers the world beneath it (env, process, files,
// clock) and acts as a session does (session.start, a tool call, drawing the band).
import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'

import { CSWAP_LIST, CSWAP_LIST_FULL, HOME, LEDGER, QUEUE, ROOT, STAR, ledger } from './fixtures'

const SHA = 'b'.repeat(40)
const BAND_PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 12,
  bodyColumns: 100,
  scroll: { offset: 0, bodyRows: 11 },
  view: {},
}

type World = {
  files: Map<string, string>
  mtimes: Map<string, number>
  ran: string[]
  looked: (readonly string[])[]
  /** loops.sh set-answer calls, as `<id> <text>` */
  answered: string[]
  /** prompts the mod submitted */
  prompts: string[]
  toasts: string[]
  /** what `cswap list --json` prints; null when cswap is not installed */
  cswap: string | null
  /** what `ps -Ao command` prints */
  ps: string
  /** cswap list calls made */
  listed: number
  /** commands the mod started detached (`cswap auto`) */
  started: string[][]
  /** while true, a started cswap auto exits at once instead of showing up in ps */
  isStartDying: boolean
  /** while true, the guard's `$.clock.now()` is refused, which fails the guard's handler */
  isClockDown: boolean
}

type Clock = Pick<ReturnType<typeof mock.clock>, 'settle'>

/**
 * A clock the test can break: it answers `clock.now` itself (`mock.clock` cannot refuse a read),
 * and holds no timers, so the world is built with the band off. Real time settles a start.
 */
function brokenClock(on: On, w: World): Clock {
  on('clock.now', () => (w.isClockDown ? { deny: 'clock down' } : { value: Date.parse('2026-10-15T08:05:00Z') }))
  return { settle: () => new Promise<void>(done => setTimeout(done, 50)) }
}

function world(on: On, handle: string, root = ROOT, isClockBroken = false, env: Record<string, string> = {}): { clock: Clock; w: World } {
  const w: World = {
    files: new Map([
      [`${HOME}/star.json`, STAR('term_A')],
      [`${HOME}/ledger.md`, LEDGER],
      [`${HOME}/open-loops.md`, QUEUE],
    ]),
    mtimes: new Map(),
    ran: [],
    looked: [],
    answered: [],
    prompts: [],
    toasts: [],
    cswap: null,
    ps: '',
    listed: 0,
    started: [],
    isStartDying: false,
    isClockDown: false,
  }
  // An empty handle stands for a session outside Orca: the variable is unset.
  mock.env(on, handle ? { ORCA_TERMINAL_HANDLE: handle, ...env } : env)
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  // The engine's own band, which a plugin that passes leaves in place.
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return h(Text, {}, 'engine band') as RenderElement
  })
  const clock = isClockBroken ? brokenClock(on, w) : mock.clock(on, { now: Date.parse('2026-10-15T08:05:00Z') })
  on('process.run', ($, e) => {
    const out = (stdout: string, exitCode = 0) => ({
      value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
    })
    if (e.argv[0]?.endsWith('cswap')) {
      w.listed += 1
      return w.cswap === null ? out('', 127) : out(w.cswap)
    }
    if (e.argv[0] === 'ps') {
      // w.ps holds one process per line, its environment after the command as `NAME=value` words:
      // `ps -Ao pid=,command=` prints the command alone, `ps eww ... -p <pids>` the environment too.
      const lines = w.ps.split('\n').filter(Boolean).map((line, k) => [String(k + 1), line] as const)
      if (e.argv[1] !== 'eww') return out(lines.map(([pid, line]) => `${pid} ${line.replace(/\s[A-Z_][A-Z0-9_]*=\S+/g, '')}`).join('\n'))
      const asked = (e.argv[e.argv.indexOf('-p') + 1] ?? '').split(',')
      return out(lines.filter(([pid]) => asked.includes(pid)).map(([pid, line]) => `${pid} ${line}`).join('\n'))
    }
    if (e.argv[0] === 'python3') {
      // the detach launcher: python3 -c <script> <argv...>
      const argv = e.argv.slice(3)
      w.started.push(argv)
      // the started loop inherits the session's environment, and with it its Claude login
      const login = env['CLAUDE_CONFIG_DIR'] ? ` CLAUDE_CONFIG_DIR=${env['CLAUDE_CONFIG_DIR']}` : ''
      if (!w.isStartDying) w.ps += `/Users/me/.local/bin/${argv.join(' ')}${login}\n`
      return out('')
    }
    if (e.argv[0] === 'crontab') return out('', 1)
    const at = e.argv.indexOf('set-answer')
    if (at < 0) {
      w.looked.push(e.argv)
      return { value: { exitCode: 0, stdout: `${HOME}\n`, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
    // loops.sh set-answer: the item's Answer line gets the text, as the script writes it.
    const [id, text] = [e.argv[at + 1] ?? '', e.argv[at + 2] ?? '']
    w.answered.push(`${id} ${text}`)
    const path = `${HOME}/open-loops.md`
    const queue = w.files.get(path) ?? ''
    const item = new RegExp(`(### ${id} · [^\\n]*\\n(?:(?!### )[^\\n]*\\n)*?)Answer:\\n`)
    w.files.set(path, queue.replace(item, `$1Answer: ${text}\n`))
    w.mtimes.set(path, (w.mtimes.get(path) ?? 1) + 1)
    return { value: { exitCode: 0, stdout: 'set\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('prompt.submit', ($, e) => {
    w.prompts.push(e.text)
    return { text: e.text }
  })
  on('ui.toast', ($, e) => {
    w.toasts.push(e.text)
    return { value: undefined }
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
  expect(await ui.find({ type: 'Text', text: /2 needs? you/ })).toBeDefined()
  // the first open item is the card; the next one is a row
  expect(await ui.find({ type: 'Input', key: 'answer:N-12' })).toBeDefined()
  expect(await ui.find({ type: 'Button', key: 'row:N-14' })).toBeDefined()
  // N-13 is answered: STAR acts on it next, so the band does not list it
  expect(await ui.find({ type: 'Text', text: /N-13/ })).toBeUndefined()
  // the build gauge: two building rows of three slots
  expect(await ui.find({ type: 'Text', text: /^ 2\/3$/ })).toBeDefined()

  w.files.set(`${HOME}/ledger.md`, ledger([['issue-1', 'building', '/w/app-issue-1']]))
  w.mtimes.set(`${HOME}/ledger.md`, 2)
  await clock.advance(5_000)
  expect(await ui.find({ type: 'Text', text: /^ 2\/3$/ })).toBeUndefined()
  expect((await ui.findAll({ type: 'Text', text: /^ [0-9]\/[0-9]$/ })).map(t => t.text)).toEqual([' 0/4', ' 1/3', ' 0/3'])
  await ui.unmount()
})

test('the card for the first open item carries its options and a reply field', async ($, on) => {
  const { clock } = world(on, 'term_A')
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  const labels = (await ui.findAll({ type: 'Button' })).filter(b => b.key?.startsWith('opt:')).map(b => b.props['label'])
  expect(labels).toEqual(['go', 'go except …', 'drop …'])
  expect((await ui.find({ type: 'Input', key: 'answer:N-12' }))?.props['placeholder']).toBe('or type an answer in words')

  // An option fills the field; it sends nothing by itself.
  await ui.press({ key: 'opt:N-12:1' })
  expect((await ui.find({ type: 'Input', key: 'answer:N-12' }))?.props['value']).toBe('go except ')

  // Another row makes that item the card.
  await ui.press({ key: 'row:N-14' })
  expect(await ui.find({ type: 'Input', key: 'answer:N-12' })).toBeUndefined()
  expect((await ui.find({ type: 'Input', key: 'answer:N-14' }))?.props['placeholder']).toBe('answer with your decision')
  await ui.unmount()
})

test('Enter records the answer through loops.sh and wakes STAR with inbox', async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  await ui.input({ key: 'answer:N-12', text: '  go  ' })
  expect(w.answered).toEqual(['N-12 go'])
  expect(w.prompts).toEqual(['inbox'])
  expect(w.toasts).toEqual(['Sent “go” to STAR for N-12'])
  // The sent item leaves the list, and the card moves on to the next open one.
  expect(await ui.find({ type: 'Text', text: /N-12/ })).toBeUndefined()
  expect(await ui.find({ type: 'Input', key: 'answer:N-14' })).toBeDefined()
  await ui.unmount()
})

test('the band lists three items at a time, and the next one moves up after a send', async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  const extra = [15, 16, 17].map(n => `### N-${n} · app · issue-${n} · ask ${n}\nkind: question\nAnswer:\n\n`).join('')
  w.files.set(`${HOME}/open-loops.md`, QUEUE.replace('## Waiting on others', `${extra}## Waiting on others`))
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  const rows = async (): Promise<(string | undefined)[]> =>
    (await ui.findAll({ type: 'Button' })).map(b => b.key).filter(k => k?.startsWith('row:'))
  // three at a time: the one being answered as the card, the next two as rows
  expect(await ui.find({ type: 'Input', key: 'answer:N-12' })).toBeDefined()
  expect(await rows()).toEqual(['row:N-14', 'row:N-15'])
  expect(await ui.find({ type: 'Text', text: /^ {2}2 more after these$/ })).toBeDefined()
  await ui.input({ key: 'answer:N-12', text: 'go' })
  expect(await ui.find({ type: 'Input', key: 'answer:N-14' })).toBeDefined()
  expect(await rows()).toEqual(['row:N-15', 'row:N-16'])
  expect(await ui.find({ type: 'Text', text: /^ {2}1 more after these$/ })).toBeDefined()
  await ui.unmount()
})

test("the band shows cswap's accounts and its auto-switch, read once a minute", { options: { star_cswap_auto: false } }, async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  w.cswap = CSWAP_LIST
  w.ps = '/Users/me/.local/bin/cswap auto --threshold 80\n'
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  for (const alias of ['personal', 'sphere', 'carol', 'old']) expect(await ui.find({ type: 'Text', text: alias })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '98%' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: ' ↺ 1d 23h' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: ' token expired' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: ' auto on (cswap auto)' })).toBeDefined()
  expect(w.listed).toBe(1)

  // the loop stops: the band says so at the next read, a minute on, not at the next 5-second tick
  w.ps = ''
  await clock.advance(5_000)
  expect(w.listed).toBe(1)
  expect(await ui.find({ type: 'Text', text: ' auto on (cswap auto)' })).toBeDefined()
  await clock.advance(60_000)
  expect(w.listed).toBe(2)
  expect(await ui.find({ type: 'Text', text: ' auto off' })).toBeDefined()
  await ui.unmount()
})

test("the band draws cswap's full payload exactly as the short one", { options: { star_cswap_auto: false } }, async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  w.cswap = CSWAP_LIST_FULL
  w.ps = '/Users/me/.local/bin/cswap auto --threshold 80\n'
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  for (const alias of ['personal', 'sphere', 'carol', 'old']) expect(await ui.find({ type: 'Text', text: alias })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '98%' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: ' ↺ 1d 23h' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: ' token expired' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: ' auto on (cswap auto)' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Fable|5d 23h|2026-11-13/ })).toBeUndefined()
  await ui.unmount()
})

test("a session whose login cswap does not manage says none is in use", async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  w.cswap = CSWAP_LIST.replace('"active":true', '"active":false')
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  expect(await ui.find({ type: 'Text', text: /none in use here/ })).toBeDefined()
  await ui.unmount()
})

test("STAR's session starts cswap auto when it is off, and the band says so", async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  w.cswap = CSWAP_LIST
  await start($)
  await clock.settle()
  expect(w.started).toEqual([['cswap', 'auto']])
  expect(w.toasts).toEqual(['Started cswap auto: it switches accounts before one hits its limit'])
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  expect(await ui.find({ type: 'Text', text: ' auto on (cswap auto)' })).toBeDefined()
  // running now: the next reads start nothing more
  await clock.advance(65_000)
  expect(w.started.length).toBe(1)
  await ui.unmount()
})

test("a cswap auto for another Claude login does not count: STAR starts one for its own", async ($, on) => {
  const sphere = { CLAUDE_CONFIG_DIR: '/Users/me/.claude-sphere', HOME: '/Users/me' }
  const { clock, w } = world(on, 'term_A', ROOT, false, sphere)
  w.cswap = CSWAP_LIST
  w.ps = '/Users/me/.local/bin/cswap auto CLAUDE_CONFIG_DIR=/Users/me/.claude-personal\n'
  await start($)
  await clock.settle()
  expect(w.started).toEqual([['cswap', 'auto']])
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  expect(await ui.find({ type: 'Text', text: ' auto on (cswap auto)' })).toBeDefined()
  await ui.unmount()
})

test('a cswap auto that does not stay up is started again only after ten minutes', async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  w.cswap = CSWAP_LIST
  w.isStartDying = true
  await start($)
  await clock.settle()
  expect(w.started.length).toBe(1)
  expect(w.toasts).toEqual([])
  await clock.advance(5 * 60_000)
  expect(w.started.length).toBe(1)
  await clock.advance(5 * 60_000)
  expect(w.started.length).toBe(2)
})

test('cswap auto is not started while a dry run of it runs', async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  w.cswap = CSWAP_LIST
  w.ps = '/Users/me/.local/bin/cswap auto --dry-run\n'
  await start($)
  await clock.settle()
  expect(w.started).toEqual([])
})

test('cswap auto is not started with star_cswap_auto off', { options: { star_cswap_auto: false } }, async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  w.cswap = CSWAP_LIST
  await start($)
  await clock.settle()
  await clock.advance(65_000)
  expect(w.started).toEqual([])
})

test('without cswap the band has no accounts row', async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  expect(w.listed).toBe(1)
  expect(await ui.find({ type: 'Text', text: /auto (on|off)/ })).toBeUndefined()
  await ui.unmount()
})

test('a session that is not the coordinator never runs cswap', async ($, on) => {
  const { clock, w } = world(on, 'term_B')
  w.cswap = CSWAP_LIST
  await start($)
  await clock.settle()
  await clock.advance(65_000)
  expect(w.listed).toBe(0)
})

test("Orca's nudge typed into the focused field is not sent: STAR is woken instead", async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  await ui.input({ key: 'answer:N-12', text: 'You have 1', kind: 'change' })
  await ui.input({ key: 'answer:N-12', text: 'You have 1 orchestration message. Run orca orchestration check --run run_x.' })
  expect(w.answered).toEqual([])
  expect(w.prompts).toEqual(['inbox'])
  expect(w.toasts).toEqual(["N-12: that was Orca's message for STAR, not your answer, so nothing was sent"])
  expect((await ui.find({ type: 'Input', key: 'answer:N-12' }))?.props['value']).toBe('')
  await ui.unmount()
})

test('the hint says how to reach the field: a click in fullscreen, ctrl+x tab on the classic screen', async ($, on) => {
  const { clock } = world(on, 'term_A')
  await start($)
  await clock.settle()
  const hint = async (isFullscreen: boolean): Promise<string | undefined> => {
    const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS, viewport: { columns: 120, rows: 40, isFullscreen } })
    const found = (await ui.find({ type: 'Text', text: /to go back$/ }))?.text
    await ui.unmount()
    return found
  }
  expect(await hint(true)).toContain('click here to reply')
  expect(await hint(false)).toContain('clicks need fullscreen: /tui fullscreen')
})

test('an answer with no letter or digit is not sent', async ($, on) => {
  const { clock, w } = world(on, 'term_A')
  await start($)
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'juel', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  await ui.input({ key: 'answer:N-12', text: '?!' })
  expect(w.answered).toEqual([])
  expect(w.prompts).toEqual([])
  expect(w.toasts).toEqual(['N-12: type an answer in words first'])
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
  expect(merged.deny).toContain('--head <sha> --home')
  expect(merged.deny).not.toContain('--grant')
  expect(merged.deny).not.toContain('go-merge')
  const read = await $.tool.call({ tool: 'Read', file_path: `${HOME}/reviews/app/issue-1-r1.md` })
  expect(read.deny).toContain('a review file')
  const tailed = await $.tool.call({ tool: 'Bash', command: `tail -n 20 ${HOME}/progress/issue-1.log` })
  expect(tailed.deny).toContain('a log file')
  const viaScript = `sh /p/skills/star/merge.sh https://github.com/o/r/pull/12 --head ${SHA} --home ${HOME} --item issue-1`
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

// The Bash guard's `.catch` handler runs when the guard fails (an engine timeout, a throw), and then
// the session's role is unknown. A worker's guard reads the clock to decide, so a refused clock
// fails it. Only a merge, which every guarded role forbids, is refused then.
test('when the guard fails, a direct merge is still refused, with the suffix saying so', { options: { star_band: false } }, async ($, on) => {
  const { clock, w } = world(on, 'term_W', '/w/app-issue-1', true)
  await start($)
  await clock.settle()
  w.isClockDown = true
  const merged = await $.tool.call({ tool: 'Bash', command: 'gh pr merge 12 --squash' })
  expect(merged.deny).toContain('a direct merge (gh pr merge) is refused')
  expect(merged.deny).toContain("(the guard could not confirm the session's role, so it refused)")
  expect(w.ran).toEqual([])
})

test('when the guard fails, a merge behind a review-file read is refused as a merge, not as a read', { options: { star_band: false } }, async ($, on) => {
  const { clock, w } = world(on, 'term_W', '/w/app-issue-1', true)
  await start($)
  await clock.settle()
  w.isClockDown = true
  const hidden = await $.tool.call({ tool: 'Bash', command: `cat ${HOME}/reviews/app/issue-1-r1.md && gh pr merge 12` })
  expect(hidden.deny).toContain('a direct merge (gh pr merge) is refused')
  expect(hidden.deny).not.toContain('a review file')
  expect(w.ran).toEqual([])
})
