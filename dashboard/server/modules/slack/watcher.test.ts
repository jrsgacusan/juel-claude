import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import { inboxText } from './inbox.ts'
import { createSlack, loadConfig, windowStart } from './watcher.ts'
import type { SlackOptions } from './watcher.ts'
import type { Message } from './state.ts'
import type { Drafter } from './drafter.ts'
import {
  answer,
  brief,
  calls,
  cleanup,
  drafter,
  envelope,
  freeGb,
  inboxFiles,
  msg,
  play,
  project,
  readState,
  release,
  sleep,
  state,
  stub,
  until,
  world,
  writeState,
} from './test-helpers.ts'
import type { Scenario, World } from './test-helpers.ts'
import type { Project } from './types.ts'

const NOW = new Date('2026-10-16T12:00:00.000Z')
const DAY = 86_400_000
const HOUR = 3_600_000
const config = loadConfig()
const SEEDED = { connected: true, lastCheck: '2026-10-16T11:55:00.000Z', error: null, model: 'haiku', workspace: 'Acme' }

test('windowStart: the last 24 hours first, then lastCheck minus 2 minutes, never more than 24 hours back', () => {
  assert.equal(windowStart(null, NOW).toISOString(), '2026-10-15T12:00:00.000Z')
  assert.equal(windowStart('2026-10-16T11:50:00.000Z', NOW).toISOString(), '2026-10-16T11:48:00.000Z')
  assert.equal(windowStart('2026-10-10T00:00:00.000Z', NOW).toISOString(), '2026-10-15T12:00:00.000Z')
  assert.equal(windowStart('2026-10-17T00:00:00.000Z', NOW).toISOString(), '2026-10-16T11:58:00.000Z')
  assert.equal(windowStart('garbage', NOW).toISOString(), '2026-10-15T12:00:00.000Z')
})

test('a check runs claude read-only from ~/.juel/slack with the window in its prompt', async () => {
  const w = await world()
  const slack = createSlack(stub([]).api, { now: () => NOW, everyMs: HOUR })
  assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 0 })
  const [call] = await calls(w)
  assert.ok(call)
  assert.equal(call.cwd, join(w.home, '.juel', 'slack'))
  const flag = (name: string): string | undefined => call.argv[call.argv.indexOf(name) + 1]
  assert.deepEqual(call.argv.slice(0, 5), ['-p', '--model', 'haiku', '--output-format', 'json'])
  assert.equal(flag('--tools'), '')
  assert.equal(flag('--setting-sources'), '')
  assert.deepEqual(JSON.parse(flag('--settings') ?? ''), { enabledPlugins: { 'slack@anthropic-plugin-directory': true } })
  assert.equal(flag('--allowedTools'), config.allowedTools.join(','))
  assert.equal(flag('--disallowedTools'), config.disallowedTools.join(','))
  assert.equal(flag('--permission-mode'), 'dontAsk')
  assert.ok(call.argv.includes('--no-session-persistence'))
  assert.ok(call.stdin.includes(String((NOW.getTime() - DAY) / 1000)))
  assert.ok(call.stdin.includes('2026-10-15T12:00:00.000Z'))
  assert.ok(!call.stdin.includes('{{'))
  assert.deepEqual(await readState(w, 'status.json'), {
    connected: true,
    lastCheck: NOW.toISOString(),
    error: null,
    model: 'haiku',
    workspace: 'Acme',
    stderr: null,
  })
  await cleanup(w)
})

test('the next check starts 2 minutes before the last successful one', async () => {
  const w = await world()
  await writeState(w, 'status.json', SEEDED)
  await createSlack(stub([]).api, { now: () => NOW, everyMs: HOUR }).check()
  const [call] = await calls(w)
  assert.ok(call?.stdin.includes(String(Date.parse('2026-10-16T11:53:00.000Z') / 1000)))
  await cleanup(w)
})

test("a routed message becomes one inbox file in its project's STAR folder, then a nudge; seen again, nothing happens", async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  const web = await project(w, 'web')
  const s = stub([app, web])
  const d = drafter()
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft })
  const m = msg({ text: 'is APP-77 landing today?' })
  // The same message twice in one answer counts once.
  await play(w, [answer([m, m])])
  assert.deepEqual(await slack.check(), { ok: true, routed: 1, unrouted: 0 })
  const files = await inboxFiles(app)
  assert.equal(files.length, 1)
  assert.equal(await readFile(join(app.home, 'inbox', files[0] ?? ''), 'utf8'), inboxText(app.repo, m, join(app.home, 'drafts', '2026-10-16-app-slack-C1-1700000000.000100.md'), null))
  assert.equal(await readFile(join(app.home, 'drafts', '2026-10-16-app-slack-C1-1700000000.000100.md'), 'utf8'), 'to: slack C1 1700000000.000100\nYes, it lands today.\n')
  assert.equal(d.asked.length, 1)
  assert.deepEqual(await inboxFiles(web), [])
  assert.deepEqual(s.nudges, ['app'])
  assert.deepEqual(s.events, [{ type: 'change', what: 'slack' }])
  assert.deepEqual((await readState(w, 'seen.json'))['C1-1700000000.000100'], {
    ...m,
    seenAt: NOW.toISOString(),
    project: 'app',
    inbox: files[0],
    delivered: true,
  })
  // The next answer lists it again: never routed, written or raised again, and no event.
  await play(w, [answer([m])])
  assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 0 })
  assert.equal((await inboxFiles(app)).length, 1)
  assert.deepEqual(s.nudges, ['app'])
  assert.equal(d.asked.length, 1, 'a message seen again is not drafted again')
  assert.equal(s.events.length, 1, 'a check that changed nothing emits nothing')
  // Routing by content never learns a channel (D3): a later message in C1 naming nothing is unrouted.
  await play(w, [answer([msg({ ts: '1700000003.000000', text: 'and the docs?' })])])
  assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 1 })
  assert.equal((await inboxFiles(app)).length, 1)
  assert.equal(existsSync(state(w, 'routes.json')), false)
  await cleanup(w)
})

test('no match or a tie goes to unrouted.json, with no inbox file and no nudge; listed again, nothing changes', async () => {
  const w = await world()
  const app = await project(w, 'app')
  const web = await project(w, 'web')
  const s = stub([app, web])
  const d = drafter()
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft })
  const none = msg({ ts: '1700000001.000000', text: 'lunch?' })
  const tie = msg({ ts: '1700000002.000000', text: 'app and web are down' })
  await play(w, [answer([none, tie])])
  assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 2 })
  assert.deepEqual(await readState(w, 'unrouted.json'), ['C1-1700000001.000000', 'C1-1700000002.000000'])
  assert.equal((await readState(w, 'seen.json'))['C1-1700000001.000000'].project, null)
  assert.deepEqual(await inboxFiles(app), [])
  assert.deepEqual(await inboxFiles(web), [])
  assert.deepEqual(s.nudges, [])
  assert.equal(s.events.length, 1)
  // D4's overlap lists them again: no new entry, no new id, no event.
  const seen = await readFile(state(w, 'seen.json'), 'utf8')
  assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 0 })
  assert.equal(await readFile(state(w, 'seen.json'), 'utf8'), seen)
  assert.deepEqual(await readState(w, 'unrouted.json'), ['C1-1700000001.000000', 'C1-1700000002.000000'])
  assert.equal(s.events.length, 1)
  await cleanup(w)
})

test('entries seen more than 30 days ago are pruned from seen.json and unrouted.json', async () => {
  const w = await world()
  const old = { ...msg({ ts: '1600000000.000000' }), seenAt: new Date(NOW.getTime() - 31 * DAY).toISOString(), project: null }
  const recent = { ...msg({ ts: '1690000000.000000' }), seenAt: new Date(NOW.getTime() - 29 * DAY).toISOString(), project: null }
  await writeState(w, 'seen.json', { 'C1-1600000000.000000': old, 'C1-1690000000.000000': recent })
  await writeState(w, 'unrouted.json', ['C1-1600000000.000000', 'C1-1690000000.000000'])
  await writeState(w, 'status.json', SEEDED)
  const s = stub([])
  const d = drafter()
  await createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft }).check()
  assert.deepEqual(Object.keys(await readState(w, 'seen.json')), ['C1-1690000000.000000'])
  assert.deepEqual(await readState(w, 'unrouted.json'), ['C1-1690000000.000000'])
  assert.deepEqual(s.events, [{ type: 'change', what: 'slack' }], 'a prune is a change')
  await cleanup(w)
})

async function snapshot(w: World, app: Project): Promise<Record<string, unknown>> {
  const read = async (name: string): Promise<string> => readFile(state(w, name), 'utf8')
  return { seen: await read('seen.json'), routes: await read('routes.json'), unrouted: await read('unrouted.json'), inbox: await inboxFiles(app) }
}

test('a check enables the installed Slack plugin, and dashboard.json can name another (#146)', async () => {
  const w = await world()
  await mkdir(join(w.root, 'claude-config', 'plugins'), { recursive: true })
  await writeFile(join(w.root, 'claude-config', 'plugins', 'installed_plugins.json'), JSON.stringify({ version: 2, plugins: { 'slack@claude-plugins-official': [{ scope: 'user' }] } }))
  const slack = createSlack(stub([]).api, { now: () => NOW, everyMs: HOUR })
  const enabled = async (): Promise<unknown> => {
    const argv = (await calls(w)).at(-1)?.argv ?? []
    return JSON.parse(argv[argv.indexOf('--settings') + 1] ?? '')
  }
  await slack.check()
  assert.deepEqual(await enabled(), { enabledPlugins: { 'slack@claude-plugins-official': true } })
  await mkdir(join(w.home, '.juel'), { recursive: true })
  await writeFile(join(w.home, '.juel', 'dashboard.json'), JSON.stringify({ slack: { plugin: 'slack@mine' } }))
  await slack.check()
  assert.deepEqual(await enabled(), { enabledPlugins: { 'slack@mine': true } })
  await cleanup(w)
})

test('a failed run keeps the last 5 lines of its stderr in status.json; a good check clears them (#146)', async () => {
  const w = await world()
  await play(w, [{ exit: 1, stderr: 'one\ntwo\nthree\nfour\n\nfive\nsix\nseven\n\n' }])
  const slack = createSlack(stub([]).api, { now: () => NOW, everyMs: HOUR })
  await slack.check()
  const failed = await readState(w, 'status.json')
  assert.equal(failed.error, 'claude exited 1: seven')
  assert.equal(failed.stderr, 'three\nfour\nfive\nsix\nseven')
  await play(w, [answer([])])
  await slack.check()
  assert.equal((await readState(w, 'status.json')).stderr, null)
  await cleanup(w)
})

test('the filter drops what is not for the owner before routing: no seen entry, no inbox file (D17)', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  const s = stub([app])
  await play(w, [answer([
    msg({ channelId: 'G0GROUP', channel: 'a DM', ts: '1700000101.000000', text: 'guys para saan yung meeting APP-77', why: 'dm' }),
    msg({ channelId: 'G0GROUP', channel: 'a DM', ts: '1700000102.000000', text: '@Melbs re PR APP-77', why: 'mention' }),
    msg({ channelId: 'D0JUEL', channel: 'a DM', ts: '1700000103.000000', text: 'can you check the build?', why: 'dm' }),
  ])])
  const d = drafter()
  assert.deepEqual(await createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft }).check(), { ok: true, routed: 0, unrouted: 1 })
  assert.deepEqual(Object.keys(await readState(w, 'seen.json')), ['D0JUEL-1700000103.000000'])
  assert.deepEqual(await inboxFiles(app), [])
  assert.ok(s.logs.includes('slack check: 2 dropped by the filter'), s.logs.join('\n'))
  assert.ok(s.logs.includes('slack check: 3 found, 0 routed, 1 unrouted, 0 pruned'), s.logs.join('\n'))
  await cleanup(w)
})

test('the prompt names slack.names as the owner\'s extra names, or none', async () => {
  const w = await world()
  const slack = createSlack(stub([]).api, { now: () => NOW, everyMs: HOUR })
  await slack.check()
  assert.ok((await calls(w)).at(-1)?.stdin.includes('these extra names: none.'))
  await mkdir(join(w.home, '.juel'), { recursive: true })
  await writeFile(join(w.home, '.juel', 'dashboard.json'), JSON.stringify({ slack: { names: ['Jrs', 'JR'] } }))
  await slack.check()
  assert.ok((await calls(w)).at(-1)?.stdin.includes('these extra names: Jrs, JR.'))
  await cleanup(w)
})

const FAILURES: { name: string; scenario: Scenario; connected: boolean; error: RegExp; kind: string; opts?: SlackOptions }[] = [
  {
    name: 'Slack not connected',
    scenario: { stdout: envelope({ connected: false, why: 'no Slack tool' }) },
    connected: false,
    error: /^Slack is not connected: no Slack tool$/,
    kind: 'not-connected',
  },
  { name: 'the CLI failing', scenario: { exit: 1, stderr: 'Error: boom\n' }, connected: true, error: /^claude exited 1: Error: boom$/, kind: 'exit 1' },
  // The fake records its call only once node has started and read stdin; a shorter limit can stop it first on a loaded machine and the call count reads 0. It must also stay well under the fake's 10 s give-up (test-helpers.ts), or the case reports `claude exited 99` instead of a timeout.
  { name: 'the CLI timing out', scenario: { wait: true }, connected: true, error: /^claude did not answer within/, kind: 'timeout', opts: { timeoutMs: 3000 } },
  {
    name: 'an is_error envelope',
    scenario: { stdout: envelope('boom', { is_error: true, subtype: 'error_during_execution' }) },
    connected: true,
    error: /^claude reported an error/,
    kind: 'cli-error',
  },
  { name: 'output that is not JSON', scenario: { stdout: 'Here you go' }, connected: true, error: /^the answer is not the expected JSON/, kind: 'bad-json' },
  {
    name: 'one invalid message',
    scenario: { stdout: envelope([msg({ text: 'APP-77 SECRET' }), { ...msg(), ts: 'x' }]) },
    connected: true,
    error: /message 2: ts is not a Slack ts/,
    kind: 'bad-json',
  },
]

for (const f of FAILURES) {
  test(`${f.name}: status.json gets it, nothing else changes, and nothing retries`, async () => {
    const w = await world()
    const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
    await writeState(w, 'status.json', SEEDED)
    await writeState(w, 'seen.json', {})
    await writeState(w, 'routes.json', {})
    await writeState(w, 'unrouted.json', [])
    const before = await snapshot(w, app)
    const s = stub([app])
    await play(w, [f.scenario])
    const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR, ...f.opts })
    assert.deepEqual(await slack.check(), { ok: false, routed: 0, unrouted: 0 })
    const status = await readState(w, 'status.json')
    assert.equal(status.connected, f.connected)
    assert.match(status.error, f.error)
    assert.equal(status.lastCheck, SEEDED.lastCheck)
    assert.equal(status.stderr, f.scenario.stderr ? f.scenario.stderr.trim() : null)
    // D8: not connected means no workspace is known; any other failure changes nothing else.
    assert.equal(status.workspace, f.connected ? 'Acme' : null)
    assert.deepEqual(await snapshot(w, app), before)
    assert.deepEqual(s.nudges, [])
    assert.deepEqual(s.logs, [`slack check failed: ${f.kind}`])
    assert.equal(s.events.length, 1, 'the error is a change')
    await sleep(100)
    assert.equal((await calls(w)).length, 1, 'no retry before the next interval')
    await slack.check()
    assert.equal(s.events.length, 1, 'the same failure again changes nothing status.json shows')
    // The next good check clears the error, and says so once.
    await play(w, [answer([])])
    assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 0 })
    const cleared = await readState(w, 'status.json')
    assert.equal(cleared.error, null)
    assert.equal(cleared.connected, true)
    assert.equal(cleared.lastCheck, NOW.toISOString())
    assert.equal(s.events.length, 2)
    await cleanup(w)
  })
}

test('a claude that cannot start is a CLI failure', async () => {
  const w = await world()
  const s = stub([])
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR, bin: join(w.root, 'no-such-claude') })
  assert.deepEqual(await slack.check(), { ok: false, routed: 0, unrouted: 0 })
  assert.match((await readState(w, 'status.json')).error, /^claude could not start: .*ENOENT/)
  assert.deepEqual(s.logs, ['slack check failed: spawn'])
  await cleanup(w)
})

test('a damaged seen.json fails the check before claude runs, and is left as it is', async () => {
  const w = await world()
  await writeState(w, 'seen.json', '{not json')
  const s = stub([])
  const d = drafter()
  assert.deepEqual(await createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft }).check(), { ok: false, routed: 0, unrouted: 0 })
  assert.equal(await readFile(state(w, 'seen.json'), 'utf8'), '{not json')
  assert.match((await readState(w, 'status.json')).error, /seen\.json is not JSON/)
  assert.deepEqual(await calls(w), [])
  assert.deepEqual(s.logs, ['slack check failed: state'])
  await cleanup(w)
})

test('one check at a time: a timer tick during a run is skipped', async () => {
  const w = await world()
  await play(w, [{ wait: true, stdout: envelope({ workspace: 'Acme', messages: [] }) }])
  const slack = createSlack(stub([]).api, { now: () => NOW, everyMs: 20 })
  slack.start()
  await until(async () => (await calls(w)).length === 1)
  assert.equal(await slack.check(), null, 'a second check while one runs is refused')
  await sleep(200)
  assert.equal((await calls(w)).length, 1, 'the ticks during the run were skipped')
  await release(w)
  await until(async () => (await calls(w)).length >= 2)
  slack.stop()
  await until(async () => (await slack.check()) !== null)
  await cleanup(w)
})

test('the log gets counts and errors only: never text, a name or a channel', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  const s = stub([app], { nudge: async () => false })
  await play(w, [
    answer([
      msg({ channelId: 'C77', channel: '#eng-private', from: 'Ria Santos', text: 'APP-77 SECRET-WORDS' }),
      msg({ ts: '1700000009.000000', channel: '#ops', from: 'Bo Diaz', text: 'OTHER-SECRET' }),
    ]),
  ])
  const d = drafter()
  await createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft }).check()
  assert.ok(s.logs.some(line => line === 'slack check: 2 found, 1 routed, 1 unrouted, 0 pruned'), s.logs.join('\n'))
  for (const line of s.logs) {
    for (const leak of ['SECRET', 'Ria', 'Santos', 'Diaz', 'eng-private', '#ops', 'C77', 'C1-']) {
      assert.ok(!line.includes(leak), `${line} leaks ${leak}`)
    }
  }
  await cleanup(w)
})

test('an emit or a log that throws never fails a check', async () => {
  const w = await world()
  const s = stub([], { throws: true })
  await play(w, [answer([msg({ text: 'lunch?' })])])
  const d = drafter()
  assert.deepEqual(await createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft }).check(), { ok: true, routed: 0, unrouted: 1 })
  assert.equal(s.events.length, 1)
  await cleanup(w)
})

test('a routed message whose inbox file cannot be written waits in unrouted, and routing it by hand tries again', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  await writeFile(join(app.home, 'inbox'), 'not a folder')
  const s = stub([app])
  const d = drafter()
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft })
  await play(w, [answer([msg({ text: 'is APP-77 landing today?' })])])
  assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 1 })
  assert.equal((await readState(w, 'seen.json'))['C1-1700000000.000100'].project, null)
  assert.deepEqual(await readState(w, 'unrouted.json'), ['C1-1700000000.000100'])
  assert.deepEqual(s.nudges, [])
  assert.ok(s.logs.some(line => line.startsWith('slack: an inbox file could not be written')), s.logs.join('\n'))
  assert.ok(s.logs.includes('slack check: 1 found, 0 routed, 1 unrouted, 0 pruned'), s.logs.join('\n'))
  await rm(join(app.home, 'inbox'))
  assert.equal(d.asked.length, 1)
  assert.deepEqual(await s.call('POST', '/api/slack/C1-1700000000.000100/route', { project: 'app' }), {
    status: 200,
    json: { project: 'app', drafting: true },
  })
  await slack.idle()
  assert.equal((await inboxFiles(app)).length, 1)
  assert.equal(d.asked.length, 1, 'the draft written by the first check is reused')
  await cleanup(w)
})

test('a project named "none" is never routed to: that name marks a dropped message (D5)', async () => {
  const w = await world()
  const none = await project(w, 'none')
  const s = stub([none])
  await play(w, [answer([msg({ text: 'none of the builds pass' })])])
  const d = drafter()
  assert.deepEqual(await createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft }).check(), { ok: true, routed: 0, unrouted: 1 })
  assert.deepEqual(await inboxFiles(none), [])
  assert.deepEqual(s.nudges, [])
  await cleanup(w)
})

test('a hand-over a crash left half done is finished by the next check, exactly once', async () => {
  const w = await world()
  const app = await project(w, 'app')
  const at = '2026-10-16T11:00:00.000Z'
  const pending = (m: Message, inbox: string): Record<string, unknown> => ({ ...m, seenAt: at, project: 'app', inbox, delivered: false })
  const noFile = msg({ ts: '1700000001.000000', text: 'one' }) // committed, then a crash before its file
  const withFile = msg({ ts: '1700000002.000000', text: 'two' }) // its file written, then a crash before the mark
  const drafted = msg({ ts: '1700000003.000000', text: 'three' }) // STAR drafted it and deleted the file
  await writeState(w, 'seen.json', {
    'C1-1700000001.000000': pending(noFile, '20261016T110000Z-slack-0001.md'),
    'C1-1700000002.000000': pending(withFile, '20261016T110000Z-slack-0002.md'),
    'C1-1700000003.000000': pending(drafted, '20261016T110000Z-slack-0003.md'),
  })
  // A route by hand that a crash cut short also leaves its id here.
  await writeState(w, 'unrouted.json', ['C1-1700000001.000000'])
  await writeState(w, 'status.json', SEEDED)
  await mkdir(join(app.home, 'inbox'), { recursive: true })
  const draftOf = (ts: string): string => join(app.home, 'drafts', `2026-10-16-app-slack-C1-${ts}.md`)
  await writeFile(join(app.home, 'inbox', '20261016T110000Z-slack-0002.md'), inboxText(app.repo, withFile, draftOf('1700000002.000000'), null))
  await mkdir(join(app.home, 'drafts'), { recursive: true })
  await writeFile(draftOf('1700000002.000000'), 'to: slack C1 1700000002.000000\nYes.\n')
  await writeFile(draftOf('1700000003.000000'), 'to: slack C1 1700000003.000000\nYes.\n')
  const s = stub([app])
  const d = drafter()
  await play(w, [answer([])])
  assert.deepEqual(await createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft }).check(), { ok: true, routed: 3, unrouted: 0 })
  // drafted's file is written again: the copy slack-handled.sh drops.
  assert.deepEqual(await inboxFiles(app), ['20261016T110000Z-slack-0001.md', '20261016T110000Z-slack-0002.md', '20261016T110000Z-slack-0003.md'])
  assert.equal(await readFile(join(app.home, 'inbox', '20261016T110000Z-slack-0001.md'), 'utf8'), inboxText(app.repo, noFile, draftOf('1700000001.000000'), null))
  assert.equal(await readFile(join(app.home, 'inbox', '20261016T110000Z-slack-0003.md'), 'utf8'), inboxText(app.repo, drafted, draftOf('1700000003.000000'), null))
  assert.deepEqual(d.asked.map(r => r.message.ts), ['1700000001.000000'])
  const seen = await readState(w, 'seen.json')
  for (const id of ['C1-1700000001.000000', 'C1-1700000002.000000', 'C1-1700000003.000000']) assert.equal(seen[id].delivered, true, id)
  assert.deepEqual(await readState(w, 'unrouted.json'), [])
  assert.deepEqual(s.nudges, ['app'])
  await cleanup(w)
})

test('workspace is the one this answer names: a bare array leaves it null (D8)', async () => {
  const w = await world()
  await writeState(w, 'status.json', SEEDED)
  await play(w, [{ stdout: envelope([]) }])
  assert.deepEqual(await createSlack(stub([]).api, { now: () => NOW, everyMs: HOUR }).check(), { ok: true, routed: 0, unrouted: 0 })
  assert.equal((await readState(w, 'status.json')).workspace, null)
  await cleanup(w)
})

test('a pending hand-over that cannot be finished stays pending, out of unrouted, until a later check finishes it', async () => {
  const w = await world()
  const app = await project(w, 'app')
  const m = msg({ ts: '1700000001.000000', text: 'one' })
  const id = 'C1-1700000001.000000'
  await writeState(w, 'seen.json', { [id]: { ...m, seenAt: '2026-10-16T11:00:00.000Z', project: 'app', inbox: '20261016T110000Z-slack-0001.md', delivered: false } })
  await writeState(w, 'status.json', SEEDED)
  // STAR's drafts folder cannot be read: whether STAR already has this message is unknown.
  await writeFile(join(app.home, 'drafts'), 'not a folder')
  const s = stub([app])
  const d = drafter()
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft })
  await play(w, [answer([])])
  assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 0 })
  const after = await readState(w, 'seen.json')
  assert.equal(after[id].project, 'app')
  assert.equal(after[id].delivered, false)
  assert.deepEqual(await readState(w, 'unrouted.json'), [])
  assert.deepEqual(await inboxFiles(app), [])
  assert.deepEqual(s.nudges, [])
  assert.ok(s.logs.some(line => line.startsWith('slack: a pending hand-over could not be finished')), s.logs.join('\n'))
  // The folder is readable again: the next check finishes it.
  await rm(join(app.home, 'drafts'))
  assert.deepEqual(await slack.check(), { ok: true, routed: 1, unrouted: 0 })
  assert.deepEqual(await inboxFiles(app), ['20261016T110000Z-slack-0001.md'])
  assert.equal((await readState(w, 'seen.json'))[id].delivered, true)
  assert.deepEqual(s.nudges, ['app'])
  await cleanup(w)
})

test('one drafter at a time: a check and a route by hand share it, and an in-flight hand-over is not started twice', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  let active = 0
  let most = 0
  const asked: string[] = []
  const draft: Drafter = async req => {
    asked.push(req.message.ts)
    active += 1
    most = Math.max(most, active)
    await sleep(150)
    active -= 1
    return { ok: true, text: 'ok' }
  }
  const s = stub([app])
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft })
  await play(w, [answer([msg({ ts: '1700000001.000000', text: 'lunch?' })])])
  await slack.check()
  assert.equal((await s.call('POST', '/api/slack/C1-1700000001.000000/route', { project: 'app' })).status, 200)
  await play(w, [answer([msg({ ts: '1700000002.000000', text: 'is APP-77 landing today?' })])])
  await slack.check()
  await slack.idle()
  assert.equal(most, 1)
  assert.deepEqual(asked.sort(), ['1700000001.000000', '1700000002.000000'])
  assert.equal((await inboxFiles(app)).length, 2)
  await cleanup(w)
})

test('the draft is written before the inbox file that names it (I-11)', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  const seenInbox: string[][] = []
  const draft: Drafter = async () => {
    seenInbox.push(await inboxFiles(app))
    return { ok: true, text: 'Yes.' }
  }
  await play(w, [answer([msg({ text: 'is APP-77 landing today?' })])])
  await createSlack(stub([app]).api, { now: () => NOW, everyMs: HOUR, draft }).check()
  assert.deepEqual(seenInbox, [[]])
  assert.equal((await inboxFiles(app)).length, 1)
  await cleanup(w)
})

test('a drafter that fails still hands the message over, with a draft holding only its to line and drafterError', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  const s = stub([app])
  const d = drafter([{ ok: false, why: 'the drafter did not answer within 600 s' }])
  const m = msg({ text: 'is APP-77 landing today?' })
  await play(w, [answer([m])])
  assert.deepEqual(await createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft }).check(), { ok: true, routed: 1, unrouted: 0 })
  const path = join(app.home, 'drafts', '2026-10-16-app-slack-C1-1700000000.000100.md')
  assert.equal(await readFile(path, 'utf8'), 'to: slack C1 1700000000.000100\n')
  const [file] = await inboxFiles(app)
  assert.equal(await readFile(join(app.home, 'inbox', file ?? ''), 'utf8'), inboxText(app.repo, m, path, 'the drafter did not answer within 600 s'))
  assert.deepEqual(s.nudges, ['app'])
  await cleanup(w)
})

test('below 3 GB free, a hand-over waits for the next check (I-12)', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  const s = stub([app])
  const d = drafter()
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR, draft: d.draft })
  await freeGb(w, 1)
  await play(w, [answer([msg({ text: 'is APP-77 landing today?' })])])
  assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 0 })
  assert.equal(d.asked.length, 0)
  assert.deepEqual(await inboxFiles(app), [])
  assert.equal(existsSync(join(app.home, 'drafts')), false)
  const entry = (await readState(w, 'seen.json'))['C1-1700000000.000100']
  assert.equal(entry.project, 'app')
  assert.equal(entry.delivered, false)
  assert.ok(s.logs.includes('slack: a hand-over waits for free memory: 1.0 GB free, 3 GB needed'), s.logs.join('\n'))
  await freeGb(w, 4)
  assert.deepEqual(await slack.check(), { ok: true, routed: 1, unrouted: 0 })
  assert.equal((await inboxFiles(app)).length, 1)
  assert.equal(d.asked.length, 1)
  await cleanup(w)
})

test('a draft already there for the message is used, never drafted again, and never stops the hand-over', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  const d = drafter()
  const m = msg({ text: 'is APP-77 landing today?' })
  const path = join(app.home, 'drafts', '2026-10-15-app-slack-C1-1700000000.000100.md')
  await mkdir(join(app.home, 'drafts'), { recursive: true })
  await writeFile(path, 'to: slack C1 1700000000.000100\nYes.\n')
  await play(w, [answer([m])])
  assert.deepEqual(await createSlack(stub([app]).api, { now: () => NOW, everyMs: HOUR, draft: d.draft }).check(), { ok: true, routed: 1, unrouted: 0 })
  assert.equal(d.asked.length, 0)
  const [file] = await inboxFiles(app)
  assert.equal(await readFile(join(app.home, 'inbox', file ?? ''), 'utf8'), inboxText(app.repo, m, path, null))
  await cleanup(w)
})
