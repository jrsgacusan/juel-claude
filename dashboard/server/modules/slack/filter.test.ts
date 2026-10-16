import assert from 'node:assert/strict'
import { test } from 'node:test'

import { keeps, ownerNames } from './filter.ts'
import type { Message } from './state.ts'
import { OWNER, msg } from './test-helpers.ts'

const NAMES = ownerNames(OWNER, ['Jrs'])
const keep = (over: Partial<Message>): boolean => keeps(msg(over), OWNER.id, NAMES)

test("ownerNames: the display name, the real name's first word, then slack.names, no repeats", () => {
  assert.deepEqual(ownerNames(OWNER, ['Jrs', 'juel', ' ']), ['Juel', 'Jrs'])
  assert.deepEqual(ownerNames({ id: 'U1', displayName: '', realName: 'Maria Clara' }, []), ['Maria'])
  assert.deepEqual(ownerNames(null, ['Jrs']), ['Jrs'])
})

test('a group DM is never a DM, and a mention must name the owner (D17, I-13)', () => {
  const group = { channelId: 'G0GROUP', channel: 'a DM' }
  assert.equal(keep({ ...group, text: 'guys para saan yung meeting', why: 'dm' }), false)
  assert.equal(keep({ ...group, text: 'guys para saan yung meeting', why: 'mention' }), false)
  assert.equal(keep({ ...group, text: '@Melbs re PR', why: 'mention' }), false)
  assert.equal(keep({ ...group, text: '@Melbs re PR', why: 'dm' }), false)
  assert.equal(keep({ channelId: 'D0JUEL', channel: 'a DM', text: 'can you check the build?', why: 'dm' }), true)
})

test('a mention counts by <@id>, @name or a name as a whole word in any case', () => {
  assert.equal(keep({ text: 'Juel can you look at the deploy?', why: 'mention' }), true)
  assert.equal(keep({ text: 'Juelz is on leave today', why: 'mention' }), false)
  assert.equal(keep({ text: 'ping <@U0OWNER> about the deploy', why: 'mention' }), true)
  assert.equal(keep({ text: 'ping <@U0OTHER> about the deploy', why: 'mention' }), false)
  assert.equal(keep({ text: '@juel re the deploy', why: 'mention' }), true)
  assert.equal(keep({ text: 'tanong ko kay JUEL, sabi ni jrs ok na', why: 'mention' }), true)
  assert.equal(keep({ text: 'the thread names Juel', thread: [], why: 'mention' }), true)
  assert.equal(keep({ text: 'any update?', thread: ['Juel: on it'], why: 'mention' }), false, 'only the message text counts')
})

test('"asks" is kept anywhere, "dm" only in a D conversation, and no why is dropped', () => {
  assert.equal(keep({ channelId: 'G0GROUP', channel: 'a DM', text: 'can you send me the file?', why: 'asks' }), true)
  assert.equal(keep({ channelId: 'C1', text: 'can you review this?', why: 'dm' }), false)
  assert.equal(keep({ channelId: 'D0JUEL', text: 'hi', why: undefined }), false)
})
