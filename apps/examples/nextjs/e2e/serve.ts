/**
 * One production build, then two `next start` servers on it: `port` as is,
 * and `latencyPort` with `BS_FETCH_DELAY_MS`, where every Supabase request
 * from the server waits `fetchDelayMs`. Playwright waits for the second,
 * which starts after the first answers.
 */
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";

import { baseURL, fetchDelayMs, latencyPort, port } from "./server.ts";

execFileSync("next", ["build"], { stdio: "inherit" });

const servers: ChildProcess[] = [];

function start(
  onPort: number,
  env: Readonly<Record<string, string>> = {},
): void {
  servers.push(
    spawn("next", ["start", "-p", String(onPort)], {
      stdio: "inherit",
      env: { ...process.env, ...env },
    }),
  );
}

async function ready(url: string): Promise<void> {
  for (;;) {
    try {
      if ((await fetch(url)).ok) return;
    } catch {
      // Not listening yet.
    }
    await sleep(250);
  }
}

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    for (const server of servers) server.kill(signal);
    process.exit(0);
  });
}

start(port);
await ready(`${baseURL}/en/login`);
start(latencyPort, { BS_FETCH_DELAY_MS: String(fetchDelayMs) });
