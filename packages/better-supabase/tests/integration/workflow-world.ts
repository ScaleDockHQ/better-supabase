import type { Pool } from "pg";

import { renderBlocks } from "../../src/sql/render.ts";
import { FIXTURE_HELPERS_SQL } from "./fixture-tenant.ts";

/**
 * Commits the `workflow-sdk` module (and the modules it requires) unless an
 * earlier suite did, as `sql-modules.integration` does: the World writes
 * through its own pool, outside any rolled-back session.
 */
export async function installWorld(pool: Pool): Promise<void> {
  const present = await pool.query<{ ok: boolean }>(
    `select coalesce(
       pg_get_functiondef(to_regprocedure('better_supabase.dispatch_workflow_deliveries(integer)'))
         like '%workflow_delivery_headers%', false) as ok`,
  );

  if (present.rows[0]?.ok === true) {
    return;
  }

  const client = await pool.connect();

  try {
    await client.query("begin");

    for (const file of renderBlocks(["workflow-sdk"], { rerunnable: true })) {
      if (file.kind !== "test") {
        await client.query(file.contents);
      }
    }

    await client.query(FIXTURE_HELPERS_SQL);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Starts a World suite from an empty Workflow state. The suites share one
 * database, and a World that finds the runs and queued deliveries of an earlier
 * suite re-delivers them to workflows it does not know. The queue exists once a
 * World has started, which a fresh database has not seen yet.
 */
export async function resetWorld(pool: Pool): Promise<void> {
  const tables = await pool.query<{ table_name: string }>(
    "select table_name from information_schema.tables where table_schema = 'workflow' and table_type = 'BASE TABLE'",
  );

  if (tables.rows.length > 0) {
    const list = tables.rows
      .map((row) => `workflow."${row.table_name}"`)
      .join(", ");

    await pool.query(`truncate ${list} restart identity cascade`);
  }

  await pool.query(
    "select pgmq.purge_queue(queue_name) from pgmq.list_queues() where queue_name = 'workflow_deliveries'",
  );
}
