import fs from "node:fs";
import path from "node:path";
import { Unreadable, whyOf } from "../http.ts";

/** A file in a STAR folder. Any read error throws Unreadable, naming the file by its path in the folder. */
export function readText(home: string, rel: string): string {
  try {
    return fs.readFileSync(path.join(home, rel), "utf8");
  } catch (err) {
    throw new Unreadable(rel, whyOf(err));
  }
}

/** The same, but undefined when the file is not there. */
export function readOptional(home: string, rel: string): string | undefined {
  try {
    return fs.readFileSync(path.join(home, rel), "utf8");
  } catch (err) {
    if ((err as { code?: unknown }).code === "ENOENT") return undefined;
    throw new Unreadable(rel, whyOf(err));
  }
}

export function isDir(p: string): boolean {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

/** Every regular file under dir, as sorted paths relative to it. Symbolic links are left out. A missing dir is []. With rel (the folder's path in the STAR folder), a folder that cannot be read is an Unreadable naming it; without, it is skipped (the change poll). */
export function listFiles(dir: string, rel?: string): string[] {
  const out: string[] = [];
  const walk = (sub: string): void => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(path.join(dir, sub), { withFileTypes: true });
    } catch (err) {
      if ((err as { code?: unknown }).code === "ENOENT") return;
      if (rel) {
        const file = sub ? `${rel}/${sub}` : rel;
        throw new Unreadable(file, whyOf(err));
      }
      return;
    }
    for (const e of entries) {
      const child = sub ? `${sub}/${e.name}` : e.name;
      if (e.isDirectory()) walk(child);
      else if (e.isFile()) out.push(child);
    }
  };
  walk("");
  return out.sort();
}

/** A STAR item, draft or briefing name: letters, digits, dot, dash and underscore, not starting with a dot, and with no `..` in it. */
export const isPlainName = (name: string): boolean =>
  /^[A-Za-z0-9_-][A-Za-z0-9._-]*$/.test(name) && !name.includes("..");
