export const TOKEN_KEY = "star-token"
let memory: string | null = null

export function getToken(): string | null {
  try {
    return sessionStorage.getItem(TOKEN_KEY) ?? memory
  } catch {
    return memory
  }
}

export function captureToken(): string | null {
  const url = new URL(window.location.href)
  const fromUrl = url.searchParams.get("t")
  if (fromUrl) {
    memory = fromUrl
    try {
      sessionStorage.setItem(TOKEN_KEY, fromUrl)
    } catch {
      // Storage may be unavailable; the in-memory copy remains usable.
    }
    url.searchParams.delete("t")
    window.history.replaceState(
      window.history.state,
      "",
      url.pathname + url.search + url.hash
    )
  }
  return getToken()
}
