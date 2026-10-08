import type { SupabaseClient } from "@supabase/supabase-js";

import type { SqlClient } from "../postgres/executor.ts";

import {
  type DbError,
  dbError,
  isDbError,
  mapDbError,
} from "../core/errors.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import { fromPgError } from "../postgres/executor.ts";
import { fromAuthError } from "./delete-account.ts";

export interface EndSessionsResult {
  readonly userId: string;
  readonly ended: number;
}

export interface SuspendAccountOptions {
  readonly suspended: boolean;
  readonly duration?: string;
}

export interface SuspendAccountResult {
  readonly userId: string;
  readonly suspended: boolean;
  readonly ended: number;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FOREVER = "876000h";

const END_SESSIONS = `with ended as (
  delete from auth.sessions where user_id = $1::uuid returning id
), tokens as (
  delete from auth.refresh_tokens where user_id = $1::text
)
select count(*)::int as ended from ended`;

function invalidUser(userId: string): DbError {
  return dbError("invalid_request", `"${userId}" is not a user id`, {
    table: "auth.users",
  });
}

function fromSqlError(cause: unknown): DbError {
  if (isDbError(cause)) return cause;
  const raw = fromPgError(cause);
  if (raw) return { ...mapDbError(raw), table: "auth.sessions" };
  return dbError(
    "unexpected",
    cause instanceof Error ? cause.message : "Ending the sessions failed",
    { table: "auth.sessions" },
  );
}

async function deleteSessions(sql: SqlClient, userId: string): Promise<number> {
  const [row] = await sql.queryRaw<{ ended: number }>(END_SESSIONS, [userId]);
  return row?.ended ?? 0;
}

export function endSessions(
  sql: SqlClient,
  userId: string,
): AsyncResult<EndSessionsResult> {
  return AsyncResult.from(async () => {
    if (!UUID.test(userId)) return err(invalidUser(userId));
    try {
      return ok({ userId, ended: await deleteSessions(sql, userId) });
    } catch (cause) {
      return err(fromSqlError(cause));
    }
  });
}

async function ban(
  client: SupabaseClient,
  userId: string,
  duration: string,
): Promise<DbError | undefined> {
  try {
    const { error } = await client.auth.admin.updateUserById(userId, {
      ban_duration: duration,
    });
    return error ? fromAuthError(error) : undefined;
  } catch (cause) {
    return fromAuthError(cause);
  }
}

export function suspendAccount(
  service: SupabaseClient | (() => SupabaseClient),
  sql: SqlClient,
  userId: string,
  options: SuspendAccountOptions,
): AsyncResult<SuspendAccountResult> {
  return AsyncResult.from(async () => {
    if (!UUID.test(userId)) return err(invalidUser(userId));
    const client = typeof service === "function" ? service() : service;
    const { suspended } = options;
    if (suspended) {
      const refused = await ban(client, userId, options.duration ?? FOREVER);
      if (refused) return err(refused);
    }
    let ended: number;
    try {
      ended = await deleteSessions(sql, userId);
    } catch (cause) {
      return err(fromSqlError(cause));
    }
    if (!suspended) {
      const refused = await ban(client, userId, "none");
      if (refused) return err(refused);
    }
    return ok({ userId, suspended, ended });
  });
}
