import type { Ctx } from '../app.ts'
import { readLedger, readQueue, readStar, tickOf, valueOf } from '../readers/star.ts'
import type { Router } from '../router.ts'

export function projectRoutes(router: Router, ctx: Ctx): void {
  router.add('GET', '/api/projects', async () => {
    const list = await ctx.registry.current()
    return { json: list.map(p => {
      let lastTick: string | null = null
      let needsYou: number | null = null
      try { const q = readQueue(p.home); lastTick = tickOf(q.resume); needsYou = q.needs.filter(n => !n.answer).length }
      catch (err) { ctx.log(`projects: ${p.name}: ${err instanceof Error ? err.message : String(err)}`) }
      return { name: p.name, repo: p.repo, state: p.state, terminal: p.terminal, lastTick, needsYou }
    }) }
  })

  router.add('GET', '/api/projects/:p/overview', async req => {
    const p = await ctx.registry.find(req.params['p'] ?? '')
    const { star, raw } = readStar(p.home)
    const rows = readLedger(p.home)
    const q = readQueue(p.home)
    const counts: Record<string, number> = {}
    for (const r of rows) counts[r.state] = (counts[r.state] ?? 0) + 1
    const inState = (...states: string[]): number => rows.filter(r => states.includes(r.state)).length
    const gate = raw['gateDown'] as Record<string, unknown> | null | undefined
    const str = (v: unknown): string | null => (typeof v === 'string' ? v : null)
    return { json: {
      resume: { state: valueOf(q.resume, 'state'), pools: valueOf(q.resume, 'pools'), next: valueOf(q.resume, 'next'), lastTick: tickOf(q.resume) },
      counts,
      workers: { brief: [inState('briefing'), star.maxBriefs], build: [inState('building', 'posting'), star.maxParallel], babysit: [inState('babysitting'), star.maxInReview] },
      gateDown: gate && typeof gate === 'object' ? { since: str(gate['since']), why: str(gate['why']) } : null,
      away: str(raw['away']), quietHours: raw['quietHours'] && typeof raw['quietHours'] === 'object' ? raw['quietHours'] : null,
    } }
  })
}
