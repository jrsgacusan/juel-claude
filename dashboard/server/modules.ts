import fs from "node:fs";
import path from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { whyOf } from "./http.ts";
import { pathToFileURL } from "node:url";
import type { Handler, Method, Router } from "./router.ts";
import type { ModuleApi } from "./types.ts";

const METHODS = new Set(["GET", "POST", "PUT", "DELETE"]);

/**
 * Import every <dir>/<name>/index.ts, in name order, and call its register(api). A module's routes
 * count only once register has returned without throwing; a module that throws, has no register, or
 * whose register does not return within registerMs, is logged and none of its routes are added
 * (anything it already started keeps running).
 */
export async function loadModules(
  dir: string,
  router: Router,
  base: Pick<ModuleApi, "emit" | "projects" | "nudge">,
  log: (line: string) => void,
  registerMs = 10_000,
): Promise<string[]> {
  let names: string[];
  try {
    names = fs
      .readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();
  } catch (err) {
    if ((err as { code?: unknown }).code !== "ENOENT") {
      log(`modules: ${dir}: ${whyOf(err)}`);
    }
    return [];
  }
  const loaded: string[] = [];
  for (const name of names) {
    log(`module ${name} loading`);
    const file = path.join(dir, name, "index.ts");
    if (!fs.existsSync(file)) {
      log(`module ${name} skipped: no index.ts`);
      continue;
    }
    const pending: [Method, string, Handler][] = [];
    let state: "loading" | "live" | "dead" = "loading";
    const api: ModuleApi = {
      route(method, routePath, handler) {
        if (!METHODS.has(method) || !routePath.startsWith("/api/")) {
          log(
            `[${name}] route ${method} ${routePath} ignored: a module route is GET, POST, PUT or DELETE under /api/`,
          );
          return;
        }
        if (state === "live") router.add(method, routePath, handler);
        else if (state === "loading")
          pending.push([method, routePath, handler]);
      },
      emit: (e) => base.emit(e),
      projects: () => base.projects(),
      nudge: (project) => base.nudge(project),
      log: (line) => log(`[${name}] ${line}`),
    };
    try {
      const mod = (await import(pathToFileURL(file).href)) as {
        register?: unknown;
      };
      if (typeof mod.register !== "function")
        throw new Error("index.ts exports no register(api)");
      const ac = new AbortController();
      const limit = sleep(registerMs, undefined, {
        signal: ac.signal,
        ref: false,
      }).then(
        () => {
          throw new Error(`register did not return in ${registerMs / 1000}s`);
        },
        () => undefined,
      );
      try {
        await Promise.race([
          Promise.resolve().then(() =>
            (mod.register as (api: ModuleApi) => unknown)(api),
          ),
          limit,
        ]);
      } finally {
        ac.abort();
      }
      for (const [m, p, h] of pending) router.add(m, p, h);
      state = "live";
      loaded.push(name);
      log(`module ${name} loaded`);
    } catch (err) {
      state = "dead";
      log(
        `module ${name} skipped: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }
  return loaded;
}
