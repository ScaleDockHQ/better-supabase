import { Pool } from "pg";

import type { EventHub } from "../core/events.ts";
import type { Executor } from "../core/executor.ts";
import type { Logger } from "../core/logger.ts";

import { postgresExecutor, type SqlClient } from "./executor.ts";
import { watchPoolErrors } from "./pool-errors.ts";

/** The part of a `pg` pool client `createPostgres` uses. */
export interface PgPoolClient {
  query(text: string, values?: unknown[]): Promise<{ rows: unknown[] }>;
  release(): void;
}

/** The part of a `pg.Pool` `createPostgres` uses. */
export interface PgPool {
  connect(): Promise<PgPoolClient>;
  end(): Promise<void>;
  /** `pg.Pool` reports errors of idle connections here. */
  on?(event: "error", listener: (error: Error) => void): unknown;
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
  /**
   * Defaults to `$SUPABASE_DB_URL`, `$DATABASE_URL`, `$POSTGRES_URL`, then
   * `$POSTGRES_URL_NON_POOLING`, the first one set.
   */
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
  /**
   * Ends a session that stays idle inside a transaction this long, in
   * milliseconds, so `transaction(fn)` can't hold a connection while `fn`
   * waits on something else. Defaults to 15000; `0` turns it off. Statements
   * outside a transaction don't set it.
   */
  readonly idleInTransactionTimeout?: number;
  /** How long `connect` waits for a connection, in milliseconds. Defaults to 10000. */
  readonly connectionTimeout?: number;
  /** How long an unused connection stays open, in milliseconds. Defaults to 10000. */
  readonly idleTimeout?: number;
  /**
   * `betterSupabase.events`: an error on an idle pooled connection arrives as
   * an `error` event instead of crashing the process.
   */
  readonly events?: EventHub;
  /** Where idle-connection errors go without `error` handlers. Defaults to the console. */
  readonly logger?: Logger;
}

/** Supabase sets no idle-in-transaction timeout; 15 s frees a stuck connection. */
const DEFAULT_IDLE_IN_TRANSACTION_TIMEOUT = 15_000;

const CONNECTION_VARIABLES = [
  "SUPABASE_DB_URL",
  "DATABASE_URL",
  "POSTGRES_URL",
  "POSTGRES_URL_NON_POOLING",
] as const;

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

/** What every transaction of a user session sets besides the claims and role. */
export interface SessionOptions {
  /**
   * Transaction-local settings, e.g. `{ 'better_supabase.tenant': id }`.
   * Names need a dot (custom settings); `role` and `request.jwt.claims` are
   * set from the claims.
   */
  readonly settings?: Readonly<Record<string, string>>;
  /** Runs every transaction with `begin read only`: writes fail with 25006. */
  readonly readOnly?: boolean;
  /**
   * Statement timeout in milliseconds for this session's transactions,
   * instead of the role's `statementTimeout` from `createPostgres`.
   */
  readonly statementTimeout?: number;
}

export interface BetterPostgres {
  /** Connects as the connection-string role. On Supabase that bypasses RLS. */
  readonly admin: SqlClient;
  /** Runs every query as the given user, with RLS, like PostgREST does. */
  asUser(claims: SqlClaims, options?: SessionOptions): SqlClient;
  /** Runs every query as `anon`. */
  readonly anon: SqlClient;
  /**
   * Repositories' executor as the given user (`postgresExecutor(asUser(claims))`).
   * `createServer` calls it for `ctx.sql`, so only apps that pass `postgres`
   * bundle the SQL compiler.
   */
  executorFor(claims: SqlClaims, options?: SessionOptions): Executor;
  /**
   * Runs `fn` in one transaction. Pass claims to run it as a user; the
   * session options apply with or without them.
   */
  transaction<T>(
    fn: (client: SqlClient) => Promise<T>,
    options?: { readonly claims?: SqlClaims } & SessionOptions,
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
    CONNECTION_VARIABLES.map((name) => process.env[name]).find(Boolean);

  if (!connectionString) {
    throw new TypeError(
      `createPostgres needs a connectionString or one of ${CONNECTION_VARIABLES.map((name) => `$${name}`).join(", ")}`,
    );
  }

  return new Pool({
    connectionString,
    max: options.max ?? 10,
    connectionTimeoutMillis: options.connectionTimeout ?? 10_000,
    idleTimeoutMillis: options.idleTimeout ?? 10_000,
  });
}

/** Claims and role are both set for a user session, and both unset for the connection role. */
interface Session extends SessionOptions {
  readonly claims?: SqlClaims;
  readonly role?: string;
}

const ADMIN: Session = {};

const RESERVED_SETTINGS = new Set(["role", "request.jwt.claims"]);

function checkSettings(settings: Readonly<Record<string, string>> = {}): void {
  for (const name of Object.keys(settings)) {
    if (!name.includes(".") || RESERVED_SETTINGS.has(name)) {
      throw new TypeError(
        `Session setting "${name}": use a custom setting with a dot, such as better_supabase.tenant`,
      );
    }
  }
}

/**
 * A pooled Postgres connection for jobs, scripts and tests. Each query (or
 * transaction) runs in its own transaction; claims and role are
 * transaction-local, so nothing leaks back into the pool. An `admin` query
 * with no timeout to set runs on its own, without `begin` and `commit`.
 */
export function createPostgres(options: PostgresOptions = {}): BetterPostgres {
  const pool = options.pool ?? openPool(options);

  watchPoolErrors(pool, {
    ...(options.events ? { events: options.events } : {}),
    ...(options.logger ? { logger: options.logger } : {}),
  });

  const idleInTransaction = Math.trunc(
    options.idleInTransactionTimeout ?? DEFAULT_IDLE_IN_TRANSACTION_TIMEOUT,
  );

  const timeouts: PostgresTimeouts =
    typeof options.statementTimeout === "number"
      ? {
          admin: options.statementTimeout,
          authenticated: options.statementTimeout,
          anon: options.statementTimeout,
        }
      : { ...DEFAULT_TIMEOUTS, ...options.statementTimeout };

  /** The transaction-local settings a session's transactions start with. */
  function settingsOf(session: Session): [string, string][] {
    const settings: [string, string][] = Object.entries(session.settings ?? {});

    const timeout =
      session.statementTimeout ??
      (session.role === "authenticated"
        ? timeouts.authenticated
        : session.role === "anon"
          ? timeouts.anon
          : timeouts.admin);

    if (timeout !== undefined) {
      settings.push(["statement_timeout", String(Math.trunc(timeout))]);
    }

    if (session.claims && session.role) {
      settings.push(
        [
          "request.jwt.claims",
          JSON.stringify({ ...session.claims, role: session.role }),
        ],
        ["role", session.role],
      );
    }

    return settings;
  }

  /** Opens the transaction, then sets the timeouts, claims and role in one round trip. */
  async function begin(
    client: PgPoolClient,
    session: Session,
    settings: readonly [string, string][],
  ): Promise<void> {
    await client.query(session.readOnly ? "begin read only" : "begin");

    const all: readonly (readonly [string, string])[] =
      idleInTransaction > 0
        ? [
            ...settings,
            ["idle_in_transaction_session_timeout", String(idleInTransaction)],
          ]
        : settings;

    if (all.length === 0) {
      return;
    }

    await client.query(
      `select ${all.map((_, index) => `set_config($${index * 2 + 1}, $${index * 2 + 2}, true)`).join(", ")}`,
      all.flat(),
    );
  }

  /** One statement on a pooled connection in autocommit, for sessions that set nothing. */
  async function single<R>(text: string, params?: unknown[]): Promise<R[]> {
    const client = await pool.connect();

    try {
      // SAFETY: each caller passes the row type that its SQL selects.
      return (await client.query(text, params)).rows as R[];
    } finally {
      client.release();
    }
  }

  async function transaction<T>(
    session: Session,
    fn: (client: SqlClient) => Promise<T>,
  ): Promise<T> {
    const client = await pool.connect();

    try {
      await begin(client, session, settingsOf(session));

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

  const clientFor = (session: Session): SqlClient => {
    const bare = !session.readOnly && settingsOf(session).length === 0;

    return {
      queryRaw: <R>(text: string, params?: unknown[]) =>
        bare
          ? single<R>(text, params)
          : transaction(session, (client) => client.queryRaw<R>(text, params)),
      transaction: (fn) => transaction(session, fn),
    };
  };

  const optionsOf = (sessionOptions: SessionOptions): SessionOptions => {
    checkSettings(sessionOptions.settings);

    return {
      ...(sessionOptions.settings ? { settings: sessionOptions.settings } : {}),
      ...(sessionOptions.readOnly ? { readOnly: true } : {}),
      ...(sessionOptions.statementTimeout === undefined
        ? {}
        : { statementTimeout: sessionOptions.statementTimeout }),
    };
  };

  const sessionFor = (
    claims: SqlClaims,
    sessionOptions: SessionOptions = {},
  ): Session => ({
    claims,
    role: roleOf(claims),
    ...optionsOf(sessionOptions),
  });

  return {
    admin: clientFor(ADMIN),
    anon: clientFor({ claims: { role: "anon" }, role: "anon" }),
    asUser: (claims, sessionOptions) =>
      clientFor(sessionFor(claims, sessionOptions)),
    executorFor: (claims, sessionOptions) =>
      postgresExecutor(clientFor(sessionFor(claims, sessionOptions))),
    transaction: (fn, txOptions = {}) =>
      transaction(
        txOptions.claims
          ? sessionFor(txOptions.claims, txOptions)
          : optionsOf(txOptions),
        fn,
      ),
    end: () => pool.end(),
    [Symbol.asyncDispose]: () => pool.end(),
  };
}
