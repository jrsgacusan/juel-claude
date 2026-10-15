import fs from "node:fs";
import path from "node:path";
import { Unreadable, whyOf } from "../http.ts";

/** The owner's go, as typed: the grant file's text after its frontmatter, on one line. Null when the brief names no grant, or one outside this STAR folder, or the file is gone. */
export function goWords(home: string, grant: string | null): string | null {
  if (!grant) return null;
  const file = path.resolve(home, grant);
  let real: string;
  let root: string;
  try {
    real = fs.realpathSync(file);
    root = fs.realpathSync(home);
  } catch {
    return null;
  }
  if (!real.startsWith(root + path.sep)) return null;
  let text: string;
  try {
    text = fs.readFileSync(real, "utf8");
  } catch (err) {
    throw new Unreadable(path.relative(root, real), whyOf(err));
  }
  const lines = text.split("\n");
  let body = 0;
  if ((lines[0] ?? "").trim() === "---") {
    const end = lines.findIndex((l, i) => i > 0 && l.trim() === "---");
    body = end < 0 ? lines.length : end + 1;
  }
  const words = lines.slice(body).join(" ").replace(/\s+/g, " ").trim();
  return words || null;
}
