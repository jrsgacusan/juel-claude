import fs from "node:fs";
import type { IncomingMessage, ServerResponse } from "node:http";
import path from "node:path";
import { listFiles } from "./readers/files.ts";
import type { Entry } from "./registry.ts";

export type DashEvent = {
  type: string;
  project?: string;
  [k: string]: unknown;
};

/** GET /api/events: Server-Sent Events to every open page. */
export class Hub {
  clients = new Set<ServerResponse>();
  timer: ReturnType<typeof setInterval>;

  constructor() {
    // a comment line every 25 s keeps idle connections open through anything that times them out
    this.timer = setInterval(() => {
      for (const c of this.clients) c.write(": ping\n\n");
    }, 25_000);
    this.timer.unref();
  }

  attach(req: IncomingMessage, res: ServerResponse): void {
    res.writeHead(200, {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-store",
      connection: "keep-alive",
    });
    res.write(": connected\n\n");
    this.clients.add(res);
    const drop = (): void => {
      this.clients.delete(res);
    };
    req.on("close", drop);
    res.on("close", drop);
    res.on("error", drop);
  }

  emit(event: DashEvent): void {
    const line = `data: ${JSON.stringify(event)}\n\n`;
    for (const c of this.clients) {
      if (c.writableEnded || c.destroyed) this.clients.delete(c);
      else c.write(line);
    }
  }

  size(): number {
    return this.clients.size;
  }

  close(): void {
    clearInterval(this.timer);
    for (const c of this.clients) c.end();
    this.clients.clear();
  }
}

export const WHATS = [
  "loops",
  "ledger",
  "progress",
  "evidence",
  "drafts",
  "slack",
  "briefings",
] as const;
const FOLDERS: Readonly<Record<string, string>> = {
  progress: "progress",
  evidence: "evidence",
  drafts: "drafts",
  slack: "slack",
  briefings: "briefings",
};

/** What a changed path (relative to the STAR folder) is about; a path fs.watch did not name could be any of them. */
export function whatOf(rel: string | null): string[] {
  if (rel === null) return [...WHATS];
  const parts = rel.split(/[\\/]/).filter(Boolean);
  const name = parts[parts.length - 1] ?? "";
  if (/\.lock$|\.tmp\.\d+$|\.seq$/.test(name)) return [];
  if (parts.length === 1) {
    if (name === "open-loops.md") return ["loops"];
    if (name === "ledger.md") return ["ledger"];
  }
  const folder = FOLDERS[parts[0] ?? ""];
  return folder ? [folder] : [];
}

const stamp = (file: string): string => {
  try {
    const s = fs.statSync(file);
    return `${s.mtimeMs}:${s.size}`;
  } catch {
    return "-";
  }
};

/** One string per `what`, changing whenever its files change: what the 5-second poll compares. */
export function signatures(home: string): Record<string, string> {
  const tree = (rel: string): string =>
    listFiles(path.join(home, rel))
      .map((f) => `${f}=${stamp(path.join(home, rel, f))}`)
      .join("|");
  return {
    loops: stamp(path.join(home, "open-loops.md")),
    ledger: stamp(path.join(home, "ledger.md")),
    progress: tree("progress"),
    evidence: tree("evidence"),
    drafts: tree("drafts"),
    slack: tree("slack"),
    briefings: tree("briefings"),
  };
}

export type WatchFn = (
  dir: string,
  opts: { recursive: boolean },
  listener: (event: string, filename: string | Buffer | null) => void,
) => fs.FSWatcher;

/**
 * One recursive fs.watch per registered STAR folder, pushing {type: 'change', project, what} at most
 * once per 150 ms per (project, what). A watch that throws or errors polls that folder every pollMs
 * instead. The registry is read again every rescanMs, so a folder registered later is watched too.
 */
export function watchHomes(
  entries: () => Entry[],
  emit: (e: DashEvent) => void,
  log: (line: string) => void,
  opts: { watch?: WatchFn; pollMs: number; rescanMs?: number },
): { close(): void } {
  const watch = opts.watch ?? (fs.watch as unknown as WatchFn);
  const stops = new Map<string, () => void>();
  const pending = new Map<string, ReturnType<typeof setTimeout>>();
  let closed = false;

  const fire = (project: string, what: string): void => {
    const key = `${project}\u0000${what}`;
    if (closed || pending.has(key)) return;
    pending.set(
      key,
      setTimeout(() => {
        pending.delete(key);
        if (!closed) emit({ type: "change", project, what });
      }, 150),
    );
  };

  const poll = (e: Entry): (() => void) => {
    let last = signatures(e.home);
    const t = setInterval(() => {
      const now = signatures(e.home);
      for (const what of WHATS)
        if (now[what] !== last[what]) fire(e.name, what);
      last = now;
    }, opts.pollMs);
    t.unref();
    return () => clearInterval(t);
  };

  const fallBack = (e: Entry, why: string): void => {
    log(
      `watch ${e.name} failed (${why}): polling every ${opts.pollMs / 1000}s`,
    );
    stops.set(e.home, poll(e));
  };

  const add = (e: Entry): void => {
    if (stops.has(e.home)) return;
    try {
      const w = watch(e.home, { recursive: true }, (_event, filename) => {
        for (const what of whatOf(
          filename === null || filename === undefined ? null : String(filename),
        ))
          fire(e.name, what);
      });
      w.on("error", (err: Error) => {
        w.close();
        stops.delete(e.home);
        if (!closed) fallBack(e, err.message);
      });
      stops.set(e.home, () => w.close());
    } catch (err) {
      fallBack(e, err instanceof Error ? err.message : String(err));
    }
  };

  const sync = (): void => {
    const now = entries();
    const homes = new Set(now.map((e) => e.home));
    for (const [home, stop] of stops) {
      if (!homes.has(home)) {
        stop();
        stops.delete(home);
      }
    }
    for (const e of now) add(e);
  };

  sync();
  const rescan = setInterval(sync, opts.rescanMs ?? 5000);
  rescan.unref();
  return {
    close(): void {
      closed = true;
      clearInterval(rescan);
      for (const stop of stops.values()) stop();
      stops.clear();
      for (const t of pending.values()) clearTimeout(t);
      pending.clear();
    },
  };
}
