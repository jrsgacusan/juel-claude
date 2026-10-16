import assert from 'node:assert/strict'
import { test } from 'node:test'

import { parseEnvelope, parseResult } from './parse.ts'
import { envelope, msg } from './test-helpers.ts'

test('a bare array of messages is accepted, with no workspace', () => {
  assert.deepEqual(parseResult(JSON.stringify([msg()])), { kind: 'messages', workspace: null, messages: [msg()], owner: null })
})

test('{workspace, messages} is accepted, and one json code fence is stripped', () => {
  const m = msg({ threadTs: '1699999999.000200', thread: ['Ann: did it ship?'] })
  const text = '```json\n' + JSON.stringify({ workspace: 'Acme', messages: [m] }) + '\n```'
  assert.deepEqual(parseResult(text), { kind: 'messages', workspace: 'Acme', messages: [m], owner: null })
  assert.deepEqual(parseResult(JSON.stringify({ workspace: null, messages: [] })), { kind: 'messages', workspace: null, messages: [], owner: null })
})

test('{"connected": false} says Slack is not connected', () => {
  assert.deepEqual(parseResult('{"connected": false, "why": "no Slack tool"}'), { kind: 'disconnected', why: 'no Slack tool' })
  assert.deepEqual(parseResult('{"connected": false}'), { kind: 'disconnected', why: 'no reason given' })
})

test('the envelope must not be is_error and must carry a result string', () => {
  assert.deepEqual(parseEnvelope(envelope([msg()])), { kind: 'messages', workspace: null, messages: [msg()], owner: null })
  assert.deepEqual(parseEnvelope(envelope('boom', { is_error: true, subtype: 'error_during_execution' })), {
    kind: 'error',
    error: 'claude reported an error (error_during_execution)',
    cli: true,
  })
  for (const stdout of ['not json', '[]', JSON.stringify({ type: 'result', is_error: false })]) {
    const out = parseEnvelope(stdout)
    assert.equal(out.kind, 'error', stdout)
    assert.equal(out.kind === 'error' && out.cli, false, stdout)
  }
})

test('one invalid element fails the whole answer', () => {
  const cases: [string, unknown][] = [
    ['not an object', 'hi'],
    ['ts is not a Slack ts', msg({ ts: '17' })],
    ['channelId is not a Slack id', msg({ channelId: '../x' })],
    ['threadTs is not a Slack ts or null', { ...msg(), threadTs: undefined }],
    ['thread is not at most 5 strings', msg({ thread: ['1', '2', '3', '4', '5', '6'] })],
    ['thread is not at most 5 strings', { ...msg(), thread: [1] }],
    ['permalink is not an https link', msg({ permalink: 'javascript:alert(1)' })],
    ['from is not a string', { ...msg(), from: 7 }],
  ]
  for (const [why, bad] of cases) {
    assert.deepEqual(parseResult(JSON.stringify([msg(), bad])), {
      kind: 'error',
      error: `the answer is not the expected JSON: message 2: ${why}`,
      cli: false,
    })
  }
})

test('anything else is not the expected JSON, and the error never quotes the answer', () => {
  for (const text of ['Here is SECRET-TEXT', '{"messages": "SECRET-TEXT"}', '42', 'null', '{"workspace": 3, "messages": []}', '[{"text": "SECRET-TEXT"']) {
    const out = parseResult(text)
    assert.equal(out.kind, 'error', text)
    assert.ok(out.kind === 'error' && out.error.startsWith('the answer is not the expected JSON: '), text)
    assert.ok(out.kind === 'error' && !out.error.includes('SECRET'), text)
  }
})
test('the answer names the owner, and every message says why (D17)', () => {
  const owner = { id: 'U0OWNER', displayName: 'Juel', realName: 'Juel Rei Gacusan' }
  const dm = msg({ channelId: 'D1', why: 'dm' })
  assert.deepEqual(parseResult(JSON.stringify({ workspace: 'Acme', owner, messages: [dm] })), { kind: 'messages', workspace: 'Acme', owner, messages: [dm] })
  assert.deepEqual(parseResult(JSON.stringify([msg(), { ...msg(), why: 'fyi' }])), {
    kind: 'error',
    error: 'the answer is not the expected JSON: message 2: why is not dm, mention or asks',
    cli: false,
  })
  assert.deepEqual(parseResult(JSON.stringify({ workspace: 'Acme', owner: { id: 7 }, messages: [] })), {
    kind: 'error',
    error: 'the answer is not the expected JSON: owner is not {id, displayName, realName}',
    cli: false,
  })
})
