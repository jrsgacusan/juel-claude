import type { ItemRow } from "@/api/types"

// brief D5: STAR's ledger ref is a spec path for a spec item, `-` when empty.
export function trackerRef(row: Pick<ItemRow, "item" | "ref">): string | null {
  const ref = row.ref?.trim()
  if (!ref || ref === "-" || ref === row.item) return null
  if (/^(\/|~\/|\.{1,2}\/)/.test(ref) || /\.md$/i.test(ref)) return null
  return ref
}

export function itemLabel(row: Pick<ItemRow, "item" | "ref">): string {
  const ref = trackerRef(row)
  return ref ? `${row.item} · ${ref}` : row.item
}
