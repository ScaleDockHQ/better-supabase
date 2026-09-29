import type { AuthSession } from './view.ts';

/**
 * Entitlement keys of the `memberships[].entitlements` claim: the literal
 * union when `sb.claims(schema)` declares one (`z.enum([...])`), otherwise
 * `string`.
 */
export type EntitlementKey<C> = C extends {
  readonly memberships?: readonly (infer M)[] | undefined;
}
  ? M extends { readonly entitlements?: readonly (infer K)[] | undefined }
    ? K extends string
      ? K
      : string
    : string
  : string;

interface MembershipClaim {
  readonly tenant_id?: unknown;
  readonly entitlements?: unknown;
}

/**
 * Whether the session's `memberships` claim grants `key` in `tenantId`. The
 * claim is as fresh as the token: enforce it in RLS with
 * `better_supabase.has_entitlement()`, and refresh the session after checkout.
 */
export function hasEntitlement<C>(
  session: AuthSession<C>,
  tenantId: string,
  key: EntitlementKey<C>,
): boolean {
  if (session.kind !== 'user') return false;
  const memberships = (session.claims as { memberships?: unknown }).memberships;
  if (!Array.isArray(memberships)) return false;
  return memberships.some((entry: MembershipClaim) => {
    if (entry?.tenant_id !== tenantId) return false;
    return (
      Array.isArray(entry.entitlements) && entry.entitlements.includes(key)
    );
  });
}
