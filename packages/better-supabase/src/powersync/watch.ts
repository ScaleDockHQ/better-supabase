import type { Result } from "../core/result.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { PowerSyncDatabaseLike } from "./executor.ts";

import { err, toDbError } from "../core/result.ts";

export interface WatchOptions<T> {
  /** SQLite tables whose changes rerun the query (`sqliteTables()` maps app keys). */
  readonly tables: readonly string[];
  /** Called with the first result, then after every change to `tables`. */
  readonly onResult: (result: Result<T>) => void;
  readonly signal?: AbortSignal;
  /** The least time between two runs. Defaults to PowerSync's 30 ms. */
  readonly throttleMs?: number;
}

/**
 * Reruns a repository call whenever PowerSync reports a change to one of
 * `tables`: local writes and synced rows alike. The same call works with
 * lists, aggregates and single rows. Returns a function that stops it.
 *
 * ```ts
 * const stop = watch(powersync, () => customerList.run(db, query), {
 *   tables: ['customers'],
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
  const signal = options.signal;
  if (signal?.aborted) return () => undefined;
  const controller = new AbortController();
  const stop = (): void => {
    controller.abort();
  };
  signal?.addEventListener("abort", stop, { once: true });
  let latest = 0;
  const rerun = async (): Promise<void> => {
    latest += 1;
    const run = latest;
    let result: Result<T>;
    try {
      result = await query();
    } catch (cause) {
      result = err(toDbError(cause));
    }
    if (run === latest && !controller.signal.aborted) options.onResult(result);
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
  return () => {
    signal?.removeEventListener("abort", stop);
    stop();
    unsubscribe();
  };
}

/** The SQLite table names of app table keys (`customerTags` to `customer_tags`). */
export function sqliteTables(
  betterSupabase: { readonly meta: SchemaMeta },
  keys: readonly string[],
): string[] {
  return keys.map((key) => {
    const table = betterSupabase.meta.tables[key];
    if (!table) throw new TypeError(`better-supabase: unknown table "${key}"`);
    return table.name;
  });
}
