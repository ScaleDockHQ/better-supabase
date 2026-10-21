import { createClient } from "@supabase/supabase-js";

import type { Db } from "../core/repository-types.ts";
import type { SqlClient } from "../postgres/executor.ts";
import type { BetterPostgres, SqlClaims } from "../postgres/pool.ts";
import type {
  AnyFunctions,
  AnyModels,
  Insert,
  Row,
  TableKey,
} from "../schema/types.ts";
import type { LocalStack, TestUser } from "./as-user.ts";
import type { ExactSeed, SeedFixtures } from "./seed.ts";

import { BetterSupabase } from "../core/define.ts";
import { ENV_VARIABLES } from "../env/index.ts";
import { internalsOf } from "./as-user.ts";
import { order } from "./seed.ts";

/** What a `scopedSeed` builder receives for one test. */
export interface Scope {
  /** The id of this test's fresh tenant. */
  readonly tenant: string;
  /** A new UUID, for rows that other fixtures reference. */
  id(): string;
}

/** The row that stands for the tenant, inserted before any fixture. */
export type ScopedTenant<M extends AnyModels> = {
  readonly [K in TableKey<M>]: {
    readonly table: K;
    readonly row: (id: string) => Insert<M, K>;
  };
}[TableKey<M>];

export interface ScopedSeedOptions<M extends AnyModels> {
  /**
   * The table and row for the tenant; leave it out when the tenant is only an
   * id.
   */
  readonly tenant?: ScopedTenant<M>;
  /** Defaults to `$SUPABASE_URL` and `$SUPABASE_SECRET_KEY`. */
  readonly stack?: LocalStack;
}

/** The rows a `scopedSeed` inserted, as the database returned them. */
export type ScopedRows<M extends AnyModels, S> = {
  readonly [K in keyof S & keyof M]: {
    readonly [N in keyof S[K]]: Row<M, K>;
  };
};

export interface ScopedSeed<M extends AnyModels, S> {
  readonly tenant: string;
  readonly rows: ScopedRows<M, S>;
  /** Deletes the rows in reverse order of creation, the tenant row last. */
  cleanup(): Promise<void>;
  [Symbol.asyncDispose](): Promise<void>;
}

type Rows = Readonly<Record<string, unknown>>;

interface Repository {
  create(
    row: unknown,
  ): PromiseLike<
    | { readonly ok: true; readonly data: unknown }
    | { readonly ok: false; readonly error: { readonly message: string } }
  >;
  deleteMany(args: object): PromiseLike<unknown>;
}

function env(names: readonly string[]): string | undefined {
  if (typeof process === "undefined") {
    return undefined;
  }

  for (const name of names) {
    const value = process.env[name];

    if (value) {
      return value;
    }
  }

  return undefined;
}

/**
 * Fresh rows for one test, so tests that run at the same time never share data.
 * It creates a new tenant id, inserts the fixtures that `build` returns through
 * the service role (RLS and plugins don't apply), and hands back the inserted
 * rows. Call `cleanup()` in `afterEach` (or `await using`) to delete them. A
 * user from `asUser` then reads them over PostgREST like any other.
 *
 * ```ts
 * const scope = await scopedSeed(
 *   betterSupabase,
 *   ({ tenant, id }) => ({
 *     customers: {
 *       first: { organizationId: tenant, name: `first-${id()}` },
 *     },
 *   }),
 *   {
 *     tenant: {
 *       table: "organizations",
 *       row: (id) => ({ id, name: id, slug: id }),
 *     },
 *   },
 * );
 * const alice = await asUser(betterSupabase, {
 *   sub: aliceId,
 *   tenant_id: scope.tenant,
 * });
 * expect(await alice.db.customers.count().orThrow()).toBe(1);
 * await scope.cleanup();
 * ```
 */
export async function scopedSeed<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  const S extends SeedFixtures<M>,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  build: (scope: Scope) => S & ExactSeed<M, S>,
  options: ScopedSeedOptions<M> = {},
): Promise<ScopedSeed<M, S>> {
  const stack = options.stack ?? {};
  const url = stack.url ?? env(ENV_VARIABLES.url) ?? "http://127.0.0.1:54321";
  const secretKey = stack.secretKey ?? env(ENV_VARIABLES.secretKey);

  if (!secretKey) {
    throw new TypeError(
      "scopedSeed needs stack.secretKey or $SUPABASE_SECRET_KEY to insert rows.",
    );
  }

  const bare = new BetterSupabase(betterSupabase.schema);

  // SAFETY: repositories are indexed by table name; the helper only uses the tables it was given.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the helper indexes repositories by table name for any schema.
  const admin = bare.connect(
    createClient(url, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
  ) as unknown as Readonly<Record<string, Repository>>;

  const tenant = crypto.randomUUID();
  const fixtures = build({ tenant, id: () => crypto.randomUUID() });
  const cleanup: (() => PromiseLike<unknown>)[] = [];

  const insert = async (table: string, row: unknown): Promise<unknown> => {
    const repository = admin[table];

    if (!repository) {
      throw new TypeError(`scopedSeed: unknown table "${table}"`);
    }

    const result = await repository.create(row);

    if (!result.ok) {
      throw new Error(`scopedSeed ${table}: ${result.error.message}`);
    }

    const meta = bare.meta.tables[table];
    // SAFETY: create returns the inserted row.
    const created = result.data as Rows;

    if (meta && meta.primaryKey.length > 0) {
      const where = Object.fromEntries(
        meta.primaryKey.map((column) => [column, created[column]]),
      );

      cleanup.push(() => repository.deleteMany({ where }));
    }

    return created;
  };

  const remove = async (): Promise<void> => {
    const pending = cleanup.splice(0).reverse();
    let failure: unknown;

    for (const run of pending) {
      try {
        await run();
      } catch (error) {
        failure ??= error;
      }
    }

    if (failure !== undefined) {
      throw failure instanceof Error ? failure : new Error(String(failure));
    }
  };

  const rows: Record<string, Record<string, unknown>> = {};

  try {
    if (options.tenant) {
      await insert(options.tenant.table, options.tenant.row(tenant));
    }

    // SAFETY: SeedFixtures maps table keys to named rows.
    const byTable = fixtures as Readonly<
      Record<string, Readonly<Record<string, unknown>>>
    >;

    for (const key of order(
      bare.meta,
      Object.keys(byTable).filter((name) => byTable[name] !== undefined),
    )) {
      rows[key] = {};

      for (const [name, row] of Object.entries(byTable[key] ?? {})) {
        rows[key][name] = await insert(key, row);
      }
    }
  } catch (error) {
    await remove().catch(() => undefined);
    throw error;
  }

  return {
    tenant,
    // SAFETY: rows holds one inserted row per fixture, keyed like the fixtures.
    rows: rows as ScopedRows<M, S>,
    cleanup: remove,
    [Symbol.asyncDispose]: remove,
  };
}

/**
 * The error `withRollback` throws to end its transaction; never reaches
 * callers.
 */
class Rollback extends Error {}

/**
 * Runs `fn` as the user over direct Postgres inside one transaction and always
 * rolls it back, so the test leaves no rows behind. `fn` gets the same
 * repositories as `user.sql`. Only the `sql` path rolls back: `user.db` talks
 * to PostgREST over HTTP and commits on its own.
 *
 * ```ts
 * const alice = await asUser(betterSupabase, claims, { postgres });
 * await withRollback(alice, async (db) => {
 *   await db.customers.create({ organizationId, name: "Temp" }).orThrow();
 *   expect(await db.customers.count().orThrow()).toBe(1);
 * });
 * ```
 */
export async function withRollback<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  T,
>(
  user: TestUser<M, F, E>,
  fn: (db: Db<M, F, E, unknown>) => Promise<T>,
): Promise<T> {
  const internal = internalsOf(user);

  if (!internal?.postgres) {
    throw new TypeError(
      "withRollback needs a user from asUser(betterSupabase, claims, { postgres }): it rolls back over direct Postgres, not PostgREST.",
    );
  }

  return rolledBack(internal.postgres, internal.claims, async (client) => {
    // SAFETY: connect builds the repositories asUser gave this user, over the transaction's client.
    const db = internal.connect(client) as Db<M, F, E, unknown>;

    return fn(db);
  });
}

/**
 * Runs `fn` over direct Postgres as the user that `claims` describe, inside one
 * transaction that always rolls back. The transaction sets `role` (from
 * `claims.role`, else `authenticated`) and `request.jwt.claims`, so
 * `auth.uid()`, `auth.jwt()` and RLS answer as they would for that user's
 * request. Use it for raw SQL; `withRollback` gives repositories instead.
 *
 * ```ts
 * await withClaims(
 *   postgres,
 *   { sub: aliceId, tenant_id: orgId },
 *   async (sql) => {
 *     const [row] = await sql.queryRaw<{ id: string }>(
 *       "select auth.uid() as id",
 *     );
 *     expect(row?.id).toBe(aliceId);
 *   },
 * );
 * ```
 */
export function withClaims<T>(
  postgres: BetterPostgres,
  claims: SqlClaims,
  fn: (sql: SqlClient) => Promise<T>,
): Promise<T> {
  return rolledBack(postgres, claims, fn);
}

async function rolledBack<T>(
  postgres: BetterPostgres,
  claims: SqlClaims,
  fn: (client: SqlClient) => Promise<T>,
): Promise<T> {
  let outcome: { readonly value: T } | undefined;

  try {
    await postgres.transaction(
      async (client) => {
        outcome = { value: await fn(client) };

        throw new Rollback("rollback");
      },
      { claims },
    );
  } catch (error) {
    if (!(error instanceof Rollback) || !outcome) {
      throw error;
    }
  }

  return outcome!.value;
}
