import type { AuthSession } from "./view.ts";

import { claimAt, tenantClaimPaths } from "../core/claims.ts";

/**
 * The active tenant of a user session: the `claim` claim (`tenant_id` by
 * default, as `config.claims.tenant`) at the top level of the token, then in
 * `app_metadata`. `undefined` for every other session.
 *
 * ```ts
 * const organizationId = tenantOf(await bs.session());
 * ```
 */
export function tenantOf<C, P>(
  session: AuthSession<C, P>,
  claim?: string,
): string | undefined {
  if (session.kind !== "user") return undefined;
  for (const path of tenantClaimPaths(claim)) {
    const value = claimAt(session.claims, path);
    if (value !== undefined) return value;
  }
  return undefined;
}
