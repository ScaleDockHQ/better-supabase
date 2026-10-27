import type { AuthSnapshot } from "../client/bind.ts";
import type { AuthSession } from "./view.ts";

import { DEFAULT_CLAIMS } from "../core/claims.ts";
import { tenantOf } from "./tenant.ts";

export interface PermissionsOfOptions {
  /**
   * The claim holding `{ [tenantId]: string[] }`, as
   * `config.claims.permissions`. Defaults to `permissions`; the truncation
   * marker is `<claim>_truncated`.
   */
  readonly claim?: string;
  /**
   * The active tenant claim, as `config.claims.tenant`, when `tenant` is left
   * out.
   */
  readonly tenantClaim?: string;
}

/**
 * The permission keys the token grants in `tenant` (the active tenant by
 * default), from the `permissions` claim `permission_claims()` writes.
 *
 * `undefined` means the token can't answer: no claim, no entry for the tenant,
 * or the hook set `permissions_truncated` because the keys didn't fit. Ask the
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
  session: AuthSession<C, P> | AuthSnapshot,
  tenant?: string,
  options: PermissionsOfOptions = {},
): readonly string[] | undefined {
  const claims = claimsOf(session);

  if (claims === undefined) {
    return undefined;
  }

  const claim = options.claim ?? DEFAULT_CLAIMS.permissions;

  if (claims[`${claim}_truncated`] === true) {
    return undefined;
  }

  const id = tenant ?? tenantOf(session, options.tenantClaim);
  const byTenant = claims[claim];

  if (id === undefined || !isRecord(byTenant)) {
    return undefined;
  }

  const keys = byTenant[id];

  return isKeyList(keys) ? keys : undefined;
}

function isKeyList(value: unknown): value is readonly string[] {
  return (
    Array.isArray(value) &&
    value.every((key: unknown) => typeof key === "string")
  );
}

function claimsOf<C, P>(
  session: AuthSession<C, P> | AuthSnapshot,
): Readonly<Record<string, unknown>> | undefined {
  if ("kind" in session) {
    return session.kind === "user" ? session.claims : undefined;
  }

  return session.status === "signed-in" ? session.claims : undefined;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
