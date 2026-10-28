import type { ClaimsSource } from "./claims-source.ts";

import { claimAt, tenantClaimPaths } from "../core/claims.ts";
import { claimsFrom } from "./claims-source.ts";

/**
 * The active tenant of a user session: the `claim` claim (`tenant_id` by
 * default, as `config.claims.tenant`) at the top level of the token, then in
 * `app_metadata`. `undefined` for every other session. Takes a server session,
 * the client's `useAuth()` snapshot or verified claims.
 *
 * ```ts
 * const organizationId = tenantOf(await bsb.claims());
 * const organizationId = tenantOf(useAuth());
 * ```
 */
export function tenantOf<C, P>(
  session: ClaimsSource<C, P>,
  claim?: string,
): string | undefined {
  const claims = claimsFrom(session);

  if (claims === undefined) {
    return undefined;
  }

  for (const path of tenantClaimPaths(claim)) {
    const value = claimAt(claims, path);

    if (value !== undefined) {
      return value;
    }
  }

  return undefined;
}
