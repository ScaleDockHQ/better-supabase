import type { Query, QueryClient } from "@tanstack/query-core";

/** Carried by every better-supabase query: the tables whose changes make it stale. */
export interface BetterQueryMeta {
  readonly bsTables: readonly string[];
  readonly [key: string]: unknown;
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

function queryTables(query: Query): readonly string[] | undefined {
  const tables = query.meta?.["bsTables"];
  if (Array.isArray(tables)) {
    const list: readonly unknown[] = tables;
    return list.every(isString) ? list : list.filter(isString);
  }
  const [prefix, table] = query.queryKey;
  return prefix === "bs" && typeof table === "string" ? [table] : undefined;
}

/**
 * Invalidates every query that read one of `tables`: better-supabase queries
 * by their `meta.bsTables`, and other `['bs', table, ...]` keys by prefix.
 */
export function invalidateTables(
  client: QueryClient,
  tables: readonly string[],
): Promise<void> {
  if (tables.length === 0) return Promise.resolve();
  const changed = new Set(tables);
  return client.invalidateQueries({
    predicate: (query) =>
      queryTables(query)?.some((table) => changed.has(table)) ?? false,
  });
}
