import { needOf } from '../../../hooks/star.ts'
import type { NeedItem } from '../../../hooks/star.ts'
import type { Ctx } from '../app.ts'
import { readQueue } from '../readers/star.ts'
import type { Router } from '../router.ts'

const BLOCKED = ['go-batch', 'question', 'person', 'escalation', 'restart-or-drop', 'go-merge']
const rank = (kind: string): number => (BLOCKED.includes(kind) ? 0 : kind === 'slack-reply' ? 1 : 2)
const num = (id: string): number => Number(id.slice(2)) || 0

export function loopOf(n: NeedItem, nowMs: number): Record<string, unknown> {
  const need = needOf(n, nowMs)
  return { id: n.id, kind: n.kind, item: n.item, title: n.title, body: n.body.filter(l => !/^(options|suggest)\s*:/i.test(l)), options: need.options.map(o => ({ label: o.label, answer: o.text, recommended: o.recommended })), suggestion: need.suggestion, answer: n.answer, askedAt: null }
}

export function loopRoutes(router: Router, ctx: Ctx): void {
  router.add('GET', '/api/projects/:p/loops', async req => {
    const p = await ctx.registry.find(req.params['p'] ?? '')
    const needs = [...readQueue(p.home).needs].sort((a, b) => rank(a.kind) - rank(b.kind) || num(a.id) - num(b.id))
    return { json: needs.map(n => loopOf(n, Date.now())) }
  })
}
