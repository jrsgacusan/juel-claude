import fs from "node:fs";
import path from "node:path";
import { parseQueue, parseStar } from "../../hooks/star.ts";
import { HttpError, whyOf } from "./http.ts";
import { listTerminals } from "./orca.ts";
import type { Project } from "./types.ts";

export type Entry = { name: string; repo: string; home: string };

const isEntry = (e: unknown): e is Entry => {
  const x = e as Record<string, unknown> | null;
  return (
    !!x &&
    typeof x === "object" &&
    typeof x["name"] === "string" &&
    !!x["name"] &&
    typeof x["repo"] === "string" &&
    typeof x["home"] === "string" &&
    !!x["home"]
  );
};

const live = (home: string): boolean =>
  fs.existsSync(path.join(home, "star.json"));

/** The STAR folders on this Mac (~/.juel/star-homes.json, written by star-home.sh register) and their state. */
export class Registry {
  dir: string;
  log: (line: string) => void;
  #cache: Project[] = [];
  #at = 0;
  #inflight: Promise<Project[]> | undefined;
  #said = new Set<string>();

  constructor(dir: string, log: (line: string) => void) {
    this.dir = dir;
    this.log = log;
  }

  /**
   * The registry's entries, one per project name. When two folders share a name, one whose star.json
   * still exists wins over one whose folder is gone (a moved project); the one left out is logged.
   */
  entries(): Entry[] {
    let data: unknown;
    try {
      data = JSON.parse(
        fs.readFileSync(path.join(this.dir, "star-homes.json"), "utf8"),
      );
    } catch (err) {
      if ((err as { code?: unknown }).code !== "ENOENT") {
        this.once(`star-homes.json unreadable: ${whyOf(err)}`);
      }
      return [];
    }
    if (!Array.isArray(data)) {
      this.once("star-homes.json is not a JSON list");
      return [];
    }
    const byName = new Map<string, Entry>();
    for (const e of data) {
      if (!isEntry(e)) {
        this.once(
          `star-homes.json: skipped an entry that is not {name, repo, home}: ${JSON.stringify(e).slice(0, 120)}`,
        );
        continue;
      }
      const entry = { name: e.name, repo: e.repo, home: e.home };
      const had = byName.get(e.name);
      if (!had) {
        byName.set(e.name, entry);
        continue;
      }
      const keep = !live(had.home) && live(entry.home) ? entry : had;
      const drop = keep === had ? entry : had;
      byName.set(e.name, keep);
      this.once(
        `star-homes.json: ${drop.home} skipped: ${keep.home} is project ${e.name} too`,
      );
    }
    return [...byName.values()];
  }

  /** Log a line once per distinct line, so a problem that lasts is not logged every 5 seconds. */
  once(line: string): void {
    if (this.#said.has(line)) return;
    this.#said.add(line);
    this.log(line);
  }

  /** Read the registry and Orca's terminal list again; callers at the same moment share one read. */
  refresh(): Promise<Project[]> {
    this.#inflight ??= (async () => {
      try {
        const terminals = await listTerminals();
        if (!terminals.ok) {
          this.once(
            `orca terminal list failed (${terminals.why}): every project shows stopped`,
          );
        }
        const listed = terminals.ok ? terminals.handles : null;
        this.#cache = this.entries().map((e) =>
          projectOf(e, listed, (line) => this.once(line)),
        );
        this.#at = Date.now();
        return this.#cache;
      } finally {
        this.#inflight = undefined;
      }
    })();
    return this.#inflight;
  }

  /** The projects, read again when the last read is older than 3 seconds. */
  async current(): Promise<Project[]> {
    if (Date.now() - this.#at > 3000) await this.refresh();
    return this.#cache;
  }

  /** A copy of the last read, for ModuleApi.projects(), which cannot wait. */
  snapshot(): Project[] {
    return this.#cache.map((p) => ({ ...p }));
  }

  async find(name: string): Promise<Project> {
    const p = (await this.current()).find((x) => x.name === name);
    if (!p) throw new HttpError(404, `no project ${name}`);
    return p;
  }
}

/** running: star.json names a terminal Orca lists (idle when the queue's Resume also says so); else stopped. */
function projectOf(
  e: Entry,
  listed: Set<string> | null,
  once: (line: string) => void,
): Project {
  let terminal: string | null = null;
  const starFile = path.join(e.home, "star.json");
  try {
    const text = fs.readFileSync(starFile, "utf8");
    const parsed = parseStar(text);
    if (parsed.ok) terminal = parsed.value.terminal;
    else once(`projects: ${e.name}: star.json: ${parsed.why}`);
  } catch (err) {
    if ((err as { code?: unknown }).code !== "ENOENT") {
      once(`projects: ${e.name}: star.json: ${whyOf(err)}`);
    }
  }
  let state: Project["state"] = "stopped";
  if (terminal && listed?.has(terminal)) {
    state = "running";
    try {
      const q = parseQueue(
        fs.readFileSync(path.join(e.home, "open-loops.md"), "utf8"),
      );
      if (q.ok && q.value.resume["state"] === "idle") state = "idle";
    } catch {
      // a queue that cannot be read says nothing about idle: running stays
    }
  }
  return { name: e.name, repo: e.repo, home: e.home, terminal, state };
}
