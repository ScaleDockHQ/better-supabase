import "server-only";
import type { SchemaMeta } from "better-supabase";

/** The part of a server `loadTables` needs. */
interface TableServer {
  readonly meta: Pick<SchemaMeta, "tableLoaders">;
  registerTable(table: Awaited<ReturnType<LoadTable>>): void;
}

type LoadTable = NonNullable<SchemaMeta["tableLoaders"]>[string];

/**
 * Loads the metadata of the named tables. The server loads table metadata on
 * first use (ADR 0611), but the REST routes, the OpenAPI document and the MCP
 * tools read each resource's table when their module evaluates, so each awaits
 * this first.
 */
export async function loadTables(
  server: TableServer,
  keys: Iterable<string>,
): Promise<void> {
  for (const key of keys) {
    const load = server.meta.tableLoaders?.[key];

    if (load !== undefined) {
      server.registerTable(await load());
    }
  }
}
