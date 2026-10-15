// Pure command judging for the STAR guards: no `$` here, so every rule is a unit test.
// A best-effort shell reader, not a shell: it knows quotes, backslashes, ; && || | & newlines,
// ( ), $( ), backticks, heredocs, comments, redirections, and `sh -c` / `bash -c` / `eval`
// strings. What it cannot see (a variable that holds a path, a script that reads a file) it lets
// through; the prose rule in the session hook still covers that.

export type Word = { text: string; start: number; end: number; op?: string }
export type Scan = { segments: Word[][]; literal: boolean[] }

/** The index of the `)` that closes the `(` at `open`, or `to` when none does. */
function closing(src: string, open: number, to: number): number {
  let depth = 0
  for (let k = open; k < to; k += 1) {
    const c = src[k]
    if (c === '\\') { k += 1; continue }
    if (c === "'") { const q = src.indexOf("'", k + 1); k = q < 0 ? to : q; continue }
    if (c === '"') {
      let q = k + 1
      while (q < to && src[q] !== '"') q += src[q] === '\\' ? 2 : 1
      k = q
      continue
    }
    if (c === '(') depth += 1
    if (c === ')') { depth -= 1; if (depth === 0) return k }
  }
  return to
}

function scanInto(src: string, from: number, to: number, out: Scan, depth: number): void {
  let seg: Word[] = []
  let text = ''
  let start = -1
  let quote = ''
  let i = from
  let wantDelim: boolean | undefined
  const heredocs: { delim: string; strip: boolean }[] = []
  const endWord = (): void => {
    if (start < 0) return
    seg.push({ text, start, end: i })
    if (wantDelim !== undefined) { heredocs.push({ delim: text, strip: wantDelim }); wantDelim = undefined }
    text = ''
    start = -1
  }
  const endSeg = (): void => {
    endWord()
    if (seg.length) out.segments.push(seg)
    seg = []
  }
  const begin = (): void => { if (start < 0) start = i }
  const substitute = (open: number): void => {
    // $( ... ) or ` ... `: its commands are segments of their own; the word keeps a placeholder
    const isTick = src[open] === '`'
    let close: number
    if (isTick) {
      close = open + 1
      while (close < to && src[close] !== '`') close += src[close] === '\\' ? 2 : 1
    } else {
      close = closing(src, open + 1, to)
    }
    const inner = isTick ? open + 1 : open + 2
    if (depth < 4) scanInto(src, inner, Math.min(close, to), out, depth + 1)
    begin()
    text += '\u0000'
    i = close + 1
  }
  while (i < to) {
    const c = src[i] ?? ''
    if (quote === "'") {
      if (c === "'") quote = ''
      else { out.literal[i] = true; text += c }
      i += 1
      continue
    }
    if (c === '\\') {
      begin()
      if (i + 1 < to) { out.literal[i + 1] = true; text += src[i + 1] ?? '' }
      i += 2
      continue
    }
    if (quote === '"') {
      if (c === '"') { quote = ''; i += 1; continue }
      if (c === '$' && src[i + 1] === '(') { substitute(i); continue }
      if (c === '`') { substitute(i); continue }
      text += c
      i += 1
      continue
    }
    if (c === "'" || c === '"') { begin(); quote = c; i += 1; continue }
    if (c === '$' && src[i + 1] === '(') { substitute(i); continue }
    if (c === '`') { substitute(i); continue }
    if (c === '#' && start < 0) { while (i < to && src[i] !== '\n') i += 1; continue }
    if (c === ' ' || c === '\t') { endWord(); i += 1; continue }
    if (c === '\n') {
      endSeg()
      i += 1
      for (const doc of heredocs.splice(0)) {
        while (i < to) {
          const nl = src.indexOf('\n', i)
          const lineEnd = nl < 0 || nl > to ? to : nl
          const line = src.slice(i, lineEnd)
          i = lineEnd + 1
          if ((doc.strip ? line.replace(/^\t+/, '') : line) === doc.delim) break
        }
      }
      continue
    }
    if (c === ';' || c === '&' || c === '|' || c === '(' || c === ')') {
      endSeg()
      i += c === src[i + 1] || (c === '|' && src[i + 1] === '&') ? 2 : 1
      continue
    }
    if (c === '<' || c === '>') {
      endWord()
      const op = /^(<<<|<<-|<<|<&|<>|<|>>|>&|>\||>)/.exec(src.slice(i, i + 3))?.[0] ?? c
      seg.push({ text: op, start: i, end: i + op.length, op })
      if (op === '<<' || op === '<<-') wantDelim = op === '<<-'
      i += op.length
      continue
    }
    begin()
    text += c
    i += 1
  }
  endSeg()
}

export function scan(src: string): Scan {
  const out: Scan = { segments: [], literal: new Array<boolean>(src.length).fill(false) }
  scanInto(src, 0, src.length, out, 0)
  return out
}

const ASSIGN = /^[A-Za-z_][A-Za-z0-9_]*=/
const WRAPPERS = new Set(['do', 'then', 'else', 'elif', 'if', 'while', 'until', '!', '{', '}', 'time', 'command',
  'builtin', 'exec', 'nohup', 'sudo', 'env', 'nice', 'timeout', 'stdbuf', 'caffeinate', 'xargs'])
const VALUE_FLAGS = new Set(['-u', '-g', '-n', '-C', '-o', '-s', '-k', '-I', '-L', '-P'])

const base = (word: string): string => word.slice(word.lastIndexOf('/') + 1)

export type Command = {
  /** The command word's basename; '' for a segment that is only redirections and keywords (`done < file`). */
  name: string
  /** Its arguments, redirections and their targets left out. */
  args: Word[]
  /** The files it reads from with `<`, wherever they stand in the segment. */
  inputs: Word[]
}

/** The command a segment runs, past assignments, redirections and wrappers, and its arguments. */
export function commandOf(seg: readonly Word[]): Command {
  const inputs: Word[] = []
  const words: Word[] = []
  for (let k = 0; k < seg.length; k += 1) {
    const w = seg[k]
    if (!w) continue
    if (w.op) {
      const target = seg[k + 1]
      if (w.op === '<' && target) inputs.push(target)
      k += 1
      continue
    }
    words.push(w)
  }
  let k = 0
  let isWrapped = false
  while (k < words.length) {
    const w = words[k]
    if (!w) break
    if (ASSIGN.test(w.text)) { k += 1; continue }
    if (isWrapped && w.text.startsWith('-')) { k += VALUE_FLAGS.has(w.text) ? 2 : 1; continue }
    if (isWrapped && /^\d+[smhd]?$/.test(w.text)) { k += 1; continue }
    if (WRAPPERS.has(w.text) || w.text === 'done') { isWrapped = true; k += 1; continue }
    return { name: base(w.text), args: words.slice(k + 1), inputs }
  }
  return { name: '', args: [], inputs }
}

const SHELLS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh'])
const INTERPRETERS = new Set(['python', 'python3', 'node', 'ruby', 'perl', 'osascript', 'deno', 'bun'])

/** Code a segment hands to another shell or interpreter as a string: `sh -c '...'`, `eval ...`, `python3 -c '...'`. */
function inlineCode(name: string, args: readonly Word[]): { code: string; isShell: boolean } | undefined {
  if (name === 'eval') return { code: args.map(a => a.text).join(' '), isShell: true }
  const at = args.findIndex(a => a.text === '-c' || a.text === '-e' || /^-[a-zA-Z]*c$/.test(a.text))
  const code = at >= 0 ? args[at + 1]?.text : undefined
  if (code === undefined) return undefined
  if (SHELLS.has(name)) return { code, isShell: true }
  if (INTERPRETERS.has(name)) return { code, isShell: false }
  return undefined
}

// --- the merge guard ---------------------------------------------------------------------------

const MERGE_REST = /(^|\/)repos\/[^/\s]+\/[^/\s]+\/pulls\/\d+\/merge\b/
const MERGE_GRAPHQL = /\b(mergePullRequest|enablePullRequestAutoMerge)\b/

function mergeCall(name: string, args: readonly Word[]): string | undefined {
  const texts = args.map(a => a.text)
  if (name === 'gh') {
    const positional: string[] = []
    for (let k = 0; k < texts.length; k += 1) {
      const t = texts[k] ?? ''
      if (t === '-R' || t === '--repo' || t === '--hostname') { k += 1; continue }
      if (!t.startsWith('-')) positional.push(t)
    }
    if (positional[0] === 'pr' && positional[1] === 'merge' && !texts.includes('--disable-auto')) return 'gh pr merge'
    if (positional[0] === 'api' && texts.some(t => MERGE_REST.test(t) || MERGE_GRAPHQL.test(t))) return 'gh api (the merge endpoint)'
  }
  if (['curl', 'wget', 'http', 'https', 'xh'].includes(name) && texts.some(t => MERGE_REST.test(t) || MERGE_GRAPHQL.test(t))) {
    return `${name} (the merge endpoint)`
  }
  return undefined
}

// --- the read guard ----------------------------------------------------------------------------

export type Protect = {
  /** The STAR folder, as star-home.sh printed it (and its realpath when that differs). */
  homes: readonly string[]
  /** docsRoot relative to the main checkout, e.g. docs/superpowers: a worktree's evidence is <worktree>/<docsRel>/evidence/. */
  docsRel: string
  /** Where a relative path is taken from. */
  cwd: string
}

function normal(path: string, cwd: string): string {
  const abs = path.startsWith('/') ? path : `${cwd.replace(/\/$/, '')}/${path}`
  const parts: string[] = []
  for (const p of abs.split('/')) {
    if (!p || p === '.') continue
    if (p === '..') parts.pop()
    else parts.push(p)
  }
  return `/${parts.join('/')}`
}

/** Why the coordinator may not read `path` into its session, or undefined when it may. */
export function protectedWhy(path: string, p: Protect): string | undefined {
  if (!path || path.includes('\u0000')) return undefined
  const norm = normal(path, p.cwd)
  for (const home of p.homes) {
    if (norm !== home && !norm.startsWith(`${home}/`)) continue
    const rel = norm.slice(home.length + 1)
    const top = rel.split('/')[0] ?? ''
    if (top === 'reviews') return 'a review file'
    if (top === 'evidence') return 'evidence'
    if (top === 'reports') return "a report (the owner reads it; the queue item carries its path)"
    if (/\.log$/.test(rel)) return 'a log file'
    return undefined
  }
  if (p.docsRel && (norm.includes(`/${p.docsRel}/evidence/`) || norm.endsWith(`/${p.docsRel}/evidence`))) return 'evidence'
  return undefined
}

// Commands that put a file's content into the session. grep and kin only when they print lines.
const READERS = new Set(['cat', 'head', 'tail', 'less', 'more', 'bat', 'batcat', 'nl', 'tac', 'view', 'strings', 'xxd',
  'hexdump', 'od', 'awk', 'gawk', 'jq', 'yq', 'sed', 'diff', 'grep', 'egrep', 'fgrep', 'rg', 'ag', 'column', 'fold', 'cut', 'sort', 'uniq', 'paste'])
const GREPS = new Set(['grep', 'egrep', 'fgrep', 'rg', 'ag'])
const COUNT_ONLY = /^(-[a-zA-Z]*[cqlL][a-zA-Z]*|--count|--quiet|--silent|--files-with-matches|--files-without-match)$/

function readsContent(name: string, args: readonly Word[]): boolean {
  if (!READERS.has(name)) return false
  if (GREPS.has(name) && args.some(a => COUNT_ONLY.test(a.text))) return false
  if (name === 'sed' && args.some(a => /^(-[a-zA-Z]*i|--in-place)/.test(a.text))) return false
  return true
}

// --- the verdict -------------------------------------------------------------------------------

export type Verdict =
  | { kind: 'merge'; how: string }
  | { kind: 'read'; path: string; why: string }

/** What a Bash or Monitor command would do that the coordinator may not, or undefined. */
export function judge(command: string, p: Protect | undefined, depth = 0): Verdict | undefined {
  for (const seg of scan(command).segments) {
    const cmd = commandOf(seg)
    const how = mergeCall(cmd.name, cmd.args)
    if (how) return { kind: 'merge', how }
    const inline = inlineCode(cmd.name, cmd.args)
    if (inline && depth < 3) {
      if (inline.isShell) {
        const nested = judge(inline.code, p, depth + 1)
        if (nested) return nested
      } else if (p) {
        for (const m of inline.code.matchAll(/\/[^\s'"`)]+/g)) {
          const why = protectedWhy(m[0], p)
          if (why) return { kind: 'read', path: m[0], why }
        }
      }
    }
    if (p && readsContent(cmd.name, cmd.args)) {
      for (const a of cmd.args) {
        if (a.text.startsWith('-')) continue
        const why = protectedWhy(a.text, p)
        if (why) return { kind: 'read', path: a.text, why }
      }
    }
    if (p) {
      // `cat < file`, `done < file`: a redirected input is read into the session, unless it is
      // only counted (wc, grep -c / -q)
      const isCounting = cmd.name === 'wc' || (GREPS.has(cmd.name) && cmd.args.some(a => COUNT_ONLY.test(a.text)))
      for (const target of isCounting ? [] : cmd.inputs) {
        const why = protectedWhy(target.text, p)
        if (why) return { kind: 'read', path: target.text, why }
      }
    }
  }
  return undefined
}

// --- #114: rm / rmdir on a bare variable ---------------------------------------------------------

const RM = new Set(['rm', 'rmdir', 'unlink'])
const VAR = /\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))/g

/**
 * The command with every bare `$NAME` / `${NAME}` in an rm, rmdir or unlink argument written as
 * `${NAME:?}`, or undefined when there is none. A quoted-literal `$` ('...' or \$) is left, as
 * are `${NAME:-x}` and other expansions that already say what an empty value does, and code
 * inside an `sh -c` string (rewriting it would need re-quoting).
 */
export function guardRmVars(command: string): string | undefined {
  const { segments, literal } = scan(command)
  const edits: { at: number; end: number; name: string }[] = []
  for (const seg of segments) {
    const cmd = commandOf(seg)
    if (!RM.has(cmd.name)) continue
    for (const a of cmd.args) {
      const raw = command.slice(a.start, a.end)
      for (const m of raw.matchAll(VAR)) {
        const at = a.start + (m.index ?? 0)
        if (literal[at] || command[at - 1] === '\\') continue
        edits.push({ at, end: at + m[0].length, name: m[1] ?? m[2] ?? '' })
      }
    }
  }
  if (!edits.length) return undefined
  let out = command
  for (const e of edits.sort((x, y) => y.at - x.at)) out = `${out.slice(0, e.at)}\${${e.name}:?}${out.slice(e.end)}`
  return out
}
