import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { type AddressInfo, createServer } from "node:net";

export async function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      // SAFETY: a TCP listener reports an AddressInfo; only pipes report a string.
      const { port } = server.address() as AddressInfo;
      server.close(() => {
        resolve(port);
      });
    });
  });
}

export async function waitFor(
  url: string,
  server: ChildProcess,
): Promise<void> {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null)
      throw new Error(`next start exited with ${String(server.exitCode)}`);
    try {
      await fetch(url, { signal: AbortSignal.timeout(1000) });
      return;
    } catch {
      await new Promise((resolve) => {
        setTimeout(resolve, 250);
      });
    }
  }
  throw new Error(`${url} did not come up`);
}

export interface NextServer {
  readonly base: string;
  readonly process: ChildProcess;
}

/** Builds the app at `cwd` and serves it with `next start` on a free port. */
export async function buildAndStart(
  cwd: string,
  env: NodeJS.ProcessEnv,
): Promise<NextServer> {
  execFileSync("pnpm", ["exec", "next", "build"], {
    cwd,
    env,
    stdio: "ignore",
  });
  const port = await freePort();
  const base = `http://127.0.0.1:${String(port)}`;
  const server = spawn(
    "pnpm",
    ["exec", "next", "start", "-p", String(port), "-H", "127.0.0.1"],
    { cwd, env, stdio: "ignore" },
  );
  await waitFor(base, server);
  return { base, process: server };
}
