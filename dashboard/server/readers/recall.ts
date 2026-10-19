import { execFile } from "node:child_process";
import { recallSh } from "../paths.ts";

export type RecallHit = {
  kind: string;
  ref: string;
  item: string;
  status: string;
  title: string;
  excerpt: string;
};

const TIMEOUT_MS = 5000;

/** What `recall.sh --json` finds for the words in q. Any failure, timeout or bad line adds nothing. */
export async function recall(home: string, q: string): Promise<RecallHit[]> {
  const words = q.split(/\s+/).filter(Boolean);
  if (!words.length) return [];
  const stdout = await new Promise<string>((resolve) => {
    let done = false;
    const finish = (s: string): void => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve(s);
    };
    const child = execFile(
      "sh",
      [recallSh(), "--home", home, "--json", "--limit", "20", ...words],
      { timeout: TIMEOUT_MS },
      (err, out) => finish(err ? "" : String(out)),
    );
    // A killed script can leave a grandchild holding the pipe open: answer anyway.
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      finish("");
    }, TIMEOUT_MS + 500);
  });
  const hits: RecallHit[] = [];
  for (const line of stdout.split("\n")) {
    if (!line.trim()) continue;
    try {
      const o = JSON.parse(line) as Record<string, unknown>;
      if (!o || typeof o !== "object") continue;
      const s = (k: string): string =>
        typeof o[k] === "string" ? (o[k] as string) : "";
      hits.push({
        kind: s("kind"),
        ref: s("ref"),
        item: s("item"),
        status: s("status"),
        title: s("title"),
        excerpt: s("excerpt"),
      });
    } catch {
      // not JSON: drop the line
    }
  }
  return hits;
}
