import assert from 'node:assert/strict'
import { test } from 'node:test'

import { block } from './test-helpers.ts'
import { extractTicket, parseTicket, stripTickets } from './ticket.ts'

const T = { title: 'Retry the sync', description: 'Why.', criteria: ['It retries'], outOfScope: ['Backoff'] }

test('a reply with a ticket block shows the text without it and gives the ticket', () => {
  const { shown, ticket } = extractTicket(`Which screen?\n\n${block(T)}`)
  assert.equal(shown, 'Which screen?')
  assert.deepEqual(ticket, T)
})

test('the last valid block is the ticket, and every block is stripped', () => {
  const later = { ...T, title: 'Later' }
  const { shown, ticket } = extractTicket(`A\n${block(T)}\nB\n${block(later)}\n${block({ title: '' })}`)
  assert.deepEqual(ticket, later)
  assert.equal(shown, 'A\n\nB')
})

test('a reply with no block, or only invalid ones, has no ticket', () => {
  assert.deepEqual(extractTicket('Just text.'), { shown: 'Just text.', ticket: null })
  assert.equal(extractTicket(`x\n${block({ ...T, criteria: 'no' })}`).ticket, null)
  assert.equal(extractTicket('x\n```ticket\nnot json\n```').ticket, null)
  assert.equal(extractTicket('x\n```json\n' + JSON.stringify(T) + '\n```').ticket, null)
})

test('parseTicket checks every field', () => {
  assert.deepEqual(parseTicket(JSON.stringify({ ...T, title: '  Padded  ' })), { ...T, title: 'Padded' })
  assert.equal(parseTicket(JSON.stringify({ ...T, title: ' ' })), null)
  assert.equal(parseTicket(JSON.stringify({ ...T, description: 3 })), null)
  assert.equal(parseTicket(JSON.stringify({ ...T, outOfScope: [1] })), null)
  assert.equal(parseTicket('[1]'), null)
  assert.equal(parseTicket('null'), null)
})

test('an unclosed ticket block is cut from its fence to the end', () => {
  assert.equal(stripTickets('Hi there.\n\n```ticket\n{"title": "Ha'), 'Hi there.')
})
