import assert from 'node:assert/strict'
import { join } from 'node:path'
import { test } from 'node:test'

import { runCli } from './claude.ts'
import { calls, cleanup, play, world } from './test-helpers.ts'

test('runCli passes argv, stdin and cwd, and returns stdout, stderr and the exit code', async () => {
  const w = await world()
  await play(w, [{ stdout: 'out', stderr: 'err', exit: 3 }])
  const result = await runCli({ bin: 'claude', args: ['-p', '--tools', ''], cwd: w.root, input: 'the prompt', timeoutMs: 5000 })
  assert.deepEqual(result, { code: 3, signal: null, stdout: 'out', stderr: 'err', spawnError: null, timedOut: false, tooLarge: false })
  assert.deepEqual(await calls(w), [{ argv: ['-p', '--tools', ''], cwd: w.root, stdin: 'the prompt' }])
  await cleanup(w)
})

test('runCli stops a run past its time limit', async () => {
  const w = await world()
  await play(w, [{ wait: true }])
  const started = Date.now()
  const result = await runCli({ bin: 'claude', args: [], cwd: w.root, input: '', timeoutMs: 200 })
  assert.equal(result.timedOut, true)
  assert.notEqual(result.code, 0)
  assert.ok(Date.now() - started < 4000, 'it did not wait for the fake to give up')
  await cleanup(w)
})

test('runCli reports a binary that cannot start, without throwing', async () => {
  const w = await world()
  const result = await runCli({ bin: join(w.root, 'no-such-claude'), args: [], cwd: w.root, input: '', timeoutMs: 5000 })
  assert.match(result.spawnError ?? '', /ENOENT/)
  assert.equal(result.code, null)
  await cleanup(w)
})

test('runCli stops reading past maxStdout and drops what it read', async () => {
  const w = await world()
  await play(w, [{ stdout: 'x'.repeat(1000) }])
  const result = await runCli({ bin: 'claude', args: [], cwd: w.root, input: '', timeoutMs: 5000, maxStdout: 100 })
  assert.equal(result.tooLarge, true)
  assert.equal(result.stdout, '')
  await cleanup(w)
})