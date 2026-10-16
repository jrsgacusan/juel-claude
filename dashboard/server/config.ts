import crypto from "node:crypto";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";

export type DashboardConfig = { port: number; token: string; pid: number };
export const DEFAULT_PORT = 4767;
export function readConfig(dir: string): Partial<DashboardConfig> | undefined {
  try {
    const data = JSON.parse(
      fs.readFileSync(path.join(dir, "dashboard.json"), "utf8"),
    ) as unknown;
    return data && typeof data === "object" && !Array.isArray(data)
      ? (data as Partial<DashboardConfig>)
      : undefined;
  } catch {
    return undefined;
  }
}
export function writeConfig(dir: string, config: DashboardConfig): void {
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, "dashboard.json");
  const tmp = `${file}.tmp.${process.pid}`;
  // every other key (claudeConfigDir, slack) survives a start
  const next = { ...(readConfig(dir) ?? {}), ...config };
  fs.writeFileSync(tmp, `${JSON.stringify(next, null, 2)}\n`, {
    mode: 0o600,
  });
  fs.chmodSync(tmp, 0o600);
  fs.renameSync(tmp, file);
}
export function isAlive(pid: unknown): boolean {
  if (typeof pid !== "number" || !Number.isInteger(pid) || pid <= 0)
    return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return (err as { code?: unknown }).code === "EPERM";
  }
}
export const isToken = (t: unknown): t is string =>
  typeof t === "string" && /^[0-9a-f]{32}$/.test(t);
export const newToken = (): string => crypto.randomBytes(16).toString("hex");
export function isFree(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const s = net.createServer();
    s.once("error", () => resolve(false));
    s.listen(port, "127.0.0.1", () => s.close(() => resolve(true)));
  });
}
export const PORT_BUSY_EXIT = 3;
export const isPort = (p: unknown): p is number =>
  typeof p === "number" && Number.isInteger(p) && p > 0 && p < 65536;
export class PortBusy extends Error {
  port: number;
  constructor(port: number) {
    super(
      `port ${port} is busy: the dashboard keeps its port so tailscale serve keeps reaching it. Stop what listens on 127.0.0.1:${port} (lsof -nP -iTCP:${port} -sTCP:LISTEN), then start it again`,
    );
    this.port = port;
  }
}
export async function pickPort(recorded: unknown): Promise<number> {
  if (isPort(recorded)) {
    if (await isFree(recorded)) return recorded;
    throw new PortBusy(recorded);
  }
  for (let port = DEFAULT_PORT; port <= 65535; port += 1)
    if (await isFree(port)) return port;
  throw new Error(`no free port from ${DEFAULT_PORT} up`);
}
export async function probe(port: unknown, token: unknown): Promise<boolean> {
  if (typeof port !== "number" || !isToken(token)) return false;
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 3000);
  try {
    const r = await fetch(`http://127.0.0.1:${port}/api/events`, {
      headers: { "x-star-token": token },
      signal: ac.signal,
    });
    const type = r.headers.get("content-type") ?? "";
    return r.status === 200 && type.toLowerCase().includes("text/event-stream");
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
    ac.abort();
  }
}
export function takeLock(dir: string): boolean {
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, "dashboard.lock");
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      fs.writeFileSync(file, String(process.pid), { flag: "wx" });
      return true;
    } catch (err) {
      if ((err as { code?: unknown }).code !== "EEXIST") throw err;
      let holder = 0;
      try {
        holder = Number(fs.readFileSync(file, "utf8").trim());
      } catch {
        holder = 0;
      }
      if (isAlive(holder)) return false;
      fs.rmSync(file, { force: true });
    }
  }
  return false;
}
export function dropLock(dir: string): void {
  const file = path.join(dir, "dashboard.lock");
  try {
    if (fs.readFileSync(file, "utf8").trim() === String(process.pid))
      fs.rmSync(file, { force: true });
  } catch {}
}
