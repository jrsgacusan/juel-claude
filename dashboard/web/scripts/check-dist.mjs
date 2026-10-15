// Fails the build when the mock layer reached dist/ (brief D3): no mockServiceWorker.js, and no
// file that carries MSW's code. Run by `npm run build` after `vite build`.
import { readdir, readFile } from "node:fs/promises"
import { basename, extname, join } from "node:path"
import { fileURLToPath } from "node:url"

const dist = fileURLToPath(new URL("../dist/", import.meta.url))
const MARKERS = ["mockServiceWorker", "setupWorker", "[MSW]", "msw/browser"]
const TEXT = new Set([
  ".js",
  ".mjs",
  ".css",
  ".html",
  ".map",
  ".json",
  ".txt",
  ".svg",
])

async function* walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) yield* walk(path)
    else yield path
  }
}

const bad = []
let count = 0
for await (const file of walk(dist)) {
  count += 1
  if (basename(file) === "mockServiceWorker.js") {
    bad.push(`${file}: the MSW worker file`)
    continue
  }
  if (!TEXT.has(extname(file))) continue
  const text = await readFile(file, "utf8")
  const hit = MARKERS.find((m) => text.includes(m))
  if (hit) bad.push(`${file}: contains "${hit}"`)
}
if (bad.length) {
  console.error(`check-dist: the mock layer reached dist/:\n${bad.join("\n")}`)
  process.exit(1)
}
console.log(`check-dist: ok, ${count} files, no mock layer`)
