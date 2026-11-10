import type { BetterPostgres, PostgresOptions } from "./pool.ts";

import { connectionStringOf, createPostgres } from "./pool.ts";

const REGISTRY = Symbol.for("better-supabase.sharedPostgres");

type Registry = Map<string, BetterPostgres>;

function registry(): Registry {
  // SAFETY: the registry lives under a symbol only this module writes.
  const holder = globalThis as { [REGISTRY]?: Registry };

  return (holder[REGISTRY] ??= new Map());
}

/**
 * One pool per process and connection string. A second call with the same
 * string (another module, a hot reload, a route and a job) gets the pool the
 * first one opened instead of a second set of connections, so two servers in
 * one process never double the connections Postgres sees. The first call's
 * options win. `end()` closes the pool and the next call opens a new one.
 *
 * Calls with `pool` or `events` options are not shared: they bring their own
 * pool or their own event hub, and `createPostgres` is the right call.
 */
export function sharedPostgres(options: PostgresOptions = {}): BetterPostgres {
  const target = connectionStringOf(options);

  if (target === undefined || options.pool !== undefined) {
    return createPostgres(options);
  }

  const key = `${target}|${String(options.max ?? "")}`;
  const found = registry().get(key);

  if (found) {
    return found;
  }

  const opened = createPostgres(options);

  const shared: BetterPostgres = {
    admin: opened.admin,
    anon: opened.anon,
    asUser: (claims, session) => opened.asUser(claims, session),
    executorFor: (claims, session) => opened.executorFor(claims, session),
    ...(opened.transactionFor
      ? {
          transactionFor: (claims, fn, session) =>
            opened.transactionFor!(claims, fn, session),
        }
      : {}),
    transaction: (fn, session) => opened.transaction(fn, session),
    end: async () => {
      registry().delete(key);
      await opened.end();
    },
    [Symbol.asyncDispose]: async () => {
      registry().delete(key);
      await opened.end();
    },
  };

  registry().set(key, shared);

  return shared;
}
