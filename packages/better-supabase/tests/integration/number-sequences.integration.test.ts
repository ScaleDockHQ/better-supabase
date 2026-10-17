import { Pool, type PoolClient } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { renderModules } from "../../src/sql/render.ts";
import { dbUrl, reachable } from "./block-session.ts";
import { FIXTURE_TENANT_SQL } from "./fixture-tenant.ts";

const live = await reachable();

const layout: ModuleLayout = {
  modules: {
    "number-sequences": {
      options: {
        entities: {
          invoice: { period: "none", format: "INV-{n:5}" },
          yearly: { period: "year", format: "{yyyy}-{n}" },
          fiscal: {
            period: { fiscalYearStartMonth: 4 },
            format: "FY-{yyyy}-{n}",
          },
        },
      },
    },
  },
};

async function install(
  client: PoolClient,
  next: ModuleLayout = layout,
): Promise<void> {
  await client.query("begin");

  try {
    for (const file of renderModules(["number-sequences"], next)) {
      if (file.kind !== "test") {
        await client.query(file.contents);
      }
    }

    // `tenant` replaces the fixture helper. Put it back before commit so
    // other suites never see the member-checked version.
    await client.query(FIXTURE_TENANT_SQL);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  }
}

async function allocate(
  client: PoolClient,
  tenant: string,
  entity: string,
  at?: string,
): Promise<string> {
  const { rows } = await client.query<{ n: string }>(
    "select better_supabase.next_number($1::uuid, $2::text, $3::timestamptz)::text as n",
    [tenant, entity, at ?? new Date().toISOString()],
  );

  return rows[0]!.n;
}

describe.skipIf(!live)("number sequences", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 4 });

  beforeAll(async () => {
    const client = await pool.connect();

    try {
      await install(client);
    } finally {
      client.release();
    }
  });

  afterAll(async () => {
    const client = await pool.connect();

    try {
      await client.query("rollback").catch(() => undefined);
      await client.query(
        "delete from better_supabase.number_sequences where entity in ('invoice', 'yearly', 'fiscal')",
      );
      await install(client, {});
    } finally {
      client.release();
      await pool.end();
    }
  });

  it("gives parallel transactions distinct numbers", async () => {
    const tenant = crypto.randomUUID();
    const left = await pool.connect();
    const right = await pool.connect();

    try {
      await left.query("begin");
      await right.query("begin");

      const sql =
        "select better_supabase.next_number($1::uuid, 'invoice', now())::text as n";

      const leftResult = left.query<{ n: string }>(sql, [tenant]);
      const rightResult = right.query<{ n: string }>(sql, [tenant]);

      const first = await Promise.race([
        leftResult.then((result) => ({ side: "left" as const, result })),
        rightResult.then((result) => ({ side: "right" as const, result })),
      ]);

      await (first.side === "left" ? left : right).query("commit");
      const second = await (first.side === "left" ? rightResult : leftResult);
      await (first.side === "left" ? right : left).query("commit");
      expect(new Set([first.result.rows[0]!.n, second.rows[0]!.n])).toEqual(
        new Set(["1", "2"]),
      );
    } finally {
      await left.query("rollback").catch(() => undefined);
      await right.query("rollback").catch(() => undefined);
      left.release();
      right.release();
    }
  });

  it("releases a number when the transaction rolls back", async () => {
    const tenant = crypto.randomUUID();
    const client = await pool.connect();

    try {
      await client.query("begin");
      expect(await allocate(client, tenant, "invoice")).toBe("1");
      await client.query("rollback");
      expect(await allocate(client, tenant, "invoice")).toBe("1");
    } finally {
      await client.query("rollback").catch(() => undefined);
      client.release();
    }
  });

  it("starts again at 1 in a new year", async () => {
    const tenant = crypto.randomUUID();
    const client = await pool.connect();

    try {
      await allocate(client, tenant, "yearly", "2025-06-01T00:00:00Z");
      await allocate(client, tenant, "yearly", "2025-12-31T00:00:00Z");
      await allocate(client, tenant, "yearly", "2026-01-01T00:00:00Z");

      const { rows } = await client.query<{
        period: string;
        last_number: string;
      }>(
        `select period, last_number::text
         from better_supabase.number_sequences
         where tenant_id = $1 and entity = 'yearly'
         order by period`,
        [tenant],
      );

      expect(rows).toEqual([
        { period: "2025", last_number: "2" },
        { period: "2026", last_number: "1" },
      ]);
    } finally {
      client.release();
    }
  });

  it("treats April as the start of the fiscal year", async () => {
    const tenant = crypto.randomUUID();
    const client = await pool.connect();

    try {
      await allocate(client, tenant, "fiscal", "2026-03-31T12:00:00Z");
      await allocate(client, tenant, "fiscal", "2026-04-01T00:00:00Z");

      const { rows } = await client.query<{ period: string }>(
        `select period
         from better_supabase.number_sequences
         where tenant_id = $1 and entity = 'fiscal'
         order by period`,
        [tenant],
      );

      expect(rows.map((row) => row.period)).toEqual(["2025", "2026"]);
    } finally {
      client.release();
    }
  });
});
