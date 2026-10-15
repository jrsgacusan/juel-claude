import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { test } from 'node:test'
import { setup } from './helpers.ts'

type Hit = { group: string; title: string; sub: string; ref: string; project: string; route: string }
const find = async (env: Awaited<ReturnType<typeof setup>>, qs: string): Promise<Hit[]> => (await (await env.api(`/api/search?${qs}`)).json()) as Hit[]

test('search finds items, open loops and decision headings in one project', async () => {
  const env = await setup()
  try {
    assert.deepEqual(await find(env, 'q=csv&project=app'), [
      { group: 'Items', title: 'Export reports as CSV', sub: 'building, gate-r2 codex gate round 2', ref: 'issue-1', project: 'app', route: '/app/progress?item=issue-1' },
      { group: 'Needs you', title: 'Ria in #eng: is the CSV export landing today?', sub: 'slack-reply', ref: 'N-4', project: 'app', route: '/app/needs?loop=N-4' },
      { group: 'Decisions', title: 'CSV over XLSX (2026-10-15, decided by the brief worker)', sub: 'issue-1 D1', ref: 'D1', project: 'app', route: '/app/progress?item=issue-1' },
    ])
  } finally {
    await env.close()
  }
})

test('search finds Slack drafts, briefings and evidence file names', async () => {
  const env = await setup()
  try {
    assert.deepEqual(await find(env, 'q=final%20review&project=app'), [
      { group: 'Slack', title: "Not today. It's in final review now.", sub: '2026-10-15-app-slack-C1-1700000000.000100.md', ref: 'C1-1700000000.000100', project: 'app', route: '/app/slack?draft=2026-10-15-app-slack-C1-1700000000.000100.md' },
    ])
    assert.deepEqual((await find(env, 'q=SAVED&project=app')).map(h => [h.group, h.title, h.route]), [['Briefings', 'Saved report views', '/app/briefing?id=b1']])
    assert.deepEqual((await find(env, 'q=invoice&project=app')).map(h => [h.group, h.title, h.ref]), [
      ['Items', 'Fix invoice rounding', 'issue-4'],
      ['Evidence', 'invoice-page.png', 'issue-4'],
    ])
    assert.deepEqual(await find(env, 'q=&project=app'), [])
    assert.equal((await env.api('/api/search?q=csv')).status, 400)
    assert.equal((await env.api('/api/search?q=csv&project=ghost')).status, 404)
  } finally {
    await env.close()
  }
})

test('all=1 searches every registered project and skips one that cannot be read', async () => {
  const env = await setup()
  try {
    await env.addProject('second')
    await env.addProject('broken', home => fs.writeFileSync(path.join(home, 'ledger.md'), 'garbage\n'))
    const hits = await find(env, 'q=xlsx&all=1')
    assert.deepEqual(hits.map(h => [h.project, h.group, h.ref]), [['app', 'Decisions', 'D1'], ['second', 'Decisions', 'D1']])
    assert.equal((await env.api('/api/search?q=xlsx&project=broken')).status, 502)
    assert.match(fs.readFileSync(path.join(env.juel, 'dashboard.log'), 'utf8'), /search skipped broken: ledger\.md: no ledger table/)
  } finally {
    await env.close()
  }
})
