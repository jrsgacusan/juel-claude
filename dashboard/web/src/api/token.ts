const TOKEN_KEY = "star-token"
let memory: string | null = null

function readFrom(area: () => Storage): string | null {
  try {
    return area().getItem(TOKEN_KEY)
  } catch {
    return null
  }
}

export function getToken(): string | null {
  return (
    memory ??
    readFrom(() => localStorage) ??
    readFrom(() => sessionStorage) ??
    null
  )
}

export function saveToken(token: string): void {
  memory = token
  try {
    localStorage.setItem(TOKEN_KEY, token)
    return
  } catch {
    // Fall through to sessionStorage.
  }
  try {
    sessionStorage.setItem(TOKEN_KEY, token)
  } catch {
    // Storage may be unavailable; the in-memory copy remains usable.
  }
}

/** The token out of a pasted link, the whole printed line, or the bare token. */
export function tokenFromPaste(text: string): string {
  return /[?&]t=([^&#\s]+)/.exec(text)?.[1] ?? text.trim()
}

export function captureToken(): string | null {
  const url = new URL(window.location.href)
  const fromUrl = url.searchParams.get("t")
  if (fromUrl) {
    saveToken(fromUrl)
    url.searchParams.delete("t")
    window.history.replaceState(
      window.history.state,
      "",
      url.pathname + url.search + url.hash
    )
  }
  return getToken()
}
