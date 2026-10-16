import path from 'node:path'

export type Kind = 'image' | 'video' | 'text'
const IMAGES = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'])
const VIDEOS = new Set(['.webm', '.mp4', '.mov', '.m4v'])

/**
 * By extension: image, video, else text. Evidence files carry no criterion in their names, so the
 * evidence route returns them as one group.
 */
export function kindOf(name: string): Kind {
  const ext = path.extname(name).toLowerCase()
  return IMAGES.has(ext) ? 'image' : VIDEOS.has(ext) ? 'video' : 'text'
}

/** <home>/evidence/<item>: where worktree-clean.sh copies an item's evidence. */
export const evidenceDir = (home: string, item: string): string => path.join(home, 'evidence', item)
