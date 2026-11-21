import type pg from "pg";

import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { EveServer } from "../src/server.ts";

import { Client } from "../src/client.ts";
import { connect, runsOf, unique } from "../src/db.ts";
import { startServer } from "../src/server.ts";

const RING = JSON.stringify([
  {
    id: "eve-world-a",
    key: Buffer.alloc(32, 7).toString("base64"),
    from: "1970-01-01T00:00:00Z",
  },
]);

let pool: pg.Pool;

beforeAll(() => {
  pool = connect();
});

afterAll(async () => {
  await pool.end();
});

/**
 * Runs a session whose second message carries `canary`, and returns what the
 * server printed.
 */
async function converse(
  server: EveServer,
  canary: string,
): Promise<{ id: string; title: string }> {
  const client = new Client(server.url);
  const title = unique("hello");
  const id = await client.create(title);
  await client.waitFor(id, "turn.settled");
  const before = (await client.history(id)).tailIndex ?? 0;
  await client.send(id, `${canary} words:2`);
  await client.waitFor(id, "turn.settled", before);

  return { id, title };
}

/**
 * Tables that hold the canary, as plain text or as the hex of its bytes
 * (`bytea` columns).
 */
async function tablesHolding(canary: string): Promise<string[]> {
  const tables = await pool.query<{ table_name: string }>(
    "select table_name from information_schema.tables where table_schema = 'workflow' and table_type = 'BASE TABLE' order by 1",
  );

  const hex = Buffer.from(canary).toString("hex");
  const found: string[] = [];

  for (const { table_name: table } of tables.rows) {
    const result = await pool.query<{ n: string }>(
      `select count(*) as n from workflow."${table}" t
       where row_to_json(t)::text like $1 or row_to_json(t)::text like $2`,
      [`%${canary}%`, `%${hex}%`],
    );

    if (Number(result.rows[0]?.n) > 0) {
      found.push(table);
    }
  }

  return found;
}

describe("run data on the Supabase World", () => {
  it("keeps the canary out of every workflow table when a key is set", async () => {
    const canary = `CANARY${String(Date.now())}KEYED`;

    const server = await startServer({
      command: "start",
      delivery: "poll",
      env: { WORKFLOW_ENCRYPTION_KEYS: RING },
    });

    try {
      const { id, title } = await converse(server, canary);

      expect(await tablesHolding(canary)).toEqual([]);
      expect(server.logs()).not.toContain("has no encryption key");

      const runs = await runsOf(pool, id, title);

      const stamped = await pool.query<{ key: string | null }>(
        "select attributes->>'$bsb.key_id' as key from workflow.workflow_runs where id = $1",
        [runs[0]?.id],
      );

      expect(stamped.rows[0]?.key).toBe("eve-world-a");
    } finally {
      await server.stop();
    }
  });

  it("finds the canary without a key, so the scan can see what it looks for", async () => {
    const canary = `CANARY${String(Date.now())}OPEN`;
    const server = await startServer({ command: "start", delivery: "poll" });

    try {
      await converse(server, canary);

      expect((await tablesHolding(canary)).length).toBeGreaterThan(0);
      expect(server.logs()).toContain(
        "The workflow World has no encryption key",
      );
    } finally {
      await server.stop();
    }
  });
});
