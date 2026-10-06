import type { SupabaseClient } from "@supabase/supabase-js";

import type { BetterSupabase } from "../core/define.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { Bucket } from "../storage/index.ts";

import { type DbError, dbError, isDbError } from "../core/errors.ts";
import { AsyncResult, err, ok } from "../core/result.ts";

export interface DeleteAccountOptions {
  /**
   * Buckets to clear first. Objects whose `owner` placeholder (`{userId}`,
   * or `owner.param` for `owner` buckets) is the user are removed; buckets
   * without one are skipped.
   */
  readonly buckets?: readonly Bucket<string>[];
  /**
   * App keys of tables whose rows the database deletes or updates with the
   * user (`on delete cascade` or `set null` to `auth.users`). They get a
   * table-wide `mutation` notice, so caches drop their reads.
   */
  readonly cascades?: readonly string[];
  readonly context?: RequestContext;
  readonly signal?: AbortSignal;
}

export interface DeleteAccountResult {
  readonly userId: string;
  /** Removed objects per bucket id. */
  readonly removed: Readonly<Record<string, number>>;
}

const REMOVE_BATCH = 1000;

interface AuthFailure {
  readonly message?: string;
  readonly name?: string;
  readonly status?: number;
  readonly code?: string;
}

/** Maps an `AuthApiError` from `auth.admin.deleteUser` to a `DbError`. */
function fromAuthError(raw: unknown): DbError {
  if (isDbError(raw)) return raw;
  // SAFETY: every AuthFailure field is optional and read with a fallback, so
  // any object fits.
  const failure = (
    typeof raw === "object" && raw !== null ? raw : {}
  ) as AuthFailure;
  const message = failure.message ?? "Auth request failed";
  const base = {
    table: "auth.users",
    ...(failure.code ? { code: failure.code } : {}),
  };
  if (failure.code === "user_not_found" || failure.status === 404)
    return dbError("not_found", message, base);
  if (/database error deleting user/i.test(message)) {
    return dbError("conflict", message, {
      ...base,
      hint: "A foreign key to auth.users without on delete cascade or set null blocks the delete (doctor BS406)",
    });
  }
  if (failure.status === 401) return dbError("unauthorized", message, base);
  if (failure.status === 403) return dbError("forbidden", message, base);
  return failure.name === "AuthRetryableFetchError" ||
    (failure.status ?? 0) >= 500
    ? dbError("network", message, base)
    : dbError("unexpected", message, base);
}

/**
 * Removes a user's Storage objects, then the Auth user, then announces the
 * delete. Rows referencing `auth.users` follow their foreign keys.
 *
 * `server.deleteAccount` calls it with the server's service client. Apps on
 * the `@supabase/server` pipeline call it with theirs:
 * `deleteAccount(betterSupabase, ctx.supabaseAdmin, userId)`.
 */
export function deleteAccount<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C>,
  service: SupabaseClient | (() => SupabaseClient),
  userId: string,
  options: DeleteAccountOptions = {},
): AsyncResult<DeleteAccountResult> {
  return AsyncResult.from(async () => {
    const client = typeof service === "function" ? service() : service;
    const removed: Record<string, number> = {};
    for (const bucket of options.buckets ?? []) {
      const param = bucket.owner;
      if (!param) continue;
      options.signal?.throwIfAborted();
      // A user's objects can sit under every tenant they belonged to.
      const storage = bucket.connect(client, { allTenants: true });
      const listed = await storage.list(
        { [param]: userId },
        options.signal ? { signal: options.signal } : {},
      );
      if (!listed.ok) return listed;
      const paths = listed.data
        .map((object) => object.path)
        .filter((path) => {
          // SAFETY: the bucket's path template returns its named parameters, or
          // null when the path does not match.
          const values = bucket.match(path) as Record<string, unknown> | null;
          return values?.[param] === userId;
        });
      for (let start = 0; start < paths.length; start += REMOVE_BATCH) {
        const batch = await storage.remove(
          paths.slice(start, start + REMOVE_BATCH),
        );
        if (!batch.ok) return batch;
      }
      removed[bucket.id] = paths.length;
    }

    options.signal?.throwIfAborted();
    try {
      const { error } = await client.auth.admin.deleteUser(userId);
      if (error) return err(fromAuthError(error));
    } catch (cause) {
      return err(fromAuthError(cause));
    }

    const context = options.context ?? {};
    betterSupabase.events.emit("mutation", {
      table: "auth.users",
      kind: "delete",
      rows: [{ id: userId }],
      context,
    });
    for (const table of options.cascades ?? [])
      betterSupabase.events.emit("mutation", {
        table,
        kind: "delete",
        rows: [],
        context,
      });
    return ok({ userId, removed });
  });
}
