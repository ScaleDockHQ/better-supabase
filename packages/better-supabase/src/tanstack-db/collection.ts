import type { QueryClient, SkipToken } from "@tanstack/query-core";

import type { BetterSupabase } from "../core/define.ts";
import type { Db } from "../core/repository-types.ts";
import type { AsyncResult } from "../core/result.ts";
import type { BetterQueryMeta } from "../query/invalidate.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";

import { DbException } from "../core/db-exception.ts";

/** The query a collection loads: `queries.<table>.findMany(args)` from `better-supabase/query`. */
export interface CollectionQuery<Row> {
  readonly queryKey: readonly unknown[];
  readonly queryFn:
    | ((context: { readonly signal: AbortSignal }) => Promise<Row[]>)
    | SkipToken;
  readonly meta?: BetterQueryMeta;
}

/** The fields of a TanStack DB pending mutation the handlers read. */
export interface PendingMutationLike<Row> {
  readonly original: unknown;
  readonly modified: Row;
  readonly changes: Partial<Row>;
}

/** The handler argument TanStack DB passes to `onInsert`, `onUpdate` and `onDelete`. */
export interface MutationParamsLike<Row> {
  readonly transaction: {
    readonly mutations: readonly PendingMutationLike<Row>[];
  };
}

export type CollectionMutationHandler<Row> = (
  params: MutationParamsLike<Row>,
) => Promise<void>;

export interface CollectionOptions<Row> {
  readonly query: CollectionQuery<Row>;
  readonly queryClient: QueryClient;
  /** The collection id. Defaults to the table key. */
  readonly id?: string;
}

/**
 * Options for `queryCollectionOptions()` from `@tanstack/query-db-collection`.
 * Typed by shape, so better-supabase doesn't depend on TanStack DB.
 */
export interface CollectionConfig<Row> {
  readonly id: string;
  readonly queryKey: readonly unknown[];
  readonly queryFn: (context: {
    readonly signal: AbortSignal;
  }) => Promise<Row[]>;
  readonly meta?: BetterQueryMeta;
  readonly queryClient: QueryClient;
  readonly getKey: (row: Row) => string | number;
  readonly onInsert: CollectionMutationHandler<Row>;
  readonly onUpdate: CollectionMutationHandler<Row>;
  readonly onDelete: CollectionMutationHandler<Row>;
}

type Write = (...args: unknown[]) => AsyncResult<unknown>;

function field(row: unknown, name: string): unknown {
  if (typeof row !== "object" || row === null || !(name in row))
    return undefined;
  return Object.getOwnPropertyDescriptor(row, name)?.value;
}

/**
 * A TanStack DB query collection for one table: it loads the rows with
 * `query`, keys them by the table's primary key, and sends inserts, updates
 * and deletes through the table's repository, so RLS, hooks, events and
 * plugins apply. After a write the collection refetches its query; with
 * `invalidateOnMutation(betterSupabase, queryClient)`, every other query
 * that read the table refetches too.
 *
 * ```ts
 * const customers = createCollection(
 *   queryCollectionOptions(
 *     collectionOptions(betterSupabase, db, "customers", {
 *       query: queries.customers.findMany({ where: { status: "active" } }),
 *       queryClient,
 *     }),
 *   ),
 * );
 * ```
 */
export function collectionOptions<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  T extends TableKey<M>,
  Row extends object,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  db: Db<M, F, E, unknown> | (() => Db<M, F, E, unknown>),
  table: T,
  options: CollectionOptions<Row>,
): CollectionConfig<Row> {
  const { query, queryClient } = options;
  const queryFn = query.queryFn;
  if (typeof queryFn !== "function")
    throw new TypeError(
      `better-supabase: the "${table}" collection needs a query that runs, not skipToken`,
    );
  const primaryKey = betterSupabase.meta.tables[table]?.primaryKey ?? [];
  const [single] = primaryKey;
  if (single === undefined)
    throw new TypeError(
      `better-supabase: the "${table}" collection needs a table with a primary key`,
    );
  const composite = primaryKey.length > 1;
  const idOf = (row: unknown): unknown =>
    composite
      ? Object.fromEntries(primaryKey.map((name) => [name, field(row, name)]))
      : field(row, single);
  const write = (method: "create" | "update" | "delete"): Write => {
    const resolved = typeof db === "function" ? db() : db;
    // SAFETY: Db is indexed by table key; the repository is checked below.
    const repository = resolved[table] as
      | Readonly<Record<string, Write | undefined>>
      | undefined;
    const fn = repository?.[method];
    if (!fn)
      throw new TypeError(
        `better-supabase: ${table}.${method} is not available`,
      );
    return fn;
  };
  const orThrow = async (result: AsyncResult<unknown>): Promise<void> => {
    const settled = await result;
    if (!settled.ok) throw new DbException(settled.error);
  };
  return {
    id: options.id ?? table,
    queryKey: query.queryKey,
    queryFn,
    ...(query.meta ? { meta: query.meta } : {}),
    queryClient,
    getKey: (row) => {
      if (!composite) {
        const id = field(row, single);
        return typeof id === "number" ? id : String(id);
      }
      return JSON.stringify(primaryKey.map((name) => field(row, name)));
    },
    onInsert: async ({ transaction }) => {
      const create = write("create");
      for (const mutation of transaction.mutations)
        await orThrow(create(mutation.modified, { returning: false }));
    },
    onUpdate: async ({ transaction }) => {
      const update = write("update");
      for (const mutation of transaction.mutations)
        await orThrow(
          update(idOf(mutation.original), mutation.changes, {
            returning: false,
          }),
        );
    },
    onDelete: async ({ transaction }) => {
      const remove = write("delete");
      for (const mutation of transaction.mutations)
        await orThrow(remove(idOf(mutation.original)));
    },
  };
}
