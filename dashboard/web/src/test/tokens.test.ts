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

describe("motion classes (I-15)", () => {
  const at = css.indexOf("@media (prefers-reduced-motion: reduce)")
  const main = at < 0 ? css : css.slice(0, at)
  const reduce = at < 0 ? "" : css.slice(at)
  const rule = (selector: string) => {
    const start = main.indexOf(`${selector} {`)
    return start < 0 ? "" : main.slice(start, main.indexOf("}", start))
  }
  it("times each one as the mockup does", () => {
    expect(rule(".motion-pop")).toContain("star-pop 420ms cubic-bezier(0.34, 1.56, 0.64, 1)")
    expect(rule(".motion-breathe")).toContain("star-breathe 2.4s ease-in-out infinite")
    expect(rule(".motion-pop.motion-breathe")).toContain("star-breathe 2.4s ease-in-out 420ms infinite")
    expect(rule(".motion-sweep::after")).toContain("star-sweep 1.8s ease-in-out infinite")
    expect(rule(".motion-ping::after")).toContain("star-ping 2s cubic-bezier(0, 0, 0.2, 1) infinite")
    expect(rule(".motion-ping::after")).toContain("background: inherit")
    expect(rule(".motion-fade-in")).toContain("star-rise 200ms")
    expect(rule(".motion-row-in")).toContain("star-rise 250ms")
    expect(rule(".motion-bar")).toMatch(/transition:[^;]*width 600ms[^;]*transform 600ms/)
    for (const name of ["star-pop", "star-breathe", "star-sweep", "star-ping", "star-rise"])
      expect(css).toContain(`@keyframes ${name} {`)
  })
  it("turns every one off under prefers-reduced-motion: reduce", () => {
    expect(at).toBeGreaterThan(0)
    for (const selector of [".motion-pop", ".motion-breathe", ".motion-pop.motion-breathe", ".motion-fade-in", ".motion-row-in", ".motion-sweep::after", ".motion-ping::after"])
      expect(reduce).toContain(selector)
    expect(reduce).toMatch(/animation:\s*none/)
    expect(reduce).toMatch(/\.motion-bar\s*\{\s*transition:\s*none/)
  })
})

// oklch -> oklab -> linear sRGB (Ottosson's matrices) -> WCAG relative luminance.
function luminance(value: string): number {
  const m = /oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\)/.exec(value)
  if (!m) throw new Error(`not an oklch value: ${value}`)
  const [L, C, h] = [Number(m[1]), Number(m[2]), (Number(m[3]) * Math.PI) / 180]
  const a = C * Math.cos(h)
  const b = C * Math.sin(h)
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
  const mm = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3
  const rgb = [
    4.0767416621 * l - 3.3077115913 * mm + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * mm - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * mm + 1.707614701 * s,
  ].map((v) => Math.min(1, Math.max(0, v)))
  return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
}
const contrast = (a: string, b: string) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

describe("answer colour and fonts", () => {
  const light = block(":root")
  const dark = block(".dark")
  const theme = block("@theme inline")
  const value = (blockText: string, name: string) => new RegExp(`--${name}:\\s*(oklch\\([^)]*\\))`).exec(blockText)?.[1] ?? ""
  it("defines --answer and --answer-foreground as oklch in both themes", () => {
    for (const b of [light, dark]) {
      expect(b).toMatch(/--answer:\s*oklch\(/)
      expect(b).toMatch(/--answer-foreground:\s*oklch\(/)
    }
  })
  it("maps them in @theme inline", () => {
    expect(theme).toContain("--color-answer: var(--answer)")
    expect(theme).toContain("--color-answer-foreground: var(--answer-foreground)")
  })
  it("uses Instrument Sans and the system mono stack, with no Geist", () => {
    expect(theme).toMatch(/--font-sans:\s*"Instrument Sans Variable"/)
    expect(theme).toMatch(/--font-mono:\s*ui-monospace/)
    expect(css.toLowerCase()).not.toContain("geist")
  })
  it("answer text contrast is at least 4.5:1 in both themes", () => {
    for (const b of [light, dark])
      expect(contrast(value(b, "answer"), value(b, "answer-foreground"))).toBeGreaterThanOrEqual(4.5)
  })
})
