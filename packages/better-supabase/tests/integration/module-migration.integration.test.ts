import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { renderModuleMigration } from "../../src/cli/sql/module-migration.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { stackDbUrl } from "./stack-env.ts";

const dbUrl = stackDbUrl();

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

const MODULES = ["memberships", "audit", "invitations", "queue", "mfa"];

describe.skipIf(!live)(
  "the module migration of sql.workflow 'migrations'",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 1 });

    afterAll(() => pool.end());

    it("applies twice, so a later module migration can repeat every statement", async () => {
      const migration = renderModuleMigration({
        files: renderBlocks(MODULES).filter((file) => file.kind !== "test"),
      });

      const client = await pool.connect();

      try {
        await client.query("begin");
        await client.query("drop schema if exists better_supabase cascade");
        await client.query(migration);
        await client.query(migration);

        const { rows } = await client.query<{ name: string }>(
          "select name from better_supabase.blocks order by name",
        );

        expect(rows.map((row) => row.name)).toEqual(
          expect.arrayContaining(MODULES),
        );
      } finally {
        await client.query("rollback");
        client.release();
      }
    });
  },
);
