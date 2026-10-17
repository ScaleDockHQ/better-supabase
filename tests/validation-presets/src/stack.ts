import type { PresetName } from "better-supabase/preset";

import { resolveConfig } from "better-supabase/config";
import { moduleLayout, renderModules } from "better-supabase/sql";
import { DatabaseError, Pool, type PoolClient } from "pg";

// `pnpm env:local` writes it (the CLI picks the ports per checkout); without
// it the suites skip, like they do when the stack is down.
export const dbUrl: string | undefined = process.env["SUPABASE_DB_URL"];

export async function reachable(): Promise<boolean> {
  if (dbUrl === undefined) return false;
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

/**
 * The module files `sql add` writes for a config with only `preset`:
 * schema files, then data files, then the pgTAP files with `tests`.
 */
export function presetFiles(
  preset: PresetName,
  options: { readonly tests?: boolean } = {},
) {
  const config = resolveConfig({ preset }, process.cwd());
  const files = renderModules(config.blockNames, moduleLayout(config));
  return [
    ...files.filter((file) => file.kind === "schema"),
    ...files.filter((file) => file.kind === "data"),
    ...(options.tests === true
      ? files.filter((file) => file.kind === "test")
      : []),
  ];
}

/**
 * Installs the files as one migration and rolls it back. Other suites
 * install modules on the same stack, and Postgres resolves a deadlock
 * between two installs by aborting one; the aborted install starts over.
 */
export async function installAndRollBack(
  pool: Pool,
  sql: string,
  body: (client: PoolClient) => Promise<void>,
): Promise<void> {
  const client = await pool.connect();
  try {
    for (let attempt = 1; ; attempt += 1) {
      await client.query("begin");
      try {
        await client.query(
          "select pg_advisory_xact_lock(hashtext('better-supabase:validation-install'))",
        );
        await client.query(sql);
        break;
      } catch (error) {
        await client.query("rollback");
        if (!(error instanceof DatabaseError) || error.code !== "40P01") {
          throw error;
        }
        if (attempt === 5) throw error;
      }
    }
    await body(client);
  } finally {
    await client.query("rollback");
    client.release();
  }
}
