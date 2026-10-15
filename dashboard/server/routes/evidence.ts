import type { Ctx } from "../app.ts";
import { HttpError } from "../http.ts";
import { readBrief } from "../readers/briefs.ts";
import { evidenceDir, kindOf } from "../readers/evidence.ts";
import { isDir, isPlainName, listFiles } from "../readers/files.ts";
import { readRelease } from "../readers/releases.ts";
import { readLedger } from "../readers/star.ts";
import type { Router } from "../router.ts";

export const fileUrl = (project: string, rel: string): string =>
  `/api/projects/${encodeURIComponent(project)}/file?path=${encodeURIComponent(rel)}`;

export function evidenceSummary(
  home: string,
  project: string,
  item: string,
): Record<string, unknown> {
  const brief = readBrief(home, project, item);
  const rel = readRelease(home, project, item);
  return {
    item,
    title: brief?.title ?? rel.title ?? null,
    pr: rel.pr,
    sha: rel.sha,
    mergedAt: rel.mergedAt,
    goAt: brief?.approved ?? null,
    files: listFiles(evidenceDir(home, item), `evidence/${item}`).length,
  };
}

export function evidenceRoutes(router: Router, ctx: Ctx): void {
  router.add("GET", "/api/projects/:p/evidence", async (req) => {
    const p = await ctx.registry.find(req.params["p"] ?? "");
    const merged = readLedger(p.home).filter(
      (r) => r.state === "done" && isDir(evidenceDir(p.home, r.item)),
    );
    const list = merged.map((r) => evidenceSummary(p.home, p.name, r.item));
    list.sort((a, b) =>
      String(b["mergedAt"] ?? "").localeCompare(String(a["mergedAt"] ?? "")),
    );
    return { json: list };
  });
  router.add("GET", "/api/projects/:p/evidence/:item", async (req) => {
    const p = await ctx.registry.find(req.params["p"] ?? "");
    const item = req.params["item"] ?? "";
    if (!isPlainName(item))
      throw new HttpError(400, `${item} is not an item name`);
    if (!isDir(evidenceDir(p.home, item)))
      throw new HttpError(404, `no evidence for ${item}`);
    const { files: _count, ...summary } = evidenceSummary(p.home, p.name, item);
    const files = listFiles(evidenceDir(p.home, item), `evidence/${item}`).map(
      (name) => ({
        name,
        kind: kindOf(name),
        url: fileUrl(p.name, `evidence/${item}/${name}`),
      }),
    );
    return { json: { ...summary, groups: [{ criterion: null, files }] } };
  });
}
