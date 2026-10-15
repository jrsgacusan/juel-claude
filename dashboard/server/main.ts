// The STAR dashboard: one server per Mac for every project's STAR folder.
//   node dashboard/server/main.ts
import { setTimeout as sleep } from "node:timers/promises";
import { startApp } from "./app.ts";
import type { App } from "./app.ts";
import {
  dropLock,
  isAlive,
  isToken,
  newToken,
  pickPort,
  probe,
  readConfig,
  takeLock,
  writeConfig,
} from "./config.ts";
import { makeLog } from "./log.ts";
import { juelDir } from "./paths.ts";

const dir = juelDir();
const log = makeLog(dir);
const urlOf = (port: number, token: string): string =>
  `http://127.0.0.1:${port}/?t=${token}`;
async function running(): Promise<boolean> {
  const c = readConfig(dir);
  if (
    !c ||
    c.pid === process.pid ||
    !isAlive(c.pid) ||
    !(await probe(c.port, c.token))
  )
    return false;
  console.log(
    `STAR dashboard already runs (pid ${String(c.pid)}): ${urlOf(c.port as number, c.token as string)}`,
  );
  return true;
}
async function main(): Promise<number> {
  if (await running()) return 0;
  let locked = takeLock(dir);
  for (let waited = 0; !locked && waited < 5000; waited += 250) {
    await sleep(250);
    if (await running()) return 0;
    locked = takeLock(dir);
  }
  if (!locked) {
    console.error(`star dashboard: another start holds ${dir}/dashboard.lock`);
    return 1;
  }
  let app: App | undefined;
  try {
    if (await running()) return 0;
    const recorded = readConfig(dir);
    const token = isToken(recorded?.token) ? recorded.token : newToken();
    let port = await pickPort(recorded?.port);
    for (let tries = 0; !app; tries += 1) {
      try {
        app = await startApp({ port, token, juelDir: dir, log });
      } catch (err) {
        if ((err as { code?: unknown }).code !== "EADDRINUSE" || tries >= 5)
          throw err;
        port = await pickPort(undefined);
      }
    }
    writeConfig(dir, { port: app.port, token, pid: process.pid });
    log(`started on 127.0.0.1:${app.port} (pid ${process.pid})`);
    console.log(`STAR dashboard: ${urlOf(app.port, token)}`);
  } finally {
    dropLock(dir);
  }
  const started = app;
  const shut = (signal: string): void => {
    log(`stopping on ${signal}`);
    void started.close().then(() => process.exit(0));
  };
  process.once("SIGTERM", () => shut("SIGTERM"));
  process.once("SIGINT", () => shut("SIGINT"));
  return -1;
}
const code = await main().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err);
  log(`could not start: ${msg}`);
  console.error(`star dashboard: could not start: ${msg}`);
  return 1;
});
if (code >= 0) process.exit(code);
