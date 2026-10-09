import type {
  Query,
  QueryCache,
  QueryClient,
  QueryMeta,
} from "@tanstack/query-core";

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

/** Table to the hashes of the queries that read it, kept current from the cache's events. */
interface TableIndex {
  readonly byTable: Map<string, Set<string>>;
  readonly tablesOf: Map<string, readonly string[]>;
}

const indexes = new WeakMap<QueryCache, TableIndex>();

function indexOf(cache: QueryCache): TableIndex {
  const existing = indexes.get(cache);
  if (existing) return existing;
  const index: TableIndex = { byTable: new Map(), tablesOf: new Map() };
  const remove = (hash: string) => {
    for (const table of index.tablesOf.get(hash) ?? []) {
      const set = index.byTable.get(table);
      set?.delete(hash);
      if (set?.size === 0) index.byTable.delete(table);
    }
    index.tablesOf.delete(hash);
  };
  const add = (hash: string) => {
    const query = cache.get(hash);
    const tables = query ? queryTables(query) : undefined;
    const known = index.tablesOf.get(hash);
    if (
      known !== undefined &&
      tables !== undefined &&
      known.length === tables.length &&
      known.every((table, at) => table === tables[at])
    )
      return;
    remove(hash);
    if (!tables || tables.length === 0) return;
    index.tablesOf.set(hash, tables);
    for (const table of tables) {
      let set = index.byTable.get(table);
      if (!set) index.byTable.set(table, (set = new Set()));
      set.add(hash);
    }
  };
  for (const query of cache.getAll()) add(query.queryHash);
  // The index lives as long as the cache; the cache has no teardown hook.
  cache.subscribe((event) => {
    const hash = event.query.queryHash;
    if (event.type === "removed") remove(hash);
    // Options, and with them `meta`, change when an observer attaches or
    // updates and when a fetch starts.
    else if (
      event.type === "added" ||
      event.type === "observerAdded" ||
      event.type === "observerOptionsUpdated" ||
      (event.type === "updated" && event.action.type === "fetch")
    )
      add(hash);
  });
  indexes.set(cache, index);
  return index;
}

/**
 * Invalidates every query that read one of `tables`: better-supabase queries
 * by their `meta.bsTables`, and other `['bs', table, ...]` keys by prefix.
 * An index from table to queries finds them, so a write to a table nothing
 * read skips the cache scan.
 */
export function invalidateTables(
  client: QueryClient,
  tables: readonly string[],
): Promise<void> {
  if (tables.length === 0) return Promise.resolve();
  const { byTable } = indexOf(client.getQueryCache());
  const matched = new Set<string>();
  for (const table of tables)
    for (const hash of byTable.get(table) ?? []) matched.add(hash);
  if (matched.size === 0) return Promise.resolve();
  return client.invalidateQueries({
    predicate: (query) => matched.has(query.queryHash),
  });
}
