import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { defineSeed } from "../../src/testing/seed.ts";
import { schema } from "../fixtures/generated-camel.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

async function reachable(): Promise<boolean> {
  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });
  try {
    await pool.query("select 1");
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

describe.skipIf(!live)("seed against the local database", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  afterAll(() => pool.end());

  it("inserts fixtures in dependency order and is re-runnable", async () => {
    const organization = crypto.randomUUID();
    const customer = crypto.randomUUID();
    const seed = defineSeed(defineSupabase(schema), {
      customers: {
        first: {
          id: customer,
          organizationId: organization,
          name: "Seed's first",
          metadata: { tier: "pro" },
        },
      },
      organizations: {
        seeded: {
          id: organization,
          name: "Seeded organization",
          slug: `seeded-${organization.slice(0, 8)}`,
        },
      },
    });
    const client = await pool.connect();
    const sql = {
      queryRaw: async <T>(text: string) =>
        (await client.query(text)).rows as T[],
    };
    try {
      await client.query("begin");
      await seed.insert(sql);
      await seed.insert(sql);
      const rows = await client.query<{
        name: string;
        metadata: unknown;
        organization_id: string;
      }>(
        "select name, metadata, organization_id from public.customers where id = $1",
        [seed.rows.customers.first.id],
      );
      expect(rows.rows).toEqual([
        {
          name: "Seed's first",
          metadata: { tier: "pro" },
          organization_id: organization,
        },
      ]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
