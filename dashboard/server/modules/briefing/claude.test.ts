import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'

import { contentOf, parseObject, runCli, tail } from './claude.ts'
import type { CliEvent, CliRun } from './claude.ts'
import { calls, cleanup, play, world } from './test-helpers.ts'
import type { World } from './test-helpers.ts'

let w: World
before(async () => {
  w = await world()
})
after(async () => {
  await cleanup(w)
})

test('JSON object lines go to onEvent and every line to onLine, with no shell and stdin closed', async () => {
  await play(w, 'claude', [{ lines: [{ type: 'a' }, [1, 2], 'str'], stdout: 'plain text\n{"type":"b"}' }])
  const events: CliEvent[] = []
  const lines: string[] = []
  const exit = await runCli({
    bin: 'claude',
    args: ['--', '$(touch nope)', "it's; rm -rf x"],
    cwd: w.repo,
    onEvent: event => { events.push(event) },
    onLine: line => { lines.push(line) },
  }).done
  assert.equal(exit.code, 0)
  assert.deepEqual(events, [{ type: 'a' }, { type: 'b' }])
  assert.deepEqual(lines, ['{"type":"a"}', '[1,2]', '"str"', 'plain text', '{"type":"b"}'])
  const call = (await calls(w, 'claude')).at(-1)!
  assert.deepEqual(call.argv, ['--', '$(touch nope)', "it's; rm -rf x"])
  assert.equal(call.cwd, w.repo)
  assert.equal(call.stdin, '')
})

test('input goes to stdin, and a non-zero exit keeps its stderr', async () => {
  await play(w, 'gh', [{ stderr: 'HTTP 401\n', exit: 3 }])
  const exit = await runCli({ bin: 'gh', args: ['issue'], cwd: w.repo, input: 'the body\n' }).done
  assert.equal(exit.code, 3)
  assert.equal(exit.stderr, 'HTTP 401\n')
  assert.equal((await calls(w, 'gh')).at(-1)!.stdin, 'the body\n')
})

test('a binary that is not on PATH is a spawn error, not a hang', async () => {
  const exit = await runCli({ bin: 'no-such-cli', args: [], cwd: w.repo }).done
  assert.match(exit.spawnError ?? '', /ENOENT/)
  assert.equal(exit.code, null)
})

test('kill ends a run that is still waiting', async () => {
  await play(w, 'claude', [{ lines: [{ type: 'x' }], wait: true }])
  let run: CliRun | null = null
  run = runCli({ bin: 'claude', args: [], cwd: w.repo, onEvent: () => run?.kill() })
  const exit = await run.done
  assert.equal(exit.signal, 'SIGTERM')
})

test('a handler that throws is reported in the exit, not thrown', async () => {
  await play(w, 'claude', [{ lines: [{ type: 'x' }] }])
  const exit = await runCli({ bin: 'claude', args: [], cwd: w.repo, onEvent: () => { throw new Error('boom') } }).done
  assert.equal(exit.handlerError, 'boom')
})

test('a stdout line longer than one pipe chunk still arrives whole', async () => {
  const text = 'x'.repeat(300_000)
  await play(w, 'claude', [{ lines: [{ type: 'assistant', text }] }])
  const events: CliEvent[] = []
  const exit = await runCli({ bin: 'claude', args: [], cwd: w.repo, onEvent: event => { events.push(event) } }).done
  assert.equal(exit.code, 0)
  assert.equal(events.length, 1)
  assert.equal(events[0].text, text)
})

test('an argument spawn refuses is a spawn error, not a throw', async () => {
  const exit = await runCli({ bin: 'claude', args: ['a\u0000b'], cwd: w.repo }).done
  assert.ok(exit.spawnError)
  assert.equal(exit.code, null)
})

test('parseObject, tail and contentOf', () => {
  assert.deepEqual(parseObject(' {"a": 1} '), { a: 1 })
  assert.equal(parseObject('[1]'), null)
  assert.equal(parseObject('{nope'), null)
  assert.equal(tail('a\nb\nc\n'), 'c')
  assert.equal(tail('a\nb\nc', 2), 'b\nc')
  assert.equal(tail('  '), '')
  assert.deepEqual(contentOf({ message: { content: [{ type: 'text' }] } }), [{ type: 'text' }])
  assert.equal(contentOf({ message: {} }), null)
})
