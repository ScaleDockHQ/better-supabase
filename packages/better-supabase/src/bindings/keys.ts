import type { Session } from "@supabase/supabase-js";

import type { AuthSnapshot } from "../client/index.ts";
import type { QuerySpec } from "../core/spec.ts";
import type { SchemaMeta } from "../schema/types.ts";

import { decodeJwtPayload } from "../core/base64.ts";
import { claimAt, claimsOf, tenantClaimPaths } from "../core/claims.ts";

/**
 * The session's user id. With `tokens-only` cookies and no stored user,
 * auth-js puts a placeholder in `session.user` whose getters throw, so the
 * id falls back to the token's `sub`.
 */
export function sessionUserId(session: Session): string | null {
  try {
    if (typeof session.user.id === "string") return session.user.id;
  } catch {
    // the tokens-only placeholder
  }
  const sub = decodeJwtPayload(session.access_token)?.["sub"];
  return typeof sub === "string" ? sub : null;
}

/** The tenant claim `config.claims.tenant` names, for a signed-in caller. */
export function claimedTenant(
  auth: AuthSnapshot,
  meta: SchemaMeta,
): string | undefined {
  if (auth.status !== "signed-in") return undefined;
  for (const path of tenantClaimPaths(claimsOf(meta).tenant)) {
    const value = claimAt(auth.claims, path);
    if (value !== undefined) return value;
  }
  return undefined;
}

const specKeys = new WeakMap<QuerySpec, string>();

/** Specs are immutable, so a memoized or module-level spec is serialized once. */
export function specKey(spec: QuerySpec): string {
  let key = specKeys.get(spec);
  if (key === undefined) {
    key = JSON.stringify(spec, (_key, value: unknown) =>
      typeof value === "bigint" ? { $bigint: value.toString() } : value,
    );
    specKeys.set(spec, key);
  }
  return key;
}
