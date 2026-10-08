import type { AddressInfo } from "node:net";

import { createServer, type Server } from "node:http";
import { env } from "node:process";
import { setTimeout as sleep } from "node:timers/promises";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import {
  WORKFLOW_DELIVERY_QUEUE,
  WORKFLOW_VAULT_SECRETS,
} from "../../src/sql/modules/workflow-sdk-world.ts";
import {
  createSupabaseWorld,
  type SupabaseWorld,
} from "../../src/workflow-sdk/world/index.ts";
import { dbUrl, reachable } from "./block-session.ts";
import { installWorld } from "./workflow-world.ts";

const live = await reachable();

// The database container reaches the test process through this host.
const HOST = env["WORKFLOW_TEST_HOST"] ?? "host.docker.internal";
const SECRET = "pg-net-test-secret";
// The jobs module keeps messages in PGMQ: q_ holds waiting ones, a_ the settled.
const QUEUE_TABLE = `q_${WORKFLOW_DELIVERY_QUEUE}`;
const ARCHIVE_TABLE = `a_${WORKFLOW_DELIVERY_QUEUE}`;

const pool = new Pool({ connectionString: dbUrl });
let createdPgNet = false;
let world: SupabaseWorld;
let server: Server;
const received: { message: unknown; attempt: number }[] = [];

function field(value: unknown, key: string): unknown {
  if (typeof value !== "object" || value === null) return undefined;
  const record: Record<string, unknown> = { ...value };
  return record[key];
}
const statuses: number[] = [];

async function setSecret(name: string, value: string): Promise<void> {
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

async function until<T>(
  read: () => Promise<T | undefined>,
  ms = 20_000,
): Promise<T> {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    const value = await read();
    if (value !== undefined) return value;
    await sleep(100);
  }
  throw new Error("timed out");
}

beforeAll(async () => {
  if (!live) return;
  await installWorld(pool);
  const installed = await pool.query(
    "select 1 from pg_extension where extname = 'pg_net'",
  );
  if (installed.rowCount === 0) {
    await pool.query("create extension pg_net");
    createdPgNet = true;
  }
  world = createSupabaseWorld({
    delivery: "pg_net",
    deliverySecret: SECRET,
    pool,
  });
  const handler = world.createQueueHandler(
    "__wkf_workflow_",
    async (message, meta) => {
      received.push({ message, attempt: meta.attempt });
    },
  );
  server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => {
      const headers = new Headers();
      for (const [key, value] of Object.entries(req.headers)) {
        if (typeof value === "string") headers.set(key, value);
      }
      void handler(
        new Request(`http://localhost${req.url ?? "/"}`, {
          method: "POST",
          headers,
          body: Buffer.concat(chunks),
        }),
      ).then(async (response) => {
        statuses.push(response.status);
        res.writeHead(response.status);
        res.end(await response.text());
      });
    });
  });
  await new Promise<void>((resolve) => {
    server.listen(0, "0.0.0.0", resolve);
  });
  const { port } = server.address() as AddressInfo;
  await setSecret(
    WORKFLOW_VAULT_SECRETS.flowUrl,
    `http://${HOST}:${String(port)}/.well-known/workflow/v1/flow`,
  );
  await setSecret(WORKFLOW_VAULT_SECRETS.deliverySecret, SECRET);
});

afterAll(async () => {
  if (!live) {
    await pool.end();
    return;
  }
  await pool.query("delete from vault.secrets where name = any($1)", [
    [WORKFLOW_VAULT_SECRETS.flowUrl, WORKFLOW_VAULT_SECRETS.deliverySecret],
  ]);
  await new Promise((resolve) => {
    server.close(resolve);
  });
  await world.close();
  if (createdPgNet) await pool.query("drop extension pg_net");
  await pool.end();
});

describe.skipIf(!live)("pg_net delivery", () => {
  it("delivers a signed message from the database and settles its job", async () => {
    const { messageId } = await world.queue("__wkf_workflow_pg_net_test", {
      runId: "wrun_pg_net_test",
    });
    const job = await pool.query<{ id: string }>(
      `select msg_id as id from pgmq.${QUEUE_TABLE}
        where message -> 'payload' ->> 'messageId' = $1`,
      [messageId],
    );
    const id = job.rows[0]?.id;
    expect(id).toBeDefined();

    const dispatched = await pool.query<{ count: number }>(
      "select better_supabase.dispatch_workflow_deliveries() as count",
    );
    expect(dispatched.rows[0]?.count).toBeGreaterThanOrEqual(1);

    const delivery = await until(async () =>
      received.find(
        (entry) => field(entry.message, "runId") === "wrun_pg_net_test",
      ),
    );
    expect(delivery.attempt).toBe(1);

    const archived = await until(async () => {
      const row = await pool.query<{ message: unknown }>(
        `select message from pgmq.${ARCHIVE_TABLE} where msg_id = $1`,
        [id],
      );
      return row.rows[0];
    });
    expect(field(archived.message, "dead")).toBeUndefined();
  });

  it("refuses a delivery whose signature does not match", async () => {
    const handler = world.createQueueHandler("__wkf_workflow_", async () => {
      throw new Error("must not run");
    });
    const response = await handler(
      new Request("http://localhost/.well-known/workflow/v1/flow", {
        method: "POST",
        headers: {
          "x-bs-job": `${WORKFLOW_DELIVERY_QUEUE}:1:1`,
          "x-bs-signature": "t=1,v1=00",
        },
        body: "{}",
      }),
    );
    expect(response.status).toBe(401);
    expect(statuses).not.toContain(500);
  });
});
