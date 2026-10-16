import { beforeEach, describe, expect, it, vi } from "vitest"

/** A fresh copy of the module: what a new tab or a home-screen start sees. */
async function load(): Promise<typeof import("./token")> {
  vi.resetModules()
  return import("./token")
}
const visit = (path: string) => window.history.replaceState(null, "", path)
const realSetItem = Storage.prototype.setItem
function refuseWrites(areas: Storage[]) {
  vi.spyOn(Storage.prototype, "setItem").mockImplementation(function (this: Storage, key: string, value: string) {
    if (areas.includes(this)) throw new DOMException("full", "QuotaExceededError")
    realSetItem.call(this, key, value)
  })
}

describe("the dashboard token", () => {
  beforeEach(() => { vi.restoreAllMocks(); localStorage.clear(); sessionStorage.clear(); visit("/") })
  it("returns null when there is no token anywhere", async () => {
    const token = await load()
    expect(token.captureToken()).toBeNull()
    expect(token.getToken()).toBeNull()
  })
  it("keeps ?t= in localStorage, over an older token, and drops it from the visible URL", async () => {
    localStorage.setItem("star-token", "old")
    visit("/sphere-app/needs?t=abc123&loop=N-41#top")
    expect((await load()).captureToken()).toBe("abc123")
    expect(localStorage.getItem("star-token")).toBe("abc123")
    expect(window.location.pathname + window.location.search + window.location.hash).toBe("/sphere-app/needs?loop=N-41#top")
  })
  it("reads a token captured once after a fresh load with no ?t= (a closed tab, a home-screen icon)", async () => {
    visit("/sphere-app/needs?t=abc123")
    ;(await load()).captureToken()
    sessionStorage.clear()
    visit("/sphere-app/needs")
    const later = await load()
    expect(later.captureToken()).toBe("abc123")
    expect(later.getToken()).toBe("abc123")
  })
  it("still reads a token a page from before this change left in sessionStorage", async () => {
    sessionStorage.setItem("star-token", "kept")
    expect((await load()).captureToken()).toBe("kept")
    expect(window.location.search).toBe("")
  })
  it("falls back to sessionStorage when localStorage cannot store it", async () => {
    refuseWrites([localStorage])
    visit("/?t=s1")
    expect((await load()).captureToken()).toBe("s1")
    expect(sessionStorage.getItem("star-token")).toBe("s1")
    expect(localStorage.getItem("star-token")).toBeNull()
    expect((await load()).getToken()).toBe("s1")
  })
  it("keeps the token in memory when no storage can store it", async () => {
    refuseWrites([localStorage, sessionStorage])
    visit("/?t=mem")
    const token = await load()
    expect(token.captureToken()).toBe("mem")
    expect(token.getToken()).toBe("mem")
  })
  it("never throws when storage cannot be read", async () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => { throw new DOMException("denied", "SecurityError") })
    const token = await load()
    expect(token.getToken()).toBeNull()
    token.saveToken("pasted")
    expect(token.getToken()).toBe("pasted")
  })
  it("saveToken keeps a pasted token for later visits", async () => {
    ;(await load()).saveToken("pasted")
    expect(localStorage.getItem("star-token")).toBe("pasted")
    expect((await load()).getToken()).toBe("pasted")
  })
  it("takes the token out of a pasted link or the whole line /juel:star dashboard prints", async () => {
    const { tokenFromPaste } = await load()
    expect(tokenFromPaste("  0123abcd \n")).toBe("0123abcd")
    expect(tokenFromPaste("http://127.0.0.1:4767/?t=0123abcd")).toBe("0123abcd")
    expect(tokenFromPaste("STAR dashboard: http://127.0.0.1:4767/?t=0123abcd")).toBe("0123abcd")
    expect(tokenFromPaste("https://mac.tail1234.ts.net/sphere-app/needs?loop=N-4&t=0123abcd#x")).toBe("0123abcd")
    expect(tokenFromPaste("   ")).toBe("")
  })
})
