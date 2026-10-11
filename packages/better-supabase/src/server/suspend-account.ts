import type { SupabaseClient } from "@supabase/supabase-js";

import type { SqlClient } from "../postgres/executor.ts";

import {
  type DbError,
  dbError,
  dbErrorOf,
  mapDbError,
} from "../core/errors.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import { temporal } from "../core/temporal-required.ts";
import { fromPgError } from "../postgres/executor.ts";
import { fromAuthError } from "./delete-account.ts";

export interface EndSessionsResult {
  readonly userId: string;
  readonly ended: number;
}

export interface SuspendAccountOptions {
  readonly suspended: boolean;
  /** A Go duration for the ban, such as `"24h"`. Defaults to 100 years. */
  readonly duration?: string;
  /**
   * Also end the sessions when suspending. Defaults to `false`: the sessions
   * stay, so Auth answers refresh and `/user` with `user_banned` and the app
   * can show why. Without the `sessions` SQL module, an access token keeps
   * working against the Data API until it expires; set this to end the
   * sessions at once instead.
   */
  readonly endSessions?: boolean;
}

export interface SuspendAccountResult {
  readonly userId: string;
  readonly suspended: boolean;
  /**
   * The sessions deleted: `0` on a suspension (unless `endSessions` is set),
   * and the user's remaining sessions when the ban is lifted.
   */
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
  const known = dbErrorOf(cause);
  if (known) return known;
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

export interface LastSignIn {
  readonly userId: string;
  /** `null` for a user who never signed in. */
  readonly lastSignInAt: Temporal.Instant | null;
}

const LAST_SIGN_INS = `select user_id, last_sign_in_at
from better_supabase.last_sign_ins($1::uuid[])`;

/**
 * The last sign-in of each user, in one query (`better_supabase.last_sign_ins`
 * from the `sessions` module, which only the service role may call). Users
 * that don't exist are missing from the map.
 */
export function lastSignIns(
  sql: SqlClient,
  userIds: readonly string[],
): AsyncResult<ReadonlyMap<string, LastSignIn>> {
  return AsyncResult.from(async () => {
    const invalid = userIds.find((userId) => !UUID.test(userId));
    if (invalid !== undefined) return err(invalidUser(invalid));
    if (userIds.length === 0) return ok(new Map<string, LastSignIn>());
    try {
      const rows = await sql.queryRaw<{
        user_id: string;
        last_sign_in_at: Date | string | null;
      }>(LAST_SIGN_INS, [[...new Set(userIds)]]);
      return ok(
        new Map(
          rows.map((row): [string, LastSignIn] => [
            row.user_id,
            {
              userId: row.user_id,
              lastSignInAt:
                row.last_sign_in_at === null
                  ? null
                  : temporal().Instant.from(
                      row.last_sign_in_at instanceof Date
                        ? row.last_sign_in_at.toISOString()
                        : row.last_sign_in_at,
                    ),
            },
          ]),
        ),
      );
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
      if (options.endSessions !== true)
        return ok({ userId, suspended, ended: 0 });
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
