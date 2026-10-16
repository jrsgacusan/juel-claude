import ReactMarkdown, { type Components } from "react-markdown"
import remarkGfm from "remark-gfm"
import { cn } from "@/lib/utils"

const COMPONENTS: Components = {
  h1: ({ children }) => <h1 className="text-base font-semibold">{children}</h1>,
  h2: ({ children }) => <h2 className="text-sm font-semibold">{children}</h2>,
  h3: ({ children }) => <h3 className="text-sm font-medium">{children}</h3>,
  h4: ({ children }) => <h4 className="text-sm font-medium">{children}</h4>,
  h5: ({ children }) => <h5 className="text-sm font-medium">{children}</h5>,
  h6: ({ children }) => <h6 className="text-sm font-medium">{children}</h6>,
  ul: ({ children }) => <ul className="flex list-disc flex-col gap-1 pl-5">{children}</ul>,
  ol: ({ children }) => <ol className="flex list-decimal flex-col gap-1 pl-5">{children}</ol>,
  li: ({ children }) => <li className="marker:text-muted-foreground">{children}</li>,
  strong: ({ children }) => <strong className="font-semibold">{children}</strong>,
  em: ({ children }) => <em className="italic">{children}</em>,
  a: ({ children, href }) => (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="font-medium underline underline-offset-4 wrap-anywhere"
    >
      {children}
    </a>
  ),
  code: ({ children, className }) => (
    <code className={cn("rounded bg-muted px-1 py-0.5 font-mono text-[0.85em]", className)}>{children}</code>
  ),
  pre: ({ children }) => (
    <pre className="overflow-x-auto rounded-md border bg-muted p-3 font-mono text-xs leading-5 [&_code]:bg-transparent [&_code]:p-0">
      {children}
    </pre>
  ),
  table: ({ children }) => (
    <div className="max-w-full overflow-x-auto rounded-md border">
      <table className="w-max min-w-full border-collapse text-xs">{children}</table>
    </div>
  ),
  th: ({ children }) => (
    <th className="border-b bg-muted px-2 py-1.5 text-left font-medium whitespace-nowrap">{children}</th>
  ),
  td: ({ children }) => <td className="border-b px-2 py-1.5 text-left whitespace-nowrap">{children}</td>,
  blockquote: ({ children }) => (
    <blockquote className="border-l-2 pl-3 text-muted-foreground">{children}</blockquote>
  ),
  // Never an <img>: text that echoes Slack or ticket content must not make the phone fetch from another host.
  img: ({ src, alt }) =>
    src && /^https?:\/\//i.test(src) ? (
      <a
        href={src}
        target="_blank"
        rel="noopener noreferrer"
        className="font-medium underline underline-offset-4 wrap-anywhere"
      >
        {alt || src}
      </a>
    ) : (
      <span>{alt}</span>
    ),
}

export function Markdown({ text, className }: { text: string; className?: string }) {
  return (
    <div className={cn("flex min-w-0 flex-col gap-3 text-sm leading-6 wrap-anywhere", className)}>
      <ReactMarkdown remarkPlugins={[remarkGfm]} components={COMPONENTS}>
        {text}
      </ReactMarkdown>
    </div>
  )
}
