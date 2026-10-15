import assert from 'node:assert/strict'
import { mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises'
import { basename, join } from 'node:path'
import { afterEach, beforeEach, test } from 'node:test'

import { briefingDir, createBriefing, readDraft, readTurns } from './store.ts'
import { block, calls, cleanup, done, hook, init, play, reads, say, world } from './test-helpers.ts'
import type { World } from './test-helpers.ts'
import { PROMPT_URL, repoPath, runTurn, turnArgs } from './turn.ts'
import type { TurnContext } from './turn.ts'

const T1 = { title: 'Retry the sync', description: 'The sync drops on a flaky network.', criteria: ['A failed sync retries once'], outOfScope: ['Backoff tuning'] }
const T2 = { ...T1, criteria: [...T1.criteria, 'The retry is logged'] }
const R1 = `First answer.\n\n${block(T1)}`
const R2 = `Second answer.\n\n${block(T2)}`

let w: World
let dir: string
let events: Record<string, unknown>[]
beforeEach(async () => {
  w = await world()
  dir = briefingDir(w.home, await createBriefing(w.home))!
  events = []
})
afterEach(async () => {
  await cleanup(w)
})

const ctx = (text: string): TurnContext => ({
  project: 'proj',
  id: basename(dir),
  repo: w.repo,
  dir,
  text,
  emit: event => { events.push(event) },
  log: () => {},
})
const exists = (path: string): Promise<boolean> => stat(path).then(() => true, () => false)
const snapshot = async (): Promise<[string, string]> => [await readFile(join(dir, 'transcript.jsonl'), 'utf8'), await readFile(join(dir, 'draft.json'), 'utf8')]

test('a first turn runs the read-only agent in the repo and saves the session, the draft and both turns', async () => {
  const reply = `I read src/sync.ts. Who sees the failure?\n\n${block(T1)}`
  await play(w, 'claude', [{ lines: [hook, init('S1'), reads(join(w.repo, 'src/sync.ts'), '/etc/hosts'), say(reply), done(reply)] }])
  const result = await runTurn(ctx('Add a retry to the sync'))
  assert.equal(result.ok, true)

  const [call] = await calls(w, 'claude')
  const prompt = await readFile(PROMPT_URL, 'utf8')
  assert.deepEqual(call.argv, ['-p', '--model', 'opus', '--output-format', 'stream-json', '--verbose', '--tools', 'Read,Grep,Glob', '--strict-mcp-config', '--allowedTools', 'Read,Grep,Glob', '--append-system-prompt', prompt, '--', 'Add a retry to the sync'])
  assert.equal(call.cwd, w.repo)
  assert.equal(call.stdin, '')

  assert.equal((await readFile(join(dir, 'session'), 'utf8')).trim(), 'S1')
  assert.deepEqual(await readDraft(dir), T1)
  const turns = await readTurns(dir)
  assert.deepEqual(turns.map(({ who, text, files }) => ({ who, text, files })), [
    { who: 'me', text: 'Add a retry to the sync', files: [] },
    { who: 'agent', text: 'I read src/sync.ts. Who sees the failure?', files: ['src/sync.ts', '/etc/hosts'] },
  ])
  assert.ok(turns.every(turn => !Number.isNaN(Date.parse(turn.at))))

  assert.ok(events.every(event => event.type === 'briefing' && event.project === 'proj' && event.id === basename(dir)))
  const shown = events.map(event => event.turn as Record<string, unknown>)
  assert.deepEqual(shown.at(-1), { who: 'agent', text: 'I read src/sync.ts. Who sees the failure?', files: ['src/sync.ts', '/etc/hosts'], done: true, draft: T1 })
  assert.ok(shown.length >= 3)
  assert.ok(shown.slice(0, -1).every(turn => turn.done === false))
  assert.ok(shown.every(turn => !String(turn.text).includes('```')))
})

test('a later turn resumes the saved session', async () => {
  await play(w, 'claude', [{ lines: [init('S1'), say(R1), done(R1)] }, { lines: [init('S1'), say(R2), done(R2)] }])
  assert.equal((await runTurn(ctx('one'))).ok, true)
  assert.equal((await runTurn(ctx('two'))).ok, true)
  const [first, second] = await calls(w, 'claude')
  assert.equal(first.argv.includes('--resume'), false)
  assert.deepEqual(second.argv.slice(-4), ['--resume', 'S1', '--', 'two'])
  assert.deepEqual(await readDraft(dir), T2)
  assert.equal((await readTurns(dir)).length, 4)
})

test('a resume that comes back with another session id keeps the new one', async () => {
  await play(w, 'claude', [{ lines: [init('S1'), say(R1), done(R1)] }, { lines: [init('S2'), say(R2), done(R2)] }])
  await runTurn(ctx('one'))
  await runTurn(ctx('two'))
  assert.equal((await readFile(join(dir, 'session'), 'utf8')).trim(), 'S2')
})

test('text that starts with a dash reaches the agent as text', async () => {
  await play(w, 'claude', [{ lines: [init('S1'), say(R1), done(R1)] }])
  await runTurn(ctx('--help me scope this'))
  const [call] = await calls(w, 'claude')
  assert.deepEqual(call.argv.slice(-2), ['--', '--help me scope this'])
})

test('a turn whose CLI exits non-zero keeps the transcript and the draft and emits the error', async () => {
  await play(w, 'claude', [{ lines: [init('S1'), say(R1), done(R1)] }, { lines: [init('S1'), say('Half a reply')], stderr: 'API Error: overloaded\n', exit: 1 }])
  await runTurn(ctx('one'))
  const before = await snapshot()
  events.length = 0
  const result = await runTurn(ctx('two'))
  assert.equal(result.ok, false)
  assert.deepEqual(await snapshot(), before)
  const failed = events.at(-1)!
  assert.equal(failed.type, 'briefing')
  assert.equal(failed.project, 'proj')
  assert.equal(failed.id, basename(dir))
  assert.match(String(failed.error), /overloaded/)
  assert.equal('turn' in failed, false)
})

test('a reply with no valid ticket block is a failed turn that writes nothing', async () => {
  const bad = 'No block.\n\n```ticket\n{"title": ""}\n```'
  await play(w, 'claude', [{ lines: [init('S1'), say(R1), done(R1)] }, { lines: [init('S1'), say(bad), done(bad)] }])
  await runTurn(ctx('one'))
  const before = await snapshot()
  const result = await runTurn(ctx('two'))
  assert.deepEqual(result, { ok: false, error: 'the reply had no valid ticket block' })
  assert.deepEqual(await snapshot(), before)
  assert.equal(events.at(-1)!.error, 'the reply had no valid ticket block')
})

test('a result line with is_error is a failed turn', async () => {
  await play(w, 'claude', [{ lines: [init('S1'), say(R1), done('Prompt is too long', true)] }])
  const result = await runTurn(ctx('one'))
  assert.equal(result.ok, false)
  assert.match(String(events.at(-1)!.error), /too long/)
  assert.equal(await exists(join(dir, 'draft.json')), false)
})

test('a turn that fails before its init event leaves no session, so the next one starts fresh', async () => {
  await play(w, 'claude', [{ stderr: 'Not logged in\n', exit: 1 }, { lines: [init('S9'), say(R1), done(R1)] }])
  assert.equal((await runTurn(ctx('one'))).ok, false)
  assert.equal(await exists(join(dir, 'session')), false)
  assert.equal(await exists(join(dir, 'transcript.jsonl')), false)
  assert.equal((await runTurn(ctx('one'))).ok, true)
  const [, second] = await calls(w, 'claude')
  assert.equal(second.argv.includes('--resume'), false)
  assert.equal((await readFile(join(dir, 'session'), 'utf8')).trim(), 'S9')
})

test('claude missing from PATH is a failed turn', async () => {
  const empty = join(w.root, 'empty-bin')
  await mkdir(empty)
  process.env.PATH = empty // nothing at all on PATH, so no real claude can be found either
  const result = await runTurn(ctx('one'))
  assert.equal(result.ok, false)
  assert.match(String(events.at(-1)!.error), /could not start/)
})

test('repoPath keeps a path outside the repo absolute', () => {
  assert.equal(repoPath('/r/repo', '/r/repo/a/b.ts'), 'a/b.ts')
  assert.equal(repoPath('/r/repo', '/r/repo-other/x.ts'), '/r/repo-other/x.ts')
  assert.equal(repoPath('/r/repo', '/r/x.ts'), '/r/x.ts')
  assert.equal(repoPath('/r/repo', 'rel.ts'), 'rel.ts')
})

test('turnArgs adds --resume only with a session', () => {
  assert.equal(turnArgs('P', null, 'hi').includes('--resume'), false)
  assert.deepEqual(turnArgs('P', 'S', 'hi').slice(-4), ['--resume', 'S', '--', 'hi'])
})

test('prompt.md asks one question at a time, grounds it in the code and ends with the ticket block', async () => {
  const prompt = await readFile(PROMPT_URL, 'utf8')
  for (const phrase of ['one question at a time', 'purpose', 'scope', 'acceptance criteria', 'Read, Grep and Glob', 'files you read', 'propose the ticket', '```ticket', '"outOfScope"', 'short, plain sentences']) {
    assert.ok(prompt.includes(phrase), phrase)
  }
  const example = /```ticket\n([\s\S]*?)\n```/.exec(prompt)
  assert.ok(example)
  assert.deepEqual(Object.keys(JSON.parse(example[1])), ['title', 'description', 'criteria', 'outOfScope'])
})

test('a saved session the CLI no longer has is forgotten, so the next message starts fresh', async () => {
  const gone = { type: 'result', subtype: 'error_during_execution', is_error: true, errors: ['No conversation found with session ID: S1'] }
  await play(w, 'claude', [
    { lines: [init('S1'), say(R1), done(R1)] },
    { lines: [gone], stderr: 'No conversation found with session ID: S1\n', exit: 1 },
    { lines: [init('S2'), say(R2), done(R2)] },
  ])
  await runTurn(ctx('one'))
  assert.equal((await runTurn(ctx('two'))).ok, false)
  assert.match(String(events.at(-1)!.error), /session S1 is gone/)
  assert.equal(await exists(join(dir, 'session')), false)
  assert.equal((await readTurns(dir)).length, 2)
  assert.equal((await runTurn(ctx('two'))).ok, true)
  const third = (await calls(w, 'claude'))[2]
  assert.equal(third.argv.includes('--resume'), false)
  assert.equal((await readFile(join(dir, 'session'), 'utf8')).trim(), 'S2')
})

test('a first turn that fails after its init event keeps the session (D3)', async () => {
  await play(w, 'claude', [
    { lines: [init('S1'), say('Half')], stderr: 'API Error: overloaded\n', exit: 1 },
    { lines: [init('S1'), say(R1), done(R1)] },
  ])
  assert.equal((await runTurn(ctx('one'))).ok, false)
  assert.equal((await readFile(join(dir, 'session'), 'utf8')).trim(), 'S1')
  assert.equal((await runTurn(ctx('one'))).ok, true)
  assert.deepEqual((await calls(w, 'claude'))[1].argv.slice(-4), ['--resume', 'S1', '--', 'one'])
})

test('the shown reply is every text of the turn, and mid-turn events carry the text so far', async () => {
  const last = `Then: who sees it?\n\n${block(T1)}`
  await play(w, 'claude', [{ lines: [init('S1'), say('I will read the sync code first.'), reads(join(w.repo, 'src/sync.ts')), say(last), done(last)] }])
  const result = await runTurn(ctx('one'))
  assert.equal(result.ok ? result.text : null, 'I will read the sync code first.\n\nThen: who sees it?')
  const mid = events.map(event => event.turn as Record<string, unknown> | undefined).filter(turn => turn?.done === false)
  assert.deepEqual(mid.map(turn => turn!.text), ['I will read the sync code first.', 'I will read the sync code first.', 'I will read the sync code first.\n\nThen: who sees it?'])
  assert.deepEqual(mid.map(turn => turn!.files), [[], ['src/sync.ts'], ['src/sync.ts']])
})

test('a save whose transcript cannot be appended leaves no draft and no temp file (D7)', async () => {
  await mkdir(join(dir, 'transcript.jsonl'))
  await play(w, 'claude', [{ lines: [init('S1'), say(R1), done(R1)] }])
  const result = await runTurn(ctx('one'))
  assert.equal(result.ok, false)
  assert.match(String(events.at(-1)!.error), /the turn could not be saved/)
  assert.equal(await exists(join(dir, 'draft.json')), false)
  assert.deepEqual((await readdir(dir)).filter(name => name.endsWith('.tmp')), [])
})

test('a save whose draft cannot be put in place cuts the transcript back (D7)', async () => {
  await play(w, 'claude', [{ lines: [init('S1'), say(R1), done(R1)] }, { lines: [init('S1'), say(R2), done(R2)] }])
  assert.equal((await runTurn(ctx('one'))).ok, true)
  const [transcript] = await snapshot()
  await rm(join(dir, 'draft.json'))
  await mkdir(join(dir, 'draft.json'))
  await writeFile(join(dir, 'draft.json', 'keep'), '')
  const result = await runTurn(ctx('two'))
  assert.equal(result.ok, false)
  assert.equal(await readFile(join(dir, 'transcript.jsonl'), 'utf8'), transcript)
  assert.deepEqual((await readdir(dir)).filter(name => name.endsWith('.tmp')), [])
})
