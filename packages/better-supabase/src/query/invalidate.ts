import type { Query, QueryClient, QueryMeta } from "@tanstack/query-core";

/**
 * Carried by every better-supabase query: the tables whose changes make it
 * stale, on top of the app's `Register['queryMeta']`, so the options stay
 * assignable to `useQuery` when the app narrows its query meta.
 */
export type BetterQueryMeta = QueryMeta & {
  readonly bsTables: readonly string[];
};

function isString(value: unknown): value is string {
  return typeof value === "string";
}

function queryTables(query: Query): readonly string[] | undefined {
  const meta: Readonly<Record<string, unknown>> | undefined = query.meta;
  const tables = meta?.["bsTables"];
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
