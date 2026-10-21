import type { SqliteCompilerOptions } from "../compile/sqlite.ts";
import type { Result } from "../core/result.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { PowerSyncDatabaseLike } from "./executor.ts";

import { err, toDbError } from "../core/result.ts";
import { shareStructure } from "../core/share.ts";

export interface WatchOptions<T> {
  /**
   * SQLite tables whose changes rerun the query (`sqliteTables()` maps app
   * keys).
   */
  readonly tables: readonly string[];
  /** Called with the first result, then after every change to `tables`. */
  readonly onResult: (result: Result<T>) => void;
  readonly signal?: AbortSignal;
  /** The least time between two runs. Defaults to PowerSync's 30 ms. */
  readonly throttleMs?: number;
  /**
   * Keeps unchanged rows' object identity across runs and skips `onResult` when
   * a run returns what the last one did. Defaults to true.
   */
  readonly structuralSharing?: boolean;
  /**
   * Reruns that don't wait for a local change, for reads that run on the
   * executor's server `fallback`: `everyMs` reruns on an interval (skipped
   * while PowerSync reports it is offline), and `onReconnect` reruns when
   * PowerSync connects again. `onReconnect` needs `registerListener()`.
   */
  readonly refresh?: {
    readonly everyMs?: number;
    readonly onReconnect?: boolean;
  };
}

/**
 * Reruns a repository call whenever PowerSync reports a change to one of
 * `tables`: local writes and synced rows alike. The same call works with lists,
 * aggregates and single rows. Unchanged rows keep their identity between runs,
 * and a run that changes nothing calls no `onResult`. Returns a function that
 * stops it.
 *
 * ```ts
 * const stop = watch(powersync, () => customerList.run(db, query), {
 *   tables: ["customers"],
 *   onResult: (page) => render(page),
 * });
 * ```
 */
export function watch<T>(
  db: PowerSyncDatabaseLike,
  query: () => PromiseLike<Result<T>>,
  options: WatchOptions<T>,
): () => void {
  if (!db.onChange) {
    throw new TypeError(
      "better-supabase: watch() needs a PowerSync database with onChange()",
    );
  }

  const refresh = options.refresh ?? {};

  if (refresh.onReconnect && !db.registerListener) {
    throw new TypeError(
      "better-supabase: watch() refresh.onReconnect needs a PowerSync database with registerListener()",
    );
  }

  const signal = options.signal;

  if (signal?.aborted) {
    return () => undefined;
  }

  const controller = new AbortController();

  const stop = (): void => {
    controller.abort();
  };

  signal?.addEventListener("abort", stop, { once: true });
  let latest = 0;
  let previous: Result<T> | undefined;
  const sharing = options.structuralSharing ?? true;

  const rerun = async (): Promise<void> => {
    latest += 1;
    const run = latest;
    let result: Result<T>;

    try {
      result = await query();
    } catch (cause) {
      result = err(toDbError(cause));
    }

    if (run !== latest || controller.signal.aborted) {
      return;
    }

    if (sharing) {
      const shared = shareStructure(previous, result);

      if (shared === previous) {
        return;
      }

      result = shared;
    }

    previous = result;
    options.onResult(result);
  };

  void rerun();

  const unsubscribe = db.onChange(
    { onChange: rerun },
    {
      tables: [...options.tables],
      signal: controller.signal,
      ...(options.throttleMs === undefined
        ? {}
        : { throttleMs: options.throttleMs }),
    },
  );

  const timer =
    refresh.everyMs === undefined
      ? undefined
      : setInterval(() => {
          if (db.currentStatus?.connected === false) {
            return;
          }

          void rerun();
        }, refresh.everyMs);

  let connected = db.currentStatus?.connected ?? true;

  const unlisten =
    refresh.onReconnect && db.registerListener
      ? db.registerListener({
          statusChanged: (status) => {
            const reconnected = status.connected && !connected;
            connected = status.connected;

            if (reconnected) {
              void rerun();
            }
          },
        })
      : undefined;

  const cleanup = (): void => {
    clearInterval(timer);
    unlisten?.();
  };

  controller.signal.addEventListener("abort", cleanup, { once: true });

  return () => {
    signal?.removeEventListener("abort", stop);
    stop();
    unsubscribe();
  };
}

/**
 * The SQLite table names of app table keys (`customerTags` to `customer_tags`).
 * Pass the executor's `tableName` when it renames tables, so `watch` listens to
 * the names the queries read.
 */
export function sqliteTables(
  betterSupabase: { readonly meta: SchemaMeta },
  keys: readonly string[],
  options: SqliteCompilerOptions = {},
): string[] {
  return keys.map((key) => {
    const table = betterSupabase.meta.tables[key];

    if (!table) {
      throw new TypeError(`better-supabase: unknown table "${key}"`);
    }

    return options.tableName ? options.tableName(table) : table.name;
  });
}
