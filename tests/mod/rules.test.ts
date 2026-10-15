// The pure rules: no session, no `$`. Each case is a command STAR or a worker really runs, or one
// the guard exists to stop.
import { describe, expect, test } from 'claude-code/testing'

import { fallbackDeny, guardRmVars, judge, protectedWhy } from '../../hooks/guards'
import type { Protect } from '../../hooks/guards'
import { bandOf, parseLedger, parseQueue, parseStar } from '../../hooks/star'
import { HOME, LEDGER, QUEUE, ROOT, STAR, ledger } from './fixtures'

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
      `sh /p/skills/star/merge.sh https://github.com/o/r/pull/12 --head ${SHA} --grant g.md --home ${HOME} --item issue-1`,
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

  test('counts the pools and the open queue items, and lists the open ones', () => {
    const band = bandOf(star.value, parseLedger(LEDGER), parseQueue(QUEUE), at('2026-10-15T08:05:00Z'))
    expect(band.line).toBe('STAR · 2 building · 1 babysitting · 1 verifying · 1 escalated · 2 waiting · 2 need you')
    expect(band.tone).toBe('attention')
    expect(band.needs).toEqual([
      'N-12 go-batch · B-1: go for batch B-1: 3 items',
      'N-14 escalation · issue-5: NOT-SAFE again after a re-scope',
    ])
  })

  test('says a stale tick and gate down', () => {
    const down = { ...star.value, isGateDown: true }
    const band = bandOf(down, parseLedger(LEDGER), parseQueue(QUEUE), at('2026-10-15T08:45:00Z'))
    expect(band.line).toBe('STAR · 2 building · 1 babysitting · 1 verifying · 1 escalated · 2 waiting · 2 need you · gate down · last tick 45m ago')
    expect(band.tone).toBe('warn')
  })

  test('is one quiet line when nothing runs and nothing waits on the owner', () => {
    const idleQueue = QUEUE.replace(/### N-1[24][\s\S]*?Answer:\n/g, '').replace('state: running', 'state: idle')
    const band = bandOf(star.value, parseLedger(ledger([['issue-7', 'done', '-']])), parseQueue(idleQueue), at('2026-10-15T08:05:00Z'))
    expect(band.line).toBe('STAR idle · 1 done · nothing needs you')
    expect(band.tone).toBe('idle')
  })

  test('names a file it cannot parse and keeps the rest', () => {
    const band = bandOf(star.value, parseLedger('# Ledger\n'), parseQueue(QUEUE), at('2026-10-15T08:05:00Z'))
    expect(band.line).toBe('STAR · ledger.md unreadable: no ledger table · 2 need you')
    expect(band.tone).toBe('error')
  })
})
