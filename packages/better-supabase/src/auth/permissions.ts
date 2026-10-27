import type { ClaimsRecord, ClaimsSource } from "./claims-source.ts";

import { DEFAULT_CLAIMS, truncatedMarker } from "../core/claims.ts";
import { claimsFrom } from "./claims-source.ts";
import { tenantOf } from "./tenant.ts";

export interface PermissionsOfOptions {
  /**
   * The claim holding `{ [tenantId]: string[] }`, as
   * `config.claims.permissions`. Defaults to `permissions`.
   */
  readonly claim?: string;
  /**
   * The claim the hook sets to `true` when it left keys out: the provider's
   * `tokenHook.truncatedClaim`. Defaults to `<claim>_truncated`.
   */
  readonly truncatedClaim?: string;
  /**
   * The active tenant claim, as `config.claims.tenant`, when `tenant` is left
   * out.
   */
  readonly tenantClaim?: string;
}

/**
 * The permission keys the token grants in `tenant` (the active tenant by
 * default), from the `permissions` claim `permission_claims()` writes. Takes a
 * server session, the client's `useAuth()` snapshot or verified claims.
 *
 * `undefined` means the token can't answer: no claim, no entry for the tenant,
 * or the hook set the truncated marker because the keys didn't fit. Ask the
 * database then (`my_permissions`). An empty list means the token says the
 * caller holds no permission there. The claim is a cache the `authz_ver` bump
 * invalidates; RLS stays the authority.
 *
 * ```ts
 * const keys = permissionsOf(await bsb.claims());
 * if (keys !== undefined && !keys.includes("billing.manage")) forbidden();
 * ```
 */
export function permissionsOf<C, P>(
  session: ClaimsSource<C, P>,
  tenant?: string,
  options: PermissionsOfOptions = {},
): readonly string[] | undefined {
  const claims = claimsFrom(session);

  if (claims === undefined) {
    return undefined;
  }

  const id = tenant ?? tenantOf(claims, options.tenantClaim);

  return id === undefined
    ? undefined
    : keysFromClaims(
        claims,
        id,
        options.claim ?? DEFAULT_CLAIMS.permissions,
        options.truncatedClaim,
      );
}

/**
 * Whether the hook left entries out of `claim` to stay within its budget.
 * `marker` is the provider's `tokenHook.truncatedClaim`; without it the marker
 * is `<claim>_truncated`. A truncated claim can't answer "not granted".
 */
export function isTruncated(
  claims: ClaimsRecord,
  claim: string = DEFAULT_CLAIMS.permissions,
  options: { readonly marker?: string | undefined } = {},
): boolean {
  return claims[truncatedMarker(claim, options.marker)] === true;
}

/** The keys `claims` grants in `tenant`, or `undefined` when it can't say. */
export function keysFromClaims(
  claims: ClaimsRecord,
  tenant: string,
  claim: string,
  marker?: string,
): readonly string[] | undefined {
  if (isTruncated(claims, claim, { marker })) {
    return undefined;
  }

  const byTenant = claims[claim];

  if (!isRecord(byTenant)) {
    return undefined;
  }

  const keys = byTenant[tenant];

  return isKeyList(keys) ? keys : undefined;
}

function isKeyList(value: unknown): value is readonly string[] {
  return (
    Array.isArray(value) &&
    value.every((key: unknown) => typeof key === "string")
  );
}

function isRecord(value: unknown): value is ClaimsRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
