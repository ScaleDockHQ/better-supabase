import type { Executor } from "../core/executor.ts";
import type {
  SqliteDatabaseLike,
  SqliteExecutorOptions,
} from "../sqlite/executor.ts";

import { sqliteExecutor } from "../sqlite/executor.ts";

export {
  fromSqliteError,
  postgrestTimestamp,
  type SqliteContextLike,
} from "../sqlite/executor.ts";

/**
 * The part of `PowerSyncDatabase` (`@powersync/react-native`,
 * `@powersync/web`, `@powersync/node`) the executor uses. Typed by shape,
 * so better-supabase doesn't depend on PowerSync.
 */
export interface PowerSyncDatabaseLike extends SqliteDatabaseLike {
  onChange?(
    handler: {
      onChange: (event: { changedTables: string[] }) => Promise<void> | void;
    },
    options?: {
      tables?: string[];
      throttleMs?: number;
      signal?: AbortSignal;
    },
  ): () => void;
}

export type PowerSyncExecutorOptions = SqliteExecutorOptions;

/**
 * Runs repository operations on PowerSync's local SQLite database, so the
 * same repositories and list definitions work offline on native. Reads
 * return rows in the PostgREST shape (booleans, parsed JSON, ISO
 * timestamps); writes go through PowerSync's upload queue. What SQLite
 * can't express (includes, full-text search, function sources) and
 * `db.$rpc` return a `DbError` of kind `unsupported` without running
 * anything, or run on `options.fallback` when you pass one.
 * `maxAffected` is checked against the selected keys before any write; a
 * call's `timeout` and `signal` are checked before the statements start,
 * and `retry` does nothing here. A `bigint` beyond `Number.MAX_SAFE_INTEGER`
 * comes back as its decimal string instead of a rounded number.
 *
 * ```ts
 * const db = betterSupabase.connect(
 *   powersyncExecutor(powersync, { fallback: postgrestExecutor(supabase) }),
 * );
 * ```
 */
export function powersyncExecutor(
  db: PowerSyncDatabaseLike,
  options: PowerSyncExecutorOptions = {},
): Executor {
  return sqliteExecutor(db, options, "powersync");
}
