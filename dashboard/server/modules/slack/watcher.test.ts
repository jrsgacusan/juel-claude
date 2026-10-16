import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'

import { inboxText } from './inbox.ts'
import { createSlack, loadConfig, windowStart } from './watcher.ts'
import type { SlackOptions } from './watcher.ts'
import type { Message } from './state.ts'
import {
  answer,
  brief,
  calls,
  cleanup,
  envelope,
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
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  const m = msg({ text: 'is APP-77 landing today?' })
  // The same message twice in one answer counts once.
  await play(w, [answer([m, m])])
  assert.deepEqual(await slack.check(), { ok: true, routed: 1, unrouted: 0 })
  const files = await inboxFiles(app)
  assert.equal(files.length, 1)
  assert.equal(await readFile(join(app.home, 'inbox', files[0] ?? ''), 'utf8'), inboxText(app.repo, m))
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
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
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
  await createSlack(s.api, { now: () => NOW, everyMs: HOUR }).check()
  assert.deepEqual(Object.keys(await readState(w, 'seen.json')), ['C1-1690000000.000000'])
  assert.deepEqual(await readState(w, 'unrouted.json'), ['C1-1690000000.000000'])
  assert.deepEqual(s.events, [{ type: 'change', what: 'slack' }], 'a prune is a change')
  await cleanup(w)
})

async function snapshot(w: World, app: Project): Promise<Record<string, unknown>> {
  const read = async (name: string): Promise<string> => readFile(state(w, name), 'utf8')
  return { seen: await read('seen.json'), routes: await read('routes.json'), unrouted: await read('unrouted.json'), inbox: await inboxFiles(app) }
}

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
  assert.deepEqual(await createSlack(s.api, { now: () => NOW, everyMs: HOUR }).check(), { ok: false, routed: 0, unrouted: 0 })
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
  await createSlack(s.api, { now: () => NOW, everyMs: HOUR }).check()
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
  assert.deepEqual(await createSlack(s.api, { now: () => NOW, everyMs: HOUR }).check(), { ok: true, routed: 0, unrouted: 1 })
  assert.equal(s.events.length, 1)
  await cleanup(w)
})

test('a routed message whose inbox file cannot be written waits in unrouted, and routing it by hand tries again', async () => {
  const w = await world()
  const app = await project(w, 'app', { briefs: { 'fix.md': brief({ name: 'fix', ref: 'APP-77' }) } })
  await writeFile(join(app.home, 'inbox'), 'not a folder')
  const s = stub([app])
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
  await play(w, [answer([msg({ text: 'is APP-77 landing today?' })])])
  assert.deepEqual(await slack.check(), { ok: true, routed: 0, unrouted: 1 })
  assert.equal((await readState(w, 'seen.json'))['C1-1700000000.000100'].project, null)
  assert.deepEqual(await readState(w, 'unrouted.json'), ['C1-1700000000.000100'])
  assert.deepEqual(s.nudges, [])
  assert.ok(s.logs.some(line => line.startsWith('slack: an inbox file could not be written')), s.logs.join('\n'))
  assert.ok(s.logs.includes('slack check: 1 found, 0 routed, 1 unrouted, 0 pruned'), s.logs.join('\n'))
  await rm(join(app.home, 'inbox'))
  assert.deepEqual(await s.call('POST', '/api/slack/C1-1700000000.000100/route', { project: 'app' }), {
    status: 200,
    json: { project: 'app', nudged: true },
  })
  assert.equal((await inboxFiles(app)).length, 1)
  await cleanup(w)
})

test('a project named "none" is never routed to: that name marks a dropped message (D5)', async () => {
  const w = await world()
  const none = await project(w, 'none')
  const s = stub([none])
  await play(w, [answer([msg({ text: 'none of the builds pass' })])])
  assert.deepEqual(await createSlack(s.api, { now: () => NOW, everyMs: HOUR }).check(), { ok: true, routed: 0, unrouted: 1 })
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
  await writeFile(join(app.home, 'inbox', '20261016T110000Z-slack-0002.md'), inboxText(app.repo, withFile))
  await mkdir(join(app.home, 'drafts'), { recursive: true })
  await writeFile(join(app.home, 'drafts', '2026-10-16-app-slack-C1-1700000003.000000.md'), 'to: slack C1 1700000003.000000\nYes.\n')
  const s = stub([app])
  await play(w, [answer([])])
  assert.deepEqual(await createSlack(s.api, { now: () => NOW, everyMs: HOUR }).check(), { ok: true, routed: 3, unrouted: 0 })
  assert.deepEqual(await inboxFiles(app), ['20261016T110000Z-slack-0001.md', '20261016T110000Z-slack-0002.md'])
  assert.equal(await readFile(join(app.home, 'inbox', '20261016T110000Z-slack-0001.md'), 'utf8'), inboxText(app.repo, noFile))
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
  const slack = createSlack(s.api, { now: () => NOW, everyMs: HOUR })
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
