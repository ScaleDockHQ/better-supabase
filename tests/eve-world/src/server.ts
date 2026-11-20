import type { ChildProcess } from "node:child_process";

import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { env as processEnv } from "node:process";
import { setTimeout as sleep } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";

const ROOT = fileURLToPath(new URL("..", import.meta.url));

export type Delivery = "poll" | "pg_net";

export interface ServerOptions {
  /** `dev` runs `eve dev --no-ui`; `start` builds once and runs `eve start`. */
  readonly command?: "dev" | "start";
  readonly delivery?: Delivery;
  readonly connection?: "session" | "transaction";
  readonly env?: Readonly<Record<string, string>>;
}

export interface EveServer {
  readonly url: string;
  readonly port: number;
  /** Everything the server printed so far. */
  logs(): string;
  /** Stops the process and waits for it to exit. */
  stop(): Promise<void>;
}

/**
 * The connection string the suites share, from the stack's
 * `.env.development.local`.
 */
export function dbUrl(): string {
  const url = process.env["SUPABASE_DB_URL"];

  if (url === undefined || url === "") {
    throw new Error(
      "SUPABASE_DB_URL is not set; run `pnpm supabase:start` and `pnpm env:local`",
    );
  }

  return url;
}

async function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const probe = createServer();
    probe.once("error", reject);
    probe.listen(0, () => {
      const address = probe.address();
      probe.close(() => {
        if (address !== null && typeof address === "object") {
          resolve(address.port);
        } else {
          reject(new Error("no port"));
        }
      });
    });
  });
}

const READY = /(?:ready at|listening at) (\S+)/u;

function eveBin(): string {
  return fileURLToPath(new URL("../node_modules/.bin/eve", import.meta.url));
}

/**
 * Starts eve's own server on a free port with the Supabase World, and waits
 * until it answers.
 */
export async function startServer(
  options: ServerOptions = {},
): Promise<EveServer> {
  const port = await freePort();
  const command = options.command ?? "dev";
  const delivery = options.delivery ?? "poll";
  const flowUrl = `http://127.0.0.1:${String(port)}/.well-known/workflow/v1/flow`;

  const env: Record<string, string | undefined> = {
    ...process.env,
    // Vitest sets NODE_ENV=test, which makes eve swap authored models for its own mock.
    NODE_ENV: command === "dev" ? "development" : "production",
    // `eve start` is not development, so the poll route needs a signed delivery.
    WORKFLOW_DELIVERY_SECRET: "eve-world-delivery-secret",
    PORT: String(port),
    WORKFLOW_TARGET_WORLD: "better-supabase/workflow-sdk/world",
    WORKFLOW_POSTGRES_URL: dbUrl(),
    WORKFLOW_DELIVERY: delivery,
    WORKFLOW_FLOW_URL: flowUrl,
    WORKFLOW_LOCAL_BASE_URL: `http://127.0.0.1:${String(port)}`,
    ...(options.connection === undefined
      ? {}
      : { WORKFLOW_POSTGRES_CONNECTION: options.connection }),
    ...options.env,
  };

  if (delivery === "pg_net") {
    // A containerized Postgres calls the host back through Docker's gateway name; a native one
    // shares the host's network.
    const host =
      processEnv["SUPABASE_RUNTIME"] === "native"
        ? "127.0.0.1"
        : "host.docker.internal";
    env["WORKFLOW_FLOW_URL"] = flowUrl.replace("127.0.0.1", host);
    await configurePgNet(env["WORKFLOW_FLOW_URL"], "eve-world-delivery-secret");
  }

  if (command === "start") {
    await run(["build"], env);
  }

  const args =
    command === "dev"
      ? ["dev", "--no-ui", "--port", String(port)]
      : ["start", "--port", String(port)];

  const child = spawn(eveBin(), args, {
    cwd: ROOT,
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";

  const collect = (chunk: Buffer): void => {
    output += chunk.toString();
  };

  child.stdout.on("data", collect);
  child.stderr.on("data", collect);

  const exited = new Promise<void>((resolve) => {
    child.once("exit", () => {
      resolve();
    });
  });

  const stop = async (): Promise<void> => {
    if (child.exitCode === null) {
      child.kill("SIGTERM");
      const killer = setTimeout(() => {
        child.kill("SIGKILL");
      }, 10_000);
      await exited;
      clearTimeout(killer);
    }
  };

  const url = `http://127.0.0.1:${String(port)}`;
  await waitReady(child, () => output, url);

  return { url, port, logs: () => output, stop };
}

async function waitReady(
  child: ChildProcess,
  output: () => string,
  url: string,
): Promise<void> {
  const deadline = Date.now() + 90_000;

  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(
        `eve exited with ${String(child.exitCode)} before it was ready:\n${output()}`,
      );
    }

    if (READY.test(output())) {
      const health = await fetch(`${url}/eve/v1/health`).catch(() => undefined);

      if (health?.ok === true) {
        return;
      }
    }

    await sleep(250);
  }

  child.kill("SIGKILL");
  throw new Error(`eve was not ready in 90 seconds:\n${output()}`);
}

async function run(
  args: readonly string[],
  env: Record<string, string | undefined>,
): Promise<void> {
  const child = spawn(eveBin(), [...args], { cwd: ROOT, env, stdio: "pipe" });
  let output = "";
  child.stdout.on("data", (chunk: Buffer) => {
    output += chunk.toString();
  });
  child.stderr.on("data", (chunk: Buffer) => {
    output += chunk.toString();
  });

  const code = await new Promise<number | null>((resolve) => {
    child.once("exit", resolve);
  });

  if (code !== 0) {
    throw new Error(
      `eve ${args.join(" ")} exited with ${String(code)}:\n${output}`,
    );
  }
}

async function setSecret(
  pool: Pool,
  name: string,
  value: string,
): Promise<void> {
  const existing = await pool.query<{ id: string }>(
    "select id from vault.secrets where name = $1",
    [name],
  );
  const id = existing.rows[0]?.id;

  if (id === undefined) {
    await pool.query("select vault.create_secret($1, $2)", [value, name]);
  } else {
    await pool.query("select vault.update_secret($1, $2)", [id, value]);
  }
}

/**
 * Points the database's dispatcher at this server: pg_net posts to the URL in
 * the Vault.
 */
async function configurePgNet(flowUrl: string, secret: string): Promise<void> {
  const pool = new Pool({ connectionString: dbUrl(), max: 1 });
  pool.on("error", () => undefined);

  try {
    await pool.query("create extension if not exists pg_net");
    await setSecret(pool, "workflow_flow_url", flowUrl);
    await setSecret(pool, "workflow_delivery_secret", secret);
  } finally {
    await pool.end();
  }
}
