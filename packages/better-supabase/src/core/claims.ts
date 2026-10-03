import type { ClaimsMeta, SchemaMeta } from "../schema/types.ts";

export const DEFAULT_CLAIMS: ClaimsMeta = {
  tenant: "tenant_id",
  scope: "tenant",
  features: "features",
};

/** The configured claim names, with defaults for the ones codegen left out. */
export function claimsOf(
  meta: Pick<SchemaMeta, "claims"> | undefined,
): ClaimsMeta {
  if (!meta?.claims) return DEFAULT_CLAIMS;
  let claims = claimsByMeta.get(meta);
  if (!claims) {
    claims = { ...DEFAULT_CLAIMS, ...meta.claims };
    claimsByMeta.set(meta, claims);
  }
  return claims;
}

const claimsByMeta = new WeakMap<object, ClaimsMeta>();

/** Where the active tenant is read from: the top-level claim, then `app_metadata`. */
export function tenantClaimPaths(
  tenant: string = DEFAULT_CLAIMS.tenant,
): readonly [string, string] {
  let paths = tenantPaths.get(tenant);
  if (!paths) {
    paths = [tenant, `app_metadata.${tenant}`];
    tenantPaths.set(tenant, paths);
  }
  return paths;
}

const tenantPaths = new Map<string, readonly [string, string]>();
/** Claim paths come from configuration, so this stays small. */
const segmentsByPath = new Map<string, readonly string[]>();

function segmentsOf(path: string): readonly string[] {
  let segments = segmentsByPath.get(path);
  if (!segments) {
    segments = path.split(".");
    if (segmentsByPath.size < 256) segmentsByPath.set(path, segments);
  }
  return segments;
}

/** The string at a dotted claim path, if any. */
export function claimAt(
  claims: Readonly<Record<string, unknown>> | undefined,
  path: string,
): string | undefined {
  let value: unknown = claims;
  for (const segment of segmentsOf(path)) {
    // SAFETY: the condition narrows value to a non-null object, and claims are JSON objects.
    value =
      typeof value === "object" && value !== null
        ? (value as Record<string, unknown>)[segment]
        : undefined;
  }
  return typeof value === "string" && value.length > 0 ? value : undefined;
}
