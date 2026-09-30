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
  return { ...DEFAULT_CLAIMS, ...meta?.claims };
}

/** Where the active tenant is read from: the top-level claim, then `app_metadata`. */
export function tenantClaimPaths(
  tenant: string = DEFAULT_CLAIMS.tenant,
): readonly [string, string] {
  return [tenant, `app_metadata.${tenant}`];
}

/** The string at a dotted claim path, if any. */
export function claimAt(
  claims: Readonly<Record<string, unknown>> | undefined,
  path: string,
): string | undefined {
  let value: unknown = claims;
  for (const segment of path.split(".")) {
    // SAFETY: the condition narrows value to a non-null object, and claims are JSON objects.
    value =
      typeof value === "object" && value !== null
        ? (value as Record<string, unknown>)[segment]
        : undefined;
  }
  return typeof value === "string" && value.length > 0 ? value : undefined;
}
