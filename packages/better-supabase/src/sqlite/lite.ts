import type { ChangingSqliteDatabase } from "./engine.ts";
import type { SqliteContextLike } from "./executor.ts";

/**
 * The part of a Supabase Lite SQLite connection (`createConnection` from
 * `@supabase/lite/sqlite`) the engine uses. Typed by shape, so better-supabase
 * doesn't depend on Supabase Lite.
 */
export interface LiteConnectionLike {
  exec<T = { rows: unknown[] }>(
    query: string,
    ...parameters: readonly unknown[]
  ): Promise<T>;
}

/**
 * A Supabase Lite SQLite connection in the shape `sqliteEngine` reads, so an
 * app that embeds Lite runs its data hooks and `db` on the same file. Write
 * transactions run one at a time.
 *
 * ```ts
 * const connection = await createConnection({ url: "file:app.db" });
 * const engine = sqliteEngine(liteDatabase(connection), {
 *   fallback: false,
 * });
 * ```
 */
export function liteDatabase(
  connection: LiteConnectionLike,
): ChangingSqliteDatabase {
  const context: SqliteContextLike = {
    getAll: async <T>(sql: string, parameters: unknown[] = []) => {
      const result = await connection.exec<{ rows?: unknown[] } | undefined>(
        sql,
        ...parameters,
      );

      // SAFETY: the caller names the row shape its SQL selects.
      return (result?.rows ?? []) as T[];
    },
    execute: (sql, parameters = []) => connection.exec(sql, ...parameters),
  };

  let queue: Promise<unknown> = Promise.resolve();

  return {
    ...context,
    writeTransaction: <T>(
      callback: (tx: SqliteContextLike) => Promise<T>,
    ): Promise<T> => {
      const run = async (): Promise<T> => {
        await connection.exec("begin");

        try {
          const value = await callback(context);
          await connection.exec("commit");

          return value;
        } catch (error) {
          await connection.exec("rollback");
          throw error;
        }
      };

      const next = queue.then(run, run);
      queue = next.catch(() => undefined);

      return next;
    },
  };
}
