import type { Executor } from "../core/executor.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { BetterPostgres, SqlClaims } from "../postgres/pool.ts";
import type { TransactionOptions } from "./server-types.ts";

import { provideConnectionRuntime } from "../core/define-runtime-full.ts";

provideConnectionRuntime();

class RolledBack extends Error {}

function isFailedResult(value: unknown): boolean {
  return (
    typeof value === "object" &&
    value !== null &&
    "ok" in value &&
    value.ok === false
  );
}

/**
 * `server.transaction`: runs `fn` as the user on a `Db` bound to one
 * transaction. A throw rolls back; so does a returned failed `Result`, which is
 * still returned.
 */
async function runServerTransaction<D, T>(
  postgres: BetterPostgres | undefined,
  connect: (executor: Executor, context: RequestContext) => D,
  userId: string,
  fn: (db: D) => Promise<T>,
  options: TransactionOptions = {},
): Promise<T> {
  if (!postgres?.transactionFor) {
    throw new TypeError(
      "server.transaction needs createServer(betterSupabase, { postgres: createPostgres() })",
    );
  }

  const claims: SqlClaims = {
    role: "authenticated",
    ...options.claims,
    sub: userId,
  };

  let failed: { readonly value: T } | undefined;

  try {
    return await postgres.transactionFor<T>(
      claims,
      async (executor) => {
        const value = await fn(
          connect(executor, {
            actor: {
              id: userId,
              kind: "user",
              role: claims.role ?? "authenticated",
            },
            claims,
            ...(options.tenant === undefined ? {} : { tenant: options.tenant }),
          }),
        );

        if (isFailedResult(value)) {
          failed = { value };
          throw new RolledBack();
        }

        return value;
      },
      options.session,
    );
  } catch (cause) {
    if (cause instanceof RolledBack && failed) {
      return failed.value;
    }

    throw cause;
  }
}

export function serverTransaction<D>(
  postgres: BetterPostgres | undefined,
  betterSupabase: { connect(executor: Executor, context: RequestContext): D },
): <T>(
  userId: string,
  fn: (db: D) => Promise<T>,
  options?: TransactionOptions,
) => Promise<T> {
  return (userId, fn, options) =>
    runServerTransaction(
      postgres,
      (executor, context) => betterSupabase.connect(executor, context),
      userId,
      fn,
      options,
    );
}
