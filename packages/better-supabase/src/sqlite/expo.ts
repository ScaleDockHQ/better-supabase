import type { ChangingSqliteDatabase } from "./engine.ts";
import type { SqliteContextLike } from "./executor.ts";

/** What an expo-sqlite database or exclusive transaction can run. */
export interface ExpoSqliteContextLike {
  getAllAsync<T>(source: string, params: unknown[]): Promise<T[]>;
  runAsync(source: string, params: unknown[]): Promise<unknown>;
}

/**
 * The part of expo-sqlite's `SQLiteDatabase` the executor uses. Typed by shape,
 * so better-supabase doesn't depend on expo-sqlite.
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
 * Expo-sqlite's `addDatabaseChangeListener`. Open the database with `{
 * enableChangeListener: true }` so it reports changes.
 */
export type AddDatabaseChangeListener = (
  listener: (event: DatabaseChangeEventLike) => void,
) => { remove(): void };

export interface ExpoSqliteOptions {
  /**
   * Reports the database's changes, so the engine reads followed sources again
   * after writes from elsewhere (a sync job, another screen's `db`).
   */
  readonly addDatabaseChangeListener?: AddDatabaseChangeListener;
}

const DEFAULT_THROTTLE_MS = 30;

function contextOf(db: ExpoSqliteContextLike): SqliteContextLike {
  return {
    getAll: (sql, parameters = []) => db.getAllAsync(sql, parameters),
    execute: (sql, parameters = []) => db.runAsync(sql, parameters),
  };
}

function changesOf(
  db: ExpoSqliteDatabaseLike,
  addListener: AddDatabaseChangeListener,
): NonNullable<ChangingSqliteDatabase["onChange"]> {
  return (handler, options = {}) => {
    const tables = options.tables ? new Set(options.tables) : undefined;
    const throttleMs = options.throttleMs ?? DEFAULT_THROTTLE_MS;
    let pending = new Set<string>();
    let timer: ReturnType<typeof setTimeout> | undefined;

    const flush = (): void => {
      timer = undefined;
      const changedTables = [...pending];
      pending = new Set();

      if (changedTables.length > 0) {
        void handler.onChange({ changedTables });
      }
    };

    const subscription = addListener((event) => {
      if (
        event.databaseFilePath !== undefined &&
        db.databasePath !== undefined &&
        event.databaseFilePath !== db.databasePath
      ) {
        return;
      }

      if (tables && !tables.has(event.tableName)) {
        return;
      }

      pending.add(event.tableName);
      timer ??= setTimeout(flush, throttleMs);
    });

    const stop = (): void => {
      subscription.remove();

      if (timer !== undefined) {
        clearTimeout(timer);
      }

      timer = undefined;
      pending = new Set();
    };

    options.signal?.addEventListener("abort", stop, { once: true });

    return stop;
  };
}

/**
 * An expo-sqlite database in the shape `sqliteEngine` reads. Writes run in
 * `withExclusiveTransactionAsync` on native and `withTransactionAsync` on web.
 *
 * ```ts
 * const sqlite = await openDatabaseAsync("app.db", {
 *   enableChangeListener: true,
 * });
 * const engine = sqliteEngine(
 *   expoSqliteDatabase(sqlite, { addDatabaseChangeListener }),
 * );
 * ```
 */
export function expoSqliteDatabase(
  db: ExpoSqliteDatabaseLike,
  options: ExpoSqliteOptions = {},
): ChangingSqliteDatabase {
  const context = contextOf(db);

  const database: ChangingSqliteDatabase = {
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

      if (!box) {
        throw new TypeError("expo-sqlite skipped the transaction");
      }

      return box.value;
    },
  };

  const addListener = options.addDatabaseChangeListener;

  return addListener
    ? { ...database, onChange: changesOf(db, addListener) }
    : database;
}
