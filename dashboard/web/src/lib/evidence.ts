import type { EvidenceFile } from "@/api/types"

/** One cell of the evidence grid: a file on its own, or a before shot beside its counterpart. */
export type EvidenceTile =
  | { kind: "single"; file: EvidenceFile; before: boolean }
  | { kind: "pair"; before: EvidenceFile; after: EvidenceFile }

export const isMedia = (file: EvidenceFile) => file.kind !== "text"

/** The folder and the lowercase words of the file's name, split on - _ . and spaces, extension dropped. */
function nameWords(name: string): { dir: string; words: string[] } {
  const slash = name.lastIndexOf("/")
  const base = name.slice(slash + 1)
  const dot = base.lastIndexOf(".")
  const stem = dot > 0 ? base.slice(0, dot) : base
  return {
    dir: name.slice(0, slash + 1),
    words: stem
      .toLowerCase()
      .split(/[-_.\s]+/)
      .filter(Boolean),
  }
}

const hasWord = (file: EvidenceFile, word: string) =>
  nameWords(file.name).words.includes(word)

/** An image or recording with "before" as a word of its name: the old version. */
export const isBefore = (file: EvidenceFile) =>
  isMedia(file) && hasWord(file, "before")

/** A before shot and its counterpart share this: same kind, same folder, same name without before/after. */
function pairKey(file: EvidenceFile): string {
  const { dir, words } = nameWords(file.name)
  const rest = words.filter((w) => w !== "before" && w !== "after")
  return `${file.kind}:${dir}${rest.join("-")}`
}

/**
 * Pairs each before shot with the image or recording that shares its name without the word
 * "before" (an "after" name wins over a bare one). Pairs come first, so they sit as whole rows
 * above the grid; every other file keeps its order. A before shot with no counterpart stays single.
 */
export function evidenceTiles(files: EvidenceFile[]): EvidenceTile[] {
  const counterpart = new Map<string, EvidenceFile>()
  for (const file of files) {
    if (!isMedia(file) || isBefore(file)) continue
    const key = pairKey(file)
    const seen = counterpart.get(key)
    if (!seen || (!hasWord(seen, "after") && hasWord(file, "after")))
      counterpart.set(key, file)
  }
  const paired = new Set<EvidenceFile>()
  const pairs: EvidenceTile[] = []
  for (const file of files) {
    if (!isBefore(file)) continue
    const after = counterpart.get(pairKey(file))
    if (!after || paired.has(after)) continue
    paired.add(file).add(after)
    pairs.push({ kind: "pair", before: file, after })
  }
  const singles: EvidenceTile[] = files
    .filter((file) => !paired.has(file))
    .map((file) => ({ kind: "single", file, before: isBefore(file) }))
  return [...pairs, ...singles]
}
