import { type DbError, dbError } from "../core/errors.ts";

/** A client that can read `auth.sessions`, such as `createPostgres().admin`. */
export interface SessionLookup {
  queryRaw<T = Record<string, unknown>>(
    text: string,
    params?: unknown[],
  ): Promise<T[]>;
}

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

const ACTIVE = `select exists (
  select 1 from auth.sessions s
  where s.id = $1::uuid and s.user_id = $2::uuid
    and (s.not_after is null or s.not_after > now())
) as active`;

/**
 * `undefined` when the user token's session still exists in `auth.sessions`;
 * otherwise an `unauthorized` error with code `SESSION_REVOKED`. A verified
 * access token stays valid until it expires, even after sign-out; call this
 * before sensitive actions (deleting the account, changing the email) to
 * reject tokens of ended sessions. It costs one query, so nothing calls it
 * by default. Non-user callers pass: `guard` decides about them.
 */
export async function checkSession(
  sql: SessionLookup,
  auth:
    | {
        readonly kind: "user";
        readonly claims: {
          readonly sub?: unknown;
          readonly session_id?: unknown;
        };
      }
    | { readonly kind: string },
): Promise<DbError | undefined> {
  if (auth.kind !== "user" || !("claims" in auth)) return undefined;
  const { sub, session_id: sessionId } = auth.claims;
  const revoked = dbError("unauthorized", "This session has ended", {
    code: "SESSION_REVOKED",
  });
  if (
    typeof sessionId !== "string" ||
    typeof sub !== "string" ||
    !UUID.test(sessionId) ||
    !UUID.test(sub)
  )
    return revoked;
  const [row] = await sql.queryRaw<{ active: boolean }>(ACTIVE, [
    sessionId,
    sub,
  ]);
  return row?.active === true ? undefined : revoked;
}
