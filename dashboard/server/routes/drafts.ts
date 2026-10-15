import fs from 'node:fs'
import path from 'node:path'
import type { Ctx } from '../app.ts'
import { HttpError, Unreadable, whyOf } from '../http.ts'
import { isPlainName } from '../readers/files.ts'
import type { Router } from '../router.ts'

export function draftRoutes(router: Router, ctx: Ctx): void {
  router.add('PUT', '/api/projects/:p/drafts/:name', async req => {
    const p = await ctx.registry.find(req.params['p'] ?? '')
    const name = req.params['name'] ?? ''
    if (!isPlainName(name)) throw new HttpError(400, `${name} is not a draft file name`)
    const body = req.body as { text?: unknown } | undefined
    if (typeof body?.text !== 'string') throw new HttpError(400, 'text must be a string')
    const file = path.join(p.home, 'drafts', name)
    let current: string
    try { current = fs.readFileSync(file, 'utf8') } catch (err) {
      if ((err as { code?: unknown }).code === 'ENOENT') throw new HttpError(404, `no draft ${name}`)
      throw new Unreadable(`drafts/${name}`, whyOf(err))
    }
    const first = current.split('\n')[0] ?? ''
    const reply = body.text.replace(/\r\n?/g, '\n').replace(/\s+$/, '')
    const tmp = `${file}.tmp.${process.pid}`
    fs.writeFileSync(tmp, `${first}\n${reply}\n`)
    fs.renameSync(tmp, file)
    return { json: { saved: true } }
  })
}
