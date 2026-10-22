import { beforeEach, describe, expect, it } from "vitest"
import { linkManifest } from "./manifest-link"

const links = () => document.head.querySelectorAll('link[rel="manifest"]')

describe("linkManifest", () => {
  beforeEach(() => {
    document.head.replaceChildren()
  })

  it("links the manifest with the token", () => {
    linkManifest("abc")
    expect(links()).toHaveLength(1)
    expect(links()[0]?.getAttribute("href")).toBe("/manifest.webmanifest?t=abc")
  })

  it("keeps one link when called again, and encodes the token", () => {
    linkManifest("abc")
    linkManifest("d e/f")
    expect(links()).toHaveLength(1)
    expect(links()[0]?.getAttribute("href")).toBe(
      "/manifest.webmanifest?t=d%20e%2Ff"
    )
  })

  it("links the bare manifest when there is no token", () => {
    linkManifest(null)
    expect(links()[0]?.getAttribute("href")).toBe("/manifest.webmanifest")
    linkManifest("")
    expect(links()).toHaveLength(1)
    expect(links()[0]?.getAttribute("href")).toBe("/manifest.webmanifest")
  })

  it("removes a manifest link the page already had", () => {
    document.head.innerHTML = '<link rel="manifest" href="/old.json">'
    linkManifest("abc")
    expect(links()).toHaveLength(1)
  })
})
