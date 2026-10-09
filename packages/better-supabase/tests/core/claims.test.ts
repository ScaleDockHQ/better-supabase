import { describe, expect, it } from "vitest";

import { claimPaths } from "../../src/config/index.ts";
import { DEFAULT_CLAIMS, claimsOf } from "../../src/core/claims.ts";

describe("claimsOf", () => {
  it("returns the defaults without configured claims", () => {
    expect(claimsOf(undefined)).toBe(DEFAULT_CLAIMS);
    expect(claimsOf({})).toBe(DEFAULT_CLAIMS);
  });

  it("merges the configured names once per schema", () => {
    const meta = { claims: { tenant: "org_id" } };
    const claims = claimsOf(meta);
    expect(claims).toEqual({ ...DEFAULT_CLAIMS, tenant: "org_id" });
    expect(claimsOf(meta)).toBe(claims);
  });
});

describe("claimPaths", () => {
  it("resolves every claim an adapter reads, with defaults", () => {
    expect(claimPaths()).toEqual({
      tenant: ["tenant_id", "app_metadata.tenant_id"],
      features: "features",
      memberships: "memberships",
      scope: "tenant",
    });
    expect(claimPaths({ tenant: "org_id", memberships: "orgs" })).toMatchObject(
      { tenant: ["org_id", "app_metadata.org_id"], memberships: "orgs" },
    );
  });
});
