import type { Pool } from "pg";

import { renderModules } from "../../src/sql/registry.ts";
import { FIXTURE_TENANT_SQL } from "./fixture-tenant.ts";

/**
 * Commits the `workflow-sdk-world` module (and the modules it requires)
 * unless an earlier suite did, as `sql-modules.integration` does: the World
 * writes through its own pool, outside any rolled-back session.
 */
export async function installWorld(pool: Pool): Promise<void> {
  const present = await pool.query<{ ok: boolean }>(
    "select to_regprocedure('better_supabase.dispatch_workflow_deliveries(integer)') is not null as ok",
  );
  if (present.rows[0]?.ok === true) return;
  const client = await pool.connect();
  try {
    await client.query("begin");
    for (const file of renderModules(["workflow-sdk-world"]))
      if (file.kind !== "test") await client.query(file.contents);
    await client.query(FIXTURE_TENANT_SQL);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}
