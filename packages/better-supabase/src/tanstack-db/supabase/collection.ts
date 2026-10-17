import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { QueryClient } from "@tanstack/query-core";

import { supabaseCollectionOptions } from "@supabase-labs/tanstack-db";

import type { BetterSupabase } from "../../core/define.ts";
import type { Db } from "../../core/repository-types.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../../schema/types.ts";

import { DbException } from "../../core/db-exception.ts";

type LabsConfig<Schema extends StandardSchemaV1> = ReturnType<
  typeof supabaseCollectionOptions<Schema>
>;

/**
 * What `supabaseCollectionOptions()` from `@supabase-labs/tanstack-db`
 * returns, without `undefined` in its optional properties, so `createCollection()`
 * accepts it under `exactOptionalPropertyTypes`.
 */
export type SupabaseCollectionConfig<Schema extends StandardSchemaV1> = {
  [K in keyof LabsConfig<Schema>]: Exclude<LabsConfig<Schema>[K], undefined>;
};

interface BaseOptions<Schema extends StandardSchemaV1> {
  /** The row schema, in database column names: `customersRow` from `standardSchema()`, `zod()` or `valibot()`. */
  readonly schema: Schema;
  /** Applies inserts, updates and deletes from other clients through Realtime `postgres_changes`. */
  readonly realtime?: boolean;
  /** Pushes each live query's filter to the Realtime subscription. Defaults to `false`. */
  readonly realtimeUseFilter?: boolean;
  readonly queryClient?: QueryClient;
}

export type SupabaseCollectionOptions<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  Schema extends StandardSchemaV1,
> = BaseOptions<Schema> &
  (
    | {
        /** Sends writes through the table's repository (the default), so RLS, hooks, events and plugins apply. */
        readonly writes?: "repository";
        readonly db: Db<M, F, E, unknown> | (() => Db<M, F, E, unknown>);
      }
    | {
        /** Sends writes straight to PostgREST with the supabase client, like `@supabase-labs/tanstack-db`. */
        readonly writes: "direct";
        readonly db?: never;
      }
  );

type Write = (...args: unknown[]) => AsyncResult<unknown>;

type Handler<
  Schema extends StandardSchemaV1,
  K extends "onInsert" | "onUpdate" | "onDelete",
> = NonNullable<SupabaseCollectionConfig<Schema>[K]>;

function field(row: unknown, name: string): unknown {
  if (typeof row !== "object" || row === null || !(name in row)) {
    return undefined;
  }

  return Object.getOwnPropertyDescriptor(row, name)?.value;
}

/**
 * A TanStack DB collection on `@supabase-labs/tanstack-db`: live queries load
 * on demand through PostgREST, Realtime keeps them current, and writes go
 * through the table's repository by default. Rows use database column names,
 * so the schema must use `casing: "snake"`, and the table must live in the
 * `public` schema, which is the one the Realtime listener watches.
 *
 * ```ts
 * const customers = createCollection(
 *   supabaseCollection(betterSupabase, supabase, "customers", {
 *     schema: customersRow,
 *     db,
 *     realtime: true,
 *   }),
 * );
 * ```
 */
export function supabaseCollection<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  T extends TableKey<M>,
  Schema extends StandardSchemaV1,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  supabase: SupabaseClient,
  table: T,
  options: SupabaseCollectionOptions<M, F, E, Schema>,
): SupabaseCollectionConfig<Schema> {
  const { meta } = betterSupabase;

  if (meta.casing !== "snake") {
    throw new TypeError(
      `better-supabase: supabaseCollection() needs casing: "snake"; @supabase-labs/tanstack-db reads and writes database column names. Use collectionOptions() with camel casing.`,
    );
  }

  const tableMeta = meta.tables[table];

  if (!tableMeta) {
    throw new TypeError(`better-supabase: unknown table "${table}"`);
  }

  if (tableMeta.schema !== "public") {
    throw new TypeError(
      `better-supabase: supabaseCollection() supports tables in the public schema; "${tableMeta.schema}.${tableMeta.name}" is not.`,
    );
  }

  const primaryKey = tableMeta.primaryKey;
  const [single] = primaryKey;

  if (single === undefined) {
    throw new TypeError(
      `better-supabase: the "${table}" collection needs a table with a primary key`,
    );
  }

  const labs = supabaseCollectionOptions({
    tableName: tableMeta.name,
    // SAFETY: with snake casing the primary key names are the row's keys.
    keys: [...primaryKey] as Parameters<
      typeof supabaseCollectionOptions<Schema>
    >[0]["keys"],
    schema: options.schema,
    supabase,
    ...(options.queryClient ? { queryClient: options.queryClient } : {}),
    ...(options.realtime === undefined ? {} : { realtime: options.realtime }),
    ...(options.realtimeUseFilter === undefined
      ? {}
      : { realtimeUseFilter: options.realtimeUseFilter }),
  });

  // SAFETY: only the declared types differ; createCollection() treats an
  // undefined optional property as unset.
  const config = labs as SupabaseCollectionConfig<Schema>;

  if (options.writes === "direct") {
    return config;
  }

  const { db } = options;

  // Codec columns decode on the repository (Temporal, bigint) but stay raw in
  // the synced rows, so those tables refetch instead of writing the result.
  const writeBack = !Object.values(tableMeta.columns).some(
    (column) => column.codec !== undefined,
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

    if (!fn) {
      throw new TypeError(
        `better-supabase: ${table}.${method} is not available`,
      );
    }

    return fn;
  };

  const orThrow = async (result: AsyncResult<unknown>): Promise<unknown> => {
    const settled = await result;

    if (!settled.ok) {
      throw new DbException(settled.error);
    }

    return settled.data;
  };

  const done = { refetch: !writeBack };

  const onInsert: Handler<Schema, "onInsert"> = async ({
    transaction,
    collection,
  }) => {
    const create = write("create");

    for (const mutation of transaction.mutations) {
      const row = await orThrow(create(mutation.modified));

      if (!writeBack) {
        continue;
      }

      // SAFETY: the repository returns the inserted row in database column
      // names (snake casing) with no codec columns, the collection's row shape.
      mutation.modified = row as typeof mutation.modified;
      // Awaiting a sync write inside the mutation function deadlocks: sync
      // commits queue behind it.
      void collection.utils.writeUpsert(mutation.modified);
    }

    return done;
  };

  const onUpdate: Handler<Schema, "onUpdate"> = async ({
    transaction,
    collection,
  }) => {
    const update = write("update");

    for (const mutation of transaction.mutations) {
      const row = await orThrow(
        update(idOf(mutation.original), mutation.changes),
      );

      if (!writeBack) {
        continue;
      }

      // SAFETY: as in onInsert, the updated row has the collection's row shape.
      mutation.modified = row as typeof mutation.modified;
      void collection.utils.writeUpdate(mutation.modified);
    }

    return done;
  };

  const onDelete: Handler<Schema, "onDelete"> = async ({
    transaction,
    collection,
  }) => {
    const remove = write("delete");

    for (const mutation of transaction.mutations) {
      await orThrow(remove(idOf(mutation.original)));

      if (!writeBack) {
        continue;
      }

      const key = collection.getKeyFromItem(mutation.original);

      // A row with a pending local delete is gone from has() but still synced.
      // oxlint-disable-next-line eslint/no-underscore-dangle -- TanStack DB exposes synced rows only on _state; @supabase-labs/tanstack-db reads the same field.
      if (collection._state.syncedData.has(key)) {
        void collection.utils.writeDelete(key);
      }
    }

    return done;
  };

  return { ...config, onInsert, onUpdate, onDelete };
}
