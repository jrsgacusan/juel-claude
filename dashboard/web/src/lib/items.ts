import type { ItemRow } from "@/api/types"

// integration brief D5: a ledger ref is the raw reference, a spec file path for a spec item and "-" when there is none. Only a tracker ref (SPH-7, #41) shows beside the item name, and not when the item is already named after it.
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
