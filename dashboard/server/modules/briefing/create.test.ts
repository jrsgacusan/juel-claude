import assert from 'node:assert/strict'
import { mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises'
import { basename, join } from 'node:path'
import { afterEach, beforeEach, test } from 'node:test'

import { CREATE_TOOLS, createTicket, lastJson, queueCreated, slugOf, ticketBody, writeInbox } from './create.ts'
import type { CreateContext } from './create.ts'
import { stamp } from './ids.ts'
import { briefingDir, createBriefing, readCreated, writeDraft } from './store.ts'
import { calls, cleanup, done, init, play, say, world } from './test-helpers.ts'
import type { World } from './test-helpers.ts'
import type { Ticket } from './ticket.ts'

const T: Ticket = { title: 'Retry the sync', description: 'The sync drops on a flaky network.', criteria: ['A failed sync retries once'], outOfScope: ['Backoff tuning'] }
const BODY = 'The sync drops on a flaky network.\n\n## Acceptance criteria\n- [ ] A failed sync retries once\n\n## Out of scope\n- Backoff tuning\n'

let w: World
let dir: string
let logs: string[]
beforeEach(async () => {
  w = await world()
  dir = briefingDir(w.home, await createBriefing(w.home))!
  await writeDraft(dir, T)
  logs = []
})
afterEach(async () => {
  await cleanup(w)
})

const ctx = (tracker: CreateContext['tracker'], trackerProject: string | null = null, at = dir): CreateContext => ({ project: 'proj', repo: w.repo, home: w.home, dir: at, tracker, trackerProject, draft: T, log: line => { logs.push(line) } })
const specPath = (name = 'retry-the-sync.md'): string => join(w.home, 'items', 'proj', name)

async function inboxFiles(): Promise<string[]> {
  try {
    return (await readdir(join(w.home, 'inbox'))).sort()
  } catch {
    return []
  }
}

/** STAR's inbox format (skills/star/SKILL.md:244-254): a repo line, then refs as a list. */
function parseInbox(text: string): { repo: string; refs: string[] } {
  const lines = text.split('\n')
  assert.match(lines[0], /^repo: \S/)
  assert.equal(lines[1], 'refs:')
  const refs = lines.slice(2).filter(Boolean)
  assert.ok(refs.length > 0 && refs.every(line => line.startsWith('- ')))
  return { repo: lines[0].slice('repo: '.length), refs: refs.map(line => line.slice(2)) }
}

async function onlyInbox(): Promise<{ repo: string; refs: string[] }> {
  const files = await inboxFiles()
  assert.equal(files.length, 1)
  assert.match(files[0], /^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}\.md$/)
  const text = await readFile(join(w.home, 'inbox', files[0]), 'utf8')
  const parsed = parseInbox(text)
  assert.equal(text, `repo: ${parsed.repo}\nrefs:\n${parsed.refs.map(ref => `- ${ref}\n`).join('')}`)
  return parsed
}

test('ticketBody lists criteria as checkboxes and says None. for an empty list', () => {
  assert.equal(ticketBody(T), BODY)
  assert.equal(ticketBody({ ...T, description: '', criteria: [], outOfScope: [] }), '## Acceptance criteria\nNone.\n\n## Out of scope\nNone.\n')
})

test('slugOf is kebab case of at most six words, and briefing when nothing is left', () => {
  assert.equal(slugOf('Retry the sync'), 'retry-the-sync')
  assert.equal(slugOf('Add a retry to the dashboard sync job, now!'), 'add-a-retry-to-the-dashboard')
  assert.equal(slugOf('!!! ???'), 'briefing')
})

test('lastJson finds the last line that is a JSON object', () => {
  assert.deepEqual(lastJson('Done.\n{"ref": "A-1", "url": "u"}\n```'), { ref: 'A-1', url: 'u' })
  assert.equal(lastJson('no json here\n[1]'), null)
  assert.deepEqual(lastJson('Done:\n{\n  "ref": "ENG-7",\n  "url": "https://x/ENG-7"\n}\n'), { ref: 'ENG-7', url: 'https://x/ENG-7' })
  assert.deepEqual(lastJson('{\n  "a": {"b": 1}\n}'), { a: { b: 1 } })
})

test('github: gh issue create in the repo, ref #<n>, created.json and the inbox file', async () => {
  await play(w, 'gh', [{ stdout: 'Creating issue in o/r\n\nhttps://github.com/o/r/issues/42\n' }])
  const outcome = await createTicket(ctx('github'))
  if (!outcome.ok) assert.fail(outcome.error)
  assert.equal(outcome.created.ref, '#42')
  assert.equal(outcome.created.url, 'https://github.com/o/r/issues/42')
  assert.equal(outcome.created.specPath, null)
  assert.equal(outcome.created.tracker, 'github')
  const [call] = await calls(w, 'gh')
  assert.deepEqual(call.argv, ['issue', 'create', '--title', 'Retry the sync', '--body-file', '-'])
  assert.equal(call.cwd, w.repo)
  assert.equal(call.stdin, BODY)
  assert.deepEqual(await readCreated(dir), outcome.created)
  assert.deepEqual(await onlyInbox(), { repo: w.repo, refs: ['#42'] })
})

test("a failed gh create keeps the draft, writes no inbox file and gives gh's error; a spec then works", async () => {
  await play(w, 'gh', [{ stderr: 'HTTP 401: Bad credentials (https://api.github.com/graphql)\n', exit: 1 }])
  const draft = await readFile(join(dir, 'draft.json'), 'utf8')
  assert.deepEqual(await createTicket(ctx('github')), { ok: false, error: 'HTTP 401: Bad credentials (https://api.github.com/graphql)' })
  assert.equal(await readFile(join(dir, 'draft.json'), 'utf8'), draft)
  assert.deepEqual(await inboxFiles(), [])
  assert.equal(await readCreated(dir), null)

  const spec = await createTicket(ctx('none'))
  if (!spec.ok) assert.fail(spec.error)
  assert.equal(spec.created.specPath, specPath())
  assert.deepEqual(await onlyInbox(), { repo: w.repo, refs: [specPath()] })
})

test('gh that exits 0 but prints no issue URL may have made the issue, so the briefing stays marked', async () => {
  await play(w, 'gh', [{ stdout: 'something else\n' }])
  const outcome = await createTicket(ctx('github'))
  assert.equal(outcome.ok, false)
  if (outcome.ok) return
  assert.equal(outcome.maybeMade, true)
  assert.match(outcome.error, /exited 0 but printed no issue URL \(something else\)/)
  assert.match(outcome.error, /check github for the issue/)
  assert.equal((await readCreated(dir))?.state, 'creating')
  assert.deepEqual(await inboxFiles(), [])
})

test('linear: a headless haiku run allowed only the create tools, when one is connected', async () => {
  const answer = 'Created it.\n{"ref": "ENG-7", "url": "https://linear.app/acme/issue/ENG-7"}'
  await play(w, 'claude', [{ lines: [init('C1', ['mcp__claude_ai_Linear__get_issue', 'mcp__claude_ai_Linear__save_issue']), say(answer), done(answer)] }])
  const outcome = await createTicket(ctx('linear', 'ENG'))
  if (!outcome.ok) assert.fail(outcome.error)
  assert.equal(outcome.created.ref, 'ENG-7')
  assert.equal(outcome.created.url, 'https://linear.app/acme/issue/ENG-7')
  const [call] = await calls(w, 'claude')
  assert.deepEqual(call.argv.slice(0, -1), ['-p', '--model', 'haiku', '--output-format', 'stream-json', '--verbose', '--permission-mode', 'dontAsk', '--tools', '', '--allowedTools', CREATE_TOOLS.linear.join(','), '--'])
  const prompt = call.argv.at(-1)!
  assert.ok(prompt.includes('Retry the sync'))
  assert.ok(prompt.includes(BODY.trim()))
  assert.ok(prompt.includes('"ENG"'))
  assert.ok(prompt.includes('{"ref": "<the issue identifier, like ENG-123>", "url": "<the issue URL>"}'))
  assert.ok(prompt.includes('{"error": "<what went wrong, in one sentence>"}'))
  assert.equal(call.cwd, w.repo)
  assert.deepEqual(await onlyInbox(), { repo: w.repo, refs: ['ENG-7'] })
})

test('linear with no create tool connected stops the run and writes the spec item', async () => {
  await play(w, 'claude', [{ lines: [init('C1', ['Read', 'mcp__slack__post'])], wait: true }])
  const started = Date.now()
  const outcome = await createTicket(ctx('linear'))
  assert.ok(Date.now() - started < 5000, 'the run was stopped at init, not left until the fake gives up after 10 s')
  if (!outcome.ok) assert.fail(outcome.error)
  assert.equal(outcome.created.ref, null)
  assert.equal(outcome.created.tracker, 'linear')
  assert.equal(outcome.created.specPath, specPath())
  assert.deepEqual(await onlyInbox(), { repo: w.repo, refs: [specPath()] })
})

test('a connected tracker that answers {error} is a failed create', async () => {
  const answer = '{"error": "no project key for Jira"}'
  await play(w, 'claude', [{ lines: [init('C1', ['mcp__atlassian__createJiraIssue']), say(answer), done(answer)] }])
  assert.deepEqual(await createTicket(ctx('jira')), { ok: false, error: 'no project key for Jira' })
  assert.deepEqual(await inboxFiles(), [])
  assert.equal(await readCreated(dir), null)
  const argv = (await calls(w, 'claude'))[0].argv
  assert.equal(argv[argv.indexOf('--allowedTools') + 1], CREATE_TOOLS.jira.join(','))
})

test('a create run that ends before its init event is a failed create', async () => {
  await play(w, 'claude', [{ stderr: 'Not logged in\n', exit: 1 }])
  const outcome = await createTicket(ctx('linear'))
  assert.equal(outcome.ok, false)
  assert.match(outcome.ok ? '' : outcome.error, /Not logged in/)
  assert.deepEqual(await inboxFiles(), [])
})

test('synapse writes the spec item without running claude', async () => {
  const outcome = await createTicket(ctx('synapse'))
  if (!outcome.ok) assert.fail(outcome.error)
  assert.equal(await readFile(specPath(), 'utf8'), `---\nstatus: todo\ntitle: Retry the sync\n---\n${BODY}`)
  assert.equal(outcome.created.url, '/api/projects/proj/file?path=items%2Fproj%2Fretry-the-sync.md')
  assert.deepEqual(await calls(w, 'claude'), [])
  assert.deepEqual(await onlyInbox(), { repo: w.repo, refs: [specPath()] })
})

test('a second spec with the same slug takes -2, and nothing is overwritten', async () => {
  const first = await createTicket(ctx('none'))
  const other = briefingDir(w.home, await createBriefing(w.home))!
  await writeDraft(other, T)
  const second = await createTicket(ctx('none', null, other))
  if (!first.ok || !second.ok) assert.fail('a spec create failed')
  assert.equal(second.created.specPath, specPath('retry-the-sync-2.md'))
  assert.equal(await readFile(specPath(), 'utf8'), `---\nstatus: todo\ntitle: Retry the sync\n---\n${BODY}`)
  assert.equal((await inboxFiles()).length, 2)
})

test('writeInbox never overwrites an inbox file', async () => {
  const now = new Date('2026-10-16T03:04:05Z')
  await mkdir(join(w.home, 'inbox'), { recursive: true })
  const taken = join(w.home, 'inbox', `${stamp(now)}-aaaa.md`)
  await writeFile(taken, 'repo: other\nrefs:\n- #1\n')
  const suffixes = ['aaaa', 'bbbb']
  const path = await writeInbox(w.home, w.repo, '#2', now, () => suffixes.shift()!)
  assert.equal(basename(path), '20261016T030405Z-bbbb.md')
  assert.equal(await readFile(taken, 'utf8'), 'repo: other\nrefs:\n- #1\n')
  assert.equal(await readFile(path, 'utf8'), `repo: ${w.repo}\nrefs:\n- #2\n`)
})

test('a connected tracker that answers in pretty-printed JSON is still read', async () => {
  const answer = 'Created it:\n{\n  "ref": "ENG-8",\n  "url": "https://linear.app/acme/issue/ENG-8"\n}'
  await play(w, 'claude', [{ lines: [init('C1', ['mcp__linear__save_issue']), say(answer), done(answer)] }])
  const outcome = await createTicket(ctx('linear'))
  if (!outcome.ok) assert.fail(outcome.error)
  assert.equal(outcome.created.ref, 'ENG-8')
})

test('a create tool that ran without a usable answer may have made the issue: it says so and the briefing stays marked', async () => {
  const toolUse = { type: 'assistant', message: { content: [{ type: 'tool_use', name: 'mcp__linear__save_issue', input: {} }] } }
  await play(w, 'claude', [{ lines: [init('C1', ['mcp__linear__save_issue']), toolUse, say('Done, I think.'), done('Done, I think.')] }])
  const outcome = await createTicket(ctx('linear'))
  assert.equal(outcome.ok, false)
  if (outcome.ok) return
  assert.equal(outcome.maybeMade, true)
  assert.match(outcome.error, /create tool ran, so the issue may exist/)
  assert.match(outcome.error, /check linear for the issue/)
  assert.equal((await readCreated(dir))?.state, 'creating')
  assert.deepEqual(await inboxFiles(), [])
  assert.ok(logs.some(line => line.includes('Done, I think.')))
})

test('a ref that is not one token, or a url that is not https, is not taken', async () => {
  for (const answer of ['{"ref": "ENG-9\\nrefs:\\n- evil", "url": "https://linear.app/x"}', '{"ref": "ENG-9", "url": "javascript:alert(1)"}']) {
    await play(w, 'claude', [{ lines: [init('C1', ['mcp__linear__save_issue']), say(answer), done(answer)] }])
    const outcome = await createTicket(ctx('linear'))
    assert.equal(outcome.ok, false, answer)
  }
  assert.deepEqual(await inboxFiles(), [])
})

test('a ticket made while the inbox cannot be written keeps inbox: null, and queueCreated sends it later', async () => {
  await play(w, 'gh', [{ stdout: 'https://github.com/o/r/issues/42\n' }])
  await writeFile(join(w.home, 'inbox'), 'not a folder')
  const outcome = await createTicket(ctx('github'))
  assert.equal(outcome.ok, false)
  if (outcome.ok) return
  assert.equal(outcome.made?.ref, '#42')
  assert.match(outcome.error, /#42 was made, but STAR's inbox file could not be written/)
  assert.ok(logs.some(line => line.includes('made #42 (https://github.com/o/r/issues/42)')))
  assert.equal((await readCreated(dir))?.inbox, null)

  await rm(join(w.home, 'inbox'))
  const queued = await queueCreated({ home: w.home, repo: w.repo, dir }, (await readCreated(dir))!)
  if (!queued.ok) assert.fail(queued.error)
  assert.deepEqual(await onlyInbox(), { repo: w.repo, refs: ['#42'] })
  const [file] = await inboxFiles()
  assert.equal(queued.created.inbox, join(w.home, 'inbox', file))
  assert.deepEqual(await readCreated(dir), queued.created)
  assert.equal((await calls(w, 'gh')).length, 1)
})

test('a spec title with a newline stays one frontmatter line', async () => {
  const draft = { ...T, title: 'Fix the sync\nstatus: done' }
  const outcome = await createTicket({ ...ctx('none'), draft })
  if (!outcome.ok) assert.fail(outcome.error)
  const text = await readFile(outcome.created.specPath!, 'utf8')
  assert.equal(text.split('\n').slice(0, 4).join('\n'), '---\nstatus: todo\ntitle: Fix the sync status: done\n---')
})

test('a create that cannot record what it made stays marked as creating, so no second ticket is made', async () => {
  await play(w, 'gh', [{ stdout: 'https://github.com/o/r/issues/42\n' }])
  await mkdir(join(dir, `.created.json.${process.pid}.tmp`)) // the record's rewrite cannot write its temp file
  const outcome = await createTicket(ctx('github'))
  assert.equal(outcome.ok, false)
  if (outcome.ok) return
  assert.equal(outcome.made?.ref, '#42')
  assert.match(outcome.error, /#42 was made, but it could not be recorded/)
  assert.equal((await readCreated(dir))?.state, 'creating')
  assert.deepEqual(await inboxFiles(), [])
  assert.ok(logs.some(line => line.includes('made #42')))
})

test('queueCreated takes its inbox file back when created.json cannot record it', async () => {
  const made = { tracker: 'github', ref: '#42', specPath: null, url: 'https://github.com/o/r/issues/42', at: '2026-10-16T00:00:00.000Z', state: 'made' as const, inbox: null }
  await writeFile(join(dir, 'created.json'), JSON.stringify(made))
  await mkdir(join(dir, `.created.json.${process.pid}.tmp`))
  const failed = await queueCreated({ home: w.home, repo: w.repo, dir }, made)
  assert.equal(failed.ok, false)
  assert.match(failed.ok ? '' : failed.error, /could not record its inbox file/)
  assert.deepEqual(await inboxFiles(), [])
  assert.equal((await readCreated(dir))?.inbox, null)
  await rm(join(dir, `.created.json.${process.pid}.tmp`), { recursive: true })
  const queued = await queueCreated({ home: w.home, repo: w.repo, dir }, made)
  if (!queued.ok) assert.fail(queued.error)
  assert.deepEqual(await onlyInbox(), { repo: w.repo, refs: ['#42'] })
})

test('a spec item that cannot be written is a failed create, and its mark is cleared', async () => {
  await mkdir(join(w.home, 'items'), { recursive: true })
  await writeFile(join(w.home, 'items', 'proj'), 'not a folder')
  const outcome = await createTicket(ctx('none'))
  assert.equal(outcome.ok, false)
  assert.match(outcome.ok ? '' : outcome.error, /the spec item could not be written/)
  assert.equal(await readCreated(dir), null)
  assert.deepEqual(await inboxFiles(), [])
})
