/**
 * The claim `forContext({ permissions })` sets: the permission keys the work
 * may use. `better_supabase.cap_allows` refuses every other key, and a job
 * queued under a cap keeps it.
 */
export const PERMISSION_CAP_CLAIM = "bsb_permission_cap";

/**
 * The authorization version an access token hook writes, so caches key on it. A
 * provider bumps it when a user's grants change.
 */
export const AUTHZ_VERSION_CLAIM = "authz_ver";

/** The caller's memberships, as a list of `{ scope, id, roles }`. */
export const MEMBERSHIPS_CLAIM = "memberships";

/** Plan features per tenant (`{ [tenantId]: string[] }`). */
export const FEATURES_CLAIM = "features";

/** Permission keys per tenant (`{ [tenantId]: string[] }`). */
export const PERMISSIONS_CLAIM = "permissions";

/**
 * Set to `true` when the hook left permission keys out of the `permissions`
 * claim. A provider that declares `tokenHook.truncatedClaim` uses its own.
 */
export const PERMISSIONS_TRUNCATED_CLAIM = "permissions_truncated";
