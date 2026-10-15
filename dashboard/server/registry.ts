import fs from "node:fs";
import path from "node:path";
import { parseQueue, parseStar } from "../../hooks/star.ts";
import { HttpError } from "./http.ts";
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

/** The STAR folders on this Mac (~/.juel/star-homes.json, written by star-home.sh register) and their state. */
export class Registry {
  dir: string;
  log: (line: string) => void;
  cache: Project[] = [];
  at = 0;
  complained = "";

  constructor(dir: string, log: (line: string) => void) {
    this.dir = dir;
    this.log = log;
  }

  /** The registry's entries, first one per name; a missing file is none, a broken one is none plus a log line. */
  entries(): Entry[] {
    let data: unknown;
    try {
      data = JSON.parse(
        fs.readFileSync(path.join(this.dir, "star-homes.json"), "utf8"),
      );
    } catch (err) {
      if ((err as { code?: unknown }).code !== "ENOENT")
        this.once(
          `star-homes.json unreadable: ${String((err as Error).message ?? err)}`,
        );
      return [];
    }
    if (!Array.isArray(data)) {
      this.once("star-homes.json is not a JSON list");
      return [];
    }
    const seen = new Set<string>();
    const out: Entry[] = [];
    for (const e of data) {
      if (!isEntry(e)) continue;
      if (seen.has(e.name)) continue;
      seen.add(e.name);
      out.push({ name: e.name, repo: e.repo, home: e.home });
    }
    return out;
  }

  once(line: string): void {
    if (this.complained === line) return;
    this.complained = line;
    this.log(line);
  }

  /** Read the registry and Orca's terminal list again. */
  async refresh(): Promise<Project[]> {
    const listed = await listTerminals();
    this.cache = this.entries().map((e) => projectOf(e, listed));
    this.at = Date.now();
    return this.cache;
  }

  /** The projects, read again when the last read is older than 3 seconds. */
  async current(): Promise<Project[]> {
    if (Date.now() - this.at > 3000) await this.refresh();
    return this.cache;
  }

  /** The last read, for ModuleApi.projects(), which cannot wait. */
  snapshot(): Project[] {
    return this.cache;
  }

  async find(name: string): Promise<Project> {
    const p = (await this.current()).find((x) => x.name === name);
    if (!p) throw new HttpError(404, `no project ${name}`);
    return p;
  }
}

/** running: star.json names a terminal Orca lists (idle when the queue's Resume also says so); else stopped. */
function projectOf(e: Entry, listed: Set<string> | null): Project {
  let terminal: string | null = null;
  try {
    const star = parseStar(
      fs.readFileSync(path.join(e.home, "star.json"), "utf8"),
    );
    if (star.ok) terminal = star.value.terminal;
  } catch {
    terminal = null;
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
