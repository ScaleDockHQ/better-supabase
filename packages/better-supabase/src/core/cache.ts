import type { SchemaMeta, TableMeta } from "../schema/types.ts";
import type { MutationNotice, RpcNotice } from "./events.ts";

import { invalidationTargets } from "../ir/tables.ts";

/** What a mutation changed: a table, the primary keys of its rows and the tenant. */
export interface CacheTarget {
  /** App key of the table. */
  readonly table: string;
  /**
   * App keys of every table whose cached reads are now stale: `table`, plus
   * tables whose foreign keys cascade or set a value when `table` rows are
   * deleted. Invalidate every read that touched one of them.
   */
  readonly tables: readonly string[];
  /** Primary keys of the changed rows; composite keys are joined with `,`. */
  readonly ids: readonly string[];
  readonly tenant?: string;
}

/**
 * Invalidates cached reads after a mutation. First-party adapters:
 * `nextCache()` (Next.js cache tags) and `queryCache(client)` (TanStack
 * Query). Attach one with `betterSupabase.cache(adapter)`; prove custom ones with
 * `testCacheAdapter`.
 */
export interface CacheAdapter {
  readonly name: string;
  invalidate(target: CacheTarget): void | Promise<void>;
}

/** Primary key of a row as a string, or `undefined` when it isn't returned. */
export function rowKey(
  table: TableMeta,
  row: Readonly<Record<string, unknown>>,
): string | undefined {
  if (table.primaryKey.length === 0) return undefined;
  const parts = table.primaryKey.map((column) => row[column]);
  if (parts.some((part) => part === undefined || part === null))
    return undefined;
  return parts.map(String).join(",");
}

export function cacheTargetOf(
  meta: SchemaMeta,
  notice: MutationNotice,
): CacheTarget {
  const table = meta.tables[notice.table];
  const ids = table
    ? [...new Set(notice.rows.flatMap((row) => rowKey(table, row) ?? []))]
    : [];
  const tenant = notice.context.tenant;
  return {
    table: notice.table,
    tables:
      notice.kind === "delete"
        ? invalidationTargets(meta, notice.table)
        : [notice.table],
    ids,
    ...(tenant === undefined ? {} : { tenant }),
  };
}

/** One target per table an RPC changes; RPCs report no row ids. */
export function rpcCacheTargets(
  meta: SchemaMeta,
  notice: RpcNotice,
): CacheTarget[] {
  const tenant = notice.context.tenant;
  return notice.invalidates.map((table) => ({
    table,
    tables: invalidationTargets(meta, table),
    ids: [],
    ...(tenant === undefined ? {} : { tenant }),
  }));
}

export interface MemoryCache extends CacheAdapter {
  readonly invalidated: readonly CacheTarget[];
  clear(): void;
}

/** Records invalidations. For tests and for checking what a mutation touches. */
export function memoryCache(): MemoryCache {
  const invalidated: CacheTarget[] = [];
  return {
    name: "memory",
    invalidated,
    invalidate: (target) => {
      invalidated.push(target);
    },
    clear: () => {
      invalidated.length = 0;
    },
  };
}
