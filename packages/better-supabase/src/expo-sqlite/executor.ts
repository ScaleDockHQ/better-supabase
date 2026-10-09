import type { Executor } from "../core/executor.ts";
import type {
  PowerSyncDatabaseLike,
  PowerSyncExecutorOptions,
  SqliteContextLike,
} from "../powersync/executor.ts";
import type { TableMeta } from "../schema/types.ts";

import { powersyncExecutor } from "../powersync/executor.ts";

/** What an expo-sqlite database or exclusive transaction can run. */
export interface ExpoSqliteContextLike {
  getAllAsync<T>(source: string, params: unknown[]): Promise<T[]>;
  runAsync(source: string, params: unknown[]): Promise<unknown>;
}

/**
 * The part of expo-sqlite's `SQLiteDatabase` the executor uses. Typed by
 * shape, so better-supabase doesn't depend on expo-sqlite.
 */
export interface ExpoSqliteDatabaseLike extends ExpoSqliteContextLike {
  /** Filters change events to this database when several are open. */
  readonly databasePath?: string;
  withTransactionAsync(task: () => Promise<void>): Promise<void>;
  /** Native only: isolates the transaction from other queries on `db`. */
  withExclusiveTransactionAsync?(
    task: (txn: ExpoSqliteContextLike) => Promise<void>,
  ): Promise<void>;
}

/** The fields of an expo-sqlite change event the watcher reads. */
export interface DatabaseChangeEventLike {
  readonly tableName: string;
  readonly databaseFilePath?: string;
}

/**
 * expo-sqlite's `addDatabaseChangeListener`. Open the database with
 * `{ enableChangeListener: true }` so it reports changes.
 */
export type AddDatabaseChangeListener = (
  listener: (event: DatabaseChangeEventLike) => void,
) => { remove(): void };

export interface ExpoSqliteOptions extends PowerSyncExecutorOptions {
  /** Enables `watch()` and `useWatch()` on the database. */
  readonly addDatabaseChangeListener?: AddDatabaseChangeListener;
}

const DEFAULT_THROTTLE_MS = 30;

/** A UUID v4 from SQLite's `randomblob`, for runtimes without `crypto.randomUUID`. */
const UUID_SQL =
  "select lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))) as id";

function contextOf(db: ExpoSqliteContextLike): SqliteContextLike {
  return {
    getAll: (sql, parameters = []) => db.getAllAsync(sql, parameters),
    execute: (sql, parameters = []) => db.runAsync(sql, parameters),
  };
}

function changesOf(
  db: ExpoSqliteDatabaseLike,
  addListener: AddDatabaseChangeListener,
): NonNullable<PowerSyncDatabaseLike["onChange"]> {
  return (handler, options = {}) => {
    const tables = options.tables ? new Set(options.tables) : undefined;
    const throttleMs = options.throttleMs ?? DEFAULT_THROTTLE_MS;
    let pending = new Set<string>();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const flush = (): void => {
      timer = undefined;
      const changedTables = [...pending];
      pending = new Set();
      if (changedTables.length > 0) void handler.onChange({ changedTables });
    };
    const subscription = addListener((event) => {
      if (
        event.databaseFilePath !== undefined &&
        db.databasePath !== undefined &&
        event.databaseFilePath !== db.databasePath
      )
        return;
      if (tables && !tables.has(event.tableName)) return;
      pending.add(event.tableName);
      timer ??= setTimeout(flush, throttleMs);
    });
    const stop = (): void => {
      subscription.remove();
      if (timer !== undefined) clearTimeout(timer);
      timer = undefined;
      pending = new Set();
    };
    options.signal?.addEventListener("abort", stop, { once: true });
    return stop;
  };
}

/**
 * An expo-sqlite database in the shape the SQLite executor, `watch()` and
 * `useWatch()` read. Writes run in `withExclusiveTransactionAsync` on
 * native and `withTransactionAsync` on web.
 */
export function expoSqliteDatabase(
  db: ExpoSqliteDatabaseLike,
  options: Pick<ExpoSqliteOptions, "addDatabaseChangeListener"> = {},
): PowerSyncDatabaseLike {
  const context = contextOf(db);
  const database: PowerSyncDatabaseLike = {
    ...context,
    async writeTransaction<T>(
      callback: (tx: SqliteContextLike) => Promise<T>,
    ): Promise<T> {
      let box: { readonly value: T } | undefined;
      if (db.withExclusiveTransactionAsync) {
        await db.withExclusiveTransactionAsync(async (txn) => {
          box = { value: await callback(contextOf(txn)) };
        });
      } else {
        await db.withTransactionAsync(async () => {
          box = { value: await callback(context) };
        });
      }
      if (!box) throw new TypeError("expo-sqlite skipped the transaction");
      return box.value;
    },
  };
  const addListener = options.addDatabaseChangeListener;
  return addListener
    ? { ...database, onChange: changesOf(db, addListener) }
    : database;
}

/** Hermes has no `crypto` unless the app installs a polyfill. */
function randomId(): string | undefined {
  // SAFETY: lib.dom types `crypto` as always present; Hermes may lack it.
  const { crypto } = globalThis as {
    readonly crypto?: { readonly randomUUID?: () => string };
  };
  return crypto?.randomUUID?.();
}

/**
 * Runs repository operations on an expo-sqlite database, without PowerSync:
 * the same repositories and list definitions work on a local database the
 * app owns. Reads return rows in the PostgREST shape; what SQLite can't
 * express returns a `DbError` of kind `unsupported`. An insert that leaves
 * out a text or uuid key gets `crypto.randomUUID()`, else a UUID from
 * SQLite.
 *
 * ```ts
 * const sqlite = await openDatabaseAsync("app.db", { enableChangeListener: true });
 * const db = betterSupabase.connect(expoSqliteExecutor(sqlite, { addDatabaseChangeListener }));
 * ```
 */
export function expoSqliteExecutor(
  db: ExpoSqliteDatabaseLike,
  options: ExpoSqliteOptions = {},
): Executor {
  const database = expoSqliteDatabase(db, options);
  const newId =
    options.newId ??
    (async (_table: TableMeta): Promise<string> => {
      const random = randomId();
      if (random !== undefined) return random;
      const [row] = await database.getAll<{ id: string }>(UUID_SQL);
      if (!row) throw new TypeError("SQLite returned no id");
      return row.id;
    });
  return {
    ...powersyncExecutor(database, { ...options, newId }),
    name: "expo-sqlite",
  };
}
