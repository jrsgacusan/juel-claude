// The pure rules: no session, no `$`. Each case is a command STAR or a worker really runs, or one
// the guard exists to stop.
import { describe, expect, test } from 'claude-code/testing'

import { fallbackDeny, guardRmVars, judge, protectedWhy } from '../../hooks/guards'
import type { Protect } from '../../hooks/guards'
import { autoOf, normDir, parseAccounts } from '../../hooks/cswap'
import type { Proc } from '../../hooks/cswap'
import { bandOf, isMachineText, needOf, optionsOf, parseLedger, parseQueue, parseStar } from '../../hooks/star'
import { CSWAP_LIST, HOME, LEDGER, QUEUE, ROOT, STAR, ledger } from './fixtures'

const P: Protect = { homes: [HOME], docsRel: 'docs/superpowers', cwd: ROOT }
const SHA = 'a'.repeat(40)

describe('merge guard', () => {
  test('refuses a direct merge in its usual spellings', () => {
    for (const c of [
      'gh pr merge 12 --squash',
      `gh pr merge https://github.com/o/r/pull/12 --squash --match-head-commit ${SHA}`,
      'GH_TOKEN=x gh -R o/r pr merge 12',
      '/opt/homebrew/bin/gh pr merge 12',
      `cd ${ROOT} && gh pr merge 12`,
      "bash -c 'gh pr merge 12 --auto'",
      'gh api -X PUT repos/o/r/pulls/12/merge',
      'gh api graphql -f query="mutation { mergePullRequest(input: {}) { clientMutationId } }"',
      'echo "$(gh pr merge 3)"',
      'timeout 60 gh pr merge 3',
    ]) {
      expect(judge(c, P)?.kind, c).toBe('merge')
    }
  })

  test('lets merge.sh, other gh calls and text that only mentions a merge through', () => {
    for (const c of [
      `sh /p/skills/star/merge.sh https://github.com/o/r/pull/12 --head ${SHA} --home ${HOME} --item issue-1`,
      'gh pr view 12 --json state,mergeable',
      'gh pr merge 12 --disable-auto',
      'echo "never run gh pr merge by hand"',
      "git commit -m 'gh pr merge is refused'",
      'cat <<EOF > note.txt\ngh pr merge 12\nEOF',
      'grep -n "gh pr merge" skills/star/merge.sh',
      `sh /p/skills/star/star-issue.sh --title "merge.sh: gh pr merge failed"`,
    ]) {
      expect(judge(c, P), c).toBeUndefined()
    }
  })
})

describe('read guard', () => {
  test('refuses reading a review, evidence, report or log file into the session', () => {
    for (const c of [
      `cat ${HOME}/reviews/app/issue-7-r2.md`,
      `head -40 ${HOME}/reviews/app/issue-7-r2.raw.md`,
      `tail -f ${HOME}/progress/issue-7.log`,
      `sed -n '1,80p' ${HOME}/reviews/app/issue-7-r2.log`,
      `grep -n NOT-SAFE ${HOME}/reviews/app/issue-7-r2.md`,
      `less ${HOME}/evidence/issue-7/report.md`,
      `cat /w/app-issue-7/docs/superpowers/evidence/2026-10-15-x/run.txt`,
      `python3 -c "print(open('${HOME}/reviews/app/x.md').read())"`,
      `while read l; do echo "$l"; done < ${HOME}/sent.log`,
      `cat ${HOME}/reports/app/issue-9.md`,
      `cat ${HOME}/x/../reviews/app/issue-7-r2.md`,
    ]) {
      expect(judge(c, P)?.kind, c).toBe('read')
    }
  })

  test('lets counts, listings, appends, scripts and the queue through', () => {
    for (const c of [
      `grep -c ' pass ' ${HOME}/reviews/app/issue-7-hosted.log`,
      `grep -q m-1 ${HOME}/processed.log`,
      `ls ${HOME}/reviews/app/ | sed -n 's/^issue-7-r\\([0-9]*\\)\\.md$/\\1/p' | sort -n | tail -1`,
      `printf '%s\\n' 'm1 d1 2026' >> ${HOME}/processed.log`,
      `wc -l < ${HOME}/sent.log`,
      `sh /p/skills/star/done-check.sh --reviews ${HOME}/reviews/app --item issue-7`,
      `cat ${HOME}/open-loops.md`,
      `grep -cE '^grant: [^ #]' ${HOME}/briefs/app/issue-7.md`,
      `sort -u ${HOME}/briefs/app/issue-7.md > ${HOME}/reviews/app/sorted.md`,
    ]) {
      expect(judge(c, P), c).toBeUndefined()
    }
  })

  test('a Read path is judged the same way', () => {
    expect(protectedWhy(`${HOME}/reviews/app/issue-7-r2.md`, P)).toBe('a review file')
    expect(protectedWhy('docs/superpowers/context/star/sent.log', P)).toBe('a log file')
    expect(protectedWhy(`${HOME}/ledger.md`, P)).toBeUndefined()
  })
})

describe('fallback guard (the session\'s role is unknown)', () => {
  const review = `${HOME}/reviews/app/issue-7-r2.md`
  const bash = (command: string) => ({ tool: 'Bash', command })

  test('refuses a merge: every guarded role forbids a direct merge', () => {
    for (const c of ['gh pr merge 12 --squash', "bash -c 'gh pr merge 12 --auto'", 'gh api -X PUT repos/o/r/pulls/12/merge']) {
      expect(fallbackDeny(bash(c))?.kind, c).toBe('merge')
    }
    expect(fallbackDeny({ tool: 'Monitor', command: 'gh pr merge 12' })?.kind).toBe('merge')
  })

  test('refuses the merge in a command that also reads a protected file', () => {
    const command = `cat ${review} && gh pr merge 12`
    expect(judge(command, P)?.kind).toBe('read') // the first verdict is the read
    expect(fallbackDeny(bash(command))?.kind).toBe('merge')
  })

  test('passes a read: a worker or a person may read its own review file', () => {
    for (const c of [`cat ${review}`, `tail -n 20 ${HOME}/progress/issue-7.log`, `cat ${HOME}/reports/app/issue-9.md`]) {
      expect(judge(c, P)?.kind, c).toBe('read')
      expect(fallbackDeny(bash(c)), c).toBeUndefined()
    }
    expect(fallbackDeny(bash('gh pr view 12'))).toBeUndefined()
  })

  test('passes a Read tool call, a protected path included', () => {
    const read = { tool: 'Read', file_path: review }
    expect(protectedWhy(review, P)).toBe('a review file')
    expect(fallbackDeny(read)).toBeUndefined()
  })
})

describe('#114 rm guard', () => {
  test('writes bare variables in rm and rmdir paths as ${NAME:?}', () => {
    expect(guardRmVars('rmdir $S/$v')).toBe('rmdir ${S:?}/${v:?}')
    expect(guardRmVars('for v in a b; do rmdir "$S/$v"; done')).toBe('for v in a b; do rmdir "${S:?}/${v:?}"; done')
    expect(guardRmVars('rm -rf "${TMP}/x" && ls')).toBe('rm -rf "${TMP:?}/x" && ls')
    expect(guardRmVars('cd $D && rm -f $D/a.txt')).toBe('cd $D && rm -f ${D:?}/a.txt')
  })

  test('leaves literal, defaulted, special and variable-free forms alone', () => {
    for (const c of [
      "rm -f '$S/x'",
      'rm -f \\$S/x',
      'rm -rf "${S:-/tmp/s}/x"',
      'rm -f "$1" "$@"',
      'rm -f $(mktemp)',
      'echo $S && ls $S',
      'rm -rf build',
    ]) {
      expect(guardRmVars(c), c).toBeUndefined()
    }
  })
})

describe('band text', () => {
  const at = (iso: string): number => Date.parse(iso)
  const star = parseStar(STAR('term_A'))
  if (!star.ok) throw new Error(star.why)

  test('counts the pools and the open queue items, and lists the open ones only', () => {
    const band = bandOf(star.value, parseLedger(LEDGER), parseQueue(QUEUE), at('2026-10-15T08:05:00Z'))
    expect(band.line).toBe('STAR · 2 building · 1 babysitting · 1 verifying · 1 set-aside · 2 waiting · 2 need you')
    expect(band.tone).toBe('attention')
    expect(band.open).toBe(2)
    // N-13 is answered: STAR acts on it at its next tick, so the band leaves it out
    expect(band.needs.map(n => [n.id, n.kind, n.item])).toEqual([
      ['N-12', 'person', 'B-1'],
      ['N-14', 'escalation', 'issue-5'],
    ])
    expect(band.project).toBe('app')
    expect(band.state).toBe('running')
    expect(band.tick).toBe('5m ago')
  })

  test('draws the pools from the ledger, against the sizes in star.json', () => {
    const band = bandOf(star.value, parseLedger(LEDGER), parseQueue(QUEUE), at('2026-10-15T08:05:00Z'))
    expect(band.gauges).toEqual([
      { name: 'brief', used: 0, max: 4 },
      { name: 'build', used: 2, max: 3 },
      { name: 'babysit', used: 1, max: 3 },
    ])
    const wide = parseStar(JSON.stringify({ terminal: 'term_A', maxParallel: 6, maxBriefs: 2, maxInReview: 5 }))
    if (!wide.ok) throw new Error(wide.why)
    const sized = bandOf(wide.value, parseLedger(LEDGER), parseQueue(QUEUE), at('2026-10-15T08:05:00Z'))
    expect(sized.gauges.map(g => g.max)).toEqual([2, 6, 5])
  })

  test('says a stale tick and gate down', () => {
    const down = { ...star.value, isGateDown: true }
    const band = bandOf(down, parseLedger(LEDGER), parseQueue(QUEUE), at('2026-10-15T08:45:00Z'))
    expect(band.line).toBe('STAR · 2 building · 1 babysitting · 1 verifying · 1 set-aside · 2 waiting · 2 need you · gate down · last tick 45m ago')
    expect(band.tone).toBe('warn')
    expect(band.flags).toEqual(['gate down', 'last tick 45m ago'])
  })

  test('is one quiet line when nothing runs and nothing waits on the owner', () => {
    const idleQueue = QUEUE.replace(/### N-1[24][\s\S]*?Answer:\n/g, '').replace('state: running', 'state: idle')
    const band = bandOf(star.value, parseLedger(ledger([['issue-7', 'done', '-']])), parseQueue(idleQueue), at('2026-10-15T08:05:00Z'))
    expect(band.line).toBe('STAR idle · 1 done · nothing needs you')
    expect(band.tone).toBe('idle')
    expect(band.open).toBe(0)
  })

  test('names a file it cannot parse and keeps the rest', () => {
    const band = bandOf(star.value, parseLedger('# Ledger\n'), parseQueue(QUEUE), at('2026-10-15T08:05:00Z'))
    expect(band.line).toBe('STAR · ledger.md unreadable: no ledger table · 2 need you')
    expect(band.tone).toBe('error')
    expect(band.problems).toEqual(['ledger.md unreadable: no ledger table'])
    expect(band.gauges).toEqual([])
  })
})

describe('the queue as the band reads it', () => {
  const at = (iso: string): number => Date.parse(iso)

  test("reads each item's body between its kind line and its Answer line, never a note under the answer", () => {
    const queue = QUEUE.replace("Answer: done\n", "Answer: done\n\nmy own note, not the body\n")
    const parsed = parseQueue(queue)
    if (!parsed.ok) throw new Error(parsed.why)
    const byId = new Map(parsed.value.needs.map(n => [n.id, n]))
    expect(byId.get('N-12')?.body).toEqual(['issue-1', 'Options: go / go except <items> / drop <item>'])
    expect(byId.get('N-13')?.body).toEqual(["Options: done / can't now"])
    expect(byId.get('N-13')?.answer).toBe('done')
  })

  test('reads Waiting on others, quoted lines unquoted', () => {
    const parsed = parseQueue(QUEUE.replace('## Waiting on others\n', '## Waiting on others\nPR #12: a review from the team\n> ### a quoted line\n'))
    if (!parsed.ok) throw new Error(parsed.why)
    expect(parsed.value.waiting).toEqual(['PR #12: a review from the team', '### a quoted line'])
  })

  test("turns an Options line into picks, templates to finish, and the words it asks for", () => {
    expect(optionsOf(['Options: go / go except <items> / drop <item> / or say what to change'])).toEqual({
      options: [
        { label: 'go', text: 'go', recommended: false },
        { label: 'go except …', text: 'go except ', recommended: false },
        { label: 'drop …', text: 'drop ', recommended: false },
      ],
      hint: 'say what to change',
    })
    expect(optionsOf(['Options: answer with your decision to run the stage again / drop'])).toEqual({
      options: [{ label: 'drop', text: 'drop', recommended: false }],
      hint: 'answer with your decision to run the stage again',
    })
    expect(optionsOf(["Options: <the value> / can't now"])).toEqual({
      options: [{ label: "can't now", text: "can't now", recommended: false }],
      hint: 'type the value',
    })
    expect(optionsOf(['msg: m-1', 'deadline: 2026-10-15T08:30:00Z'])).toEqual({ options: [], hint: '' })
  })

  test('marks the recommended option, and sends its words without the suffix', () => {
    expect(optionsOf(["Options: done (recommended) / can't now"])).toEqual({
      options: [
        { label: 'done', text: 'done', recommended: true },
        { label: "can't now", text: "can't now", recommended: false },
      ],
      hint: '',
    })
    expect(optionsOf(['Options: send / rewrite: <how> (Recommended) / skip']).options).toEqual([
      { label: 'send', text: 'send', recommended: false },
      { label: 'rewrite: …', text: 'rewrite: ', recommended: true },
      { label: 'skip', text: 'skip', recommended: false },
    ])
  })

  test("reads the Suggest line as the item's suggestion, not as a detail", () => {
    const need = needOf(
      {
        id: 'N-30', kind: 'person', project: 'app', item: 'issue-4', title: 'confirm the host',
        body: ['brief: /h/briefs/app/issue-4.md', 'step: 1', '> kind: confirm-id', 'Suggest: staging.example.com: the brief names it', "Options: done (recommended) / can't now"],
        answer: '',
      },
      at('2026-10-15T08:07:00Z'),
    )
    expect(need.suggestion).toBe('staging.example.com: the brief names it')
    expect(need.details.map(d => d.key)).toEqual(['brief', 'step', 'kind'])
    expect(need.options[0]).toEqual({ label: 'done', text: 'done', recommended: true })
    const plain = needOf({ id: 'N-32', kind: 'held', project: 'app', item: 'issue-4', title: 't', body: ['Options: done'], answer: '' }, at('2026-10-15T08:07:00Z'))
    expect(plain.suggestion).toBe(null)
  })

  test('a secret step never carries a suggestion or a recommended option', () => {
    const need = needOf(
      {
        id: 'N-31', kind: 'person', project: 'app', item: 'issue-4', title: 'add the key',
        body: ['brief: /h/briefs/app/issue-4.md', 'step: 2', '> kind: secret (value)', 'Suggest: sk_test_123', "Options: done (recommended) / can't now"],
        answer: '',
      },
      at('2026-10-15T08:07:00Z'),
    )
    expect(need.suggestion).toBe(null)
    expect(need.options.map(o => o.recommended)).toEqual([false, false])
    expect(need.details.some(d => d.value.includes('sk_test'))).toBe(false)
    expect(need.names.some(n => n.includes('sk_test'))).toBe(false)
  })

  test('reads every ledger column, as ledger.sh writes them', () => {
    const parsed = parseLedger(LEDGER)
    if (!parsed.ok) throw new Error(parsed.why)
    expect(parsed.value[0]).toEqual({
      item: 'issue-1', ref: '#1', project: 'app', worktree: '/w/app-issue-1', state: 'building', stage: 'build',
      round: '1', task: 't-issue-1', dispatch: 'd-issue-1', restarts: '0', pr: '-', head: '-', cursor: '-',
      verify: '-', counters: '-', updated: '2026-10-15T08:00:00Z',
    })
  })

  test("shows a question's deadline, and leaves the Orca message id out", () => {
    const need = needOf(
      { id: 'N-20', kind: 'question', project: 'app', item: 'issue-1', title: 'which date format?', body: ['msg: m-77', 'deadline: 2026-10-15T08:30:00Z'], answer: '' },
      at('2026-10-15T08:07:00Z'),
    )
    expect(need.due).toBe('23m left')
    expect(need.details).toEqual([])
    expect(need.hint).toBe('type your answer')
    const late = needOf({ id: 'N-20', kind: 'question', project: 'app', item: 'issue-1', title: 'q', body: ['deadline: 2026-10-15T08:30:00Z'], answer: '' }, at('2026-10-15T08:35:00Z'))
    expect(late.due).toBe('5m overdue')
  })

  test("splits a person step's body into its fields, and a batch's into its item names", () => {
    const step = needOf(
      { id: 'N-21', kind: 'person', project: 'app', item: 'issue-4', title: 'add the key', body: ['brief: /h/briefs/app/issue-4.md', 'step: 2', '> kind: secret', "Options: done / can't now"], answer: '' },
      at('2026-10-15T08:07:00Z'),
    )
    expect(step.details).toEqual([
      { key: 'brief', value: '/h/briefs/app/issue-4.md' },
      { key: 'step', value: '2' },
      { key: 'kind', value: 'secret' },
    ])
    expect(step.names).toEqual([])
    expect(step.hint).toBe('or type an answer in words')
    const batch = needOf(
      { id: 'N-22', kind: 'person', project: 'app', item: 'B-1', title: 'the Stripe account for B-1', body: ['issue-1', 'issue-2', 'Options: go / drop <item>'], answer: '' },
      at('2026-10-15T08:07:00Z'),
    )
    expect(batch.names).toEqual(['issue-1', 'issue-2'])
  })
})

describe('cswap accounts', () => {
  test('reads cswap list --json: the active account first, aliases, usage and when a spent window resets', () => {
    const parsed = parseAccounts(CSWAP_LIST)
    if (!parsed.ok) throw new Error(parsed.why)
    expect(parsed.value.map(a => [a.alias, a.isActive, a.fiveHour, a.sevenDay, a.resets])).toEqual([
      ['personal', true, 5, 64, null],
      ['sphere', false, 0, 98, '1d 23h'],
      ['carol', false, 24, 7, null],
      ['old', false, null, null, null],
    ])
    const [, , carol, old] = parsed.value
    expect([carol?.isDisabled, carol?.isStale, carol?.status]).toEqual([true, true, 'unavailable'])
    expect([old?.isStale, old?.status]).toEqual([false, 'token expired'])
  })

  test('says why a payload cannot be read', () => {
    expect(parseAccounts('not json')).toEqual({ ok: false, why: 'cswap list --json printed no JSON' })
    expect(parseAccounts(JSON.stringify({ schemaVersion: 1, error: { message: 'no accounts file' } }))).toEqual({ ok: false, why: 'cswap: no accounts file' })
    expect(parseAccounts(JSON.stringify({ schemaVersion: 2, accounts: [] }))).toEqual({ ok: false, why: 'cswap list --json: an unknown schema' })
  })

  // Processes under this session's login, '' (unset, so ~/.claude) unless a test says otherwise.
  const HOMEDIR = '/Users/me'
  const procs = (text: string, configDir = ''): Proc[] => text.split('\n').filter(Boolean).map(command => ({ command, configDir }))
  const auto = (ps: Proc[], menubar: string | null = null, cron = '', mine = '') => autoOf(ps, menubar, cron, mine, HOMEDIR)

  test('auto is on while a cswap auto loop runs, and in dry run when that is all there is', () => {
    const py = '/opt/homebrew/Cellar/python@3.12/3.12.13_4/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python'
    expect(auto(procs(`${py} /Users/me/.local/bin/cswap auto --threshold 80`))).toEqual({ state: 'on', via: 'cswap auto' })
    expect(auto(procs('cswap auto --dry-run'))).toEqual({ state: 'dry run', via: 'cswap auto' })
    expect(auto(procs('cswap auto --once --json'))).toEqual({ state: 'off', via: '' })
    // a shell or a grep that only mentions it is not cswap
    expect(auto(procs("grep cswap auto\nzsh -c 'cswap auto'"))).toEqual({ state: 'off', via: '' })
    // the dashboard is not the loop
    expect(auto(procs(`${py} /Users/me/.local/bin/cswap`))).toEqual({ state: 'off', via: '' })
  })

  test("auto is on through the menu bar only while it runs with its toggle on", () => {
    const menubar = procs('/Users/me/.local/bin/cswap menubar')
    expect(auto(menubar, '{"auto_switch_enabled": true}')).toEqual({ state: 'on', via: 'menu bar' })
    expect(auto(menubar, '{"auto_switch_enabled": false}')).toEqual({ state: 'off', via: '' })
    expect(auto([], '{"auto_switch_enabled": true}')).toEqual({ state: 'off', via: '' })
    expect(auto(procs('cswap menubar --service-status'), '{"auto_switch_enabled": true}')).toEqual({ state: 'off', via: '' })
  })

  test('auto is on through a cron entry that runs cswap auto --once', () => {
    expect(auto([], null, '*/5 * * * * cswap auto --once --json >> ~/.cswap-auto.log 2>&1\n')).toEqual({ state: 'on', via: 'cron' })
    expect(auto([], null, '# */5 * * * * cswap auto --once\n')).toEqual({ state: 'off', via: '' })
  })

  test("only what runs under this session's Claude login counts", () => {
    const personal = '/Users/me/.claude-personal'
    const sphere = '/Users/me/.claude-sphere'
    // a loop for the personal login does nothing for a sphere session
    expect(auto(procs('cswap auto', personal), null, '', sphere)).toEqual({ state: 'off', via: '' })
    expect(auto(procs('cswap auto', personal), null, '', personal)).toEqual({ state: 'on', via: 'cswap auto' })
    // ~ and a trailing slash are the same folder; unset is ~/.claude
    expect(auto(procs('cswap auto', '~/.claude-personal/'), null, '', personal)).toEqual({ state: 'on', via: 'cswap auto' })
    expect(auto(procs('cswap auto', ''), null, '', '/Users/me/.claude')).toEqual({ state: 'on', via: 'cswap auto' })
    expect(auto(procs('cswap auto', ''), null, '', sphere)).toEqual({ state: 'off', via: '' })
    // the menu bar under launchd has no CLAUDE_CONFIG_DIR: it switches ~/.claude
    expect(auto(procs('cswap menubar'), '{"auto_switch_enabled": true}', '', personal)).toEqual({ state: 'off', via: '' })
    // a crontab's variable line applies to the jobs under it; an inline one to its own job
    const cron = `CLAUDE_CONFIG_DIR=${personal}\n*/5 * * * * cswap auto --once\n`
    expect(auto([], null, cron, personal)).toEqual({ state: 'on', via: 'cron' })
    expect(auto([], null, cron, sphere)).toEqual({ state: 'off', via: '' })
    expect(auto([], null, `*/5 * * * * CLAUDE_CONFIG_DIR=${sphere} cswap auto --once\n`, sphere)).toEqual({ state: 'on', via: 'cron' })
  })

  test('a config folder has one spelling', () => {
    expect(normDir('', HOMEDIR)).toBe('/Users/me/.claude')
    expect(normDir('~/.claude-personal/', HOMEDIR)).toBe('/Users/me/.claude-personal')
    expect(normDir('$HOME/.claude-sphere', HOMEDIR)).toBe('/Users/me/.claude-sphere')
    expect(normDir('"/Users/me/.claude-x"', HOMEDIR)).toBe('/Users/me/.claude-x')
  })
})

describe('machine text in the reply field', () => {
  test("Orca's nudge and STAR's own prompts are never an answer", () => {
    for (const t of ['You have 1 orchestration message. Run orca orchestration check --run run_c538777b6a11.', 'You have 3 orchestration messages.', 'STAR heartbeat: if you are not already in a tick, run one.', 'inbox', '  INBOX  ']) {
      expect(isMachineText(t), t).toBe(true)
    }
  })

  test("the owner's words are", () => {
    for (const t of ['go', 'drop SPH-17', 'inbox it later', 'you have my go', 'accept']) {
      expect(isMachineText(t), t).toBe(false)
    }
  })
})
