import { Pool, type PoolClient } from "pg";

import type { SqlClient } from "./executor.ts";

export interface PostgresOptions {
  /** Defaults to `$SUPABASE_DB_URL`, then `$DATABASE_URL`. */
  readonly connectionString?: string;
  readonly max?: number;
  /** Statement timeout in milliseconds, applied per transaction. */
  readonly statementTimeout?: number;
}

/** JWT claims to run as. `role` must be `authenticated` or `anon`. */
export interface SqlClaims {
  readonly sub?: string;
  readonly role?: string;
  readonly [claim: string]: unknown;
}

export interface Postgres {
  /** Connects as the connection-string role. On Supabase that bypasses RLS. */
  readonly admin: SqlClient;
  /** Runs every query as the given user, with RLS, like PostgREST does. */
  asUser(claims: SqlClaims): SqlClient;
  /** Runs every query as `anon`. */
  readonly anon: SqlClient;
  /** Runs `fn` in one transaction. Pass claims to run it as a user. */
  transaction<T>(
    fn: (client: SqlClient) => Promise<T>,
    options?: { readonly claims?: SqlClaims },
  ): Promise<T>;
  end(): Promise<void>;
  [Symbol.asyncDispose](): Promise<void>;
}

const ROLES = new Set(["authenticated", "anon"]);

function roleOf(claims: SqlClaims): string {
  const role = claims.role ?? (claims.sub ? "authenticated" : "anon");
  if (!ROLES.has(role)) {
    throw new TypeError(
      `Cannot run as role "${role}": only "authenticated" and "anon" are assumed. Use postgres.admin for service work.`,
    );
  }
  return role;
}

type Session =
  | { readonly claims: SqlClaims; readonly role: string }
  | undefined;

/**
 * A pooled Postgres connection for jobs, scripts and tests. Each query (or
 * transaction) runs in its own transaction; claims and role are
 * transaction-local, so nothing leaks back into the pool.
 */
export function createPostgres(options: PostgresOptions = {}): Postgres {
  const connectionString =
    options.connectionString ??
    process.env["SUPABASE_DB_URL"] ??
    process.env["DATABASE_URL"];
  if (!connectionString) {
    throw new TypeError(
      "createPostgres needs a connectionString, $SUPABASE_DB_URL or $DATABASE_URL",
    );
  }
  const pool = new Pool({ connectionString, max: options.max ?? 10 });

  async function begin(client: PoolClient, session: Session): Promise<void> {
    await client.query("begin");
    if (options.statementTimeout !== undefined) {
      await client.query(
        `set local statement_timeout = ${Math.trunc(options.statementTimeout)}`,
      );
    }
    if (session) {
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({ ...session.claims, role: session.role }),
      ]);
      await client.query(`set local role ${session.role}`);
    }
  }

  async function transaction<T>(
    session: Session,
    fn: (client: SqlClient) => Promise<T>,
  ): Promise<T> {
    const client = await pool.connect();
    try {
      await begin(client, session);
      // SAFETY: each caller passes the row type that its SQL selects.
      const scoped: SqlClient = {
        queryRaw: async <R>(text: string, params?: unknown[]) =>
          (await client.query(text, params)).rows as R[],
        transaction: (inner) => inner(scoped),
      };
      const result = await fn(scoped);
      await client.query("commit");
      return result;
    } catch (cause) {
      await client.query("rollback").catch(() => undefined);
      throw cause;
    } finally {
      client.release();
    }
  }

  const clientFor = (session: Session): SqlClient => ({
    queryRaw: <R>(text: string, params?: unknown[]) =>
      transaction(session, (client) => client.queryRaw<R>(text, params)),
    transaction: (fn) => transaction(session, fn),
  });

  const sessionFor = (claims: SqlClaims): Session => ({
    claims,
    role: roleOf(claims),
  });

  return {
    admin: clientFor(undefined),
    anon: clientFor({ claims: { role: "anon" }, role: "anon" }),
    asUser: (claims) => clientFor(sessionFor(claims)),
    transaction: (fn, txOptions) =>
      transaction(
        txOptions?.claims ? sessionFor(txOptions.claims) : undefined,
        fn,
      ),
    end: () => pool.end(),
    [Symbol.asyncDispose]: () => pool.end(),
  };
}
