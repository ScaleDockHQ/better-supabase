import { Pool } from "pg";

import { dbUrl } from "./server.ts";

/**
 * Starts every run from an empty Workflow state. A World that finds the runs of
 * earlier servers (their wake-ups, parked sessions and queued deliveries)
 * re-delivers them, which crowds out the messages a scenario is waiting for.
 * The suite owns the `workflow` schema and its queue, so a session-level
 * advisory lock keeps a second run (`pnpm check` starts two) waiting until the
 * first one has finished.
 */
const LOCK = 7_351_001;

export default async function setup(): Promise<() => Promise<void>> {
  const pool = new Pool({ connectionString: dbUrl(), max: 1 });
  pool.on("error", () => undefined);

  try {
    await pool.query("select pg_advisory_lock($1)", [LOCK]);

    const tables = await pool.query<{ table_name: string }>(
      "select table_name from information_schema.tables where table_schema = 'workflow' and table_type = 'BASE TABLE'",
    );

    if (tables.rows.length > 0) {
      const list = tables.rows
        .map((row) => `workflow."${row.table_name}"`)
        .join(", ");
      await pool.query(`truncate ${list} restart identity cascade`);
    }

    // The queue exists once a World has started against the database, which a
    // fresh stack has not seen yet.
    await pool.query(
      "select pgmq.purge_queue(queue_name) from pgmq.list_queues() where queue_name = 'workflow_deliveries'",
    );
  } catch (error) {
    await pool.end();
    throw error;
  }

  return async () => {
    await pool.query("select pg_advisory_unlock($1)", [LOCK]);
    await pool.end();
  };
}
