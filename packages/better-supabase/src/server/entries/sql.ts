import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { AuthState } from "../../auth/resolve.ts";
import type { Db } from "../../core/repository-types.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";

/** The keys `withSql` reads. */
export interface SqlIn<M extends AnyModels, F extends AnyFunctions, E, C, P> {
  readonly bs: {
    readonly auth: AuthState<C, P>;
    readonly sql: Db<M, F, E, undefined> | undefined;
  };
}

/**
 * Entry contributing `ctx.sql`: repositories over direct Postgres as the
 * caller, with RLS, from `createServer`'s `postgres`, else `undefined`.
 * `withPostgresClient` reads `jwtClaims`, so it runs after this entry and
 * can't back `ctx.sql`; importing the SQL compiler here would also ship it
 * to every app without Postgres.
 */
export function withSql<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(): SingleKeyEntry<
  "sql",
  SqlIn<M, F, E, C, P>,
  Db<M, F, E, undefined> | undefined
> {
  return defineMiddleware<
    "sql",
    undefined,
    SqlIn<M, F, E, C, P>,
    Db<M, F, E, undefined> | undefined
  >({
    key: "sql",
    run: () => (_request, ctx) => Promise.resolve({ sql: ctx.bs.sql }),
  })();
}
