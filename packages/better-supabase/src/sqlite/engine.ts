import type {
  DataChanges,
  DataEngine,
  LiveEngineOptions,
  LocalTablesOption,
} from "../bindings/data-engine.ts";
import type { Executor } from "../core/executor.ts";
import type { TableMeta } from "../schema/types.ts";
import type { SqliteDatabaseLike, SqliteExecutorOptions } from "./executor.ts";

import { localEngine } from "../bindings/data-engine.ts";
import { sqliteExecutor } from "./executor.ts";

/** A SQLite database that may report which tables changed. */
export interface ChangingSqliteDatabase extends SqliteDatabaseLike {
  onChange?(
    handler: {
      onChange: (event: { changedTables: string[] }) => Promise<void> | void;
    },
    options?: { tables?: string[]; throttleMs?: number; signal?: AbortSignal },
  ): () => void;
}

export interface SqliteEngineOptions
  extends
    Omit<SqliteExecutorOptions, "fallback">,
    LiveEngineOptions,
    LocalTablesOption {
  /**
   * Where reads are kept: `queryEngine(queryClient)` to share them with
   * TanStack Query. Default one in memory.
   */
  readonly cache?: DataEngine;
  /** The least time between two reads after changes. Default 30 ms. */
  readonly throttleMs?: number;
  /**
   * Reads that SQLite can't run and `db.$rpc` go to the server: the client's
   * PostgREST executor unless `fallback` names another. `false` keeps every
   * call local, for a database the app owns alone.
   */
  readonly fallback?: Executor | false;
}

/**
 * A UUID v4 from SQLite's `randomblob`, for runtimes without
 * `crypto.randomUUID`.
 */
const UUID_SQL =
  "select lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))) as id";

/** Hermes has no `crypto` unless the app installs a polyfill. */
function randomId(): string | undefined {
  // SAFETY: lib.dom types `crypto` as always present; Hermes may lack it.
  const { crypto } = globalThis as {
    readonly crypto?: { readonly randomUUID?: () => string };
  };

  return crypto?.randomUUID?.();
}

function newIdOn(
  database: SqliteDatabaseLike,
): (table: TableMeta) => Promise<string> {
  return async () => {
    const random = randomId();

    if (random !== undefined) {
      return random;
    }

    const [row] = await database.getAll<{ id: string }>(UUID_SQL);

    if (!row) {
      throw new TypeError("SQLite returned no id");
    }

    return row.id;
  };
}

/**
 * The tables `db` writes through the executor, for a database without change
 * events.
 */
function writeEvents(): DataChanges & {
  readonly wrap: (executor: Executor) => Executor;
} {
  const listeners = new Set<(tables: readonly string[]) => void>();

  return {
    subscribe: (onChange) => {
      listeners.add(onChange);

      return () => {
        listeners.delete(onChange);
      };
    },
    wrap: (executor) => ({
      ...executor,
      execute: async (op, context) => {
        const result = await executor.execute(op, context);

        if (result.ok && op.kind !== "select") {
          for (const listener of listeners) {
            listener([op.table.name]);
          }
        }

        return result;
      },
    }),
  };
}

/**
 * The data hooks and `db` on a SQLite database the app holds: Expo SQLite
 * (`expoSqliteDatabase`), Supabase Lite (`liteDatabase`) or any database in the
 * same shape. Reads return rows in the PostgREST shape and writes run locally.
 * The database's change events, or else `db`'s own writes, refresh every hook
 * that follows the table. An insert that leaves out a text or uuid key gets
 * `crypto.randomUUID()`, else a UUID from SQLite.
 *
 * ```ts
 * export const bsb = createNativeClient(betterSupabase, supabase, {
 *   engine: sqliteEngine(
 *     expoSqliteDatabase(sqlite, { addDatabaseChangeListener }),
 *   ),
 * });
 * ```
 */
export function sqliteEngine(
  database: ChangingSqliteDatabase,
  options: SqliteEngineOptions = {},
): DataEngine {
  const { cache, throttleMs, tables, local, fallback, ...executor } = options;

  const writes = database.onChange === undefined ? writeEvents() : undefined;

  const changes: DataChanges = writes ?? {
    subscribe: (onChange) =>
      database.onChange?.(
        {
          onChange: (event) => {
            onChange(event.changedTables);
          },
        },
        throttleMs === undefined ? {} : { throttleMs },
      ) ?? (() => undefined),
  };

  return localEngine({
    cache,
    changes,
    ...(tables === undefined ? {} : { tables }),
    ...(local === undefined ? {} : { local }),
    connect: (server) => {
      const onDevice = sqliteExecutor(database, {
        ...executor,
        newId: executor.newId ?? newIdOn(database),
        ...(fallback === false ? {} : { fallback: fallback ?? server }),
      });

      return writes === undefined ? onDevice : writes.wrap(onDevice);
    },
  });
}
