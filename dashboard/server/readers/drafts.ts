import fs from "node:fs";
import path from "node:path";
import { Unreadable, whyOf } from "../http.ts";

export type SlackDraft = { name: string; to: string; reply: string };

/**
 * drafts/*-slack-*.md: the first line (`to: slack <channelId> <threadTs or ts>`) and the reply
 * after it. A draft that cannot be read is an Unreadable.
 */
export function slackDrafts(home: string): SlackDraft[] {
  let names: string[];
  try {
    names = fs
      .readdirSync(path.join(home, "drafts"))
      .filter((n) => /-slack-.+\.md$/.test(n))
      .sort();
  } catch (err) {
    if ((err as { code?: unknown }).code === "ENOENT") return [];
    throw new Unreadable("drafts", whyOf(err));
  }
  const out: SlackDraft[] = [];
  for (const name of names) {
    let text: string;
    try {
      text = fs.readFileSync(path.join(home, "drafts", name), "utf8");
    } catch (err) {
      throw new Unreadable(`drafts/${name}`, whyOf(err));
    }
    const at = text.indexOf("\n");
    out.push({
      name,
      to: (at < 0 ? text : text.slice(0, at)).trim(),
      reply: at < 0 ? "" : text.slice(at + 1).trim(),
    });
  }
  return out;
}
