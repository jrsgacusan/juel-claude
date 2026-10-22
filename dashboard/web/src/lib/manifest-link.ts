/** Points the document at the web app manifest, carrying the token when there is one. */
export function linkManifest(
  token: string | null,
  doc: Document = document
): void {
  for (const existing of doc.head.querySelectorAll('link[rel="manifest"]'))
    existing.remove()
  const link = doc.createElement("link")
  link.rel = "manifest"
  link.setAttribute(
    "href",
    token
      ? `/manifest.webmanifest?t=${encodeURIComponent(token)}`
      : "/manifest.webmanifest"
  )
  doc.head.append(link)
}
