import type { Server } from "node:http";
import type { AddressInfo } from "node:net";

import { createServer } from "node:http";
import { setTimeout as sleep } from "node:timers/promises";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { SupabaseWorld } from "../../src/workflow-sdk/world/index.ts";

import { createSupabaseWorld } from "../../src/workflow-sdk/world/index.ts";
import { dbUrl, reachable } from "./block-session.ts";
import { installWorld } from "./workflow-world.ts";

const live = await reachable();

const SECRET = "recovery-test-secret";
const RUN_ID = "wrun_recovery_sweep";

const pool = new Pool({ connectionString: dbUrl });
let world: SupabaseWorld;
let server: Server;
const received: unknown[] = [];

async function until<T>(
  read: () => Promise<T | undefined>,
  ms = 20_000,
): Promise<T> {
  const deadline = Date.now() + ms;

  while (Date.now() < deadline) {
    const value = await read();

    if (value !== undefined) {
      return value;
    }

    await sleep(100);
  }

  throw new Error("timed out");
}

beforeAll(async () => {
  if (!live) {
    return;
  }

  await installWorld(pool);
  await pool.query("delete from workflow.workflow_runs where id = $1", [
    RUN_ID,
  ]);
  await pool.query("select pgmq.purge_queue('workflow_deliveries')");

  let flowUrl = "";

  world = createSupabaseWorld({
    delivery: "poll",
    deliverySecret: SECRET,
    pollInterval: 200,
    recoverAfter: 5,
    pool,
    get flowUrl() {
      return flowUrl;
    },
  });

  const handler = world.createQueueHandler(
    "__wkf_workflow_",
    async (message) => {
      received.push(message);
    },
  );

  server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => {
      const headers = new Headers();

      for (const [key, value] of Object.entries(req.headers)) {
        if (typeof value === "string") {
          headers.set(key, value);
        }
      }

      void handler(
        new Request(`http://localhost${req.url ?? "/"}`, {
          method: "POST",
          headers,
          body: Buffer.concat(chunks),
        }),
      ).then(async (response) => {
        res.writeHead(response.status);
        res.end(await response.text());

        return response;
      });
    });
  });
  await new Promise<void>((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });
  const { port } = server.address() as AddressInfo;
  flowUrl = `http://127.0.0.1:${String(port)}/.well-known/workflow/v1/flow`;
});

afterAll(async () => {
  if (live) {
    await pool.query("delete from workflow.workflow_runs where id = $1", [
      RUN_ID,
    ]);
    await world.close();
    await new Promise((resolve) => {
      server.close(resolve);
    });
  }

  await pool.end();
});

describe.skipIf(!live)("owed wake-up recovery", () => {
  it("wakes a run whose wake-up was lost, then clears the flag once delivered", async () => {
    await pool.query(
      `insert into workflow.workflow_runs
         (id, deployment_id, name, status, spec_version, wake_pending, updated_at)
       values ($1, 'dpl_test', 'workflow//recovery//sweep', 'running', '3',
               true, now() - interval '1 hour')`,
      [RUN_ID],
    );

    await world.start();

    const woken = await until(async () =>
      received.find(
        (message) =>
          typeof message === "object" &&
          message !== null &&
          "runId" in message &&
          message.runId === RUN_ID,
      ),
    );

    expect(woken).toBeDefined();

    const flag = await until(async () => {
      const row = await pool.query<{ wake_pending: boolean }>(
        "select wake_pending from workflow.workflow_runs where id = $1",
        [RUN_ID],
      );

      return row.rows[0]?.wake_pending === false ? false : undefined;
    });

    expect(flag).toBe(false);
  });
});
