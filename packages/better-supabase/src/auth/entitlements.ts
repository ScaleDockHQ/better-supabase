import type { AuthSession } from "./view.ts";

/**
 * One entry of the `memberships` claim when a hook writes it as a list.
 * Hooks strip `null`s, so optional fields are absent rather than `null`.
 */
export interface MembershipClaim {
  /** The scope the membership is in, e.g. `tenant` or `organization`. */
  readonly scope: string;
  readonly id: string;
  /** Parent scopes, e.g. `{ organization: '...' }` for a project membership. */
  readonly within?: Readonly<Record<string, string>>;
  readonly roles: readonly string[];
  readonly via?: string;
  /** Unix seconds. */
  readonly expiresAt?: number;
  readonly grantedBy?: string;
  readonly reason?: string;
  readonly member?: { readonly group: string };
  readonly managedBy?: "idp";
  /** Seats, not plan features: those are in the `features` claim. */
  readonly entitlements?: readonly string[];
}

/**
 * Entitlement keys of the `features` claim: the literal union when
 * `betterSupabase.claims(schema)` declares one (`z.enum([...])`), otherwise `string`.
 */
export type EntitlementKey<C> = C extends {
  readonly features?: infer F;
}
  ? NonNullable<F> extends Readonly<Record<string, readonly (infer K)[]>>
    ? K extends string
      ? K
      : string
    : string
  : string;

/** Where `hasEntitlement` reads the features claim, and its short codes. */
export interface EntitlementClaimOptions {
  /** `config.claims.features`, default `features`. */
  readonly claim?: string;
  /** `entitlements.claim.keys`: the short code written for each feature key. */
  readonly keys?: Readonly<Record<string, string>>;
}

/**
 * Whether the session's plan-features claim grants `key` in `tenantId`.
 * `claim` is `config.claims.features` (default `features`), the claim
 * `better_supabase.feature_claims()` fills, or `{ claim, keys }` when
 * `entitlements.claim.keys` writes short codes. The claim is as fresh as the
 * token: enforce it in RLS with `better_supabase.has_entitlement()`, and
 * refresh the session after checkout. A tenant left out by
 * `entitlements.claim.maxTenants` reads as not granted.
 */
export function hasEntitlement<C>(
  session: AuthSession<C>,
  tenantId: string,
  key: EntitlementKey<C>,
  claim: string | EntitlementClaimOptions = "features",
): boolean {
  if (session.kind !== "user") return false;
  const options = typeof claim === "string" ? { claim } : claim;
  const claims: unknown = session.claims;
  if (!isRecord(claims)) return false;
  const features = claims[options.claim ?? "features"];
  if (!isRecord(features) || !Object.hasOwn(features, tenantId)) return false;
  const keys = features[tenantId];
  const code = options.keys?.[key] ?? key;
  return Array.isArray(keys) && keys.includes(code);
}

const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null;
