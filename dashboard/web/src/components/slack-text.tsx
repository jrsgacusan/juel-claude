import { Fragment, type ReactNode } from "react"
import { cn } from "@/lib/utils"

const BULLET = /^\s*[•◦▪*-]\s+/
const INLINE = /<([^<>\s|]+)(?:\|([^<>]*))?>|(https?:\/\/[^\s<>]+)/g
const WEB = /^https?:\/\//
const TRAILING = ".,;:!?"

const decode = (text: string) =>
  text.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")

const Link = ({ href, children }: { href: string; children: ReactNode }) => (
  <a
    href={href}
    target="_blank"
    rel="noopener noreferrer"
    className="break-all font-medium underline underline-offset-2"
  >
    {children}
  </a>
)

/** A bare URL without the punctuation a sentence puts after it, and an unmatched closing bracket. */
function splitTrailing(raw: string): [string, string] {
  let url = raw
  for (;;) {
    const last = url[url.length - 1]
    const unmatched =
      last === ")" && (url.match(/\)/g) ?? []).length > (url.match(/\(/g) ?? []).length
    if (last !== undefined && (TRAILING.includes(last) || unmatched)) url = url.slice(0, -1)
    else break
  }
  return [url, raw.slice(url.length)]
}

function inline(line: string): ReactNode[] {
  const out: ReactNode[] = []
  let last = 0
  let key = 0
  for (const match of line.matchAll(INLINE)) {
    const at = match.index
    if (at > last) out.push(decode(line.slice(last, at)))
    const [whole, target, label, bare] = match
    if (bare !== undefined) {
      const [url, rest] = splitTrailing(bare)
      const href = decode(url)
      out.push(<Link key={key++} href={href}>{href}</Link>)
      if (rest) out.push(decode(rest))
    } else if (target !== undefined && WEB.test(target)) {
      const href = decode(target)
      out.push(<Link key={key++} href={href}>{label ? decode(label) : href}</Link>)
    } else {
      out.push(decode(label ?? whole))
    }
    last = at + whole.length
  }
  if (last < line.length) out.push(decode(line.slice(last)))
  return out
}

type Block = { kind: "p"; lines: string[] } | { kind: "ul"; items: string[] }

function blocks(text: string): Block[] {
  const out: Block[] = []
  let current: Block | null = null
  for (const line of text.split("\n")) {
    if (line.trim() === "") {
      current = null
    } else if (BULLET.test(line)) {
      if (current?.kind !== "ul") out.push((current = { kind: "ul", items: [] }))
      current.items.push(line.replace(BULLET, ""))
    } else {
      if (current?.kind !== "p") out.push((current = { kind: "p", lines: [] }))
      current.lines.push(line)
    }
  }
  return out
}

/** A Slack message as React elements only: line breaks, bullets, and http(s) links. Never HTML. */
export function SlackText({ text, className }: { text: string; className?: string }) {
  return (
    <div className={cn("flex min-w-0 flex-col gap-2 break-words", className)}>
      {blocks(text).map((block, i) =>
        block.kind === "ul" ? (
          <ul key={i} className="list-disc space-y-1 pl-5">
            {block.items.map((item, j) => (
              <li key={j}>{inline(item)}</li>
            ))}
          </ul>
        ) : (
          <p key={i}>
            {block.lines.map((line, j) => (
              <Fragment key={j}>
                {j > 0 && <br />}
                {inline(line)}
              </Fragment>
            ))}
          </p>
        )
      )}
    </div>
  )
}
