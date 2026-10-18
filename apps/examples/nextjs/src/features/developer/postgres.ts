import "server-only";
import type { AuthSession } from "better-supabase/next";

import {
  dbError,
  err,
  mapDbError,
  ok,
  type Result,
  toDbError,
} from "better-supabase";
import {
  type BetterPostgres,
  createPostgres,
  fromPgError,
  type SqlClaims,
} from "better-supabase/postgres";

let pool: BetterPostgres | undefined;

/**
 * A direct Postgres connection for module tables the Data API doesn't
 * expose (`better_supabase.*`, `pgmq.*`). It shares `WORKFLOW_POSTGRES_URL`
 * with the Workflow SDK; `null` when that is unset.
 */
export function postgres(): BetterPostgres | null {
  const connectionString = process.env["WORKFLOW_POSTGRES_URL"];

  if (!connectionString) {
    return null;
  }

  pool ??= createPostgres({ connectionString, max: 3 });

  return pool;
}

/** `postgres()`, or a `network` error that says which variable is missing. */
export function requirePostgres(): Result<BetterPostgres> {
  const connection = postgres();

  return connection
    ? ok(connection)
    : err(
        dbError("network", "Set WORKFLOW_POSTGRES_URL to reach the database"),
      );
}

/**
 * The session's verified claims, for `asUser`, so RLS sees what PostgREST
 * would. `null` for an API key or anonymous caller.
 */
export function userClaims(session: AuthSession): SqlClaims | null {
  return session.kind === "user" ? { ...session.claims } : null;
}

/** The connection and the caller's claims, or the error that stops a write. */
export function requireCaller(
  session: AuthSession,
): Result<{ connection: BetterPostgres; claims: SqlClaims }> {
  const connection = requirePostgres();

  if (!connection.ok) {
    return connection;
  }

  const claims = userClaims(session);

  return claims
    ? ok({ connection: connection.data, claims })
    : err(dbError("unauthorized", "Sign in to manage this"));
}

/** Runs raw SQL and maps a Postgres error to a `DbError` instead of throwing. */
export async function sqlResult<T>(run: () => Promise<T>): Promise<Result<T>> {
  try {
    return ok(await run());
  } catch (error) {
    const raw = fromPgError(error);

    return err(raw ? mapDbError(raw) : toDbError(error));
  }
}
