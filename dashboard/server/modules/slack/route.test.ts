import assert from 'node:assert/strict'
import { test } from 'node:test'

import { briefSignals, hasBranch, hasWord, routeMessage, signalsOf, slugOf } from './route.ts'
import type { Signals } from './route.ts'
import { brief, cleanup, ledger, msg, project, world } from './test-helpers.ts'

const sig = (over: Partial<Signals> & { project: string }): Signals => ({
  refs: [],
  prs: [],
  slug: null,
  branches: [],
  names: [over.project],
  ...over,
})

test('rule 1, a ref: a ledger item name or a brief ref, as a whole word', () => {
  const app = sig({ project: 'app', refs: ['issue-4', 'APP-77'] })
  const web = sig({ project: 'web', refs: ['issue-42'] })
  assert.deepEqual(routeMessage(msg({ text: 'how is ISSUE-4 going?' }), [app, web], {}), { project: 'app' })
  assert.deepEqual(routeMessage(msg({ text: 'and app-77?' }), [app, web], {}), { project: 'app' })
  assert.deepEqual(routeMessage(msg({ text: 'issue-42 please' }), [app, web], {}), { project: 'web' })
  assert.deepEqual(routeMessage(msg({ text: 'issue-4x' }), [app, web], {}), { project: null, why: 'none' })
})

test("rule 2, a PR of the project's repository: its URL, or #n / PR n from its ledger", () => {
  const app = sig({ project: 'app', slug: 'acme/app', prs: [12] })
  const web = sig({ project: 'web', slug: 'acme/web', prs: [30] })
  assert.deepEqual(routeMessage(msg({ text: 'see https://github.com/Acme/App/pull/99' }), [app, web], {}), { project: 'app' })
  assert.deepEqual(routeMessage(msg({ text: 'can you look at #12?' }), [app, web], {}), { project: 'app' })
  assert.deepEqual(routeMessage(msg({ text: 'PR 30 is red' }), [app, web], {}), { project: 'web' })
  assert.deepEqual(routeMessage(msg({ text: 'pr #30' }), [app, web], {}), { project: 'web' })
  assert.deepEqual(routeMessage(msg({ text: '#123 and C#12 and &#12;' }), [app, web], {}), { project: null, why: 'none' })
  assert.deepEqual(routeMessage(msg({ text: 'https://github.com/other/repo/pull/12' }), [app, web], {}), { project: null, why: 'none' })
})

test('rule 3, a branch name in the text', () => {
  const app = sig({ project: 'app', branches: ['fix/app-77-rounding'] })
  assert.deepEqual(routeMessage(msg({ text: 'merged fix/app-77-rounding.' }), [app], {}), { project: 'app' })
  assert.deepEqual(routeMessage(msg({ text: 'fix/app-77-rounding-v2' }), [app], {}), { project: null, why: 'none' })
})

test('rule 4, the project or its repo folder name, in the text or its thread', () => {
  const app = sig({ project: 'app', names: ['app', 'acme-app'] })
  const web = sig({ project: 'web' })
  assert.deepEqual(routeMessage(msg({ text: 'the acme-app deploy' }), [app, web], {}), { project: 'app' })
  assert.deepEqual(routeMessage(msg({ text: 'nothing here', thread: ['Ann: is web down?'] }), [app, web], {}), { project: 'web' })
})

test('rule 5, a learned channel, only for a registered project', () => {
  const app = sig({ project: 'app' })
  assert.deepEqual(routeMessage(msg({ channelId: 'C9' }), [app], { C9: 'app' }), { project: 'app' })
  assert.deepEqual(routeMessage(msg({ channelId: 'C9' }), [app], { C9: 'gone' }), { project: null, why: 'none' })
})

test('the first rule that matches decides; a tie there is unrouted, with no fall-through', () => {
  const app = sig({ project: 'app', refs: ['APP-77'] })
  const web = sig({ project: 'web' })
  assert.deepEqual(routeMessage(msg({ text: 'APP-77 breaks web' }), [app, web], {}), { project: 'app' })
  assert.deepEqual(routeMessage(msg({ channelId: 'C9', text: 'app and web are both down' }), [app, web], { C9: 'app' }), {
    project: null,
    why: 'tie',
  })
})

test('hasWord and hasBranch match whole words only (S9)', () => {
  assert.equal(hasWord('see issue-4.', 'issue-4'), true)
  assert.equal(hasWord('see issue-42', 'issue-4'), false)
  assert.equal(hasWord('see my-issue-4', 'issue-4'), false)
  assert.equal(hasBranch('on feat/x.', 'feat/x'), true)
  assert.equal(hasBranch('on feat/x.y', 'feat/x'), false)
  assert.equal(hasBranch('on old/feat/x', 'feat/x'), false)
})

test('briefSignals reads item.ref and branch from the front matter only', () => {
  assert.deepEqual(briefSignals(brief({ name: 'x', ref: '"APP-1"', branch: 'feat/x' })), { ref: 'APP-1', branch: 'feat/x' })
  assert.deepEqual(briefSignals(brief({ name: 'x', ref: null })), { ref: null, branch: 'feat/x' })
  assert.deepEqual(briefSignals('no front matter\nref: APP-2\nbranch: y\n'), { ref: null, branch: null })
})

test('slugOf reads ssh and https GitHub remotes', () => {
  assert.equal(slugOf('git@github.com:Acme/App.git\n'), 'acme/app')
  assert.equal(slugOf('https://github.com/acme/app'), 'acme/app')
  assert.equal(slugOf('https://github.com/acme/app.git/'), 'acme/app')
  assert.equal(slugOf('https://gitlab.com/acme/app'), null)
})

test('signalsOf reads the ledger, the briefs, the origin remote and the names', async () => {
  const w = await world()
  const app = await project(w, 'app', {
    origin: 'git@github.com:Acme/app.git',
    ledger: ledger([{ item: 'issue-4', pr: 'https://github.com/Acme/app/pull/12' }, { item: 'issue-5' }]),
    briefs: { 'issue-4.md': brief({ name: 'issue-4', ref: 'APP-77', branch: 'fix/app-77-rounding' }), 'notes.txt': 'ref: NOPE-1' },
    repoName: 'acme-app',
  })
  assert.deepEqual(await signalsOf(app), {
    project: 'app',
    refs: ['issue-4', 'issue-5', 'APP-77'],
    prs: [12],
    slug: 'acme/app',
    branches: ['fix/app-77-rounding'],
    names: ['app', 'acme-app'],
  })
  assert.deepEqual(await signalsOf(await project(w, 'bare')), { project: 'bare', refs: [], prs: [], slug: null, branches: [], names: ['bare'] })
  await cleanup(w)
})