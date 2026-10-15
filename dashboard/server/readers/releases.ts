import fs from "node:fs";
import path from "node:path";
import { Unreadable, whyOf } from "../http.ts";

export type Release = {
  title: string | null;
  pr: string | null;
  sha: string | null;
  mergedAt: string | null;
  fields: Record<string, string>;
};

const slugOf = (item: string): string =>
  item
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "item";

/**
 * The newest release record (release-record.sh) for this item: the PR, the merge commit, when it
 * merged, and every `- <Label>: <value>` line. A record that cannot be read is an Unreadable.
 */
export function readRelease(
  home: string,
  project: string,
  item: string,
): Release {
  const none: Release = {
    title: null,
    pr: null,
    sha: null,
    mergedAt: null,
    fields: {},
  };
  let names: string[];
  try {
    names = fs.readdirSync(path.join(home, "releases"));
  } catch (err) {
    if ((err as { code?: unknown }).code === "ENOENT") return none;
    throw new Unreadable("releases", whyOf(err));
  }
  const slug = slugOf(item);
  let best: Release | undefined;
  for (const name of names) {
    if (!name.endsWith(".md") || !name.includes(`-${project}-${slug}`))
      continue;
    let text: string;
    try {
      text = fs.readFileSync(path.join(home, "releases", name), "utf8");
    } catch (err) {
      throw new Unreadable(`releases/${name}`, whyOf(err));
    }
    const lines = text.split("\n");
    const head = /^# (.*?) · (.*?) · (.*)$/.exec(lines[0] ?? "");
    if (!head || head[1] !== project || head[2] !== item) continue;
    const fields: Record<string, string> = {};
    for (const line of lines) {
      const field = /^- ([^:]+):\s*(.*)$/.exec(line);
      if (field) fields[field[1] ?? ""] = (field[2] ?? "").trim();
    }
    const rec: Release = {
      title: (head[3] ?? "").trim() || null,
      pr: null,
      sha: null,
      mergedAt: null,
      fields,
    };
    const pr = /^- PR: (\S+)/m.exec(text);
    if (pr) rec.pr = pr[1] ?? null;
    const merged = /^- Merged: (\S+) by .*?, merge commit (\S+)/m.exec(text);
    if (merged) {
      rec.mergedAt = merged[1] ?? null;
      rec.sha = merged[2] && merged[2] !== "unknown" ? merged[2] : null;
    }
    if (!best || (rec.mergedAt ?? "") > (best.mergedAt ?? "")) best = rec;
  }
  return best ?? none;
}
