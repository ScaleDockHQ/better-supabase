import type { AuthSnapshot } from "../client/bind.ts";
import type { AuthSession } from "./view.ts";

import { claimAt, tenantClaimPaths } from "../core/claims.ts";

/**
 * The active tenant of a user session: the `claim` claim (`tenant_id` by
 * default, as `config.claims.tenant`) at the top level of the token, then in
 * `app_metadata`. `undefined` for every other session. Takes a server
 * session or the client's `useAuth()` snapshot.
 *
 * ```ts
 * const organizationId = tenantOf(await bs.session());
 * const organizationId = tenantOf(useAuth());
 * ```
 */
export function tenantOf<C, P>(
  session: AuthSession<C, P> | AuthSnapshot,
  claim?: string,
): string | undefined {
  const claims = claimsOf(session);
  if (claims === undefined) return undefined;
  for (const path of tenantClaimPaths(claim)) {
    const value = claimAt(claims, path);
    if (value !== undefined) return value;
  }
  return undefined;
}

function claimsOf<C, P>(
  session: AuthSession<C, P> | AuthSnapshot,
): Readonly<Record<string, unknown>> | undefined {
  if ("kind" in session)
    return session.kind === "user" ? session.claims : undefined;
  return session.status === "signed-in" ? session.claims : undefined;
}
