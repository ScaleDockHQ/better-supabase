import type { SqliteCompilerOptions, SqlitePlan } from "../compile/sqlite.ts";
import type { Compiler } from "../core/compiler.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { DbError } from "../core/errors.ts";
import type { ExecuteResult, Executor } from "../core/executor.ts";
import type { Result } from "../core/result.ts";
import type { ListDefinition, ListQuery } from "../list/list-query.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";

import { compileSqlite } from "../compile/sqlite.ts";
import { err, ok, toDbError } from "../core/result.ts";

export const sqliteCompiler: Compiler<SqlitePlan> = {
  target: "sqlite",
  compile: (op) => compileSqlite(op),
};

export interface CheckSqliteOptions extends SqliteCompilerOptions {
  /**
   * Return every error instead of the first, one per distinct message. With a
   * `fallback` executor, these are the reads that run on the server.
   */
  readonly all?: boolean;
}

/**
 * Compiles every operation a list definition runs (the page, its count and the
 * facet counts) for SQLite, without a database. Returns the first `unsupported`
 * or `invalid_request` error, so a test or a dev build fails before a native
 * screen does. With `all: true`, returns every error, an empty array when the
 * whole list runs on SQLite.
 *
 * ```ts
 * expect(await checkSqlite(betterSupabase, customerList)).toEqual({
 *   ok: true,
 *   data: undefined,
 * });
 * expect(
 *   await checkSqlite(betterSupabase, customerList, { all: true }),
 * ).toEqual([]);
 * ```
 */
export async function checkSqlite<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  T extends TableKey<M>,
  S extends string,
  Fa extends string,
  C extends boolean,
  P extends "offset" | "cursor",
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  list: ListDefinition<M, T, E, S, Fa, C, P>,
  options: CheckSqliteOptions & { readonly all: true },
): Promise<readonly DbError[]>;
export async function checkSqlite<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  T extends TableKey<M>,
  S extends string,
  Fa extends string,
  C extends boolean,
  P extends "offset" | "cursor",
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  list: ListDefinition<M, T, E, S, Fa, C, P>,
  options?: CheckSqliteOptions & { readonly all?: false },
): Promise<Result<undefined>>;
export async function checkSqlite<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  T extends TableKey<M>,
  S extends string,
  Fa extends string,
  C extends boolean,
  P extends "offset" | "cursor",
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  list: ListDefinition<M, T, E, S, Fa, C, P>,
  options: CheckSqliteOptions = {},
): Promise<Result<undefined> | readonly DbError[]> {
  const failures = new Map<string, DbError>();

  const probe: Executor = {
    name: "sqlite-check",
    execute(op): Promise<Result<ExecuteResult>> {
      try {
        compileSqlite(op, options);
      } catch (cause) {
        const failure = toDbError(cause);

        if (!failures.has(failure.message)) {
          failures.set(failure.message, failure);
        }

        return Promise.resolve(err(failure));
      }

      return Promise.resolve(ok({ rows: [], count: 0 }));
    },
  };

  const facets: Record<string, readonly string[]> = {};

  for (const facet of list.facets) {
    facets[facet.key] = [facet.values?.[0] ?? "x"];
  }

  // SAFETY: the keys come from list.facets, which is keyed by the facet keys Fa.
  const query = { ...list.defaults, q: "x", facets } as ListQuery<S, Fa>;

  const db = betterSupabase.connect(probe);
  await list.run(db, query);

  // An operation stops compiling at its first unsupported feature, so a
  // search term would hide the features the rest of the list needs.
  if (options.all) {
    await list.run(db, list.defaults);
  }

  const found = [...failures.values()];

  if (options.all) {
    return found;
  }

  const [first] = found;

  return first ? err(first) : ok(undefined);
}
