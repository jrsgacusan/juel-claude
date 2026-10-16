import fs from "node:fs";
import path from "node:path";
import type { Ctx } from "../app.ts";
import { HttpError, Unreadable, whyOf } from "../http.ts";
import type { Router } from "../router.ts";
import { typeOf } from "../static.ts";

const TEXTUAL = new Set([".html", ".htm", ".xml"]);

export function fileRoutes(router: Router, ctx: Ctx): void {
  router.add("GET", "/api/projects/:p/file", async (req) => {
    const p = await ctx.registry.find(req.params["p"] ?? "");
    const rel = req.query.get("path") ?? "";
    if (
      !rel ||
      rel.includes("\0") ||
      path.isAbsolute(rel) ||
      rel.split(/[\\/]/).includes("..")
    )
      throw new HttpError(
        400,
        "path must be a relative path inside the STAR folder",
      );
    const root = fs.realpathSync(p.home);
    let real: string;
    try {
      real = fs.realpathSync(path.join(p.home, rel));
    } catch (err) {
      if ((err as { code?: unknown }).code === "ENOENT")
        throw new HttpError(404, `no file ${rel}`);
      throw new Unreadable(rel, whyOf(err));
    }
    if (!real.startsWith(root + path.sep))
      throw new HttpError(400, `${rel} leaves the STAR folder`);
    const stat = fs.statSync(real);
    if (!stat.isFile()) throw new HttpError(400, `${rel} is not a file`);
    try {
      fs.accessSync(real, fs.constants.R_OK);
    } catch (err) {
      throw new Unreadable(rel, whyOf(err));
    }
    const type = TEXTUAL.has(path.extname(real).toLowerCase())
      ? "text/plain; charset=utf-8"
      : typeOf(real);
    return { file: { path: real, rel, size: stat.size, type } };
  });
}
