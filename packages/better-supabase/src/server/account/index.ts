import type { AsyncResult } from "../../core/result.ts";
import type { AccountServer } from "../account-parts.ts";
import type {
  DeleteAccountOptions,
  DeleteAccountResult,
} from "../delete-account.ts";
import type {
  EndSessionsResult,
  LastSignIn,
  SuspendAccountOptions,
  SuspendAccountResult,
} from "../suspend-account.ts";

import { ACCOUNT_PARTS } from "../account-parts.ts";
import { deleteAccount as deleteUser } from "../delete-account.ts";
import {
  endSessions as endUserSessions,
  lastSignIns as lastUserSignIns,
  suspendAccount as suspendUser,
} from "../suspend-account.ts";

export type {
  DeleteAccountOptions,
  DeleteAccountResult,
} from "../delete-account.ts";

export type {
  EndSessionsResult,
  LastSignIn,
  SuspendAccountOptions,
  SuspendAccountResult,
} from "../suspend-account.ts";

/**
 * Deletes a user: the Auth user, then their objects in `buckets`, then a
 * `mutation` notice for `auth.users`. Needs the secret key. With `postgres`, a
 * delete the database refuses returns its own error and hint. Access tokens
 * already issued stay valid until they expire. On a `createNext` server it also
 * drops the user's cached reads and session memo.
 *
 * ```ts
 * import { deleteAccount } from "better-supabase/server/account";
 *
 * await deleteAccount(bsb, userId, { buckets: [avatars] });
 * ```
 */
export function deleteAccount(
  server: AccountServer,
  userId: string,
  options?: DeleteAccountOptions,
): AsyncResult<DeleteAccountResult> {
  const parts = server[ACCOUNT_PARTS];

  return deleteUser(parts.betterSupabase, parts.service, userId, {
    ...(parts.sql ? { sql: parts.sql } : {}),
    ...options,
  }).map((deleted) => {
    parts.audit.account("account.deleted", userId, {
      removed: deleted.removed,
    });
    parts.after?.(userId);

    return deleted;
  });
}

/**
 * Deletes the user's sessions. Without `postgres`, it calls `end_sessions` in
 * the sessions block's API schema as the service role.
 */
export function endSessions(
  server: AccountServer,
  userId: string,
): AsyncResult<EndSessionsResult> {
  const parts = server[ACCOUNT_PARTS];

  return endUserSessions(parts.transport(), userId).map((ended) => {
    parts.audit.account("account.sessions_ended", userId, {
      ended: ended.ended,
    });
    parts.after?.(userId);

    return ended;
  });
}

/**
 * The last sign-in of each user in one call (`better_supabase.last_sign_ins`
 * from the `sessions` module), over `postgres` or the service role's Data API.
 * Users that don't exist are missing from the map.
 */
export function lastSignIns(
  server: AccountServer,
  userIds: readonly string[],
): AsyncResult<ReadonlyMap<string, LastSignIn>> {
  return lastUserSignIns(server[ACCOUNT_PARTS].transport(), userIds);
}

/**
 * Bans the user in Auth and keeps their sessions, so Auth answers with
 * `user_banned` (`endSessions: true` deletes them too). Lifting the ban ends
 * the sessions first, so the user signs in again.
 */
export function suspendAccount(
  server: AccountServer,
  userId: string,
  options: SuspendAccountOptions,
): AsyncResult<SuspendAccountResult> {
  const parts = server[ACCOUNT_PARTS];

  return suspendUser(parts.service, parts.transport(), userId, options).map(
    (suspended) => {
      parts.audit.account(
        suspended.suspended ? "account.suspended" : "account.unsuspended",
        userId,
        {
          ended: suspended.ended,
          ...(options.duration === undefined
            ? {}
            : { duration: options.duration }),
        },
      );
      parts.after?.(userId);

      return suspended;
    },
  );
}
