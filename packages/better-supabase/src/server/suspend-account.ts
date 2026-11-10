import type { SupabaseClient } from "@supabase/supabase-js";

import type { BlockTransport } from "../core/block-transport.ts";
import type { DbError } from "../core/errors.ts";
import type { SqlClient } from "../postgres/executor.ts";

import { dbError, dbErrorOf, mapDbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import { temporal } from "../core/temporal-required.ts";
import { fromPgError } from "../postgres/pg-error.ts";
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
   * working against the Data API until it expires; set this to end the sessions
   * at once instead.
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

/**
 * What the account helpers call the database through: direct Postgres, or a
 * `BlockTransport` such as `rpcTransport(admin, { schema })` over the Data API.
 * The transport form needs the `sessions` SQL module.
 */
export type AccountTransport = SqlClient | BlockTransport;

const isTransport = (client: AccountTransport): client is BlockTransport =>
  "call" in client && typeof client.call === "function";

/** The schema `better_supabase.end_sessions` lives in, for a transport call. */
const SESSIONS_SCHEMA = "better_supabase";

function invalidUser(userId: string): DbError {
  return dbError("invalid_request", `"${userId}" is not a user id`, {
    table: "auth.users",
  });
}

function fromSqlError(cause: unknown): DbError {
  const known = dbErrorOf(cause);

  if (known) {
    return known;
  }

  const raw = fromPgError(cause);

  if (raw) {
    return { ...mapDbError(raw), table: "auth.sessions" };
  }

  return dbError(
    "unexpected",
    cause instanceof Error ? cause.message : "Ending the sessions failed",
    { table: "auth.sessions" },
  );
}

async function deleteSessions(
  client: AccountTransport,
  userId: string,
): Promise<number> {
  if (isTransport(client)) {
    const value = await client.call(SESSIONS_SCHEMA, "end_sessions", {
      p_user: userId,
    });

    return typeof value === "number" ? value : 0;
  }

  const [row] = await client.queryRaw<{ ended: number }>(END_SESSIONS, [
    userId,
  ]);

  return row?.ended ?? 0;
}

/**
 * Deletes a user's sessions and refresh tokens. Pass `postgres.admin` (raw SQL,
 * no module needed) or a service-role `BlockTransport` (the `sessions` module's
 * `end_sessions`).
 */
export function endSessions(
  sql: AccountTransport,
  userId: string,
): AsyncResult<EndSessionsResult> {
  return AsyncResult.from(async () => {
    if (!UUID.test(userId)) {
      return err(invalidUser(userId));
    }

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

interface LastSignInRow {
  readonly user_id: string;
  readonly last_sign_in_at: Date | string | null;
}

const isRow = (value: unknown): value is LastSignInRow =>
  isRecord(value) && typeof value["user_id"] === "string";

async function lastSignInRows(
  client: AccountTransport,
  userIds: readonly string[],
): Promise<readonly LastSignInRow[]> {
  if (isTransport(client)) {
    // The Data API answers a table function with an array of rows.
    const value = await client.call(SESSIONS_SCHEMA, "last_sign_ins", {
      p_users: userIds,
    });

    return Array.isArray(value) ? value.filter(isRow) : [];
  }

  return client.queryRaw<LastSignInRow>(LAST_SIGN_INS, [userIds]);
}

/**
 * The last sign-in of each user, in one query (`better_supabase.last_sign_ins`
 * from the `sessions` module, which only the service role may call). Users that
 * don't exist are missing from the map.
 */
export function lastSignIns(
  sql: AccountTransport,
  userIds: readonly string[],
): AsyncResult<ReadonlyMap<string, LastSignIn>> {
  return AsyncResult.from(async () => {
    const invalid = userIds.find((userId) => !UUID.test(userId));

    if (invalid !== undefined) {
      return err(invalidUser(invalid));
    }

    if (userIds.length === 0) {
      return ok(new Map<string, LastSignIn>());
    }

    try {
      const rows = await lastSignInRows(sql, [...new Set(userIds)]);

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
  sql: AccountTransport,
  userId: string,
  options: SuspendAccountOptions,
): AsyncResult<SuspendAccountResult> {
  return AsyncResult.from(async () => {
    if (!UUID.test(userId)) {
      return err(invalidUser(userId));
    }

    const client = typeof service === "function" ? service() : service;
    const { suspended } = options;

    if (suspended) {
      const refused = await ban(client, userId, options.duration ?? FOREVER);

      if (refused) {
        return err(refused);
      }

      if (options.endSessions !== true) {
        return ok({ userId, suspended, ended: 0 });
      }
    }

    let ended: number;

    try {
      ended = await deleteSessions(sql, userId);
    } catch (cause) {
      return err(fromSqlError(cause));
    }

    if (!suspended) {
      const refused = await ban(client, userId, "none");

      if (refused) {
        return err(refused);
      }
    }

    return ok({ userId, suspended, ended });
  });
}
