import { Pool } from "pg";

import type { Executor } from "../core/executor.ts";

import { postgresExecutor, type SqlClient } from "./executor.ts";

/** The part of a `pg` pool client `createPostgres` uses. */
export interface PgPoolClient {
  query(text: string, values?: unknown[]): Promise<{ rows: unknown[] }>;
  release(): void;
}

/** The part of a `pg.Pool` `createPostgres` uses. */
export interface PgPool {
  connect(): Promise<PgPoolClient>;
  end(): Promise<void>;
}

/** Statement timeouts in milliseconds by the role a transaction runs as. */
export interface PostgresTimeouts {
  /** The connection-string role (`admin` and `transaction` without claims). Unset by default. */
  readonly admin?: number;
  /** Defaults to 8000, Supabase's setting for the role. */
  readonly authenticated?: number;
  /** Defaults to 3000, Supabase's setting for the role. */
  readonly anon?: number;
}

export interface PostgresOptions {
  /** Defaults to `$SUPABASE_DB_URL`, then `$DATABASE_URL`. */
  readonly connectionString?: string;
  /** An existing pool to run on instead of opening one. `end()` ends it. */
  readonly pool?: PgPool;
  readonly max?: number;
  /**
   * Statement timeout in milliseconds, applied per transaction: one value
   * for every role, or one per role. `set role` doesn't apply the role's own
   * `statement_timeout`, so `authenticated` and `anon` get Supabase's 8 s
   * and 3 s unless you set them.
   */
  readonly statementTimeout?: number | PostgresTimeouts;
  /** Ends a session that stays idle inside a transaction this long, in milliseconds. */
  readonly idleInTransactionTimeout?: number;
  /** How long `connect` waits for a connection, in milliseconds. Defaults to 10000. */
  readonly connectionTimeout?: number;
  /** How long an unused connection stays open, in milliseconds. Defaults to 10000. */
  readonly idleTimeout?: number;
}

const DEFAULT_TIMEOUTS: PostgresTimeouts = {
  authenticated: 8000,
  anon: 3000,
};

/** JWT claims to run as. `role` must be `authenticated` or `anon`. */
export interface SqlClaims {
  readonly sub?: string;
  readonly role?: string;
  readonly [claim: string]: unknown;
}

export interface BetterPostgres {
  /** Connects as the connection-string role. On Supabase that bypasses RLS. */
  readonly admin: SqlClient;
  /** Runs every query as the given user, with RLS, like PostgREST does. */
  asUser(claims: SqlClaims): SqlClient;
  /** Runs every query as `anon`. */
  readonly anon: SqlClient;
  /**
   * Repositories' executor as the given user (`postgresExecutor(asUser(claims))`).
   * `createServer` calls it for `ctx.sql`, so only apps that pass `postgres`
   * bundle the SQL compiler.
   */
  executorFor(claims: SqlClaims): Executor;
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

function openPool(options: PostgresOptions): PgPool {
  const connectionString =
    options.connectionString ??
    process.env["SUPABASE_DB_URL"] ??
    process.env["DATABASE_URL"];
  if (!connectionString) {
    throw new TypeError(
      "createPostgres needs a connectionString, $SUPABASE_DB_URL or $DATABASE_URL",
    );
  }
  return new Pool({
    connectionString,
    max: options.max ?? 10,
    connectionTimeoutMillis: options.connectionTimeout ?? 10_000,
    idleTimeoutMillis: options.idleTimeout ?? 10_000,
  });
}

type Session =
  | { readonly claims: SqlClaims; readonly role: string }
  | undefined;

/**
 * A pooled Postgres connection for jobs, scripts and tests. Each query (or
 * transaction) runs in its own transaction; claims and role are
 * transaction-local, so nothing leaks back into the pool.
 */
export function createPostgres(options: PostgresOptions = {}): BetterPostgres {
  const pool = options.pool ?? openPool(options);
  const timeouts: PostgresTimeouts =
    typeof options.statementTimeout === "number"
      ? {
          admin: options.statementTimeout,
          authenticated: options.statementTimeout,
          anon: options.statementTimeout,
        }
      : { ...DEFAULT_TIMEOUTS, ...options.statementTimeout };

  /** Opens the transaction, then sets the timeouts, claims and role in one round trip. */
  async function begin(client: PgPoolClient, session: Session): Promise<void> {
    await client.query("begin");
    const settings: [string, string][] = [];
    const timeout =
      session?.role === "authenticated"
        ? timeouts.authenticated
        : session?.role === "anon"
          ? timeouts.anon
          : timeouts.admin;
    if (timeout !== undefined)
      settings.push(["statement_timeout", String(Math.trunc(timeout))]);
    if (options.idleInTransactionTimeout !== undefined)
      settings.push([
        "idle_in_transaction_session_timeout",
        String(Math.trunc(options.idleInTransactionTimeout)),
      ]);
    if (session) {
      settings.push(
        [
          "request.jwt.claims",
          JSON.stringify({ ...session.claims, role: session.role }),
        ],
        ["role", session.role],
      );
    }
    if (settings.length === 0) return;
    await client.query(
      `select ${settings.map((_, index) => `set_config($${index * 2 + 1}, $${index * 2 + 2}, true)`).join(", ")}`,
      settings.flat(),
    );
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
    executorFor: (claims) => postgresExecutor(clientFor(sessionFor(claims))),
    transaction: (fn, txOptions) =>
      transaction(
        txOptions?.claims ? sessionFor(txOptions.claims) : undefined,
        fn,
      ),
    end: () => pool.end(),
    [Symbol.asyncDispose]: () => pool.end(),
  };
}
