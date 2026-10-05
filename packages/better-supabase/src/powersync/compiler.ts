import type { Compiler } from "../core/compiler.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { DbError } from "../core/errors.ts";
import type { ExecuteResult, Executor } from "../core/executor.ts";
import type { ListDefinition, ListQuery } from "../list/list-query.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";

import {
  compileSqlite,
  type SqliteCompilerOptions,
  type SqlitePlan,
} from "../compile/sqlite.ts";
import { err, ok, type Result, toDbError } from "../core/result.ts";

export const sqliteCompiler: Compiler<SqlitePlan> = {
  target: "sqlite",
  compile: (op) => compileSqlite(op),
};

/**
 * Compiles every operation a list definition runs (the page, its count and
 * the facet counts) for SQLite, without a database. Returns the first
 * `unsupported` or `invalid_request` error, so a test or a dev build fails
 * before a native screen does.
 *
 * ```ts
 * expect(await checkSqlite(betterSupabase, customerList)).toEqual({ ok: true, data: undefined });
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
  options: SqliteCompilerOptions = {},
): Promise<Result<undefined>> {
  let failure: DbError | undefined;
  const probe: Executor = {
    name: "sqlite-check",
    execute(op): Promise<Result<ExecuteResult>> {
      try {
        compileSqlite(op, options);
      } catch (cause) {
        failure ??= toDbError(cause);
        return Promise.resolve(err(failure));
      }
      return Promise.resolve(ok({ rows: [], count: 0 }));
    },
  };
  const facets: Record<string, readonly string[]> = {};
  for (const facet of list.facets)
    facets[facet.key] = [facet.values?.[0] ?? "x"];
  // SAFETY: the keys come from list.facets, which is keyed by the facet keys Fa.
  const query = {
    ...list.defaults,
    q: "x",
    facets,
  } as ListQuery<S, Fa>;
  const db = betterSupabase.connect(probe);
  await list.run(db, query);
  return failure ? err(failure) : ok(undefined);
}
