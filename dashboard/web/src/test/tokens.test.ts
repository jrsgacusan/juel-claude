// @ts-expect-error Node typings are only enabled for the tooling project, not the browser app.
import { readFileSync } from "node:fs"
// @ts-expect-error Node typings are only enabled for the tooling project, not the browser app.
import { resolve } from "node:path"
import { describe, expect, it } from "vitest"

// The state colors (brief: amber needs you, blue running, green done, red stopped) must exist in
// both themes, or every Dot, state badge and banner renders without color.
const css = readFileSync(resolve((import.meta as ImportMeta & { dirname: string }).dirname, "../index.css"), "utf8")
const block = (selector: string) => {
  const at = css.indexOf(`${selector} {`)
  return at < 0 ? "" : css.slice(at, css.indexOf("}", at))
}

describe("state color tokens", () => {
  const light = block(":root")
  const dark = block(".dark")
  for (const tone of ["wait", "run", "done", "stop"]) {
    it(`defines --${tone} and its fg/bg/line in light mode`, () => {
      for (const name of [tone, `${tone}-fg`, `${tone}-bg`, `${tone}-line`]) {
        expect(light).toMatch(new RegExp(`--${name}:\\s*oklch\\(`))
      }
    })
    it(`overrides --${tone}-fg/bg/line in dark mode`, () => {
      for (const name of [`${tone}-fg`, `${tone}-bg`, `${tone}-line`]) {
        expect(dark).toMatch(new RegExp(`--${name}:\\s*oklch\\(`))
      }
    })
  }
  it("defines the screenshot tokens in both themes", () => {
    for (const name of ["shot", "shot-bar", "shot-line"]) {
      expect(light).toMatch(new RegExp(`--${name}:\\s*oklch\\(`))
      expect(dark).toMatch(new RegExp(`--${name}:\\s*oklch\\(`))
    }
  })
})
